; src/command.asm

    %include "include/sysdefs.inc"

section .bss

section .data
execve_fail_msg db "Error: execve failed", 10
    execve_fail_len equ $ - execve_fail_msg

section .text
global _start

_start:
    pop     rdi                         ;argc
    mov     rbx, rsp                    ;argv pointer
    lea     rdx, [rbx + rdi*8 + 8]      ;envp pointer
    cmp     rdi, 1
    jle     .exit_success

    add     rbx, 8                      ;skip program name
    mov     rsi, rbx                    ;argv for execve
    mov     rdi, [rsi]                  ;command path
    mov     rax, SYS_EXECVE
    syscall

    write   STDERR_FILENO, execve_fail_msg, execve_fail_len
    exit    1

.exit_success:
    exit    0
