; src/groups.asm

%include "include/sysdefs.inc"

section .bss
    groups_buf  resd 256        ; buffer for group IDs (32-bit each)
    numbuf      resb 16         ; temporary buffer for printing numbers

section .data
    newline     db 10
    space       db ' '

section .text
    global _start

_start:
    mov     rax, SYS_GETGID
    syscall
    test    rax, rax
    js      .error
    mov     r13, rax            ; primary gid (match id -G ordering)

    mov     rax, SYS_GETEGID
    syscall
    test    rax, rax
    js      .error

    mov     edi, r13d
    call    print_num

    mov     rax, SYS_GETGROUPS
    mov     rdi, 256            ; max groups
    mov     rsi, groups_buf
    syscall

    test    rax, rax
    js      .error

    mov     r12, rax            ; number of supplementary groups
    xor     rbx, rbx            ; index
.next_group:
    cmp     rbx, r12
    je      .done

    mov     r14d, [groups_buf + rbx*4]
    cmp     r14d, r13d
    je      .skip_group

    call    write_space
    mov     edi, r14d
    call    print_num

.skip_group:
    inc     rbx
    jmp     .next_group

.done:
    write   STDOUT_FILENO, newline, 1
    exit    0

.error:
    exit    1

print_num:
    mov     rax, rdi
    mov     rsi, numbuf + 15
    mov     byte [rsi], 0
    mov     r8, 10

.print_loop:
    xor     rdx, rdx
    div     r8
    dec     rsi
    add     dl, '0'
    mov     [rsi], dl
    test    rax, rax
    jnz     .print_loop

    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rdx, numbuf + 15
    sub     rdx, rsi
    syscall
    ret

write_space:
    write   STDOUT_FILENO, space, 1
    ret
