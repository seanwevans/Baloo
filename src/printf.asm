; src/printf.asm

    %include "include/sysdefs.inc"

section .text
global _start

_start:
    pop rdi                             ;argc
    pop rbx                             ;argv[0]
    cmp rdi, 1
    jle .exit
    mov rsi, [rsp]
    call strlen
    write STDOUT_FILENO, rsi, rbx
.exit:
    exit 0
