; src/rm.asm

    %include "include/sysdefs.inc"

section .bss

section .data
usage_msg       db "Usage: rm [file]", 10
    usage_msg_len   equ $ - usage_msg
error_msg       db "Error: Could not remove file", 10
    error_msg_len   equ $ - error_msg

section .text
global          _start

_start:
    pop             rdi
    cmp             rdi, 2
    jne             usage_error

    pop             rsi
    pop             rdi
    mov             rax, SYS_UNLINK
    syscall

    test            rax, rax
    js              unlink_error

    exit            0

usage_error:
    write           STDERR_FILENO, usage_msg, usage_msg_len
    exit            1

unlink_error:
    write           STDERR_FILENO, error_msg, error_msg_len
    exit            1
