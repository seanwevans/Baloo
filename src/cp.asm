; src/cp.asm

    %include "include/sysdefs.inc"

    %define BUFFER_SIZE 4096
    %define ARG_PTR_SIZE 8

section .bss
    buffer      resb BUFFER_SIZE        ;file data

section .data

section .text
global      _start

_start:
    pop         rcx                     ;argc
    mov         rbp, rsp

    cmp         rcx, 1                  ;If only program name, use stdin/stdout
    je          use_stdio

    cmp         rcx, 2                  ;If only source, use source/stdout
    je          source_only

    cmp         rcx, 3                  ;If source and dest, use both
    je          source_and_dest

    jmp         use_stdio               ;Default to stdin/stdout for any other case

source_only:
    add         rbp, ARG_PTR_SIZE       ;Skip program name
    mov         rsi, [rbp]              ;Get source filename
    mov         rdi, STDIN_FILENO       ;Default source is stdin
    call        open_file               ;Open source file

    mov         r8, rax                 ;Save source fd
    mov         r9, STDOUT_FILENO       ;Destination is stdout
    jmp         copy_loop

source_and_dest:
    add         rbp, ARG_PTR_SIZE       ;Skip program name to point to first arg
    mov         rsi, [rbp]              ;Get source filename pointer
    mov         rdi, STDIN_FILENO       ;Default source is stdin
    call        open_file

    mov         r8, rax                 ;source fd
    add         rbp, ARG_PTR_SIZE       ;Move to next argument
    mov         rsi, [rbp]              ;Get dest filename pointer
    mov         rdi, STDOUT_FILENO      ;Default dest is stdout
    call        open_dest_file

    mov         r9, rax                 ;Save dest fd
    jmp         copy_loop

use_stdio:
    mov         r8, STDIN_FILENO        ;Source is stdin
    mov         r9, STDOUT_FILENO       ;Destination is stdout

copy_loop:
    mov         rax, SYS_READ
    mov         rdi, r8                 ;Source fd
    mov         rsi, buffer             ;Buffer
    mov         rdx, BUFFER_SIZE        ;Buffer size
    syscall

    cmp         rax, 0
    jl          read_error
    je          end_copy                ;End of file

    mov         rdx, rax                ;Bytes read
    mov         rax, SYS_WRITE
    mov         rdi, r9                 ;Destination fd
    mov         rsi, buffer             ;Buffer
    syscall

    cmp         rax, 0
    jl          write_error

    jmp         copy_loop               ;Continue copying

end_copy:
    cmp         r8, STDIN_FILENO
    je          check_dest

    mov         rax, SYS_CLOSE
    mov         rdi, r8
    syscall

check_dest:
    cmp         r9, STDOUT_FILENO
    je          exit_success

    mov         rax, SYS_CLOSE
    mov         rdi, r9
    syscall

exit_success:
    exit        0

read_error:
    write       STDERR_FILENO, error_msg_read, error_msg_read_len
    exit        1

write_error:
    write       STDERR_FILENO, error_msg_write, error_msg_write_len
    exit        2
