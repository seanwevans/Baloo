; src/uudecode.asm

    %include "include/sysdefs.inc"

section .bss
    linebuf     resb 256
    outbuf      resb 256
    filename    resb 256

section .text
global _start

; --------------------------------------------------------------
; read_line: reads a line from r8 file descriptor into linebuf
; returns length in rax, or -1 on EOF/error. newline removed.
; --------------------------------------------------------------
read_line:
    push rbx
    xor rbx, rbx                        ;index
.rl_loop:
    mov rax, SYS_READ
    mov rdi, r8
    lea rsi, [linebuf + rbx]
    mov rdx, 1
    syscall
    cmp rax, 0
    jle .eof
    cmp byte [linebuf + rbx], WHITESPACE_NL
    je .done
    inc rbx
    cmp rbx, 255
    jl .rl_loop
.done:
    mov byte [linebuf + rbx], 0
    mov rax, rbx
    pop rbx
    ret
.eof:
    mov byte [linebuf + rbx], 0
    mov rax, -1
    pop rbx
    ret

; --------------------------------------------------------------
; decode_line: decodes current linebuf and writes to output file r15
; --------------------------------------------------------------
decode_line:
    movzx rcx, byte [linebuf]
    sub rcx, 32
    and rcx, 0x3F                       ;number of bytes
    cmp rcx, 0
    jle .end_line
    lea rsi, [linebuf + 1]
    xor rdx, rdx                        ;out index
.loop_group:
    cmp rcx, 0
    jle .write
; decode 4 chars -> 3 bytes
    movzx rax, byte [rsi]
    sub al, 32
    and al, 0x3F
    shl rax, 18
    movzx rbx, byte [rsi+1]
    sub bl, 32
    and bl, 0x3F
    shl rbx, 12
    or  rax, rbx
    movzx rbx, byte [rsi+2]
    sub bl, 32
    and bl, 0x3F
    shl rbx, 6
    or  rax, rbx
    movzx rbx, byte [rsi+3]
    sub bl, 32
    and bl, 0x3F
    or  rax, rbx
    mov rbx, rax
    shr rbx, 16
    mov byte [outbuf + rdx], bl
    inc rdx
    dec rcx
    cmp rcx, 0
    je .next
    mov rbx, rax
    shr rbx, 8
    mov byte [outbuf + rdx], bl
    inc rdx
    dec rcx
    cmp rcx, 0
    je .next
    mov bl, al
    mov byte [outbuf + rdx], bl
    inc rdx
    dec rcx
.next:
    add rsi, 4
    jmp .loop_group

.write:
    mov rax, SYS_WRITE
    mov rdi, r15
    mov rsi, outbuf
    mov rdx, rdx                        ;bytes already in rdx
    syscall
.end_line:
    ret

_start:
    pop rcx                             ;argc
    pop rax                             ;skip argv[0]
    mov r8, STDIN_FILENO
    dec rcx
    cmp rcx, 0
    je find_header
    pop rsi                             ;input filename
    mov rdi, r8
    call open_file
    mov r8, rax

find_header:
    call read_line
    cmp rax, -1
    je finish
    cmp byte [linebuf], 'b'
    jne find_header
    cmp byte [linebuf+1], 'e'
    jne find_header
    cmp byte [linebuf+2], 'g'
    jne find_header
    cmp byte [linebuf+3], 'i'
    jne find_header
    cmp byte [linebuf+4], 'n'
    jne find_header
    cmp byte [linebuf+5], WHITESPACE_SPACE
    jne find_header
    mov rbx, 6
.skip_digits:
    mov al, [linebuf + rbx]
    cmp al, WHITESPACE_SPACE
    je .got_space
    cmp al, 0
    je find_header
    inc rbx
    jmp .skip_digits
.got_space:
    inc rbx
    xor rcx, rcx
.copy_name:
    mov al, [linebuf + rbx]
    cmp al, 0
    je open_output
    mov [filename + rcx], al
    inc rbx
    inc rcx
    jmp .copy_name
open_output:
    mov byte [filename + rcx], 0
    mov rsi, filename
    mov rdi, STDOUT_FILENO
    call open_dest_file
    mov r15, rax
    jmp decode_loop

decode_loop:
    call read_line
    cmp rax, -1
    je finish
    cmp byte [linebuf], 'e'
    jne .check_zero
    cmp byte [linebuf+1], 'n'
    jne .check_zero
    cmp byte [linebuf+2], 'd'
    je finish
.check_zero:
    mov al, [linebuf]
    cmp al, 0x60
    je decode_end
    cmp al, WHITESPACE_SPACE
    je decode_end
    call decode_line
    jmp decode_loop

decode_end:
; final line of data, read next 'end'
    call read_line
    jmp finish

finish:
    cmp r8, STDIN_FILENO
    je .chk_out
    mov rax, SYS_CLOSE
    mov rdi, r8
    syscall
.chk_out:
    cmp r15, 0
    je exit_success
    mov rax, SYS_CLOSE
    mov rdi, r15
    syscall
exit_success:
    exit 0
