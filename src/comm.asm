; src/comm.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 4096
%define LINE_BUFFER_SIZE 1024

section .bss
    buffer1     resb BUFFER_SIZE
    buffer2     resb BUFFER_SIZE
    line1       resb LINE_BUFFER_SIZE
    line2       resb LINE_BUFFER_SIZE
    fd1         resq 1
    fd2         resq 1
    bytes1      resq 1
    bytes2      resq 1
    pos1        resq 1
    pos2        resq 1
    len1        resq 1
    len2        resq 1
    eof1        resb 1
    eof2        resb 1
    show1       resb 1
    show2       resb 1
    show3       resb 1
    arg1_ptr    resq 1
    arg2_ptr    resq 1

section .data
    usage_msg   db "Usage: comm [-123] FILE1 FILE2", 10
    usage_len   equ $ - usage_msg
    tab_char    db WHITESPACE_TAB

section .text
    global _start

_start:
    ; initialize
    mov byte [show1], 1
    mov byte [show2], 1
    mov byte [show3], 1
    mov qword [arg1_ptr], 0
    mov qword [arg2_ptr], 0

    mov rcx, [rsp]          ; argc
    lea rsi, [rsp+8]        ; pointer to argv[0]
    add rsi, 8              ; point to argv[1]
    dec rcx                 ; number of args after program name

parse_loop:
    test rcx, rcx
    jz args_done
    mov rdi, [rsi]
    mov al, [rdi]
    cmp al, '-'
    jne arg_is_file
    mov al, [rdi+1]
    cmp al, 0
    je arg_is_file
    cmp byte [rdi+2], 0
    jne arg_is_file
    cmp al, '1'
    je suppress1
    cmp al, '2'
    je suppress2
    cmp al, '3'
    je suppress3
    jmp print_usage
suppress1:
    mov byte [show1], 0
    jmp next_arg
suppress2:
    mov byte [show2], 0
    jmp next_arg
suppress3:
    mov byte [show3], 0
    jmp next_arg

arg_is_file:
    mov rbx, [arg1_ptr]
    test rbx, rbx
    jnz .check_second
    mov [arg1_ptr], rdi
    jmp next_arg
.check_second:
    mov rbx, [arg2_ptr]
    test rbx, rbx
    jnz extra_arg
    mov [arg2_ptr], rdi
    jmp next_arg
extra_arg:
    jmp print_usage

next_arg:
    add rsi, 8
    dec rcx
    jmp parse_loop

args_done:
    mov rax, [arg1_ptr]
    test rax, rax
    jz print_usage
    mov rax, [arg2_ptr]
    test rax, rax
    jz print_usage

    ; open files
    mov rsi, [arg1_ptr]
    mov rdi, STDIN_FILENO
    call open_file
    mov [fd1], rax

    mov rsi, [arg2_ptr]
    mov rdi, STDIN_FILENO
    call open_file
    mov [fd2], rax

    mov qword [bytes1], 0
    mov qword [bytes2], 0
    mov qword [pos1], 0
    mov qword [pos2], 0

    call read_next1
    call read_next2

main_loop:
    cmp byte [eof1], 1
    jne check_eof2
    cmp byte [eof2], 1
    je done
    ; only file2 has data
    mov rsi, line2
    mov rdx, [len2]
    mov bl, 2
    call output_line
    call read_next2
    jmp main_loop

check_eof2:
    cmp byte [eof2], 1
    jne compare_lines
    ; only file1 has data
    mov rsi, line1
    mov rdx, [len1]
    mov bl, 1
    call output_line
    call read_next1
    jmp main_loop

compare_lines:
    mov rsi, line1
    mov rdi, line2
    call line_cmp
    cmp rax, 0
    je lines_equal
    jl line1_less
    ; line2 less
    mov rsi, line2
    mov rdx, [len2]
    mov bl, 2
    call output_line
    call read_next2
    jmp main_loop

line1_less:
    mov rsi, line1
    mov rdx, [len1]
    mov bl, 1
    call output_line
    call read_next1
    jmp main_loop

lines_equal:
    mov rsi, line1
    mov rdx, [len1]
    mov bl, 3
    call output_line
    call read_next1
    call read_next2
    jmp main_loop

done:
    mov rax, SYS_CLOSE
    mov rdi, [fd1]
    syscall
    mov rax, SYS_CLOSE
    mov rdi, [fd2]
    syscall
    exit 0

print_usage:
    write STDERR_FILENO, usage_msg, usage_len
    exit 1

; read_next1: updates eof1 flag
read_next1:
    call read_line1
    cmp rax, 0
    jne .ok1
    mov byte [eof1], 1
    ret
.ok1:
    mov byte [eof1], 0
    ret

; read_next2: updates eof2 flag
read_next2:
    call read_line2
    cmp rax, 0
    jne .ok2
    mov byte [eof2], 1
    ret
.ok2:
    mov byte [eof2], 0
    ret

; Compare two lines: rsi=line1, rdi=line2
; returns rax = -1 if line1 < line2, 0 if equal, 1 if line1 > line2
line_cmp:
    xor rcx, rcx
.compare_loop:
    mov al, [rsi + rcx]
    mov bl, [rdi + rcx]
    cmp al, WHITESPACE_NL
    je .end1
    cmp bl, WHITESPACE_NL
    je .end2
    cmp al, bl
    jne .diff
    inc rcx
    jmp .compare_loop
.end1:
    cmp bl, WHITESPACE_NL
    je .equal
    mov rax, -1
    ret
.end2:
    mov rax, 1
    ret
.diff:
    cmp al, bl
    jl .less
    mov rax, 1
    ret
.less:
    mov rax, -1
    ret
.equal:
    mov rax, 0
    ret

; Output line according to column
; rsi = line pointer, rdx = length, bl = column (1-3)
output_line:
    mov r8, rsi
    mov r9, rdx
    cmp bl, 1
    je .col1
    cmp bl, 2
    je .col2
    ; column 3
    cmp byte [show3], 0
    je .ret
    xor r10d, r10d
    cmp byte [show1], 0
    je .skip31
    inc r10
.skip31:
    cmp byte [show2], 0
    je .skip32
    inc r10
.skip32:
    mov rsi, tab_char
    mov rdx, 1
.tab_loop3:
    cmp r10, 0
    je .after_tabs3
    write STDOUT_FILENO, rsi, rdx
    dec r10
    jmp .tab_loop3
.after_tabs3:
    mov rsi, r8
    mov rdx, r9
    write STDOUT_FILENO, rsi, rdx
    jmp .ret
.col2:
    cmp byte [show2], 0
    je .ret
    xor r10d, r10d
    cmp byte [show1], 0
    je .skip21
    inc r10
.skip21:
    mov rsi, tab_char
    mov rdx, 1
.tab_loop2:
    cmp r10, 0
    je .after_tabs2
    write STDOUT_FILENO, rsi, rdx
    dec r10
    jmp .tab_loop2
.after_tabs2:
    mov rsi, r8
    mov rdx, r9
    write STDOUT_FILENO, rsi, rdx
    jmp .ret
.col1:
    cmp byte [show1], 0
    je .ret
    mov rsi, r8
    mov rdx, r9
    write STDOUT_FILENO, rsi, rdx
.ret:
    ret

; Read a line from file1 -> line1, len1
; returns rax=1 if line read, 0 if EOF
read_line1:
    mov qword [len1], 0
.read1_loop:
    mov rax, [pos1]
    cmp rax, [bytes1]
    jl .buf1_has
    mov rdi, [fd1]
    mov rsi, buffer1
    mov rdx, BUFFER_SIZE
    mov rax, SYS_READ
    syscall
    cmp rax, 0
    jle .eof1
    mov [bytes1], rax
    mov qword [pos1], 0
.buf1_has:
    mov rsi, buffer1
    add rsi, [pos1]
    mov al, [rsi]
    inc qword [pos1]
    cmp al, WHITESPACE_NL
    je .end1
    mov rdi, line1
    add rdi, [len1]
    mov [rdi], al
    inc qword [len1]
    cmp qword [len1], LINE_BUFFER_SIZE - 1
    jl .read1_loop
.end1:
    mov rdi, line1
    add rdi, [len1]
    mov byte [rdi], WHITESPACE_NL
    inc qword [len1]
    mov rax, 1
    ret
.eof1:
    mov rax, 0
    ret

; Read a line from file2 -> line2, len2
; returns rax=1 if line read, 0 if EOF
read_line2:
    mov qword [len2], 0
.read2_loop:
    mov rax, [pos2]
    cmp rax, [bytes2]
    jl .buf2_has
    mov rdi, [fd2]
    mov rsi, buffer2
    mov rdx, BUFFER_SIZE
    mov rax, SYS_READ
    syscall
    cmp rax, 0
    jle .eof2
    mov [bytes2], rax
    mov qword [pos2], 0
.buf2_has:
    mov rsi, buffer2
    add rsi, [pos2]
    mov al, [rsi]
    inc qword [pos2]
    cmp al, WHITESPACE_NL
    je .end2
    mov rdi, line2
    add rdi, [len2]
    mov [rdi], al
    inc qword [len2]
    cmp qword [len2], LINE_BUFFER_SIZE - 1
    jl .read2_loop
.end2:
    mov rdi, line2
    add rdi, [len2]
    mov byte [rdi], WHITESPACE_NL
    inc qword [len2]
    mov rax, 1
    ret
.eof2:
    mov rax, 0
    ret
