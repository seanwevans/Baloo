; src/ln.asm

    %include "include/sysdefs.inc"

section .bss
    argc            resq 1              ;Argument count
    argv            resq 1              ;Argument vector
    symlink_flag    resb 1              ;Flag for symbolic link (-s option)
    source_path     resq 1              ;Pointer to source path
    target_path     resq 1              ;Pointer to target path

section .data
usage_msg       db "Usage: ln [-s] source_file target_file", 10, 0
    usage_len       equ $ - usage_msg
error_msg       db "Error: ", 0
    error_len       equ $ - error_msg
    error_no_source db "source file not specified", 10, 0
    error_no_source_len equ $ - error_no_source
    error_no_target     db "target file not specified", 10, 0
    error_no_target_len equ $ - error_no_target
    error_link_failed   db "failed to create link", 10, 0
    error_link_failed_len equ $ - error_link_failed

section .text
global          _start

_start:
    pop             qword [argc]        ;Get argument count
    mov             qword [argv], rsp   ;Save pointer to argument vector
    mov             byte [symlink_flag], 0
    call            parse_args

    cmp             qword [source_path], 0
    je              error_missing_source

    cmp             qword [target_path], 0
    je              error_missing_target

    movzx           rax, byte [symlink_flag]
    test            rax, rax
    jnz             create_symbolic_link

    mov             rax, SYS_LINK       ;link syscall
    mov             rdi, [source_path]  ;source path
    mov             rsi, [target_path]  ;target path
    syscall

    jmp             check_link_result

create_symbolic_link:
    mov             rax, SYS_SYMLINK    ;symlink syscall
    mov             rdi, [source_path]  ;source path
    mov             rsi, [target_path]  ;target path
    syscall

check_link_result:
    test            rax, rax
    js              link_failed

    exit            0

parse_args:
    mov             rcx, [argc]         ;Get argument count
    cmp             rcx, 1              ;Check if only program name is provided
    jle             display_usage       ;If no arguments, display usage

    mov             r8, [argv]          ;Get argument vector
    add             r8, 8               ;Skip program name
    mov             rdi, [r8]           ;Get first argument
    cmp             byte [rdi], '-'     ;Check if it starts with '-'
    jne             no_option

    cmp             byte [rdi+1], 's'   ;Check if it's '-s'
    jne             display_usage       ;If not '-s', display usage

    mov             byte [symlink_flag], 1
    add             r8, 8
    dec             rcx                 ;Decrement argument count

no_option:
    cmp             rcx, 2              ;Need at least 2 arguments (source and target)
    jl              display_usage

    mov             rax, [r8]
    mov             [source_path], rax
    add             r8, 8
    mov             rax, [r8]
    mov             [target_path], rax
    ret

display_usage:
    write           STDERR_FILENO, usage_msg, usage_len
    exit            1

error_missing_source:
    write           STDERR_FILENO, error_msg, error_len
    write           STDERR_FILENO, error_no_source, error_no_source_len
    exit            1

error_missing_target:
    write           STDERR_FILENO, error_msg, error_len
    write           STDERR_FILENO, error_no_target, error_no_target_len
    exit            1

link_failed:
    write           STDERR_FILENO, error_msg, error_len
    write           STDERR_FILENO, error_link_failed, error_link_failed_len
    exit            1
