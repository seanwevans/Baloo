; src/chcon.asm

%include "include/sysdefs.inc"

section .data
    usage_msg   db "Usage: chcon CONTEXT FILE", 10
    usage_len   equ $ - usage_msg
    fail_msg    db "chcon: setxattr failed", 10
    fail_len    equ $ - fail_msg
    attr_name   db "security.selinux", 0

section .text
    global _start

_start:
    pop     rcx             ; argc
    cmp     rcx, 3
    jne     .usage

    pop     rax             ; discard argv[0]
    pop     rsi             ; context string
    pop     rdi             ; file path

    call    strlen          ; length -> rbx

    mov     rax, SYS_SETXATTR
    mov     rdx, rsi        ; value
    mov     rsi, attr_name  ; name
    mov     r10, rbx        ; size
    xor     r8, r8          ; flags
    syscall

    test    rax, rax
    js      .fail
    exit    0

.usage:
    write   STDOUT_FILENO, usage_msg, usage_len
    exit    1

.fail:
    write   STDERR_FILENO, fail_msg, fail_len
    exit    1
