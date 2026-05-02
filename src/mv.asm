; src/mv.asm

    %include "include/sysdefs.inc"

section .bss
    source_path     resb 4096           ;source path
    dest_path       resb 4096           ;destination path

section .data
error_usage     db "Usage: mv source destination", 10, 0
error_rename    db "Error: Cannot rename/move file", 10, 0

section .text
global          _start

_start:
    pop             rcx                 ;Get argc
    cmp             rcx, 3              ;Check if we have 2 arguments (source and destination)
    jne             usage_error         ;If not, display usage error

    pop             rdi                 ;Skip argv[0] (program name)
    pop             rdi                 ;Get argv[1] (source path)
    mov             rsi, source_path    ;Destination buffer
    call            copy_string

    pop             rdi                 ;Get argv[2] (destination path)
    mov             rsi, dest_path      ;Destination buffer
    call            copy_string

    mov             rax, SYS_RENAME
    mov             rdi, source_path    ;Source path
    mov             rsi, dest_path      ;Destination path
    syscall

    test            rax, rax            ;Check if rename succeeded
    js              rename_error        ;If failed, show rename error

    exit            0

usage_error:
    mov             rdi, error_usage
    call            print_string
    exit            1

rename_error:
    mov             rdi, error_rename
    call            print_string
    exit            1

copy_string:
    xor             rcx, rcx            ;Initialize counter

.loop:
    mov             al, [rdi + rcx]     ;Get character from source
    mov             [rsi + rcx], al     ;Copy to destination
    inc             rcx                 ;Increment counter
    test            al, al              ;Check if null terminator
    jnz             .loop               ;If not, continue
    ret

print_string:
    mov             rsi, rdi            ;String to print
    mov             rdx, 0              ;Initialize length counter

.count:
    cmp             byte [rsi + rdx], 0 ;Check for null terminator
    je              .print              ;If found, print the string
    inc             rdx                 ;Increment length counter
    jmp             .count              ;Continue counting
.print:
    write           STDERR_FILENO, rsi, rdx ;Write string to stderr
    ret
