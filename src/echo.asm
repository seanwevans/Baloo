; src/echo.asm -- echo(1): write arguments separated by spaces.
; Supports -n (no trailing newline), -e (interpret backslash escapes) and
; -E (disable escapes, the default). Options may be bundled (e.g. -ne); an
; argument containing any other character is treated as a literal operand.

    %include "include/sysdefs.inc"

    %define OUTBUF_SIZE 65536

section .bss
    no_newline   resb 1
    escape_mode  resb 1
    outbuf       resb OUTBUF_SIZE
    outlen       resq 1

section .text
global      _start

_start:
    mov         qword [outlen], 0
    mov         byte [no_newline], 0
    mov         byte [escape_mode], 0
    mov         r12, [rsp]              ;argc
    lea         r13, [rsp + 16]         ;&argv[1]
    dec         r12                     ;operand count

parse_opts:
    cmp         r12, 0
    jle         print_start
    mov         rbx, [r13]
    cmp         byte [rbx], '-'
    jne         print_start
    cmp         byte [rbx + 1], 0       ;lone "-" is an operand
    je          print_start
;an option bundle is valid only if every character is n/e/E
    lea         rdi, [rbx + 1]
.validate:
    movzx       eax, byte [rdi]
    test        al, al
    je          .apply
    cmp         al, 'n'
    je          .valid_char
    cmp         al, 'e'
    je          .valid_char
    cmp         al, 'E'
    je          .valid_char
    jmp         print_start             ;not an option -> literal operand
.valid_char:
    inc         rdi
    jmp         .validate
.apply:
    lea         rdi, [rbx + 1]
.apply_loop:
    movzx       eax, byte [rdi]
    test        al, al
    je          .next_opt
    cmp         al, 'n'
    je          .set_n
    cmp         al, 'e'
    je          .set_e
    mov         byte [escape_mode], 0   ;'E'
    inc         rdi
    jmp         .apply_loop
.set_n:
    mov         byte [no_newline], 1
    inc         rdi
    jmp         .apply_loop
.set_e:
    mov         byte [escape_mode], 1
    inc         rdi
    jmp         .apply_loop
.next_opt:
    add         r13, 8
    dec         r12
    jmp         parse_opts

print_start:
    cmp         r12, 0
    jle         finish
.op_loop:
    mov         rsi, [r13]
    cmp         byte [escape_mode], 1
    je          .escaped
    call        emit_raw
    jmp         .after
.escaped:
    call        emit_escaped
.after:
    dec         r12
    jz          finish                  ;last operand -> no trailing space
    mov         al, ' '
    call        emit_al
    add         r13, 8
    jmp         .op_loop

finish:
    cmp         byte [no_newline], 1
    je          flush_exit
    mov         al, WHITESPACE_NL
    call        emit_al
flush_exit:
    call        flush
    exit        0

; stop_output: \c encountered -> flush what we have and exit (no newline)
stop_output:
    call        flush
    exit        0

; emit_raw: append the NUL-terminated string at rsi verbatim
emit_raw:
    mov         al, [rsi]
    test        al, al
    je          .done
    call        emit_al
    inc         rsi
    jmp         emit_raw
.done:
    ret

; emit_escaped: append the string at rsi, interpreting backslash escapes
emit_escaped:
    mov         al, [rsi]
    test        al, al
    je          .done
    cmp         al, 92                  ;backslash
    je          .esc
    call        emit_al
    inc         rsi
    jmp         emit_escaped
.esc:
    inc         rsi
    mov         al, [rsi]
    test        al, al
    jz          .lone_bs
    cmp         al, 'n'
    je          .e_n
    cmp         al, 't'
    je          .e_t
    cmp         al, 'r'
    je          .e_r
    cmp         al, 'v'
    je          .e_v
    cmp         al, 'f'
    je          .e_f
    cmp         al, 'b'
    je          .e_b
    cmp         al, 'a'
    je          .e_a
    cmp         al, 'e'
    je          .e_e
    cmp         al, 92
    je          .e_bs
    cmp         al, 'c'
    je          stop_output             ;\c stops all output
    cmp         al, '0'
    je          .e_oct
    cmp         al, 'x'
    je          .e_hex
;unknown escape: keep the backslash and the character
    mov         al, 92
    call        emit_al
    mov         al, [rsi]
    call        emit_al
    inc         rsi
    jmp         emit_escaped
.lone_bs:
    mov         al, 92
    call        emit_al
    jmp         .done
.e_n:
    mov         al, 10
    jmp         .e_emit
.e_t:
    mov         al, 9
    jmp         .e_emit
.e_r:
    mov         al, 13
    jmp         .e_emit
.e_v:
    mov         al, 11
    jmp         .e_emit
.e_f:
    mov         al, 12
    jmp         .e_emit
.e_b:
    mov         al, 8
    jmp         .e_emit
.e_a:
    mov         al, 7
    jmp         .e_emit
.e_e:
    mov         al, 27
    jmp         .e_emit
.e_bs:
    mov         al, 92
.e_emit:
    call        emit_al
    inc         rsi
    jmp         emit_escaped
.e_oct:
    inc         rsi                     ;skip the leading '0'
    xor         eax, eax
    xor         r10, r10
.oct_loop:
    cmp         r10, 3
    jge         .oct_done
    mov         dl, [rsi]
    sub         dl, '0'
    cmp         dl, 7
    ja          .oct_done
    shl         al, 3
    add         al, dl
    inc         rsi
    inc         r10
    jmp         .oct_loop
.oct_done:
    call        emit_al
    jmp         emit_escaped
.e_hex:
    inc         rsi                     ;skip 'x'
    xor         eax, eax
    xor         r10, r10
.hex_loop:
    cmp         r10, 2
    jge         .hex_done
    mov         dl, [rsi]
    cmp         dl, '0'
    jb          .hex_done
    cmp         dl, '9'
    jbe         .hex_dig
    or          dl, 0x20
    cmp         dl, 'a'
    jb          .hex_done
    cmp         dl, 'f'
    ja          .hex_done
    sub         dl, 'a' - 10
    jmp         .hex_acc
.hex_dig:
    sub         dl, '0'
.hex_acc:
    shl         al, 4
    add         al, dl
    inc         rsi
    inc         r10
    jmp         .hex_loop
.hex_done:
    test        r10, r10
    jnz         .hex_emit
;no hex digits: keep "\x" literally
    mov         al, 92
    call        emit_al
    mov         al, 'x'
    call        emit_al
    jmp         emit_escaped
.hex_emit:
    call        emit_al
    jmp         emit_escaped
.done:
    ret

; emit_al: append al to the output buffer, flushing when full
emit_al:
    push        rdx
    mov         rdx, [outlen]
    cmp         rdx, OUTBUF_SIZE
    jl          .store
    call        flush
    xor         rdx, rdx
.store:
    mov         [outbuf + rdx], al
    inc         rdx
    mov         [outlen], rdx
    pop         rdx
    ret

; flush: write the buffered output to stdout (preserves registers)
flush:
    push        rax
    push        rcx
    push        rdx
    push        rsi
    push        rdi
    push        r11
    mov         rdx, [outlen]
    test        rdx, rdx
    jz          .empty
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, outbuf
    syscall
    mov         qword [outlen], 0
.empty:
    pop         r11
    pop         rdi
    pop         rsi
    pop         rdx
    pop         rcx
    pop         rax
    ret
