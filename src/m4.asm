; src/m4.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 4096

section .bss
    buffer  resb BUFFER_SIZE

section .text
    global _start

_start:
read_loop:
    mov rax, SYS_READ
    mov rdi, STDIN_FILENO
    mov rsi, buffer
    mov rdx, BUFFER_SIZE
    syscall
    cmp rax, 0
    jle  .done
    mov rdx, rax
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FILENO
    mov rsi, buffer
    syscall
    jmp read_loop

.done:
    cmp rax, 0
    jl  .error
    exit 0

.error:
    exit 1
