; src/tail.asm

    %include "include/sysdefs.inc"

section .bss
    buffer          resb 65536          ;Buffer for file content (64KB)
    buffer_size     equ 65536           ;Size of buffer
    line_positions  resq 1024           ;Array to store positions of line starts
    fd              resq 1              ;File descriptor
    num_lines       resq 1              ;Number of lines to display
    bytes_read      resq 1              ;Number of bytes read from file
    total_lines     resq 1              ;Total number of lines in file

section .data
    default_lines    dq 10              ;Default number of lines to display
    newline          db 10              ;Newline character (LF)
    error_msg        db "Error", 10, 0
    error_len        equ $ - error_msg

section .text
global          _start

_start:
    mov             qword [fd], STDIN_FILENO
    mov             rax, [default_lines]
    mov             [num_lines], rax
    pop             rcx                 ;argc
    cmp             rcx, 1              ;Check if any arguments
    je              process_file        ;No arguments, use defaults

    pop             rax                 ;Skip program name (argv[0])
    dec             rcx
    jmp             parse_args          ;Start parsing arguments

parse_args:
    test            rcx, rcx
    jz              process_file        ;No more arguments

    pop             rdi
    dec             rcx
    cmp             byte [rdi], '-'
    jne             open_file_tail      ;Not a flag, must be filename

    movzx           rax, byte [rdi + 1]
    cmp             al, 'n'
    je              handle_n_option

    call            is_digit
    jnz             parse_args          ;Not a digit, skip

    lea             rdi, [rdi + 1]      ;Skip dash
    call            parse_number

    mov             [num_lines], rax
    jmp             parse_args          ;Continue parsing

handle_n_option:
    cmp             byte [rdi + 2], 0
    je              handle_separate_n   ;Just -n, number is next argument

    lea             rdi, [rdi + 2]      ;Skip -n
    call            parse_number

    mov             [num_lines], rax
    jmp             parse_args          ;Continue parsing

handle_separate_n:
    test            rcx, rcx            ;Check if there are more arguments
    jz              process_file        ;No more arguments

    pop             rdi
    dec             rcx
    cmp             byte [rdi], '-'
    je              process_file        ;It's another option, not a number

    call            parse_number

    mov             [num_lines], rax
    jmp             parse_args

open_file_tail:
    mov             rax, SYS_OPEN
    mov             rsi, O_RDONLY
    xor             rdx, rdx
    syscall

    cmp             rax, 0
    jl              error

    mov             [fd], rax

process_file:
    mov             rax, SYS_READ
    mov             rdi, [fd]
    mov             rsi, buffer
    mov             rdx, buffer_size
    syscall

    cmp             rax, 0
    jl              error

    mov             [bytes_read], rax
    test            rax, rax
    jz              exit_success

    mov             qword [line_positions], 0
    mov             qword [total_lines], 1
    xor             rcx, rcx            ;Buffer index
    mov             r8, 1               ;Line counter (already counted first line)

scan_loop:
    cmp             rcx, [bytes_read]
    jge             scan_done

    cmp             byte [buffer + rcx], 10
    jne             not_newline

    inc             rcx
    cmp             rcx, [bytes_read]
    jge             scan_done

    mov             [line_positions + r8*8], rcx
    inc             r8

not_newline:
    inc             rcx
    jmp             scan_loop

scan_done:
    mov             [total_lines], r8
    mov             r9, [num_lines]     ;Lines to display
    mov             r10, [total_lines]  ;Total lines in file
    cmp             r9, r10
    jl              calculate_start

    mov             r9, r10             ;Display all lines
    xor             r11, r11            ;Start from first line
    jmp             output_lines

calculate_start:
    mov             r11, r10
    sub             r11, r9             ;Starting line index

output_lines:
    mov             r12, r11            ;Current line index

output_loop:
    cmp             r12, r10            ;Check if reached total lines
    jge             exit_success

    mov             r13, [line_positions + r12*8] ;Start position of current line
    mov             r14, r12
    inc             r14
    cmp             r14, r10            ;Check if this is the last line
    jge             last_line

    mov             r15, [line_positions + r14*8]
    jmp             output_line

last_line:
    mov             r15, [bytes_read]

output_line:
    mov             rdx, r15
    sub             rdx, r13            ;Length = end - start
    mov             rax, SYS_WRITE
    mov             rdi, STDOUT_FILENO
    lea             rsi, [buffer + r13] ;Start position of line
    syscall

    inc             r12
    jmp             output_loop

exit_success:
    cmp             qword [fd], STDIN_FILENO
    je              exit_program

    mov             rax, SYS_CLOSE
    mov             rdi, [fd]
    syscall

exit_program:
    exit            0

error:
    write           STDERR_FILENO, error_msg, error_len
    exit            1

is_digit:
    cmp             al, '0'
    jl              not_digit

    cmp             al, '9'
    jg              not_digit

    test            al, 0               ;Set zero flag without modifying AL
    ret

not_digit:
    or              al, al              ;Clear zero flag without modifying AL
    ret

parse_number:
    xor             rax, rax            ;Initialize result
    xor             rcx, rcx            ;Initialize index
    cmp             byte [rdi], '+'
    jne             check_minus

    inc             rdi                 ;Skip the plus sign

check_minus:
    mov             r9, 0               ;Flag for negative number (0 = positive)
    cmp             byte [rdi], '-'
    jne             parse_digits

    inc             rdi                 ;Skip the minus sign
    mov             r9, 1               ;Set negative flag

parse_digits:
    movzx           rdx, byte [rdi + rcx] ;Get current character
    test            rdx, rdx            ;Check for end of string
    jz              finalize_number

    cmp             rdx, '0'            ;Check if digit
    jl              parse_error

    cmp             rdx, '9'
    jg              parse_error

    imul            rax, 10
    sub             rdx, '0'
    add             rax, rdx
    inc             rcx                 ;Move to next character
    jmp             parse_digits

finalize_number:
    test            r9, r9
    jz              parse_check_zero
    neg             rax                 ;Convert to negative

parse_check_zero:
    test            rax, rax
    jnz             parse_abs

    mov             rax, 10             ;Default to 10 lines
    jmp             parse_exit

parse_abs:
    cmp             rax, 0
    jge             parse_exit

    neg             rax

parse_exit:
    ret

parse_error:
    mov             rax, 10             ;Default to 10 lines on error
    ret
