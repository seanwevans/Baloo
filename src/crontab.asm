; src/crontab.asm

%include "include/sysdefs.inc"

section .data
    msg db "crontab: not implemented", WHITESPACE_NL
    msg_len equ $ - msg

section .text
    global _start

_start:
    write STDOUT_FILENO, msg, msg_len
    exit 1
