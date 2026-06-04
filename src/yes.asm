; src/yes.asm

    %include "include/sysdefs.inc"

    %define BUF_SIZE 8192

section .bss
    buf     resb BUF_SIZE               ;assembled output line

section .data
    default_msg db "y", 10
    default_len equ $ - default_msg

section .text
global  _start

_start:
    mov     rax, [rsp]                  ;argc
    cmp     rax, 1
    jle     .use_default                ;no operands -> repeat "y"

    lea     r12, [rsp + 16]             ;&argv[1]
    mov     r13, rax
    dec     r13                         ;operand count (argc - 1)
    xor     rbx, rbx                    ;output length / write offset
    xor     r14, r14                    ;current operand index

.next_arg:
    mov     rsi, [r12 + r14*8]          ;argv[1 + r14]
.copy_byte:
    mov     al, [rsi]
    test    al, al
    jz      .arg_copied
    cmp     rbx, BUF_SIZE - 2           ;leave room for separator + newline
    jae     .terminate
    mov     [buf + rbx], al
    inc     rbx
    inc     rsi
    jmp     .copy_byte
.arg_copied:
    inc     r14
    cmp     r14, r13
    jae     .terminate                  ;last operand copied
    cmp     rbx, BUF_SIZE - 2
    jae     .terminate
    mov     byte [buf + rbx], ' '       ;separate operands with a space
    inc     rbx
    jmp     .next_arg

.terminate:
    mov     byte [buf + rbx], 10        ;trailing newline
    inc     rbx

.loop_line:
    write   STDOUT_FILENO, buf, rbx
    jmp     .loop_line

.use_default:
    write   STDOUT_FILENO, default_msg, default_len
    jmp     .use_default
