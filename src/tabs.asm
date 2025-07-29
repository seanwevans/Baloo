; src/tabs.asm

%include "include/sysdefs.inc"

section .data
    clear_cmd  db 0x1b, '[3g', 13
    clear_len  equ $ - clear_cmd
    tab_set    db 0x1b, 'H'
    tab_len    equ $ - tab_set
    spaces8    db '        '
    spaces_len equ $ - spaces8
    cr         db 13

section .text
    global _start

_start:
    ; clear existing tab stops
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FILENO
    mov rsi, clear_cmd
    mov rdx, clear_len
    syscall

    ; set default tabs every 8 columns (11 stops)
    mov rcx, 11
.loop:
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FILENO
    mov rsi, tab_set
    mov rdx, tab_len
    syscall

    mov rax, SYS_WRITE
    mov rdi, STDOUT_FILENO
    mov rsi, spaces8
    mov rdx, spaces_len
    syscall

    loop .loop

    ; return cursor to column 1
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FILENO
    mov rsi, cr
    mov rdx, 1
    syscall

    exit 0
