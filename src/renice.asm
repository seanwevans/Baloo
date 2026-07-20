; src/renice.asm -- renice(1): adjust process nice values.
; Usage: renice -n INCREMENT [-p] PID...
;
; -n gives a relative adjustment applied to each process's current nice value
; (getpriority returns 20-nice). Failures on individual PIDs are reported and
; produce a non-zero exit, but the remaining PIDs are still adjusted.

    %include "include/sysdefs.inc"

    %define PRIO_PROCESS 0

section .bss
    pids        resq 256
    npids       resq 1
    nval        resq 1
    had_err     resb 1

section .data
usage_msg   db "Usage: renice -n INCREMENT PID...", WHITESPACE_NL
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    mov     qword [npids], 0
    mov     qword [nval], 0
    mov     byte [had_err], 0

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12
parse:
    cmp     r12, 0
    je      after_parse
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .pid
    cmp     byte [rdi + 1], 0
    je      .pid
    cmp     byte [rdi + 1], 'n'
    je      .setn
jmp     .nextarg                    ;-p/-g/-u: ignore
.setn:
    cmp     byte [rdi + 2], 0
    jne     .n_attached
    add     r13, 8
    dec     r12
    mov     rdi, [r13]
    jmp     .n_parse
.n_attached:
    lea     rdi, [rdi + 2]
.n_parse:
    call    parse_signed
    mov     [nval], rax
    jmp     .nextarg
.pid:
    call    parse_signed
    mov     rcx, [npids]
    mov     [pids + rcx*8], rax
    inc     qword [npids]
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

after_parse:
    cmp     qword [npids], 0
    jne     .apply
    write   STDERR_FILENO, usage_msg, usage_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall
.apply:
    xor     r14, r14
.each:
    cmp     r14, [npids]
    jge     .done
    mov     r15, [pids + r14*8]         ;pid
    mov     rax, SYS_GETPRIORITY
    mov     rdi, PRIO_PROCESS
    mov     rsi, r15
    syscall
    test    rax, rax
    js      .fail
;current nice = 20 - raw; new = nice + inc
    mov     rcx, 20
    sub     rcx, rax
    add     rcx, [nval]
    mov     rax, SYS_SETPRIORITY
    mov     rdi, PRIO_PROCESS
    mov     rsi, r15
    mov     rdx, rcx
    syscall
    test    rax, rax
    js      .fail
    jmp     .next
.fail:
    mov     byte [had_err], 1
.next:
    inc     r14
    jmp     .each
.done:
    movzx   edi, byte [had_err]
    mov     rax, SYS_EXIT
    syscall

; parse_signed: rdi -> signed decimal in rax.
parse_signed:
    xor     rax, rax
    xor     r8, r8
    cmp     byte [rdi], '-'
    jne     .plus
    mov     r8, 1
    inc     rdi
    jmp     .digits
.plus:
    cmp     byte [rdi], '+'
    jne     .digits
    inc     rdi
.digits:
    movzx   ecx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .done
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    inc     rdi
    jmp     .digits
.done:
    test    r8, r8
    jz      .ret
    neg     rax
.ret:
    ret
