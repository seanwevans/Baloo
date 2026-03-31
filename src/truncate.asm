; src/truncate.asm

%include "include/sysdefs.inc"

section .bss
    filesize    resq 1

section .data
    usage_msg   db "Usage: truncate -s <size> <file>", 10
    usage_len   equ $ - usage_msg
    error_msg   db "Error: Could not truncate file", 10
    error_len   equ $ - error_msg
    opt_s       db "-s", 0

section .text
    global      _start

_start:
    pop         rcx                     ; argc
    cmp         rcx, 4                  ; Need program name + -s + size + file
    jne         print_usage

    pop         rdi                     ; Drop program name
    pop         r12                     ; option
    pop         r13                     ; size
    pop         r14                     ; file

    mov         rdi, r12
    mov         rsi, opt_s
    call        streq
    test        rax, rax
    jz          print_usage

    mov         rdi, r13
    call        string_to_uint          ; size in rax, success in rdx
    test        rdx, rdx
    jz          print_usage

    mov         [filesize], rax
    mov         rax, SYS_TRUNCATE       ; truncate syscall
    mov         rdi, r14                ; pathname
    mov         rsi, [filesize]         ; length
    syscall

    test        rax, rax
    js          error_exit
    jmp         exit_success

print_usage:
    write       STDERR_FILENO, usage_msg, usage_len
    jmp         exit_failure

error_exit:
    write       STDERR_FILENO, error_msg, error_len
    jmp         exit_failure

exit_success:
    exit        0

exit_failure:
    exit        1

; rdi = lhs, rsi = rhs
; rax = 1 if equal, 0 otherwise
streq:
.loop:
    mov         al, [rdi]
    mov         dl, [rsi]
    cmp         al, dl
    jne         .not_equal
    test        al, al
    jz          .equal
    inc         rdi
    inc         rsi
    jmp         .loop

.not_equal:
    xor         rax, rax
    ret

.equal:
    mov         rax, 1
    ret

; rdi = numeric string
; rax = parsed value
; rdx = 1 on success, 0 on error
string_to_uint:
    xor         rax, rax
    xor         rdx, rdx
    mov         cl, [rdi]
    test        cl, cl
    jz          .parse_fail

.parse_loop:
    movzx       rcx, byte [rdi]
    test        cl, cl
    jz          .parse_ok
    cmp         cl, '0'
    jb          .parse_fail
    cmp         cl, '9'
    ja          .parse_fail

    imul        rax, rax, 10
    sub         cl, '0'
    add         rax, rcx
    inc         rdi
    jmp         .parse_loop

.parse_ok:
    mov         rdx, 1
    ret

.parse_fail:
    xor         rax, rax
    xor         rdx, rdx
    ret
