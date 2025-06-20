; src/mknod.asm

    %include "include/sysdefs.inc"

    %define S_IFCHR 0o020000
    %define S_IFBLK 0o060000

section .bss

section .data
usage_msg db "Usage: mknod NAME TYPE [MAJOR MINOR]", 10
    usage_len equ $ - usage_msg
error_msg db "Error: mknod failed", 10
    error_len equ $ - error_msg

section .text
global _start

_start:
    pop rcx                             ;argc
    cmp rcx, 3                          ;need at least name and type
    jb usage
    cmp rcx, 5                          ;at most name type major minor
    ja usage

    add rsp, 8                          ;skip program name
    pop r12                             ;name pointer
    pop rbx                             ;type pointer
    mov bl, [rbx]

    cmp bl, 'p'
    je create_fifo
    cmp bl, 'c'
    je create_charblock
    cmp bl, 'b'
    je create_charblock
    jmp usage

create_fifo:
    cmp rcx, 3
    jne usage
    mov rax, SYS_MKNOD
    mov rdi, r12
    mov rsi, S_IFIFO | S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH
    xor rdx, rdx
    syscall
    test rax, rax
    js fail
    exit 0

create_charblock:
    cmp rcx, 5
    jne usage
    pop rdi                             ;major string
    call parse_number
    cmp rax, -1
    je usage
    mov r8, rax
    pop rdi                             ;minor string
    call parse_number
    cmp rax, -1
    je usage
    mov r9, rax

    mov rax, r8
    shl rax, 8
    or  rax, r9
    mov rdx, rax
    mov rdi, r12
    mov rax, SYS_MKNOD
    cmp bl, 'b'
    je .block
    mov rsi, S_IFCHR | S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH
    jmp .call
.block:
    mov rsi, S_IFBLK | S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH
.call:
    syscall
    test rax, rax
    js fail
    exit 0

usage:
    write STDERR_FILENO, usage_msg, usage_len
    exit 1

fail:
    write STDERR_FILENO, error_msg, error_len
    exit 1

parse_number:
    xor rax, rax
    xor rcx, rcx
.loop:
    movzx rdx, byte [rdi+rcx]
    test rdx, rdx
    jz .done
    sub rdx, '0'
    cmp rdx, 9
    ja .error
    imul rax, 10
    add rax, rdx
    inc rcx
    jmp .loop
.done:
    test rcx, rcx
    jz .error
    ret
.error:
    mov rax, -1
    ret

