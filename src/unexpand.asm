; src/unexpand.asm

%include "include/sysdefs.inc"

section .bss
    buffer      resb buffer_size ; I/O buffer
    output      resb buffer_size ; Output buffer

section .data
    tab_size    equ 8           ; Default tab size (8 spaces per tab)
    buffer_size equ 4096        ; Size of the I/O buffer

section .text

global _start

_start:

    pop     rcx                 ; Get argc
    pop     rdi                 ; Skip argv[0] (program name)
    
    mov     r8, STDIN_FILENO    ; Default input file descriptor
    mov     r9, STDOUT_FILENO   ; Default output file descriptor
    
    dec     rcx                 ; Check if we have any arguments
    jz      process_input       ; If no arguments, use defaults

    pop     rdi                 ; Get argv[1] (input filename)
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    mov     rdx, 0              ; Not creating a file, so no mode needed
    syscall
    
    cmp     rax, 0              ; Check if open succeeded
    jl      use_stdin           ; If error, use stdin
    mov     r8, rax             ; Save input file descriptor
    
    dec     rcx                 ; Check if we have output file argument
    jz      process_input       ; If no output file, use stdout

    pop     rdi                 ; Get argv[2] (output filename)
    mov     rax, SYS_OPEN
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, DEFAULT_MODE   ; File permissions if created
    syscall
    
    cmp     rax, 0              ; Check if open succeeded
    jl      use_stdout          ; If error, use stdout
    mov     r9, rax             ; Save output file descriptor
    jmp     process_input
    
use_stdin:
    mov     r8, STDIN_FILENO    ; Use standard input
    jmp     process_input
    
use_stdout:
    mov     r9, STDOUT_FILENO   ; Use standard output

process_input:
    xor     r13, r13            ; Current column
    xor     r14, r14            ; Pending space count

    
read_loop:

    mov     rax, SYS_READ
    mov     rdi, r8             ; Input file descriptor
    mov     rsi, buffer         ; Buffer to read into
    mov     rdx, buffer_size    ; Amount to read
    syscall
    
    cmp     rax, 0              ; Check for EOF or error
    jle     cleanup             ; If EOF or error, exit
    
    mov     r10, rax            ; Save number of bytes read
    mov     r11, 0              ; Input position
    mov     r12, 0              ; Output position

process_char:
    cmp     r11, r10            ; Check if we've processed all input
    jge     flush_pending_spaces ; If yes, flush pending spaces then write
    
    movzx   rax, byte [buffer + r11] ; Get current character
    inc     r11                 ; Move to next character
 
    cmp     al, WHITESPACE_SPACE
    je      handle_space

    cmp     r14, 0
    je      handle_non_space
    call    emit_pending_spaces

handle_non_space:
    cmp     al, WHITESPACE_TAB
    je      handle_tab

    cmp     al, WHITESPACE_NL
    je      handle_newline

    mov     byte [output + r12], al
    inc     r12
    inc     r13
    jmp     process_char

handle_space:
    inc     r14                 ; Keep pending until tab stop reached
    inc     r13
    test    r13, tab_size - 1
    jne     process_char
    mov     byte [output + r12], WHITESPACE_TAB
    inc     r12
    xor     r14, r14
    jmp     process_char

handle_tab:
    mov     byte [output + r12], WHITESPACE_TAB
    inc     r12
    add     r13, tab_size
    and     r13, -tab_size      ; Next tab stop
    jmp     process_char

handle_newline:
    mov     byte [output + r12], WHITESPACE_NL
    inc     r12
    xor     r13, r13
    xor     r14, r14
    jmp     process_char        ; Continue processing

flush_pending_spaces:
    cmp     r14, 0
    je      write_output
    call    emit_pending_spaces

write_output:

    mov     rax, SYS_WRITE
    mov     rdi, r9             ; Output file descriptor
    mov     rsi, output         ; Output buffer
    mov     rdx, r12            ; Number of bytes to write
    syscall

    jmp     read_loop

emit_pending_spaces:
    cmp     r14, 0
    je      .done
.loop:
    mov     byte [output + r12], WHITESPACE_SPACE
    inc     r12
    dec     r14
    jne     .loop
.done:
    ret
    
cleanup:

    cmp     r8, STDIN_FILENO
    je      check_output
    
    mov     rax, SYS_CLOSE
    mov     rdi, r8             ; Input file descriptor
    syscall
    
check_output:

    cmp     r9, STDOUT_FILENO
    je      exit_program
    
    mov     rax, SYS_CLOSE
    mov     rdi, r9             ; Output file descriptor
    syscall
    
exit_program:

    exit 0
