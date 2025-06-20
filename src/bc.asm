; src/bc.asm

%include "include/sysdefs.inc"

section .data
    bc_path         db "/usr/bin/bc", 0
    execve_fail_msg db "Error: execve failed", 10
    execve_fail_len equ $ - execve_fail_msg

section .text
    global _start

_start:
    pop     rax                 ; argc
    mov     rbx, rsp            ; argv
    lea     rdx, [rbx + rax*8 + 8] ; envp

    mov     qword [rbx], bc_path      ; argv[0] = bc_path
    mov     rdi, bc_path        ; filename
    mov     rsi, rbx            ; argv

    mov     rax, SYS_EXECVE
    syscall

    ; If execve returns, an error occurred
execve_error:
    write   STDERR_FILENO, execve_fail_msg, execve_fail_len
    exit    1
