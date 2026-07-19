; src/mkfifo.asm -- mkfifo(1): create named pipes, with -m MODE.

    %include "include/sysdefs.inc"

    %define DEFMODE 0o666

section .bss
    m_flag      resb 1
    mode_val    resq 1

section .data
error_msg:      db "mkfifo: cannot create fifo", 10
error_len:      equ $ - error_msg
usage_msg:      db "mkfifo: missing operand", 10
usage_len:      equ $ - usage_msg

section .text
global          _start

_start:
    mov             r12, [rsp]          ;argc
    lea             r13, [rsp + 16]     ;&argv[1]
    cmp             r12, 2
    jl              usage_error

    mov             byte [m_flag], 0
    mov             qword [mode_val], DEFMODE
    dec             r12                 ;remaining arguments
    xor             r14, r14            ;exit status

opt_loop:
    cmp             r12, 0
    je              usage_error         ;options but no operand
    mov             rdi, [r13]
    cmp             byte [rdi], '-'
    jne             operands
    cmp             byte [rdi + 1], 0   ;lone "-" is an operand
    je              operands
    inc             rdi                 ;skip '-'
.char:
    movzx           eax, byte [rdi]
    test            al, al
    je              .next_opt
    cmp             al, 'm'
    je              .set_m
    inc             rdi                 ;ignore unknown option letters
    jmp             .char
.set_m:
    mov             byte [m_flag], 1
    inc             rdi
    cmp             byte [rdi], 0       ;mode attached (-mNNN) or next arg?
    jne             .mode_here
    add             r13, 8
    dec             r12
    mov             rdi, [r13]
.mode_here:
    call            parse_mode
.next_opt:
    add             r13, 8
    dec             r12
    jmp             opt_loop

operands:
    cmp             r12, 0
    je              done
    mov             rdi, [r13]
    call            make_fifo
    add             r13, 8
    dec             r12
    jmp             operands

done:
    mov             rdi, r14
    mov             rax, SYS_EXIT
    syscall

; parse_mode: rdi -> octal digits, result into mode_val
parse_mode:
    xor             rax, rax
.loop:
    movzx           rdx, byte [rdi]
    cmp             dl, '0'
    jb              .done
    cmp             dl, '7'
    ja              .done
    sub             dl, '0'
    shl             rax, 3
    add             rax, rdx
    inc             rdi
    jmp             .loop
.done:
    mov             [mode_val], rax
    ret

; make_fifo: rdi -> path, create a FIFO with the requested mode
make_fifo:
    push            rdi
    mov             rsi, [mode_val]
    or              rsi, S_IFIFO
    xor             rdx, rdx            ;dev_t unused for FIFOs
    mov             rax, SYS_MKNOD
    syscall
    pop             rdi
    test            rax, rax
    js              .fail
    cmp             byte [m_flag], 0
    je              .ok
    mov             rsi, [mode_val]     ;apply the exact mode (bypass umask)
    mov             rax, SYS_CHMOD
    syscall
.ok:
    ret
.fail:
    write           STDERR_FILENO, error_msg, error_len
    mov             r14, 1
    ret

usage_error:
    write           STDERR_FILENO, usage_msg, usage_len
    exit            1
