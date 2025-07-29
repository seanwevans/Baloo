; src/getopts.asm

%include "include/sysdefs.inc"

section .bss
    printed_flag    resb 1
    charbuf         resb 1

section .data
    usage_msg   db "Usage: getopts OPTSTRING [ARGS...]", 10
    usage_len   equ $ - usage_msg
    space_char  db ' '
    dash_char   db '-'
    dashdash    db '--', ' ', 0
    newline     db 10

section .text
    global _start

_start:
    pop rcx                     ; argc
    cmp rcx, 2
    jb  usage                   ; need at least OPTSTRING

    pop rax                     ; skip program name
    pop r14                     ; optstring
    dec rcx                     ; remaining arg count
    mov r13, rsp                ; pointer to args
    mov byte [printed_flag], 0

next_arg:
    cmp rcx, 0
    je  finish
    mov rbx, [r13]
    add r13, 8
    dec rcx

    cmp byte [rbx], '-'
    jne non_option
    cmp byte [rbx+1], 0
    je  non_option
    cmp byte [rbx+1], '-'
    jne short_opt
    cmp byte [rbx+2], 0
    jne short_opt

    ; handle "--" terminator
    call emit_space
    write STDOUT_FILENO, dashdash, 3
    jmp print_remaining

short_opt:
    mov rsi, rbx
    inc rsi                     ; point to first option char
opt_char_loop:
    mov bl, [rsi]
    test bl, bl
    jz  next_arg

    mov rdi, r14                ; optstring
    mov dl, bl
    call find_option
    test rax, rax
    jz  usage                   ; invalid option

    call emit_space
    mov dil, '-'
    call write_ch
    mov dil, bl
    call write_ch

    cmp byte [rax+1], ':'       ; requires argument?
    jne no_argument

    inc rsi
    mov rdx, rsi                ; possible attached argument
    mov bl, [rdx]
    test bl, bl
    jnz have_arg_same

    cmp rcx, 0
    je  usage                   ; missing argument
    mov rdx, [r13]
    add r13, 8
    dec rcx
have_arg_same:
    mov dil, ' '
    call write_ch
    mov rdi, rdx
    call write_str
    jmp next_arg

no_argument:
    inc rsi
    jmp opt_char_loop

non_option:
    call emit_space
    write STDOUT_FILENO, dashdash, 3
    mov rdi, rbx
    call write_str
    jmp print_remaining

print_remaining:
    ; print rest of arguments
print_loop:
    cmp rcx, 0
    je done
    mov rbx, [r13]
    add r13, 8
    dec rcx
    mov dil, ' '
    call write_ch
    mov rdi, rbx
    call write_str
    jmp print_loop

done:
    mov dil, 10
    call write_ch
    exit 0

finish:
    mov dil, 10
    call write_ch
    exit 0

usage:
    write STDERR_FILENO, usage_msg, usage_len
    exit 1

;-----------------------------------------
; rdi = optstring pointer
; dl  = option character to find
; returns rax = pointer to match or 0
find_option:
    push rcx
    xor rcx, rcx
fo_loop:
    mov al, [rdi + rcx]
    test al, al
    jz fo_not_found
    cmp al, dl
    je fo_found
    inc rcx
    jmp fo_loop
fo_found:
    lea rax, [rdi + rcx]
    pop rcx
    ret
fo_not_found:
    xor rax, rax
    pop rcx
    ret

;-----------------------------------------
; print space if not first token
emit_space:
    cmp byte [printed_flag], 0
    je set_flag
    write STDOUT_FILENO, space_char, 1
set_flag:
    mov byte [printed_flag], 1
    ret

;-----------------------------------------
; write character in dil
write_ch:
    mov [charbuf], dil
    write STDOUT_FILENO, charbuf, 1
    ret

;-----------------------------------------
; write null terminated string at rdi
write_str:
    mov rsi, rdi
    call strlen                ; length -> rbx
    write STDOUT_FILENO, rsi, rbx
    ret

