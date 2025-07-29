; src/csplit.asm

%include "include/sysdefs.inc"

section .bss
    buffer       resb 1            ; byte buffer
    in_fd        resq 1
    out_fd       resq 1
    line_count   resq 1
    split_after  resq 1

section .data
    file1        db "xaa", 0
    file2        db "xab", 0
    usage_msg    db "Usage: csplit FILE NUM", 10
    usage_len    equ $ - usage_msg

section .text
    global _start

_start:
    pop     rbx                     ; argc
    cmp     rbx, 3
    jne     usage

    pop     rax                     ; skip program name
    pop     rsi                     ; filename
    mov     rdi, STDIN_FILENO
    call    open_file               ; -> rax
    mov     [in_fd], rax

    pop     rdi                     ; NUM
    call    atoi                    ; -> rax
    test    rax, rax
    jle     usage
    mov     [split_after], rax

    mov     rdi, STDOUT_FILENO
    mov     rsi, file1
    call    open_dest_file          ; -> rax
    mov     [out_fd], rax
    xor     rcx, rcx
    mov     [line_count], rcx

read_loop:
    mov     rax, SYS_READ
    mov     rdi, [in_fd]
    mov     rsi, buffer
    mov     rdx, 1
    syscall
    test    rax, rax
    jle     finish

    mov     rax, SYS_WRITE
    mov     rdi, [out_fd]
    mov     rsi, buffer
    mov     rdx, 1
    syscall

    cmp     byte [buffer], 10
    jne     read_loop

    inc     qword [line_count]
    mov     rax, [split_after]
    cmp     qword [line_count], rax
    jne     read_loop

    ; switch to second file
    mov     rax, SYS_CLOSE
    mov     rdi, [out_fd]
    syscall
    mov     rdi, STDOUT_FILENO
    mov     rsi, file2
    call    open_dest_file
    mov     [out_fd], rax
    jmp     read_loop

finish:
    cmp     qword [in_fd], STDIN_FILENO
    je      .close_out
    mov     rax, SYS_CLOSE
    mov     rdi, [in_fd]
    syscall
.close_out:
    mov     rax, SYS_CLOSE
    mov     rdi, [out_fd]
    syscall
    exit    0

usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

; atoi: rdi -> number, returns rax
atoi:
    xor     rax, rax
    xor     rcx, rcx
atoi_loop:
    movzx   r9, byte [rdi + rcx]
    test    r9, r9
    jz      atoi_done
    cmp     r9, '0'
    jl      atoi_err
    cmp     r9, '9'
    jg      atoi_err
    imul    rax, 10
    sub     r9, '0'
    add     rax, r9
    inc     rcx
    jmp     atoi_loop
atoi_done:
    ret
atoi_err:
    xor     rax, rax
    ret
