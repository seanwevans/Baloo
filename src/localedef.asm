; src/localedef.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 4096

section .bss
    buffer      resb BUFFER_SIZE

section .data
    usage_msg   db "Usage: localedef -i INPUT -f CHARMAP OUTPUT", WHITESPACE_NL
    usage_len   equ $ - usage_msg

section .text
    global _start

_start:
    pop     rdi                 ; argc
    mov     rsi, rsp            ; argv pointer
    cmp     rdi, 6              ; program + -i INPUT -f CHARMAP OUTPUT
    jne     .usage

    mov     rax, [rsi + 8]      ; argv[1]
    mov     rbx, rax
    cmp     byte [rbx], '-'
    jne     .usage
    cmp     byte [rbx + 1], 'i'
    jne     .usage

    mov     r12, [rsi + 16]     ; INPUT

    mov     rax, [rsi + 24]     ; argv[3]
    mov     rbx, rax
    cmp     byte [rbx], '-'
    jne     .usage
    cmp     byte [rbx + 1], 'f'
    jne     .usage

    mov     r13, [rsi + 32]     ; CHARMAP
    mov     r14, [rsi + 40]     ; OUTPUT

    ; open input file
    mov     rdi, STDIN_FILENO
    mov     rsi, r12
    call    open_file           ; -> rax
    mov     r8, rax             ; input fd

    ; open charmap file (just to verify it exists)
    mov     rdi, STDIN_FILENO
    mov     rsi, r13
    call    open_file
    mov     r9, rax             ; charmap fd

    ; open output file
    mov     rdi, STDOUT_FILENO
    mov     rsi, r14
    call    open_dest_file
    mov     r10, rax            ; output fd

.copy_loop:
    mov     rax, SYS_READ
    mov     rdi, r8
    mov     rsi, buffer
    mov     rdx, BUFFER_SIZE
    syscall
    cmp     rax, 0
    jle     .close_all
    mov     r11, rax
    mov     rax, SYS_WRITE
    mov     rdi, r10
    mov     rsi, buffer
    mov     rdx, r11
    syscall
    jmp     .copy_loop

.close_all:
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    mov     rax, SYS_CLOSE
    mov     rdi, r9
    syscall
    mov     rax, SYS_CLOSE
    mov     rdi, r10
    syscall
    exit    0

.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1
