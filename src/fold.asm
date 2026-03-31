; src/fold.asm

%include "include/sysdefs.inc"

section .bss
    buffer      resb 4096   ; Input buffer
    output_buf  resb 1      ; Single character output buffer
    width       resq 1      ; Width to fold at
    num_buf     resb 32     ; Buffer for number conversion
    filename    resq 1      ; Pointer to filename
    fd          resq 1      ; File descriptor
    column      resq 1      ; Current column position

section .data
    default_width   dq 80   ; Default width for folding
    help_msg    db "Usage: fold [-w WIDTH] [FILE]", 10, "Wrap input lines to fit specified width (default: 80).", 10, 0
    help_len    equ $ - help_msg
    error_msg   db "Error: Invalid width specified", 10, 0
    error_len   equ $ - error_msg
    newline     db WHITESPACE_NL
    
section .text
    global      _start

_start:
    mov         rax, [default_width]
    mov         [width], rax
    mov         qword [column], 0
    mov         qword [fd], STDIN_FILENO
    pop         r12                 ; argc
    cmp         r12, 1              ; If argc == 1, use stdin
    je          process_input
    
    pop         rax                 ; skip program name
    dec         r12

parse_args:
    cmp         r12, 0              ; No more arguments
    je          open_file_fold

    pop         rax                 ; Get next argument
    test        rax, rax            ; Defensive: null argv pointer
    jz          show_help
    dec         r12
    cmp         byte [rax], '-'     ; Check if it's an option
    jne         store_filename      ; If not, assume it's a filename

    cmp         byte [rax+1], 'w'   ; Check if it's -w
    jne         check_help          ; If not, check if it's help
    
    cmp         byte [rax+2], 0     ; Check if it's just -w or -wNUMBER
    je          get_width_arg       ; If -w alone, next arg is width

    add         rax, 2              ; Skip to the number part
    call        atoi
    
    cmp         rax, 0              ; Check if width <= 0
    jle         show_error
    
    mov         [width], rax
    jmp         parse_args
    
get_width_arg:
    cmp         r12, 0              ; Check if there's another argument
    je          show_help           ; If not, show help

    pop         rax                 ; Get the width argument
    test        rax, rax            ; Defensive: null argv pointer
    jz          show_help
    dec         r12
    call        atoi
    
    cmp         rax, 0              ; Check if width <= 0
    jle         show_error
    
    mov         [width], rax
    jmp         parse_args

check_help:
    cmp         byte [rax+1], 'h'
    je          show_help
    
    mov         r8, rax             ; Save pointer to arg
    cmp         byte [r8], '-'      ; Check first char
    jne         parse_args
    
    inc         r8
    cmp         byte [r8], '-'      ; Check second char
    jne         parse_args
    
    inc         r8
    cmp         byte [r8], 'h'      ; Check 'h'
    jne         parse_args
    
    inc         r8
    cmp         byte [r8], 'e'      ; Check 'e'
    jne         parse_args
    
    inc         r8
    cmp         byte [r8], 'l'      ; Check 'l'
    jne         parse_args
    
    inc         r8    
    cmp         byte [r8], 'p'      ; Check 'p'
    jne         parse_args
    
    jmp         show_help           ; If --help, show help
    
store_filename:
    mov         [filename], rax
    jmp         parse_args

open_file_fold:
    cmp         qword [filename], 0
    je          process_input       ; If not, use stdin

    mov         rax, SYS_OPEN
    mov         rdi, [filename]     ; Filename
    mov         rsi, O_RDONLY       ; Read-only mode
    xor         rdx, rdx            ; No permissions needed for reading
    syscall

    test        rax, rax
    js          exit_program        ; If negative, error occurred

    mov         [fd], rax

process_input:
read_loop:
    mov         rax, SYS_READ
    mov         rdi, [fd]           ; File descriptor
    mov         rsi, buffer
    mov         rdx, 4096
    syscall

    test        rax, rax            ; Check if EOF or error
    jle         cleanup             ; If EOF or error, clean up

    mov         r13, rax            ; Store bytes read
    xor         r14, r14            ; Buffer position

process_chars:
    cmp         r14, r13            ; Check if we've processed all bytes
    jge         read_loop           ; If yes, read more

    mov         al, [buffer + r14]  ; Get next character
    inc         r14
    cmp         al, 10              ; '\n'
    je          output_newline

    mov         [output_buf], al
    write       STDOUT_FILENO, output_buf, 1

    inc         qword [column]
    mov         rax, [column]
    cmp         rax, [width]
    jl          process_chars       ; If not, continue

    mov         byte [output_buf], 10
    write       STDOUT_FILENO, output_buf, 1
    mov         qword [column], 0   ; Reset column counter
    jmp         process_chars

output_newline:
    mov         byte [output_buf], 10
    write       STDOUT_FILENO, output_buf, 1
    mov         qword [column], 0   ; Reset column counter
    jmp         process_chars

cleanup:
    cmp         qword [fd], STDIN_FILENO
    je          exit_program
    
    mov         rax, SYS_CLOSE
    mov         rdi, [fd]
    syscall

exit_program:
    cmp         qword [column], 0
    je          final_exit
    
    mov         byte [output_buf], 10
    write       STDOUT_FILENO, output_buf, 1

final_exit:
    exit        0

show_help:
    write       STDOUT_FILENO, help_msg, help_len
    jmp         exit_program

show_error:
    write       STDERR_FILENO, error_msg, error_len
    jmp         exit_program

atoi:
    push        rbx
    push        rcx
    push        rdx
    push        rsi
    mov         rsi, rax            ; string pointer
    xor         rax, rax            ; result
    xor         rcx, rcx            ; current character

atoi_loop:
    mov         cl, [rsi]           ; Get character
    test        cl, cl              ; Check for null terminator
    jz          atoi_done

    cmp         cl, '0'             ; Check if it's a digit
    jl          atoi_error
    cmp         cl, '9'
    jg          atoi_error

    sub         cl, '0'             ; Convert to number
    imul        rax, 10             ; result = result * 10
    add         rax, rcx            ; result = result + digit
    inc         rsi                 ; Move to next character
    jmp         atoi_loop

atoi_error:
    xor         rax, rax            ; Return 0 on error

atoi_done:
    pop         rsi
    pop         rdx
    pop         rcx
    pop         rbx
    ret
