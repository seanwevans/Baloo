; src/base32.asm

    %include "include/sysdefs.inc"

section .bss
    inbuf       resb 5                  ;Input buffer
    outbuf      resb 8192               ;Output buffer

section .data
    base32_table db BASE32_TABLE
    nl          db WHITESPACE_NL

section .text
global      _start

_start:
    pop         rax                     ;Get argc
    pop         rax                     ;skip program name
    cmp         rax, 0

    jle         use_stdin               ;If no args, read from stdin

    pop         rsi                     ;Get filename

    mov         rax, SYS_OPEN
    mov         rdi, rsi                ;copy filename
    mov         rsi, O_RDONLY           ;open in read-only mode
    xor         rdx, rdx                ;no special mode
    syscall

    cmp         rax, 0
    jl          exit_error              ;If open failed, exit

    mov         r14, rax                ;r14 = file descriptor
    jmp         start_encoding

use_stdin:
    mov         r14, STDIN_FILENO

start_encoding:
    xor         r12, r12                ;r12 = bytes in outbuf
    xor         r13, r13                ;r13 = line length counter

process_input:
    mov         rax, SYS_READ
    mov         rdi, r14
    lea         rsi, [inbuf]
    mov         rdx, 5                  ;Read 5 bytes at a time
    syscall

    cmp         rax, 0
    jl          exit_error              ;If read error, exit
    je          flush_and_exit          ;If EOF (0 bytes read), flush and exit

    mov         rcx, rax                ;rcx = bytes read (1-5)

    cmp         rcx, 5
    je          encode_block

    cmp         rcx, 4
    je          zero_one_byte

    cmp         rcx, 3
    je          zero_two_bytes

    cmp         rcx, 2
    je          zero_three_bytes

    mov         byte [inbuf + 1], 0
zero_three_bytes:
    mov         byte [inbuf + 2], 0
zero_two_bytes:
    mov         byte [inbuf + 3], 0
zero_one_byte:
    mov         byte [inbuf + 4], 0

encode_block:
    xor         rax, rax
    mov         al, byte [inbuf]
    shl         rax, 8
    mov         al, byte [inbuf + 1]
    shl         rax, 8
    mov         al, byte [inbuf + 2]
    shl         rax, 8
    mov         al, byte [inbuf + 3]
    shl         rax, 8
    mov         al, byte [inbuf + 4]

    mov         r8, rax                 ;Save original 40 bits

    mov         rdx, r8
    shr         rdx, 35
    and         rdx, 0x1F
    mov         dl, byte [base32_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13

    mov         rdx, r8
    shr         rdx, 30
    and         rdx, 0x1F
    mov         dl, byte [base32_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13

    mov         rdx, r8
    shr         rdx, 25
    and         rdx, 0x1F
    mov         dl, byte [base32_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13

    mov         rdx, r8
    shr         rdx, 20
    and         rdx, 0x1F
    mov         dl, byte [base32_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13

    mov         rdx, r8
    shr         rdx, 15
    and         rdx, 0x1F
    mov         dl, byte [base32_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13

    mov         rdx, r8
    shr         rdx, 10
    and         rdx, 0x1F
    mov         dl, byte [base32_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13

    mov         rdx, r8
    shr         rdx, 5
    and         rdx, 0x1F
    mov         dl, byte [base32_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13

    mov         rdx, r8
    and         rdx, 0x1F
    mov         dl, byte [base32_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13

    cmp         rcx, 5
    je          check_line_wrap

    cmp         rcx, 4
    je          pad_one_char

    cmp         rcx, 3
    je          pad_three_chars

    cmp         rcx, 2
    je          pad_four_chars

; rcx == 1
    mov         byte [outbuf + r12 - 1], '='
    mov         byte [outbuf + r12 - 2], '='
    mov         byte [outbuf + r12 - 3], '='
    mov         byte [outbuf + r12 - 4], '='
    mov         byte [outbuf + r12 - 5], '='
    mov         byte [outbuf + r12 - 6], '='
    jmp         check_line_wrap

pad_four_chars:
    mov         byte [outbuf + r12 - 1], '='
    mov         byte [outbuf + r12 - 2], '='
    mov         byte [outbuf + r12 - 3], '='
    mov         byte [outbuf + r12 - 4], '='
    jmp         check_line_wrap

pad_three_chars:
    mov         byte [outbuf + r12 - 1], '='
    mov         byte [outbuf + r12 - 2], '='
    mov         byte [outbuf + r12 - 3], '='
    jmp         check_line_wrap

pad_one_char:
    mov         byte [outbuf + r12 - 1], '='

check_line_wrap:
    cmp         r13, 76
    jl          check_flush

    mov         byte [outbuf + r12], 10 ;Add newline
    inc         r12
    xor         r13, r13                ;Reset line counter

check_flush:
    cmp         r12, 8000
    jl          process_input

    call        flush_output
    jmp         process_input

flush_and_exit:
    test        r12, r12
    jz          check_close

    call        flush_output

    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    lea         rsi, [nl]
    mov         rdx, 1
    syscall

check_close:
    cmp         r14, STDIN_FILENO
    je          exit_success

    mov         rax, SYS_CLOSE
    mov         rdi, r14
    syscall

exit_success:
    exit        0

exit_error:
    cmp         r14, STDIN_FILENO
    je          error_exit_noclosefile

    mov         rax, SYS_CLOSE
    mov         rdi, r14
    syscall

error_exit_noclosefile:
    exit        1

flush_output:
    push        rbp
    mov         rbp, rsp

    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    lea         rsi, [outbuf]
    mov         rdx, r12
    syscall

    xor         r12, r12

    pop         rbp
    ret
