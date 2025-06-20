; src/newgrp.asm

    %include "include/sysdefs.inc"

section .bss
    env_ptr     resq 1

section .data
usage_msg       db "Usage: newgrp GROUP [COMMAND...]", 10
    usage_len       equ $ - usage_msg
setgid_fail_msg db "Error: setgid failed", 10
    setgid_fail_len equ $ - setgid_fail_msg
exec_fail_msg   db "Error: execve failed", 10
    exec_fail_len   equ $ - exec_fail_msg
    shell_path      db "/bin/sh", 0

section .text
global _start

_start:
    pop r10                             ;argc
    cmp r10, 2
    jl usage_error

    mov rbx, rsp                        ;argv pointer
    lea r11, [rbx + r10*8 + 8]
    mov [env_ptr], r11                  ;save envp

    mov rdi, [rbx + 8]                  ;argv[1] = group
    call parse_group
    mov edi, eax                        ;gid

    mov rax, SYS_SETGID
    syscall
    test rax, rax
    js setgid_error

    cmp r10, 2
    jg exec_command

    sub rsp, 24                         ;space for argv[0], argv[1], NULL
    mov rdi, shell_path
    mov [rsp], rdi
    mov qword [rsp+8], 0
    mov rsi, rsp
    mov rdx, [env_ptr]
    mov rax, SYS_EXECVE
    syscall
    jmp exec_error

exec_command:
    add rbx, 16                         ;skip argv[0] and group
    mov rsi, rbx                        ;argv array for command
    mov rdi, [rbx]                      ;command path
    mov rdx, [env_ptr]
    mov rax, SYS_EXECVE
    syscall
    jmp exec_error

usage_error:
    write STDOUT_FILENO, usage_msg, usage_len
    exit 1

setgid_error:
    write STDERR_FILENO, setgid_fail_msg, setgid_fail_len
    exit 1

exec_error:
    write STDERR_FILENO, exec_fail_msg, exec_fail_len
    exit 1

parse_group:
    xor rax, rax
    xor rcx, rcx

.parse_loop:
    mov cl, byte [rdi]
    cmp cl, 0
    je .done
    sub cl, '0'
    cmp cl, 9
    ja .done
    imul rax, rax, 10
    add rax, rcx
    inc rdi
    jmp .parse_loop
.done:
    ret
