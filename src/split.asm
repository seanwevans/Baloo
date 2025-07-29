; src/split.asm

    %include "include/sysdefs.inc"

    %define LINES_PER_FILE 1000

section .bss
    buffer      resb 1                  ;read one byte at a time
    namebuf     resb 4                  ;output file name "xaa\0"

section .text
global      _start

_start:
    pop         rcx                     ;argc
    dec         rcx                     ;exclude program name
    mov         r8, STDIN_FILENO        ;default input fd

    cmp         rcx, 0
    je          open_first

    pop         rdi                     ;skip argv[0]
    pop         rsi                     ;filename
    mov         rdi, STDIN_FILENO
    call        open_file               ;open input file
    mov         r8, rax

open_first:
    xor         r9, r9                  ;file index
    call        create_output
    xor         r10, r10                ;line counter

read_loop:
    mov         rax, SYS_READ
    mov         rdi, r8
    mov         rsi, buffer
    mov         rdx, 1
    syscall

    cmp         rax, 0
    je          end_input
    jl          read_error

    mov         rax, SYS_WRITE
    mov         rdi, r11                ;current output fd
    mov         rsi, buffer
    mov         rdx, 1
    syscall

    cmp         rax, 0
    jl          write_error

    cmp         byte [buffer], 10       ;newline?
    jne         read_loop

    inc         r10
    cmp         r10, LINES_PER_FILE
    jne         read_loop

    xor         r10, r10
    mov         rax, SYS_CLOSE
    mov         rdi, r11
    syscall

    inc         r9
    call        create_output
    jmp         read_loop

end_input:
    mov         rax, SYS_CLOSE
    mov         rdi, r11
    syscall
    cmp         r8, STDIN_FILENO
    je          exit_success
    mov         rax, SYS_CLOSE
    mov         rdi, r8
    syscall

exit_success:
    exit        0

read_error:
    write       STDERR_FILENO, error_msg_read, error_msg_read_len
    exit        1

write_error:
    write       STDERR_FILENO, error_msg_write, error_msg_write_len
    exit        1

create_output:
    mov         rax, r9
    mov         rcx, 26
    xor         rdx, rdx
    div         rcx                     ;rax/26 -> quotient rax, remainder rdx
    mov         bl, al                  ;high index
    mov         al, dl                  ;low index
    add         bl, 'a'
    add         al, 'a'
    mov         byte [namebuf], 'x'
    mov         byte [namebuf+1], bl
    mov         byte [namebuf+2], al
    mov         byte [namebuf+3], 0

    mov         rsi, namebuf
    mov         rdi, STDOUT_FILENO
    call        open_dest_file
    mov         r11, rax
    ret
