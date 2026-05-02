; src/rmdir.asm

    %include "include/sysdefs.inc"

section .bss
    buffer      resb 4096               ;Buffer for directory path

section .data
usage_msg   db "Usage: rmdir <directory_path>", 10
    usage_len   equ $ - usage_msg
error_msg   db "Error: Could not remove directory", 10
    error_len   equ $ - error_msg

section .text
global      _start

_start:
    pop         rdi                     ;Get argc
    cmp         rdi, 2                  ;Should be 2 (program name + dir path)
    jne         print_usage             ;If not, print usage and exit

    pop         rsi                     ;Skip argv[0] (program name)
    pop         rsi                     ;Get argv[1] (directory path)

    mov         rax, SYS_RMDIR          ;rmdir system call number
    mov         rdi, rsi                ;Pass directory path to rdi
    syscall

    test        rax, rax
    js          print_error             ;Jump if sign flag set (negative return = error)

    exit        0

print_usage:
    write       STDOUT_FILENO, usage_msg, usage_len
    exit        1

print_error:
    write       STDERR_FILENO, error_msg, error_len
    exit        1

read_from_stdin:
    mov         rax, SYS_READ
    mov         rdi, STDIN_FILENO
    mov         rsi, buffer
    mov         rdx, 4096
    syscall

    test        rax, rax
    jle         end_of_input

    mov         rcx, rax                ;Save the length
    dec         rcx                     ;Check the last character
    mov         byte [buffer + rcx], 0  ;Null-terminate the string

    mov         rax, SYS_RMDIR
    mov         rdi, buffer
    syscall

    test        rax, rax
    js          print_error

    exit        0

end_of_input:
    exit        1
