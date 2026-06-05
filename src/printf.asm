; src/printf.asm -- printf(1): interpret a format string (escapes and
; %-conversions, with field width) over the operands, reusing the format
; while operands remain. Precision is parsed but not applied.

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

; ---------------- %-conversions ----------------
.conv:
    mov     qword [convlen], 0
    mov     qword [pf_width], 0
    mov     byte [pf_left], 0
    mov     byte [pf_zero], 0
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
    je      .flag_skip
    cmp     al, 32                      ;space
    je      .flag_skip
    cmp     al, 35                      ;'#'
    je      .flag_skip
    jmp     .width
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
    inc     rcx
.skip_prec:
    mov     al, [rcx]
    cmp     al, 48
    jb      .dispatch
    cmp     al, 57
    ja      .dispatch
    inc     rcx
    jmp     .skip_prec
.dispatch:
    mov     al, [rcx]
    cmp     al, 37                      ;'%'
    je      .c_percent
    cmp     al, 's'
    je      .c_s
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
    mov     al, 37                      ;unknown -> emit percent then char raw
    call    emit_al
    mov     al, [rcx]
    test    al, al
    jz      .pass_end
    call    emit_al
    jmp     .conv_next
.c_percent:
    mov     al, 37
    call    cb_al
    jmp     .c_done
.c_s:
    mov     byte [pf_zero], 0           ;zero flag does not apply to strings
    call    next_operand
    call    cb_str
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

; parse_int: rsi -> rax (signed, base 10); advances rsi past the number
parse_int:
    xor     rax, rax
    xor     r10, r10                    ;sign flag
    mov     dl, [rsi]
    cmp     dl, 45                      ;'-'
    jne     .plus
    mov     r10, 1
    inc     rsi
    jmp     .digits
.plus:
    cmp     dl, 43                      ;'+'
    jne     .digits
    inc     rsi
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

; cb_signed: rax = signed value -> convbuf, with optional leading minus
cb_signed:
    test    rax, rax
    jns     .pos
    push    rax
    mov     al, 45
    call    cb_al
    pop     rax
    neg     rax
.pos:
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

; cb_str: rsi -> NUL-terminated string into convbuf
cb_str:
    push    rsi
.loop:
    mov     al, [rsi]
    test    al, al
    jz      .done
    call    cb_al
    inc     rsi
    jmp     .loop
.done:
    pop     rsi
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
