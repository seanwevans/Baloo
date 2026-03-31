; src/umask.asm

%include "include/sysdefs.inc"

section .data
    usage_msg   db "Usage: umask [mode]", 10, 0
    usage_len   equ $ - usage_msg
    error_msg   db "Error: Invalid mode", 10, 0
    error_len   equ $ - error_msg
    newline     db WHITESPACE_NL

section .bss
    buffer      resb 64         ; Buffer for string manipulation
    mode        resq 1          ; Variable to store parsed mode

section .text
    global      _start

_start:
    pop         rcx             ; Get argc
    cmp         rcx, 1          ; If argc == 1 (no arguments)
    je          display_current_umask ; Just display current umask
    
    cmp         rcx, 2          ; If argc == 2 (one argument)
    je          set_new_umask   ; Set new umask

    write       STDERR_FILENO, usage_msg, usage_len
    exit        1

display_current_umask:
    mov         rax, SYS_UMASK
    mov         rdi, 0          ; Get current value by setting to 0
    syscall                     ; Returns old value in rax

    push        rax
    mov         rdi, rax        ; Original value
    mov         rax, SYS_UMASK
    syscall

    pop         rdi             ; Get original value
    mov         rsi, buffer     ; Set buffer as destination
    mov         byte [rsi], '0' ; Leading '0' for octal
    inc         rsi
    test        rdi, rdi
    jnz         .convert_nonzero
    
    mov         byte [rsi], '0'
    inc         rsi
    jmp         .finish_string
    
.convert_nonzero:
    mov         rax, rdi        ; Value to convert
    mov         rcx, 0          ; Digit counter
    
.convert_loop:
    test        rax, rax
    jz          .print_loop

    mov         rdi, rax
    and         rdi, 7          ; Get last 3 bits
    add         rdi, '0'        ; Convert to ASCII
    push        rdi
    inc         rcx
    shr         rax, 3
    jmp         .convert_loop
    
.print_loop:
    test        rcx, rcx
    jz          .finish_string

    pop         rdi
    mov         byte [rsi], dil
    inc         rsi
    dec         rcx
    jmp         .print_loop
    
.finish_string:
    mov         byte [rsi], 10
    inc         rsi
    mov         byte [rsi], 0   ; Null terminator
    mov         rdx, rsi        ; End of output buffer (past newline)
    sub         rdx, buffer     ; Calculate length from buffer start
    write       STDOUT_FILENO, buffer, rdx ; Write directly
    exit        0

set_new_umask:
    pop         rdi             ; Skip program name
    pop         rdi             ; Get argument pointer

    call        parse_octal

    cmp         rax, -1
    je          invalid_mode

    mov         rdi, rax
    mov         rax, SYS_UMASK
    syscall

    exit        0

invalid_mode:
    write       STDERR_FILENO, error_msg, error_len
    exit        1

parse_octal:
    xor         rax, rax        ; Clear accumulator
    xor         rcx, rcx        ; Clear counter

    mov         cl, byte [rdi]
    cmp         cl, '0'
    jne         .process_char   ; If not '0', process as is
    inc         rdi             ; Skip the '0' prefix
    
.process_char:
    movzx       rcx, byte [rdi] ; Get character
    test        cl, cl          ; Check for end of string
    jz          .done

    sub         cl, '0'
    cmp         cl, 7
    ja          .error          ; Not valid octal

    shl         rax, 3          ; rax *= 8
    add         rax, rcx        ; Add new digit

    cmp         rax, 0777
    ja          .error          ; Value too large
    
    inc         rdi             ; Move to next character
    jmp         .process_char
    
.error:
    mov         rax, -1         ; Return error
    ret
    
.done:
    ret
