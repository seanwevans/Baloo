; src/gettext.asm

%include "include/sysdefs.inc"

section .bss

section .data
    newline     db WHITESPACE_NL

section .text
    global _start

_start:
    mov     rsi, rsp
    mov     rdi, [rsi]        ; argc
    add     rsi, 8            ; argv[0]
    add     rsi, 8            ; argv[1]
    cmp     rdi, 1
    jle     .print_nl

    mov     rsi, [rsi]
    call    strlen

    write   STDOUT_FILENO, rsi, rbx

.print_nl:
    write   STDOUT_FILENO, newline, 1
    exit    0

