; src/uniq.asm

    %include "include/sysdefs.inc"

    %define BUFFER_SIZE 4096            ;Size of input buffer
    %define LINE_BUFFER_SIZE 1024       ;Max line size

section .bss
    input_buffer    resb BUFFER_SIZE    ;Buffer for reading input
    current_line    resb LINE_BUFFER_SIZE ;Current line being processed
    previous_line   resb LINE_BUFFER_SIZE ;Previous line
    input_fd        resq 1              ;Input file descriptor
    output_fd       resq 1              ;Output file descriptor
    bytes_read      resq 1              ;Number of bytes read from input
    buffer_pos      resq 1              ;Current position in input buffer
    current_line_len  resq 1            ;Length of current line
    previous_line_len resq 1            ;Length of previous line
has_prev_line   resb 1                  ; Flag: do we have a previous line?

section .data
error_msg       db "Error: Could not open file", 10, 0
    error_len       equ $ - error_msg

section .text
global          _start

_start:
    mov             qword [input_fd], STDIN_FILENO
    mov             qword [output_fd], STDOUT_FILENO
    mov             qword [buffer_pos], 0
    mov             qword [bytes_read], 0
    mov             qword [current_line_len], 0
    mov             qword [previous_line_len], 0
    mov             byte [has_prev_line], 0 ;No previous line initially
    pop             rax                 ;argc
    cmp             rax, 1              ;If argc == 1, use stdin/stdout
    je              process_input

    pop             rdi                 ;Pop argv[0] (program name)
    dec             rax                 ;Decrement arg count
    jz              process_input       ;If no more args, proceed

    pop             rdi                 ;Get input filename
    mov             rsi, O_RDONLY
    mov             rax, SYS_OPEN
    syscall

    cmp             rax, 0              ;Check for error
    jl              open_error

    mov             [input_fd], rax     ;Save file descriptor
    pop             rax                 ;Check if we have another arg
    cmp             rax, 0
    je              process_input       ;If no more args, proceed

    mov             rdi, rax            ;Get output filename
    mov             rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov             rdx, DEFAULT_MODE   ;File permissions
    mov             rax, SYS_OPEN
    syscall

    cmp             rax, 0              ;Check for error
    jl              open_error

    mov             [output_fd], rax    ;Save file descriptor

process_input:
process_next_line:
    call            read_line           ;Read a line into current_line

    cmp             qword [current_line_len], 0
    je              end_processing      ;End of file

    cmp             byte [has_prev_line], 0
    je              first_line          ;If no previous line, this is the first line

    mov             rsi, current_line
    mov             rdi, previous_line
    mov             rcx, [current_line_len]
    cmp             rcx, [previous_line_len]
    jne             lines_differ        ;Lines have different lengths

    mov             rsi, current_line
    mov             rdi, previous_line
    mov             rcx, [current_line_len]
    cld                                 ;Clear direction flag (increment)
    repe            cmpsb               ;Compare bytes
    jnz             lines_differ        ;Lines differ, output current line

    jmp             process_next_line

first_line:
    mov             byte [has_prev_line], 1 ;Now we have a previous line

    call            save_current_line

    mov             rdi, [output_fd]
    mov             rsi, current_line
    mov             rdx, [current_line_len]
    write           rdi, rsi, rdx

    jmp             process_next_line

lines_differ:
    mov             rdi, [output_fd]
    mov             rsi, current_line
    mov             rdx, [current_line_len]
    write           rdi, rsi, rdx

    call            save_current_line

    jmp             process_next_line

save_current_line:
    mov             rsi, current_line
    mov             rdi, previous_line
    mov             rcx, [current_line_len]
    cld                                 ;Clear direction flag (increment)
    rep             movsb               ;Copy bytes
    mov             rax, [current_line_len]
    mov             [previous_line_len], rax ;Save length
    ret

end_processing:
    mov             rdi, [input_fd]
    cmp             rdi, STDIN_FILENO
    je              check_output_fd

    mov             rax, SYS_CLOSE
    syscall

check_output_fd:
    mov             rdi, [output_fd]
    cmp             rdi, STDOUT_FILENO
    je              exit_success

    mov             rax, SYS_CLOSE
    syscall

exit_success:
    exit            0

open_error:
    mov             rdi, STDERR_FILENO
    mov             rsi, error_msg
    mov             rdx, error_len
    write           rdi, rsi, rdx

    exit            1

read_line:
    mov             qword [current_line_len], 0

read_line_loop:
    mov             rax, [buffer_pos]
    cmp             rax, [bytes_read]
    jl              buffer_has_data     ;If buffer_pos < bytes_read, we still have data

    mov             rdi, [input_fd]
    mov             rsi, input_buffer
    mov             rdx, BUFFER_SIZE
    mov             rax, SYS_READ
    syscall

    cmp             rax, 0              ;Check if we've reached EOF
    jle             read_line_done

    mov             [bytes_read], rax   ;Save number of bytes read
    mov             qword [buffer_pos], 0 ;Reset buffer position

buffer_has_data:
    mov             rsi, input_buffer   ;Buffer address
    add             rsi, [buffer_pos]   ;Add current position
    mov             al, [rsi]           ;Get current character
    inc             qword [buffer_pos]  ;Move to next character
    cmp             al, WHITESPACE_NL   ;Check if we've reached the end of the line
    je              read_line_end

    mov             rdi, current_line
    add             rdi, [current_line_len]
    mov             [rdi], al
    inc             qword [current_line_len]
    cmp             qword [current_line_len], LINE_BUFFER_SIZE - 1
    jge             read_line_end       ;If so, truncate the line

    jmp             read_line_loop      ;Continue reading

read_line_end:
    mov             rdi, current_line
    add             rdi, [current_line_len]
    mov             byte [rdi], WHITESPACE_NL
    inc             qword [current_line_len]

read_line_done:
    ret
