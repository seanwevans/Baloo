; src/truncate.asm -- truncate(1): set a file's size with -s SIZE.
; SIZE accepts a k/m/g suffix and a leading +, -, <, >, / or % modifier
; relative to the current size. The file is created if it does not exist.

    %include "include/sysdefs.inc"

    %define SYS_FSTAT 5

section .bss
    statbuf     resb 160

section .data
usage_msg   db "Usage: truncate -s <size> <file>", 10
    usage_len   equ $ - usage_msg
error_msg   db "truncate: could not truncate file", 10
    error_len   equ $ - error_msg

section .text
global      _start

_start:
    pop         rcx                     ;argc
    cmp         rcx, 4                  ;program + -s + size + file
    jne         print_usage

    pop         rdi                     ;program name (discarded)
    pop         r12                     ;option (must be -s)
    pop         r13                     ;size string
    pop         r14                     ;file

    cmp         byte [r12], '-'
    jne         print_usage
    cmp         byte [r12 + 1], 's'
    jne         print_usage
    cmp         byte [r12 + 2], 0
    jne         print_usage

;open (creating if needed), then fstat for the current size
    mov         rax, SYS_OPEN
    mov         rdi, r14
    mov         rsi, O_RDWR | O_CREAT
    mov         rdx, 0o644
    syscall
    test        rax, rax
    js          error_exit
    mov         r15, rax                ;fd

    mov         rax, SYS_FSTAT
    mov         rdi, r15
    mov         rsi, statbuf
    syscall
    mov         rbx, [statbuf + 48]     ;current size

;parse the size argument -> modifier in r10, magnitude in r11
    mov         rsi, r13
    movzx       r10, byte [rsi]         ;possible modifier
    cmp         r10b, '+'
    je          .mod
    cmp         r10b, '-'
    je          .mod
    cmp         r10b, '<'
    je          .mod
    cmp         r10b, '>'
    je          .mod
    cmp         r10b, '/'
    je          .mod
    cmp         r10b, '%'
    je          .mod
    xor         r10, r10                ;no modifier (absolute)
    jmp         .parse
.mod:
    inc         rsi
.parse:
    call        parse_size              ;rax = magnitude
    mov         r11, rax                ;N

;compute the new size from the modifier
    test        r10, r10
    jz          .absolute
    cmp         r10b, '+'
    je          .add
    cmp         r10b, '-'
    je          .sub
    cmp         r10b, '<'
    je          .atmost
    cmp         r10b, '>'
    je          .atleast
    cmp         r10b, '/'
    je          .rdown
;'%' round up to a multiple of N
    mov         rax, rbx
    add         rax, r11
    dec         rax
    xor         rdx, rdx
    div         r11
    mul         r11
    jmp         .do_truncate
.rdown:
    mov         rax, rbx                ;round down to a multiple of N
    xor         rdx, rdx
    div         r11
    mul         r11
    jmp         .do_truncate
.add:
    mov         rax, rbx
    add         rax, r11
    jmp         .do_truncate
.sub:
    mov         rax, rbx
    sub         rax, r11
    jns         .do_truncate
    xor         rax, rax                ;clamp at zero
    jmp         .do_truncate
.atmost:
    mov         rax, rbx                ;min(current, N)
    cmp         rax, r11
    jbe         .do_truncate
    mov         rax, r11
    jmp         .do_truncate
.atleast:
    mov         rax, rbx                ;max(current, N)
    cmp         rax, r11
    jae         .do_truncate
    mov         rax, r11
    jmp         .do_truncate
.absolute:
    mov         rax, r11

.do_truncate:
    mov         rsi, rax                ;length
    mov         rax, SYS_FTRUNCATE
    mov         rdi, r15
    syscall
    test        rax, rax
    js          error_exit

    mov         rax, SYS_CLOSE
    mov         rdi, r15
    syscall
    exit        0

print_usage:
    write       STDERR_FILENO, usage_msg, usage_len
    exit        1

error_exit:
    write       STDERR_FILENO, error_msg, error_len
    exit        1

; parse_size: rsi -> digits with optional k/m/g suffix; rax = value
parse_size:
    xor         rax, rax
.loop:
    movzx       rcx, byte [rsi]
    cmp         cl, '0'
    jb          .suffix
    cmp         cl, '9'
    ja          .suffix
    imul        rax, rax, 10
    sub         cl, '0'
    add         rax, rcx
    inc         rsi
    jmp         .loop
.suffix:
    or          cl, 0x20                ;fold case
    cmp         cl, 'k'
    je          .k
    cmp         cl, 'm'
    je          .m
    cmp         cl, 'g'
    je          .g
    ret
.k:
    shl         rax, 10
    ret
.m:
    shl         rax, 20
    ret
.g:
    shl         rax, 30
    ret
