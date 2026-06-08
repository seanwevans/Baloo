; src/read.asm -- read a single line from standard input and echo it.
; Reads one byte at a time so no input past the line is consumed (as a
; shell `read` would behave). Exits 0 once a line is read, 1 on EOF with
; no data.

    %include "include/sysdefs.inc"

    %define LINEBUF_SIZE 65536

section .bss
    linebuf resb LINEBUF_SIZE + 1

section .text
global _start

_start:
    xor     r12, r12                    ;bytes in the line so far
.read_byte:
    mov     rax, SYS_READ
    xor     rdi, rdi                    ;stdin
    lea     rsi, [linebuf + r12]
    mov     rdx, 1
    syscall
    cmp     rax, 1
    jne     .eof
    mov     al, [linebuf + r12]
    cmp     al, 10                      ;end of line
    je      .emit
    inc     r12
    cmp     r12, LINEBUF_SIZE
    jb      .read_byte
.emit:
    mov     byte [linebuf + r12], 10    ;newline-terminate the echoed line
    inc     r12
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, linebuf
    mov     rdx, r12
    syscall
    exit    0
.eof:
    test    r12, r12
    jnz     .emit                       ;final line without a trailing newline
    exit    1
