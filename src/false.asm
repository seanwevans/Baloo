; src/false.asm

    %include "include/sysdefs.inc"

section .bss

section .data

section .text
global  _start

_start:
    exit    1
