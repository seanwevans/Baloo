; src/tac.asm
    %include "include/sysdefs.inc"

section .bss
    buffer      resb 65536
    line_pos    resq 8192
    buffer_size equ 65536
    exit_status resq 1

section .data
tac_pre     db "tac: "
    tac_pre_len equ $ - tac_pre
tac_suf     db ": No such file or directory", WHITESPACE_NL
    tac_suf_len equ $ - tac_suf

section .text
global _start

_start:
    pop r12                             ;argc
    pop rdi                             ;skip program name
    mov qword [exit_status], 0
    dec r12
    cmp r12, 0
    je read_stdin

process_args:
    cmp r12, 0
    je exit_success
    pop rdi                             ;filename
    cmp byte [rdi], '-'                 ;"-" means stdin
    jne .file
    cmp byte [rdi + 1], 0
    jne .file
    push r12
    mov rdi, STDIN_FILENO
    call tac_fd
    pop r12
    jmp .next
.file:
    call tac_file
.next:
    dec r12
    jmp process_args

read_stdin:
    mov rdi, STDIN_FILENO
    call tac_fd
    jmp exit_success

; rdi = filename
tac_file:
    mov rax, SYS_OPEN
    mov rsi, O_RDONLY
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl report_missing
    mov rdi, rax
    push r12
    push rdi                            ;preserve fd across tac_fd
    call tac_fd
    pop rdi                             ;restore fd for close
    pop r12
    mov rax, SYS_CLOSE
    syscall
    ret

; rdi = file descriptor
; reads file, stores line positions, outputs reversed
; clobbers rax..r11

tac_fd:
    mov rax, SYS_READ
    mov rsi, buffer
    mov rdx, buffer_size
    syscall
    cmp rax, 0
    jl error_exit
    mov rbx, rax                        ;bytes_read

    mov qword [line_pos], 0             ;first line start index
    mov rcx, 1                          ;line count
    xor r8, r8                          ;current index

.scan_loop:
    cmp r8, rbx
    jge .scan_done
    mov al, [buffer + r8]
    cmp al, 10
    jne .not_nl
    mov r9, rbx
    dec r9
    cmp r8, r9
    je .not_nl                          ;newline at end -> ignore
    lea rax, [r8 + 1]
    mov [line_pos + rcx*8], rax
    inc rcx
.not_nl:
    inc r8
    jmp .scan_loop

.scan_done:
    mov r15, rcx                        ;total line count
    mov r14, r15
    dec r14                             ;r14 = last line index

.output_loop:
    cmp r14, -1
    jle .done
    mov r9, [line_pos + r14*8]          ;start
    mov r10, r14
    inc r10
    cmp r10, r15
    jne .not_last
    mov r11, rbx
    jmp .write_line
.not_last:
    mov r11, [line_pos + r10*8]
.write_line:
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FILENO
    lea rsi, [buffer + r9]
    mov rdx, r11
    sub rdx, r9
    syscall
    dec r14
    jmp .output_loop

.done:
    ret

error_exit:
    exit 1

; report_missing: rdi -> filename; print a diagnostic and set the exit status
report_missing:
    mov r13, rdi
    write STDERR_FILENO, tac_pre, tac_pre_len
    mov rsi, r13
    call strlen                         ;rbx = length (include/sysdefs.inc)
    mov rax, SYS_WRITE
    mov rdi, STDERR_FILENO
    mov rsi, r13
    mov rdx, rbx
    syscall
    write STDERR_FILENO, tac_suf, tac_suf_len
    mov qword [exit_status], 1
    ret

exit_success:
    mov rdi, [exit_status]
    mov rax, SYS_EXIT
    syscall
