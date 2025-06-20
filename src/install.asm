; src/install.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 4096

section .bss
    buffer      resb BUFFER_SIZE
    dest_ptr    resq 1

section .data
    usage_msg       db "Usage: install SOURCE DEST", 10
    usage_len       equ $ - usage_msg
    chmod_err_msg   db "install: failed to set permissions", 10
    chmod_err_len   equ $ - chmod_err_msg

section .text
    global _start

_start:
    pop     rcx                 ; argc
    cmp     rcx, 3
    jne     usage_error

    pop     rdi                 ; skip program name

    pop     rsi                 ; source path
    mov     rdi, STDIN_FILENO
    call    open_file
    mov     r8, rax             ; source fd

    pop     rsi                 ; destination path
    mov     [dest_ptr], rsi     ; save for chmod
    mov     rdi, STDOUT_FILENO
    call    open_dest_file
    mov     r9, rax             ; dest fd

copy_loop:
    mov     rax, SYS_READ
    mov     rdi, r8
    mov     rsi, buffer
    mov     rdx, BUFFER_SIZE
    syscall

    cmp     rax, 0
    jl      read_error
    je      copy_done

    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, r9
    mov     rsi, buffer
    syscall
    cmp     rax, 0
    jl      write_error
    jmp     copy_loop

copy_done:
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    mov     rax, SYS_CLOSE
    mov     rdi, r9
    syscall

    mov     rax, SYS_CHMOD
    mov     rdi, [dest_ptr]
    mov     rsi, 0o755
    syscall
    test    rax, rax
    js      chmod_error

    exit    0

usage_error:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

read_error:
    write   STDERR_FILENO, error_msg_read, error_msg_read_len
    exit    1

write_error:
    write   STDERR_FILENO, error_msg_write, error_msg_write_len
    exit    1

chmod_error:
    write   STDERR_FILENO, chmod_err_msg, chmod_err_len
    exit    1
