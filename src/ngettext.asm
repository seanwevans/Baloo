; src/ngettext.asm

    %include "include/sysdefs.inc"

section .bss

section .data
    newline     db WHITESPACE_NL
    err_msg     db "ngettext: missing operand", 10
    err_len     equ $ - err_msg

section .text
    global _start

_start:
    mov     rsi, rsp                    ;argc pointer
    mov     rdi, [rsi]
    cmp     rdi, 4
    jl      missing_operand

    add     rsi, 8                      ;skip argc
    add     rsi, 8                      ;skip argv[0]
    mov     r8, [rsi]                   ;singular msgid
    add     rsi, 8
    mov     r9, [rsi]                   ;plural msgid
    add     rsi, 8
    mov     rdi, [rsi]                  ;n argument
    call    atoi
    mov     rdx, rax

    cmp     rdx, 1
    jne     .use_plural

    mov     rsi, r8
    call    strlen
    mov     rdx, rbx
    write   STDOUT_FILENO, rsi, rdx
    write   STDOUT_FILENO, newline, 1
    exit    0

.use_plural:
    mov     rsi, r9
    call    strlen
    mov     rdx, rbx
    write   STDOUT_FILENO, rsi, rdx
    write   STDOUT_FILENO, newline, 1
    exit    0

missing_operand:
    write   STDERR_FILENO, err_msg, err_len
    exit    1

; Convert string in RDI to integer in RAX (returns 0 on error)
atoi:
    xor     rax, rax
    xor     rcx, rcx

atoi_loop:
    movzx   r8, byte [rdi + rcx]
    test    r8, r8
    jz      atoi_done
    cmp     r8, '0'
    jl      atoi_error
    cmp     r8, '9'
    jg      atoi_error
    imul    rax, 10
    sub     r8, '0'
    add     rax, r8
    inc     rcx
    jmp     atoi_loop

atoi_done:
    ret

atoi_error:
    xor     rax, rax
    ret
