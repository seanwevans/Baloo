; src/write.asm

%include "include/sysdefs.inc"

section .bss
    buffer      resb 4096

section .text
    global _start

_start:
    pop rax                ; argc
    pop rbx                ; argv[0]
    cmp rax, 2
    jne .usage

    pop rdi                ; tty path
    mov rax, SYS_OPEN
    mov rsi, O_WRONLY
    xor rdx, rdx
    syscall

    cmp rax, 0
    jl .fail_open

    mov r12, rax           ; fd

.read_loop:
    mov rax, SYS_READ
    mov rdi, STDIN_FILENO
    mov rsi, buffer
    mov rdx, 4096
    syscall

    test rax, rax
    jle .close_exit

    mov r13, rax           ; bytes read
    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, buffer
    mov rdx, r13
    syscall

    jmp .read_loop

.close_exit:
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall
    exit 0

.usage:
    exit 1

.fail_open:
    exit 2
