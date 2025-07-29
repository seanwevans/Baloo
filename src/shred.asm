; src/shred.asm

    %include "include/sysdefs.inc"

section .bss
    stat_buf    resb 144                ;buffer for stat
    zero_buf    resb 4096               ;4k zero buffer
    path_ptr    resq 1                  ;file path pointer
    del_flag    resb 1                  ;delete flag

section .data
usage_msg   db "Usage: shred [-u] FILE", 10
    usage_len   equ $ - usage_msg
err_open    db "Error: open", 10
    err_open_len equ $ - err_open
err_write   db "Error: write", 10
    err_write_len equ $ - err_write
err_unlink  db "Error: unlink", 10
    err_unlink_len equ $ - err_unlink

section .text
global _start

_start:
    pop rcx                             ;argc
    pop rdi                             ;argv[0]
    dec rcx
    cmp rcx, 1
    jl usage

    mov byte [del_flag], 0

    cmp rcx, 2
    jne .single

; two args possible, check for -u
    pop rdi                             ;arg1
    cmp byte [rdi], '-'
    jne usage
    cmp byte [rdi+1], 'u'
    jne usage
    cmp byte [rdi+2], 0
    jne usage
    mov byte [del_flag], 1
    pop rdi                             ;filename
    mov [path_ptr], rdi
    jmp shred_file

.single:
    pop rdi                             ;filename
    mov [path_ptr], rdi

shred_file:
; open file for writing
    mov rax, SYS_OPEN
    mov rsi, O_WRONLY
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl open_error
    mov r12, rax                        ;fd

; stat file to get size
    mov rax, SYS_STAT
    mov rdi, [path_ptr]
    mov rsi, stat_buf
    syscall
    cmp rax, 0
    jl close_error
    mov rbx, [stat_buf + 48]            ;file size

write_loop:
    cmp rbx, 0
    je done_writing
    mov rdx, 4096
    cmp rbx, 4096
    jbe .partial
    jmp .do_write
.partial:
    mov rdx, rbx
.do_write:
    mov rax, SYS_WRITE
    mov rdi, r12
    mov rsi, zero_buf
    syscall
    cmp rax, 0
    jl close_error
    sub rbx, rax
    jmp write_loop

done_writing:
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

    cmp byte [del_flag], 1
    jne exit_success
    mov rax, SYS_UNLINK
    mov rdi, [path_ptr]
    syscall
    cmp rax, 0
    jl unlink_error

exit_success:
    exit 0

usage:
    write STDERR_FILENO, usage_msg, usage_len
    exit 1

open_error:
    write STDERR_FILENO, err_open, err_open_len
    exit 1

close_error:
    write STDERR_FILENO, err_write, err_write_len
    exit 1

unlink_error:
    write STDERR_FILENO, err_unlink, err_unlink_len
    exit 1
