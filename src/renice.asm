; src/renice.asm

%include "include/sysdefs.inc"

%define PRIO_PROCESS 0

section .data
    usage_msg   db "Usage: renice PRIORITY PID...", 10
    usage_len   equ $ - usage_msg

section .bss
    newprio     resq 1

section .text
    global _start

_start:
    pop     rcx                     ; argc
    mov     rbx, rsp                ; argv pointer
    cmp     rcx, 3
    jl      .usage
    mov     r14, rcx                ; stable argc tracker

    mov     rdi, [rbx + 8]          ; argv[1] priority
    test    rdi, rdi
    jz      .usage
    call    parse_number
    cmp     rax, -1
    je      .usage
    mov     [newprio], rax

    lea     rbx, [rbx + 16]         ; first pid arg
    sub     r14, 2                  ; number of pids

.next_pid:
    cmp     r14, 0
    je      .done
    mov     rdi, [rbx]
    test    rdi, rdi
    jz      .usage
    call    parse_number
    cmp     rax, -1
    je      .usage
    mov     r10, rax                ; pid
    mov     rax, SYS_SETPRIORITY
    mov     rdi, PRIO_PROCESS
    mov     rsi, r10
    mov     rdx, [newprio]
    syscall
    test    rax, rax
    js      .err
    add     rbx, 8
    dec     r14
    jmp     .next_pid

.done:
    exit    0

.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

.err:
    neg     rax
    exit    rax

; ---------------------------------------------
; Parse signed decimal number at [rdi] -> rax
; Returns -1 on error
parse_number:
    xor     rax, rax
    xor     rcx, rcx                 ; digit count
    xor     r8, r8                   ; sign flag
    movzx   r9, byte [rdi]
    cmp     r9b, '-'
    jne     .check_plus
    mov     r8, 1
    inc     rdi
    jmp     .parse_loop
.check_plus:
    cmp     r9b, '+'
    jne     .parse_loop
    inc     rdi
.parse_loop:
    movzx   r9, byte [rdi]
    cmp     r9b, 0
    je      .finish
    cmp     r9b, '0'
    jb      .error
    cmp     r9b, '9'
    ja      .error
    sub     r9b, '0'
    imul    rax, 10
    add     rax, r9
    inc     rdi
    inc     rcx
    jmp     .parse_loop
.finish:
    test    rcx, rcx
    jz      .error
    cmp     r8, 1
    jne     .ret
    neg     rax
.ret:
    ret
.error:
    mov     rax, -1
    ret
