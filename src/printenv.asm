; src/printenv.asm

%include "include/sysdefs.inc"

section .bss

section .data
    newline db WHITESPACE_NL
    
section .text
    global  _start

_start:
    mov     rbp, rsp
    mov     rax, [rbp]          ; argc
    lea     r10, [rbp + 8]      ; &argv[0]

    cmp     rax, 1
    je      .setup_envp_only
    cmp     rax, 2
    je      .setup_single_name

    ; Behavior for unsupported usage:
    ; more than one variable name is treated as "not found"/invalid and exits 1.
    exit    1

.setup_single_name:
    mov     r13, [r10 + 8]      ; argv[1] -> NAME
    mov     rsi, r13
    call    strlen
    mov     r14, rbx            ; name length
    mov     rsi, r10
    mov     rdi, [rbp]          ; argc
    jmp     .skip_argv

.setup_envp_only:
    xor     r13, r13            ; no requested NAME

    mov     rsi, r10
    mov     rdi, [rbp]      ; argc
.skip_argv:
    cmp     rdi, 0
    jle     .find_env_null
    add     rsi, 8          ; skip argv[i]
    dec     rdi
    jmp     .skip_argv

.find_env_null:
    add     rsi, 8          ; Skip the argv NULL terminator, rsi now points to envp[0]
    mov     r12, rsi        ; Use r12 as the envp iterator pointer

.loop_env:
    mov     rbx, [r12]      ; envp[i]
    test    rbx, rbx        ; Check if the pointer is NULL
    je      .env_done       ; If NULL, we're done with environment variables

    test    r13, r13
    jz      .print_full

    xor     rcx, rcx
.cmp_name_loop:
    cmp     rcx, r14
    je      .check_equals
    mov     al, [rbx + rcx]
    cmp     al, [r13 + rcx]
    jne     .next_env
    inc     rcx
    jmp     .cmp_name_loop

.check_equals:
    cmp     byte [rbx + r14], '='
    jne     .next_env

    lea     rsi, [rbx + r14 + 1]   ; print only VALUE, not NAME=
    call    strlen
    write   STDOUT_FILENO, rsi, rbx
    write   STDOUT_FILENO, newline, 1
    exit    0

.print_full:
    mov     rsi, rbx
    call    strlen
    write   STDOUT_FILENO, rsi, rbx
    write   STDOUT_FILENO, newline, 1

.next_env:
    add     r12, 8          ; next envp pointer (envp[i+1])
    jmp     .loop_env       ; Repeat

.env_done:
    test    r13, r13
    jnz     .not_found      ; single NAME mode: not found => exit 1 (GNU printenv behavior)
    exit    0

.not_found:
    exit    1
