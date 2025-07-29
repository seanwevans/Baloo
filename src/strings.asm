; src/strings.asm

%include "include/sysdefs.inc"

section .bss
    bytebuf          resb 1                ; single byte buffer
    strbuf      resb 1024             ; buffer for current string
    fd          resq 1                ; file descriptor
    len         resq 1                ; length of string in buffer

section .data
    usage_msg   db "Usage: strings [FILE]", WHITESPACE_NL
    usage_len   equ $ - usage_msg
    nl          db WHITESPACE_NL

section .text
    global _start

_start:
    pop     rbx                     ; argc
    mov     qword [fd], STDIN_FILENO
    pop     rax                     ; skip program name
    dec     rbx
    cmp     rbx, 0
    jle     process
    pop     rsi                     ; filename
    dec     rbx
    mov     rdi, STDIN_FILENO
    call    open_file
    mov     [fd], rax
    cmp     rbx, 0
    je      process
    jmp     show_usage

process:
    xor     rcx, rcx                ; current length

read_loop:
    mov     rax, SYS_READ
    mov     rdi, [fd]
    mov     rsi, bytebuf
    mov     rdx, 1
    syscall
    cmp     rax, 0
    jle     eof

    movzx   rax, byte [bytebuf]
    cmp     al, 32
    jl      flush
    cmp     al, 126
    jg      flush

    mov     byte [strbuf + rcx], al
    inc     rcx
    cmp     rcx, 1023
    jl      read_loop

    ; buffer full, flush if long enough
    mov     byte [strbuf + rcx], 0
    cmp     rcx, 4
    jl      reset
    write   STDOUT_FILENO, strbuf, rcx
    write   STDOUT_FILENO, nl, 1
reset:
    xor     rcx, rcx
    jmp     read_loop

flush:
    mov     byte [strbuf + rcx], 0
    cmp     rcx, 4
    jl      clr
    write   STDOUT_FILENO, strbuf, rcx
    write   STDOUT_FILENO, nl, 1
clr:
    xor     rcx, rcx
    jmp     read_loop

eof:
    mov     byte [strbuf + rcx], 0
    cmp     rcx, 4
    jl      close_fd
    write   STDOUT_FILENO, strbuf, rcx
    write   STDOUT_FILENO, nl, 1

close_fd:
    cmp     qword [fd], STDIN_FILENO
    je      exit_success
    mov     rax, SYS_CLOSE
    mov     rdi, [fd]
    syscall

exit_success:
    exit    0

show_usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1
