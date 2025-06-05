; src/wc.asm

    %include "include/sysdefs.inc"

section .bss
    buffer  resb 4096                   ;file buffer
    number_str resb 32                  ;conversion buffer

section .data
    space   db " "
    newline db WHITESPACE_NL

section .text
global  _start

_start:
    mov     rdi, [rsp]                  ;argc
    cmp     rdi, 2                      ;file argument?
    jb      use_stdin                   ;use standard input

    mov     rax, [rsp+16]
    mov     rdi, rax
    mov     rsi, O_RDONLY
    mov     rdx, 0
    mov     rax, SYS_OPEN
    syscall

    cmp     rax, 0                      ;open succeeded?
    jl      exit_fail                   ;error

    mov     r12, rax                    ;file descriptor
    jmp     process_file

use_stdin:
    mov     r12, STDIN_FILENO           ;use standard input if no file argument

process_file:
    xor     r13, r13                    ;line count = 0
    xor     r14, r14                    ;word count = 0
    xor     r15, r15                    ;byte count = 0
    xor     rbx, rbx                    ;word flag (0 = outside word)

read_loop:
    mov     rdi, r12                    ;file descriptor
    mov     rsi, buffer                 ;pointer to buffer for reading
    mov     rdx, 4096                   ;read up to 4096 bytes
    mov     rax, SYS_READ
    syscall

    cmp     rax, 0                      ;check for end-of-file (0 bytes read)
    je      cleanup_file

    cmp     rax, 0                      ;check for read error (<0)
    jl      exit_fail

    add     r15, rax                    ;add number of bytes read to total byte count
    mov     rcx, rax                    ;set inner loop counter to number of bytes read
    mov     rsi, buffer                 ;reset buffer pointer

process_buffer:
    cmp     rcx, 0                      ;check if buffer fully processed
    je      read_loop_continue          ;if done, continue reading more data

    dec     rcx                         ;decrement byte counter
    mov     al, [rsi]                   ;load current byte into AL
    inc     rsi                         ;advance buffer pointer
    cmp     al, 10                      ;check if byte is newline (LF)
    je      count_newline

    cmp     al, 9                       ;check if byte is a tab character
    je      reset_word

    cmp     al, 32                      ;check if byte is a space character
    je      reset_word

    cmp     rbx, 0                      ;if word flag is 0 (not in word)
    jne     process_buffer              ;if already inside a word, continue

mov     rbx, 1              ; set word flag: entering a word
    inc     r14                         ;increment word count
    jmp     process_buffer

reset_word:
    mov     rbx, 0                      ;reset word flag (outside a word)
    jmp     process_buffer

count_newline:
    inc     r13                         ;increment line count
    mov     rbx, 0                      ;reset word flag after newline
    jmp     process_buffer

read_loop_continue:
    jmp     read_loop                   ;go back to read next chunk

cleanup_file:
    cmp     r12, STDIN_FILENO           ;check if file descriptor is not STDIN
    je      print_results               ;if STDIN, skip closing

    mov     rdi, r12                    ;set file descriptor for close syscall
    mov     rax, SYS_CLOSE
    syscall

print_results:
    mov     rdi, r13                    ;line count
    call    print_decimal

    mov     rdi, STDOUT_FILENO
    mov     rsi, space
    mov     rdx, 1
    mov     rax, SYS_WRITE
    syscall

    mov     rdi, r14                    ;word count
    call    print_decimal

    mov     rdi, STDOUT_FILENO
    mov     rsi, space
    mov     rdx, 1
    mov     rax, SYS_WRITE
    syscall

    mov     rdi, r15                    ;byte count
    call    print_decimal
    mov     rdi, STDOUT_FILENO
    mov     rsi, newline
    mov     rdx, 1
    mov     rax, SYS_WRITE
    syscall

    mov     rdi, 0
    exit    0

exit_fail:
    mov     rdi, 1
    exit    1

print_decimal:
    push    rbx
    cmp     rdi, 0
    jne     .print_loop_start

    mov     byte [number_str+31], '0'
    mov     rdx, 1
    mov     rsi, number_str+31
    mov     rdi, STDOUT_FILENO
    mov     rax, SYS_WRITE
    syscall

    pop     rbx
    ret

.print_loop_start:
    mov     rsi, number_str+32          ;end of the conversion buffer
    xor     rcx, rcx                    ;clear digit counter
    mov     rax, rdi                    ;division
    mov     r8, 10                      ;divisor constant 10

.print_loop:
    xor     rdx, rdx
    div     r8
    add     rdx, '0'
    dec     rsi
    mov     [rsi], dl                   ;ASCII
    inc     rcx
    test    rax, rax
    jnz     .print_loop                 ;repeat if quotient is not zero

    mov     rdi, STDOUT_FILENO          ;set file descriptor for STDOUT
    mov     rax, SYS_WRITE              ;syscall number for write
    mov     rdx, rcx                    ;length equals number of digits
    syscall

    pop     rbx                         ;restore rbx
    ret
