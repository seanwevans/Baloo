; src/cat.asm

    %include "include/sysdefs.inc"

section .bss
    buffer      resb 4096               ;Buffer for reading data
    buffer_size equ 4096                ;Size of the buffer

section .text
global      _start

_start:
    pop         r12                     ;argc
    pop         rdi
    dec         r12
    cmp         r12, 0
    je          read_from_stdin         ;If no arguments, read from stdin

process_arguments:
    cmp         r12, 0                  ;Check if we've processed all arguments
    je          exit_success

    pop         rdi                     ;Get the filename
    call        cat_file                ;Process the file

    dec r12
    jmp         process_arguments

read_from_stdin:
    mov         rdi, STDIN_FILENO
    call        cat_fd
    jmp         exit_success

cat_file:
    mov         rax, SYS_OPEN
    mov         rsi, O_RDONLY
    mov         rdx, 0
    syscall                             ;Open for reading only

    cmp         rax, 0
    jl          error_exit

    mov         rdi, rax                ;Move file descriptor to rdi for cat_fd
    push        r12                     ;Save arg count
    call        cat_fd                  ;Process the opened file

    pop         r12                     ;Restore r12
    mov         rax, SYS_CLOSE
    syscall

    ret

cat_fd:
    push        rdi

read_loop:
    mov         rax, SYS_READ
    pop         rdi                     ;Restore file descriptor
    push        rdi                     ;Save it again for the next iteration
    mov         rsi, buffer             ;Buffer to read into
    mov         rdx, buffer_size        ;Number of bytes to read
    syscall

    cmp         rax, 0                  ;Check if read returned 0 (EOF)
    jle         read_done               ;If <= 0, we're done or there was an error

    mov         rdx, rax                ;Number of bytes to write (from read)
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, buffer             ;Buffer to write from
    syscall

    jmp         read_loop               ;Continue reading

read_done:
    pop         rdi                     ;Clean up the stack
    ret

error_exit:
    exit        1

exit_success:
    exit        0
