; src/cmp.asm

    %include "include/sysdefs.inc"

section .bss
    buffer1         resb buffer_size    ;Buffer for file 1
    buffer2         resb buffer_size    ;Buffer for file 2
    file1_name      resq 1              ;Pointer to file1 name
    file2_name      resq 1              ;Pointer to file2 name
    file1_fd        resq 1              ;File descriptor for file 1
    file2_fd        resq 1              ;File descriptor for file 2
    byte_pos        resq 1              ;Byte position (0-indexed as per standard cmp)
    line_count      resq 1              ;Line number of difference
    digit_buffer    resb 32             ;Buffer for converting numbers to strings
    different       resq 1              ;Nonzero when files differ
    silent_flag     resq 1              ;Nonzero for -s

section .data
    buffer_size     equ 4096            ;Size of buffer for reading files
usage_msg       db "Usage: cmp file1 file2", 10, 0
    usage_len       equ $ - usage_msg
error_open_msg  db "Error: Cannot open file ", 0
    error_open_len  equ $ - error_open_msg
    newline         db 10, 0

    diff_format     db " "              ;Space between filenames
    diff_format_len equ $ - diff_format
    stdin_name      db "-", 0
differ_msg      db " differ: byte "     ; Standard cmp uses "byte" not "char"
    differ_len      equ $ - differ_msg
    line_msg        db ", line "
    line_len        equ $ - line_msg
cmp_prefix      db "cmp: EOF on "
    cmp_prefix_len  equ $ - cmp_prefix
    after_byte_msg  db " after byte "
    after_byte_len  equ $ - after_byte_msg

section .text
global          _start

_start:
    mov             qword [byte_pos], 0 ;Start byte position at 0 (0-indexed)
    mov             qword [line_count], 1 ;Start at line 1
    mov             qword [different], 0
    mov             qword [silent_flag], 0

    mov             rbx, [rsp]
    cmp             rbx, 4
    jne             .check_argc
    mov             rsi, [rsp + 16]
    cmp             byte [rsi], '-'
    jne             .check_argc
    cmp             byte [rsi + 1], 's'
    jne             .check_argc
    cmp             byte [rsi + 2], 0
    jne             .check_argc
    mov             qword [silent_flag], 1
    mov             rax, [rsp + 24]
    mov             [file1_name], rax
    mov             rax, [rsp + 32]
    mov             [file2_name], rax
    jmp             .open_files

.check_argc:
    cmp             rbx, 2
    je              .one_file
    cmp             rbx, 3
    jne             print_usage

    mov             rax, [rsp + 16]     ;file1
    mov             [file1_name], rax
    mov             rax, [rsp + 24]     ;file2
    mov             [file2_name], rax
    jmp             .open_files

.one_file:
    mov             rax, [rsp + 16]     ;file1
    mov             [file1_name], rax
    mov             qword [file2_name], stdin_name

.open_files:

    mov             rdi, [file1_name]
    call            open_input

    cmp             rax, 0
    jl              error_open_file1

    mov             [file1_fd], rax

    mov             rdi, [file2_name]
    call            open_input

    cmp             rax, 0
    jl              error_open_file2

    mov             [file2_fd], rax

    call            compare_files

    mov             rax, SYS_CLOSE
    mov             rdi, [file1_fd]
    syscall

    mov             rax, SYS_CLOSE
    mov             rdi, [file2_fd]
    syscall

    mov             rax, [different]
    cmp             rax, 0
    jne             exit_different

    exit            0

exit_different:
    exit            1

error_open_file1:
    write           STDERR_FILENO, error_open_msg, error_open_len

    mov             rsi, [file1_name]
    call            print_string_stderr

    write           STDERR_FILENO, newline, 1
    exit            2

error_open_file2:
    write           STDERR_FILENO, error_open_msg, error_open_len

    mov             rsi, [file2_name]
    call            print_string_stderr

    mov             rax, SYS_CLOSE
    mov             rdi, [file1_fd]
    syscall

    write           STDERR_FILENO, newline, 1
    exit            2

print_usage:
    write           STDERR_FILENO, usage_msg, usage_len
    exit            2

compare_files:
.read_loop:
    mov             rax, SYS_READ
    mov             rdi, [file1_fd]
    mov             rsi, buffer1
    mov             rdx, buffer_size
    syscall

    mov             r12, rax
    cmp             rax, 0
    jle             .check_file2_eof    ;If EOF or error, check if file 2 is also at EOF

    mov             rax, SYS_READ
    mov             rdi, [file2_fd]
    mov             rsi, buffer2
    mov             rdx, buffer_size
    syscall

    mov             r13, rax
    cmp             rax, 0
    jl              .exit_error

    cmp             r12, r13
    jne             .compare_buffers

    cmp             r12, 0
    je              .files_identical

.compare_buffers:
    mov             rcx, r12            ;Default to bytes from file 1
    cmp             rcx, r13            ;Compare with bytes from file 2
    jle             .min_bytes_set      ;If file 1 bytes <= file 2 bytes, keep rcx
    mov             rcx, r13            ;Otherwise, use file 2 bytes

.min_bytes_set:
    mov             rsi, buffer1        ;buffer1
    mov             rdi, buffer2        ;buffer2
    xor             r14, r14            ;buffer index

.compare_byte:
    cmp             r14, rcx            ;Check if we've compared all bytes
    jge             .check_buffer_sizes ;If yes, check if buffer sizes are different

    mov             al, byte [rsi + r14]
    cmp             al, byte [rdi + r14]
    jne             .difference_found   ;If different, report it

    cmp             al, 10              ;'\n'
    jne             .not_newline
    inc             qword [line_count]  ;Increment line counter

.not_newline:
    inc             r14                 ;Move to next byte
    jmp             .compare_byte       ;Continue comparing

.check_buffer_sizes:
    add             [byte_pos], rcx     ;Add compared bytes to total
    cmp             r12, r13
    jne             .eof_in_shorter     ;If buffer sizes different, report EOF

    jmp             .read_loop

.eof_in_shorter:
    cmp             r12, r13
    jg              .eof_file2
    mov             rsi, [file1_name]
    jmp             .print_eof
.eof_file2:
    mov             rsi, [file2_name]
.print_eof:
    mov             qword [different], 1
    dec             qword [line_count]
    cmp             qword [silent_flag], 1
    je              .silent_eof
    push            rsi
    write           STDERR_FILENO, cmp_prefix, cmp_prefix_len
    pop             rsi
    call            print_string_stderr
    write           STDERR_FILENO, after_byte_msg, after_byte_len
    mov             rax, [byte_pos]
    call            print_number_stderr
    write           STDERR_FILENO, line_msg, line_len
    mov             rax, [line_count]
    call            print_number_stderr
    write           STDERR_FILENO, newline, 1
.silent_eof:
    ret

.difference_found:
    add             qword [byte_pos], r14 ;Add our current index in the buffer
    mov             qword [different], 1

    cmp             qword [silent_flag], 1
    je              .silent_difference

    mov             rsi, [file1_name]
    call            print_string

    write           STDOUT_FILENO, diff_format, diff_format_len

    mov             rsi, [file2_name]
    call            print_string

    write           STDOUT_FILENO, differ_msg, differ_len

    mov             rax, [byte_pos]     ;Standard cmp reports 0-indexed positions
    inc             rax                 ;Adjust by 1 to match standard cmp behavior
    call            print_number

    write           STDOUT_FILENO, line_msg, line_len

    mov             rax, [line_count]
    call            print_number

    write           STDOUT_FILENO, newline, 1

.silent_difference:
    ret

.check_file2_eof:
    mov             rax, SYS_READ
    mov             rdi, [file2_fd]
    mov             rsi, buffer2
    mov             rdx, buffer_size
    syscall

    cmp             rax, 0
    je              .files_identical

    mov             qword [different], 1
    jmp             .difference_found

.files_identical:
    ret

.exit_error:
    exit            2

open_input:
    cmp             byte [rdi], '-'
    jne             .open
    cmp             byte [rdi + 1], 0
    jne             .open
    mov             rax, STDIN_FILENO
    ret
.open:
    mov             rax, SYS_OPEN
    mov             rsi, O_RDONLY
    xor             rdx, rdx
    syscall
    ret

print_string:
    push            rsi                 ;Save string pointer
    mov             rdx, 0              ;Initialize length counter
.strlen_loop:
    cmp             byte [rsi + rdx], 0 ;Check for null terminator
    je              .strlen_done
    inc             rdx                 ;Increment length
    jmp             .strlen_loop
.strlen_done:
    pop             rsi                 ;Restore string pointer
    mov             rax, SYS_WRITE
    mov             rdi, STDOUT_FILENO
    syscall
    ret

print_number_stderr:
    mov             rsi, digit_buffer + 31
    mov             byte [rsi], 0
    mov             r10, 10
    cmp             rax, 0
    jne             .convert_loop
    dec             rsi
    mov             byte [rsi], '0'
    jmp             .print_digits
.convert_loop:
    cmp             rax, 0
    je              .print_digits
    xor             rdx, rdx
    div             r10
    add             dl, '0'
    dec             rsi
    mov             [rsi], dl
    jmp             .convert_loop
.print_digits:
    call            print_string_stderr
    ret

print_string_stderr:
    push            rsi
    xor             rdx, rdx
.strlen_loop:
    cmp             byte [rsi + rdx], 0
    je              .strlen_done
    inc             rdx
    jmp             .strlen_loop
.strlen_done:
    pop             rsi
    mov             rax, SYS_WRITE
    mov             rdi, STDERR_FILENO
    syscall
    ret

print_number:
    mov             rsi, digit_buffer + 31 ;Point to end of buffer
    mov             byte [rsi], 0       ;Null terminator
    mov             r10, 10             ;Divisor
    cmp             rax, 0
    jne             .convert_loop

    dec             rsi
    mov             byte [rsi], '0'
    jmp             .print_digits

.convert_loop:
    cmp             rax, 0
    je              .print_digits

    xor             rdx, rdx            ;Clear rdx for division
    div             r10                 ;Divide rax by 10, remainder in rdx

    add             dl, '0'             ;Convert remainder to ASCII
    dec             rsi                 ;Move pointer
    mov             [rsi], dl           ;Store digit

    jmp             .convert_loop

.print_digits:
    call            print_string
    ret
