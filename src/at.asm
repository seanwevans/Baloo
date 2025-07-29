; src/at.asm

%include "include/sysdefs.inc"

%define CMD_BUF_SIZE 8192

section .bss
    cmd_buffer  resb CMD_BUF_SIZE
    ts_sec      resq 1
    ts_nsec     resq 1

section .data
    sh_path     db "/bin/sh", 0
    dash_c      db "-c", 0
    usage_msg   db "Usage: at <seconds>\n", 0
    usage_len   equ $ - usage_msg
    exec_fail   db "Error: execve failed", WHITESPACE_NL
    exec_fail_len equ $ - exec_fail

section .text
    global _start

_start:
    ; retrieve argc and envp
    pop     rbx             ; argc
    mov     rax, rsp        ; pointer to argv[0]
    lea     r12, [rax + rbx*8 + 8]  ; envp pointer
    dec     rbx
    cmp     rbx, 1
    jl      .usage

    pop     rdi             ; seconds argument
    call    str_to_int
    mov     [ts_sec], rax

    ; read commands from stdin
    mov     r8, cmd_buffer
    mov     r9, CMD_BUF_SIZE-1
.read_loop:
    mov     rax, SYS_READ
    mov     rdi, STDIN_FILENO
    mov     rsi, r8
    mov     rdx, r9
    syscall
    cmp     rax, 0
    jle     .done_read
    add     r8, rax
    sub     r9, rax
    cmp     r9, 0
    jle     .done_read
    jmp     .read_loop
.done_read:
    mov     byte [r8], 0

    ; sleep for the specified seconds
    mov     rax, 35             ; SYS_nanosleep
    lea     rdi, [ts_sec]
    xor     rsi, rsi
    syscall

    ; prepare argv for execve("/bin/sh", ["sh","-c",cmd], envp)
    sub     rsp, 32
    mov     qword [rsp], sh_path
    mov     qword [rsp+8], dash_c
    lea     rax, [cmd_buffer]
    mov     [rsp+16], rax
    mov     qword [rsp+24], 0

    mov     rdi, sh_path
    mov     rsi, rsp
    mov     rdx, r12
    mov     rax, SYS_EXECVE
    syscall

    ; on failure
    write STDERR_FILENO, exec_fail, exec_fail_len
    exit 1

.usage:
    write STDERR_FILENO, usage_msg, usage_len
    exit 1

; Convert string in RDI to integer in RAX
str_to_int:
    xor rax, rax
    xor rcx, rcx
.next_digit:
    movzx rcx, byte [rdi]
    test rcx, rcx
    jz .done
    sub rcx, '0'
    cmp rcx, 9
    ja .done
    imul rax, rax, 10
    add rax, rcx
    inc rdi
    jmp .next_digit
.done:
    ret
