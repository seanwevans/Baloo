; src/pinky.asm

    %include "include/sysdefs.inc"

section .bss
    num_buffer  resb 32

section .data
    decimal_base dq 10
    newline db WHITESPACE_NL

section .text
global _start

_start:
    mov rax, SYS_GETEUID
    syscall
    call print_int
    write STDOUT_FILENO, newline, 1
    exit 0

print_int:
    mov rbx, num_buffer
    add rbx, 31
    mov byte [rbx], 0
    dec rbx
    mov rcx, 0
    cmp rax, 0
    jge .convert_digits
    neg rax
    mov rcx, 1
.convert_digits:
    mov rdx, 0
    div qword [decimal_base]
    add dl, '0'
    mov [rbx], dl
    dec rbx
    test rax, rax
    jnz .convert_digits
    cmp rcx, 1
    jne .print_digits
    mov byte [rbx], '-'
    dec rbx
.print_digits:
    inc rbx
    mov rdx, num_buffer
    add rdx, 31
    sub rdx, rbx
    write STDOUT_FILENO, rbx, rdx
    ret
