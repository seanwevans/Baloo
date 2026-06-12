; src/cut.asm

    %include "include/sysdefs.inc"

    %define MAX_RANGES 128
    %define OPEN_END 0x7fffffffffffffff
    %define LINE_CAP 8192

section .bss
    buffer       resb 1
    line_buffer  resb LINE_CAP
    line_len     resq 1
    fd           resq 1
    ranges_start resq MAX_RANGES
    ranges_end   resq MAX_RANGES
    range_count  resq 1
    mode         resq 1                 ;1 = byte/char, 2 = fields
    delimiter    resb 1
    suppress     resb 1

section .data
usage_msg   db "Usage: cut -b LIST | -c LIST | -f LIST [-d DELIM] [-s] [FILE]", 10
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    mov qword [fd], STDIN_FILENO
    mov qword [range_count], 0
    mov qword [mode], 0
    mov byte [delimiter], WHITESPACE_TAB
    mov byte [suppress], 0
    mov qword [line_len], 0

    pop r12                             ;argc
    pop rax                             ;argv[0]
    dec r12
    jle usage

parse_args:
    test r12, r12
    jz process

    pop rdi
    dec r12

    cmp byte [rdi], '-'
    jne open_input

    mov al, [rdi + 1]
    cmp al, 'b'
    je range_option
    cmp al, 'c'
    je range_option
    cmp al, 'f'
    je field_option
    cmp al, 'd'
    je delim_option
    cmp al, 's'
    je suppress_option
    cmp al, 'n'
    je ignore_option
    jmp usage

range_option:
    mov qword [mode], 1
    cmp byte [rdi + 2], 0
    jne inline_range
    test r12, r12
    jz usage
    pop rdi
    dec r12
    jmp parse_range_arg

field_option:
    mov qword [mode], 2
    cmp byte [rdi + 2], 0
    jne inline_range
    test r12, r12
    jz usage
    pop rdi
    dec r12
    jmp parse_range_arg

inline_range:
    lea rdi, [rdi + 2]

parse_range_arg:
    call parse_ranges
    jmp parse_args

delim_option:
    cmp byte [rdi + 2], 0
    jne inline_delim
    test r12, r12
    jz usage
    pop rdi
    dec r12
    mov al, [rdi]
    test al, al
    jz usage
    mov [delimiter], al
    jmp parse_args

inline_delim:
    mov al, [rdi + 2]
    mov [delimiter], al
    jmp parse_args

suppress_option:
    mov byte [suppress], 1
    jmp parse_args

ignore_option:
    jmp parse_args

open_input:
    mov rsi, rdi
    mov rdi, STDIN_FILENO
    call open_file
    mov [fd], rax
    jmp parse_args

process:
    cmp qword [range_count], 0
    je usage
    cmp qword [mode], 2
    je process_fields

    xor r12, r12                        ;1-based byte/character position in line
read_loop:
    mov rax, SYS_READ
    mov rdi, [fd]
    mov rsi, buffer
    mov rdx, 1
    syscall
    cmp rax, 0
    jle done

    cmp byte [buffer], WHITESPACE_NL
    je print_newline

    inc r12
    mov rdi, r12
    call is_selected
    test rax, rax
    jz read_loop
    call write_buffer
    jmp read_loop

print_newline:
    call write_buffer
    xor r12, r12
    jmp read_loop

process_fields:
    cmp byte [delimiter], WHITESPACE_NL
    je process_newline_fields
    jmp field_read_loop

process_newline_fields:
    mov r12, 1                          ;current newline-delimited field number
    xor r13, r13                        ;printed anything yet
    mov rdi, r12
    call is_selected
    mov r14, rax                        ;current field selected?

newline_field_loop:
    mov rax, SYS_READ
    mov rdi, [fd]
    mov rsi, buffer
    mov rdx, 1
    syscall
    cmp rax, 0
    jle done

    cmp byte [buffer], WHITESPACE_NL
    je newline_field_delim

    test r14, r14
    jz newline_field_loop
    call write_buffer
    mov r13, 1
    jmp newline_field_loop

newline_field_delim:
    test r14, r14
    jz .select_next
    mov byte [buffer], WHITESPACE_NL
    call write_buffer
.select_next:
    inc r12
    mov rdi, r12
    call is_selected
    mov r14, rax
    jmp newline_field_loop

field_read_loop:
    mov rax, SYS_READ
    mov rdi, [fd]
    mov rsi, buffer
    mov rdx, 1
    syscall
    cmp rax, 0
    jl done
    je fields_eof

    cmp byte [buffer], WHITESPACE_NL
    je fields_newline

    mov rax, [line_len]
    cmp rax, LINE_CAP
    jae field_read_loop                 ;truncate overlong input lines safely
    mov bl, [buffer]
    mov [line_buffer + rax], bl
    inc rax
    mov [line_len], rax
    jmp field_read_loop

fields_newline:
    mov rdi, 1                          ;append newline after this line
    call process_field_line
    mov qword [line_len], 0
    jmp field_read_loop

fields_eof:
    cmp qword [line_len], 0
    je done
    xor rdi, rdi                        ;no synthetic newline at EOF
    call process_field_line
    mov qword [line_len], 0
    jmp done

done:
    cmp qword [fd], STDIN_FILENO
    je exit_success
    mov rax, SYS_CLOSE
    mov rdi, [fd]
    syscall

exit_success:
    exit 0

usage:
    write STDERR_FILENO, usage_msg, usage_len
    exit 1

write_buffer:
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FILENO
    mov rsi, buffer
    mov rdx, 1
    syscall
    ret

write_one:
    mov [buffer], al
    call write_buffer
    ret

; rdi = 1 when a newline should be appended, 0 otherwise.
process_field_line:
    push rdi                            ;save newline flag

    xor r12, r12                        ;scan index
    mov r13, [line_len]
    xor r14, r14                        ;line has delimiter
.find_delim:
    cmp r12, r13
    jae .delim_scan_done
    mov al, [line_buffer + r12]
    cmp al, [delimiter]
    je .found_delim
    inc r12
    jmp .find_delim
.found_delim:
    mov r14, 1
.delim_scan_done:
    test r14, r14
    jnz .cut_fields

    cmp byte [suppress], 0
    jne .skip_line
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FILENO
    mov rsi, line_buffer
    mov rdx, [line_len]
    syscall
    jmp .append_newline

.skip_line:
    pop rdi
    ret

.cut_fields:
    xor r12, r12                        ;scan index
    mov r13, [line_len]
    mov r14, 1                          ;current field number
    xor r15, r15                        ;printed anything yet
    mov rdi, r14
    call is_selected
    mov r11, rax                        ;current field selected?

.field_loop:
    cmp r12, r13
    jae .append_newline
    mov al, [line_buffer + r12]
    cmp al, [delimiter]
    je .at_delim

    test r11, r11
    jz .next_char
    call write_one
    mov r15, 1
.next_char:
    inc r12
    jmp .field_loop

.at_delim:
    inc r14
    mov rdi, r14
    call is_selected
    mov r11, rax
    test r15, r15
    jz .skip_delim
    test r11, r11
    jz .skip_delim
    mov al, [delimiter]
    call write_one
.skip_delim:
    inc r12
    jmp .field_loop

.append_newline:
    pop rdi
    test rdi, rdi
    jz .done
    mov al, WHITESPACE_NL
    call write_one
.done:
    ret

; rdi = 1-based position. returns rax=1 when any range contains it.
is_selected:
    xor rcx, rcx
    mov r8, [range_count]
.check_loop:
    cmp rcx, r8
    jae .no
    mov rax, [ranges_start + rcx * 8]
    cmp rdi, rax
    jb .next
    mov rax, [ranges_end + rcx * 8]
    cmp rdi, rax
    jbe .yes
.next:
    inc rcx
    jmp .check_loop
.yes:
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

; rdi = comma-separated list of N, N-M, N-, or -M ranges.
parse_ranges:
    mov rsi, rdi
.next_range:
    mov rax, [range_count]
    cmp rax, MAX_RANGES
    jae usage

    xor r8, r8                          ;start
    xor r9, r9                          ;end

    cmp byte [rsi], '-'
    je .leading_dash

    call parse_number                   ;rax=number, rsi=next char
    test rax, rax
    jz usage
    mov r8, rax
    mov r9, rax

    cmp byte [rsi], '-'
    jne .finish_range
    inc rsi
    cmp byte [rsi], 0
    je .open_ended
    cmp byte [rsi], ','
    je .open_ended

    call parse_number
    test rax, rax
    jz usage
    mov r9, rax
    jmp .validate

.leading_dash:
    mov r8, 1
    inc rsi
    call parse_number
    test rax, rax
    jz usage
    mov r9, rax
    jmp .validate

.open_ended:
    mov r9, OPEN_END

.validate:
    cmp r9, r8
    jb usage

.finish_range:
    mov rcx, [range_count]
    mov [ranges_start + rcx * 8], r8
    mov [ranges_end + rcx * 8], r9
    inc rcx
    mov [range_count], rcx

    cmp byte [rsi], ','
    jne .done
    inc rsi
    cmp byte [rsi], 0
    je usage
    jmp .next_range
.done:
    cmp byte [rsi], 0
    jne usage
    ret

; rsi points at decimal digits. returns rax=number and advances rsi.
parse_number:
    xor rax, rax
    xor rcx, rcx
.loop:
    movzx rdx, byte [rsi]
    cmp rdx, '0'
    jb .done
    cmp rdx, '9'
    ja .done
    imul rax, 10
    sub rdx, '0'
    add rax, rdx
    inc rsi
    inc rcx
    jmp .loop
.done:
    test rcx, rcx
    jnz .have_digits
    xor rax, rax
.have_digits:
    ret
