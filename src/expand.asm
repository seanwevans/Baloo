; src/expand.asm

%include "include/sysdefs.inc"

section .bss
    in_buffer   resb buffer_size    ; Input buffer
    out_buffer  resb buffer_size    ; Output buffer
    col_pos     resq 1              ; Current column position

section .data
    tab_size    equ 8               ; Default tab size
    buffer_size equ 4096            ; Size of input/output buffers

section .text
    global      _start


_start:
    pop         rax                     ; argc
    mov         rbx, rsp                ; argv pointer
    mov         qword [col_pos], 0

    cmp         rax, 1                  ; any filename argument?
    jle         use_stdin

    mov         rdi, [rbx + 8]          ; argv[1]
    mov         rax, SYS_OPEN
    mov         rsi, O_RDONLY
    xor         rdx, rdx
    syscall
    cmp         rax, 0
    jl          exit_program            ; if open fails, just exit
    mov         r14, rax                ; file descriptor
    jmp         process_input

use_stdin:
    mov         r14, STDIN_FILENO
    jmp         process_input

process_input:
    mov         rax, SYS_READ
    mov         rdi, r14
    mov         rsi, in_buffer
    mov         rdx, buffer_size
    syscall

    cmp         rax, 0
    jle         exit_program

    mov         rcx, rax            ; number of bytes read
    mov         rsi, in_buffer      ; input buffer
    mov         rdi, out_buffer     ; output buffer
    mov         r8, 0               ; input index
    mov         r9, 0               ; output index
    
process_char:
    cmp         r8, rcx
    jge         write_output

    movzx       rax, byte [rsi + r8]
    inc         r8
    cmp         al, 9               ; tab
    je          handle_tab

    cmp         al, 10              ; newline
    je          handle_newline

    mov         [rdi + r9], al
    inc         r9
    inc         qword [col_pos]
    jmp         check_buffer_full
    
handle_tab:
    mov         rax, [col_pos]
    mov         rbx, tab_size
    xor         rdx, rdx
    div         rbx
    mov         rax, tab_size
    sub         rax, rdx            ; spaces needed
    mov         rdx, rax            ; spaces to add
    add         qword [col_pos], rdx    ; Update column position
    
add_spaces:
    cmp         rdx, 0
    je          check_buffer_full

    mov         byte [rdi + r9], WHITESPACE_SPACE
    inc         r9
    dec         rdx
    jmp         add_spaces
    
handle_newline:
    mov         byte [rdi + r9], al
    inc         r9
    mov         qword [col_pos], 0
    
check_buffer_full:
    cmp         r9, buffer_size - tab_size
    jl          process_char
    
write_output:
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, out_buffer
    mov         rdx, r9
    syscall

    jmp         process_input
    
exit_program:
    cmp         r14, STDIN_FILENO
    je          .done
    mov         rax, SYS_CLOSE
    mov         rdi, r14
    syscall
.done:
    exit        0
