; src/man.asm

%include "include/sysdefs.inc"

SECTION .bss
    buffer      resb 4096
    path_buf    resb 256
    fd          resq 1
    topic_ptr   resq 1

SECTION .data
    prefix      db "/usr/share/man/man1/",0
    prefix_len  equ $ - prefix
    suffix      db ".1",0
    suffix_len  equ $ - suffix
    usage_msg   db "Usage: man TOPIC",10
    usage_len   equ $ - usage_msg
    no_entry1   db "man: ",0
    no_entry1_len equ $ - no_entry1
    no_entry2   db ": No manual entry",10
    no_entry2_len equ $ - no_entry2

SECTION .text
    global _start

_start:
    pop     rcx                 ; argc
    cmp     rcx, 2
    jne     usage_error
    pop     rax                 ; skip program name
    pop     rdi                 ; topic pointer
    mov     [topic_ptr], rdi

    ; build path = prefix + topic + suffix
    lea     rsi, [path_buf]
    mov     rdi, prefix
    call    copy_string

    lea     rsi, [path_buf + prefix_len]
    mov     rdi, [topic_ptr]
    call    copy_string

    mov     rsi, [topic_ptr]
    call    strlen              ; rbx = length of topic
    lea     rsi, [path_buf + prefix_len + rbx]
    mov     rdi, suffix
    call    copy_string

    ; open the man file
    mov     rax, SYS_OPEN
    lea     rdi, [path_buf]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      no_entry
    mov     [fd], rax

read_loop:
    mov     rax, SYS_READ
    mov     rdi, [fd]
    mov     rsi, buffer
    mov     rdx, 4096
    syscall
    cmp     rax, 0
    jle     done_read
    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, buffer
    syscall
    jmp     read_loop

done_read:
    cmp     rax, 0
    jl      read_error
    mov     rax, SYS_CLOSE
    mov     rdi, [fd]
    syscall
    exit    0

usage_error:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

no_entry:
    write   STDERR_FILENO, no_entry1, no_entry1_len
    mov     rsi, [topic_ptr]
    call    strlen
    write   STDERR_FILENO, [topic_ptr], rbx
    write   STDERR_FILENO, no_entry2, no_entry2_len
    exit    1

read_error:
    exit    1

copy_string:
    xor     rcx, rcx
.copy_loop:
    mov     al, [rdi + rcx]
    mov     [rsi + rcx], al
    inc     rcx
    test    al, al
    jnz     .copy_loop
    ret
