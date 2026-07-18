; src/cat.asm -- cat(1): concatenate files (and "-"/no args = stdin) to stdout

    %include "include/sysdefs.inc"

section .bss
    buffer      resb 4096               ;Buffer for reading data
    buffer_size equ 4096                ;Size of the buffer

section .data
errpre      db "cat: "
    errpre_len  equ $ - errpre
errsuf      db ": No such file or directory", WHITESPACE_NL
    errsuf_len  equ $ - errsuf

section .text
global      _start

_start:
    mov         r12, [rsp]              ;argc
    lea         r13, [rsp + 16]         ;&argv[1]
    xor         r14, r14                ;exit status
    dec         r12                     ;operand count
    jz          stdin_only              ;no operands -> stdin

process:
    cmp         r12, 0
    je          done
    mov         rdi, [r13]
    cmp         byte [rdi], '-'         ;"-" means stdin
    jne         open_it
    cmp         byte [rdi + 1], 0
    jne         open_it
    mov         rdi, STDIN_FILENO
    call        cat_fd
    jmp         next

open_it:
    mov         rax, SYS_OPEN
    mov         rsi, O_RDONLY
    xor         rdx, rdx
    syscall
    test        rax, rax
    js          open_err
    mov         r15, rax                ;file descriptor
    mov         rdi, r15
    call        cat_fd
    mov         rdi, r15
    mov         rax, SYS_CLOSE
    syscall
    jmp         next

open_err:
    write       STDERR_FILENO, errpre, errpre_len
    mov         rsi, [r13]              ;file name
    call        strlen                  ;rbx = length (from include/sysdefs.inc)
    mov         rax, SYS_WRITE
    mov         rdi, STDERR_FILENO
    mov         rsi, [r13]
    mov         rdx, rbx
    syscall
    write       STDERR_FILENO, errsuf, errsuf_len
    mov         r14, 1

next:
    add         r13, 8
    dec         r12
    jmp         process

stdin_only:
    mov         rdi, STDIN_FILENO
    call        cat_fd

done:
    mov         rdi, r14
    mov         rax, SYS_EXIT
    syscall

; cat_fd: copy everything from fd (rdi) to stdout. Sets r14=1 on write error.
cat_fd:
    mov         rbx, rdi                ;fd (survives syscalls; rcx/r11 do not)
.read_loop:
    mov         rax, SYS_READ
    mov         rdi, rbx
    mov         rsi, buffer
    mov         rdx, buffer_size
    syscall
    cmp         rax, 0
    jle         .done                   ;EOF or read error
    mov         r10, rax                ;bytes remaining to write
    mov         r9, buffer              ;current position
.write_loop:
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, r9
    mov         rdx, r10
    syscall
    test        rax, rax
    js          .write_err
    add         r9, rax
    sub         r10, rax
    jnz         .write_loop
    jmp         .read_loop
.write_err:
    mov         r14, 1
.done:
    ret
