; src/xargs.asm

    %include "include/sysdefs.inc"

    %define BUF_SIZE 8192
    %define MAX_ARGS 256
    %define PATH_SEPARATOR 58

section .bss
    buffer      resb BUF_SIZE           ;storage for stdin
    arg_list    resq MAX_ARGS + 1       ;pointers to args
    path_buf    resb 4096               ;candidate path for PATH search

section .data
    default_cmd db "echo", 0
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
    call    exec_path

    write   STDERR_FILENO, exec_fail, exec_fail_len
    exit    1

exec_path:
    mov     r13, rdi                    ;command name
    mov     r14, rsi                    ;argv
    mov     r15, rdx                    ;envp

    xor     rcx, rcx
.check_slash:
    mov     al, [r13 + rcx]
    cmp     al, 0
    je      .find_path
    cmp     al, '/'
    je      .exec_direct
    inc     rcx
    jmp     .check_slash

.exec_direct:
    mov     rdi, r13
    mov     rsi, r14
    mov     rdx, r15
    mov     rax, SYS_EXECVE
    syscall
    ret

.find_path:
    mov     rbx, r15
.env_loop:
    mov     rdi, [rbx]
    test    rdi, rdi
    je      .done
    cmp     dword [rdi], 'PATH'
    jne     .next_env
    cmp     byte [rdi + 4], '='
    je      .have_path
.next_env:
    add     rbx, 8
    jmp     .env_loop

.have_path:
    lea     r12, [rdi + 5]

.path_loop:
    mov     al, [r12]
    cmp     al, 0
    je      .done
    lea     rdi, [rel path_buf]
    mov     rbx, rdi

    mov     al, [r12]
    cmp     al, PATH_SEPARATOR
    jne     .copy_dir
    mov     byte [rbx], '.'
    inc     rbx
    jmp     .finish_dir

.copy_dir:
    mov     al, [r12]
    cmp     al, 0
    je      .finish_dir
    cmp     al, PATH_SEPARATOR
    je      .finish_dir
    mov     al, [r12]
    mov     [rbx], al
    inc     rbx
    inc     r12
    lea     rax, [rel path_buf + 4094]
    cmp     rbx, rax
    jae     .skip_component
    jmp     .copy_dir

.finish_dir:
    cmp     rbx, rdi
    je      .empty_component
    mov     al, [rbx - 1]
    cmp     al, '/'
    je      .copy_cmd
    mov     byte [rbx], '/'
    inc     rbx
    jmp     .copy_cmd

.empty_component:
    mov     byte [rbx], '.'
    inc     rbx
    mov     byte [rbx], '/'
    inc     rbx

.copy_cmd:
    xor     rcx, rcx
.copy_cmd_loop:
    mov     al, [r13 + rcx]
    mov     [rbx], al
    cmp     al, 0
    je      .try_exec
    inc     rbx
    inc     rcx
    lea     rax, [rel path_buf + 4095]
    cmp     rbx, rax
    jae     .skip_component
    jmp     .copy_cmd_loop

.try_exec:
    lea     rdi, [rel path_buf]
    mov     rsi, r14
    mov     rdx, r15
    mov     rax, SYS_EXECVE
    syscall

.skip_component:
    mov     al, [r12]
    cmp     al, PATH_SEPARATOR
    jne     .path_loop
    inc     r12
    jmp     .path_loop

.done:
    ret
