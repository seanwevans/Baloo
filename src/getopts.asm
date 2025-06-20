; src/getopts.asm

%include "include/sysdefs.inc"

section .data
    msg db "getopts not implemented", 10
    msg_len equ $ - msg

section .text
    global _start

_start:
    write STDOUT_FILENO, msg, msg_len
    exit 1
