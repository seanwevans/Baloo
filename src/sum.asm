; src/sum.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 4096

section .bss
    buffer  resb BUFFER_SIZE
    numbuf  resb 32

section .data
    nl      db WHITESPACE_NL
    space   db " "

section .text
    global _start

_start:
    pop rcx                    ; argc
    mov rbp, rsp               ; argv pointer
    cmp rcx, 1
    jle use_stdin

    mov rbx, rbp
    add rbx, 8                 ; skip program name
.arg_loop:
    mov rsi, [rbx]             ; filename pointer
    mov rdi, STDIN_FILENO
    call open_file             ; returns fd in rax
    mov r8, rax                ; fd
    call do_sum
    cmp r8, STDIN_FILENO
    je .skip_close
    mov rax, SYS_CLOSE
    mov rdi, r8
    syscall
.skip_close:
    add rbx, 8
    dec rcx
    jnz .arg_loop
    exit 0

use_stdin:
    mov r8, STDIN_FILENO
    mov rsi, 0
    call do_sum
    exit 0

; r8 = file descriptor
; rsi = filename pointer or 0

do_sum:
    push rbp
    mov rbp, rsp
    xor r12d, r12d               ; checksum
    xor r13, r13                 ; total bytes
.read_loop:
    mov rax, SYS_READ
    mov rdi, r8
    mov rsi, buffer
    mov rdx, BUFFER_SIZE
    syscall
    cmp rax, 0
    je .finish
    jl .read_error
    add r13, rax
    mov rcx, rax
    mov rbx, buffer
.process_byte:
    cmp rcx, 0
    je .read_loop
    movzx eax, byte [rbx]
    mov dx, r12w
    ror dx, 1
    add dx, ax
    and dx, 0xFFFF
    mov r12w, dx
    inc rbx
    dec rcx
    jmp .process_byte
.finish:
    mov rax, r13
    add rax, 1023
    shr rax, 10                  ; block count
    mov rdi, r12
    call print_decimal
    write STDOUT_FILENO, space, 1
    mov rdi, rax
    call print_decimal
    test rsi, rsi
    jz .newline
    write STDOUT_FILENO, space, 1
    mov rdi, rsi
    call print_string
.newline:
    write STDOUT_FILENO, nl, 1
    pop rbp
    ret
.read_error:
    write STDERR_FILENO, error_msg_read, error_msg_read_len
    exit 1

print_string:
    mov rsi, rdi
    call strlen
    write STDOUT_FILENO, rsi, rbx
    ret

print_decimal:
    push rbx
    cmp rdi, 0
    jne .pd_loop_start
    mov byte [numbuf+31], '0'
    write STDOUT_FILENO, numbuf+31, 1
    pop rbx
    ret
.pd_loop_start:
    mov rsi, numbuf+32
    xor rcx, rcx
    mov rax, rdi
    mov r8, 10
.pd_loop:
    xor rdx, rdx
    div r8
    add rdx, '0'
    dec rsi
    mov [rsi], dl
    inc rcx
    test rax, rax
    jnz .pd_loop
    write STDOUT_FILENO, rsi, rcx
    pop rbx
    ret
