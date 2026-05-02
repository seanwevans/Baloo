; src/unlink.asm

    %include "include/sysdefs.inc"

section .bss

section .data
error_msg   db "Error: No filename specified", 10
    error_len   equ $ - error_msg
usage_msg   db "Usage: unlink filename", 10
    usage_len   equ $ - usage_msg
unlink_error_msg db "Error: Failed to unlink file", 10
    unlink_error_len equ $ - unlink_error_msg

section .text
global      _start

_start:
    pop         rax                     ;argc
    cmp         rax, 2                  ;Program name is arg 0, need at least 2 args
    jge         has_args

    write       STDERR_FILENO, error_msg, error_len
    write       STDERR_FILENO, usage_msg, usage_len
    exit        1

has_args:
    pop         rdi
    pop         rdi                     ;filename to unlink

    mov         rax, SYS_UNLINK
    syscall

    test        rax, rax
    js          unlink_error

    exit        0

unlink_error:
    write       STDERR_FILENO, unlink_error_msg, unlink_error_len
    exit        1
