; src/ar.asm

%include "include/sysdefs.inc"

%define AR_HDR_SIZE 60
%define SEEK_CUR 1

section .bss
    header      resb AR_HDR_SIZE       ; archive header buffer
    namebuf     resb 17                ; filename buffer (null terminated)
    size_val    resq 1                 ; temporary for file size

section .data
    magic       db '!<arch>', 10
    magic_len   equ $ - magic
    nl          db WHITESPACE_NL
    usage_msg   db "Usage: ar t ARCHIVE", 10
    usage_len   equ $ - usage_msg
    invalid_msg db "ar: invalid archive", 10
    invalid_len equ $ - invalid_msg

section .text
    global _start

_start:
    mov     rsi, rsp
    mov     rdi, [rsi]         ; argc
    cmp     rdi, 2
    jl      .show_usage

    add     rsi, 8             ; skip argc
    add     rsi, 8             ; skip argv[0]
    mov     rsi, [rsi]         ; argv[1] = archive
    mov     rdi, STDIN_FILENO
    call    open_file
    mov     r12, rax           ; fd

    ; read and validate magic header
    mov     rax, SYS_READ
    mov     rdi, r12
    mov     rsi, header
    mov     rdx, magic_len
    syscall
    cmp     rax, magic_len
    jne     .invalid
    mov     rax, qword [header]
    cmp     rax, qword [magic]
    jne     .invalid

.read_loop:
    ; read file header
    mov     rax, SYS_READ
    mov     rdi, r12
    mov     rsi, header
    mov     rdx, AR_HDR_SIZE
    syscall
    cmp     rax, 0
    je      .done
    cmp     rax, AR_HDR_SIZE
    jne     .invalid

    ; copy filename (up to '/')
    lea     rsi, [header]
    lea     rdi, [namebuf]
    mov     rcx, 16
.copy_name:
    mov     al, [rsi]
    cmp     al, '/'
    je      .terminate
    cmp     rcx, 0
    je      .terminate
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jmp     .copy_name
.terminate:
    mov     byte [rdi], 0
    mov     rbx, rdi
    sub     rbx, namebuf
    write   STDOUT_FILENO, namebuf, rbx
    write   STDOUT_FILENO, nl, 1

    ; parse size from header[48:58]
    lea     rsi, [header + 48]
    mov     rcx, 10
    xor     rax, rax
.parse_loop:
    mov     bl, [rsi]
    cmp     bl, '0'
    jb      .skip_char
    cmp     bl, '9'
    ja      .skip_char
    sub     bl, '0'
    imul    rax, 10
    add     rax, rbx
.skip_char:
    inc     rsi
    dec     rcx
    jnz     .parse_loop
    mov     [size_val], rax

    ; skip file data
    mov     rax, SYS_LSEEK
    mov     rdi, r12
    mov     rsi, [size_val]
    mov     rdx, SEEK_CUR
    syscall
    ; align to even
    test    byte [size_val], 1
    jz      .read_loop
    mov     rax, SYS_LSEEK
    mov     rdi, r12
    mov     rsi, 1
    mov     rdx, SEEK_CUR
    syscall
    jmp     .read_loop

.done:
    mov     rax, SYS_CLOSE
    mov     rdi, r12
    syscall
    exit    0

.show_usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

.invalid:
    write   STDERR_FILENO, invalid_msg, invalid_len
    exit    1
