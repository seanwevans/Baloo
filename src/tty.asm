; src/tty.asm

    %include "include/sysdefs.inc"

section .bss
    termios_buf resb 32                 ;dummy termios struct
    result_buf  resb 128                ;for readlink result

section .data
    fd_path     db "/proc/self/fd/0", 0
    not_a_tty   db "not a tty", 10
    newline     db WHITESPACE_NL

section .text
global      _start

_start:
    mov         rax, SYS_IOCTL
    mov         rdi, STDIN_FILENO
    mov         rsi, 0x5401             ;TCGETS
    lea         rdx, [termios_buf]
    syscall

    test        rax, rax
    js          .notty                  ;not a tty if ioctl fails

    mov         rax, SYS_READLINK       ;readlink("/proc/self/fd/0") → result_buf
    lea         rdi, [fd_path]
    lea         rsi, [result_buf]
    mov         rdx, 128
    syscall

    test        rax, rax
    js          .notty                  ;should never happen here

    mov         rdi, STDOUT_FILENO
    mov         rsi, result_buf
    mov         rdx, rax                ;bytes read
    mov         rax, SYS_WRITE
    syscall

    write       1, newline, 1
    exit        0

.notty:
    write       1, not_a_tty, 10
    exit        1
