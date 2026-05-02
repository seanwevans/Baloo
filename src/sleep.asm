; src/sleep.asm

    %include "include/sysdefs.inc"

section .bss
    numbuf      resb 32

section .data
    timespec    dq  0                   ;seconds

section .text
global      _start

_start:
    mov         rbx, [rsp]              ;argc
    cmp         rbx, 2
    jl          .usage

    mov         rsi, [rsp + 16]         ;argv[1]
    call        str_to_int

    mov         [timespec], rax         ;set seconds
    mov         rax, 35                 ;SYS_nanosleep
    mov         rdi, timespec
    xor         rsi, rsi
    syscall

    exit        0

.usage:
    exit        1

str_to_int:
    xor         rax, rax                ;result
    xor         rcx, rcx                ;temp

.next_digit:
    movzx       rcx, byte [rsi]
    test        rcx, rcx
    jz          .done
    sub         rcx, '0'
    cmp         rcx, 9
    ja          .done
    imul        rax, rax, 10
    add         rax, rcx
    inc         rsi
    jmp         .next_digit

.done:
    ret
