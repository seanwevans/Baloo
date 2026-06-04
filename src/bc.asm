; src/bc.asm

    %include "include/sysdefs.inc"

section .bss
    input_buffer resb 8193
    num_buffer   resb 32

section .data
    decimal_base dq 10
    newline      db WHITESPACE_NL
usage_msg   db "Usage: bc [file ...]", WHITESPACE_NL
    usage_len    equ $ - usage_msg
    syntax_msg  db "syntax error", WHITESPACE_NL
    syntax_len   equ $ - syntax_msg
    read_msg    db "Error reading input", WHITESPACE_NL
    read_len     equ $ - read_msg
    open_msg    db "Error opening file", WHITESPACE_NL
    open_len     equ $ - open_msg
div_zero_msg db "Runtime error: divide by zero", WHITESPACE_NL
    div_zero_len equ $ - div_zero_msg

section .text
global _start

_start:
    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;argv[1]

    cmp     r12, 1
    je      read_stdin

    dec     r12                         ;number of file operands
file_loop:
    cmp     r12, 0
    je      exit_ok

    mov     rdi, [r13]
    call    process_file
    add     r13, 8
    dec     r12
    jmp     file_loop

read_stdin:
    mov     rdi, STDIN_FILENO
    call    read_fd
    mov     rsi, input_buffer
    call    process_buffer
    jmp     exit_ok

process_file:
    push    r12
    push    r13

    mov     rsi, O_RDONLY
    xor     rdx, rdx
    mov     rax, SYS_OPEN
    syscall
    cmp     rax, 0
    jl      open_error

    mov     r12, rax                    ;fd
    mov     rdi, r12
    call    read_fd

    mov     rdi, r12
    mov     rax, SYS_CLOSE
    syscall

    mov     rsi, input_buffer
    call    process_buffer

    pop     r13
    pop     r12
    ret

read_fd:
    mov     r8, rdi                     ;fd
    xor     r9, r9                      ;bytes used
.read_loop:
    mov     rdi, r8
    lea     rsi, [input_buffer + r9]
    mov     rdx, 8192
    sub     rdx, r9
    cmp     rdx, 0
    je      .done
    mov     rax, SYS_READ
    syscall
    cmp     rax, 0
    jl      read_error
    cmp     rax, 0
    je      .done
    add     r9, rax
    jmp     .read_loop
.done:
    mov     byte [input_buffer + r9], 0
    ret

process_buffer:
.statement_loop:
    call    skip_separators
    movzx   eax, byte [rsi]
    cmp     al, 0
    je      .done

    call    parse_expr
    push    rax
    call    skip_spaces

    movzx   edx, byte [rsi]
    cmp     dl, 0
    je      .print
    cmp     dl, WHITESPACE_NL
    je      .print_advance
    cmp     dl, 59
    je      .print_advance
    jmp     syntax_error

.print_advance:
    inc     rsi
.print:
    pop     rax
    push    rsi
    call    print_int
    write   STDOUT_FILENO, newline, 1
    pop     rsi
    jmp     .statement_loop
.done:
    ret

skip_separators:
.loop:
    movzx   eax, byte [rsi]
    cmp     al, WHITESPACE_SPACE
    je      .advance
    cmp     al, WHITESPACE_TAB
    je      .advance
    cmp     al, WHITESPACE_NL
    je      .advance
    cmp     al, 59
    je      .advance
    ret
.advance:
    inc     rsi
    jmp     .loop

skip_spaces:
.loop:
    movzx   eax, byte [rsi]
    cmp     al, WHITESPACE_SPACE
    je      .advance
    cmp     al, WHITESPACE_TAB
    je      .advance
    ret
.advance:
    inc     rsi
    jmp     .loop

parse_expr:
    call    parse_term
.loop:
    push    rax
    call    skip_spaces
    movzx   edx, byte [rsi]
    cmp     dl, '+'
    je      .add
    cmp     dl, '-'
    je      .sub
    pop     rax
    ret
.add:
    inc     rsi
    call    parse_term
    mov     rcx, rax
    pop     rax
    add     rax, rcx
    jmp     .loop
.sub:
    inc     rsi
    call    parse_term
    mov     rcx, rax
    pop     rax
    sub     rax, rcx
    jmp     .loop

parse_term:
    call    parse_power
.loop:
    push    rax
    call    skip_spaces
    movzx   edx, byte [rsi]
    cmp     dl, '*'
    je      .mul
    cmp     dl, '/'
    je      .div
    cmp     dl, '%'
    je      .mod
    pop     rax
    ret
.mul:
    inc     rsi
    call    parse_power
    mov     rcx, rax
    pop     rax
    imul    rax, rcx
    jmp     .loop
.div:
    inc     rsi
    call    parse_power
    mov     rcx, rax
    cmp     rcx, 0
    je      div_zero_error
    pop     rax
    cqo
    idiv    rcx
    jmp     .loop
.mod:
    inc     rsi
    call    parse_power
    mov     rcx, rax
    cmp     rcx, 0
    je      div_zero_error
    pop     rax
    cqo
    idiv    rcx
    mov     rax, rdx
    jmp     .loop

parse_power:
    call    parse_unary
    push    rax
    call    skip_spaces
    movzx   edx, byte [rsi]
    cmp     dl, '^'
    je      .pow
    pop     rax
    ret
.pow:
    inc     rsi
    call    parse_unary
    mov     rcx, rax                    ;exponent
    pop     rbx                         ;base
    cmp     rcx, 0
    jl      syntax_error
    mov     rax, 1
.pow_loop:
    cmp     rcx, 0
    je      .done
    imul    rax, rbx
    dec     rcx
    jmp     .pow_loop
.done:
    ret

parse_unary:
    call    skip_spaces
    movzx   edx, byte [rsi]
    cmp     dl, '+'
    je      .plus
    cmp     dl, '-'
    je      .minus
    jmp     parse_primary
.plus:
    inc     rsi
    jmp     parse_unary
.minus:
    inc     rsi
    call    parse_unary
    neg     rax
    ret

parse_primary:
    call    skip_spaces
    movzx   edx, byte [rsi]
    cmp     dl, '('
    je      .paren
    cmp     dl, '0'
    jb      syntax_error
    cmp     dl, '9'
    ja      syntax_error
    jmp     parse_number
.paren:
    inc     rsi
    call    parse_expr
    push    rax
    call    skip_spaces
    movzx   edx, byte [rsi]
    cmp     dl, ')'
    jne     syntax_error
    inc     rsi
    pop     rax
    ret

parse_number:
    xor     rax, rax
.loop:
    movzx   rdx, byte [rsi]
    cmp     dl, '0'
    jb      .done
    cmp     dl, '9'
    ja      .done
    sub     dl, '0'
    imul    rax, 10
    add     rax, rdx
    inc     rsi
    jmp     .loop
.done:
    ret

print_int:
    mov     rbx, num_buffer
    add     rbx, 31
    mov     byte [rbx], 0
    dec     rbx
    xor     rcx, rcx
    cmp     rax, 0
    jge     .convert
    neg     rax
    mov     rcx, 1
.convert:
    xor     rdx, rdx
    div     qword [decimal_base]
    add     dl, '0'
    mov     [rbx], dl
    dec     rbx
    test    rax, rax
    jnz     .convert
    cmp     rcx, 1
    jne     .print
    mov     byte [rbx], '-'
    dec     rbx
.print:
    inc     rbx
    mov     rdx, num_buffer
    add     rdx, 31
    sub     rdx, rbx
    write   STDOUT_FILENO, rbx, rdx
    ret

open_error:
    write   STDERR_FILENO, open_msg, open_len
    exit    1

read_error:
    write   STDERR_FILENO, read_msg, read_len
    exit    1

syntax_error:
    write   STDERR_FILENO, syntax_msg, syntax_len
    exit    1

div_zero_error:
    write   STDERR_FILENO, div_zero_msg, div_zero_len
    exit    1

print_usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

exit_ok:
    exit    0
