; src/mkdir.asm

%include "include/sysdefs.inc"

section .bss
    dirbuf      resb 256            ; buffer to hold directory name
    readlen     resq 1              ; to store read length

section .data
    usage_msg   db "Usage: mkdir [dirname]", 10
    usage_len   equ $ - usage_msg

section .text
    global      _start

_start:
    mov         r12, [rsp]          ; argc
    cmp         r12, 2
    je          .use_argv
    cmp         r12, 1
    je          .read_stdin         ; optional stdin mode (no dirname arg)
    jmp         .print_usage        ; unsupported argc form

.use_argv:
    mov         r13, [rsp + 16]     ; pointer to dirname
    jmp         .mkdir

.read_stdin:
    mov         rax, SYS_READ
    mov         rdi, STDIN_FILENO
    mov         rsi, dirbuf
    mov         rdx, 255
    syscall
    
    cmp         rax, 0
    jle         .print_usage        ; EOF or error
    
    mov         [readlen], rax
    mov         rcx, rax
    dec         rcx
    
.strip_nl:
    cmp         byte [dirbuf + rcx], WHITESPACE_NL
    jne         .done_strip
    
    mov         byte [dirbuf + rcx], 0
    
.done_strip:
    lea         r13, [dirbuf]

.mkdir:
    mov         rax, 83             ; SYS_mkdir
    mov         rdi, r13            ; pathname
    mov         rsi, 0o755          ; mode: rwxr-xr-x
    syscall
    
    test        rax, rax
    js          .print_usage        ; if mkdir failed, show usage
    exit        0

.print_usage:
    write       STDERR_FILENO, usage_msg, usage_len
    exit        1
