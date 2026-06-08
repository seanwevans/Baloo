; src/stty.asm
;
; stty - print terminal line settings.
;
; Supported form
;   stty size    print the terminal's "ROWS COLS" using the TIOCGWINSZ
;                ioctl on standard input
;
; Changing attributes and the full settings display are out of scope; this
; implements the widely-used "size" operand, matching coreutils.

    %include "include/sysdefs.inc"

    %define TIOCGWINSZ 0x5413

section .bss
    winsz       resw 4                  ;struct winsize, four shorts
    numbuf      resb 24

section .data
usage_msg   db "Usage: stty size", 10
    usage_len   equ $ - usage_msg
notty_msg   db "stty: 'standard input': Inappropriate ioctl for device", 10
    notty_len   equ $ - notty_msg
    sizecmd     db "size", 0
    space       db ' '
    newline     db 10

section .text
global _start

_start:
    pop     rbx                         ;argc
    mov     r12, rsp                    ;argv pointer
    cmp     rbx, 2
    jne     usage

    mov     rsi, [r12 + 8]              ;argv[1]
    mov     rdi, sizecmd
    call    streq
    test    rax, rax
    jz      usage

; query the terminal window size on standard input
    mov     rax, SYS_IOCTL
    mov     rdi, STDIN_FILENO
    mov     rsi, TIOCGWINSZ
    mov     rdx, winsz
    syscall
    test    rax, rax
    js      not_a_tty

    movzx   rax, word [winsz]           ;ws_row
    call    print_uint
    write   STDOUT_FILENO, space, 1
    movzx   rax, word [winsz + 2]       ;ws_col
    call    print_uint
    write   STDOUT_FILENO, newline, 1
    exit    0

not_a_tty:
    write   STDERR_FILENO, notty_msg, notty_len
    exit    1

usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

;------------------------------------------------------------------
; streq - compare two NUL-terminated strings, rax = 1 when equal
;------------------------------------------------------------------
streq:
    xor     rcx, rcx
.loop:
    mov     al, [rdi + rcx]
    mov     dl, [rsi + rcx]
    cmp     al, dl
    jne     .ne
    test    al, al
    je      .eq
    inc     rcx
    jmp     .loop
.eq:
    mov     rax, 1
    ret
.ne:
    xor     rax, rax
    ret

;------------------------------------------------------------------
; print_uint - write rax as unsigned decimal to stdout
;------------------------------------------------------------------
print_uint:
    mov     rcx, numbuf + 24            ;one past the end of the buffer
    mov     rbx, 10
.div:
    xor     rdx, rdx
    div     rbx
    add     dl, '0'
    dec     rcx
    mov     [rcx], dl
    test    rax, rax
    jnz     .div

    mov     rdx, numbuf + 24
    sub     rdx, rcx                    ;digit count
    mov     rsi, rcx
    mov     rdi, STDOUT_FILENO
    mov     rax, SYS_WRITE
    syscall
    ret
