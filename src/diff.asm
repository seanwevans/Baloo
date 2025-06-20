; src/diff.asm

%include "include/sysdefs.inc"

%define LINE_SIZE 1024

section .bss
    line1       resb LINE_SIZE
    line2       resb LINE_SIZE
    fd1         resq 1
    fd2         resq 1
    diff_found  resb 1

section .data
    usage_msg       db "Usage: diff file1 file2", 10
    usage_len       equ $ - usage_msg
    prefix_left     db '< ', 0
    prefix_left_len equ $ - prefix_left
    prefix_right    db '> ', 0
    prefix_right_len equ $ - prefix_right
    newline         db 10

section .text
    global _start

_start:
    pop rcx                          ; argc
    cmp rcx, 3
    jne print_usage

    pop rax                          ; skip program name
    pop rax
    mov [fd1], rax                   ; temporarily store path pointer
    pop rbx
    mov [fd2], rbx                   ; temporarily store path pointer

    ; open first file
    mov rdi, [fd1]
    mov rax, SYS_OPEN
    mov rsi, O_RDONLY
    syscall
    cmp rax, 0
    jl open_error
    mov [fd1], rax

    ; open second file
    mov rdi, [fd2]
    mov rax, SYS_OPEN
    mov rsi, O_RDONLY
    syscall
    cmp rax, 0
    jl open_error2
    mov [fd2], rax

    mov byte [diff_found], 0

main_loop:
    mov rdi, [fd1]
    mov rsi, line1
    call read_line
    mov r8, rax                      ; length of line1 or -1

    mov rdi, [fd2]
    mov rsi, line2
    call read_line
    mov r9, rax                      ; length of line2 or -1

    cmp r8, -1
    je handle_eof1
    cmp r9, -1
    je handle_eof2

    cmp r8, r9
    jne lines_diff
    mov rsi, line1
    mov rdi, line2
    mov rcx, r8
    cld
    repe cmpsb
    jne lines_diff
    jmp main_loop

lines_diff:
    mov byte [diff_found], 1
    mov rsi, line1
    call print_left
    mov rsi, line2
    call print_right
    jmp main_loop

handle_eof1:
    cmp r9, -1
    je done
    mov byte [diff_found], 1
    mov rsi, line2
    call print_right
print_rest2:
    mov rdi, [fd2]
    mov rsi, line2
    call read_line
    cmp rax, -1
    je done
    mov rsi, line2
    call print_right
    jmp print_rest2

handle_eof2:
    cmp r8, -1
    je done
    mov byte [diff_found], 1
    mov rsi, line1
    call print_left
print_rest1:
    mov rdi, [fd1]
    mov rsi, line1
    call read_line
    cmp rax, -1
    je done
    mov rsi, line1
    call print_left
    jmp print_rest1

done:
    cmp byte [diff_found], 0
    jne diff_exit
    exit 0

diff_exit:
    exit 1

print_usage:
    write STDERR_FILENO, usage_msg, usage_len
    exit 2

open_error:
    write STDERR_FILENO, usage_msg, usage_len
    exit 2
open_error2:
    write STDERR_FILENO, usage_msg, usage_len
    exit 2

; rdi = fd, rsi = buffer
; returns rax = length or -1 for EOF
read_line:
    push rdi
    push rsi
    xor rcx, rcx
    mov r8, rsi                    ; buffer start
read_byte:
    mov rdi, [rsp + 8]             ; fd
    mov rsi, r8
    add rsi, rcx
    mov rax, SYS_READ
    mov rdx, 1
    syscall
    cmp rax, 0
    je  .eof
    mov rdi, r8
    add rdi, rcx
    cmp byte [rdi], 10
    je  .done
    inc rcx
    cmp rcx, LINE_SIZE-1
    jge .done
    jmp read_byte
.eof:
    cmp rcx, 0
    jne .done
    pop rsi
    pop rdi
    mov rax, -1
    ret
.done:
    mov rdi, r8
    add rdi, rcx
    mov byte [rdi], 0
    pop rsi
    pop rdi
    mov rax, rcx
    ret

print_left:
    write STDOUT_FILENO, prefix_left, prefix_left_len
    mov rdi, rsi
    call print_line
    ret

print_right:
    write STDOUT_FILENO, prefix_right, prefix_right_len
    mov rdi, rsi
    call print_line
    ret

print_line:
    push rdi
    call strlen
    mov rdx, rax
    pop rdi
    write STDOUT_FILENO, rdi, rdx
    write STDOUT_FILENO, newline, 1
    ret
