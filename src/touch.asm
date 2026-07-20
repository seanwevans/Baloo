; src/touch.asm -- touch(1): create files and/or update their timestamps.
; Usage: touch [-c] FILE...   (-c: do not create missing files).
;
; Other timestamp options (-t/-d/-r/-a/-m) are accepted but only the default
; "set to the current time" behaviour is implemented.

    %include "include/sysdefs.inc"

section .bss
    nocreate    resb 1

section .data
usage_msg   db "Usage: touch [-c] FILE...", 10
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    mov     byte [nocreate], 0
    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

    xor     r14, r14                    ;count of file operands seen
parse:
    cmp     r12, 0
    je      .checkfiles
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .file
    cmp     byte [rdi + 1], 0
    je      .file                       ;lone "-" is a filename
    lea     rsi, [rdi + 1]
.opt:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 'c'
    jne     .skipopt
    mov     byte [nocreate], 1
.skipopt:
    inc     rsi
    jmp     .opt
.file:
    inc     r14
    call    touch_file
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse
.checkfiles:
    test    r14, r14
    jnz     .ok
    write   STDERR_FILENO, usage_msg, usage_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall
.ok:
    xor     rdi, rdi
    mov     rax, SYS_EXIT
    syscall

; touch_file: rdi = filename. Creates it (unless -c) then sets its times to now.
touch_file:
    mov     r15, rdi                    ;keep the name
    cmp     byte [nocreate], 1
    je      .settime
    mov     rax, SYS_OPEN
    mov     rsi, O_WRONLY | O_CREAT
    mov     rdx, 0o666
    syscall
    test    rax, rax
    js      .settime
    mov     rdi, rax
    mov     rax, SYS_CLOSE
    syscall
.settime:
    mov     rax, SYS_UTIMENSAT
    mov     rdi, AT_FDCWD
    mov     rsi, r15
    xor     rdx, rdx                    ;NULL -> current time
    xor     r10, r10
    syscall
    ret
