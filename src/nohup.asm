; src/nohup.asm

    %include "include/sysdefs.inc"

section .bss

section .data
usage_msg   db "Usage: nohup COMMAND [ARGS...]", 10
    usage_len   equ $ - usage_msg
exec_fail   db "nohup: exec failed", 10
    exec_fail_len equ $ - exec_fail
    out_path    db "nohup.out", 0

section .text
global  _start

_start:
    pop     r9                          ;argc
    mov     rbx, rsp                    ;argv pointer
    cmp     r9, 2
    jl      .usage

; compute env pointer
    lea     r13, [rbx + r9*8 + 8]

; open nohup.out for append
    mov     rax, SYS_OPEN
    lea     rdi, [rel out_path]
    mov     rsi, O_WRONLY | O_CREAT | O_APPEND
    mov     rdx, DEFAULT_MODE
    syscall
    test    rax, rax
    js      .usage                      ;if open fails, show usage
    mov     r12, rax

; duplicate descriptor to stdout and stderr
    mov     rax, SYS_DUP2
    mov     rdi, r12
    mov     rsi, STDOUT_FILENO
    syscall

    mov     rax, SYS_DUP2
    mov     rdi, r12
    mov     rsi, STDERR_FILENO
    syscall

    mov     rax, SYS_CLOSE
    mov     rdi, r12
    syscall

; ignore SIGHUP
    sub     rsp, 152
    mov     rcx, 19
    xor     rax, rax
    mov     rdi, rsp
    rep     stosq
    mov     qword [rsp], SIG_IGN
    mov     rax, SYS_RT_SIGACTION
    mov     rdi, SIGHUP                 ;SIGHUP
    mov     rsi, rsp
    xor     rdx, rdx                    ;oldact
    mov     r10, 128                    ;sigsetsize
    syscall
    add     rsp, 152

; exec command
    mov     rdi, [rbx + 8]
    lea     rsi, [rbx + 8]
    mov     rdx, r13
    mov     rax, SYS_EXECVE
    syscall

    write   STDERR_FILENO, exec_fail, exec_fail_len
    exit    1

.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1
