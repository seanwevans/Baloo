; src/sync.asm

    %include "include/sysdefs.inc"

section .text
global  _start

_start:
    mov     rax, SYS_SYNC
    syscall

    exit    0
