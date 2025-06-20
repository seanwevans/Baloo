; src/find.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 8192
%define DT_DIR 4

struc dirent64
    .d_ino      resq 1
    .d_off      resq 1
    .d_reclen   resw 1
    .d_type     resb 1
    .d_name     resb 1
endstruc

section .bss
    buffer      resb BUFFER_SIZE
    path_buf    resb 4096

section .data
    newline     db 10
    dot         db '.',0

section .text
    global _start

_start:
    pop rcx                ; argc
    mov rsi, rsp           ; argv pointer
    cmp rcx, 1
    je .use_dot

    pop rdi                ; skip program name

.arg_loop:
    pop rdi                ; next path
    call find_dir
    dec rcx
    cmp rcx, 1
    jg .arg_loop
    exit 0

.use_dot:
    mov rdi, dot
    call find_dir
    exit 0

; rdi = path
find_dir:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r14, rdi           ; save path pointer
    mov rsi, rdi
    call strlen
    mov rdx, rbx
    write STDOUT_FILENO, r14, rdx
    write STDOUT_FILENO, newline, 1

    mov rax, SYS_OPEN
    mov rdi, r14
    mov rsi, O_RDONLY
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl .done
    mov r15, rax

.read_loop:
    mov rax, SYS_GETDENTS64
    mov rdi, r15
    mov rsi, buffer
    mov rdx, BUFFER_SIZE
    syscall
    cmp rax, 0
    jle .close_dir
    mov r12, rax
    xor r13, r13

.entry_loop:
    cmp r13, r12
    jge .read_loop

    lea rbx, [buffer + r13]
    movzx r10, word [rbx + dirent64.d_reclen]
    lea rsi, [rbx + dirent64.d_name]

    ; skip '.' and '..'
    cmp byte [rsi], '.'
    jne .not_special
    cmp byte [rsi + 1], 0
    je .skip_entry
    cmp byte [rsi + 1], '.'
    jne .not_special
    cmp byte [rsi + 2], 0
    je .skip_entry
.not_special:
    mov rdi, path_buf
    mov rsi, r14
    call copy_string
    mov rcx, rax
    dec rcx
    mov byte [path_buf + rcx], '/'
    inc rcx
    lea rdi, [path_buf + rcx]
    lea rsi, [rbx + dirent64.d_name]
    call copy_string
    mov rdi, path_buf
    mov bl, [rbx + dirent64.d_type]
    cmp bl, DT_DIR
    je .recurse
    call print_entry
    jmp .after
.recurse:
    call find_dir
.after:
.skip_entry:
    add r13, r10
    jmp .entry_loop

.close_dir:
    mov rax, SYS_CLOSE
    mov rdi, r15
    syscall
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

print_entry:
    mov rsi, rdi
    call strlen
    mov rdx, rbx
    write STDOUT_FILENO, rsi, rdx
    write STDOUT_FILENO, newline, 1
    ret

copy_string:
    xor rax, rax
.copy_loop:
    mov bl, [rsi + rax]
    mov [rdi + rax], bl
    inc rax
    test bl, bl
    jne .copy_loop
    ret
