; src/tee.asm
    %include "include/sysdefs.inc"

section .bss
    buffer  resb 4096                   ;I/O buffer

section .text
global  _start

_start:
    mov     rsi, rsp                    ;rsi = stack pointer
    mov     rdi, [rsi]                  ;rdi = argc
    cmp     rdi, 1
    je      .loop_stdio_only            ;./tee (no file) → only stdout

    cmp     rdi, 2
    jne     .usage                      ;only support 0 or 1 arg

    mov     rsi, [rsp + 16]             ;filename
    mov     rax, SYS_OPEN
    mov     rdi, rsi
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, DEFAULT_MODE
    syscall

    test    rax, rax
    js      .fail_open
    mov     r12, rax                    ;file descriptor

.loop:
    mov     rax, SYS_READ
    mov     rdi, STDIN_FILENO
    mov     rsi, buffer
    mov     rdx, 4096
    syscall

    test    rax, rax
    jle     .close_and_exit
    mov     r13, rax                    ;bytes read
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, buffer
    mov     rdx, r13
    syscall

    mov     rax, SYS_WRITE
    mov     rdi, r12
    mov     rsi, buffer
    mov     rdx, r13
    syscall

    jmp     .loop

.loop_stdio_only:
    mov     rax, SYS_READ
    mov     rdi, STDIN_FILENO
    mov     rsi, buffer
    mov     rdx, 4096
    syscall

    test    rax, rax
    jle     .exit

    mov     r13, rax

    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, buffer
    mov     rdx, r13
    syscall

    jmp     .loop_stdio_only

.close_and_exit:
    mov     rax, SYS_CLOSE
    mov     rdi, r12
    syscall

.exit:
    exit    0

.usage:
    exit    1

.fail_open:
    exit    2
