; src/mkfifo.asm

    %include "include/sysdefs.inc"

section .bss

section .data
error_msg:      db "Error: Failed to create FIFO", 10
error_len:      equ $ - error_msg
exists_msg:     db "mkfifo: cannot create fifo '", 0
exists_msg_len: equ $ - exists_msg
exists_suffix:  db "': File exists", 10
exists_suffix_len: equ $ - exists_suffix
usage_msg:      db "mkfifo: missing operand", 10, "Try 'mkfifo --help' for more information.", 10
usage_len:      equ $ - usage_msg

section .text
global          _start

_start:
    pop             rcx                 ;argc
    cmp             rcx, 2              ;Need at least 2 (program name + fifo name)
    jl              usage_error         ;If less than 2, show usage message

    add             rsp, 8              ;Skip program name (argv[0])
    pop             rdi                 ;Get argv[1] into rdi (the FIFO name)
    mov             rax, SYS_MKNOD
    mov             rsi, S_IFIFO | S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH ;File type and mode (0666)
    mov             rdx, 0              ;dev_t parameter (not used for FIFOs)
    push            rdi
    syscall

    test            rax, rax
    js              handle_error        ;Jump if sign flag is set (negative result = error)

    exit            0

usage_error:
    write           STDERR_FILENO, usage_msg, usage_len
    exit            1

handle_error:
    pop             rdi

    cmp             rax, -EEXIST        ;Check if error is EEXIST (File exists)
    je              file_exists_error

    write           STDERR_FILENO, error_msg, error_len
    exit            1

file_exists_error:
    push            rdi                 ;Save filename pointer
    write           STDERR_FILENO, exists_msg, exists_msg_len

    pop             rdi
    push            rdi                 ;Save filename pointer again
    mov             rcx, 0              ;Initialize counter

count_loop:
    cmp             byte [rdi + rcx], 0 ;Check for null terminator
    je              count_done

    inc             rcx                 ;Increment counter
    jmp             count_loop

count_done:
    mov             rdx, rcx            ;Move length to rdx for syscall
    mov             rax, SYS_WRITE
    mov             rsi, rdi            ;Source is the filename
    mov             rdi, STDERR_FILENO  ;Destination is stderr
    syscall

    pop             rdi
    write           STDERR_FILENO, exists_suffix, exists_suffix_len
    exit 1
