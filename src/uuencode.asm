; src/uuencode.asm

%include "include/sysdefs.inc"

%define LINE_BUF 45

section .bss
    inbuf       resb LINE_BUF
    outbuf      resb 128
    destname    resq 1

section .data
    header      db "begin 644 ",0
    header_len  equ $ - header
    newline     db WHITESPACE_NL
    space_line  db ' ', WHITESPACE_NL
    space_len   equ $ - space_line
    endmsg      db "end", WHITESPACE_NL
    endmsg_len  equ $ - endmsg

section .text
    global _start

_start:
    pop rcx                     ; argc
    mov rbx, rsp                ; argv pointer
    cmp rcx, 2
    jl  exit_error              ; need dest name
    cmp rcx, 3
    jl  .stdin_only

    mov rdi, [rbx+8]            ; argv[1] input file
    mov rax, SYS_OPEN
    mov rsi, O_RDONLY
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl  exit_error
    mov r14, rax                ; file descriptor
    mov rsi, [rbx+16]           ; argv[2] dest name
    jmp .have_input

.stdin_only:
    mov r14, STDIN_FILENO
    mov rsi, [rbx+8]            ; argv[1] dest name

.have_input:
    mov [destname], rsi

    ; print header
    write STDOUT_FILENO, header, header_len
    mov rsi, [destname]
    call strlen
    write STDOUT_FILENO, rsi, rbx
    write STDOUT_FILENO, newline, 1

read_loop:
    mov rax, SYS_READ
    mov rdi, r14
    mov rsi, inbuf
    mov rdx, LINE_BUF
    syscall
    cmp rax, 0
    jl exit_error
    je finish

    mov rcx, rax                ; bytes read
    mov r8b, cl
    add r8b, 32
    mov byte [outbuf], r8b
    lea rdi, [inbuf]
    lea rsi, [outbuf+1]
    push rcx
    call encode_line
    pop rcx
    mov rdx, rax
    add rdx, 1
    mov byte [outbuf+rdx], 10
    inc rdx
    write STDOUT_FILENO, outbuf, rdx
    jmp read_loop

finish:
    write STDOUT_FILENO, space_line, space_len
    write STDOUT_FILENO, endmsg, endmsg_len
    cmp r14, STDIN_FILENO
    je exit_success
    mov rax, SYS_CLOSE
    mov rdi, r14
    syscall
exit_success:
    exit 0
exit_error:
    exit 1

; rdi = src, rcx = length, rsi = dest
; returns rax = bytes written
encode_line:
    push rbp
    mov rbp, rsp
    xor rax, rax                ; output count
    mov r8, rcx                 ; remaining bytes
    mov r9, rdi                 ; src pointer
    mov r10, rsi                ; dest pointer

.loop:
    cmp r8, 0
    jle .done
    movzx edx, byte [r9]
    xor ebx, ebx
    xor ecx, ecx
    dec r8
    inc r9

    cmp r8, 0
    jle .after_second
    movzx ebx, byte [r9]
    dec r8
    inc r9
.after_second:
    cmp r8, 0
    jle .pack
    movzx ecx, byte [r9]
    dec r8
    inc r9
.pack:
    mov r11d, edx               ; pack bytes
    shl r11d, 16
    mov r12d, ebx
    shl r12d, 8
    or  r11d, r12d
    or  r11d, ecx

    mov r12d, r11d
    shr r12d, 18
    and r12d, 0x3F
    add r12b, 32
    mov [r10+rax], r12b
    inc rax

    mov r12d, r11d
    shr r12d, 12
    and r12d, 0x3F
    add r12b, 32
    mov [r10+rax], r12b
    inc rax

    mov r12d, r11d
    shr r12d, 6
    and r12d, 0x3F
    add r12b, 32
    mov [r10+rax], r12b
    inc rax

    mov r12d, r11d
    and r12d, 0x3F
    add r12b, 32
    mov [r10+rax], r12b
    inc rax

    jmp .loop

.done:
    mov rsp, rbp
    pop rbp
    ret
