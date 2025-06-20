; src/date.asm

%include "include/sysdefs.inc"

section .bss
    num_buffer  resb 32
    digit_buf   resb 2

section .data
    newline     db WHITESPACE_NL
    dash        db '-'
    space       db ' '
    colon       db ':'
    month_len   db 31,28,31,30,31,30,31,31,30,31,30,31

section .text
    global _start

_start:
    ; get current time
    mov     rax, SYS_TIME
    xor     rdi, rdi
    syscall
    mov     rbx, rax                ; seconds since epoch

    ; days and remainder seconds
    mov     rcx, 86400
    xor     rdx, rdx
    div     rcx
    mov     r8, rax                 ; days since epoch
    mov     r9, rdx                 ; seconds in current day

    ; hours
    mov     rax, r9
    mov     rcx, 3600
    xor     rdx, rdx
    div     rcx
    mov     r10, rax                ; hours
    mov     r9, rdx

    ; minutes
    mov     rax, r9
    mov     rcx, 60
    xor     rdx, rdx
    div     rcx
    mov     rbx, rax                ; minutes
    mov     r12, rdx                ; seconds

    ; compute year
    mov     r13, 1970
.year_loop:
    mov     rdi, r13
    call    days_in_year
    cmp     r8, rax
    jb      .got_year
    sub     r8, rax
    inc     r13
    jmp     .year_loop
.got_year:
    mov     rdi, r13
    call    is_leap
    mov     r14, rax                ; leap flag

    ; compute month and day
    xor     rcx, rcx                ; month index
.month_loop:
    movzx   rax, byte [month_len + rcx]
    cmp     rcx, 1
    jne     .chk_days
    test    r14, r14
    jz      .chk_days
    inc     rax                     ; February in leap year
.chk_days:
    cmp     r8, rax
    jb      .got_month
    sub     r8, rax
    inc     rcx
    jmp     .month_loop
.got_month:
    mov     r15, rcx                ; month (0-based)
    mov     r8, r8                  ; day remains in r8 (0-based)

    ; print year
    mov     rax, r13
    call    print_num
    write   STDOUT_FILENO, dash, 1
    mov     rax, r15
    inc     rax                     ; month number
    call    print_two
    write   STDOUT_FILENO, dash, 1
    mov     rax, r8
    inc     rax                     ; day number
    call    print_two
    write   STDOUT_FILENO, space, 1
    mov     rax, r10
    call    print_two
    write   STDOUT_FILENO, colon, 1
    mov     rax, rbx
    call    print_two
    write   STDOUT_FILENO, colon, 1
    mov     rax, r12
    call    print_two
    write   STDOUT_FILENO, newline, 1
    exit    0

; check if year in rdi is leap year, return 1 in rax if leap else 0
is_leap:
    push    rbx
    mov     rbx, rdi
    mov     rax, rbx
    and     rax, 3
    jne     .not
    mov     rax, rbx
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    test    rdx, rdx
    jne     .yes
    mov     rax, rbx
    xor     rdx, rdx
    mov     rcx, 400
    div     rcx
    test    rdx, rdx
    jne     .not
.yes:
    mov     rax, 1
    pop     rbx
    ret
.not:
    xor     rax, rax
    pop     rbx
    ret

; return days in year rdi -> rax
days_in_year:
    call    is_leap
    cmp     rax, 0
    je      .norm
    mov     rax, 366
    ret
.norm:
    mov     rax, 365
    ret

; prints number in rax
print_num:
    push    rbx
    push    rcx
    push    rdx
    mov     rbx, num_buffer
    add     rbx, 31
    mov     byte [rbx], 0
    dec     rbx
    mov     rcx, 10
.print_loop:
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    mov     [rbx], dl
    dec     rbx
    test    rax, rax
    jnz     .print_loop
    inc     rbx
    mov     rdx, num_buffer
    add     rdx, 32
    sub     rdx, rbx
    dec     rdx
    write   STDOUT_FILENO, rbx, rdx
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; prints two-digit number in rax
print_two:
    push    rbx
    push    rcx
    push    rdx
    mov     rcx, 10
    xor     rdx, rdx
    div     rcx
    add     al, '0'
    add     dl, '0'
    mov     [digit_buf], al
    mov     [digit_buf+1], dl
    write   STDOUT_FILENO, digit_buf, 2
    pop     rdx
    pop     rcx
    pop     rbx
    ret
