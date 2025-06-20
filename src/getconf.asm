; src/getconf.asm

    %include "include/sysdefs.inc"

section .bss
    cpuset      resb 128                ;for NPROCESSORS_ONLN
    numbuf      resb 16

section .data
usage_msg   db "Usage: getconf VARIABLE", 10
    usage_len   equ $ - usage_msg
    pagesize_str db "PAGESIZE", 0
    page_size_str db "PAGE_SIZE", 0
    nproc_str   db "NPROCESSORS_ONLN", 0
    argmax_str  db "ARG_MAX", 0
    newline     db WHITESPACE_NL

section .text
global _start

_start:
    pop rax                             ;argc
    cmp rax, 2
    jne .usage
    pop rdi                             ;skip program name
    pop rdi                             ;variable name

    mov rsi, pagesize_str
    call strcmp
    test rax, rax
    je .print_pagesize

    mov rsi, page_size_str
    call strcmp
    test rax, rax
    je .print_pagesize

    mov rsi, nproc_str
    call strcmp
    test rax, rax
    je .print_nproc

    mov rsi, argmax_str
    call strcmp
    test rax, rax
    je .print_argmax

.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

.print_pagesize:
    mov     rdi, 4096
    call    print_num
    write   STDOUT_FILENO, newline, 1
    exit    0

.print_argmax:
    mov     rdi, 2097152
    call    print_num
    write   STDOUT_FILENO, newline, 1
    exit    0

.print_nproc:
    mov     rax, 204                    ;sched_getaffinity
    mov     rdi, 0
    mov     rsi, 128
    lea     rdx, [rel cpuset]
    syscall
    test    rax, rax
    js      .usage

    xor     rbx, rbx
    mov     rcx, 16
    lea     rsi, [rel cpuset]
.count_loop:
    mov     rax, [rsi]
    popcnt  rax, rax
    add     rbx, rax
    add     rsi, 8
    loop    .count_loop

    mov     rdi, rbx
    call    print_num
    write   STDOUT_FILENO, newline, 1
    exit    0

; print_num: rdi = number
print_num:
    mov     rax, rdi
    mov     rsi, numbuf + 15
    mov     byte [rsi], 0
    mov     rcx, 10
.next_digit:
    xor     rdx, rdx
    div     rcx
    dec     rsi
    add     dl, '0'
    mov     [rsi], dl
    test    rax, rax
    jnz     .next_digit
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rdx, numbuf + 16
    sub     rdx, rsi
    syscall
    ret

; strcmp: rdi = s1, rsi = s2
strcmp:
    push    rcx
    xor     rcx, rcx
.compare_loop:
    mov     al, [rdi + rcx]
    mov     dl, [rsi + rcx]
    cmp     al, dl
    jne     .not_equal
    test    al, al
    jz      .equal
    inc     rcx
    jmp     .compare_loop
.not_equal:
    mov     rax, 1
    pop     rcx
    ret
.equal:
    xor     rax, rax
    pop     rcx
    ret
