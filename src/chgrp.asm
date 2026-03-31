; src/chgrp.asm

%include "include/sysdefs.inc"

section .data
    usage_msg       db "Usage: chgrp GROUP FILE", 10
    usage_msg_len   equ $ - usage_msg
    fail_msg        db "Failed to change group", 10
    fail_msg_len    equ $ - fail_msg

section .text
    global          _start

_start:
    mov             rbx, [rsp]              ; argc
    cmp             rbx, 3
    jne             .usage

    mov             rsi, [rsp + 16]         ; argv[1] = group
    call            parse_group
    cmp             eax, -1                 ; parse failure
    je              .usage

    mov             edi, eax                ; gid

    mov             rsi, [rsp + 24]         ; argv[2] = file
    call            chgrp
    
    cmp             rax, 0
    jl              .fail

    exit            0

.usage:
    write           STDOUT_FILENO, usage_msg, usage_msg_len
    exit            1

.fail:
    write           STDERR_FILENO, fail_msg, fail_msg_len
    exit            1

parse_group:
    xor             rax, rax                ; result = 0
    xor             rcx, rcx                ; temp
    xor             rdx, rdx                ; parsed digit count

.parse_loop:
    mov             cl, byte [rsi]
    cmp             cl, 0
    je              .done
    cmp             cl, '0'
    jb              .parse_fail
    cmp             cl, '9'
    ja              .parse_fail
    imul            rax, rax, 10
    sub             cl, '0'
    add             rax, rcx
    inc             rdx
    inc             rsi
    jmp             .parse_loop

.done:
    cmp             rdx, 0
    je              .parse_fail
    ret

.parse_fail:
    mov             eax, -1
    ret

chgrp:
    mov             rax, SYS_CHOWN
    mov             rdi, rsi        ; rdi = filename
    mov             rsi, -1         ; rsi = uid
    mov             edx, edi        ; edx = gid
    syscall
    ret
