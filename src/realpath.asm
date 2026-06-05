; src/realpath.asm -- print the canonical absolute path of an operand.
; Resolves symlinks, "." and ".." by opening the path with O_PATH and
; reading /proc/self/fd/N (the kernel's canonical name). The path must
; exist (as with realpath -e).
; Usage: realpath PATH

    %include "include/sysdefs.inc"

    %define O_PATH 0o10000000

section .data
    procprefix db "/proc/self/fd/"
    procprefix_len equ $ - procprefix
    newline db 10
err_msg db "realpath: cannot resolve path", 10
    err_len equ $ - err_msg

section .bss
    procpath resb 64
    numtmp   resb 24
    outbuf   resb 4096

section .text
global _start

_start:
    pop     rax                         ;argc
    pop     rdi                         ;argv[0] discarded
    cmp     rax, 2
    jl      .fail
    pop     rdi                         ;argv[1] = path

    mov     rax, SYS_OPEN
    mov     rsi, O_PATH
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fail
    mov     r12, rax                    ;fd

    call    build_procpath

    mov     rax, SYS_READLINK
    mov     rdi, procpath
    mov     rsi, outbuf
    mov     rdx, 4096
    syscall
    test    rax, rax
    jle     .fail

    mov     rdx, rax                    ;length of canonical path
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, outbuf
    syscall
    write   STDOUT_FILENO, newline, 1
    exit    0

.fail:
    write   STDERR_FILENO, err_msg, err_len
    exit    1

; build_procpath: write "/proc/self/fd/<r12>" (NUL-terminated) into procpath
build_procpath:
    mov     rsi, procprefix
    mov     rdi, procpath
    mov     rcx, procprefix_len
.copy:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .copy
    mov     rax, r12
    test    rax, rax
    jnz     .convert
    mov     byte [rdi], '0'
    inc     rdi
    jmp     .term
.convert:
    lea     r8, [numtmp + 24]
    mov     rbx, 10
.digits:
    xor     rdx, rdx
    div     rbx
    add     dl, '0'
    dec     r8
    mov     [r8], dl
    test    rax, rax
    jnz     .digits
    lea     r9, [numtmp + 24]
.emit:
    cmp     r8, r9
    jge     .term
    mov     al, [r8]
    mov     [rdi], al
    inc     rdi
    inc     r8
    jmp     .emit
.term:
    mov     byte [rdi], 0
    ret
