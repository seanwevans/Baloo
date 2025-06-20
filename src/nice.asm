; src/nice.asm

%include "include/sysdefs.inc"

section .bss
    argc        resq 1
    argv_ptr    resq 1
    env_ptr     resq 1
    adjust      resq 1
    
section .data
    usage_msg       db "Usage: nice [-n adjustment] command [args...]", 10
    usage_len       equ $ - usage_msg
    exec_err_msg    db "Error: execve failed", 10
    exec_err_len    equ $ - exec_err_msg

section .text
    global  _start

_start:
    pop     rax                         ;argc
    mov     [argc], rax
    mov     rbx, rsp                    ;argv pointer
    mov     [argv_ptr], rbx
    lea     rcx, [rbx + rax*8 + 8]      ;env pointer
    mov     [env_ptr], rcx

    cmp     rax, 2
    jl      .usage

    mov     qword [adjust], 10          ;default adjustment
    mov     rdx, rbx
    add     rdx, 8                      ;argv[1]
    mov     rsi, [rdx]
    cmp     byte [rsi], '-'
    jne     .set_cmd
    cmp     byte [rsi+1], 'n'
    jne     .set_cmd
    cmp     byte [rsi+2], 0
    jne     .set_cmd

    cmp     rax, 4
    jl      .usage
    add     rdx, 8                      ;value string
    mov     rdi, [rdx]
    call    parse_number
    cmp     rax, -1
    je      .usage
    mov     [adjust], rax
    add     rdx, 8                      ;command

.set_cmd:
    mov     [argv_ptr], rdx

    mov     rax, SYS_NICE
    mov     rdi, [adjust]
    syscall

    mov     rdi, [rdx]
    mov     rsi, rdx
    mov     rdx, [env_ptr]
    mov     rax, SYS_EXECVE
    syscall

.exec_error:
    write   STDERR_FILENO, exec_err_msg, exec_err_len
    exit    1

.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

parse_number:
    xor     rax, rax
    xor     rcx, rcx

.parse_loop:
    movzx   rdx, byte [rdi+rcx]
    test    rdx, rdx
    jz      .done
    sub     rdx, '0'
    cmp     rdx, 9
    ja      .error
    imul    rax, 10
    add     rax, rdx
    inc     rcx
    jmp     .parse_loop

.done:
    test    rcx, rcx
    jz      .error
    ret

.error:
    mov     rax, -1
    ret
