; src/wc.asm -- wc(1): count lines, words, characters, bytes, max line length.
; Usage: wc [-Lcmwl] [FILE...]   ("-" or no FILE = stdin).
;
; Field order printed is lines, words, chars(-m), bytes(-c), maxlen(-L) --
; only the requested fields, in that order. Default is -lwc. Fields are
; right-justified in a seven-wide column unless there is exactly one file
; operand, or stdin with a single field, in which case no padding is used
; (matching toybox). With more than one operand a "total" line follows.

    %include "include/sysdefs.inc"

    %define BUFCAP (8 * 1024 * 1024)
    %define FL_l 1
    %define FL_w 2
    %define FL_m 4
    %define FL_c 8
    %define FL_L 16

section .bss
    inbuf       resb BUFCAP
    files       resq 256
    lengths     resq 5
    totals      resq 5
    numbuf      resb 32
    optflags    resq 1
    optc        resq 1
    spacew      resq 1
    nfiles      resq 1
    fi          resq 1
    tmpname     resq 1
    had_err     resb 1
; do_wc state
    dw_fd       resq 1
    dw_name     resq 1
    dw_len      resq 1
    dw_pos      resq 1
    dw_clen     resq 1
    dw_wchar    resq 1
    dw_line     resq 1
    dw_word     resq 1
    dw_space    resq 1
; print state
    pl_base     resq 1
    pl_name     resq 1
    pl_i        resq 1
    pl_first    resq 1
    pl_digptr   resq 1
    pl_diglen   resq 1
    pl_padn     resq 1
    pl_sp       resb 1

section .data
    total_str   db "total", 0
err_msg     db "wc: cannot open file", WHITESPACE_NL
    err_len     equ $ - err_msg

; zero-width (combining) codepoint ranges, lo/hi pairs, 0 sentinel.
zw_ranges:
    dq 0x0300, 0x036F
    dq 0x0483, 0x0489
    dq 0x0591, 0x05BD
    dq 0x05BF, 0x05BF
    dq 0x05C1, 0x05C2
    dq 0x05C4, 0x05C5
    dq 0x0610, 0x061A
    dq 0x064B, 0x065F
    dq 0x0670, 0x0670
    dq 0x06D6, 0x06DC
    dq 0x06DF, 0x06E4
    dq 0x0711, 0x0711
    dq 0x0730, 0x074A
    dq 0x1AB0, 0x1AFF
    dq 0x1DC0, 0x1DFF
    dq 0x200B, 0x200F
    dq 0x20D0, 0x20FF
    dq 0xFE20, 0xFE2F
    dq 0

; wide (double-width) codepoint ranges, lo/hi pairs, 0 sentinel.
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
    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12
    mov     qword [optflags], 0
    mov     qword [nfiles], 0
    mov     byte [had_err], 0

parse:
    cmp     r12, 0
    je      parsed
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .isfile
    cmp     byte [rdi + 1], 0
    je      .isfile                     ;lone "-" -> stdin operand
    lea     rsi, [rdi + 1]
.fl:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 'l'
    je      .fl_l
    cmp     al, 'w'
    je      .fl_w
    cmp     al, 'm'
    je      .fl_m
    cmp     al, 'c'
    je      .fl_c
    cmp     al, 'L'
    je      .fl_L
    inc     rsi
    jmp     .fl
.fl_l:
    or      qword [optflags], FL_l
    inc     rsi
    jmp     .fl
.fl_w:
    or      qword [optflags], FL_w
    inc     rsi
    jmp     .fl
.fl_m:
    or      qword [optflags], FL_m
    inc     rsi
    jmp     .fl
.fl_c:
    or      qword [optflags], FL_c
    inc     rsi
    jmp     .fl
.fl_L:
    or      qword [optflags], FL_L
    inc     rsi
    jmp     .fl
.isfile:
    mov     rcx, [nfiles]
    mov     [files + rcx*8], rdi
    inc     qword [nfiles]
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

parsed:
    cmp     qword [optflags], 0
    jne     .haveflags
    mov     qword [optflags], FL_l | FL_w | FL_c
.haveflags:
    mov     rax, [nfiles]
    mov     [optc], rax

;spacew = 7 unless optc==1, or (optc==0 and a single field)
    mov     qword [spacew], 0
    cmp     qword [optc], 1
    je      .space_done
    cmp     qword [optc], 0
    jne     .space7
    mov     rax, [optflags]
    mov     rdx, rax
    dec     rdx
    and     rax, rdx                    ;0 iff optflags has <=1 bit set
    jz      .space_done
.space7:
    mov     qword [spacew], 7
.space_done:

;zero totals
    xor     rcx, rcx
.zt:
    mov     qword [totals + rcx*8], 0
    inc     rcx
    cmp     rcx, 5
    jl      .zt

    cmp     qword [nfiles], 0
    jne     .files
    mov     rdi, STDIN_FILENO
    xor     rsi, rsi
    call    do_wc_and_print
    jmp     totals_out
.files:
    mov     qword [fi], 0
.floop:
    mov     rax, [fi]
    cmp     rax, [nfiles]
    jge     totals_out
    mov     rcx, [fi]
    mov     rdi, [files + rcx*8]
    cmp     byte [rdi], '-'
    jne     .open
    cmp     byte [rdi + 1], 0
    jne     .open
    mov     rsi, rdi                    ;name "-"
    mov     rdi, STDIN_FILENO
    jmp     .call
.open:
    mov     [tmpname], rdi
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .openfail
    mov     rsi, [tmpname]
    mov     rdi, rax
.call:
    call    do_wc_and_print
.fnext:
    inc     qword [fi]
    jmp     .floop
.openfail:
    write   STDERR_FILENO, err_msg, err_len
    mov     byte [had_err], 1
    jmp     .fnext

totals_out:
    cmp     qword [nfiles], 1
    jbe     .end
    mov     rdi, totals
    mov     rsi, total_str
    call    print_lengths
.end:
    movzx   eax, byte [had_err]
    mov     rdi, rax
    mov     rax, SYS_EXIT
    syscall

; do_wc_and_print: rdi = fd, rsi = name (0 = stdin, no name printed).
do_wc_and_print:
    mov     [dw_fd], rdi
    mov     [dw_name], rsi

    xor     rcx, rcx
.zl:
    mov     qword [lengths + rcx*8], 0
    inc     rcx
    cmp     rcx, 5
    jl      .zl

;read the whole input into inbuf (capped at BUFCAP)
    xor     r15, r15
.rd:
    mov     rdx, BUFCAP
    sub     rdx, r15
    jz      .rdone
    mov     rax, SYS_READ
    mov     rdi, [dw_fd]
    lea     rsi, [inbuf + r15]
    syscall
    test    rax, rax
    jle     .rdone
    add     r15, rax
    jmp     .rd
.rdone:
    mov     [dw_len], r15

    mov     qword [dw_pos], 0
    mov     qword [dw_clen], 1
    mov     qword [dw_line], 0
    mov     qword [dw_word], 0
    mov     qword [dw_space], 0

.loop:
    mov     rax, [dw_pos]
    cmp     rax, [dw_len]
    jge     .after
    movzx   ecx, byte [inbuf + rax]
    cmp     cl, WHITESPACE_NL
    jne     .nnl
    inc     qword [lengths + 0]
.nnl:
    inc     qword [lengths + 24]        ;bytes (index 3)
    test    qword [optflags], FL_m | FL_L
    jz      .ascii
    dec     qword [dw_clen]
    cmp     qword [dw_clen], 1
jge     .word                       ;continuation byte: reuse dw_space
    call    utf8_decode
    inc     qword [lengths + 16]        ;chars (index 2)
    call    wc_addwidth
    jmp     .word
.ascii:
    mov     qword [dw_space], 0
    cmp     cl, ' '
    je      .setsp
    mov     dl, cl
    sub     dl, 9
    cmp     dl, 4                       ;9..13 -> tab,nl,vt,ff,cr
    ja      .word
.setsp:
    mov     qword [dw_space], 1
.word:
    cmp     qword [dw_space], 0
    je      .notspace
    mov     qword [dw_word], 0
    jmp     .adv
.notspace:
    cmp     qword [dw_word], 0
    jne     .adv
    inc     qword [lengths + 8]         ;words (index 1)
    mov     qword [dw_word], 1
.adv:
    inc     qword [dw_pos]
    jmp     .loop
.after:
    mov     rax, [dw_line]
    cmp     rax, [lengths + 32]         ;maxlen (index 4)
    jbe     .accum
    mov     [lengths + 32], rax
.accum:
;totals[0..3] += lengths; totals[4] = max
    mov     rax, [lengths + 0]
    add     [totals + 0], rax
    mov     rax, [lengths + 8]
    add     [totals + 8], rax
    mov     rax, [lengths + 16]
    add     [totals + 16], rax
    mov     rax, [lengths + 24]
    add     [totals + 24], rax
    mov     rax, [lengths + 32]
    cmp     rax, [totals + 32]
    jbe     .noclose
    mov     [totals + 32], rax
.noclose:
;close non-stdin fd
    mov     rdi, [dw_fd]
    cmp     rdi, STDIN_FILENO
    je      .print
    mov     rax, SYS_CLOSE
    syscall
.print:
    mov     rdi, lengths
    mov     rsi, [dw_name]
    call    print_lengths
    ret

; utf8_decode: decode the sequence at inbuf+[dw_pos]; set [dw_clen], [dw_wchar].
utf8_decode:
    mov     rsi, [dw_pos]
    mov     rax, [dw_len]
    sub     rax, rsi                    ;remaining bytes
    movzx   edx, byte [inbuf + rsi]     ;b0
    cmp     dl, 0x80
    jb      .one
    mov     cl, dl
    and     cl, 0xE0
    cmp     cl, 0xC0
    je      .two
    mov     cl, dl
    and     cl, 0xF0
    cmp     cl, 0xE0
    je      .three
    mov     cl, dl
    and     cl, 0xF8
    cmp     cl, 0xF0
    je      .four
.one:
    and     edx, 0xFF
    mov     [dw_wchar], rdx
    mov     qword [dw_clen], 1
    ret
.two:
    cmp     rax, 2
    jl      .one
    movzx   r8d, byte [inbuf + rsi + 1]
    and     edx, 0x1F
    shl     edx, 6
    and     r8d, 0x3F
    or      edx, r8d
    mov     [dw_wchar], rdx
    mov     qword [dw_clen], 2
    ret
.three:
    cmp     rax, 3
    jl      .one
    movzx   r8d, byte [inbuf + rsi + 1]
    movzx   r9d, byte [inbuf + rsi + 2]
    and     edx, 0x0F
    shl     edx, 12
    and     r8d, 0x3F
    shl     r8d, 6
    or      edx, r8d
    and     r9d, 0x3F
    or      edx, r9d
    mov     [dw_wchar], rdx
    mov     qword [dw_clen], 3
    ret
.four:
    cmp     rax, 4
    jl      .one
    movzx   r8d, byte [inbuf + rsi + 1]
    movzx   r9d, byte [inbuf + rsi + 2]
    movzx   ecx, byte [inbuf + rsi + 3]
    and     edx, 0x07
    shl     edx, 18
    and     r8d, 0x3F
    shl     r8d, 12
    or      edx, r8d
    and     r9d, 0x3F
    shl     r9d, 6
    or      edx, r9d
    and     ecx, 0x3F
    or      edx, ecx
    mov     [dw_wchar], rdx
    mov     qword [dw_clen], 4
    ret

; wc_addwidth: fold the decoded [dw_wchar] into [dw_line]/maxlen and dw_space.
wc_addwidth:
    mov     rdi, [dw_wchar]
    call    wcwidth
    test    rax, rax
    jns     .pos
    xor     rax, rax
.pos:
    add     [dw_line], rax
    mov     rdi, [dw_wchar]
    cmp     rdi, 9                      ;tab
    jne     .notab
    mov     rax, [dw_line]
    and     rax, 7
    mov     rdx, 8
    sub     rdx, rax
    add     [dw_line], rdx
    jmp     .setspace
.notab:
    cmp     rdi, 10
    je      .nl
    cmp     rdi, 13
    je      .nl
    jmp     .setspace
.nl:
    mov     rax, [dw_line]
    cmp     rax, [lengths + 32]
    jbe     .reset
    mov     [lengths + 32], rax
.reset:
    mov     qword [dw_line], 0
.setspace:
    mov     rdi, [dw_wchar]
    mov     qword [dw_space], 0
    cmp     rdi, ' '
    je      .sp
    cmp     rdi, 9
    jb      .sdone
    cmp     rdi, 13
    jbe     .sp
    jmp     .sdone
.sp:
    mov     qword [dw_space], 1
.sdone:
    ret

; wcwidth: rdi = codepoint -> rax width (-1 control, 0, 1, or 2).
wcwidth:
    test    rdi, rdi
    jz      .zero
    cmp     rdi, 32
    jb      .neg
    cmp     rdi, 0x7F
    jb      .width1                     ;printable ASCII
    cmp     rdi, 0xA0
    jb      .neg                        ;0x7F..0x9F control
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

; range_check: rdi = codepoint, rsi = table of lo/hi pairs (0 sentinel);
; rax = 1 if inside any range else 0. Preserves rdi.
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

; print_lengths: rdi = base (lengths/totals), rsi = name (0 = none).
print_lengths:
    mov     [pl_base], rdi
    mov     [pl_name], rsi
    mov     qword [pl_i], 0
    mov     qword [pl_first], 1
.loop:
    mov     rax, [pl_i]
    cmp     rax, 5
    jge     .name
    mov     rcx, [pl_i]
    mov     rdx, 1
    shl     rdx, cl
    test    [optflags], rdx
    jz      .next
    cmp     qword [pl_first], 1
    je      .noprefix
    mov     byte [pl_sp], ' '
    write   STDOUT_FILENO, pl_sp, 1
.noprefix:
    mov     qword [pl_first], 0
    mov     rax, [pl_i]
    mov     rcx, [pl_base]
    mov     rdi, [rcx + rax*8]
    mov     rsi, [spacew]
    call    print_num_padded
.next:
    inc     qword [pl_i]
    jmp     .loop
.name:
    cmp     qword [pl_name], 0
    je      .nl
    mov     byte [pl_sp], ' '
    write   STDOUT_FILENO, pl_sp, 1
    mov     rsi, [pl_name]
    call    print_cstr
.nl:
    mov     byte [pl_sp], WHITESPACE_NL
    write   STDOUT_FILENO, pl_sp, 1
    ret

; print_num_padded: rdi = value, rsi = min field width (space-padded).
print_num_padded:
    mov     rax, rdi
    lea     rcx, [numbuf + 31]
    mov     r8, 10
    xor     r9, r9
.d:
    xor     rdx, rdx
    div     r8
    add     dl, '0'
    dec     rcx
    mov     [rcx], dl
    inc     r9
    test    rax, rax
    jnz     .d
    mov     [pl_digptr], rcx
    mov     [pl_diglen], r9
    mov     rax, rsi
    sub     rax, r9
    jle     .digits
    mov     [pl_padn], rax
.pad:
    mov     byte [pl_sp], ' '
    write   STDOUT_FILENO, pl_sp, 1
    dec     qword [pl_padn]
    jnz     .pad
.digits:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, [pl_digptr]
    mov     rdx, [pl_diglen]
    syscall
    ret

; print_cstr: rsi = NUL-terminated string -> stdout.
print_cstr:
    xor     rdx, rdx
.len:
    cmp     byte [rsi + rdx], 0
    je      .out
    inc     rdx
    jmp     .len
.out:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    ret
