; src/dirname.asm

%include "include/sysdefs.inc"

section .bss

section .data
    dot         db ".", 0
    newline     db WHITESPACE_NL
    err_msg     db "dirname: missing operand", 10
    err_len     equ $ - err_msg

section .text
    global      _start

_start:
    mov         rsi, rsp
    mov         rdi, [rsi]          ; argc
    cmp         rdi, 2              ; need at least argv[1]
    jl          .missing_operand

    add         rsi, 8              ; skip argc
    add         rsi, 8              ; skip argv[0]
    mov         rsi, [rsi]          ; rsi = argv[1]
    
    call        strlen
    dec         rbx                 ; rbx = strlen - 1
    mov         rcx, rbx

.scan:
    cmp         rcx, 0
    je          .noslash
    cmp         byte [rsi + rcx], '/'
    je          .found
    dec         rcx
    jmp         .scan

.noslash:
    mov         rsi, dot
    mov         rbx, 1
    jmp         .print

.found:
    mov         byte [rsi + rcx], 0
    mov         rbx, rcx
    jmp         .print

.print:
    write       1, rsi, rbx
    write       1, newline, 1
    exit        0

.missing_operand:
    write       2, err_msg, err_len
    exit        1
