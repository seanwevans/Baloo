; src/fmt.asm -- fmt(1): reflow paragraphs to a target width.
; Usage: fmt [-w WIDTH] [FILE...]   (no FILE or "-" = stdin, default width 75).
;
; Consecutive non-blank lines form a paragraph whose words are re-wrapped so a
; line breaks before a word would reach the width (pos + word + separator >=
; width, matching toybox). A paragraph keeps the indentation of its first line;
; blank or whitespace-only lines are emitted as paragraph separators.

    %include "include/sysdefs.inc"

    %define BUFCAP (8 * 1024 * 1024)

section .bss
    inbuf       resb BUFCAP
    obuf        resb (BUFCAP + 4096)
    files       resq 256
    nfiles      resq 1
    inlen       resq 1
    obuf_len    resq 1
    cur_fd      resq 1
    width       resq 1
    pos         resq 1
    level       resq 1
    fl_ptr      resq 1
    fl_len      resq 1
    fl_idx      resq 1
    fl_indent   resq 1
    fl_levelcols resq 1
    fl_wstart   resq 1
    fl_wlen     resq 1
    fl_cnt      resq 1

section .text
global _start

_start:
    mov     qword [width], 75
    mov     qword [pos], 0
    mov     qword [level], 0
    mov     qword [obuf_len], 0
    mov     qword [nfiles], 0

    mov     r8, [rsp]                   ;argc
    lea     r9, [rsp + 16]              ;&argv[1]
    dec     r8
parse:
    cmp     r8, 0
    je      after_parse
    mov     rdi, [r9]
    cmp     byte [rdi], '-'
    jne     .file
    cmp     byte [rdi + 1], 0
    je      .file                       ;lone "-" -> stdin
    cmp     byte [rdi + 1], 'w'
    jne     .pnext                      ;ignore other options
    cmp     byte [rdi + 2], 0
    jne     .wattached
    add     r9, 8
    dec     r8
    mov     rdi, [r9]
    jmp     .watou
.wattached:
    lea     rdi, [rdi + 2]
.watou:
    call    atou
    mov     [width], rax
    jmp     .pnext
.file:
    mov     rcx, [nfiles]
    mov     [files + rcx*8], rdi
    inc     qword [nfiles]
.pnext:
    add     r9, 8
    dec     r8
    jmp     parse

after_parse:
    xor     r15, r15                    ;bytes read into inbuf
    cmp     qword [nfiles], 0
    jne     .files
    mov     qword [cur_fd], STDIN_FILENO
    call    read_into
    jmp     .process
.files:
    xor     r14, r14
.floop:
    cmp     r14, [nfiles]
    jge     .process
    mov     rdi, [files + r14*8]
    cmp     byte [rdi], '-'
    jne     .openf
    cmp     byte [rdi + 1], 0
    jne     .openf
    mov     qword [cur_fd], STDIN_FILENO
    jmp     .readf
.openf:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fnext
    mov     [cur_fd], rax
.readf:
    call    read_into
    mov     rdi, [cur_fd]
    cmp     rdi, STDIN_FILENO
    je      .fnext
    mov     rax, SYS_CLOSE
    syscall
.fnext:
    inc     r14
    jmp     .floop

.process:
    mov     [inlen], r15
    xor     r12, r12                    ;position in inbuf
.lineloop:
    cmp     r12, [inlen]
    jge     .flush
    mov     r14, r12
.findnl:
    cmp     r14, [inlen]
    jge     .gotline
    cmp     byte [inbuf + r14], WHITESPACE_NL
    je      .gotline
    inc     r14
    jmp     .findnl
.gotline:
    lea     rax, [inbuf + r12]
    mov     [fl_ptr], rax
    mov     rax, r14
    sub     rax, r12
    mov     [fl_len], rax
    call    fmt_line
    mov     r12, r14
    cmp     r12, [inlen]
    jge     .flush
    inc     r12
    jmp     .lineloop
.flush:
    cmp     qword [pos], 0
    je      .write
    mov     al, WHITESPACE_NL
    call    append_byte
.write:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, obuf
    mov     rdx, [obuf_len]
    syscall
    xor     rdi, rdi
    mov     rax, SYS_EXIT
    syscall

; read_into: append [cur_fd] to inbuf at offset r15; updates r15.
read_into:
.l:
    mov     rdx, BUFCAP
    sub     rdx, r15
    jz      .done
    mov     rax, SYS_READ
    mov     rdi, [cur_fd]
    lea     rsi, [inbuf + r15]
    syscall
    test    rax, rax
    jle     .done
    add     r15, rax
    jmp     .l
.done:
    ret

; fmt_line: reflow the line at [fl_ptr]/[fl_len]. Preserves r12/r14.
fmt_line:
    mov     qword [fl_idx], 0
    mov     qword [fl_levelcols], 0
.imeas:
    mov     rax, [fl_idx]
    cmp     rax, [fl_len]
    jge     .iend
    mov     rsi, [fl_ptr]
    movzx   eax, byte [rsi + rax]
    call    isws
    test    rax, rax
    jz      .iend
    mov     rsi, [fl_ptr]
    mov     rcx, [fl_idx]
    movzx   eax, byte [rsi + rcx]
    cmp     al, 9
    jne     .isp
    mov     rax, [fl_levelcols]
    and     rax, 7
    mov     rcx, 8
    sub     rcx, rax
    add     [fl_levelcols], rcx
    jmp     .inext
.isp:
    cmp     al, ' '
    jne     .inext
    inc     qword [fl_levelcols]
.inext:
    inc     qword [fl_idx]
    jmp     .imeas
.iend:
    mov     rax, [fl_idx]
    mov     [fl_indent], rax
    cmp     rax, [fl_len]
    jne     .notblank
    mov     al, WHITESPACE_NL
    call    append_byte
    mov     qword [level], 0
    cmp     qword [pos], 0
    je      .b2
    mov     al, WHITESPACE_NL
    call    append_byte
.b2:
    mov     qword [pos], 0
    ret
.notblank:
    mov     rax, [fl_levelcols]
    cmp     rax, [level]
    je      .samelevel
    cmp     qword [pos], 0
    je      .lvlset
    mov     al, WHITESPACE_NL
    call    append_byte
    mov     qword [pos], 0
.lvlset:
.samelevel:
    mov     rax, [fl_levelcols]
    mov     [level], rax
.wloop:
    mov     rax, [fl_idx]
    cmp     rax, [fl_len]
    jge     .wdone
    mov     [fl_wstart], rax
.wscan:
    mov     rax, [fl_idx]
    cmp     rax, [fl_len]
    jge     .wend
    mov     rsi, [fl_ptr]
    movzx   eax, byte [rsi + rax]
    call    isws
    test    rax, rax
    jnz     .wend
    inc     qword [fl_idx]
    jmp     .wscan
.wend:
    mov     rax, [fl_idx]
    sub     rax, [fl_wstart]
    mov     [fl_wlen], rax
    mov     [fl_cnt], rax
    mov     rax, [pos]
    add     rax, [fl_cnt]
    cmp     qword [pos], 0
    je      .ns
    inc     rax
.ns:
    cmp     rax, [width]
    jl      .place
    cmp     qword [pos], 0
    je      .place
    mov     al, WHITESPACE_NL
    call    append_byte
    mov     qword [pos], 0
.place:
    cmp     qword [pos], 0
    jne     .notfirst
    mov     rax, [level]
    mov     [pos], rax
    cmp     qword [fl_indent], 0
    je      .pw
    mov     rsi, [fl_ptr]
    mov     rdx, [fl_indent]
    call    append_range
    jmp     .pw
.notfirst:
    mov     al, ' '
    call    append_byte
    inc     qword [fl_cnt]
.pw:
    mov     rsi, [fl_ptr]
    add     rsi, [fl_wstart]
    mov     rdx, [fl_wlen]
    call    append_range
    mov     rax, [fl_cnt]
    add     [pos], rax
.skipws:
    mov     rax, [fl_idx]
    cmp     rax, [fl_len]
    jge     .wloop
    mov     rsi, [fl_ptr]
    movzx   eax, byte [rsi + rax]
    call    isws
    test    rax, rax
    jz      .wloop
    inc     qword [fl_idx]
    jmp     .skipws
.wdone:
    ret

; isws: al = byte -> rax = 1 if ASCII whitespace else 0.
isws:
    cmp     al, ' '
    je      .y
    cmp     al, 9
    jb      .n
    cmp     al, 13
    jbe     .y
.n:
    xor     rax, rax
    ret
.y:
    mov     rax, 1
    ret

; append_byte: al -> obuf.
append_byte:
    mov     rcx, [obuf_len]
    mov     [obuf + rcx], al
    inc     qword [obuf_len]
    ret

; append_range: rsi = ptr, rdx = length -> obuf.
append_range:
    xor     rcx, rcx
.l:
    cmp     rcx, rdx
    jge     .d
    mov     al, [rsi + rcx]
    mov     r8, [obuf_len]
    mov     [obuf + r8], al
    inc     qword [obuf_len]
    inc     rcx
    jmp     .l
.d:
    ret

; atou: rdi -> unsigned decimal in rax.
atou:
    xor     rax, rax
.l:
    movzx   rcx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .done
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .l
.done:
    ret
