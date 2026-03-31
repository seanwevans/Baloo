; src/chown.asm

%include "include/sysdefs.inc"

section .bss

section .data
    usage_msg       db "Usage: chown_numeric UID[:GID] file", 10
    usage_len       equ $ - usage_msg
    error_chown     db "chown failed", 10
    error_chown_len equ $ - error_chown
    error_format    db "Invalid UID/GID format", 10
    error_format_len equ $ - error_format
    error_argv      db "Argument error", 10
    error_argv_len  equ $ - error_argv
    colon           db ":"

section .text
    global          _start

_start:
    mov             r12, [rsp]          ; argc
    cmp             r12, 3
    jne             .print_usage        ; Must have 3 args

    mov             r13, [rsp+16]       ; argv[1] (owner/group spec)
    mov             r14, [rsp+24]       ; argv[2] (file path)
    mov             r8d, 0xFFFFFFFF     ; target UID
    mov             r9d, 0xFFFFFFFF     ; target GID

    mov             rdi, r13            ; String to parse
    xor             rcx, rcx
    xor             r10, r10

.find_colon_loop:
    mov             al, [rdi+rcx]
    cmp             al, 0
    je              .colon_search_done
    cmp             al, ':'
    je              .found_colon
    inc             rcx
    jmp             .find_colon_loop

.found_colon:
    lea             r10, [rdi+rcx]      ; address of colon

.colon_search_done:
    cmp             r10, 0              ; Was colon found?
    je              .no_colon           ; No colon, parse entire string as UID

    cmp             r10, rdi            ; Is colon the first character? (e.g., ":1000")
    je              .colon_is_first

    mov             byte [r10], 0       ; Temporarily null-terminate UID part
    call            parse_uint          ; Parse UID part
    jc              .print_format_error ; parse error
    mov             r8d, eax            ; parsed UID
    mov             byte [r10], ':'     ; Restore colon

.colon_is_first:
    inc             r10                 ; Move past the colon
    cmp             byte [r10], 0       ; Is there anything after the colon?
    je              .parse_done         ; No, GID remains -1 (e.g., "1000:")

    mov             rdi, r10            ; String to parse
    call            parse_uint          ; GID part
    jc              .print_format_error ; parse error
    mov             r9d, eax            ; parsed GID
    jmp             .parse_done

.no_colon:
    call            parse_uint          ; Parse UID
    jc              .print_format_error ; parse error
    mov             r8d, eax            ; parsed UID

.parse_done:
    mov             rax, SYS_CHOWN
    mov             rdi, r14            ; pathname
    mov             esi, r8d            ; owner (UID)
    mov             edx, r9d            ; group (GID)
    syscall

    test            rax, rax
    jns             .exit_success
    
    mov             rax, SYS_WRITE
    mov             rdi, STDERR_FILENO
    lea             rsi, [rel error_chown]
    mov             rdx, error_chown_len
    syscall
    
    jmp             .exit_error

.print_usage:
    mov             rax, SYS_WRITE
    mov             rdi, STDERR_FILENO
    lea             rsi, [rel usage_msg]
    mov             rdx, usage_len
    syscall
    
    jmp             .exit_error_args

.print_format_error:
    mov             rax, SYS_WRITE
    mov             rdi, STDERR_FILENO
    lea             rsi, [rel error_format]
    mov             rdx, error_format_len
    syscall
    
    jmp             .exit_error

.exit_success:
    exit            0

.exit_error:
    exit            1

.exit_error_args:
    exit            2

parse_uint:
    xor             rax, rax            ; Accumulator (result)
    xor             rcx, rcx            ; Pointer/index within string
.loop:
    mov             dl, [rdi+rcx]       ; Get character
    cmp             dl, 0
    je              .done               ; End of string

    cmp             dl, '0'
    jl              .error              ; Not a digit
    cmp             dl, '9'
    jg              .error              ; Not a digit

    sub             dl, '0'             ; Convert char to integer value

    imul            rax, rax, 10        ; Multiply accumulator by 10
    jo              .error              ; Check overflow flag after multiplication

    movzx           r11, dl             ; Zero-extend digit for full-width add
    add             rax, r11            ; Add digit to full accumulator
    jc              .error

    mov             r11d, 0xFFFFFFFF    ; Keep value within 32-bit unsigned range
    cmp             rax, r11
    ja              .error

    inc             rcx
    jmp             .loop

.done:
    cmp             rcx, 0
    je              .error

    clc
    ret

.error:
    stc
    ret