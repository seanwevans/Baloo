; src/iconv.asm

%include "include/sysdefs.inc"

section .bss
    buffer      resb 4096
    outbuf      resb 2
    fd          resq 1
    from_enc    resb 1
    to_enc      resb 1

section .data
    usage_msg   db "Usage: iconv -f FROM -t TO [FILE]", 10
    usage_len   equ $ - usage_msg
    invalid_msg db "Unsupported encoding", 10
    invalid_len equ $ - invalid_msg
    utf8_str    db "UTF-8", 0
    latin1_str  db "ISO-8859-1", 0
    ascii_str   db "ASCII", 0

section .text
    global _start

_start:
    pop     rcx                 ; argc
    mov     rbx, rsp            ; argv pointer
    mov     byte [from_enc], 0
    mov     byte [to_enc], 0
    mov     qword [fd], STDIN_FILENO

    dec     rcx                 ; skip program name
    cmp     rcx, 0
    jle     .check_enc

.parse_loop:
    mov     rdi, [rbx]
    cmp     byte [rdi], '-'
    jne     .filename

    cmp     byte [rdi+1], 'f'
    je      .handle_from
    cmp     byte [rdi+1], 't'
    je      .handle_to
    jmp     .usage

.handle_from:
    cmp     rcx, 1
    jle     .usage
    add     rbx, 8
    dec     rcx
    mov     rdi, [rbx]
    call    parse_encoding
    test    al, al
    jz      .invalid
    mov     [from_enc], al
    jmp     .next_arg

.handle_to:
    cmp     rcx, 1
    jle     .usage
    add     rbx, 8
    dec     rcx
    mov     rdi, [rbx]
    call    parse_encoding
    test    al, al
    jz      .invalid
    mov     [to_enc], al
    jmp     .next_arg

.filename:
    mov     rdi, STDIN_FILENO
    mov     rsi, [rbx]
    call    open_file
    mov     [fd], rax

.next_arg:
    add     rbx, 8
    dec     rcx
    cmp     rcx, 0
    jg      .parse_loop

.check_enc:
    cmp     byte [from_enc], 0
    je      .usage
    cmp     byte [to_enc], 0
    je      .usage

    call    convert_stream
    exit    0

.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

.invalid:
    write   STDERR_FILENO, invalid_msg, invalid_len
    exit    1

; rdi -> encoding string
; return al = 1 (UTF-8) 2 (LATIN1) 3 (ASCII) or 0
parse_encoding:
    push    rsi
    push    rdi

    mov     rsi, rdi
    lea     rdi, [rel utf8_str]
    call    str_equal
    cmp     al, 1
    je      .utf8

    pop     rdi
    pop     rsi
    push    rsi
    push    rdi
    mov     rsi, rdi
    lea     rdi, [rel latin1_str]
    call    str_equal
    cmp     al, 1
    je      .latin1

    pop     rdi
    pop     rsi
    push    rsi
    push    rdi
    mov     rsi, rdi
    lea     rdi, [rel ascii_str]
    call    str_equal
    cmp     al, 1
    je      .ascii

    xor     eax, eax
    jmp     .done

.utf8:
    mov     al, 1
    jmp     .done_pop
.latin1:
    mov     al, 2
    jmp     .done_pop
.ascii:
    mov     al, 3
    jmp     .done_pop

.done_pop:
    pop     rdi
    pop     rsi
    jmp     .done

.done:
    ret

; rdi, rsi => strings
; return al=1 if equal
str_equal:
    push    rcx
    mov     rcx, 0
.loop:
    mov     al, [rdi + rcx]
    mov     dl, [rsi + rcx]
    cmp     al, dl
    jne     .ne
    cmp     al, 0
    je      .eq
    inc     rcx
    jmp     .loop
.eq:
    mov     al, 1
    pop     rcx
    ret
.ne:
    xor     eax, eax
    pop     rcx
    ret

; convert stream
convert_stream:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

.read_loop:
    mov     rax, SYS_READ
    mov     rdi, [fd]
    mov     rsi, buffer
    mov     rdx, 4096
    syscall
    cmp     rax, 0
    jle     .finish
    mov     rcx, rax
    xor     rbx, rbx
.process_byte:
    cmp     rbx, rcx
    jge     .read_loop
    movzx   eax, byte [buffer + rbx]
    inc     rbx

    mov     r8b, [from_enc]
    cmp     r8b, 1
    je      .from_utf8
    cmp     r8b, 2
    je      .from_latin1
    cmp     r8b, 3
    je      .from_ascii
    mov     al, '?'
    jmp     .output_cp

.from_utf8:
    test    al, 0x80
    jz      .cp_ready
    mov     bl, al
    and     bl, 0xE0
    cmp     bl, 0xC0
    jne     .bad_seq
    cmp     rbx, rcx
    jge     .bad_seq
    mov     dl, [buffer + rbx]
    mov     bl, dl
    and     bl, 0xC0
    cmp     bl, 0x80
    jne     .bad_seq
    inc     rbx
    movzx   eax, al
    and     eax, 0x1F
    shl     eax, 6
    movzx   edx, dl
    and     edx, 0x3F
    or      eax, edx
    jmp     .cp_ready2
.bad_seq:
    mov     eax, '?'
    jmp     .output_cp
.cp_ready:
    movzx   eax, al
.cp_ready2:
    jmp     .output_cp

.from_latin1:
    movzx   eax, al
    jmp     .output_cp

.from_ascii:
    movzx   eax, al
    cmp     eax, 0x80
    jb      .output_cp
    mov     eax, '?'

.output_cp:
    mov     r8b, [to_enc]
    cmp     r8b, 1
    je      .to_utf8
    cmp     r8b, 2
    je      .to_latin1
    cmp     r8b, 3
    je      .to_ascii
    mov     al, '?'
    jmp     .emit_one

.to_utf8:
    cmp     eax, 0x80
    jb      .emit_one
    mov     bl, al
    shr     bl, 6
    or      bl, 0xC0
    mov     [outbuf], bl
    mov     bl, al
    and     bl, 0x3F
    or      bl, 0x80
    mov     [outbuf+1], bl
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    lea     rsi, [outbuf]
    mov     rdx, 2
    syscall
    jmp     .process_byte

.to_latin1:
    cmp     eax, 0x100
    jb      .emit_one
    mov     al, '?'
    jmp     .emit_one

.to_ascii:
    cmp     eax, 0x80
    jb      .emit_one
    mov     al, '?'

.emit_one:
    mov     [outbuf], al
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    lea     rsi, [outbuf]
    mov     rdx, 1
    syscall
    jmp     .process_byte

.finish:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

.invalid_enc_exit:
    mov     al, '?'
    jmp     .emit_one
