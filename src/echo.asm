; src/echo.asm

%include "include/sysdefs.inc"

section .bss
    no_newline   resb 1

section .data
    newline     db WHITESPACE_NL

section .text
    global      _start

_start:
    mov         rsi, rsp
    mov         rdi, [rsi]        ; argc
    add         rsi, 8            ; argv[0]
    add         rsi, 8            ; argv[1]
    mov         byte [no_newline], 0
    cmp         rdi, 1
    jle         .done

    mov         rbx, [rsi]        ; first argument
    mov         al, [rbx]
    cmp         al, '-'
    jne         .use_arg
    cmp         byte [rbx + 1], 'n'
    jne         .use_arg
    cmp         byte [rbx + 2], 0
    jne         .use_arg
    mov         byte [no_newline], 1
    add         rsi, 8            ; skip -n
    dec         rdi
.use_arg:
    cmp         rdi, 1
    jl          .maybe_nl
    mov         rsi, [rsi]
    call        strlen
    write       1, rsi, rbx

.maybe_nl:
    cmp         byte [no_newline], 1
    je          .done
    write       1, newline, 1
.done:
    exit        0
