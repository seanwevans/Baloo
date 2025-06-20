; src/md5sum.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 4096

section .bss
    buffer      resb BUFFER_SIZE        ; read buffer
    digest      resb 16                 ; MD5 result
    hex_output  resb 32                 ; hex string
    newline     resb 1

section .data
    hex_chars   db "0123456789abcdef"

    sockaddr:
        dw AF_ALG                      ; salg_family
        db 'hash',0,0,0,0,0,0,0,0,0,0   ; salg_type[14]
        dd 0                           ; salg_feat
        dd 0                           ; salg_mask
        db 'md5',0
        times (64-4) db 0
    sockaddr_len equ $ - sockaddr

section .text
    global _start

_start:
    pop rcx                     ; argc
    pop rbx                     ; argv[0]
    dec rcx
    jz  .use_stdin

    pop rsi                     ; filename
    mov rdi, STDIN_FILENO
    call open_file
    mov r14, rax                ; input fd
    jmp .setup_socket

.use_stdin:
    mov r14, STDIN_FILENO

.setup_socket:
    mov rax, SYS_SOCKET
    mov rdi, AF_ALG
    mov rsi, SOCK_SEQPACKET
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl  .error
    mov r15, rax

    mov rdi, r15
    lea rsi, [rel sockaddr]
    mov rdx, sockaddr_len
    mov rax, SYS_BIND
    syscall
    cmp rax, 0
    jl  .error

    mov rdi, r15
    xor rsi, rsi
    xor rdx, rdx
    mov rax, SYS_ACCEPT
    syscall
    cmp rax, 0
    jl  .error
    mov r13, rax                ; op fd

.read_loop:
    mov rax, SYS_READ
    mov rdi, r14
    mov rsi, buffer
    mov rdx, BUFFER_SIZE
    syscall
    cmp rax, 0
    jl  .error
    je  .finish
    mov rcx, rax
    mov rax, SYS_WRITE
    mov rdi, r13
    mov rsi, buffer
    mov rdx, rcx
    syscall
    cmp rax, 0
    jl  .error
    jmp .read_loop

.finish:
    mov rax, SYS_READ
    mov rdi, r13
    lea rsi, [digest]
    mov rdx, 16
    syscall
    cmp rax, 0
    jl  .error

    cmp r14, STDIN_FILENO
    je  .skip_close
    mov rax, SYS_CLOSE
    mov rdi, r14
    syscall
.skip_close:
    mov rax, SYS_CLOSE
    mov rdi, r13
    syscall
    mov rax, SYS_CLOSE
    mov rdi, r15
    syscall

    ; convert digest to hex
    lea rdi, [digest]
    lea rsi, [hex_output]
    mov rcx, 16
.hex_loop:
    movzx rax, byte [rdi]
    mov rdx, rax
    shr rdx, 4
    mov bl, [hex_chars + rdx]
    mov [rsi], bl
    and al, 0xF
    mov bl, [hex_chars + rax]
    mov [rsi + 1], bl
    inc rdi
    add rsi, 2
    loop .hex_loop

    mov byte [newline], 10
    write STDOUT_FILENO, hex_output, 32
    write STDOUT_FILENO, newline, 1
    exit 0

.error:
    exit 1
