; src/dircolors.asm

    %include "include/sysdefs.inc"

section .data
msg db "LS_COLORS='di=01;34:ln=01;36:so=01;35:pi=33:bd=01;33:cd=01;33:or=01;31:ex=01;32'", 10, "export LS_COLORS", 10
    msg_len equ $ - msg

section .text
global _start

_start:
    write STDOUT_FILENO, msg, msg_len
    exit 0

