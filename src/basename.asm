; src/basename.asm

    %include "include/sysdefs.inc"

section .bss

section .data
    nl          db WHITESPACE_NL
err_msg     db "basename: missing operand", 10
    err_len     equ $ - err_msg

section .text
global      _start

_start:
    mov         rsi, rsp
    mov         rdi, [rsi]              ;argc
    cmp         rdi, 2                  ;need at least 1 argument after program name
    jl          missing_operand

    add         rsi, 8                  ;skip argc
    add         rsi, 8                  ;skip argv[0]
    mov         rsi, [rsi]              ;rsi = argv[1]
    call        find_basename

    mov         rbx, rsi
    call        strlen

    write       STDOUT_FILENO, rsi, rbx
    write       STDOUT_FILENO, nl, 1
    exit        0

missing_operand:
    write       STDERR_FILENO, err_msg, err_len
    exit        1

find_basename:
    mov         rbx, rsi

.next:
    cmp         byte [rbx], 0
    je          .done
    cmp         byte [rbx], '/'
    jne         .advance
    mov         rsi, rbx
    inc         rsi

.advance:
    inc         rbx
    jmp         .next

.done:
    ret
