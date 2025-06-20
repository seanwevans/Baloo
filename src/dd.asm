; src/dd.asm

%include "include/sysdefs.inc"

%define DEFAULT_BS 512
%define BUFFER_MAX 65536

section .bss
    buffer      resb BUFFER_MAX
    bs_value    resq 1
    count_value resq 1
    in_fd       resq 1
    out_fd      resq 1

section .text
    global _start

_start:
    ; default settings
    mov qword [bs_value], DEFAULT_BS
    mov qword [count_value], -1
    mov qword [in_fd], STDIN_FILENO
    mov qword [out_fd], STDOUT_FILENO

    pop rcx                    ; argc
    dec rcx                    ; skip program name
    mov rbx, rsp               ; argv pointer

.parse_args:
    cmp rcx, 0
    je .start_copy
    mov rdi, [rbx]
    add rbx, 8
    dec rcx

    ; check if=FILE
    cmp byte [rdi], 'i'
    jne .check_of
    cmp byte [rdi+1], 'f'
    jne .check_of
    cmp byte [rdi+2], '='
    jne .check_of
    lea rsi, [rdi+3]
    mov rdi, STDIN_FILENO
    call open_file
    mov [in_fd], rax
    jmp .parse_args

.check_of:
    cmp byte [rdi], 'o'
    jne .check_bs
    cmp byte [rdi+1], 'f'
    jne .check_bs
    cmp byte [rdi+2], '='
    jne .check_bs
    lea rsi, [rdi+3]
    mov rdi, STDOUT_FILENO
    call open_dest_file
    mov [out_fd], rax
    jmp .parse_args

.check_bs:
    cmp byte [rdi], 'b'
    jne .check_count
    cmp byte [rdi+1], 's'
    jne .check_count
    cmp byte [rdi+2], '='
    jne .check_count
    lea rdi, [rdi+3]
    call str_to_int
    cmp rax, BUFFER_MAX
    jbe .set_bs
    mov rax, BUFFER_MAX
.set_bs:
    mov [bs_value], rax
    jmp .parse_args

.check_count:
    cmp byte [rdi], 'c'
    jne .parse_args
    cmp byte [rdi+1], 'o'
    jne .parse_args
    cmp byte [rdi+2], 'u'
    jne .parse_args
    cmp byte [rdi+3], 'n'
    jne .parse_args
    cmp byte [rdi+4], 't'
    jne .parse_args
    cmp byte [rdi+5], '='
    jne .parse_args
    lea rdi, [rdi+6]
    call str_to_int
    mov [count_value], rax
    jmp .parse_args

.start_copy:
    mov r12, [in_fd]
    mov r13, [out_fd]
    mov r14, [bs_value]
    mov r15, [count_value]

.copy_loop:
    cmp r15, 0
    je .done
    mov rax, SYS_READ
    mov rdi, r12
    mov rsi, buffer
    mov rdx, r14
    syscall
    test rax, rax
    jle .done
    mov rdx, rax
    mov rax, SYS_WRITE
    mov rdi, r13
    mov rsi, buffer
    syscall
    cmp r15, -1
    je .copy_loop
    dec r15
    jmp .copy_loop

.done:
    cmp r12, STDIN_FILENO
    je .check_out
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

.check_out:
    cmp r13, STDOUT_FILENO
    je .exit_success
    mov rax, SYS_CLOSE
    mov rdi, r13
    syscall

.exit_success:
    exit 0

; Convert string in RDI to integer in RAX (decimal, positive only)
str_to_int:
    xor rax, rax
    xor rcx, rcx
.str_loop:
    movzx rcx, byte [rdi]
    test rcx, rcx
    jz .str_done
    sub rcx, '0'
    cmp rcx, 9
    ja .str_done
    imul rax, rax, 10
    add rax, rcx
    inc rdi
    jmp .str_loop
.str_done:
    ret
