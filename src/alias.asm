; src/alias.asm

    %include "include/sysdefs.inc"

section .data
    alias_path db "/tmp/alias.txt", 0
    newline    db 10

section .bss
    buffer     resb 1024

section .text
global _start

_start:
    pop     rdi                         ;argc
    pop     rbx                         ;skip argv[0]
    dec     rdi
    cmp     rdi, 0
    je      list_aliases

; open file for append
    mov     rax, SYS_OPEN
    mov     rdi, alias_path
    mov     rsi, O_WRONLY | O_CREAT | O_APPEND
    mov     rdx, DEFAULT_MODE
    syscall
    cmp     rax, 0
    jl      error_exit
    mov     r12, rax

.write_loop:
    cmp     rdi, 0
    je      .close_write
    pop     rsi                         ;argument string
    call    strlen
    mov     rdx, rbx
    mov     rax, SYS_WRITE
    mov     rdi, r12
    syscall
    mov     rax, SYS_WRITE
    mov     rdi, r12
    mov     rsi, newline
    mov     rdx, 1
    syscall
    dec     rdi
    jmp     .write_loop

.close_write:
    mov     rax, SYS_CLOSE
    mov     rdi, r12
    syscall
    exit    0

list_aliases:
    mov     rax, SYS_OPEN
    mov     rdi, alias_path
    mov     rsi, O_RDONLY
    mov     rdx, 0
    syscall
    cmp     rax, 0
    jl      error_exit
    mov     r12, rax

.read_loop:
    mov     rax, SYS_READ
    mov     rdi, r12
    mov     rsi, buffer
    mov     rdx, 1024
    syscall
    cmp     rax, 0
    jle     .close_read
    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, buffer
    syscall
    jmp     .read_loop

.close_read:
    mov     rax, SYS_CLOSE
    mov     rdi, r12
    syscall
    exit    0

error_exit:
    exit    1
