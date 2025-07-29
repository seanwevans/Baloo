; src/wait.asm

%include "include/sysdefs.inc"

%define SYS_WAIT4 61

section .bss
    status  resd 1

section .data
    usage_msg db "Usage: wait [pid]", 10
    usage_len equ $ - usage_msg

section .text
    global _start

_start:
    pop rcx                ; argc
    mov rbp, rsp
    cmp rcx, 1
    je .no_args
    cmp rcx, 2
    je .one_arg
    jmp .usage

.no_args:
    mov rdi, -1            ; wait for any child
    jmp .do_wait

.one_arg:
    mov rdi, [rbp]         ; skip prog name already at rbp?
    ; Actually rbp currently points to argv[0]; so [rbp] -> argv0, we want argv1
    ; Wait: after pop rcx, rbp points to argv0. So we need [rbp+8]
    mov rdi, [rbp+8]
    call str_to_int        ; pid in rax
    mov rdi, rax
    jmp .do_wait

.usage:
    write STDERR_FILENO, usage_msg, usage_len
    exit 1

.do_wait:
    mov rax, SYS_WAIT4
    mov rsi, status
    xor rdx, rdx           ; options = 0
    xor r10, r10           ; rusage = NULL
    syscall
    test rax, rax
    js .error
    mov eax, [status]
    shr eax, 8
    and eax, 0xff
    movzx rax, al
    exit rax

.error:
    neg rax
    exit rax

; Convert string in RDI to integer in RAX (decimal, positive only)
str_to_int:
    xor rax, rax
    xor rcx, rcx
.str_loop:
    movzx rcx, byte [rdi]
    test rcx, rcx
    jz .done
    sub rcx, '0'
    cmp rcx, 9
    ja .done
    imul rax, rax, 10
    add rax, rcx
    inc rdi
    jmp .str_loop
.done:
    ret
