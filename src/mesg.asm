; src/mesg.asm

    %include "include/sysdefs.inc"

section .bss
    stat_buf    resb 144                ;struct stat buffer
    mode_tmp    resq 1                  ;temporary mode storage

section .data
    tty_path    db "/dev/tty", 0
usage_msg   db "Usage: mesg [y|n]", WHITESPACE_NL
    usage_len   equ $ - usage_msg
err_msg     db "mesg: tty failure", WHITESPACE_NL
    err_len     equ $ - err_msg
    msg_y       db "is y", WHITESPACE_NL
    msg_y_len   equ $ - msg_y
    msg_n       db "is n", WHITESPACE_NL
    msg_n_len   equ $ - msg_n

section .text
global _start

_start:
    pop     rcx                         ;argc
    pop     rdx                         ;skip argv[0]
    dec     rcx
    cmp     rcx, 0
    je      .show
    cmp     rcx, 1
    jne     .usage

    pop     rdi                         ;argument string
    mov     al, [rdi]
    cmp     al, 'y'
    je      .enable
    cmp     al, 'n'
    je      .disable
    jmp     .usage

.show:
    mov     rax, SYS_STAT
    lea     rdi, [rel tty_path]
    lea     rsi, [stat_buf]
    syscall
    test    rax, rax
    js      .fail
    mov     eax, dword [stat_buf + 24]
    test    eax, S_IWGRP
    jz      .print_n
    jmp     .print_y

.enable:
    mov     rax, SYS_STAT
    lea     rdi, [rel tty_path]
    lea     rsi, [stat_buf]
    syscall
    test    rax, rax
    js      .fail
    mov     eax, dword [stat_buf + 24]
    or      eax, S_IWGRP
    mov     [mode_tmp], rax
    mov     rax, SYS_CHMOD
    lea     rdi, [rel tty_path]
    mov     rsi, [mode_tmp]
    syscall
    test    rax, rax
    js      .fail
    exit    0

.disable:
    mov     rax, SYS_STAT
    lea     rdi, [rel tty_path]
    lea     rsi, [stat_buf]
    syscall
    test    rax, rax
    js      .fail
    mov     eax, dword [stat_buf + 24]
    and     eax, ~S_IWGRP
    mov     [mode_tmp], rax
    mov     rax, SYS_CHMOD
    lea     rdi, [rel tty_path]
    mov     rsi, [mode_tmp]
    syscall
    test    rax, rax
    js      .fail
    exit    0

.print_y:
    write   STDOUT_FILENO, msg_y, msg_y_len
    exit    0

.print_n:
    write   STDOUT_FILENO, msg_n, msg_n_len
    exit    0

.usage:
    write   STDOUT_FILENO, usage_msg, usage_len
    exit    1

.fail:
    write   STDERR_FILENO, err_msg, err_len
    exit    1
