; src/strings.asm -- strings(1): print printable character runs of at least
; -n N bytes (default 4) from a file or stdin. -f prefixes the file name,
; -o/-t RADIX prefixes each run's byte offset (octal/decimal/hex).

    %include "include/sysdefs.inc"

section .bss
    bytebuf     resb 1
    strbuf      resb 4096
    numbuf      resb 32
    fd          resq 1
    fname       resq 1
    min_len     resq 1
    radix       resq 1
    f_flag      resb 1
    off_flag    resb 1

section .data
usage_msg   db "Usage: strings [-fo] [-n len] [-t radix] [file]", WHITESPACE_NL
    usage_len   equ $ - usage_msg
    nl          db WHITESPACE_NL
colon       db ":"
    space       db " "

section .text
global _start

_start:
    mov     qword [fd], STDIN_FILENO
    mov     qword [fname], 0
    mov     qword [min_len], 4
    mov     qword [radix], 8
    mov     byte [f_flag], 0
    mov     byte [off_flag], 0

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    je      opened
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .file
    cmp     byte [rdi + 1], 0
    je      .file                       ;lone "-" is stdin (a file operand)
    inc     rdi
.char:
    movzx   eax, byte [rdi]
    test    al, al
    je      .next
    cmp     al, 'f'
    je      .set_f
    cmp     al, 'o'
    je      .set_o
    cmp     al, 'n'
    je      .set_n
    cmp     al, 't'
    je      .set_t
    inc     rdi
    jmp     .char
.set_f:
    mov     byte [f_flag], 1
    inc     rdi
    jmp     .char
.set_o:
    mov     byte [off_flag], 1
    mov     qword [radix], 8
    inc     rdi
    jmp     .char
.set_n:
    inc     rdi
    cmp     byte [rdi], 0
    jne     .n_here
    add     r13, 8
    dec     r12
    mov     rdi, [r13]
.n_here:
    call    atou
    mov     [min_len], rax
    jmp     .next
.set_t:
    inc     rdi
    cmp     byte [rdi], 0
    jne     .t_here
    add     r13, 8
    dec     r12
    mov     rdi, [r13]
.t_here:
    mov     byte [off_flag], 1
    movzx   eax, byte [rdi]
    cmp     al, 'd'
    je      .t_dec
    cmp     al, 'x'
    je      .t_hex
    mov     qword [radix], 8            ;'o' or default octal
    jmp     .next
.t_dec:
    mov     qword [radix], 10
    jmp     .next
.t_hex:
    mov     qword [radix], 16
    jmp     .next
.next:
    add     r13, 8
    dec     r12
    jmp     parse
.file:
    mov     [fname], rdi
    cmp     byte [rdi], '-'             ;"-" stays stdin
    jne     .open
    cmp     byte [rdi + 1], 0
    je      .adv
.open:
    mov     rsi, rdi
    mov     rdi, STDIN_FILENO
    call    open_file
    mov     [fd], rax
.adv:
    add     r13, 8
    dec     r12
    jmp     parse

opened:
    xor     r12, r12                    ;current run length
    xor     r14, r14                    ;file offset of next byte
    xor     r15, r15                    ;offset of current run start

read_loop:
    mov     rax, SYS_READ
    mov     rdi, [fd]
    mov     rsi, bytebuf
    mov     rdx, 1
    syscall
    cmp     rax, 0
    jle     eof

    movzx   rax, byte [bytebuf]
    cmp     al, 32
    jl      .nonprint
    cmp     al, 126
    jg      .nonprint
;printable
    test    r12, r12
    jnz     .store
    mov     r15, r14                    ;record run start offset
.store:
    cmp     r12, 4095
    jge     .adv_pos
    mov     byte [strbuf + r12], al
    inc     r12
.adv_pos:
    inc     r14
    jmp     read_loop
.nonprint:
    inc     r14
    call    flush_run
    jmp     read_loop

eof:
    call    flush_run
    cmp     qword [fd], STDIN_FILENO
    je      exit_success
    mov     rax, SYS_CLOSE
    mov     rdi, [fd]
    syscall
exit_success:
    exit    0

; flush_run: emit the current run if it meets the minimum length, then reset
flush_run:
    mov     rax, [min_len]
    cmp     r12, rax
    jl      .reset
    cmp     byte [f_flag], 1
    jne     .maybe_off
    mov     rsi, [fname]
    call    strlen                      ;rbx = length
    write   STDOUT_FILENO, rsi, rbx
    write   STDOUT_FILENO, colon, 1
.maybe_off:
    cmp     byte [off_flag], 1
    jne     .fspace
    cmp     byte [f_flag], 1
    jne     .off_emit
    write   STDOUT_FILENO, space, 1     ;separate filename from offset
.off_emit:
    mov     rdi, r15
    mov     rsi, [radix]
    call    emit_num
    write   STDOUT_FILENO, space, 1
    jmp     .body
.fspace:
    cmp     byte [f_flag], 1
    jne     .body
    write   STDOUT_FILENO, space, 1
.body:
    write   STDOUT_FILENO, strbuf, r12
    write   STDOUT_FILENO, nl, 1
.reset:
    xor     r12, r12
    ret

; emit_num: rdi = value, rsi = radix; write the digits to stdout
emit_num:
    push    rbx
    push    r12
    lea     rcx, [numbuf + 31]
    mov     rax, rdi
    mov     rbx, rsi
.loop:
    xor     rdx, rdx
    div     rbx
    cmp     dl, 10
    jb      .digit
    add     dl, 'a' - 10
    jmp     .store
.digit:
    add     dl, '0'
.store:
    dec     rcx
    mov     [rcx], dl
    test    rax, rax
    jnz     .loop
    lea     rdx, [numbuf + 31]
    sub     rdx, rcx
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, rcx
    syscall
    pop     r12
    pop     rbx
    ret

; atou: rdi -> decimal digits, result in rax
atou:
    xor     rax, rax
.loop:
    movzx   rcx, byte [rdi]
    cmp     cl, '0'
    jb      .done
    cmp     cl, '9'
    ja      .done
    imul    rax, rax, 10
    sub     cl, '0'
    add     rax, rcx
    inc     rdi
    jmp     .loop
.done:
    ret

show_usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1
