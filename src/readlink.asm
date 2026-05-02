; src/readlink.asm

    %include "include/sysdefs.inc"

section .bss
    buffer      resb 4096               ;path read from the symlink
    path        resb 4096               ;path argument

section .data
usage_msg   db "Usage: readlink <path>", 10
    usage_len   equ $ - usage_msg
error_msg   db "Error: Failed to read symbolic link", 10
    error_len   equ $ - error_msg
    newline     db WHITESPACE_NL

section .text
global      _start

_start:
    pop         rdi                     ;argc
    cmp         rdi, 2                  ;need one argument
    jne         usage_error

    pop         rsi                     ;Skip program name
    pop         rsi                     ;Get symlink path
    mov         rdi, path
    call        copy_string

    mov         rax, SYS_READLINK
    mov         rdi, path               ;Path to the symlink
    mov         rsi, buffer             ;Where to store the result
    mov         rdx, 4096               ;Maximum size to read
    syscall

    test        rax, rax
    js          error_exit

    mov         rdx, rax                ;Length of the path returned by readlink
    mov         rsi, buffer             ;Buffer containing the path
    mov         rdi, STDOUT_FILENO
    mov         rax, SYS_WRITE
    syscall

    mov         rdi, STDOUT_FILENO
    mov         rsi, newline
    mov         rdx, 1
    mov         rax, SYS_WRITE
    syscall

    xor         rdi, rdi
    mov         rax, SYS_EXIT
    syscall

copy_string:
    push        rdi                     ;Save destination address

copy_loop:
    mov         al, byte [rsi]          ;Load character from source
    mov         byte [rdi], al          ;Store character to destination
    inc         rsi                     ;Move to next source character
    inc         rdi                     ;Move to next destination character
    test        al, al                  ;Check if we reached the end of string
    jnz         copy_loop               ;If not zero, continue copying

    pop         rdi                     ;Restore original destination address
    ret

usage_error:
    mov         rdi, STDERR_FILENO
    mov         rsi, usage_msg
    mov         rdx, usage_len
    mov         rax, SYS_WRITE
    syscall

    exit        1

error_exit:
    mov         rdi, STDERR_FILENO
    mov         rsi, error_msg
    mov         rdx, error_len
    mov         rax, SYS_WRITE
    syscall

    exit        1
