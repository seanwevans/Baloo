; src/expr.asm

    %include "include/sysdefs.inc"

section .bss
    num_buffer  resb 32

section .data
    decimal_base dq 10
    newline     db WHITESPACE_NL
usage_msg   db "Usage: expr NUMBER OP NUMBER", WHITESPACE_NL
    usage_len   equ $ - usage_msg
    div_zero_msg db "Division by zero", WHITESPACE_NL
    div_zero_len equ $ - div_zero_msg

section .text
global _start

_start:
    pop rax                             ;argc
    cmp rax, 4
    jne print_usage

    pop rdi                             ;skip program name
    pop rdi                             ;first operand
    call parse_number
    mov rbx, rax                        ;store first number

    pop rdi                             ;operator
    movzx r8, byte [rdi]

    pop rdi                             ;second operand
    call parse_number
    mov rcx, rax                        ;store second number

    mov rax, rbx                        ;prepare result with first number

    cmp r8b, '+'
    je do_add
    cmp r8b, '-'
    je do_sub
    cmp r8b, '*'
    je do_mul
    cmp r8b, '/'
    je do_div

print_usage:
    write STDERR_FILENO, usage_msg, usage_len
    exit 1

do_add:
    add rax, rcx
    jmp print_result

do_sub:
    sub rax, rcx
    jmp print_result

do_mul:
    imul rax, rcx
    jmp print_result

do_div:
    test rcx, rcx
    jz div_zero_error
    xor rdx, rdx
    div rcx
    jmp print_result

div_zero_error:
    write STDERR_FILENO, div_zero_msg, div_zero_len
    exit 1

print_result:
    call print_int
    write STDOUT_FILENO, newline, 1
    exit 0

; ----------------------- helpers -----------------------
parse_number:
    xor rax, rax                        ;result
    xor r8, r8                          ;sign flag

    movzx rbx, byte [rdi]
    cmp bl, '-'
    jne .check_plus
    mov r8, 1
    inc rdi
    jmp .parse_loop
.check_plus:
    cmp bl, '+'
    jne .parse_loop
    inc rdi
.parse_loop:
    movzx rbx, byte [rdi]
    cmp bl, 0
    je .done
    cmp bl, '0'
    jb print_usage
    cmp bl, '9'
    ja print_usage
    sub bl, '0'
    imul rax, 10
    add rax, rbx
    inc rdi
    jmp .parse_loop
.done:
    cmp r8, 1
    jne .ret
    neg rax
.ret:
    ret

print_int:
    mov rbx, num_buffer
    add rbx, 31
    mov byte [rbx], 0
    dec rbx
    mov rcx, 0
    cmp rax, 0
    jge .convert
    neg rax
    mov rcx, 1
.convert:
    mov rdx, 0
    div qword [decimal_base]
    add dl, '0'
    mov [rbx], dl
    dec rbx
    test rax, rax
    jnz .convert
    cmp rcx, 1
    jne .print
    mov byte [rbx], '-'
    dec rbx
.print:
    inc rbx
    mov rdx, num_buffer
    add rdx, 31
    sub rdx, rbx
    write STDOUT_FILENO, rbx, rdx
    ret
