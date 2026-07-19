; src/printf.asm -- printf(1): interpret a format string (escapes and
; %-conversions, with field width, precision and the -/+/space/0 flags)
; over the operands, reusing the format while operands remain.

    %include "include/sysdefs.inc"

    %define OUTBUF_SIZE 8192
    %define CONVBUF_SIZE 512

section .bss
    outbuf  resb OUTBUF_SIZE
    outlen  resq 1
    convbuf resb CONVBUF_SIZE           ;one rendered conversion
    convlen resq 1
    numbuf  resb 32
    pf_width resq 1
    pf_left resb 1
    pf_zero resb 1
    pf_prec resq 1
    pf_has_prec resb 1
    pf_plus resb 1
    pf_space resb 1

section .data
    digits_lower db "0123456789abcdef"
    digits_upper db "0123456789ABCDEF"
    empty_str    db 0

section .text
global _start

_start:
    mov     qword [outlen], 0
    pop     rax                         ;argc
    pop     rdi                         ;argv[0] (discarded)
    cmp     rax, 2
    jl      .noargs
    mov     r13, rsp                    ;points at argv[1]
    mov     r12, [r13]                  ;format string
    add     r13, 8                      ;operands base (argv+2)
    sub     rax, 2
    mov     r14, rax                    ;operand count
    xor     r15, r15                    ;operand index

.format_pass:
    mov     rbp, r15                    ;operand index at start of this pass
    mov     rcx, r12                    ;format cursor
.fmt_loop:
    mov     al, [rcx]
    test    al, al
    jz      .pass_end
    cmp     al, 92                      ;backslash
    je      .escape
    cmp     al, 37                      ;percent
    je      .conv
    call    emit_al
    inc     rcx
    jmp     .fmt_loop

.pass_end:
    cmp     r15, rbp
    je      .done                       ;consumed no operand this pass
    cmp     r15, r14
    jl      .format_pass                ;operands remain, reuse the format
.done:
    call    flush
    exit    0
.noargs:
    exit    0

; ---------------- backslash escapes ----------------
.escape:
    inc     rcx
    mov     al, [rcx]
    test    al, al
    jz      .esc_trailing
    cmp     al, 'n'
    je      .esc_n
    cmp     al, 't'
    je      .esc_t
    cmp     al, 'r'
    je      .esc_r
    cmp     al, 92
    je      .esc_bs
    cmp     al, 'a'
    je      .esc_a
    cmp     al, 'b'
    je      .esc_b
    cmp     al, 'f'
    je      .esc_f
    cmp     al, 'v'
    je      .esc_v
    cmp     al, 'e'
    je      .esc_e
    cmp     al, 'x'
    je      .esc_hex
    cmp     al, 'c'
    je      .esc_c
    cmp     al, 48                      ;'0'
    jb      .esc_unknown
    cmp     al, 55                      ;'7'
    jbe     .esc_oct
.esc_unknown:
    mov     al, 92
    call    emit_al
    mov     al, [rcx]
    call    emit_al
    inc     rcx
    jmp     .fmt_loop
.esc_trailing:
    mov     al, 92
    call    emit_al
    jmp     .fmt_loop
.esc_n:
    mov     al, 10
    jmp     .esc_one
.esc_t:
    mov     al, 9
    jmp     .esc_one
.esc_r:
    mov     al, 13
    jmp     .esc_one
.esc_bs:
    mov     al, 92
    jmp     .esc_one
.esc_a:
    mov     al, 7
    jmp     .esc_one
.esc_b:
    mov     al, 8
    jmp     .esc_one
.esc_f:
    mov     al, 12
    jmp     .esc_one
.esc_v:
    mov     al, 11
    jmp     .esc_one
.esc_e:
    mov     al, 27                      ;escape (ESC)
.esc_one:
    call    emit_al
    inc     rcx
    jmp     .fmt_loop
.esc_oct:
    xor     rax, rax
    xor     r10, r10
.oct_loop:
    cmp     r10, 3
    jge     .oct_done
    mov     dl, [rcx]
    sub     dl, 48
    cmp     dl, 7
    ja      .oct_done
    shl     rax, 3
    add     al, dl
    inc     rcx
    inc     r10
    jmp     .oct_loop
.oct_done:
    call    emit_al
    jmp     .fmt_loop
.esc_hex:
    inc     rcx                         ;skip 'x'
    xor     rax, rax
    xor     r10, r10                    ;hex digit count
.hex_loop:
    cmp     r10, 2
    jge     .hex_check
    mov     dl, [rcx]
    cmp     dl, '0'
    jb      .hex_check
    cmp     dl, '9'
    jbe     .hex_digit
    or      dl, 0x20                    ;fold letters to lower case
    cmp     dl, 'a'
    jb      .hex_check
    cmp     dl, 'f'
    ja      .hex_check
    sub     dl, 'a' - 10
    jmp     .hex_acc
.hex_digit:
    sub     dl, '0'
.hex_acc:
    shl     rax, 4
    add     al, dl
    inc     rcx
    inc     r10
    jmp     .hex_loop
.hex_check:
    test    r10, r10
    jz      .hex_bad                    ;\x with no hex digits is an error
    call    emit_al
    jmp     .fmt_loop
.hex_bad:
    call    flush
    exit    1
.esc_c:
    call    flush                       ;\c stops all further output
    exit    0

; ---------------- %-conversions ----------------
.conv:
    mov     qword [convlen], 0
    mov     qword [pf_width], 0
    mov     byte [pf_left], 0
    mov     byte [pf_zero], 0
    mov     qword [pf_prec], 0
    mov     byte [pf_has_prec], 0
    mov     byte [pf_plus], 0
    mov     byte [pf_space], 0
    inc     rcx
.flags:
    mov     al, [rcx]
    cmp     al, 45                      ;'-'
    jne     .flag_zero
    mov     byte [pf_left], 1
    inc     rcx
    jmp     .flags
.flag_zero:
    cmp     al, 48                      ;'0'
    jne     .flag_other
    mov     byte [pf_zero], 1
    inc     rcx
    jmp     .flags
.flag_other:
    cmp     al, 43                      ;'+'
    je      .flag_plus
    cmp     al, 32                      ;space
    je      .flag_space
    cmp     al, 35                      ;'#'
    je      .flag_skip
    jmp     .width
.flag_plus:
    mov     byte [pf_plus], 1
    inc     rcx
    jmp     .flags
.flag_space:
    mov     byte [pf_space], 1
    inc     rcx
    jmp     .flags
.flag_skip:
    inc     rcx
    jmp     .flags
.width:
    mov     al, [rcx]
    cmp     al, 48
    jb      .precision
    cmp     al, 57
    ja      .precision
    movzx   rdx, al
    sub     dl, 48
    mov     rax, [pf_width]
    imul    rax, rax, 10
    add     rax, rdx
    mov     [pf_width], rax
    inc     rcx
    jmp     .width
.precision:
    mov     al, [rcx]
    cmp     al, 46                      ;'.'
    jne     .dispatch
    mov     byte [pf_has_prec], 1
    inc     rcx
.skip_prec:
    mov     al, [rcx]
    cmp     al, 48
    jb      .dispatch
    cmp     al, 57
    ja      .dispatch
    movzx   rdx, al
    sub     dl, 48
    mov     rax, [pf_prec]
    imul    rax, rax, 10
    add     rax, rdx
    mov     [pf_prec], rax
    inc     rcx
    jmp     .skip_prec
.dispatch:
    mov     al, [rcx]
    cmp     al, 37                      ;'%'
    je      .c_percent
    cmp     al, 's'
    je      .c_s
    cmp     al, 'b'
    je      .c_b
    cmp     al, 'd'
    je      .c_d
    cmp     al, 'i'
    je      .c_d
    cmp     al, 'u'
    je      .c_u
    cmp     al, 'x'
    je      .c_x
    cmp     al, 'X'
    je      .c_xx
    cmp     al, 'o'
    je      .c_o
    cmp     al, 'c'
    je      .c_c
    cmp     al, 'f'
    je      .c_f
    cmp     al, 'F'
    je      .c_f
    cmp     al, 'g'
    je      .c_g
    cmp     al, 'G'
    je      .c_g
    cmp     al, 42                      ;'*' dynamic width is unsupported
    je      .conv_error
    test    al, al                      ;'%' at end of format is an error
    jz      .conv_error
    mov     al, 37                      ;unknown -> emit percent then char raw
    call    emit_al
    mov     al, [rcx]
    call    emit_al
    jmp     .conv_next
.conv_error:
    call    flush
    exit    1
.c_percent:
    mov     al, 37
    call    cb_al
    jmp     .c_done
.c_s:
    mov     byte [pf_zero], 0           ;zero flag does not apply to strings
    call    next_operand
    call    cb_str
    jmp     .c_done
.c_b:
    mov     byte [pf_zero], 0           ;zero flag does not apply to strings
    call    next_operand
    call    cb_str_b
    jmp     .c_done
.c_f:
    mov     byte [pf_zero], 0
    push    rcx                         ;preserve the format cursor
    call    next_operand
    call    parse_double
    call    render_f
    pop     rcx
    jmp     .c_done
.c_g:
    mov     byte [pf_zero], 0
    push    rcx                         ;preserve the format cursor
    call    next_operand
    call    parse_double
    call    render_g
    pop     rcx
    jmp     .c_done
.c_c:
    mov     byte [pf_zero], 0
    call    next_operand
    mov     al, [rsi]
    test    al, al
    jz      .c_done
    call    cb_al
    jmp     .c_done
.c_d:
    call    next_operand
    call    parse_int
    call    cb_signed
    jmp     .c_done
.c_u:
    call    next_operand
    call    parse_int
    mov     r8, 10
    mov     r9, digits_lower
    call    cb_unsigned
    jmp     .c_done
.c_x:
    call    next_operand
    call    parse_int
    mov     r8, 16
    mov     r9, digits_lower
    call    cb_unsigned
    jmp     .c_done
.c_xx:
    call    next_operand
    call    parse_int
    mov     r8, 16
    mov     r9, digits_upper
    call    cb_unsigned
    jmp     .c_done
.c_o:
    call    next_operand
    call    parse_int
    mov     r8, 8
    mov     r9, digits_lower
    call    cb_unsigned
.c_done:
    call    emit_conv
.conv_next:
    inc     rcx
    jmp     .fmt_loop

; ==================== helpers ====================

; next_operand -> rsi points at the next operand (or empty), advances r15
next_operand:
    cmp     r15, r14
    jge     .none
    mov     rsi, [r13 + r15*8]
    inc     r15
    ret
.none:
    mov     rsi, empty_str
    ret

; parse_int: rsi -> rax (signed); advances rsi past the number. A leading
; 0x/0X marks hexadecimal and a leading 0 marks octal, matching printf.
parse_int:
    xor     rax, rax
    xor     r10, r10                    ;sign flag
    mov     dl, [rsi]
    cmp     dl, 45                      ;'-'
    jne     .plus
    mov     r10, 1
    inc     rsi
    jmp     .base
.plus:
    cmp     dl, 43                      ;'+'
    jne     .base
    inc     rsi
.base:
    mov     dl, [rsi]
    cmp     dl, '0'
    jne     .digits                     ;no leading 0 -> decimal
    mov     dl, [rsi + 1]
    or      dl, 0x20
    cmp     dl, 'x'
    je      .hex
    inc     rsi                         ;consume the leading 0 (octal)
.oct:
    movzx   rdx, byte [rsi]
    sub     dl, 48
    cmp     dl, 7
    ja      .end
    shl     rax, 3
    add     rax, rdx
    inc     rsi
    jmp     .oct
.hex:
    add     rsi, 2                      ;skip 0x
.hexdigits:
    movzx   rdx, byte [rsi]
    cmp     dl, '0'
    jb      .end
    cmp     dl, '9'
    jbe     .hex_dig
    or      dl, 0x20
    cmp     dl, 'a'
    jb      .end
    cmp     dl, 'f'
    ja      .end
    sub     dl, 'a' - 10
    jmp     .hex_acc
.hex_dig:
    sub     dl, '0'
.hex_acc:
    shl     rax, 4
    add     rax, rdx
    inc     rsi
    jmp     .hexdigits
.digits:
    movzx   rdx, byte [rsi]
    sub     dl, 48
    cmp     dl, 9
    ja      .end
    imul    rax, rax, 10
    add     rax, rdx
    inc     rsi
    jmp     .digits
.end:
    test    r10, r10
    jz      .ret
    neg     rax
.ret:
    ret

; cb_signed: rax = signed value -> convbuf, with a leading sign per the
; '-' (always), '+' and space flags.
cb_signed:
    test    rax, rax
    js      .neg
    cmp     byte [pf_plus], 0
    jne     .plus
    cmp     byte [pf_space], 0
    jne     .space
    jmp     .digits
.plus:
    push    rax
    mov     al, 43                      ;'+'
    call    cb_al
    pop     rax
    jmp     .digits
.space:
    push    rax
    mov     al, 32                      ;' '
    call    cb_al
    pop     rax
    jmp     .digits
.neg:
    push    rax
    mov     al, 45                      ;'-'
    call    cb_al
    pop     rax
    neg     rax
.digits:
    mov     r8, 10
    mov     r9, digits_lower
    call    cb_unsigned
    ret

; cb_unsigned: rax = value, r8 = base, r9 = digit table -> convbuf
cb_unsigned:
    push    rcx
    mov     rdi, numbuf
    add     rdi, 32
.conv_loop:
    xor     rdx, rdx
    div     r8
    mov     r10b, [r9 + rdx]
    dec     rdi
    mov     [rdi], r10b
    test    rax, rax
    jnz     .conv_loop
    mov     rcx, numbuf
    add     rcx, 32
.emit_loop:
    cmp     rdi, rcx
    jge     .emit_done
    mov     al, [rdi]
    call    cb_al
    inc     rdi
    jmp     .emit_loop
.emit_done:
    pop     rcx
    ret

; cb_str: rsi -> NUL-terminated string into convbuf, honouring precision
; as the maximum number of characters to copy.
cb_str:
    push    rsi
    push    rcx
    xor     rcx, rcx                    ;characters copied
.loop:
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     byte [pf_has_prec], 0
    je      .emit
    cmp     rcx, [pf_prec]
    jge     .done
.emit:
    call    cb_al
    inc     rsi
    inc     rcx
    jmp     .loop
.done:
    pop     rcx
    pop     rsi
    ret

; cb_str_b: rsi -> NUL-terminated string into convbuf, interpreting the
; backslash escapes recognised by printf's %b conversion.
cb_str_b:
    push    rsi
.loop:
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     al, 92                      ;backslash
    je      .esc
    call    cb_al
    inc     rsi
    jmp     .loop
.esc:
    inc     rsi
    mov     al, [rsi]
    test    al, al
    jz      .lone_bs
    cmp     al, 'n'
    je      .e_n
    cmp     al, 't'
    je      .e_t
    cmp     al, 'r'
    je      .e_r
    cmp     al, 'v'
    je      .e_v
    cmp     al, 'f'
    je      .e_f
    cmp     al, 'b'
    je      .e_b
    cmp     al, 'a'
    je      .e_a
    cmp     al, 'e'
    je      .e_e
    cmp     al, 92
    je      .e_bs
    cmp     al, 'c'
    je      .done                       ;\c stops all further output
    cmp     al, 'x'
    je      .e_hex
    cmp     al, 48                      ;'0' introduces an octal escape
    je      .e_oct
;unrecognised: emit backslash then the character literally
    push    rax
    mov     al, 92
    call    cb_al
    pop     rax
    call    cb_al
    inc     rsi
    jmp     .loop
.lone_bs:
    mov     al, 92
    call    cb_al
    jmp     .done
.e_n:
    mov     al, 10
    jmp     .e_emit
.e_t:
    mov     al, 9
    jmp     .e_emit
.e_r:
    mov     al, 13
    jmp     .e_emit
.e_v:
    mov     al, 11
    jmp     .e_emit
.e_f:
    mov     al, 12
    jmp     .e_emit
.e_b:
    mov     al, 8
    jmp     .e_emit
.e_a:
    mov     al, 7
    jmp     .e_emit
.e_e:
    mov     al, 27
    jmp     .e_emit
.e_bs:
    mov     al, 92
.e_emit:
    call    cb_al
    inc     rsi
    jmp     .loop
.e_oct:
    inc     rsi                         ;skip the leading '0'
    xor     rax, rax
    xor     r10, r10
.oct_loop:
    cmp     r10, 3
    jge     .oct_done
    mov     dl, [rsi]
    sub     dl, 48
    cmp     dl, 7
    ja      .oct_done
    shl     rax, 3
    add     al, dl
    inc     rsi
    inc     r10
    jmp     .oct_loop
.oct_done:
    call    cb_al
    jmp     .loop
.e_hex:
    inc     rsi                         ;skip 'x'
    xor     rax, rax
    xor     r10, r10                    ;hex digit count
.hex_loop:
    cmp     r10, 2
    jge     .hex_done
    mov     dl, [rsi]
    cmp     dl, '0'
    jb      .hex_done
    cmp     dl, '9'
    jbe     .hex_dig
    or      dl, 0x20
    cmp     dl, 'a'
    jb      .hex_done
    cmp     dl, 'f'
    ja      .hex_done
    sub     dl, 'a' - 10
    jmp     .hex_acc
.hex_dig:
    sub     dl, '0'
.hex_acc:
    shl     rax, 4
    add     al, dl
    inc     rsi
    inc     r10
    jmp     .hex_loop
.hex_done:
    test    r10, r10
    jz      .loop                       ;\x with no hex digits emits nothing
    call    cb_al
    jmp     .loop
.done:
    pop     rsi
    ret

; parse_double: rsi -> xmm0 (double); advances rsi past the number. Handles
; an optional sign, a fractional part and an e-exponent.
parse_double:
    xor     r11, r11                    ;sign flag
    mov     dl, [rsi]
    cmp     dl, '-'
    jne     .pd_plus
    mov     r11, 1
    inc     rsi
    jmp     .pd_int
.pd_plus:
    cmp     dl, '+'
    jne     .pd_int
    inc     rsi
.pd_int:
    xor     rax, rax                    ;mantissa (integer form)
    xor     rcx, rcx                    ;count of fractional digits
.pd_int_loop:
    movzx   rdx, byte [rsi]
    cmp     dl, '0'
    jb      .pd_dot
    cmp     dl, '9'
    ja      .pd_dot
    sub     dl, '0'
    imul    rax, rax, 10
    add     rax, rdx
    inc     rsi
    jmp     .pd_int_loop
.pd_dot:
    cmp     byte [rsi], '.'
    jne     .pd_exp
    inc     rsi
.pd_frac_loop:
    movzx   rdx, byte [rsi]
    cmp     dl, '0'
    jb      .pd_exp
    cmp     dl, '9'
    ja      .pd_exp
    sub     dl, '0'
    imul    rax, rax, 10
    add     rax, rdx
    inc     rcx
    inc     rsi
    jmp     .pd_frac_loop
.pd_exp:
    xor     r8, r8                      ;exponent value
    xor     r9, r9                      ;exponent sign
    movzx   rdx, byte [rsi]
    or      dl, 0x20
    cmp     dl, 'e'
    jne     .pd_scale
    inc     rsi
    mov     dl, [rsi]
    cmp     dl, '-'
    jne     .pd_eplus
    mov     r9, 1
    inc     rsi
    jmp     .pd_eloop
.pd_eplus:
    cmp     dl, '+'
    jne     .pd_eloop
    inc     rsi
.pd_eloop:
    movzx   rdx, byte [rsi]
    cmp     dl, '0'
    jb      .pd_esign
    cmp     dl, '9'
    ja      .pd_esign
    sub     dl, '0'
    imul    r8, r8, 10
    add     r8, rdx
    inc     rsi
    jmp     .pd_eloop
.pd_esign:
    test    r9, r9
    jz      .pd_scale
    neg     r8
.pd_scale:
    cvtsi2sd xmm0, rax                  ;mantissa as double
    sub     r8, rcx                     ;net power of ten to apply
    mov     rax, 10
    cvtsi2sd xmm1, rax                  ;10.0
    test    r8, r8
    js      .pd_div
.pd_mul:
    test    r8, r8
    jz      .pd_sign
    mulsd   xmm0, xmm1
    dec     r8
    jmp     .pd_mul
.pd_div:
    neg     r8
.pd_div_loop:
    test    r8, r8
    jz      .pd_sign
    divsd   xmm0, xmm1
    dec     r8
    jmp     .pd_div_loop
.pd_sign:
    test    r11, r11
    jz      .pd_done
    xorpd   xmm7, xmm7
    subsd   xmm7, xmm0
    movsd   xmm0, xmm7
.pd_done:
    ret

; render_f: xmm0 -> convbuf as a fixed-point number, using precision (default
; 6) fractional digits and emitting a leading sign when negative.
render_f:
    mov     rcx, 6
    cmp     byte [pf_has_prec], 0
    je      .rf_go
    mov     rcx, [pf_prec]
.rf_go:
    movq    rax, xmm0
    test    rax, rax
    jns     render_f_core
    push    rcx
    mov     al, '-'
    call    cb_al
    pop     rcx
    xorpd   xmm7, xmm7
    subsd   xmm7, xmm0
    movsd   xmm0, xmm7
; fall through to render_f_core

; render_f_core: xmm0 (>= 0) -> convbuf with rcx fractional digits.
render_f_core:
    mov     r10, 1                      ;integer 10^rcx
    mov     rax, 1
    cvtsi2sd xmm1, rax                  ;double 10^rcx accumulator
    mov     rax, 10
    cvtsi2sd xmm2, rax                  ;10.0
    mov     rax, rcx
.rfc_pow:
    test    rax, rax
    jz      .rfc_scaled
    mulsd   xmm1, xmm2
    imul    r10, r10, 10
    dec     rax
    jmp     .rfc_pow
.rfc_scaled:
    mulsd   xmm0, xmm1
    cvtsd2si rax, xmm0                  ;round to nearest
    xor     rdx, rdx
    div     r10                         ;rax = integer part, rdx = fraction
    push    rdx
    push    rcx
    mov     r8, 10
    mov     r9, digits_lower
    call    cb_unsigned                 ;emit integer part
    pop     rcx
    pop     rdx
    test    rcx, rcx
    jz      .rfc_done
    push    rcx
    mov     al, '.'
    call    cb_al
    pop     rcx
    mov     rax, rdx
    mov     r11, rcx                    ;pad fraction to precision digits
    call    cb_uint_pad
.rfc_done:
    ret

; render_g: xmm0 -> convbuf like printf %g (significant digits, trailing
; zeros stripped). Uses the %f rendering for the common in-range magnitudes.
render_g:
    mov     rcx, 6
    cmp     byte [pf_has_prec], 0
    je      .rg_go
    mov     rcx, [pf_prec]
    test    rcx, rcx
    jnz     .rg_go
    mov     rcx, 1
.rg_go:
    push    rbx
    movq    rax, xmm0
    test    rax, rax
    jns     .rg_pos
    push    rcx
    mov     al, '-'
    call    cb_al
    pop     rcx
    xorpd   xmm7, xmm7
    subsd   xmm7, xmm0
    movsd   xmm0, xmm7
.rg_pos:
    xorpd   xmm3, xmm3
    ucomisd xmm0, xmm3
    jne     .rg_nz
    jnp     .rg_zero
.rg_nz:
    movsd   xmm5, xmm0                  ;work on a copy to find the exponent
    mov     rax, 10
    cvtsi2sd xmm2, rax
    mov     rax, 1
    cvtsi2sd xmm4, rax
    xor     rbx, rbx                    ;decimal exponent X
.rg_hi:
    ucomisd xmm5, xmm2
    jb      .rg_lo
    divsd   xmm5, xmm2
    inc     rbx
    jmp     .rg_hi
.rg_lo:
    ucomisd xmm5, xmm4
    jae     .rg_dec
    mulsd   xmm5, xmm2
    dec     rbx
    jmp     .rg_lo
.rg_dec:
    mov     r11, rcx                    ;decimals = P - 1 - X
    dec     r11
    sub     r11, rbx
    test    r11, r11
    jns     .rg_ok
    xor     r11, r11
.rg_ok:
    push    r11
    mov     rcx, r11
    call    render_f_core
    pop     r11
    test    r11, r11
    jz      .rg_done
.rg_strip:
    mov     rax, [convlen]
    test    rax, rax
    jz      .rg_done
    dec     rax
    cmp     byte [convbuf + rax], '0'
    jne     .rg_dot
    mov     [convlen], rax
    jmp     .rg_strip
.rg_dot:
    cmp     byte [convbuf + rax], '.'
    jne     .rg_done
    mov     [convlen], rax
    jmp     .rg_done
.rg_zero:
    mov     al, '0'
    call    cb_al
.rg_done:
    pop     rbx
    ret

; cb_uint_pad: append rax (unsigned base 10) to convbuf, left-padded with
; zeros to at least r11 digits.
cb_uint_pad:
    push    rcx
    mov     rdi, numbuf
    add     rdi, 32
    xor     rcx, rcx                    ;digit count
.cu_loop:
    xor     rdx, rdx
    mov     r8, 10
    div     r8
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    inc     rcx
    test    rax, rax
    jnz     .cu_loop
.cu_pad:
    cmp     rcx, r11
    jge     .cu_emit
    dec     rdi
    mov     byte [rdi], '0'
    inc     rcx
    jmp     .cu_pad
.cu_emit:
    mov     al, [rdi]
    call    cb_al
    inc     rdi
    dec     rcx
    jnz     .cu_emit
    pop     rcx
    ret

; cb_al: append al to convbuf (capped at CONVBUF_SIZE-1)
cb_al:
    push    rdx
    mov     rdx, [convlen]
    cmp     rdx, CONVBUF_SIZE - 1
    jge     .full
    mov     [convbuf + rdx], al
    inc     rdx
    mov     [convlen], rdx
.full:
    pop     rdx
    ret

; emit_conv: emit convbuf to outbuf, padded to [pf_width] per the flags
emit_conv:
    push    rcx
    mov     r10, [convlen]
    mov     rdi, [pf_width]
    sub     rdi, r10                    ;rdi = pad count (may be <= 0)
    cmp     byte [pf_left], 1
    je      .left
    test    rdi, rdi
    jle     .emit_all
    cmp     byte [pf_zero], 1
    je      .zero
.space:
    mov     rcx, rdi
.space_loop:
    mov     al, 32
    call    emit_al
    dec     rcx
    jnz     .space_loop
    xor     rsi, rsi
    jmp     .emit_from
.zero:
    xor     rsi, rsi
    mov     al, [convbuf]
    cmp     al, 45                      ;leading minus stays before zeros
    jne     .zero_pad
    call    emit_al
    mov     rsi, 1
.zero_pad:
    mov     rcx, rdi
.zero_loop:
    mov     al, 48
    call    emit_al
    dec     rcx
    jnz     .zero_loop
    jmp     .emit_from
.emit_all:
    xor     rsi, rsi
    jmp     .emit_from
.left:
    xor     rsi, rsi
    call    emit_convbuf
    test    rdi, rdi
    jle     .ec_done
    mov     rcx, rdi
.left_loop:
    mov     al, 32
    call    emit_al
    dec     rcx
    jnz     .left_loop
    jmp     .ec_done
.emit_from:
    call    emit_convbuf
.ec_done:
    pop     rcx
    ret

; emit_convbuf: emit convbuf[rsi .. convlen) to outbuf
emit_convbuf:
    mov     rdx, [convlen]
.l:
    cmp     rsi, rdx
    jge     .d
    mov     al, [convbuf + rsi]
    call    emit_al
    inc     rsi
    jmp     .l
.d:
    ret

; emit_al: append al to the output buffer, flushing when full
emit_al:
    push    rdx
    mov     rdx, [outlen]
    cmp     rdx, OUTBUF_SIZE
    jl      .store
    call    flush
    xor     rdx, rdx
.store:
    mov     [outbuf + rdx], al
    inc     rdx
    mov     [outlen], rdx
    pop     rdx
    ret

; flush: write the buffered output to stdout (preserves all registers)
flush:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r11
    mov     rdx, [outlen]
    test    rdx, rdx
    jz      .empty
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, outbuf
    syscall
    mov     qword [outlen], 0
.empty:
    pop     r11
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret
