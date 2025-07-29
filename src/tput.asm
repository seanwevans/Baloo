; src/tput.asm

%include "include/sysdefs.inc"

section .data
    tput_path        db "/usr/bin/tput", 0
    execve_fail_msg  db "Error: execve failed", 10
    execve_fail_len  equ $ - execve_fail_msg

section .text
    global _start

_start:
    pop     rax                 ; argc
    mov     rbx, rsp            ; argv
    lea     rdx, [rbx + rax*8 + 8] ; envp

    mov     qword [rbx], tput_path   ; argv[0] = path to system tput
    mov     rdi, tput_path
    mov     rsi, rbx

    mov     rax, SYS_EXECVE
    syscall

execve_error:
    write   STDERR_FILENO, execve_fail_msg, execve_fail_len
    exit    1
