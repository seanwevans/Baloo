; src/baseenc.asm

%include "include/sysdefs.inc"

section .bss
    inbuf       resb 3                          ; Input buffer
    outbuf      resb 8192                       ; Output buffer
    filepath    resb 256                        ; filepath buffer

section .data
    base64_table db BASE64_TABLE
    nl          db WHITESPACE_NL
    
section .text
    global      _start

_start:
    pop         rax                             ; Get argc
    pop         rax                             ; skip program name
    cmp         rax, 0

    jle         use_stdin                       ; If no args, read from stdin

    pop         rsi                             ; Get filename

    mov         rax, SYS_OPEN   
    mov         rdi, rsi                        ; copy filename
    mov         rsi, O_RDONLY                   ; open in read-only mode
    xor         rdx, rdx                        ; no special mode
    syscall

    cmp         rax, 0
    jl          exit_error                      ; If open failed, exit

    mov         r14, rax                        ; r14 = file descriptor
    jmp         start_encoding

use_stdin:
    mov         r14, STDIN_FILENO
    
start_encoding:
    xor         r12, r12                        ; r12 = bytes in outbuf
    xor         r13, r13                        ; r13 = line length counter
    
process_input:
    mov         rax, SYS_READ
    mov         rdi, r14
    lea         rsi, [inbuf]
    mov         rdx, 3                          ; Read 3 bytes at a time
    syscall

    cmp         rax, 0
    jl          exit_error                      ; If read error, exit
    je          flush_and_exit                  ; If EOF (0 bytes read), flush and exit

    mov         rcx, rax                        ; rcx = bytes read (1-3)

    cmp         rcx, 3
    je          encode_block                    ; If we read 3 bytes, no need to zero out

    cmp         rcx, 1
    je          zero_two_bytes

    mov         byte [inbuf + 2], 0
    jmp         encode_block
    
zero_two_bytes:
    mov         byte [inbuf + 1], 0
    mov         byte [inbuf + 2], 0
    
encode_block:
    xor         rax, rax
    mov         al, byte [inbuf]                ; First byte
    shl         rax, 8
    mov         al, byte [inbuf + 1]            ; Second byte
    shl         rax, 8
    mov         al, byte [inbuf + 2]            ; Third byte

    mov         r8, rax                         ; Save original 24 bits

    mov         rdx, r8
    shr         rdx, 18                         ; First 6 bits
    and         rdx, 0x3F                       ; Mask to 6 bits
    mov         dl, byte [base64_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13                             ; Increment line position counter
    
    mov         rdx, r8
    shr         rdx, 12                         ; Next 6 bits
    and         rdx, 0x3F
    mov         dl, byte [base64_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13
    
    mov         rdx, r8
    shr         rdx, 6                          ; Next 6 bits
    and         rdx, 0x3F
    mov         dl, byte [base64_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13
    
    mov         rdx, r8                         ; Last 6 bits
    and         rdx, 0x3F
    mov         dl, byte [base64_table + rdx]
    mov         byte [outbuf + r12], dl
    inc         r12
    inc         r13

    cmp         rcx, 3
    je          check_line_wrap                 ; If 3 bytes read, no padding needed
    
    cmp         rcx, 1
    je          pad_two_chars

    mov         byte [outbuf + r12 - 1], '='    ; Replace last character with '='
    jmp         check_line_wrap
    
pad_two_chars:
    mov         byte [outbuf + r12 - 1], '='    ; Replace last character with '='
    mov         byte [outbuf + r12 - 2], '='    ; Replace second-to-last character with '='
    
check_line_wrap:
    cmp         r13, 76
    jl          check_flush
    
    mov         byte [outbuf + r12], 10         ; Add newline
    inc         r12
    xor         r13, r13                        ; Reset line counter
    
check_flush:
    cmp         r12, 8000                       ; Leave some margin
    jl          process_input                   ; If buffer not full, continue processing

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
    je          exit_success                    ; If using stdin, no need to close

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
