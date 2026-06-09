; src/dirname.asm

    %include "include/sysdefs.inc"

section .bss

section .data
    dot         db ".", 0
    newline     db WHITESPACE_NL
    slash       db "/"
err_msg     db "dirname: missing operand", 10
    err_len     equ $ - err_msg

section .text
global      _start

_start:
    mov         rsi, rsp
    mov         rdi, [rsi]              ;argc
    cmp         rdi, 2                  ;need at least argv[1]
    jl          .missing_operand

    add         rsi, 8                  ;skip argc
    add         rsi, 8                  ;skip argv[0]
    mov         rsi, [rsi]              ;rsi = argv[1]

    mov         r10, rsi                ;r10 = start of string
    call        strlen                  ;rbx = length
    mov         r11, rbx                ;r11 = original length
    mov         r8, rbx                 ;r8 = end index

.strip_trailing:
    test        r8, r8
    jz          .root_or_dot
    cmp         byte [r10 + r8 - 1], '/'
    jne         .find_slash
    dec         r8
    jmp         .strip_trailing

.root_or_dot:
    test        r11, r11                ;empty operand -> "."
    jz          .dot
    jmp         .root                   ;all-slash operand -> "/"

.find_slash:
    mov         r9, r8                  ;scan back for the last '/'
.scan:
    test        r9, r9
    jz          .dot                    ;no '/' -> "."
    cmp         byte [r10 + r9 - 1], '/'
    je          .strip_mid
    dec         r9
    jmp         .scan

.strip_mid:
    test        r9, r9                  ;drop the trailing separators
    jz          .root                   ;leading '/' only -> "/"
    cmp         byte [r10 + r9 - 1], '/'
    jne         .emit
    dec         r9
    jmp         .strip_mid

.emit:
    write       STDOUT_FILENO, r10, r9
    jmp         .put_nl

.root:
    write       STDOUT_FILENO, slash, 1
    jmp         .put_nl

.dot:
    write       STDOUT_FILENO, dot, 1
    jmp         .put_nl

.put_nl:
    write       STDOUT_FILENO, newline, 1
    exit        0

.missing_operand:
    write       STDERR_FILENO, err_msg, err_len
    exit        1
