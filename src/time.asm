; src/time.asm

%include "include/sysdefs.inc"

section .bss
    start_ts    resq 2                ; struct timespec for start
    end_ts      resq 2                ; struct timespec for end
    rusage_buf  resb 144              ; struct rusage
    argv_ptr    resq 1
    env_ptr     resq 1
    num_buf     resb 32

section .data
    usage_msg   db "Usage: time command [args...]", 10
    usage_len   equ $ - usage_msg
    exec_err    db "time: exec failed", 10
    exec_err_len equ $ - exec_err
    real_str    db "real ",0
    user_str    db "user ",0
    sys_str     db "sys ",0
    newline     db WHITESPACE_NL

section .text
    global _start

_start:
    pop     rax                 ; argc
    mov     rbx, rsp            ; argv pointer
    lea     r12, [rbx + rax*8 + 8] ; env pointer
    cmp     rax, 2
    jl      .usage
    add     rbx, 8              ; argv[1]
    mov     [argv_ptr], rbx
    mov     [env_ptr], r12

    ; get start time
    mov     rax, SYS_CLOCK_GETTIME
    mov     rdi, CLOCK_MONOTONIC
    mov     rsi, start_ts
    syscall

    ; fork
    mov     rax, SYS_FORK
    syscall
    test    rax, rax
    je      .child
    mov     r12, rax            ; child pid

    ; parent waits
    mov     rax, SYS_WAIT4
    mov     rdi, r12            ; pid
    xor     rsi, rsi            ; status
    xor     rdx, rdx            ; options
    mov     r10, rusage_buf
    syscall

    ; end time
    mov     rax, SYS_CLOCK_GETTIME
    mov     rdi, CLOCK_MONOTONIC
    mov     rsi, end_ts
    syscall

    ; compute and print
    write   STDOUT_FILENO, real_str, 5
    mov     rax, [end_ts]
    sub     rax, [start_ts]
    mov     rdi, rax
    call    print_decimal
    write   STDOUT_FILENO, newline, 1

    write   STDOUT_FILENO, user_str, 5
    mov     rdi, [rusage_buf]
    call    print_decimal
    write   STDOUT_FILENO, newline, 1

    write   STDOUT_FILENO, sys_str, 4
    mov     rdi, [rusage_buf+16]
    call    print_decimal
    write   STDOUT_FILENO, newline, 1

    exit    0

.child:
    mov     rdi, [argv_ptr]
    mov     rsi, [argv_ptr]
    mov     rdx, [env_ptr]
    mov     rdi, [rsi]          ; command path
    mov     rax, SYS_EXECVE
    syscall

    write   STDERR_FILENO, exec_err, exec_err_len
    exit    1

.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

; print_decimal: prints rdi in decimal
print_decimal:
    push    rbx
    cmp     rdi, 0
    jne     .loop_start
    mov     byte [num_buf+31], '0'
    mov     rdx, 1
    mov     rsi, num_buf+31
    mov     rdi, STDOUT_FILENO
    mov     rax, SYS_WRITE
    syscall
    pop     rbx
    ret

.loop_start:
    mov     rsi, num_buf+32
    xor     rcx, rcx
    mov     rax, rdi
    mov     r8, 10

.loop:
    xor     rdx, rdx
    div     r8
    add     rdx, '0'
    dec     rsi
    mov     [rsi], dl
    inc     rcx
    test    rax, rax
    jnz     .loop

    mov     rdi, STDOUT_FILENO
    mov     rax, SYS_WRITE
    mov     rdx, rcx
    syscall

    pop     rbx
    ret
