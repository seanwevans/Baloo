; src/timeout.asm

    %include "include/sysdefs.inc"

section .data
usage_msg       db "Usage: timeout SECS COMMAND [ARGS...]", 10
    usage_len       equ $ - usage_msg
exec_err_msg    db "timeout: exec failed", 10
    exec_err_len    equ $ - exec_err_msg

section .text
global _start

_start:
    pop     rax                         ;argc
    mov     rbx, rsp                    ;argv pointer
    mov     r12, rax                    ;save argc
    cmp     rax, 3
    jl      .usage

    mov     rsi, [rbx + 8]              ;argv[1] seconds
    call    str_to_int

    mov     rdi, rax                    ;seconds
    mov     rax, 37                     ;SYS_alarm
    syscall

    lea     rdx, [rbx + r12*8 + 8]      ;env pointer
    mov     rdi, [rbx + 16]             ;command
    lea     rsi, [rbx + 16]             ;argv for command
    mov     rax, SYS_EXECVE
    syscall

    write   STDERR_FILENO, exec_err_msg, exec_err_len
    exit    1

.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

str_to_int:
    xor     rax, rax
    xor     rcx, rcx

.next:
    movzx   rdx, byte [rsi+rcx]
    test    rdx, rdx
    jz      .done
    sub     rdx, '0'
    cmp     rdx, 9
    ja      .done
    imul    rax, rax, 10
    add     rax, rdx
    inc     rcx
    jmp     .next

.done:
    ret
