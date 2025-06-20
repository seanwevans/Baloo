; src/fmt.asm

    %include "include/sysdefs.inc"

    %define WIDTH 75
    %define BUFFER_SIZE 4096
    %define WORD_MAX 256

section .bss
    buffer      resb BUFFER_SIZE
    word_buf    resb WORD_MAX
    line_len    resq 1
    word_len    resq 1
    prev_nl     resb 1

section .data
    space       db WHITESPACE_SPACE
    newline     db WHITESPACE_NL

section .text
global _start

_start:
    mov qword [line_len], 0
    mov qword [word_len], 0
    mov byte [prev_nl], 0

read_loop:
    mov rax, SYS_READ
    mov rdi, STDIN_FILENO
    mov rsi, buffer
    mov rdx, BUFFER_SIZE
    syscall
    cmp rax, 0
    jle end_of_file

    mov rcx, rax                        ;bytes read
    xor rbx, rbx                        ;index

process_char:
    cmp rbx, rcx
    je read_loop

    mov al, [buffer + rbx]
    inc rbx

    cmp al, WHITESPACE_SPACE
    je handle_space
    cmp al, WHITESPACE_TAB
    je handle_space
    cmp al, WHITESPACE_NL
    je handle_newline

; regular character
    mov rdi, [word_len]
    cmp rdi, WORD_MAX-1
    jge process_char                    ;ignore if word too long
    mov [word_buf + rdi], al
    inc rdi
    mov [word_len], rdi
    mov byte [prev_nl], 0
    jmp process_char

handle_space:
    call flush_word
    mov byte [prev_nl], 0
    jmp process_char

handle_newline:
    call flush_word
    cmp byte [prev_nl], 0
    jne emit_blank
    mov byte [prev_nl], 1
    jmp process_char

emit_blank:
    write STDOUT_FILENO, newline, 1
    mov qword [line_len], 0
    mov byte [prev_nl], 1
    jmp process_char

end_of_file:
    call flush_word
    write STDOUT_FILENO, newline, 1
    exit 0

flush_word:
    push rax
    push rbx
    push rcx
    push rdx
    cmp qword [word_len], 0
    je .done

    mov rcx, [line_len]
    mov rdx, [word_len]
    cmp rcx, 0
    jne .check_len
; first word of line
    mov rsi, word_buf
    write STDOUT_FILENO, rsi, rdx
    mov [line_len], rdx
    jmp .reset

.check_len:
    mov rax, rcx
    add rax, 1
    add rax, rdx
    cmp rax, WIDTH
    jle .same_line
; start new line
    write STDOUT_FILENO, newline, 1
    mov rcx, 0
    mov qword [line_len], 0

.same_line:
    cmp rcx, 0
    je .write_word
    write STDOUT_FILENO, space, 1
    inc qword [line_len]

.write_word:
    mov rsi, word_buf
    write STDOUT_FILENO, rsi, rdx
    add qword [line_len], rdx

.reset:
    mov qword [word_len], 0
.done:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret
