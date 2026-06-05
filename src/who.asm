; src/who.asm

    %include "include/sysdefs.inc"

section .bss
    utmp_buf        resb UTMP_SIZE

section .data
    utmp_run        db "/run/utmp", 0
    utmp_file       db "/var/run/utmp", 0
errmsg_open     db "who: cannot open utmp file", 10
    errmsg_open_len equ $ - errmsg_open
errmsg_read     db "who: cannot read utmp file", 10
    errmsg_read_len equ $ - errmsg_read
    newline         db WHITESPACE_NL
    tab             db 9

section .text
global          _start

_start:
    cmp             qword [rsp], 2
    jl              .open_default_utmp
    mov             rdi, [rsp + 16]     ;Optional FILE argument
    jmp             .open_selected_utmp

.open_default_utmp:
    mov             rdi, utmp_run       ;try modern path first
    call            .try_open_utmp
    cmp             rax, 0
    jge             .opened

    mov             rdi, utmp_file      ;fall back to legacy path

.open_selected_utmp:
    call            .try_open_utmp
    cmp             rax, 0
    jl              .no_utmp            ;no utmp -> no logged-in users
    jmp             .opened

.try_open_utmp:
    mov             rax, SYS_OPEN
    mov             rsi, O_RDONLY
    mov             rdx, 0
    syscall
    ret

.opened:
    mov             r12, rax            ;file descriptor

.read_loop:
    mov             rax, SYS_READ
    mov             rdi, r12            ;file descriptor
    mov             rsi, utmp_buf       ;buffer address
    mov             rdx, UTMP_SIZE      ;size of one record
    syscall

    cmp             rax, 0
    jle             .done

    cmp             rax, UTMP_SIZE
    jne             .read_error

    mov             ax, word [utmp_buf + UT_TYPE_OFF]
    cmp             ax, EMPTY
    je              .read_loop          ;If it's an empty record, skip it and read the next

    mov             rdi, utmp_buf + UT_USER_OFF ;Address of username field in buffer
    mov             rsi, UT_NAMESIZE    ;Max size of the field
    call            print_field_padded

    mov             rax, SYS_WRITE
    mov             rdi, STDOUT_FILENO
    mov             rsi, tab
    mov             rdx, 1
    syscall

    mov             rdi, utmp_buf + UT_LINE_OFF ;Address of line field in buffer
    mov             rsi, UT_LINESIZE    ;Max size of the field
    call            print_field_padded  ;Call helper function to print it

    mov             rax, SYS_WRITE
    mov             rdi, STDOUT_FILENO
    mov             rsi, tab
    mov             rdx, 1
    syscall

    mov             eax, dword [utmp_buf + UT_TV_OFF]
    call            print_uint32_dec    ;Call helper to print unsigned int in eax

    mov             rax, SYS_WRITE
    mov             rdi, STDOUT_FILENO
    mov             rsi, newline
    mov             rdx, 1
    syscall

    jmp             .read_loop          ;Go back to read the next record

.done:
    cmp             rax, 0              ;Check rax from the last SYS_READ call
    jl              .read_error         ;read error, jump to handler

.close_and_exit_ok:
    mov             rax, SYS_CLOSE
    mov             rdi, r12
    syscall
    exit            0

.no_utmp:
    exit            0

.read_error:
    mov             rax, SYS_WRITE
    mov             rdi, STDERR_FILENO
    mov             rsi, errmsg_read
    mov             rdx, errmsg_read_len
    syscall

    mov             rax, SYS_CLOSE
    mov             rdi, r12            ;file descriptor
    syscall
    exit            1

print_field_padded:
    mov             rdx, 0
    mov             rcx, rsi
    mov             rsi, rdi

.scan_loop:
    cmp             rcx, 0
    je              .do_write

    cmp             byte [rsi], 0       ;Check if the current byte is a null terminator
    je              .do_write

    inc             rsi                 ;Move scan pointer to the next byte
    inc             rdx                 ;Increment the length count
    dec             rcx                 ;Decrement the max size counter
    jmp             .scan_loop          ;Continue scanning

.do_write:
    cmp             rdx, 0
    jle             .skip_write

    mov             rax, SYS_WRITE
    mov             rsi, rdi            ;buffer address
    mov             rdi, STDOUT_FILENO
    syscall

.skip_write:
    ret

print_uint32_dec:
    sub             rsp, 16
    mov             rdi, rsp
    add             rdi, 10
    mov             byte [rdi], 0
    mov             rcx, rdi
    mov             ebx, 10
    test            eax, eax
    jnz             .conversion_loop

    dec             rdi
    mov             byte [rdi], '0'
    jmp             .print_number

.conversion_loop:
xor             edx, edx            ; Clear edx for 32-bit division (edx:eax / ebx)
    div             ebx                 ;eax = quotient, edx = remainder
    add             dl, '0'             ;Convert remainder (0-9) to ASCII ('0'-'9')
    dec             rdi                 ;Move buffer pointer back
    mov             [rdi], dl           ;Store ASCII digit in buffer
    test            eax, eax            ;Check if quotient is zero
    jnz             .conversion_loop    ;If not zero, continue loop

.print_number:
    sub             rcx, rdi
    mov             rdx, rcx            ;length of the string
    mov             rax, SYS_WRITE
    mov             rsi, rdi            ;start of digits
    mov             rdi, STDOUT_FILENO
    syscall

    add rsp, 16
    ret
