; src/echo.asm

    %include "include/sysdefs.inc"

section .bss
    no_newline   resb 1

section .data
    newline     db WHITESPACE_NL
    space       db " "

section .text
global      _start

_start:
    mov         rsi, rsp
    mov         r12, [rsi]              ;argc
    lea         r13, [rsi + 16]         ;&argv[1]
    mov         byte [no_newline], 0
    dec         r12                     ;operand count = argc - 1
    jle         .maybe_nl               ;no operands -> just a newline

    mov         rbx, [r13]              ;first operand
    cmp         byte [rbx], '-'
    jne         .args_loop
    cmp         byte [rbx + 1], 'n'
    jne         .args_loop
    cmp         byte [rbx + 2], 0
    jne         .args_loop
    mov         byte [no_newline], 1    ;suppress trailing newline (-n)
    add         r13, 8                  ;skip -n
    dec         r12
    jle         .maybe_nl               ;nothing left to print

.args_loop:
    mov         rsi, [r13]
    call        strlen
    write       STDOUT_FILENO, rsi, rbx
    dec         r12
    jz          .maybe_nl               ;last operand -> no trailing space
    write       STDOUT_FILENO, space, 1
    add         r13, 8
    jmp         .args_loop

.maybe_nl:
    cmp         byte [no_newline], 1
    je          .done
    write       STDOUT_FILENO, newline, 1
.done:
    exit        0
