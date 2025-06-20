; src/batch.asm

%include "include/sysdefs.inc"

%define CMD_BUF_SIZE 8192

section .bss
    cmd_buffer  resb CMD_BUF_SIZE

section .data
    sh_path     db "/bin/sh", 0
    dash_c      db "-c", 0
    exec_fail   db "Error: execve failed", WHITESPACE_NL
    exec_fail_len equ $ - exec_fail

section .text
    global _start

_start:
    ; Retrieve argc and compute envp pointer
    pop     rbx             ; argc
    mov     rax, rsp        ; pointer to argv[0]
    lea     r12, [rax + rbx*8 + 8]  ; envp pointer

    ; Read commands from stdin
    mov     r8, cmd_buffer          ; current buffer pointer
    mov     r9, CMD_BUF_SIZE-1      ; remaining space

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
    mov byte [r8], 0

    ; Prepare argv array for execve("/bin/sh", ["sh","-c",cmd], envp)
    sub     rsp, 32
    mov     qword [rsp], sh_path    ; argv[0]
    mov     qword [rsp+8], dash_c   ; argv[1]
    lea     rax, [cmd_buffer]
    mov     [rsp+16], rax           ; argv[2]
    mov     qword [rsp+24], 0       ; NULL terminator

    mov     rdi, sh_path
    mov     rsi, rsp
    mov     rdx, r12
    mov     rax, SYS_EXECVE
    syscall

    ; If execve fails
    write STDERR_FILENO, exec_fail, exec_fail_len
    exit 1
