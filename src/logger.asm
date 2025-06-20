; src/logger.asm

%include "include/sysdefs.inc"

section .data
    log_path    db "/dev/kmsg", 0
    newline     db 10

section .text
    global _start

_start:
    pop rax                 ; argc
    pop rbx                 ; argv[0]
    cmp rax, 2
    jl  .usage

    pop rsi                 ; message string pointer
    mov r13, rsi            ; save pointer

    mov rax, SYS_OPEN
    mov rdi, log_path
    mov rsi, O_WRONLY | O_APPEND
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl  .fail
    mov r12, rax            ; fd

    mov rdi, r13            ; pointer to message
    call strlen             ; length in rbx
    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, r13
    mov rdx, rbx
    syscall

    ; write newline
    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, newline
    mov rdx, 1
    syscall

    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

    exit 0

.usage:
    exit 1

.fail:
    exit 1
