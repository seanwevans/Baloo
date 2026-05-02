; src/arch.asm

    %include "include/sysdefs.inc"

section .bss
    uts     resb 390                    ;struct utsname

section .data
    nl      db WHITESPACE_NL

section .text
global  _start

_start:
    mov     rax, SYS_UNAME
    mov     rdi, uts
    syscall

    lea     rsi, [uts + 260]            ;.machine field
    call    strlen

    write   STDOUT_FILENO, rsi, rbx
    write   STDOUT_FILENO, nl, 1
    exit    0
