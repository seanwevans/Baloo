; src/nl.asm

    %include "include/sysdefs.inc"

    %define BUFFER_SIZE 4096

section .bss
    buffer      resb BUFFER_SIZE        ;input buffer
    numbuf      resb 32                 ;number conversion buffer
    char_buf    resb 1                  ;single char holder

section .data
    tab_char    db 9                    ;tab separator

section .text
global  _start

_start:
    mov         r13, 1                  ;current line number
    mov         r15b, 1                 ;print line number flag
    pop         r12                     ;argc
    pop         rdi                     ;skip program name
    dec         r12
    cmp         r12, 0
    je          read_stdin

process_args:
    cmp         r12, 0
    je          exit_success

    pop         rsi                     ;filename
    mov         rdi, STDIN_FILENO       ;default fd if none
    call        open_file               ;returns fd in rax or exits
    mov         r14, rax                ;file descriptor
    push        r12                     ;save remaining args count
    call        nl_fd
    pop         r12
    cmp         r14, STDIN_FILENO
    je          next_arg
    mov         rax, SYS_CLOSE
    mov         rdi, r14
    syscall

next_arg:
    dec         r12
    jmp         process_args

read_stdin:
    mov         rdi, STDIN_FILENO
    call        nl_fd
    jmp         exit_success

; ------------------------------------------------------------
; nl_fd: number lines from file descriptor in rdi
; ------------------------------------------------------------
nl_fd:
    push        rdi                     ;save fd

read_loop:
    mov         rax, SYS_READ
    pop         rdi                     ;restore fd
    push        rdi                     ;save again
    mov         rsi, buffer
    mov         rdx, BUFFER_SIZE
    syscall

    cmp         rax, 0
    je          read_done
    cmp         rax, 0
    jl          read_error

    mov         rcx, rax                ;bytes read
    mov         rbx, buffer

process_buffer:
    cmp         rcx, 0
    je          read_loop

    mov         al, [rbx]
    mov         byte [char_buf], al
    inc         rbx
    dec         rcx

    cmp         r15b, 0
    je          .after_number

    mov         rdi, r13
    call        print_decimal
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, tab_char
    mov         rdx, 1
    syscall
    mov         r15b, 0

.after_number:
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, char_buf
    mov         rdx, 1
    syscall

    cmp         byte [char_buf], WHITESPACE_NL
    jne         process_buffer
    inc         r13
    mov         r15b, 1
    jmp         process_buffer

read_done:
    pop         rdi                     ;clean stack
    ret

read_error:
    pop         rdi
    exit        1

; ------------------------------------------------------------
; print_decimal: prints rdi in decimal
; ------------------------------------------------------------
print_decimal:
    push    rbx
    cmp     rdi, 0
    jne     .print_loop_start

    mov     byte [numbuf+31], '0'
    mov     rdx, 1
    mov     rsi, numbuf+31
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall

    pop     rbx
    ret

.print_loop_start:
    mov     rsi, numbuf+32
    xor     rcx, rcx
    mov     rax, rdi
    mov     r8, 10

.print_loop:
    xor     rdx, rdx
    div     r8
    add     rdx, '0'
    dec     rsi
    mov     [rsi], dl
    inc     rcx
    test    rax, rax
    jnz     .print_loop

    mov     rdi, STDOUT_FILENO
    mov     rax, SYS_WRITE
    mov     rdx, rcx
    syscall

    pop     rbx
    ret

exit_success:
    exit        0
