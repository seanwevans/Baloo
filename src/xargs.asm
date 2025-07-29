; src/xargs.asm

    %include "include/sysdefs.inc"

    %define BUF_SIZE 8192
    %define MAX_ARGS 256

section .bss
    buffer      resb BUF_SIZE           ;storage for stdin
    arg_list    resq MAX_ARGS + 1       ;pointers to args

section .data
    default_cmd db "/bin/echo", 0
exec_fail   db "xargs: exec failed", WHITESPACE_NL
    exec_fail_len equ $ - exec_fail

section .text
global _start

_start:
    pop     rcx                         ;argc
    mov     rbx, rsp                    ;argv pointer
    lea     r12, [rbx + rcx*8 + 8]      ;envp pointer

    xor     r8, r8                      ;arg counter
    cmp     rcx, 1
    jg      .have_cmd

    lea     rax, [rel default_cmd]
    mov     [arg_list], rax
    inc     r8
    jmp     .read_input

.have_cmd:
    add     rbx, 8                      ;skip prog name
    dec     rcx                         ;remaining args
.copy_loop:
    cmp     rcx, 0
    je      .read_input
    mov     rax, [rbx]
    mov     [arg_list + r8*8], rax
    inc     r8
    add     rbx, 8
    dec     rcx
    jmp     .copy_loop

.read_input:
    xor     r9, r9                      ;bytes read
.read_loop:
    mov     rax, SYS_READ
    mov     rdi, STDIN_FILENO
    lea     rsi, [buffer + r9]
    mov     rdx, BUF_SIZE
    sub     rdx, r9
    syscall
    cmp     rax, 0
    jle     .parse_input
    add     r9, rax
    cmp     r9, BUF_SIZE-1
    jl      .read_loop

.parse_input:
    mov     rsi, buffer
    mov     rcx, r9                     ;total bytes
    xor     rbx, rbx                    ;index
    xor     r10, r10                    ;in_word flag
.parse_loop:
    cmp     rbx, rcx
    je      .done_parse
    mov     al, [rsi + rbx]
    cmp     al, WHITESPACE_SPACE
    je      .separator
    cmp     al, WHITESPACE_NL
    je      .separator
    cmp     al, WHITESPACE_TAB
    je      .separator
    cmp     r10, 1
    je      .store_char
    lea     rax, [rsi + rbx]
    mov     [arg_list + r8*8], rax
    inc     r8
    mov     r10, 1
.store_char:
    inc     rbx
    jmp     .parse_loop

.separator:
    cmp     r10, 1
    jne     .skip_sep
    mov     byte [rsi + rbx], 0
    mov     r10, 0
.skip_sep:
    inc     rbx
    jmp     .parse_loop

.done_parse:
    cmp     r10, 1
    jne     .build_argv
    mov     byte [rsi + rbx], 0

.build_argv:
    mov     qword [arg_list + r8*8], 0  ;null terminator
    mov     rdi, [arg_list]
    mov     rsi, arg_list
    mov     rdx, r12
    mov     rax, SYS_EXECVE
    syscall

    write   STDERR_FILENO, exec_fail, exec_fail_len
    exit    1
