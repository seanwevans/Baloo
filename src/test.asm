; src/test.asm

    %include "include/sysdefs.inc"

section .bss

section .data
usage_msg   db "Usage: test EXPRESSION", 10
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    pop r12                             ;argc
    cmp r12, 1
    jle return_false

    pop rax                             ;skip argv[0]
    dec r12
    cmp r12, 0
    je return_false

    pop rdi                             ;first argument
    dec r12

    xor ebx, ebx                        ;not flag = 0
    cmp byte [rdi], '!'
    jne .after_not
    cmp byte [rdi+1], 0
    jne .after_not
    mov bl, 1
    cmp r12, 0
    je return_false
    pop rdi
    dec r12
.after_not:
    cmp r12, 0
    je single_arg
    cmp r12, 1
    je two_args
    cmp r12, 2
    je three_args
    jmp return_false

single_arg:
    mov rsi, rdi
    call strlen                         ;length -> rbx
    cmp rbx, 0
    jne result_true
    jmp result_false

two_args:
    pop rsi
    cmp byte [rdi], '-'
    jne invalid
    mov al, [rdi+1]
    cmp al, 'n'
    je op_n
    cmp al, 'z'
    je op_z
    cmp al, 'e'
    je op_e
    jmp invalid

op_n:
    mov rdi, rsi
    call strlen
    cmp rbx, 0
    jne result_true
    jmp result_false

op_z:
    mov rdi, rsi
    call strlen
    cmp rbx, 0
    je result_true
    jmp result_false

op_e:
    mov rax, SYS_ACCESS
    mov rdi, rsi
    mov rsi, F_OK
    syscall
    cmp rax, 0
    je result_true
    jmp result_false

three_args:
    pop rsi                             ;operator
    pop rdx                             ;operand2
    cmp byte [rsi], '='
    je op_eq
    cmp byte [rsi], '!'
    jne .check_dash
    cmp byte [rsi+1], '='
    je op_ne_string
.check_dash:
    cmp byte [rsi], '-'
    jne invalid
    cmp byte [rsi+1], 'e'
    jne .check_ne
    cmp byte [rsi+2], 'q'
    jne invalid
    cmp byte [rsi+3], 0
    jne invalid
; -eq
    mov rdi, rdi                        ;arg1
    call parse_number
    mov r8, rax
    mov rdi, rdx
    call parse_number
    cmp r8, rax
    je result_true
    jmp result_false
.check_ne:
    cmp byte [rsi+1], 'n'
    jne invalid
    cmp byte [rsi+2], 'e'
    jne invalid
    cmp byte [rsi+3], 0
    jne invalid
; -ne
    mov rdi, rdi
    call parse_number
    mov r8, rax
    mov rdi, rdx
    call parse_number
    cmp r8, rax
    jne result_true
    jmp result_false

op_eq:
    mov rsi, rdx
    call strcmp
    test rax, rax
    je result_true
    jmp result_false

op_ne_string:
    mov rsi, rdx
    call strcmp
    test rax, rax
    jne result_true
    jmp result_false

invalid:
    jmp result_false

result_true:
    mov al, 0
    jmp apply_not

result_false:
    mov al, 1
    jmp apply_not

return_false:
    mov al, 1
    jmp apply_not

apply_not:
    test bl, bl
    jz .no_not
    xor al, 1
.no_not:
    movzx edi, al
    mov eax, SYS_EXIT
    syscall

;----------------- helper functions -----------------
strcmp:
    push rcx
    xor rcx, rcx
.str_loop:
    mov al, [rdi+rcx]
    mov dl, [rsi+rcx]
    cmp al, dl
    jne .not_eq
    test al, al
    jz .eq
    inc rcx
    jmp .str_loop
.not_eq:
    mov rax, 1
    pop rcx
    ret
.eq:
    xor rax, rax
    pop rcx
    ret

parse_number:
    xor rax, rax
    xor r8, r8
    movzx rbx, byte [rdi]
    cmp bl, '-'
    jne .check_plus
    mov r8, 1
    inc rdi
    jmp .parse_loop
.check_plus:
    cmp bl, '+'
    jne .parse_loop
    inc rdi
.parse_loop:
    movzx rbx, byte [rdi]
    cmp bl, 0
    je .done
    cmp bl, '0'
    jb .fail
    cmp bl, '9'
    ja .fail
    sub bl, '0'
    imul rax, 10
    add rax, rbx
    inc rdi
    jmp .parse_loop
.done:
    cmp r8, 1
    jne .ret
    neg rax
.ret:
    ret
.fail:
    xor rax, rax
    ret
