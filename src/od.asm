; src/od.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 16

section .bss
    buffer      resb BUFFER_SIZE
    num_buffer  resb 32
    offset      resq 1

section .data
    decimal_base dq 10
    space        db ' '
    newline      db WHITESPACE_NL

section .text
    global _start

_start:
    pop rdi                 ; argc
    pop rsi                 ; argv[0]
    cmp rdi, 1
    jle use_stdin
    pop rsi                 ; filename
    mov rdi, STDIN_FILENO
    call open_file          ; open file or use stdin
    mov r12, rax            ; file descriptor
    jmp read_loop

use_stdin:
    mov r12, STDIN_FILENO

    mov qword [offset], 0

read_loop:
    mov rax, SYS_READ
    mov rdi, r12
    mov rsi, buffer
    mov rdx, BUFFER_SIZE
    syscall
    cmp rax, 0
    jle done

    mov rbx, rax            ; bytes read

    mov rax, [offset]
    call print_int
    write STDOUT_FILENO, space, 1

    xor rcx, rcx
.byte_loop:
    mov al, [buffer + rcx]
    call print_octal_byte
    inc rcx
    cmp rcx, rbx
    jne .byte_loop

    write STDOUT_FILENO, newline, 1
    add qword [offset], rbx
    jmp read_loop

done:
    exit 0

print_octal_byte:
    push rbx
    movzx rbx, al
    mov bl, al
    shr bl, 6
    and bl, 7
    add bl, '0'
    mov [num_buffer], bl

    mov bl, al
    shr bl, 3
    and bl, 7
    add bl, '0'
    mov [num_buffer+1], bl

    mov bl, al
    and bl, 7
    add bl, '0'
    mov [num_buffer+2], bl

    write STDOUT_FILENO, num_buffer, 3
    write STDOUT_FILENO, space, 1
    pop rbx
    ret

print_int:
    push rbx
    push rcx
    push rdx
    mov rbx, num_buffer
    add rbx, 31
    mov byte [rbx], 0
    dec rbx
    mov rcx, 0
    cmp rax, 0
    jge convert_digits
    neg rax
    mov rcx, 1
convert_digits:
    mov rdx, 0
    div qword [decimal_base]
    add dl, '0'
    mov [rbx], dl
    dec rbx
    test rax, rax
    jnz convert_digits
    cmp rcx, 1
    jne print_digits
    mov byte [rbx], '-'
    dec rbx
print_digits:
    inc rbx
    mov rdx, num_buffer
    add rdx, 31
    sub rdx, rbx
    write STDOUT_FILENO, rbx, rdx
    pop rdx
    pop rcx
    pop rbx
    ret
