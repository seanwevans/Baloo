; src/cut.asm

    %include "include/sysdefs.inc"

section .bss
    buffer      resb 1                  ;Input buffer
    bytes_limit resq 1                  ;Number of characters to keep per line
    fd          resq 1                  ;File descriptor

section .data
usage_msg   db "Usage: cut -c NUM [FILE]", 10
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    pop rbx                             ;argc
    mov qword [fd], STDIN_FILENO
    pop rax                             ;skip argv[0]
    dec rbx
    cmp rbx, 0
    jle usage

    pop rdi                             ;first arg
    dec rbx
    cmp byte [rdi], '-'
    jne usage
    cmp byte [rdi+1], 'c'
    jne usage

    cmp rbx, 0
    jle usage
    pop rdi                             ;NUM
    dec rbx
    call atoi
    test rax, rax
    jle usage
    mov [bytes_limit], rax

    cmp rbx, 0
    jle process
    pop rsi                             ;FILE
    dec rbx
    mov rdi, STDIN_FILENO
    call open_file
    mov [fd], rax

process:
    xor rcx, rcx                        ;char counter
read_loop:
    mov rax, SYS_READ
    mov rdi, [fd]
    mov rsi, buffer
    mov rdx, 1
    syscall

    cmp rax, 0
    jle done

    movzx rax, byte [buffer]
    cmp al, WHITESPACE_NL
    jne check_print
    mov rcx, 0
    jmp print_char

check_print:
    inc rcx
    mov rdx, [bytes_limit]
    cmp rcx, rdx
    jg read_loop

print_char:
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FILENO
    mov rsi, buffer
    mov rdx, 1
    syscall
    jmp read_loop

done:
    cmp qword [fd], STDIN_FILENO
    je exit_success
    mov rax, SYS_CLOSE
    mov rdi, [fd]
    syscall

exit_success:
    exit 0

usage:
    write STDERR_FILENO, usage_msg, usage_len
    exit 1

; Convert decimal string to integer in rax
atoi:
    xor rax, rax
    xor rcx, rcx
atoi_loop:
    movzx r9, byte [rdi + rcx]
    test r9, r9
    jz atoi_done
    cmp r9, '0'
    jl atoi_error
    cmp r9, '9'
    jg atoi_error
    imul rax, 10
    sub r9, '0'
    add rax, r9
    inc rcx
    jmp atoi_loop
atoi_done:
    ret
atoi_error:
    xor rax, rax
    ret
