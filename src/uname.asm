; src/uname.asm

%include "include/sysdefs.inc"

section .bss
    uts         resb 390
    sys_only    resb 1

section .data
    newline     db WHITESPACE_NL
    usage_msg   db "Usage: uname [-s]", WHITESPACE_NL
    usage_len   equ $ - usage_msg

section .text
    global      _start

_start:
    pop         rcx                     ; argc
    mov         byte [sys_only], 0
    cmp         rcx, 1
    je          .print_default
    cmp         rcx, 2
    jne         .usage

    pop         rax                     ; skip argv[0]
    pop         rdi                     ; argv[1]
    cmp         byte [rdi], '-'
    jne         .usage
    cmp         byte [rdi + 1], 's'
    jne         .usage
    cmp         byte [rdi + 2], 0
    jne         .usage

    mov         byte [sys_only], 1
    jmp         .do_uname

.print_default:
    ; default behavior: print full uname fields
    jmp         .do_uname

.do_uname:
    mov         rax, SYS_UNAME
    mov         rdi, uts
    syscall

.print_sysname:
    lea         rsi, [uts + 0]      ; sysname
    call        print_line

    cmp         byte [sys_only], 1
    je          .exit_ok

    lea         rsi, [uts + 65]     ; nodename
    call        print_line

    lea         rsi, [uts + 130]    ; release
    call        print_line

    lea         rsi, [uts + 195]    ; version
    call        print_line

    lea         rsi, [uts + 260]    ; machine
    call        print_line

.exit_ok:
    exit        0

.usage:
    write       STDERR_FILENO, usage_msg, usage_len
    exit        1

print_line:
    call        strlen
    write       1, rsi, rbx
    write       1, newline, 1
    ret
