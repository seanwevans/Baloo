; src/stdbuf.asm

%include "include/sysdefs.inc"

section .bss
    buf_i      resb 64
    buf_o      resb 64
    buf_e      resb 64

section .data
    usage_msg  db "Usage: stdbuf [-i MODE] [-o MODE] [-e MODE] COMMAND [ARGS...]", 10
    usage_len  equ $ - usage_msg
    prefix_i   db "_STDBUF_I="
    prefix_i_len equ $ - prefix_i
    prefix_o   db "_STDBUF_O="
    prefix_o_len equ $ - prefix_o
    prefix_e   db "_STDBUF_E="
    prefix_e_len equ $ - prefix_e

section .text
    global _start

;-----------------------------------------------------
_start:
    pop     rbx                 ; argc
    mov     r12, rsp            ; argv pointer
    lea     r13, [r12 + rbx*8 + 8]  ; envp pointer
    cmp     rbx, 2
    jl      show_usage

    mov     r14, 0              ; ptr for _STDBUF_I
    mov     r15, 0              ; ptr for _STDBUF_O
    xor     r10, r10            ; ptr for _STDBUF_E (use r10)

    add     r12, 8              ; skip program name
    dec     rbx                 ; remaining args

parse_opts:
    cmp     rbx, 0
    je      need_command

    mov     rdi, [r12]
    cmp     byte [rdi], '-'
    jne     need_command

    mov     al, [rdi+1]
    cmp     al, 'i'
    je      handle_i
    cmp     al, 'o'
    je      handle_o
    cmp     al, 'e'
    je      handle_e
    jmp     need_command

handle_i:
    cmp     byte [rdi+2], 0
    je      i_separate
    lea     rsi, [rdi+2]
    jmp     make_i

i_separate:
    cmp     rbx, 1
    jle     show_usage
    add     r12, 8
    dec     rbx
    mov     rsi, [r12]

make_i:
    lea     rcx, [rel buf_i]
    lea     rdx, [rel prefix_i]
    mov     r8, prefix_i_len
    call    build_env
    mov     r14, rcx
    add     r12, 8
    dec     rbx
    jmp     parse_opts

handle_o:
    cmp     byte [rdi+2], 0
    je      o_separate
    lea     rsi, [rdi+2]
    jmp     make_o

o_separate:
    cmp     rbx, 1
    jle     show_usage
    add     r12, 8
    dec     rbx
    mov     rsi, [r12]

make_o:
    lea     rcx, [rel buf_o]
    lea     rdx, [rel prefix_o]
    mov     r8, prefix_o_len
    call    build_env
    mov     r15, rcx
    add     r12, 8
    dec     rbx
    jmp     parse_opts

handle_e:
    cmp     byte [rdi+2], 0
    je      e_separate
    lea     rsi, [rdi+2]
    jmp     make_e

e_separate:
    cmp     rbx, 1
    jle     show_usage
    add     r12, 8
    dec     rbx
    mov     rsi, [r12]

make_e:
    lea     rcx, [rel buf_e]
    lea     rdx, [rel prefix_e]
    mov     r8, prefix_e_len
    call    build_env
    mov     r10, rcx
    add     r12, 8
    dec     rbx
    jmp     parse_opts

need_command:
    cmp     rbx, 1
    jl      show_usage

    mov     rdi, [r12]          ; command path
    mov     rsi, r12            ; argv pointer for exec

    ; if no modifiers, exec with original env
    mov     rdx, r13
    test    r14, r14
    jnz     build_env_array
    test    r15, r15
    jnz     build_env_array
    test    r10, r10
    jz      exec_cmd

build_env_array:
    ; count original env entries
    mov     rbx, 0
    mov     r11, r13
count_loop:
    mov     rax, [r11 + rbx*8]
    test    rax, rax
    je      count_done
    inc     rbx
    jmp     count_loop
count_done:
    mov     rcx, 0
    test    r14, r14
    jz      ci
    inc     rcx
ci:
    test    r15, r15
    jz      co
    inc     rcx
co:
    test    r10, r10
    jz      ce
    inc     rcx
ce:
    mov     rdx, rbx
    add     rdx, rcx
    inc     rdx               ; for NULL
    shl     rdx, 3            ; multiply by 8
    sub     rsp, rdx
    mov     r9, rsp            ; new envp pointer
    mov     rax, 0

    mov     r8, 0
    test    r14, r14
    jz      skip_i_add
    mov     [r9 + r8*8], r14
    inc     r8
skip_i_add:
    test    r15, r15
    jz      skip_o_add
    mov     [r9 + r8*8], r15
    inc     r8
skip_o_add:
    test    r10, r10
    jz      skip_e_add
    mov     [r9 + r8*8], r10
    inc     r8
skip_e_add:
    mov     r11, r13
copy_env:
    mov     rax, [r11]
    mov     [r9 + r8*8], rax
    add     r11, 8
    inc     r8
    test    rax, rax
    jne     copy_env

    mov     rdx, r9

exec_cmd:
    mov     rax, SYS_EXECVE
    syscall

show_usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

;-----------------------------------------------------
; build_env: rsi=value ptr, rdx=prefix ptr, r8=prefix_len, rcx=dest
; returns rcx (dest)
build_env:
    push    rbx
    xor     rbx, rbx
.copy_prefix:
    cmp     rbx, r8
    jge     .prefix_done
    mov     al, [rdx + rbx]
    mov     [rcx + rbx], al
    inc     rbx
    jmp     .copy_prefix
.prefix_done:
    mov     rdi, rsi
    xor     rsi, rsi
.copy_value:
    mov     al, [rdi + rsi]
    mov     rdx, rcx
    add     rdx, rbx
    mov     [rdx + rsi], al
    inc     rsi
    cmp     al, 0
    jne     .copy_value
    pop     rbx
    ret
