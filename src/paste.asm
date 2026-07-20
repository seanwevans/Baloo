; src/paste.asm -- paste(1): merge corresponding lines of files.
; Usage: paste [-s] [-d LIST] [FILE...]   ("-" or no FILE = stdin).
;
; Default (parallel) mode reads one line from each file per output row, joined
; by the delimiter list (default tab), and keeps going until every file is
; exhausted; an exhausted file contributes an empty field. -s (serial) folds
; each file's lines onto a single output line. -d gives the delimiter list,
; cycled per gap; a delimiter unit may be an escape (\0 = none, \t, \n, \\) or
; a UTF-8 character with trailing zero-width combining marks.

    %include "include/sysdefs.inc"

    %define LINECAP (1024 * 1024)

section .bss
    linebuf     resb LINECAP
    files       resq 256
    fds         resq 256
    nfiles      resq 1
    s_flag      resb 1
    dstr        resq 1                  ;delimiter list pointer
    dpos        resq 1                  ;current position in the list
    d_start     resq 1                  ;start of the current delimiter unit
    d_len       resq 1                  ;byte length of the current unit
    d_is_esc    resq 1                  ;unit is a single unescaped char
    esc_char    resb 1
    linelen     resq 1
    seq_fd      resq 1
    gl_fd       resq 1
    fi          resq 1
    nlbuf       resb 1

section .data
    def_tab     db 9, 0
    dash        db "-", 0
err_msg     db "paste: cannot open file", WHITESPACE_NL
    err_len     equ $ - err_msg

zw_ranges:
    dq 0x0300, 0x036F
    dq 0x0483, 0x0489
    dq 0x0591, 0x05BD
    dq 0x0610, 0x061A
    dq 0x064B, 0x065F
    dq 0x06D6, 0x06DC
    dq 0x1AB0, 0x1AFF
    dq 0x1DC0, 0x1DFF
    dq 0x200B, 0x200F
    dq 0x20D0, 0x20FF
    dq 0xFE20, 0xFE2F
    dq 0

wide_ranges:
    dq 0x1100, 0x115F
    dq 0x2329, 0x232A
    dq 0x2E80, 0x303E
    dq 0x3041, 0x33FF
    dq 0x3400, 0x4DBF
    dq 0x4E00, 0x9FFF
    dq 0xA000, 0xA4CF
    dq 0xAC00, 0xD7A3
    dq 0xF900, 0xFAFF
    dq 0xFE10, 0xFE19
    dq 0xFE30, 0xFE6F
    dq 0xFF00, 0xFF60
    dq 0xFFE0, 0xFFE6
    dq 0x20000, 0x3FFFD
    dq 0

section .text
global _start

_start:
    mov     qword [nfiles], 0
    mov     byte [s_flag], 0
    mov     qword [dstr], def_tab

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    je      after_parse
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .file
    cmp     byte [rdi + 1], 0
    je      .file                       ;lone "-" operand
    lea     rsi, [rdi + 1]
.optc:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 's'
    je      .set_s
    cmp     al, 'd'
    je      .set_d
    inc     rsi
    jmp     .optc
.set_s:
    mov     byte [s_flag], 1
    inc     rsi
    jmp     .optc
.set_d:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .d_here
    add     r13, 8
    dec     r12
    mov     rsi, [r13]
.d_here:
    mov     [dstr], rsi
    jmp     .nextarg
.file:
    mov     rcx, [nfiles]
    mov     [files + rcx*8], rdi
    inc     qword [nfiles]
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

after_parse:
    cmp     qword [nfiles], 0
    jne     .open
    mov     qword [files], dash         ;default operand is stdin
    mov     qword [nfiles], 1
.open:
    mov     qword [fi], 0
.oloop:
    mov     rax, [fi]
    cmp     rax, [nfiles]
    jge     .run
    mov     rcx, [fi]
    mov     rdi, [files + rcx*8]
    cmp     byte [rdi], '-'
    jne     .openfile
    cmp     byte [rdi + 1], 0
    jne     .openfile
    xor     rax, rax                    ;stdin
    jmp     .storefd
.openfile:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .openfail
.storefd:
    mov     rcx, [fi]
    mov     [fds + rcx*8], rax
    inc     qword [fi]
    jmp     .oloop
.openfail:
    write   STDERR_FILENO, err_msg, err_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall

.run:
    cmp     byte [s_flag], 1
    jne     .parallel
    mov     qword [fi], 0
.sloop:
    mov     rax, [fi]
    cmp     rax, [nfiles]
    jge     .exit
    mov     rcx, [fi]
    mov     rax, [fds + rcx*8]
    mov     [seq_fd], rax
    call    paste_seq
    mov     byte [nlbuf], WHITESPACE_NL
    mov     rsi, nlbuf
    mov     rdx, 1
    call    put_bytes
    inc     qword [fi]
    jmp     .sloop
.parallel:
    call    paste_parallel
.exit:
    xor     rdi, rdi
    mov     rax, SYS_EXIT
    syscall

; paste_parallel: one line per file per row until all are exhausted.
paste_parallel:
.row:
    mov     rax, [dstr]
    mov     [dpos], rax                 ;reset the delimiter cycle
    xor     r12, r12                    ;slot index
    xor     r13, r13                    ;any output this row
.slot:
    cmp     r12, [nfiles]
    jge     .endrow
    mov     rcx, r12
    mov     rax, [fds + rcx*8]
    cmp     rax, -1
    je      .eofslot
    mov     rdi, rax
    call    getline
    test    rax, rax
    jg      .havedata
    mov     rcx, r12
    mov     rdi, [fds + rcx*8]
    cmp     rdi, STDIN_FILENO
    je      .marker
    mov     rax, SYS_CLOSE
    syscall
.marker:
    mov     rcx, r12
    mov     qword [fds + rcx*8], -1
    test    r13, r13
    jz      .next
    mov     qword [linelen], 0
    jmp     .emit
.eofslot:
    test    r13, r13
    jz      .next
    mov     qword [linelen], 0
    jmp     .emit
.havedata:
    mov     [linelen], rax
.emit:
    test    r13, r13
    jz      .dc_i
    mov     r14, 1
    jmp     .dc_done
.dc_i:
    mov     r14, r12
.dc_done:
    mov     r13, 1
.dloop:
    test    r14, r14
    jz      .field
    call    emit_one_delim
    dec     r14
    jmp     .dloop
.field:
    mov     rdx, [linelen]
    test    rdx, rdx
    jz      .next
    mov     rax, rdx
    dec     rax
    cmp     byte [linebuf + rax], WHITESPACE_NL
    jne     .nostrip
    dec     rdx
.nostrip:
    mov     rsi, linebuf
    call    put_bytes
.next:
    inc     r12
    jmp     .slot
.endrow:
    test    r13, r13
    jz      .done
    mov     byte [nlbuf], WHITESPACE_NL
    mov     rsi, nlbuf
    mov     rdx, 1
    call    put_bytes
    jmp     .row
.done:
    ret

; paste_seq: fold all lines of [seq_fd] onto one line (no trailing newline).
paste_seq:
    mov     rax, [dstr]
    mov     [dpos], rax
    xor     r13, r13                    ;any
    xor     r12, r12                    ;field index
.loop:
    mov     rdi, [seq_fd]
    call    getline
    test    rax, rax
    jg      .havedata
    mov     rdi, [seq_fd]
    cmp     rdi, STDIN_FILENO
    je      .ret
    mov     rax, SYS_CLOSE
    syscall
.ret:
    ret
.havedata:
    mov     [linelen], rax
    test    r13, r13
    jz      .dc_i
    mov     r14, 1
    jmp     .dc_done
.dc_i:
    mov     r14, r12
.dc_done:
    mov     r13, 1
.dloop:
    test    r14, r14
    jz      .field
    call    emit_one_delim
    dec     r14
    jmp     .dloop
.field:
    mov     rdx, [linelen]
    mov     rax, rdx
    dec     rax
    cmp     byte [linebuf + rax], WHITESPACE_NL
    jne     .nostrip
    dec     rdx
.nostrip:
    mov     rsi, linebuf
    call    put_bytes
    inc     r12
    jmp     .loop

; getline: rdi = fd -> rax = line length in linebuf (with any trailing newline),
; 0 at EOF. Reads a byte at a time so a shared stdin stops exactly at newline.
getline:
    mov     [gl_fd], rdi
    xor     r10, r10                    ;count (survives syscalls)
.l:
    mov     rax, SYS_READ
    mov     rdi, [gl_fd]
    lea     rsi, [linebuf + r10]
    mov     rdx, 1
    syscall
    test    rax, rax
    jle     .done
    inc     r10
    cmp     byte [linebuf + r10 - 1], WHITESPACE_NL
    je      .done
    cmp     r10, LINECAP - 1
    jl      .l
.done:
    mov     rax, r10
    ret

; emit_one_delim: output the next delimiter unit and advance [dpos]. Cycles the
; list; preserves r12-r15.
emit_one_delim:
    mov     qword [d_is_esc], 0
    mov     qword [d_len], 0
    mov     rsi, [dstr]
    cmp     byte [rsi], 0
je      .wrap                       ;empty list: emit nothing
    mov     rsi, [dpos]
    mov     [d_start], rsi
    movzx   eax, byte [rsi]
    cmp     al, 0x5C                    ;backslash
    je      .escape
.utf:
    mov     rdi, [dpos]
    call    utf8_char                   ;rax = byte length, rdx = codepoint
    test    rax, rax
    jle     .utf_end
    add     [dpos], rax
    mov     rdi, rdx
    call    wcwidth
    test    rax, rax
jz      .utf                        ;zero width: accumulate combining marks
jns     .utf_end                    ;positive width: this char ends the unit
mov     rax, [d_start]              ;control: unit is one byte
    inc     rax
    mov     [dpos], rax
.utf_end:
    mov     rax, [dpos]
    sub     rax, [d_start]
    mov     [d_len], rax
    jmp     .wrap
.escape:
    inc     qword [dpos]                ;skip the backslash
    mov     rax, [dpos]
    movzx   ecx, byte [rax]
    cmp     cl, '0'
    jne     .esc_other
    inc     qword [dpos]                ;\0 -> emit nothing
    mov     qword [d_len], 0
    jmp     .wrap
.esc_other:
    movzx   edi, cl
    call    unescape
    test    al, al
    jz      .esc_literal
    mov     [esc_char], al
    mov     qword [d_is_esc], 1
    mov     qword [d_len], 1
    inc     qword [dpos]
    jmp     .wrap
.esc_literal:
mov     qword [d_len], 1            ;unknown escape: emit the backslash
.wrap:
    mov     rax, [dpos]
    cmp     byte [rax], 0
    jne     .doemit
    mov     rax, [dstr]
    mov     [dpos], rax
.doemit:
    cmp     qword [d_len], 0
    je      .ret
    cmp     qword [d_is_esc], 1
    jne     .emit_normal
    mov     rsi, esc_char
    mov     rdx, 1
    call    put_bytes
    ret
.emit_normal:
    mov     rsi, [d_start]
    mov     rdx, [d_len]
    call    put_bytes
.ret:
    ret

; utf8_char: rdi = ptr -> rax = byte length, rdx = codepoint.
utf8_char:
    movzx   eax, byte [rdi]
    test    al, al
    jz      .zero
    cmp     al, 0x80
    jb      .one
    mov     cl, al
    and     cl, 0xE0
    cmp     cl, 0xC0
    je      .two
    mov     cl, al
    and     cl, 0xF0
    cmp     cl, 0xE0
    je      .three
    mov     cl, al
    and     cl, 0xF8
    cmp     cl, 0xF0
    je      .four
.one:
    mov     rdx, rax
    mov     rax, 1
    ret
.two:
    movzx   r8d, byte [rdi + 1]
    and     eax, 0x1F
    shl     eax, 6
    and     r8d, 0x3F
    or      eax, r8d
    mov     rdx, rax
    mov     rax, 2
    ret
.three:
    movzx   r8d, byte [rdi + 1]
    movzx   r9d, byte [rdi + 2]
    and     eax, 0x0F
    shl     eax, 12
    and     r8d, 0x3F
    shl     r8d, 6
    or      eax, r8d
    and     r9d, 0x3F
    or      eax, r9d
    mov     rdx, rax
    mov     rax, 3
    ret
.four:
    movzx   r8d, byte [rdi + 1]
    movzx   r9d, byte [rdi + 2]
    movzx   ecx, byte [rdi + 3]
    and     eax, 0x07
    shl     eax, 18
    and     r8d, 0x3F
    shl     r8d, 12
    or      eax, r8d
    and     r9d, 0x3F
    shl     r9d, 6
    or      eax, r9d
    and     ecx, 0x3F
    or      eax, ecx
    mov     rdx, rax
    mov     rax, 4
    ret
.zero:
    xor     rdx, rdx
    xor     rax, rax
    ret

; wcwidth: rdi = codepoint -> rax width (-1 control, 0, 1, 2).
wcwidth:
    test    rdi, rdi
    jz      .zero
    cmp     rdi, 32
    jb      .neg
    cmp     rdi, 0x7F
    jb      .width1
    cmp     rdi, 0xA0
    jb      .neg
    mov     rsi, zw_ranges
    call    range_check
    test    rax, rax
    jnz     .zero
    mov     rsi, wide_ranges
    call    range_check
    test    rax, rax
    jnz     .two
.width1:
    mov     rax, 1
    ret
.two:
    mov     rax, 2
    ret
.zero:
    xor     rax, rax
    ret
.neg:
    mov     rax, -1
    ret

; range_check: rdi = codepoint, rsi = lo/hi table (0 sentinel) -> rax 1/0.
range_check:
.l:
    mov     rax, [rsi]
    test    rax, rax
    jz      .no
    mov     rdx, [rsi + 8]
    cmp     rdi, rax
    jb      .next
    cmp     rdi, rdx
    jbe     .yes
.next:
    add     rsi, 16
    jmp     .l
.yes:
    mov     rax, 1
    ret
.no:
    xor     rax, rax
    ret

; unescape: dil = escape letter -> al = byte value, or 0 if unknown.
unescape:
    movzx   eax, dil
    cmp     al, 'n'
    je      .n
    cmp     al, 't'
    je      .t
    cmp     al, 'r'
    je      .r
    cmp     al, 0x5C
    je      .bs
    cmp     al, 'a'
    je      .a
    cmp     al, 'b'
    je      .b
    cmp     al, 'f'
    je      .f
    cmp     al, 'v'
    je      .v
    xor     al, al
    ret
.n:
    mov     al, 10
    ret
.t:
    mov     al, 9
    ret
.r:
    mov     al, 13
    ret
.bs:
    mov     al, 0x5C
    ret
.a:
    mov     al, 7
    ret
.b:
    mov     al, 8
    ret
.f:
    mov     al, 12
    ret
.v:
    mov     al, 11
    ret

; put_bytes: rsi = ptr, rdx = length -> stdout (nothing when length <= 0).
put_bytes:
    test    rdx, rdx
    jle     .done
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
.done:
    ret
