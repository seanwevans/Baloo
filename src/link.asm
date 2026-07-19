; src/link.asm

    %include "include/sysdefs.inc"

section .bss
oldpath:    resb 4096       ; source file path
newpath:    resb 4096       ; destination file path
buffer:     resb 4096

section .data
usage_msg:  db "Usage: link oldpath newpath", 10
usage_len:  equ $ - usage_msg
error_msg:  db "Error: link failed", 10
error_len:  equ $ - error_msg

section .text
global      _start

_start:
    pop         rcx                     ;argc
    cmp         rcx, 3                  ;Need program name + oldpath + newpath = 3 args
    je          parse_args              ;If we have correct number of args, parse them

    call        read_paths_from_stdin
    jmp         perform_link            ;After reading paths, perform the link

parse_args:
    pop         rdi
    pop         rdi                     ;Source path argument
    mov         rsi, oldpath            ;Destination buffer
    call        copy_string

    pop         rdi                     ;Destination path argument
    mov         rsi, newpath            ;Destination buffer
    call        copy_string

    jmp         perform_link

read_paths_from_stdin:
    mov         rdi, buffer
    mov         byte [rdi], '>'
    mov         byte [rdi+1], ' '
    mov         byte [rdi+2], 0
    write       STDOUT_FILENO, buffer, 2

    mov         rax, SYS_READ
    mov         rdi, STDIN_FILENO
    mov         rsi, oldpath
    mov         rdx, 4096
    syscall

    mov         rcx, rax                ;Save bytes read count
    lea         rdi, [oldpath+rcx-1]    ;Point to last character (should be newline)
    mov         byte [rdi], 0           ;Replace newline with null terminator

    mov         rdi, buffer
    mov         byte [rdi], '>'
    mov         byte [rdi+1], ' '
    mov         byte [rdi+2], 0
    write       STDOUT_FILENO, buffer, 2

    mov         rax, SYS_READ
    mov         rdi, STDIN_FILENO
    mov         rsi, newpath
    mov         rdx, 4096
    syscall

    mov         rcx, rax                ;Save bytes read count
    lea         rdi, [newpath+rcx-1]    ;Point to last character (should be newline)
    mov         byte [rdi], 0           ;Replace newline with null terminator
    ret

perform_link:
    mov         rax, SYS_LINK
    mov         rdi, oldpath            ;Source path
    mov         rsi, newpath            ;Destination path
    syscall

    test        rax, rax
    js          print_error

    exit        0

print_error:
    write       STDERR_FILENO, error_msg, error_len
    exit        1

copy_string:
    xor         rcx, rcx                ;Clear counter
.loop:
    mov         al, [rdi+rcx]           ;Get character from source
    mov         [rsi+rcx], al           ;Copy to destination
    inc         rcx                     ;Increment counter
    test        al, al                  ;Check if null terminator
    jnz         .loop                   ;If not null, continue loop
    ret
