; src/du.asm

%include "include/sysdefs.inc"

section .bss
    stat_buf    resb 144           ; struct stat buffer
    numbuf      resb 16            ; buffer for number printing

section .data
    newline     db WHITESPACE_NL
    tab         db WHITESPACE_TAB
    dot         db '.',0

section .text
    global _start

_start:
    pop rcx                     ; argc
    pop rdx                     ; skip program name
    dec rcx
    cmp rcx, 0
    je  .use_default

.loop_args:
    pop rdi                     ; path pointer
    push rcx                    ; save counter
    mov rsi, rdi                ; save for printing
    call get_size               ; rax = size
    mov rdi, rax
    call print_num
    write   STDOUT_FILENO, tab, 1
    mov rdi, rsi
    call write_str
    write   STDOUT_FILENO, newline, 1
    pop rcx
    dec rcx
    jnz .loop_args
    exit 0

.use_default:
    mov rdi, dot
    mov rsi, rdi
    call get_size
    mov rdi, rax
    call print_num
    write   STDOUT_FILENO, tab, 1
    mov rdi, dot
    call write_str
    write   STDOUT_FILENO, newline, 1
    exit 0

; rdi = path pointer
; returns rax = file size (st_size) or 0 on error
get_size:
    push rdi
    mov rax, SYS_STAT
    mov rsi, stat_buf
    syscall
    cmp rax, 0
    jl  .err
    mov rax, [stat_buf + 48]
    jmp .done
.err:
    xor rax, rax
.done:
    pop rdi
    ret

print_num:
    mov rax, rdi
    mov rsi, numbuf + 15
    mov byte [rsi], 0
    mov rcx, 10
.next_digit:
    xor rdx, rdx
    div rcx
    dec rsi
    add dl, '0'
    mov [rsi], dl
    test rax, rax
    jnz .next_digit
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FILENO
    mov rdx, numbuf + 16
    sub rdx, rsi
    syscall
    ret

write_str:
    mov rsi, rdi
    call strlen
    write   STDOUT_FILENO, rsi, rbx
    ret
