; src/uudecode.asm -- uudecode(1): decode a uuencode or base64 stream.
; Usage: uudecode [-o OUTFILE] [INFILE]   ("-" output means stdout).

    %include "include/sysdefs.inc"

section .bss
    linebuf     resb 4096
    outline     resb 4096
    dec_table   resb 256
    hdr_name    resb 4096
    o_target    resq 1                  ;-o argument, or 0
    in_fd       resq 1
    out_fd      resq 1
    hdr_mode    resq 1

section .data
    base64_table db BASE64_TABLE
    end_uu       db "end", 0
err_msg      db "uudecode: malformed input", WHITESPACE_NL
    err_len      equ $ - err_msg

section .text
global _start

_start:
    mov     qword [o_target], 0
    mov     qword [in_fd], STDIN_FILENO
    mov     qword [hdr_mode], 0o644

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    je      build_table
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .infile
    cmp     byte [rdi + 1], 0
    je      .infile                     ;lone "-" input operand
    cmp     byte [rdi + 1], 'o'
    jne     .next                       ;ignore other options
;-o TARGET
    cmp     byte [rdi + 2], 0
    jne     .o_attached
    add     r13, 8
    dec     r12
    mov     rdi, [r13]
    mov     [o_target], rdi
    jmp     .next
.o_attached:
    lea     rdi, [rdi + 2]
    mov     [o_target], rdi
    jmp     .next
.infile:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .next
    mov     [in_fd], rax
.next:
    add     r13, 8
    dec     r12
    jmp     parse

build_table:
    xor     rcx, rcx
.zero:
    mov     byte [dec_table + rcx], 0xFF
    inc     rcx
    cmp     rcx, 256
    jl      .zero
    xor     rcx, rcx
.fill:
    cmp     rcx, 64
    jge     read_header
    movzx   rax, byte [base64_table + rcx]
    mov     [dec_table + rax], cl
    inc     rcx
    jmp     .fill

read_header:
    mov     r8, [in_fd]
    call    read_line
    cmp     rax, -1
    je      error
;detect "begin-base64 " vs "begin "
    mov     rsi, linebuf
    cmp     dword [rsi], 'begi'
    jne     error
    cmp     byte [rsi + 4], 'n'
    jne     error
    cmp     byte [rsi + 5], '-'
    je      .b64
;uu: "begin MODE NAME"
    lea     rsi, [linebuf + 6]
    mov     r14, 0                      ;mode = uu
    jmp     .parse_hdr
.b64:
;"begin-base64 MODE NAME"  ("begin-base64 " = 13 chars)
    lea     rsi, [linebuf + 13]
    mov     r14, 1                      ;mode = base64
.parse_hdr:
;rsi -> "MODE NAME"; parse octal mode
    xor     rax, rax
.mode:
    movzx   rdx, byte [rsi]
    cmp     dl, '0'
    jb      .mode_done
    cmp     dl, '7'
    ja      .mode_done
    shl     rax, 3
    sub     dl, '0'
    add     rax, rdx
    inc     rsi
    jmp     .mode
.mode_done:
    mov     [hdr_mode], rax
    cmp     byte [rsi], ' '
    jne     error
    inc     rsi                         ;skip the space -> name
;copy the name into hdr_name
    xor     rcx, rcx
.cpy:
    mov     al, [rsi + rcx]
    mov     [hdr_name + rcx], al
    test    al, al
    je      .name_done
    inc     rcx
    jmp     .cpy
.name_done:

open_output:
    mov     rdi, [o_target]
    test    rdi, rdi
    jnz     .have_target
mov     rdi, hdr_name               ;default: the header file name
.have_target:
    cmp     byte [rdi], '-'
    jne     .file
    cmp     byte [rdi + 1], 0
    jne     .file
    mov     qword [out_fd], STDOUT_FILENO
    jmp     decode
.file:
    mov     rax, SYS_OPEN
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, [hdr_mode]
    syscall
    test    rax, rax
    js      error
    mov     [out_fd], rax

decode:
    cmp     r14, 1
    je      decode_b64

; ---------------- uu decode ----------------
decode_uu:
    mov     r8, [in_fd]
    call    read_line
    cmp     rax, -1
    je      .done
;stop at "end"
    mov     rsi, linebuf
    cmp     byte [rsi], 'e'
    jne     .data
    cmp     byte [rsi + 1], 'n'
    jne     .data
    cmp     byte [rsi + 2], 'd'
    je      .done
.data:
;length = DEC(linebuf[0]); 0 means the terminator line
    movzx   rax, byte [linebuf]
    sub     al, 0x20
    and     al, 0x3f
    movzx   r9, al                      ;bytes to output on this line
    test    r9, r9
    jz      decode_uu                   ;empty line, keep scanning for "end"
    mov     rbx, 1                      ;source index (skip length char)
    xor     r10, r10                    ;output index
.grp:
    cmp     r10, r9
    jge     .emit
;decode 4 chars -> 3 bytes
    movzx   rax, byte [linebuf + rbx]
    sub     al, 0x20
    and     al, 0x3f
    movzx   rcx, byte [linebuf + rbx + 1]
    sub     cl, 0x20
    and     cl, 0x3f
    movzx   rdx, byte [linebuf + rbx + 2]
    sub     dl, 0x20
    and     dl, 0x3f
    movzx   rsi, byte [linebuf + rbx + 3]
    sub     sil, 0x20
    and     sil, 0x3f
;b0 = (a<<2)|(b>>4)
    mov     r11, rax
    shl     r11, 2
    mov     rdi, rcx
    shr     rdi, 4
    or      r11, rdi
    mov     [outline + r10], r11b
    inc     r10
    cmp     r10, r9
    jge     .grp_next
;b1 = (b<<4)|(c>>2)
    mov     r11, rcx
    shl     r11, 4
    mov     rdi, rdx
    shr     rdi, 2
    or      r11, rdi
    mov     [outline + r10], r11b
    inc     r10
    cmp     r10, r9
    jge     .grp_next
;b2 = (c<<6)|d
    mov     r11, rdx
    shl     r11, 6
    or      r11, rsi
    mov     [outline + r10], r11b
    inc     r10
.grp_next:
    add     rbx, 4
    jmp     .grp
.emit:
    mov     rax, SYS_WRITE
    mov     rdi, [out_fd]
    mov     rsi, outline
    mov     rdx, r9
    syscall
    jmp     decode_uu
.done:
    jmp     finish

; ---------------- base64 decode ----------------
decode_b64:
    mov     r8, [in_fd]
    call    read_line
    cmp     rax, -1
    je      finish
    cmp     byte [linebuf], '='         ;"====" terminator
    je      finish
;decode the line's base64 characters
    xor     rbx, rbx                    ;source index
    xor     r10, r10                    ;output index
    xor     r8, r8                      ;bit accumulator
    xor     r9, r9                      ;bits held
.dl:
    mov     al, [linebuf + rbx]
    test    al, al
    je      .flush
    movzx   rax, al
    inc     rbx
    movzx   rdx, byte [dec_table + rax]
    cmp     dl, 0xFF
    je      .dl
    shl     r8, 6
    or      r8, rdx
    add     r9, 6
    cmp     r9, 8
    jl      .dl
    sub     r9, 8
    mov     rax, r8
    mov     rcx, r9
    shr     rax, cl
    and     rax, 0xFF
    mov     [outline + r10], al
    inc     r10
    mov     rax, 1
    shl     rax, cl
    dec     rax
    and     r8, rax
    jmp     .dl
.flush:
    test    r10, r10
    jz      decode_b64
    mov     rax, SYS_WRITE
    mov     rdi, [out_fd]
    mov     rsi, outline
    mov     rdx, r10
    syscall
    jmp     decode_b64

finish:
    cmp     qword [out_fd], STDOUT_FILENO
    je      .ok
    mov     rax, SYS_CLOSE
    mov     rdi, [out_fd]
    syscall
.ok:
    exit    0

error:
    write   STDERR_FILENO, err_msg, err_len
    exit    1

; read_line: read a line from fd r8 into linebuf (newline stripped, NUL
; terminated). rax = length, or -1 at EOF with no data.
read_line:
    push    rbx
    xor     rbx, rbx
.loop:
    mov     rax, SYS_READ
    mov     rdi, r8
    lea     rsi, [linebuf + rbx]
    mov     rdx, 1
    syscall
    cmp     rax, 0
    jle     .eof
    cmp     byte [linebuf + rbx], WHITESPACE_NL
    je      .done
    inc     rbx
    cmp     rbx, 4095
    jl      .loop
.done:
    mov     byte [linebuf + rbx], 0
    mov     rax, rbx
    pop     rbx
    ret
.eof:
    test    rbx, rbx
    jnz     .done
    mov     byte [linebuf], 0
    mov     rax, -1
    pop     rbx
    ret
