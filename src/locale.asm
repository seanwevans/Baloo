; src/locale.asm

%include "include/sysdefs.inc"

section .bss

section .data
    newline         db WHITESPACE_NL
    lang_prefix     db "LANG=",0
    language_prefix db "LANGUAGE=",0
    lc_prefix       db "LC_",0

section .text
    global _start

_start:
    mov     rsi, rsp
    mov     rdi, [rsi]      ; argc
    add     rsi, 8          ; skip argc

.skip_argv:
    cmp     rdi, 0
    jle     .find_env_null
    add     rsi, 8          ; skip argv[i]
    dec     rdi
    jmp     .skip_argv

.find_env_null:
    add     rsi, 8          ; skip NULL after argv
    mov     r12, rsi        ; r12 points to envp[0]

.loop_env:
    mov     rbx, [r12]
    test    rbx, rbx
    je      .exit

    mov     rdi, rbx
    mov     rsi, lang_prefix
    mov     rcx, 5
    call    starts_with
    cmp     rax, 1
    je      .print_var

    mov     rdi, rbx
    mov     rsi, language_prefix
    mov     rcx, 9
    call    starts_with
    cmp     rax, 1
    je      .print_var

    mov     rdi, rbx
    mov     rsi, lc_prefix
    mov     rcx, 3
    call    starts_with
    cmp     rax, 1
    jne     .next_env

.print_var:
    mov     rsi, rbx
    call    strlen
    write   STDOUT_FILENO, rsi, rbx
    write   STDOUT_FILENO, newline, 1

.next_env:
    add     r12, 8
    jmp     .loop_env

.exit:
    exit    0

; ---------------------------------------------
; Helper: check if string at rdi starts with
; prefix at rsi of length rcx. Returns
; rax=1 if match, rax=0 otherwise.
starts_with:
    cmp     rcx, 0
    je      .yes
.loop:
    cmp     rcx, 0
    je      .yes
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .no
    inc     rdi
    inc     rsi
    dec     rcx
    jmp     .loop

.yes:
    mov     rax, 1
    ret

.no:
    xor     rax, rax
    ret
