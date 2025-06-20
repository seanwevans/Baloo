; src/grep.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 4096

section .bss
    buffer      resb BUFFER_SIZE       ; line buffer
    fd          resq 1
    line_len    resq 1
    pattern_ptr resq 1
    pattern_len resq 1

section .data
    usage_msg   db "Usage: grep PATTERN [FILE]", 10
    usage_len   equ $ - usage_msg

section .text
    global _start

_start:
    pop     rdi                 ; argc
    cmp     rdi, 2
    jb      show_usage
    pop     rax                 ; skip program name
    pop     rsi                 ; pattern argument
    mov     [pattern_ptr], rsi
    call    strlen
    mov     [pattern_len], rbx
    mov     qword [fd], STDIN_FILENO
    dec     rdi                 ; remaining args after pattern
    cmp     rdi, 1
    jb      read_loop
    pop     rsi                 ; filename
    mov     rdi, STDIN_FILENO   ; default fd if none
    call    open_file           ; open file -> rax
    mov     [fd], rax

read_loop:
    xor     r12, r12            ; current line length

.next_char:
    mov     rax, SYS_READ
    mov     rdi, [fd]
    lea     rsi, [buffer + r12]
    mov     rdx, 1
    syscall
    cmp     rax, 0
    je      .eof
    jl      .io_error
    inc     r12
    cmp     byte [buffer + r12 - 1], 10
    je      .process_line
    cmp     r12, BUFFER_SIZE-1
    jl      .next_char
.process_line:
    mov     [line_len], r12
    mov     rdi, buffer
    mov     rsi, r12
    mov     rdx, [pattern_ptr]
    mov     rcx, [pattern_len]
    call    contains_pattern
    test    rax, rax
    jz      .reset
    mov     rsi, buffer
    mov     rdx, r12
    mov     rdi, STDOUT_FILENO
    mov     rax, SYS_WRITE
    syscall
.reset:
    xor     r12, r12
    jmp     .next_char

.eof:
    cmp     r12, 0
    je      .close_fd
    mov     [line_len], r12
    mov     rdi, buffer
    mov     rsi, r12
    mov     rdx, [pattern_ptr]
    mov     rcx, [pattern_len]
    call    contains_pattern
    test    rax, rax
    jz      .close_fd
    mov     rsi, buffer
    mov     rdx, r12
    mov     rdi, STDOUT_FILENO
    mov     rax, SYS_WRITE
    syscall

.close_fd:
    cmp     qword [fd], STDIN_FILENO
    je      exit_success
    mov     rax, SYS_CLOSE
    mov     rdi, [fd]
    syscall
    jmp     exit_success

.io_error:
    exit    1

show_usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

exit_success:
    exit    0

; rdi = buffer pointer
; rsi = buffer length
; rdx = pattern pointer
; rcx = pattern length
; returns rax = 1 if found, 0 otherwise
contains_pattern:
    push    rbx
    push    r8
    push    r9
    xor     rax, rax
    cmp     rcx, 0
    je      .found
    cmp     rsi, rcx
    jl      .done
    mov     r8, rsi
    sub     r8, rcx
.outer:
    cmp     rbx, r8
    jg      .done
    mov     r9, 0
.inner:
    cmp     r9, rcx
    je      .found
    mov     r8, rbx
    add     r8, r9
    mov     al, [rdi + r8]
    cmp     al, [rdx + r9]
    jne     .next
    inc     r9
    jmp     .inner
.next:
    inc     rbx
    jmp     .outer
.found:
    mov     rax, 1
.done:
    pop     r9
    pop     r8
    pop     rbx
    ret
