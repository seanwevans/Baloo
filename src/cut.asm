; src/cut.asm

    %include "include/sysdefs.inc"

    %define MAX_RANGES 128
    %define OPEN_END 0x7fffffffffffffff

section .bss
    buffer       resb 1
    fd           resq 1
    ranges_start resq MAX_RANGES
    ranges_end   resq MAX_RANGES
    range_count  resq 1

section .data
usage_msg   db "Usage: cut -b LIST [FILE]", 10
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    mov qword [fd], STDIN_FILENO
    mov qword [range_count], 0

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
    jmp usage

range_option:
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

open_input:
    mov rsi, rdi
    mov rdi, STDIN_FILENO
    call open_file
    mov [fd], rax
    jmp parse_args

process:
    cmp qword [range_count], 0
    je usage

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
