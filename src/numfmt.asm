; src/numfmt.asm

%include "include/sysdefs.inc"

section .bss
    num_buffer  resb 32                ; Buffer for integer conversion
    unit_buf    resb 1                 ; Buffer for unit suffix

section .data
    decimal_base dq 10
    units       db 0, 'K', 'M', 'G', 'T', 'P', 'E'
    usage_msg   db "Usage: numfmt NUMBER", 10
    usage_len   equ $ - usage_msg
    newline     db WHITESPACE_NL

section .text
    global _start

_start:
    pop rdi                         ; argc
    cmp rdi, 2                      ; expect one argument
    jne print_usage

    pop rax                         ; skip argv[0]
    pop rdi                         ; pointer to number string
    call parse_number               ; rax = number
    call human_format
    exit 0

print_usage:
    write STDOUT_FILENO, usage_msg, usage_len
    exit 1

; rax = number to format
human_format:
    mov rcx, 0                      ; unit index
    mov rbx, 1024
.convert_loop:
    cmp rax, 1024
    jb .done
    xor rdx, rdx
    div rbx                         ; divide by 1024
    inc rcx
    cmp rcx, 6                      ; up to 'E'
    jl .convert_loop
.done:
    push rcx
    call print_int                  ; print number
    pop rcx
    cmp rcx, 0
    je .newline
    mov bl, [units + rcx]
    mov [unit_buf], bl
    write STDOUT_FILENO, unit_buf, 1
.newline:
    write STDOUT_FILENO, newline, 1
    ret

; ---------------------------------------------
; Parse decimal number at [rdi] -> rax
; Supports optional + or - sign
parse_number:
    xor rax, rax
    xor rcx, rcx
    xor r8, r8                      ; sign flag
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
    jb parse_error
    cmp bl, '9'
    ja parse_error
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

parse_error:
    jmp print_usage

; ---------------------------------------------
; Print integer in rax
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
    jne .output
    mov byte [rbx], '-'
    dec rbx
.output:
    inc rbx
    mov rdx, num_buffer
    add rdx, 31
    sub rdx, rbx
    write STDOUT_FILENO, rbx, rdx
    ret
