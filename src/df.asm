; src/df.asm

    %include "include/sysdefs.inc"

section .bss
    fsbuf       resb 128                ;struct statfs buffer
    numbuf      resb 32                 ;buffer for number output

section .data
    path_root   db '/',0
    newline     db WHITESPACE_NL

section .text
global      _start

_start:
    mov         rax, SYS_STATFS
    mov         rdi, path_root          ;path
    mov         rsi, fsbuf              ;buffer
    syscall

    cmp         rax, 0
    jl          .error

    mov         rax, [fsbuf + 32]       ;f_bavail
    mov         rbx, [fsbuf + 8]        ;f_bsize
    mul         rbx                     ;product in rdx rax
    mov         rdi, rax                ;lower 64 bits
    call        print_decimal

    write       STDOUT_FILENO, newline, 1
    exit        0

.error:
    exit        1

print_decimal:
    push        rbx
    cmp         rdi, 0
    jne         .pd_loop_start
    mov         byte [numbuf + 31], '0'
    mov         rdx, 1
    mov         rsi, numbuf + 31
    mov         rdi, STDOUT_FILENO
    mov         rax, SYS_WRITE
    syscall
    pop         rbx
    ret

.pd_loop_start:
    mov         rsi, numbuf + 32
    xor         rcx, rcx
    mov         rax, rdi
    mov         r8, 10

.pd_loop:
    xor         rdx, rdx
    div         r8
    add         rdx, '0'
    dec         rsi
    mov         [rsi], dl
    inc         rcx
    test        rax, rax
    jnz         .pd_loop

    mov         rdi, STDOUT_FILENO
    mov         rax, SYS_WRITE
    mov         rdx, rcx
    syscall

    pop         rbx
    ret
