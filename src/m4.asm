; src/m4.asm

    %include "include/sysdefs.inc"

section .data
    m4_path          db "/usr/bin/m4", 0
execve_fail_msg  db "m4: execve failed", 10
    execve_fail_len  equ $ - execve_fail_msg

section .text
global      _start

_start:
    pop         rax                     ;argc
    mov         rbx, rsp                ;argv
    lea         rdx, [rbx + rax*8 + 8]  ;envp

    mov         qword [rbx], m4_path    ;argv[0] = m4_path
    mov         rdi, m4_path            ;filename
    mov         rsi, rbx                ;argv
    mov         rax, SYS_EXECVE
    syscall

    write       STDERR_FILENO, execve_fail_msg, execve_fail_len
    exit        1
