; src/join.asm

    %include "include/sysdefs.inc"

    %define BUFFER_SIZE 4096
    %define LINE_BUFFER_SIZE 1024

section .bss
    buffer1         resb BUFFER_SIZE
    buffer2         resb BUFFER_SIZE
    line1           resb LINE_BUFFER_SIZE
    line2           resb LINE_BUFFER_SIZE
    fd1             resq 1
    fd2             resq 1
    bytes1          resq 1
    bytes2          resq 1
    pos1            resq 1
    pos2            resq 1
    len1            resq 1
    len2            resq 1

section .data
usage_msg       db "Usage: join FILE1 FILE2", 10
    usage_len       equ $ - usage_msg
    space_char      db " ", 0

section .text
global _start

_start:
    cmp qword [rsp], 3
    jne print_usage

    mov rsi, [rsp + 16]                 ;file1
    mov rdi, STDIN_FILENO
    call open_file
    mov [fd1], rax

    mov rsi, [rsp + 24]                 ;file2
    mov rdi, STDIN_FILENO
    call open_file
    mov [fd2], rax

    mov qword [bytes1], 0
    mov qword [bytes2], 0
    mov qword [pos1], 0
    mov qword [pos2], 0

    call read_line1
    test rax, rax
    jz done

    call read_line2
    test rax, rax
    jz done

join_loop:
    mov rsi, line1
    mov rdi, line2
    call key_cmp
    cmp rax, 0
    je join_lines
    jl read_next1

read_next2:
    call read_line2
    test rax, rax
    jz done
    jmp join_loop

read_next1:
    call read_line1
    test rax, rax
    jz done
    jmp join_loop

join_lines:
; output line1 without trailing newline
    mov rdi, STDOUT_FILENO
    mov rsi, line1
    mov rdx, [len1]
    dec rdx
    write rdi, rsi, rdx

; space delimiter
    write STDOUT_FILENO, space_char, 1

; find offset after first field in line2
    mov rsi, line2
    call skip_field
    mov r11, rax                        ;offset in line2
    mov rsi, line2
    add rsi, r11
    mov rdx, [len2]
    sub rdx, r11
    write STDOUT_FILENO, rsi, rdx

    call read_line1
    test rax, rax
    jz done
    call read_line2
    test rax, rax
    jz done
    jmp join_loop

print_usage:
    write STDERR_FILENO, usage_msg, usage_len
    exit 1

done:
    mov rax, SYS_CLOSE
    mov rdi, [fd1]
    syscall
    mov rax, SYS_CLOSE
    mov rdi, [fd2]
    syscall
    exit 0

; Compare first fields of two lines
; rsi = line1, rdi = line2
; returns rax: -1 if key1 < key2, 0 if equal, 1 if key1 > key2
key_cmp:
    xor rcx, rcx                        ;offset1
    xor rdx, rdx                        ;offset2
.compare_loop:
    mov al, [rsi + rcx]
    mov bl, [rdi + rdx]

    cmp al, WHITESPACE_TAB
    je .end1
    cmp al, WHITESPACE_SPACE
    je .end1
    cmp al, WHITESPACE_NL
    je .end1

    cmp bl, WHITESPACE_TAB
    je .end2
    cmp bl, WHITESPACE_SPACE
    je .end2
    cmp bl, WHITESPACE_NL
    je .end2

    cmp al, bl
    jne .diff
    inc rcx
    inc rdx
    jmp .compare_loop

.end1:
    cmp bl, WHITESPACE_TAB
    je .check_end
    cmp bl, WHITESPACE_SPACE
    je .check_end
    cmp bl, WHITESPACE_NL
    je .check_end
    mov rax, -1
    ret
.check_end:
    mov rax, 0
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

; Skip first field and following whitespace
; rsi = line pointer
; returns rax = offset after first field and whitespace
skip_field:
    xor rax, rax
.skip_field_loop:
    mov bl, [rsi + rax]
    cmp bl, WHITESPACE_TAB
    je .end_field
    cmp bl, WHITESPACE_SPACE
    je .end_field
    cmp bl, WHITESPACE_NL
    je .end_field
    inc rax
    jmp .skip_field_loop
.end_field:
.skip_ws:
    cmp bl, WHITESPACE_SPACE
    jne .check_tab
    inc rax
    mov bl, [rsi + rax]
    jmp .skip_ws
.check_tab:
    cmp bl, WHITESPACE_TAB
    jne .done_skip
    inc rax
    mov bl, [rsi + rax]
    jmp .skip_ws
.done_skip:
    ret

; Read a line from file1 -> line1
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

; Read a line from file2 -> line2
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
