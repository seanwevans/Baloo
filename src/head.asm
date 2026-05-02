; src/head.asm

    %include "include/sysdefs.inc"

section .data
    default_lines    dq 10              ;Default number of lines to display
    error_msg        db "Error opening file", 10, 0
    error_msg_len    equ $ - error_msg
usage_msg        db "Usage: head [-n NUM] [FILE]", 10, 0
    usage_msg_len    equ $ - usage_msg

section .bss
    buffer          resb 1              ;Single byte buffer
    lines_to_read   resq 1              ;Number of lines to read
    fd              resq 1              ;File descriptor

section .text
global          _start

_start:
    mov             qword [fd], STDIN_FILENO ;Default to stdin
    mov             rax, [default_lines] ;Default to 10 lines
    mov             qword [lines_to_read], rax
    pop             rcx                 ;argc
    cmp             rcx, 1              ;Check if any arguments
    je              read_input          ;No arguments, use defaults

    pop             rax                 ;Skip program name (argv[0])
    dec             rcx
    mov             r12, rcx            ;Save argument count
    mov             r13, rsp            ;Save argument pointer
    xor             r14, r14            ;Flag for -n option (0 = not seen)

parse_args_loop:
    cmp             r12, 0              ;Check if more arguments
    je              read_input          ;No more arguments, start reading

    mov             rdi, [r13]          ;Get next argument
    add             r13, 8              ;Move to next argument pointer
    dec             r12                 ;Decrement argument count
    cmp             byte [rdi], '-'
    jne             open_file_head      ;Not a flag, must be filename

    cmp             byte [rdi + 1], 'n'
    jne             parse_args_loop     ;Not -n flag, skip

    cmp             byte [rdi + 2], 0
    jne             parse_args_loop     ;Not exactly "-n", skip

    mov             r14, 1

    cmp             r12, 0              ;Check if more arguments
    je              error_usage         ;No number argument

    mov             rdi, [r13]          ;Get number argument
    add             r13, 8              ;Move to next argument
    dec             r12                 ;Decrement argument count

    call            atoi

    cmp             rax, 0
    jle             error_usage

    mov             [lines_to_read], rax

    jmp             parse_args_loop

open_file_head:
    mov             rax, SYS_OPEN
    mov             rsi, O_RDONLY
    mov             rdx, 0
    syscall

    cmp             rax, 0
    jl              error_open
    mov             [fd], rax

read_input:
    xor             r12, r12            ;Line counter

read_byte:
    mov             rax, SYS_READ
    mov             rdi, [fd]           ;File descriptor
    mov             rsi, buffer         ;Buffer
    mov             rdx, 1              ;Read 1 byte
    syscall

    cmp             rax, 0
    jle             close_file

    mov             rax, SYS_WRITE
    mov             rdi, STDOUT_FILENO
    mov             rsi, buffer
    mov             rdx, 1              ;Write 1 byte
    syscall

    cmp             byte [buffer], 10   ;10 = newline (LF)
    jne             read_byte           ;Not a newline, continue

    inc             r12
    cmp             r12, [lines_to_read]
    jl              read_byte           ;Not enough lines, continue

    jmp             close_file

close_file:
    cmp             qword [fd], STDIN_FILENO
    je              exit_success

    mov             rax, SYS_CLOSE
    mov             rdi, [fd]
    syscall

exit_success:
    exit            0

error_open:
    write           STDERR_FILENO, error_msg, error_msg_len
    exit            1

error_usage:
    write           STDERR_FILENO, usage_msg, usage_msg_len
    exit            1

atoi:
    xor             rax, rax            ;Initialize result
    xor             rcx, rcx            ;Initialize index

atoi_loop:
    movzx           r9, byte [rdi + rcx] ;Get current character

    test            r9, r9              ;Check for end of string
    jz              atoi_done

    cmp             r9, '0'             ;Check if digit
    jl              atoi_error

    cmp             r9, '9'
    jg              atoi_error

    imul            rax, 10

    sub             r9, '0'             ;Convert ASCII to number
    add             rax, r9

    inc             rcx                 ;Move to next character
    jmp             atoi_loop

atoi_done:
    ret

atoi_error:
    xor             rax, rax
    ret
