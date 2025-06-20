; src/hash.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 4096

section .bss
    buffer      resb BUFFER_SIZE
    hex_output  resb 16

section .data
    fnv_offset  dq 0xcbf29ce484222325
    fnv_prime   dq 0x100000001b3
    hex_chars   db "0123456789abcdef"
    newline     db WHITESPACE_NL

section .text
    global _start

_start:
    mov     rbx, [fnv_offset]            ; initial hash value

.read_loop:
    mov     rax, SYS_READ
    mov     rdi, STDIN_FILENO
    mov     rsi, buffer
    mov     rdx, BUFFER_SIZE
    syscall
    cmp     rax, 0
    jle     .finish
    mov     rcx, rax
    mov     rsi, buffer
.byte_loop:
    mov     al, [rsi]
    xor     bl, al
    mov     rax, rbx
    mul     qword [fnv_prime]
    mov     rbx, rax
    inc     rsi
    dec     rcx
    jnz     .byte_loop
    jmp     .read_loop

.finish:
    mov     rax, rbx
    call    print_hex
    exit    0

; Convert rax to 16-character lowercase hexadecimal string
print_hex:
    mov     rsi, hex_output
    mov     rcx, 16
.convert_loop:
    mov     rdx, rax
    and     rdx, 0x0F
    mov     dl, [hex_chars + rdx]
    mov     [rsi + rcx - 1], dl
    shr     rax, 4
    dec     rcx
    jnz     .convert_loop
    write   STDOUT_FILENO, hex_output, 16
    write   STDOUT_FILENO, newline, 1
    ret
