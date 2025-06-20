; src/env.asm

    %include "include/sysdefs.inc"

section .bss

section .data
exec_fail_msg db "env: execve failed", 10
    exec_fail_len equ $ - exec_fail_msg
    newline       db WHITESPACE_NL

section .text
global _start

_start:
    pop     rax                         ;argc
    mov     rbx, rax
    mov     r12, rsp                    ;argv
    lea     r13, [r12 + rbx*8 + 8]      ;envp pointer

    cmp     rbx, 1
    jg      .has_command

.print_env:
    mov     r12, r13
.print_loop:
    mov     rsi, [r12]
    test    rsi, rsi
    je      .done

    call    strlen                      ;length -> rbx
    write   STDOUT_FILENO, rsi, rbx
    write   STDOUT_FILENO, newline, 1

    add     r12, 8
    jmp     .print_loop

.done:
    exit    0

.has_command:
    pop     rdi                         ;skip program name
    mov     rsi, rsp                    ;argv for execve (command and args)
    mov     rdx, r13                    ;envp pointer
    mov     rdi, [rsi]                  ;command path
    mov     rax, SYS_EXECVE
    syscall

    write   STDERR_FILENO, exec_fail_msg, exec_fail_len
    exit    1
