; src/uuencode.asm -- uuencode(1): encode a file (or stdin) in historical
; uuencode format, or base64 with -m. Usage: uuencode [-m] [INPUT] NAME.

    %include "include/sysdefs.inc"

    %define SYS_FSTAT 5
    %define INSIZE 1048576
    %define OUTSIZE 2097152

section .bss
    inbuf       resb INSIZE
    outbuf      resb OUTSIZE
    statbuf     resb 160
    inlen       resq 1
    outpos      resq 1
    mode        resq 1
    m_flag      resb 1
    name_ptr    resq 1

section .data
    base64_table db BASE64_TABLE
    begin_uu     db "begin "
    begin_uu_len equ $ - begin_uu
    begin_b64    db "begin-base64 "
    begin_b64_len equ $ - begin_b64
    end_uu       db "end", WHITESPACE_NL
    end_uu_len   equ $ - end_uu
    end_b64      db "====", WHITESPACE_NL
    end_b64_len  equ $ - end_b64

section .text
global _start

_start:
    mov     byte [m_flag], 0
    mov     qword [outpos], 0
    mov     qword [mode], 0o744         ;default mode (stdin)

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

;optional -m
    cmp     r12, 0
    je      arg_error
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .operands
    cmp     byte [rdi + 1], 'm'
    jne     .operands
    mov     byte [m_flag], 1
    add     r13, 8
    dec     r12
.operands:
    cmp     r12, 1
    jl      arg_error
    je      .stdin
;INPUT NAME
    mov     rdi, [r13]
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      arg_error
    mov     rdi, rax
    push    rdi
    call    read_all
    pop     rdi
    mov     rax, SYS_FSTAT              ;take the mode from the input file
    mov     rsi, statbuf
    syscall
    mov     rax, [statbuf + 24]
    and     rax, 0o777
    mov     [mode], rax
    mov     rax, [r13 + 8]
    mov     [name_ptr], rax
    jmp     header
.stdin:
    mov     rax, [r13]
    mov     [name_ptr], rax
    mov     rdi, STDIN_FILENO
    call    read_all

header:
    cmp     byte [m_flag], 1
    je      .b64_header
    mov     rsi, begin_uu
    mov     rdx, begin_uu_len
    call    put_str
    jmp     .name
.b64_header:
    mov     rsi, begin_b64
    mov     rdx, begin_b64_len
    call    put_str
.name:
    mov     rax, [mode]                 ;3-digit octal mode
    shr     rax, 6
    and     rax, 7
    add     al, '0'
    call    put_byte
    mov     rax, [mode]
    shr     rax, 3
    and     rax, 7
    add     al, '0'
    call    put_byte
    mov     rax, [mode]
    and     rax, 7
    add     al, '0'
    call    put_byte
    mov     al, ' '
    call    put_byte
    mov     rsi, [name_ptr]
    call    strlen
    mov     rsi, [name_ptr]
    mov     rdx, rbx
    call    put_str
    mov     al, WHITESPACE_NL
    call    put_byte

    cmp     byte [m_flag], 1
    je      encode_b64

; ---------------- uu encoding ----------------
encode_uu:
    xor     rbx, rbx                    ;input index
.line:
    mov     rax, [inlen]
    sub     rax, rbx
    jle     .done
    mov     r9, rax                     ;bytes left
    cmp     r9, 45
    jle     .have
    mov     r9, 45
.have:
    mov     rax, r9                     ;length character
    call    uu_enc
    call    put_byte
    xor     rcx, rcx                    ;byte offset within the line
.group:
    cmp     rcx, r9
    jge     .eol
;load b0,b1,b2 for this 3-byte group (missing bytes = 0)
    movzx   r8, byte [inbuf + rbx + rcx]
    xor     r10, r10
    xor     r11, r11
    lea     rax, [rcx + 1]
    cmp     rax, r9
    jge     .emit
    movzx   r10, byte [inbuf + rbx + rcx + 1]
    lea     rax, [rcx + 2]
    cmp     rax, r9
    jge     .emit
    movzx   r11, byte [inbuf + rbx + rcx + 2]
.emit:
;c0 = b0 >> 2
    mov     rax, r8
    shr     rax, 2
    and     rax, 0x3f
    call    uu_enc
    call    put_byte
;c1 = ((b0 << 4) | (b1 >> 4)) & 0x3f
    mov     rax, r8
    shl     rax, 4
    mov     rdx, r10
    shr     rdx, 4
    or      rax, rdx
    and     rax, 0x3f
    call    uu_enc
    call    put_byte
;c2 = ((b1 << 2) | (b2 >> 6)) & 0x3f
    mov     rax, r10
    shl     rax, 2
    mov     rdx, r11
    shr     rdx, 6
    or      rax, rdx
    and     rax, 0x3f
    call    uu_enc
    call    put_byte
;c3 = b2 & 0x3f
    mov     rax, r11
    and     rax, 0x3f
    call    uu_enc
    call    put_byte
    add     rcx, 3
    jmp     .group
.eol:
    mov     al, WHITESPACE_NL
    call    put_byte
    add     rbx, 45
    jmp     .line
.done:
    mov     rsi, end_uu
    mov     rdx, end_uu_len
    call    put_str
    call    flush
    exit    0

; uu_enc: rax value 0..63 -> character in al (0 becomes backtick)
uu_enc:
    test    al, al
    jnz     .nz
    mov     al, 0x60
    ret
.nz:
    add     al, 0x20
    ret

; ---------------- base64 encoding ----------------
encode_b64:
    xor     rbx, rbx                    ;input index
    xor     r10, r10                    ;column
.blk:
    mov     rax, [inlen]
    sub     rax, rbx
    jle     .fin
    mov     r9, rax
    xor     r8, r8
    movzx   rdx, byte [inbuf + rbx]
    shl     rdx, 16
    or      r8, rdx
    cmp     r9, 1
    je      .n1
    movzx   rdx, byte [inbuf + rbx + 1]
    shl     rdx, 8
    or      r8, rdx
    cmp     r9, 2
    je      .n2
    movzx   rdx, byte [inbuf + rbx + 2]
    or      r8, rdx
    mov     r11, 3
    jmp     .e4
.n2:
    mov     r11, 2
    jmp     .e4
.n1:
    mov     r11, 1
.e4:
    mov     rdx, r8
    shr     rdx, 18
    and     rdx, 0x3f
    mov     al, [base64_table + rdx]
    call    b64_col
    mov     rdx, r8
    shr     rdx, 12
    and     rdx, 0x3f
    mov     al, [base64_table + rdx]
    call    b64_col
    cmp     r11, 2
    jl      .p2
    mov     rdx, r8
    shr     rdx, 6
    and     rdx, 0x3f
    mov     al, [base64_table + rdx]
    jmp     .e2
.p2:
    mov     al, '='
.e2:
    call    b64_col
    cmp     r11, 3
    jl      .p3
    mov     rdx, r8
    and     rdx, 0x3f
    mov     al, [base64_table + rdx]
    jmp     .e3
.p3:
    mov     al, '='
.e3:
    call    b64_col
    add     rbx, 3
    jmp     .blk
.fin:
    test    r10, r10
    jz      .term
    mov     al, WHITESPACE_NL
    call    put_byte
.term:
    mov     rsi, end_b64
    mov     rdx, end_b64_len
    call    put_str
    call    flush
    exit    0

; b64_col: append al, wrapping at 60 columns
b64_col:
    cmp     r10, 60
    jne     .store
    push    rax
    mov     al, WHITESPACE_NL
    call    put_byte
    pop     rax
    xor     r10, r10
.store:
    call    put_byte
    inc     r10
    ret

; read_all: rdi = fd; read up to INSIZE bytes into inbuf, set [inlen]
read_all:
    xor     r14, r14
.loop:
    mov     rdx, INSIZE
    sub     rdx, r14
    jle     .done
    mov     rax, SYS_READ
    lea     rsi, [inbuf + r14]
    syscall
    cmp     rax, 0
    jle     .done
    add     r14, rax
    jmp     .loop
.done:
    mov     [inlen], r14
    ret

; put_byte: append al to outbuf
put_byte:
    push    rcx
    mov     rcx, [outpos]
    mov     [outbuf + rcx], al
    inc     rcx
    mov     [outpos], rcx
    pop     rcx
    ret

; put_str: append rdx bytes at rsi to outbuf
put_str:
    push    rcx
    push    rsi
    xor     rcx, rcx
.l:
    cmp     rcx, rdx
    jge     .done
    mov     al, [rsi + rcx]
    push    rcx
    push    rdx
    push    rsi
    call    put_byte
    pop     rsi
    pop     rdx
    pop     rcx
    inc     rcx
    jmp     .l
.done:
    pop     rsi
    pop     rcx
    ret

; flush: write outbuf to stdout
flush:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, outbuf
    mov     rdx, [outpos]
    syscall
    ret

arg_error:
    exit    1
