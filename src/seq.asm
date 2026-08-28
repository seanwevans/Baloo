; src/seq.asm -- seq(1): print a sequence of numbers.
; Usage: seq [-w] [-s SEP] [-f FORMAT] [FIRST [INCREMENT]] LAST
;
; Everything is fixed point. Each operand is parsed into a mantissa and a
; count of decimals (an e/E exponent just shifts that count), and the sequence
; is stepped as scaled integers, so "seq 3 .3 4" lands exactly on 3.9 instead
; of drifting the way binary floating point would.
;
; Two precisions matter. The working precision is the widest of the three
; operands and is what the loop counts in; the printed precision comes from
; FIRST and INCREMENT alone, which is why "seq -s, 1.0 2.00 4" prints two
; decimals and LAST does not get a say. Every value in the sequence is an
; exact multiple of the difference, so scaling down to print is exact.
;
; -w pads with zeros after the sign to the wider of the formatted FIRST and
; LAST. -f takes a printf conversion, which must be exactly one float
; conversion with no argument tricks -- "%*f", "%2$f" and "%1-f" are rejected
; the way seq rejects them.

    %include "include/sysdefs.inc"

    %define OUTCAP 65536
    %define OUTHIGH (OUTCAP - 512)
    %define FMTCAP 256
    %define NUMCAP 128

section .bss
    outbuf      resb OUTCAP
    numbuf      resb NUMCAP
    bodybuf     resb NUMCAP
    digbuf      resb NUMCAP
    tmpbuf      resb NUMCAP
    fmt_pre     resb FMTCAP
    fmt_post    resb FMTCAP
    ops         resq 4
    nops        resq 1
    outlen      resq 1
    pn_mant     resq 1
    pn_dec      resq 1
    f_mant      resq 1
    f_dec       resq 1
    i_mant      resq 1
    i_dec       resq 1
    l_mant      resq 1
    l_dec       resq 1
    workprec    resq 1
    outprec     resq 1
    scaledown   resq 1
    cur         resq 1
    step        resq 1
    limit       resq 1
    sepstr      resq 1
    seplen      resq 1
    fmtstr      resq 1
    padwidth    resq 1
    fmt_prelen  resq 1
    fmt_postlen resq 1
    sp_width    resq 1
    sp_prec     resq 1
    dig_len     resq 1
    body_len    resq 1
    opt_w       resb 1
    sp_minus    resb 1
    sp_plus     resb 1
    sp_space    resb 1
    sp_zero     resb 1
    sp_conv     resb 1

section .data
usage_msg   db "Usage: seq [-w] [-s SEP] [-f FORMAT] "
    db "[FIRST [INCREMENT]] LAST", 10
    usage_len   equ $ - usage_msg
zero_msg    db "seq: increment must not be zero", 10
    zero_len    equ $ - zero_msg
fmt_msg     db "seq: invalid format", 10
    fmt_len     equ $ - fmt_msg
    default_sep db WHITESPACE_NL
    newline     db WHITESPACE_NL
    flagchars   db "-+ #0'", 0
    convchars   db "aAeEfFgG", 0

section .text
global _start

_start:
    mov     qword [sepstr], default_sep
    mov     qword [seplen], 1
    mov     qword [sp_prec], -1

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    jle     ready
    mov     rdi, [r13]
    test    rdi, rdi
    jz      ready
    cmp     byte [rdi], '-'
    jne     .operand
    cmp     byte [rdi + 1], 0
    je      .operand
; "-5" and "-.5" are operands, not option bundles
    movzx   eax, byte [rdi + 1]
    cmp     al, '.'
    je      .operand
    cmp     al, '0'
    jb      .flags
    cmp     al, '9'
    jbe     .operand
.flags:
    lea     rsi, [rdi + 1]
.flag:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .next
    inc     rsi
    cmp     al, 'w'
    je      .f_w
    cmp     al, 's'
    je      .f_s
    cmp     al, 'f'
    je      .f_f
    jmp     usage
.f_w:
    mov     byte [opt_w], 1
    jmp     .flag
.f_s:
    call    opt_value
    mov     [sepstr], rdx
    mov     rdi, rdx
    call    strlen_z
    mov     [seplen], rax
    jmp     .next
.f_f:
    call    opt_value
    mov     [fmtstr], rdx
    jmp     .next
.operand:
    mov     rcx, [nops]
    cmp     rcx, 4
    jae     usage                       ;more operands than seq accepts
    mov     [ops + rcx * 8], rdi
    inc     rcx
    mov     [nops], rcx
.next:
    add     r13, 8
    dec     r12
    jmp     parse

; opt_value: the rest of this bundle is the value, or the next argument is.
opt_value:
    cmp     byte [rsi], 0
    je      .separate
    mov     rdx, rsi
    ret
.separate:
    add     r13, 8
    dec     r12
    mov     rdx, [r13]
    test    rdx, rdx
    jz      usage
    ret

usage:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, usage_msg
    mov     rdx, usage_len
    syscall
    exit    1

bad_format:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, fmt_msg
    mov     rdx, fmt_len
    syscall
    exit    1

bad_zero:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, zero_msg
    mov     rdx, zero_len
    syscall
    exit    1

ready:
    mov     rax, [fmtstr]
    test    rax, rax
    jz      .operands
    mov     rsi, rax
    call    parse_format
    test    al, al
    jz      bad_format
.operands:
    mov     rax, [nops]
    cmp     rax, 1
    jb      usage
    cmp     rax, 3
    ja      usage

    mov     qword [f_mant], 1           ;FIRST and INCREMENT default to 1
    mov     qword [f_dec], 0
    mov     qword [i_mant], 1
    mov     qword [i_dec], 0

    cmp     rax, 1
    je      .one
    cmp     rax, 2
    je      .two
; three operands: FIRST INCREMENT LAST
    mov     rsi, [ops]
    call    parse_num
    test    al, al
    jz      usage
    mov     rax, [pn_mant]
    mov     [f_mant], rax
    mov     rax, [pn_dec]
    mov     [f_dec], rax
    mov     rsi, [ops + 8]
    call    parse_num
    test    al, al
    jz      usage
    mov     rax, [pn_mant]
    mov     [i_mant], rax
    mov     rax, [pn_dec]
    mov     [i_dec], rax
    mov     rsi, [ops + 16]
    jmp     .last
.two:
    mov     rsi, [ops]
    call    parse_num
    test    al, al
    jz      usage
    mov     rax, [pn_mant]
    mov     [f_mant], rax
    mov     rax, [pn_dec]
    mov     [f_dec], rax
    mov     rsi, [ops + 8]
    jmp     .last
.one:
    mov     rsi, [ops]
.last:
    call    parse_num
    test    al, al
    jz      usage
    mov     rax, [pn_mant]
    mov     [l_mant], rax
    mov     rax, [pn_dec]
    mov     [l_dec], rax

; the loop counts at the widest precision; only FIRST and INCREMENT decide
; how many decimals get printed
    mov     rax, [f_dec]
    mov     rcx, [i_dec]
    cmp     rcx, rax
    jbe     .haveout
    mov     rax, rcx
.haveout:
    mov     [outprec], rax
    mov     rcx, [l_dec]
    cmp     rcx, rax
    jbe     .havework
    mov     rax, rcx
.havework:
    mov     [workprec], rax
    mov     rcx, rax
    sub     rcx, [outprec]
    mov     rax, 1
    call    pow10                       ;-> rax = 10^rcx
    mov     [scaledown], rax

    mov     rax, [f_mant]
    mov     rcx, [workprec]
    sub     rcx, [f_dec]
    call    scale_by
    mov     [cur], rax
    mov     rax, [i_mant]
    mov     rcx, [workprec]
    sub     rcx, [i_dec]
    call    scale_by
    mov     [step], rax
    mov     rax, [l_mant]
    mov     rcx, [workprec]
    sub     rcx, [l_dec]
    call    scale_by
    mov     [limit], rax

    cmp     qword [step], 0
    je      bad_zero

    cmp     byte [opt_w], 0
    je      run
    call    compute_width

; ---------------------------------------------------------------------------
; run: step the sequence, separating with -s and ending with a newline. An
; empty sequence prints nothing at all, not even that newline.
; ---------------------------------------------------------------------------
run:
    xor     r15, r15                    ;values emitted so far
.loop:
    mov     rax, [cur]
    cmp     qword [step], 0
    jl      .descending
    cmp     rax, [limit]
    jg      .done
    jmp     .emit
.descending:
    cmp     rax, [limit]
    jl      .done
.emit:
    test    r15, r15
    jz      .value
    mov     rsi, [sepstr]
    mov     rdx, [seplen]
    call    out_bytes
.value:
    mov     rax, [cur]
    call    emit_value
    inc     r15
    mov     rax, [cur]
    add     rax, [step]
    jo      .done                       ;the sequence ran out of range
    mov     [cur], rax
    jmp     .loop
.done:
    test    r15, r15
    jz      .flush
    mov     rsi, newline
    mov     rdx, 1
    call    out_bytes
.flush:
    call    out_flush
    exit    0

; ---------------------------------------------------------------------------
; emit_value: print the working-precision value in rax, either through the -f
; format or as a plain fixed-point number padded for -w.
; ---------------------------------------------------------------------------
emit_value:
    push    r15
    cqo
    idiv    qword [scaledown]           ;down to the printed precision
    mov     r15, rax
    cmp     qword [fmtstr], 0
    je      .plain
    mov     rax, r15
    call    render_format
    pop     r15
    ret
.plain:
    mov     rax, r15
    mov     rcx, [outprec]
    mov     rdi, numbuf
    call    format_fixed
    cmp     byte [opt_w], 0
    jne     .padded
    mov     rsi, numbuf
    mov     rdx, rax
    call    out_bytes
    pop     r15
    ret
.padded:
    mov     rdx, rax
    call    out_padded
    pop     r15
    ret

; out_padded: write numbuf (rdx bytes) zero-padded after any sign to padwidth.
out_padded:
    mov     rcx, [padwidth]
    sub     rcx, rdx
    jle     .plain
    mov     rsi, numbuf
    cmp     byte [rsi], '-'
    je      .sign
    cmp     byte [rsi], '+'
    jne     .zeros
.sign:
    push    rcx
    push    rdx
    mov     rdx, 1
    call    out_bytes
    pop     rdx
    pop     rcx
    dec     rdx
.zeros:
    push    rcx
    push    rdx
.zero:
    mov     al, '0'
    call    out_char
    dec     rcx
    jnz     .zero
    pop     rdx
    pop     rcx
    mov     rsi, numbuf
    mov     rcx, [padwidth]
    sub     rcx, rdx
    add     rsi, 1
    cmp     byte [numbuf], '-'
    je      .body
    cmp     byte [numbuf], '+'
    je      .body
    mov     rsi, numbuf
.body:
    call    out_bytes
    ret
.plain:
    mov     rsi, numbuf
    call    out_bytes
    ret

; compute_width: -w pads to the wider of the formatted FIRST and LAST.
compute_width:
    mov     rax, [cur]
    cqo
    idiv    qword [scaledown]
    mov     rcx, [outprec]
    mov     rdi, numbuf
    call    format_fixed
    mov     [padwidth], rax
    mov     rax, [limit]
    cqo
    idiv    qword [scaledown]
    mov     rcx, [outprec]
    mov     rdi, numbuf
    call    format_fixed
    cmp     rax, [padwidth]
    jbe     .out
    mov     [padwidth], rax
.out:
    ret

; ---------------------------------------------------------------------------
; parse_num: read a decimal operand at rsi into pn_mant and pn_dec. An e/E
; exponent shifts pn_dec rather than the mantissa, so "1.0e0" still counts as
; one decimal. al = 1 only when the whole operand was consumed.
; ---------------------------------------------------------------------------
parse_num:
    push    rbx
    push    rdi
    xor     r8, r8                      ;mantissa
    xor     r9, r9                      ;decimals
    xor     r10, r10                    ;negative
    xor     r11, r11                    ;digits seen
    mov     al, [rsi]
    cmp     al, '-'
    jne     .plus
    mov     r10, 1
    inc     rsi
    jmp     .integer
.plus:
    cmp     al, '+'
    jne     .integer
    inc     rsi
.integer:
    movzx   rcx, byte [rsi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .point
    imul    r8, r8, 10
    add     r8, rcx
    inc     r11
    inc     rsi
    jmp     .integer
.point:
    cmp     byte [rsi], '.'
    jne     .exponent
    inc     rsi
.fraction:
    movzx   rcx, byte [rsi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .exponent
    imul    r8, r8, 10
    add     r8, rcx
    inc     r9
    inc     r11
    inc     rsi
    jmp     .fraction
.exponent:
    test    r11, r11
    jz      .bad                        ;no digits at all
    movzx   eax, byte [rsi]
    cmp     al, 'e'
    je      .expsign
    cmp     al, 'E'
    jne     .end
.expsign:
    inc     rsi
    xor     rcx, rcx                    ;exponent value
    xor     rdi, rdi                    ;exponent negative
    mov     al, [rsi]
    cmp     al, '-'
    jne     .expplus
    mov     rdi, 1
    inc     rsi
    jmp     .expdigits
.expplus:
    cmp     al, '+'
    jne     .expdigits
    inc     rsi
.expdigits:
    xor     rbx, rbx
.expdigit:
    movzx   rax, byte [rsi]
    sub     al, '0'
    cmp     al, 9
    ja      .expdone
    imul    rcx, rcx, 10
    add     rcx, rax
    inc     rbx
    inc     rsi
    jmp     .expdigit
.expdone:
    test    rbx, rbx
    jz      .bad
    test    rdi, rdi
    jz      .exppos
    add     r9, rcx
    jmp     .end
.exppos:
    sub     r9, rcx
.end:
    cmp     byte [rsi], 0
    jne     .bad                        ;trailing junk, as in "1f"
.normalize:
    cmp     r9, 0
    jge     .sign
    imul    r8, r8, 10                  ;a positive exponent folds into the
    inc     r9                          ;mantissa instead
    jmp     .normalize
.sign:
    test    r10, r10
    jz      .store
    neg     r8
.store:
    mov     [pn_mant], r8
    mov     [pn_dec], r9
    mov     al, 1
    pop     rdi
    pop     rbx
    ret
.bad:
    xor     al, al
    pop     rdi
    pop     rbx
    ret

; pow10: rax = 10^rcx.
pow10:
    mov     rax, 1
.step:
    test    rcx, rcx
    jle     .out
    imul    rax, rax, 10
    dec     rcx
    jmp     .step
.out:
    ret

; scale_by: rax = rax * 10^rcx.
scale_by:
    test    rcx, rcx
    jle     .out
    imul    rax, rax, 10
    dec     rcx
    jmp     scale_by
.out:
    ret

; ---------------------------------------------------------------------------
; format_fixed: write the value in rax with rcx decimals to rdi, returning the
; length in rax. The digits are padded so there is always something before
; the point: 7 with one decimal prints as "0.7".
; ---------------------------------------------------------------------------
format_fixed:
    push    rbx
    push    rdi
    mov     rbx, rdi
    xor     r8, r8
    test    rax, rax
    jns     .digits
    mov     r8, 1
    neg     rax
.digits:
    mov     rsi, tmpbuf + NUMCAP - 1
    mov     byte [rsi], 0
    xor     r9, r9
    mov     r10, 10
.digit:
    xor     rdx, rdx
    div     r10
    dec     rsi
    add     dl, '0'
    mov     [rsi], dl
    inc     r9
    test    rax, rax
    jnz     .digit
.pad:
    mov     rax, rcx
    inc     rax
    cmp     r9, rax
    jae     .sign
    dec     rsi
    mov     byte [rsi], '0'
    inc     r9
    jmp     .pad
.sign:
    test    r8, r8
    jz      .integer
    mov     byte [rbx], '-'
    inc     rbx
.integer:
    mov     r11, r9
    sub     r11, rcx
.intdigit:
    test    r11, r11
    jz      .point
    mov     al, [rsi]
    mov     [rbx], al
    inc     rbx
    inc     rsi
    dec     r11
    jmp     .intdigit
.point:
    test    rcx, rcx
    jz      .done
    mov     byte [rbx], '.'
    inc     rbx
.fracdigit:
    mov     al, [rsi]
    test    al, al
    jz      .done
    mov     [rbx], al
    inc     rbx
    inc     rsi
    jmp     .fracdigit
.done:
    mov     byte [rbx], 0
    pop     rdi
    mov     rax, rbx
    sub     rax, rdi
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; parse_format: validate the -f format and split it around its conversion.
; Exactly one float conversion is allowed, and the pieces of the specifier
; have to appear in order -- "%1-f" puts a flag after the width, so it is
; rejected. al = 1 when the format is usable.
; ---------------------------------------------------------------------------
parse_format:
    push    rbx
    mov     rdi, fmt_pre
    xor     r8, r8                      ;conversions seen
    xor     r9, r9                      ;0 = before, 1 = after
.scan:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .end
    cmp     al, '%'
    je      .percent
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     .scan
.percent:
    inc     rsi
    movzx   eax, byte [rsi]
    test    al, al
    jz      .bad                        ;a lone trailing '%'
    cmp     al, '%'
    jne     .conversion
    mov     byte [rdi], '%'
    inc     rdi
    inc     rsi
    jmp     .scan
.conversion:
    test    r8, r8
    jnz     .bad                        ;seq takes one conversion, not two
    mov     byte [rdi], 0
    mov     rax, rdi
    cmp     r9, 0
    jne     .bad
    sub     rax, fmt_pre
    mov     [fmt_prelen], rax
.flags:
    movzx   eax, byte [rsi]
    cmp     al, '-'
    je      .fl_minus
    cmp     al, '+'
    je      .fl_plus
    cmp     al, WHITESPACE_SPACE
    je      .fl_space
    cmp     al, '0'
    je      .fl_zero
    cmp     al, '#'
    je      .fl_skip
cmp     al, 0x27                    ;apostrophe: grouping, accepted
    je      .fl_skip
    jmp     .width
.fl_minus:
    mov     byte [sp_minus], 1
    inc     rsi
    jmp     .flags
.fl_plus:
    mov     byte [sp_plus], 1
    inc     rsi
    jmp     .flags
.fl_space:
    mov     byte [sp_space], 1
    inc     rsi
    jmp     .flags
.fl_zero:
    mov     byte [sp_zero], 1
    inc     rsi
    jmp     .flags
.fl_skip:
    inc     rsi
    jmp     .flags
.width:
    xor     rbx, rbx
.wdigit:
    movzx   eax, byte [rsi]
    sub     al, '0'
    cmp     al, 9
    ja      .precision
    imul    rbx, rbx, 10
    movzx   ecx, al
    add     rbx, rcx
    inc     rsi
    jmp     .wdigit
.precision:
    mov     [sp_width], rbx
    cmp     byte [rsi], '.'
    jne     .conv
    inc     rsi
    xor     rbx, rbx
.pdigit:
    movzx   eax, byte [rsi]
    sub     al, '0'
    cmp     al, 9
    ja      .haveprec
    imul    rbx, rbx, 10
    movzx   ecx, al
    add     rbx, rcx
    inc     rsi
    jmp     .pdigit
.haveprec:
    mov     [sp_prec], rbx
.conv:
    movzx   eax, byte [rsi]
    mov     rdi, convchars
    call    charin
    test    al, al
    jz      .bad
    movzx   eax, byte [rsi]
    mov     [sp_conv], al
    inc     rsi
    inc     r8
    mov     r9, 1
    mov     rdi, fmt_post
    jmp     .scan
.end:
    mov     byte [rdi], 0
    cmp     r8, 1
    jne     .bad                        ;no conversion, or more than one
    mov     rax, rdi
    sub     rax, fmt_post
    mov     [fmt_postlen], rax
    mov     al, 1
    pop     rbx
    ret
.bad:
    xor     al, al
    pop     rbx
    ret

; charin: is the byte in al one of the NUL-terminated set at rdi? al = 1/0.
charin:
    mov     cl, al
.scan:
    mov     al, [rdi]
    test    al, al
    jz      .no
    cmp     al, cl
    je      .yes
    inc     rdi
    jmp     .scan
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; render_format: print the printed-precision value in rax through the -f
; format -- literals, then the conversion with its flags and width.
; ---------------------------------------------------------------------------
render_format:
    push    r15
    mov     r15, rax
    mov     rsi, fmt_pre
    mov     rdx, [fmt_prelen]
    call    out_bytes
    mov     rax, r15
    call    build_body
; a sign the body does not already carry
    mov     rsi, [body_start]
    cmp     byte [rsi], '-'
    je      .width
    cmp     byte [sp_plus], 0
    je      .space
    call    body_prefix_plus
    jmp     .width
.space:
    cmp     byte [sp_space], 0
    je      .width
    call    body_prefix_space
.width:
    mov     rcx, [sp_width]
    sub     rcx, [body_len]
    jle     .body
    cmp     byte [sp_minus], 0
    jne     .left
    cmp     byte [sp_zero], 0
    jne     .zeros
.spaces:
    push    rcx
    mov     al, WHITESPACE_SPACE
    call    out_char
    pop     rcx
    dec     rcx
    jnz     .spaces
    jmp     .body
.zeros:
    mov     rsi, [body_start]
    cmp     byte [rsi], '-'
    je      .zerosign
    cmp     byte [rsi], '+'
    je      .zerosign
    cmp     byte [rsi], WHITESPACE_SPACE
    jne     .zerofill
.zerosign:
    push    rcx
    mov     rdx, 1
    call    out_bytes
    pop     rcx
    dec     qword [body_len]
    inc     qword [body_start]
.zerofill:
    push    rcx
    mov     al, '0'
    call    out_char
    pop     rcx
    dec     rcx
    jnz     .zerofill
    jmp     .body
.left:
    push    rcx
    mov     rsi, [body_start]
    mov     rdx, [body_len]
    call    out_bytes
    pop     rcx
.leftpad:
    push    rcx
    mov     al, WHITESPACE_SPACE
    call    out_char
    pop     rcx
    dec     rcx
    jnz     .leftpad
    jmp     .tail
.body:
    mov     rsi, [body_start]
    mov     rdx, [body_len]
    call    out_bytes
.tail:
    mov     rsi, fmt_post
    mov     rdx, [fmt_postlen]
    call    out_bytes
    pop     r15
    ret

; body_prefix_plus / body_prefix_space: put a sign in front of the body.
body_prefix_plus:
    mov     al, '+'
    jmp     body_prefix
body_prefix_space:
    mov     al, WHITESPACE_SPACE
body_prefix:
    mov     rsi, [body_start]
    dec     rsi
    mov     [rsi], al
    mov     [body_start], rsi
    inc     qword [body_len]
    ret

; ---------------------------------------------------------------------------
; build_body: render the value in rax per the conversion into bodybuf,
; leaving body_start and body_len pointing at it. bodybuf keeps a spare byte
; at the front so a sign can be pushed on later.
; ---------------------------------------------------------------------------
build_body:
    push    r15
    mov     r15, rax
    mov     qword [body_start], bodybuf + 1
    movzx   eax, byte [sp_conv]
    cmp     al, 'e'
    je      .exponent
    cmp     al, 'E'
    je      .exponent
    cmp     al, 'g'
    je      .general
    cmp     al, 'G'
    je      .general
; %f and %a alike: fixed point with the requested decimals
    mov     rcx, [sp_prec]
    cmp     rcx, 0
    jge     .fixed
    mov     rcx, 6
.fixed:
    mov     rax, r15
    call    rescale_to
    mov     rdi, bodybuf + 1
    call    format_fixed
    mov     [body_len], rax
    pop     r15
    ret
.exponent:
    mov     rcx, [sp_prec]
    cmp     rcx, 0
    jge     .doexp
    mov     rcx, 6
.doexp:
    mov     rax, r15
    call    format_exp
    mov     [body_len], rax
    pop     r15
    ret
.general:
    mov     rcx, [sp_prec]
    cmp     rcx, 0
    jg      .dogen
    mov     rcx, 6                      ;%g counts significant digits
.dogen:
    mov     rax, r15
    call    format_general
    mov     [body_len], rax
    pop     r15
    ret

; rescale_to: rax holds a value with outprec decimals; return it with rcx
; decimals instead.
rescale_to:
    push    rcx
    mov     r8, rcx
    sub     r8, [outprec]
    jl      .down
    mov     rcx, r8
    call    scale_by
    pop     rcx
    ret
.down:
    neg     r8
    mov     rcx, r8
    push    rax
    mov     rax, 1
    call    pow10
    mov     r9, rax
    pop     rax
    cqo
    idiv    r9
    pop     rcx
    ret

; ---------------------------------------------------------------------------
; format_general: %g -- fixed notation with rcx significant digits, trailing
; zeros removed, falling back to exponent notation when the value is too
; large or too small to show that way.
; ---------------------------------------------------------------------------
format_general:
    push    rbx
    push    r15
    mov     r15, rax
    mov     rbx, rcx
    test    rax, rax
    jnz     .exponent
    mov     byte [bodybuf + 1], '0'     ;zero is just "0"
    mov     byte [bodybuf + 2], 0
    mov     rax, 1
    pop     r15
    pop     rbx
    ret
.exponent:
    mov     rax, r15
    call    decimal_exponent            ;-> rax = exponent of the value
    mov     r8, rax
    cmp     r8, -4
    jl      .scientific
    cmp     r8, rbx
    jge     .scientific
    mov     rcx, rbx
    dec     rcx
    sub     rcx, r8                     ;digits after the point
    cmp     rcx, 0
    jge     .fixed
    xor     rcx, rcx
.fixed:
    mov     rax, r15
    call    rescale_to
    mov     rdi, bodybuf + 1
    call    format_fixed
    mov     rdi, bodybuf + 1
    call    strip_zeros
    pop     r15
    pop     rbx
    ret
.scientific:
    mov     rcx, rbx
    dec     rcx
    mov     rax, r15
    call    format_exp
    pop     r15
    pop     rbx
    ret

; strip_zeros: drop trailing fractional zeros, and the point with them.
; rdi -> string; returns the new length in rax.
strip_zeros:
    mov     rsi, rdi
    xor     rcx, rcx
    xor     r8, r8                      ;does it have a point?
.scan:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .trim
    cmp     al, '.'
    jne     .next
    mov     r8, 1
.next:
    inc     rcx
    jmp     .scan
.trim:
    test    r8, r8
    jz      .out
.zero:
    cmp     rcx, 0
    je      .out
    mov     al, [rsi + rcx - 1]
    cmp     al, '0'
    je      .drop
    cmp     al, '.'
    je      .drop
    jmp     .out
.drop:
    dec     rcx
    mov     byte [rsi + rcx], 0
    cmp     al, '.'
    jne     .zero
.out:
    mov     rax, rcx
    ret

; ---------------------------------------------------------------------------
; format_exp: %e -- one digit, a point, rcx more digits, then the exponent.
; ---------------------------------------------------------------------------
format_exp:
    push    rbx
    push    r15
    mov     r15, rcx                    ;digits after the point
    mov     rbx, bodybuf + 1
    xor     r8, r8
    test    rax, rax
    jns     .digits
    mov     r8, 1
    neg     rax
.digits:
    call    decimal_digits              ;digbuf/dig_len hold |rax|
    test    r8, r8
    jz      .lead
    mov     byte [rbx], '-'
    inc     rbx
.lead:
    mov     rax, [dig_len]
    dec     rax
    sub     rax, [outprec]
    mov     r9, rax                     ;the exponent
    cmp     qword [dig_len], 1
    jne     .first
    cmp     byte [digbuf], '0'
    jne     .first
    xor     r9, r9                      ;a zero value has exponent zero
.first:
    mov     al, [digbuf]
    mov     [rbx], al
    inc     rbx
    test    r15, r15
    jz      .marker
    mov     byte [rbx], '.'
    inc     rbx
    mov     rcx, 1                      ;index into digbuf
.frac:
    test    r15, r15
    jz      .marker
    mov     al, '0'
    cmp     rcx, [dig_len]
    jae     .putfrac
    mov     al, [digbuf + rcx]
.putfrac:
    mov     [rbx], al
    inc     rbx
    inc     rcx
    dec     r15
    jmp     .frac
.marker:
    mov     al, 'e'
    cmp     byte [sp_conv], 'E'
    jne     .putmarker
    mov     al, 'E'
.putmarker:
    cmp     byte [sp_conv], 'G'
    jne     .haveMarker
    mov     al, 'E'
.haveMarker:
    mov     [rbx], al
    inc     rbx
    mov     al, '+'
    test    r9, r9
    jns     .putsign
    mov     al, '-'
    neg     r9
.putsign:
    mov     [rbx], al
    inc     rbx
    cmp     r9, 10
    jae     .exp2
    mov     byte [rbx], '0'
    inc     rbx
.exp2:
    mov     rax, r9
    mov     rdi, rbx
    call    u64_to_dec
    mov     rbx, rdi
    mov     byte [rbx], 0
    mov     rax, rbx
    sub     rax, bodybuf + 1
    pop     r15
    pop     rbx
    ret

; decimal_exponent: the power of ten of the leading digit of rax, where rax
; carries outprec decimals.
decimal_exponent:
    call    decimal_digits
    mov     rax, [dig_len]
    dec     rax
    sub     rax, [outprec]
    ret

; decimal_digits: the digits of |rax| into digbuf, length in dig_len.
decimal_digits:
    test    rax, rax
    jns     .positive
    neg     rax
.positive:
    mov     rsi, tmpbuf + NUMCAP - 1
    mov     byte [rsi], 0
    xor     r9, r9
    mov     r10, 10
.digit:
    xor     rdx, rdx
    div     r10
    dec     rsi
    add     dl, '0'
    mov     [rsi], dl
    inc     r9
    test    rax, rax
    jnz     .digit
    mov     [dig_len], r9
    mov     rdi, digbuf
.copy:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .out
    inc     rsi
    inc     rdi
    jmp     .copy
.out:
    ret

; u64_to_dec: append rax as decimal at rdi, leaving rdi past the last digit.
u64_to_dec:
    push    rbx
    mov     rbx, rdi
    mov     rcx, 10
    xor     r8, r8
.split:
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    push    rdx
    inc     r8
    test    rax, rax
    jnz     .split
.emit:
    pop     rdx
    mov     [rbx], dl
    inc     rbx
    dec     r8
    jnz     .emit
    mov     rdi, rbx
    pop     rbx
    ret

; strlen_z: length of the NUL-terminated string at rdi, in rax.
strlen_z:
    xor     rax, rax
.scan:
    cmp     byte [rdi + rax], 0
    je      .out
    inc     rax
    jmp     .scan
.out:
    ret

; ---------------------------------------------------------------------------
; Output buffering: seq 10000000 is a lot of tiny writes otherwise.
; ---------------------------------------------------------------------------
out_bytes:
    test    rdx, rdx
    jle     .out
.copy:
    mov     rdi, outbuf
    add     rdi, [outlen]
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     qword [outlen]
    dec     rdx
    push    rsi
    push    rdx
    call    out_maybe_flush
    pop     rdx
    pop     rsi
    test    rdx, rdx
    jnz     .copy
.out:
    ret

out_char:
    mov     rdi, outbuf
    add     rdi, [outlen]
    mov     [rdi], al
    inc     qword [outlen]
    call    out_maybe_flush
    ret

out_maybe_flush:
    cmp     qword [outlen], OUTHIGH
    jb      .out
    call    out_flush
.out:
    ret

out_flush:
    mov     rdx, [outlen]
    test    rdx, rdx
    jz      .out
    mov     rsi, outbuf
.write:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    test    rax, rax
    jle     .done
    add     rsi, rax
    sub     rdx, rax
    jnz     .write
.done:
    mov     qword [outlen], 0
.out:
    ret

section .bss
    body_start  resq 1
