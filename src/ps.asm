; src/ps.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 8192

struc dirent64
    .d_ino      resq 1
    .d_off      resq 1
    .d_reclen   resw 1
    .d_type     resb 1
    .d_name     resb 1
endstruc

section .bss
    buffer      resb BUFFER_SIZE
    path_buf    resb 256
    comm_buf    resb 256
    dirfd       resq 1

section .data
    proc_prefix db '/proc/',0
    comm_suffix db '/comm',0
    space       db ' '
    newline     db WHITESPACE_NL

section .text
    global _start

_start:
    mov     rax, SYS_OPEN
    mov     rdi, proc_prefix
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      exit_error
    mov     [dirfd], rax

read_dir:
    mov     rax, SYS_GETDENTS64
    mov     rdi, [dirfd]
    mov     rsi, buffer
    mov     rdx, BUFFER_SIZE
    syscall
    cmp     rax, 0
    jle     close_exit
    mov     r12, rax                ; bytes read
    xor     r13, r13                ; offset

next_entry:
    cmp     r13, r12
    jge     read_dir
    lea     r15, [buffer + r13]
    movzx   r14, word [r15 + dirent64.d_reclen]
    lea     rsi, [r15 + dirent64.d_name]
    mov     rdi, rsi
    call    is_numeric
    test    al, al
    jz      skip_entry

    ; Build path /proc/<pid>/comm
    mov     rdi, path_buf
    mov     rsi, proc_prefix
    call    copy_string
    mov     rsi, path_buf
    call    strlen
    mov     rcx, rbx
    lea     rdi, [path_buf + rcx]
    mov     rsi, r15
    add     rsi, dirent64.d_name
    call    copy_string
    mov     rsi, path_buf
    call    strlen
    mov     rcx, rbx
    lea     rdi, [path_buf + rcx]
    mov     rsi, comm_suffix
    call    copy_string

    mov     rax, SYS_OPEN
    mov     rdi, path_buf
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      skip_entry
    mov     rbx, rax

    mov     rax, SYS_READ
    mov     rdi, rbx
    mov     rsi, comm_buf
    mov     rdx, 255
    syscall
    mov     r8, rax
    mov     rax, SYS_CLOSE
    mov     rdi, rbx
    syscall
    cmp     r8, 0
    jle     skip_entry
    dec     r8
    mov     byte [comm_buf + r8], 0

    lea     rdi, [r15 + dirent64.d_name]
    call    write_str
    write   STDOUT_FILENO, space, 1
    mov     rdi, comm_buf
    call    write_str
    write   STDOUT_FILENO, newline, 1

skip_entry:
    add     r13, r14
    jmp     next_entry

close_exit:
    mov     rax, SYS_CLOSE
    mov     rdi, [dirfd]
    syscall
    exit    0

exit_error:
    exit    1

; rdi = destination, rsi = source
copy_string:
    xor     rcx, rcx
.copy_loop:
    mov     al, [rsi + rcx]
    mov     [rdi + rcx], al
    inc     rcx
    test    al, al
    jnz     .copy_loop
    ret

; rdi = string pointer
write_str:
    mov     rsi, rdi
    call    strlen                 ; length -> rbx
    mov     rdx, rbx
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    ret

; rdi = string, returns al=1 if all digits, 0 otherwise
is_numeric:
    xor     rcx, rcx
.loop:
    mov     al, [rdi + rcx]
    test    al, al
    jz      .true
    cmp     al, '0'
    jl      .false
    cmp     al, '9'
    jg      .false
    inc     rcx
    jmp     .loop
.true:
    mov     al, 1
    ret
.false:
    xor     al, al
    ret
