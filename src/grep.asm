; src/grep.asm -- grep(1): show lines matching a regular expression.
; Usage: grep [-abcEFHhIiLlnoqRrsvwxZz] [-ABC NUM] [-m MAX] [-e REGEX]...
;             [-f FILE]... [--color[=WHEN]] [--exclude-dir=PATTERN] [FILE]...
;
; Patterns come in two kinds. Most of what people search for is a plain
; string, perhaps with a dot, an anchor, or a backslashed character in it,
; and those are matched directly: they are filed under their first literal
; character and, within each of those, tried longest first, so a search with
; ten thousand patterns costs about the same as a search with one.
;
; A pattern that needs more than that -- a bracket expression, a repeat, a
; group, an alternation -- is compiled into a tree and matched by trying
; every way it could fit and keeping the longest, since POSIX asks for the
; longest match rather than the first one found.
;
; A line is matched over and over from where the last match ended, which is
; what -o needs to show every match, what --color needs to highlight them,
; and what -c must not count twice.

    %include "include/sysdefs.inc"

    %define SYS_LSEEK_ID 8
    %define SYS_GETDENTS_ID 217
    %define SYS_LSTAT_ID 6
    %define SYS_FSTAT_ID 5
    %define SYS_OPENAT_ID 257

    %define O_NONBLOCK_FLAG 0x800
    %define O_NOCTTY_FLAG 0x100
    %define O_DIRECTORY_FLAG 0x10000

    %define ST_MODE_OFF 24
    %define S_IFMT 0xF000
    %define S_IFDIR 0x4000
    %define S_IFLNK 0xA000

    %define MAXPATS 200000
    %define PATTEXT 8388608
    %define MAXFILES 4096
    %define LINECAP 1048576
    %define OUTCAP 262144
    %define MAXNODES 65536
    %define MAXCONTS 262144
    %define MAXCLASS 256
    %define MAXGROUPS 10
    %define MAXDEPTH 128
    %define PATHCAP 4096
    %define DIRCAP 32768
    %define READCAP 262144


; a node of a compiled pattern
    %define N_CHAR 0
    %define N_ANY 1
    %define N_CLASS 2
    %define N_BOL 3
    %define N_EOL 4
    %define N_GSTART 5
    %define N_GEND 6
    %define N_BACKREF 7
    %define N_ALT 8
    %define N_REP 9

    %define ND_TYPE 0
    %define ND_A 8
    %define ND_B 16
    %define ND_C 24
    %define ND_NEXT 32
    %define ND_SIZE 40

; a continuation: what is left to do once the piece being matched is done
    %define CT_KIND 0
    %define CT_NODE 8
    %define CT_COUNT 16
    %define CT_START 24
    %define CT_PARENT 32
    %define CT_SIZE 40

section .bss
    pat_ptr     resq MAXPATS
    pat_len     resq MAXPATS
    pat_next    resq MAXPATS
    patcount    resq 1
    pattext     resb PATTEXT
    pattextlen  resq 1
    bucket      resq 256

    regexes     resq 256                ;the compiled patterns
    regexcount  resq 1
    rx_rc       resq 256                ;whether each still has a live match
    rx_so       resq 256
    rx_eo       resq 256

    nodes       resb MAXNODES * ND_SIZE
    nodecount   resq 1
    classes     resb MAXCLASS * 32      ;a bitmap for each bracket expression
    classcount  resq 1
    conts       resb MAXCONTS * CT_SIZE
    conttop     resq 1
    altlist     resq 4096
    altcount    resq 1

    cap_s       resq MAXGROUPS
    cap_e       resq MAXGROUPS
    best_s      resq MAXGROUPS
    best_e      resq MAXGROUPS
    best_end    resq 1
    have_best   resq 1
    m_text      resq 1
    m_len       resq 1
    m_notbol    resq 1
    m_start     resq 1
    groupcount  resq 1

    files       resq MAXFILES
    filecount   resq 1
    excl_dir    resq 256
    excl_dircnt resq 1
    excl_pat    resq 256
    excl_patcnt resq 1
    incl_pat    resq 256
    incl_patcnt resq 1

    linebuf     resb LINECAP
    linelen     resq 1
    outbuf      resb OUTCAP
    outlen      resq 1
    readbuf     resb READCAP
    readpos     resq 1
    readend     resq 1
    readfd      resq 1
    readeof     resq 1
    readerr     resq 1

    ctxbuf      resb LINECAP            ;lines held back for -B
    ctxlen      resq 1
    ctx_off     resq MAXDEPTH
    ctx_len     resq MAXDEPTH
    ctx_boff    resq MAXDEPTH
    ctx_count   resq 1

    pathbuf     resb PATHCAP
    pathlen     resq 1
    dirbufs     resb MAXDEPTH * 8
    stbuf       resb 160
    numbuf      resb 32

    opt_A       resq 1
    opt_B       resq 1
    opt_C       resq 1
    opt_m       resq 1
    have_A      resb 1
    have_B      resb 1
    have_C      resb 1
    have_m      resb 1
    opt_a       resb 1
    opt_b       resb 1
    opt_c       resb 1
    opt_E       resb 1
    opt_F       resb 1
    opt_H       resb 1
    opt_h       resb 1
    opt_I       resb 1
    opt_i       resb 1
    opt_L       resb 1
    opt_l       resb 1
    opt_n       resb 1
    opt_o       resb 1
    opt_q       resb 1
    opt_r       resb 1
    opt_R       resb 1
    opt_s       resb 1
    opt_v       resb 1
    opt_w       resb 1
    opt_x       resb 1
    opt_z       resb 1
    opt_Z       resb 1
    opt_color   resb 1
    color_arg   resq 1
    have_e      resb 1
    have_f      resb 1
    delim       resb 1
    found       resq 1
    tried       resq 1
    exitcode    resq 1
    curname     resq 1
    is_binary   resq 1
    barspending resq 1

    g_line      resq 1
    g_ulen      resq 1
    g_start     resq 1
    g_so        resq 1
    g_eo        resq 1
    g_mso       resq 1
    g_meo       resq 1
    g_rc        resq 1
    g_move      resq 1
    g_matched   resq 1
    g_dash      resb 1
    g_lcount    resq 1
    g_mcount    resq 1
    g_offset    resq 1
    g_after     resq 1
    g_before    resq 1
    g_new       resq 1
    g_rawlen    resq 1
    ctxw        resq 1
    ctx_head    resq 1
    dirbuf      resb DIRCAP
    rx_mso      resq 1
    rx_meo      resq 1
    rx_p        resq 1
    rx_group    resq 1
    rx_atstart  resq 1

section .data
    l_linebuf   db "line-buffered", 0
    l_color     db "color", 0
    l_excldir   db "exclude-dir", 0
    l_exclude   db "exclude", 0
    l_include   db "include", 0
    l_byteoff   db "byte-offset", 0
    l_nofile    db "no-filename", 0
    l_onlymatch db "only-matching", 0
    l_count     db "count", 0
    l_without   db "files-without-match", 0
    l_with      db "files-with-matches", 0
    l_quiet     db "quiet", 0
    l_silent    db "silent", 0
    s_auto      db "auto", 0
    s_stdin     db "(standard input)", 0
    s_dot       db ".", 0
    s_dash      db "-", 0
    s_bars      db "--", 10
    s_binary1   db "Binary file "
    s_binary1_l equ $ - s_binary1
    s_binary2   db " matches", 10
    s_binary2_l equ $ - s_binary2

    cls_alpha   db "alpha", 0
    cls_digit   db "digit", 0
    cls_alnum   db "alnum", 0
    cls_upper   db "upper", 0
    cls_lower   db "lower", 0
    cls_space   db "space", 0
    cls_blank   db "blank", 0
    cls_punct   db "punct", 0
    cls_print   db "print", 0
    cls_graph   db "graph", 0
    cls_cntrl   db "cntrl", 0
    cls_xdigit  db "xdigit", 0

    c_purple    db 27, "[35m", 0
    c_cyan      db 27, "[36m", 0
    c_red       db 27, "[1;31m", 0
    c_green     db 27, "[32m", 0
    c_grey      db 27, "[m", 0
    c_empty     db 0

e_usage     db "usage: grep [-abcEFHhIiLlnoqrsvwxZz] [-ABC NUM] [-m MAX] [-e REGEX]... [-f REGFILE]... [FILE]...", 10
    e_usage_len equ $ - e_usage
e_prefix    db "grep: "
    e_prefix_l  equ $ - e_prefix
e_noregex   db "grep: no REGEX", 10
    e_noregex_l equ $ - e_noregex
e_badregex  db "grep: bad regular expression", 10
    e_badregex_l equ $ - e_badregex
e_nofile    db ": No such file or directory", 10
    e_nofile_l  equ $ - e_nofile

section .text
global _start

_start:
    mov     r14, [rsp]                  ;argc
    lea     r15, [rsp + 8]              ;argv
    mov     qword [exitcode], 2
    mov     byte [delim], WHITESPACE_NL
    mov     r12, 1
.arg:
    cmp     r12, r14
    jae     .parsed
    mov     rbx, [r15 + r12 * 8]
    cmp     byte [rbx], '-'
    jne     .operand
    cmp     byte [rbx + 1], 0
    je      .operand
    cmp     byte [rbx + 1], '-'
    je      .longopt
    lea     rbx, [rbx + 1]
.flag:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .nextarg
    inc     rbx
    cmp     al, 'a'
    je      .f_a
    cmp     al, 'b'
    je      .f_b
    cmp     al, 'c'
    je      .f_c
    cmp     al, 'E'
    je      .f_E
    cmp     al, 'F'
    je      .f_F
    cmp     al, 'H'
    je      .f_H
    cmp     al, 'h'
    je      .f_h
    cmp     al, 'I'
    je      .f_I
    cmp     al, 'i'
    je      .f_i
    cmp     al, 'L'
    je      .f_L
    cmp     al, 'l'
    je      .f_l
    cmp     al, 'n'
    je      .f_n
    cmp     al, 'o'
    je      .f_o
    cmp     al, 'q'
    je      .f_q
    cmp     al, 'r'
    je      .f_r
    cmp     al, 'R'
    je      .f_R
    cmp     al, 's'
    je      .f_s
    cmp     al, 'v'
    je      .f_v
    cmp     al, 'w'
    je      .f_w
    cmp     al, 'x'
    je      .f_x
    cmp     al, 'z'
    je      .f_z
    cmp     al, 'Z'
    je      .f_Z
    cmp     al, 'e'
    je      .f_e
    cmp     al, 'f'
    je      .f_f
    cmp     al, 'A'
    je      .f_A
    cmp     al, 'B'
    je      .f_B
    cmp     al, 'C'
    je      .f_C
    cmp     al, 'm'
    je      .f_m
    cmp     al, 'S'
    je      .f_S
    cmp     al, 'M'
    je      .f_M
    jmp     usage_error
.f_a:
    mov     byte [opt_a], 1
    jmp     .flag
.f_b:
    mov     byte [opt_b], 1
    jmp     .flag
.f_c:
    mov     byte [opt_c], 1
    jmp     .flag
.f_E:
    mov     byte [opt_E], 1
    jmp     .flag
.f_F:
    mov     byte [opt_F], 1
    jmp     .flag
.f_H:
    mov     byte [opt_H], 1
    jmp     .flag
.f_h:
    mov     byte [opt_h], 1
    jmp     .flag
.f_I:
    mov     byte [opt_I], 1
    jmp     .flag
.f_i:
    mov     byte [opt_i], 1
    jmp     .flag
.f_L:
    mov     byte [opt_L], 1
    jmp     .flag
.f_l:
    mov     byte [opt_l], 1
    jmp     .flag
.f_n:
    mov     byte [opt_n], 1
    jmp     .flag
.f_o:
    mov     byte [opt_o], 1
    jmp     .flag
.f_q:
    mov     byte [opt_q], 1
    jmp     .flag
.f_r:
    mov     byte [opt_r], 1
    jmp     .flag
.f_R:
    mov     byte [opt_R], 1
    mov     byte [opt_r], 1
    jmp     .flag
.f_s:
    mov     byte [opt_s], 1
    jmp     .flag
.f_v:
    mov     byte [opt_v], 1
    jmp     .flag
.f_w:
    mov     byte [opt_w], 1
    jmp     .flag
.f_x:
    mov     byte [opt_x], 1
    jmp     .flag
.f_z:
    mov     byte [opt_z], 1
    jmp     .flag
.f_Z:
    mov     byte [opt_Z], 1
    jmp     .flag
.f_e:
    call    take_value
    mov     rdi, rax
    call    add_pattern_text
    mov     byte [have_e], 1
    jmp     .nextarg
.f_f:
    call    take_value
    mov     rdi, rax
    call    add_pattern_file
    mov     byte [have_f], 1
    jmp     .nextarg
.f_A:
    call    take_value
    mov     rdi, rax
    call    parse_number
    mov     [opt_A], rax
    mov     byte [have_A], 1
    jmp     .nextarg
.f_B:
    call    take_value
    mov     rdi, rax
    call    parse_number
    mov     [opt_B], rax
    mov     byte [have_B], 1
    jmp     .nextarg
.f_C:
    call    take_value
    mov     rdi, rax
    call    parse_number
    mov     [opt_C], rax
    mov     byte [have_C], 1
    jmp     .nextarg
.f_m:
    call    take_value
    mov     rdi, rax
    call    parse_number
    mov     [opt_m], rax
    mov     byte [have_m], 1
    jmp     .nextarg
.f_S:
    call    take_value
    mov     rcx, [excl_patcnt]
    mov     [excl_pat + rcx * 8], rax
    inc     qword [excl_patcnt]
    jmp     .nextarg
.f_M:
    call    take_value
    mov     rcx, [incl_patcnt]
    mov     [incl_pat + rcx * 8], rax
    inc     qword [incl_patcnt]
    jmp     .nextarg

.longopt:
    add     rbx, 2
    cmp     byte [rbx], 0
    je      .nextarg                    ;a bare -- ends the options
    mov     rdi, rbx
    mov     rsi, l_linebuf
    call    long_match
    test    al, al
    jnz     .nextarg
    mov     rdi, rbx
    mov     rsi, l_color
    call    long_match
    test    al, al
    jz      .l_excldir
    mov     byte [opt_color], 1
    mov     [color_arg], rdx
    jmp     .nextarg
.l_excldir:
    mov     rdi, rbx
    mov     rsi, l_excldir
    call    long_match
    test    al, al
    jz      .l_exclude
    call    long_value
    mov     rcx, [excl_dircnt]
    mov     [excl_dir + rcx * 8], rax
    inc     qword [excl_dircnt]
    jmp     .nextarg
.l_exclude:
    mov     rdi, rbx
    mov     rsi, l_exclude
    call    long_match
    test    al, al
    jz      .l_include
    call    long_value
    mov     rcx, [excl_patcnt]
    mov     [excl_pat + rcx * 8], rax
    inc     qword [excl_patcnt]
    jmp     .nextarg
.l_include:
    mov     rdi, rbx
    mov     rsi, l_include
    call    long_match
    test    al, al
    jz      .l_byteoff
    call    long_value
    mov     rcx, [incl_patcnt]
    mov     [incl_pat + rcx * 8], rax
    inc     qword [incl_patcnt]
    jmp     .nextarg
.l_byteoff:
    mov     rdi, rbx
    mov     rsi, l_byteoff
    call    long_match
    test    al, al
    jz      .l_nofile
    mov     byte [opt_b], 1
    jmp     .nextarg
.l_nofile:
    mov     rdi, rbx
    mov     rsi, l_nofile
    call    long_match
    test    al, al
    jz      .l_onlymatch
    mov     byte [opt_h], 1
    jmp     .nextarg
.l_onlymatch:
    mov     rdi, rbx
    mov     rsi, l_onlymatch
    call    long_match
    test    al, al
    jz      .l_count
    mov     byte [opt_o], 1
    jmp     .nextarg
.l_count:
    mov     rdi, rbx
    mov     rsi, l_count
    call    long_match
    test    al, al
    jz      .l_without
    mov     byte [opt_c], 1
    jmp     .nextarg
.l_without:
    mov     rdi, rbx
    mov     rsi, l_without
    call    long_match
    test    al, al
    jz      .l_with
    mov     byte [opt_L], 1
    jmp     .nextarg
.l_with:
    mov     rdi, rbx
    mov     rsi, l_with
    call    long_match
    test    al, al
    jz      .l_quiet
    mov     byte [opt_l], 1
    jmp     .nextarg
.l_quiet:
    mov     rdi, rbx
    mov     rsi, l_quiet
    call    long_match
    test    al, al
    jnz     .setquiet
    mov     rdi, rbx
    mov     rsi, l_silent
    call    long_match
    test    al, al
    jz      usage_error
.setquiet:
    mov     byte [opt_q], 1
    jmp     .nextarg

.operand:
    mov     rcx, [filecount]
    mov     [files + rcx * 8], rbx
    inc     qword [filecount]
.nextarg:
    inc     r12
    jmp     .arg

.parsed:
    call    run_grep
    mov     rdi, [exitcode]
    mov     rax, SYS_EXIT
    syscall

; take_value: the rest of this option bundle, or the argument after it.
take_value:
    cmp     byte [rbx], 0
    je      .separate
    mov     rax, rbx
    xor     rcx, rcx
.skip:
    cmp     byte [rbx], 0
    je      .out
    inc     rbx
    jmp     .skip
.separate:
    inc     r12
    cmp     r12, r14
    jae     usage_error
    mov     rax, [r15 + r12 * 8]
.out:
    ret

; long_match: does rdi start with the name rsi, ending there or at an equals
; sign? al says so, and rdx points past the equals sign when there is one.
long_match:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rsi + rcx]
    test    al, al
    jz      .ended
    cmp     al, [rdi + rcx]
    jne     .no
    inc     rcx
    jmp     .byte
.ended:
    movzx   eax, byte [rdi + rcx]
    test    al, al
    jz      .bare
    cmp     al, '='
    jne     .no
    lea     rdx, [rdi + rcx + 1]
    mov     al, 1
    ret
.bare:
    xor     rdx, rdx
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; long_value: the text after the equals sign, or the next argument.
long_value:
    test    rdx, rdx
    jnz     .have
    inc     r12
    cmp     r12, r14
    jae     usage_error
    mov     rdx, [r15 + r12 * 8]
.have:
    mov     rax, rdx
    ret

parse_number:
    xor     rax, rax
    xor     rcx, rcx
.digit:
    movzx   edx, byte [rdi + rcx]
    sub     dl, '0'
    cmp     dl, 9
    ja      .out
    imul    rax, rax, 10
    add     rax, rdx
    inc     rcx
    jmp     .digit
.out:
    ret

usage_error:
    call    out_flush
    write   STDERR_FILENO, e_usage, e_usage_len
    exit    2

; ---------------------------------------------------------------------------
; Collecting patterns. Both -e and -f split what they are given at newlines,
; so one -e can carry several patterns and an empty line in a -f file is a
; pattern that matches everything.
; ---------------------------------------------------------------------------

; add_pattern_text: the NUL terminated string at rdi, split at newlines.
add_pattern_text:
    push    rbx
    push    r12
    mov     rbx, rdi
    xor     r12, r12
.scan:
    movzx   eax, byte [rbx + r12]
    test    al, al
    jz      .last
    cmp     al, WHITESPACE_NL
    jne     .step
    lea     rdi, [rbx]
    mov     rsi, r12
    call    store_pattern
    lea     rbx, [rbx + r12 + 1]
    xor     r12, r12
    jmp     .scan
.step:
    inc     r12
    jmp     .scan
.last:
    mov     rdi, rbx
    mov     rsi, r12
    call    store_pattern
    pop     r12
    pop     rbx
    ret

; add_pattern_file: every line of a file is a pattern. An empty file adds
; nothing at all, which is what -f /dev/null means.
add_pattern_file:
    push    rbx
    push    r12
    push    r13
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .missing
    mov     r13, rax
    mov     rbx, pattext
    add     rbx, [pattextlen]
    mov     r12, rbx
.chunk:
    mov     rax, SYS_READ
    mov     rdi, r13
    mov     rsi, r12
    mov     rdx, 65536
    syscall
    test    rax, rax
    jle     .done
    add     r12, rax
    jmp     .chunk
.done:
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
    cmp     r12, rbx
    je      .out                        ;an empty file has no patterns at all
    cmp     byte [r12 - 1], WHITESPACE_NL
    jne     .terminate
    dec     r12
.terminate:
    mov     byte [r12], 0
    inc     r12
    sub     r12, pattext
    mov     [pattextlen], r12
    mov     rdi, rbx
    call    add_pattern_text
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret
.missing:
    call    out_flush
    write   STDERR_FILENO, e_usage, e_usage_len
    exit    2

; store_pattern: keep a copy of the rsi characters at rdi.
store_pattern:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
    mov     rbx, [pattextlen]
    lea     rdi, [pattext + rbx]
    mov     rsi, r12
    mov     rdx, r13
    call    copy_bytes
    lea     rax, [pattext + rbx]
    mov     byte [rax + r13], 0
    add     rbx, r13
    inc     rbx
    mov     [pattextlen], rbx
    mov     rcx, [patcount]
    mov     [pat_ptr + rcx * 8], rax
    mov     [pat_len + rcx * 8], r13
    mov     qword [pat_next + rcx * 8], -1
    inc     qword [patcount]
    pop     r13
    pop     r12
    pop     rbx
    ret

copy_bytes:
    test    rdx, rdx
    jz      .out
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rdx
    jmp     copy_bytes
.out:
    ret

; ---------------------------------------------------------------------------
; sort_patterns: a pattern that is a plain string -- letters, dots, anchors,
; backslashed punctuation -- is filed under its first literal character and
; matched directly. Anything with a bracket, a repeat, a group or an
; alternation in it is compiled instead.
; ---------------------------------------------------------------------------
sort_patterns:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rcx, 256
    xor     rax, rax
.clear:
    dec     rcx
    mov     [bucket + rcx * 8], rax
    test    rcx, rcx
    jnz     .clear
    mov     rcx, 256
.clearheads:
    dec     rcx
    mov     qword [bucket + rcx * 8], -1
    test    rcx, rcx
    jnz     .clearheads
    xor     r12, r12
.pattern:
    cmp     r12, [patcount]
    jae     .bucketed
    mov     rbx, [pat_ptr + r12 * 8]
    call    is_plain_pattern
    test    al, al
    jz      .compile
; a plain pattern: work out the character it is filed under
    xor     rcx, rcx
    cmp     byte [opt_F], 0
    jne     .havekey
    cmp     byte [rbx], '^'
    jne     .notcaret
    mov     rcx, 1
.notcaret:
    cmp     byte [rbx + rcx], '\'
    jne     .notescape
    inc     rcx
    jmp     .havekey
.notescape:
    cmp     byte [rbx + rcx], '$'
    jne     .havekey
    cmp     byte [rbx + rcx + 1], 0
    jne     .havekey
    inc     rcx
.havekey:
    movzx   eax, byte [rbx + rcx]
    cmp     byte [opt_i], 0
    je      .keyready
    call    upper_al
.keyready:
    mov     rdi, rax
    mov     rsi, r12
    call    bucket_insert
    inc     r12
    jmp     .pattern
.compile:
    mov     rdi, rbx
    call    regex_compile
    mov     rcx, [regexcount]
    mov     [regexes + rcx * 8], rax
    inc     qword [regexcount]
    inc     r12
    jmp     .pattern
.bucketed:
; every bucket ends with the patterns filed under nothing, which match
; wherever they are tried
    mov     r12, 1
.chain:
    cmp     r12, 256
    jae     .out
    mov     rax, [bucket + r12 * 8]
    cmp     rax, -1
    jne     .append
    mov     rax, [bucket]
    mov     [bucket + r12 * 8], rax
    inc     r12
    jmp     .chain
.append:
    mov     rcx, rax
.tail:
    mov     rdx, [pat_next + rcx * 8]
    cmp     rdx, -1
    je      .attach
    mov     rcx, rdx
    jmp     .tail
.attach:
    mov     rax, [bucket]
    mov     [pat_next + rcx * 8], rax
    inc     r12
    jmp     .chain
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; bucket_insert: put pattern rsi into bucket rdi, longest first so that the
; first pattern that fits is the longest one that could.
bucket_insert:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, [pat_len + r12 * 8]
    mov     rcx, [bucket + rbx * 8]
    cmp     rcx, -1
    je      .head
    mov     rax, [pat_len + rcx * 8]
    cmp     r13, rax
    ja      .head
.walk:
    mov     rdx, [pat_next + rcx * 8]
    cmp     rdx, -1
    je      .after
    mov     rax, [pat_len + rdx * 8]
    cmp     r13, rax
    ja      .after
    mov     rcx, rdx
    jmp     .walk
.after:
    mov     rax, [pat_next + rcx * 8]
    mov     [pat_next + r12 * 8], rax
    mov     [pat_next + rcx * 8], r12
    jmp     .out
.head:
    mov     rax, [bucket + rbx * 8]
    mov     [pat_next + r12 * 8], rax
    mov     [bucket + rbx * 8], r12
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; is_plain_pattern: al = 1 when the pattern at rbx can be matched directly.
is_plain_pattern:
    push    rbx
    push    r12
    cmp     byte [opt_F], 0
    jne     .plain
    cmp     byte [rbx], '.'
    je      .needsregex
    cmp     byte [rbx], '^'
    jne     .scan
    cmp     byte [rbx + 1], '$'
    jne     .scan
    cmp     byte [rbx + 2], 0
    je      .needsregex
.scan:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .plain
    cmp     al, '\'
    je      .escape
    call    is_regex_char
    test    al, al
    jnz     .needsregex
    inc     rbx
    jmp     .scan
.escape:
    movzx   eax, byte [rbx + 1]
    test    al, al
    jz      .needsregex
    call    is_special_char
    test    al, al
    jz      .needsregex
    movzx   eax, byte [rbx + 1]
    cmp     al, '('
    jne     .escapeok
    cmp     byte [opt_E], 0
    je      .needsregex
.escapeok:
    add     rbx, 2
    jmp     .scan
.plain:
    mov     al, 1
    pop     r12
    pop     rbx
    ret
.needsregex:
    xor     al, al
    pop     r12
    pop     rbx
    ret

; is_regex_char: the characters that a direct match cannot handle.
is_regex_char:
    cmp     al, '['
    je      .yes
    cmp     al, '('
    je      .yes
    cmp     al, ')'
    je      .yes
    cmp     al, '|'
    je      .yes
    cmp     al, '*'
    je      .yes
    cmp     al, '+'
    je      .yes
    cmp     al, '?'
    je      .yes
    cmp     al, '{'
    je      .yes
    xor     al, al
    ret
.yes:
    mov     al, 1
    ret

; is_special_char: the characters a backslash may stand in front of and
; still leave the pattern a plain one.
is_special_char:
    cmp     al, '\'
    je      .yes
    cmp     al, '.'
    je      .yes
    cmp     al, '^'
    je      .yes
    cmp     al, '$'
    je      .yes
    jmp     is_regex_char
.yes:
    mov     al, 1
    ret

upper_al:
    cmp     al, 'a'
    jb      .out
    cmp     al, 'z'
    ja      .out
    sub     al, 32
.out:
    ret

; ---------------------------------------------------------------------------
; Compiling a pattern. The result is a chain of nodes; a group becomes a
; start marker, the chain inside it, and an end marker, so that matching
; never has to look at the pattern text again.
; ---------------------------------------------------------------------------

; node_new: a node of type rdi. rax is its index.
node_new:
    mov     rax, [nodecount]
    test    rax, rax
    jnz     .allocate
    mov     rax, 1                      ;nought stands for no node at all
.allocate:
    lea     rcx, [rax + 1]
    mov     [nodecount], rcx
    imul    rcx, rax, ND_SIZE
    add     rcx, nodes
    mov     [rcx + ND_TYPE], rdi
    mov     qword [rcx + ND_A], 0
    mov     qword [rcx + ND_B], 0
    mov     qword [rcx + ND_C], 0
    mov     qword [rcx + ND_NEXT], 0
    ret

; node_at: rax points at node rdi.
node_at:
    imul    rax, rdi, ND_SIZE
    add     rax, nodes
    ret

; chain_tail: the last node of the chain starting at rdi.
chain_tail:
    mov     rax, rdi
.walk:
    imul    rcx, rax, ND_SIZE
    add     rcx, nodes
    mov     rdx, [rcx + ND_NEXT]
    test    rdx, rdx
    jz      .out
    mov     rax, rdx
    jmp     .walk
.out:
    ret

; regex_compile: rdi is the pattern text; rax is the head of its chain.
regex_compile:
    push    rbx
    mov     [rx_p], rdi
    mov     qword [rx_group], 1
    call    rx_alt
    mov     rcx, [rx_p]
    cmp     byte [rcx], 0
    jne     bad_regex
    pop     rbx
    ret

bad_regex:
    call    out_flush
    write   STDERR_FILENO, e_badregex, e_badregex_l
    exit    2

; rx_alt: one or more branches separated by a bar.
rx_alt:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8 * 64
    xor     r12, r12                    ;branches so far
.branch:
    call    rx_concat
    mov     [rsp + r12 * 8], rax
    inc     r12
    call    rx_at_bar
    test    al, al
    jz      .done
    call    rx_skip_bar
    cmp     r12, 64
    jae     bad_regex
    jmp     .branch
.done:
    cmp     r12, 1
    jne     .alternation
    mov     rax, [rsp]
    jmp     .out
.alternation:
    mov     r13, [altcount]
    xor     rcx, rcx
.copy:
    cmp     rcx, r12
    jae     .copied
    mov     rax, [rsp + rcx * 8]
    mov     rdx, r13
    add     rdx, rcx
    mov     [altlist + rdx * 8], rax
    inc     rcx
    jmp     .copy
.copied:
    add     rcx, r13
    mov     [altcount], rcx
    mov     rdi, N_ALT
    call    node_new
    mov     rbx, rax
    mov     rdi, rbx
    call    node_at
    mov     [rax + ND_A], r13
    mov     [rax + ND_B], r12
    mov     rax, rbx
.out:
    add     rsp, 8 * 64
    pop     r13
    pop     r12
    pop     rbx
    ret

; rx_concat: pieces one after another until a bar, a closing bracket or the
; end of the pattern.
rx_concat:
    push    rbx
    push    r12
    xor     rbx, rbx                    ;head
    xor     r12, r12                    ;tail
    mov     qword [rx_atstart], 1
.piece:
    mov     rcx, [rx_p]
    cmp     byte [rcx], 0
    je      .out
    call    rx_at_bar
    test    al, al
    jnz     .out
    call    rx_at_close
    test    al, al
    jnz     .out
    call    rx_repeat
    mov     qword [rx_atstart], 0
    test    rax, rax
    jz      .piece
    test    rbx, rbx
    jnz     .link
    mov     rbx, rax
    mov     rdi, rax
    call    chain_tail
    mov     r12, rax
    jmp     .piece
.link:
    push    rax
    mov     rdi, r12
    call    node_at
    mov     rcx, [rsp]
    mov     [rax + ND_NEXT], rcx
    pop     rdi
    call    chain_tail
    mov     r12, rax
    jmp     .piece
.out:
    mov     rax, rbx
    pop     r12
    pop     rbx
    ret

; rx_repeat: an atom, and whatever repeat markers follow it.
rx_repeat:
    push    rbx
    push    r12
    push    r13
    call    rx_atom
    mov     rbx, rax
    test    rbx, rbx
    jz      .out
.more:
    call    rx_repeat_kind              ;-> al kind, and the cursor moved on
    test    al, al
    jz      .out
    cmp     al, 1
    je      .star
    cmp     al, 2
    je      .plus
    cmp     al, 3
    je      .question
    call    rx_interval                 ;-> rax min, rdx max
    mov     r12, rax
    mov     r13, rdx
    jmp     .wrap
.star:
    xor     r12, r12
    mov     r13, -1
    jmp     .wrap
.plus:
    mov     r12, 1
    mov     r13, -1
    jmp     .wrap
.question:
    xor     r12, r12
    mov     r13, 1
.wrap:
    mov     rdi, N_REP
    call    node_new
    push    rax
    mov     rdi, rax
    call    node_at
    mov     [rax + ND_A], rbx
    mov     [rax + ND_B], r12
    mov     [rax + ND_C], r13
    pop     rbx
    jmp     .more
.out:
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

; rx_repeat_kind: al is 0 for none, 1 star, 2 plus, 3 question, 4 interval.
rx_repeat_kind:
    mov     rcx, [rx_p]
    movzx   eax, byte [rcx]
    cmp     al, '*'
    je      .star
    cmp     byte [opt_E], 0
    jne     .extended
    cmp     al, '\'
    jne     .none
    movzx   eax, byte [rcx + 1]
    cmp     al, '+'
    je      .escplus
    cmp     al, '?'
    je      .escquestion
    cmp     al, '{'
    je      .escbrace
    jmp     .none
.escplus:
    add     qword [rx_p], 2
    mov     al, 2
    ret
.escquestion:
    add     qword [rx_p], 2
    mov     al, 3
    ret
.escbrace:
    add     qword [rx_p], 2
    mov     al, 4
    ret
.extended:
    cmp     al, '+'
    je      .plus
    cmp     al, '?'
    je      .question
    cmp     al, '{'
    je      .brace
    jmp     .none
.star:
    inc     qword [rx_p]
    mov     al, 1
    ret
.plus:
    inc     qword [rx_p]
    mov     al, 2
    ret
.question:
    inc     qword [rx_p]
    mov     al, 3
    ret
.brace:
    inc     qword [rx_p]
    mov     al, 4
    ret
.none:
    xor     al, al
    ret

; rx_interval: the counts inside braces. rax is the least, rdx the most, or
; minus one when there is no limit.
rx_interval:
    push    rbx
    push    r12
    mov     rbx, [rx_p]
    xor     r12, r12
.mindigit:
    movzx   eax, byte [rbx]
    sub     al, '0'
    cmp     al, 9
    ja      .mindone
    imul    r12, r12, 10
    movzx   ecx, al
    add     r12, rcx
    inc     rbx
    jmp     .mindigit
.mindone:
    mov     rdx, r12
    cmp     byte [rbx], ','
    jne     .close
    inc     rbx
    movzx   eax, byte [rbx]
    sub     al, '0'
    cmp     al, 9
    jbe     .maxdigits
    mov     rdx, -1
    jmp     .close
.maxdigits:
    xor     rdx, rdx
.maxdigit:
    movzx   eax, byte [rbx]
    sub     al, '0'
    cmp     al, 9
    ja      .close
    imul    rdx, rdx, 10
    movzx   ecx, al
    add     rdx, rcx
    inc     rbx
    jmp     .maxdigit
.close:
    cmp     byte [opt_E], 0
    jne     .plainclose
    cmp     byte [rbx], '\'
    jne     bad_regex
    cmp     byte [rbx + 1], '}'
    jne     bad_regex
    add     rbx, 2
    jmp     .stored
.plainclose:
    cmp     byte [rbx], '}'
    jne     bad_regex
    inc     rbx
.stored:
    mov     [rx_p], rbx
    mov     rax, r12
    pop     r12
    pop     rbx
    ret

; rx_at_bar: al = 1 when the cursor sits on an alternation marker.
rx_at_bar:
    mov     rcx, [rx_p]
    cmp     byte [opt_E], 0
    je      .basic
    cmp     byte [rcx], '|'
    je      .yes
    jmp     .no
.basic:
    cmp     byte [rcx], '\'
    jne     .no
    cmp     byte [rcx + 1], '|'
    je      .yes
.no:
    xor     al, al
    ret
.yes:
    mov     al, 1
    ret

rx_skip_bar:
    cmp     byte [opt_E], 0
    je      .basic
    inc     qword [rx_p]
    ret
.basic:
    add     qword [rx_p], 2
    ret

; rx_at_close: al = 1 when the cursor sits on a closing group marker.
rx_at_close:
    mov     rcx, [rx_p]
    cmp     byte [opt_E], 0
    je      .basic
    cmp     byte [rcx], ')'
    je      .yes
    jmp     .no
.basic:
    cmp     byte [rcx], '\'
    jne     .no
    cmp     byte [rcx + 1], ')'
    je      .yes
.no:
    xor     al, al
    ret
.yes:
    mov     al, 1
    ret

; ---------------------------------------------------------------------------
; rx_atom: one piece of a pattern.
; ---------------------------------------------------------------------------
rx_atom:
    push    rbx
    push    r12
    push    r13
    mov     rbx, [rx_p]
    movzx   eax, byte [rbx]
    test    al, al
    jz      .none
    cmp     al, '.'
    je      .any
    cmp     al, '['
    je      .bracket
    cmp     al, '^'
    je      .caret
    cmp     al, '$'
    je      .dollar
    cmp     al, '\'
    je      .escape
    cmp     byte [opt_E], 0
    je      .literal
    cmp     al, '('
    je      .group
.literal:
    inc     qword [rx_p]
    mov     rdi, N_CHAR
    call    node_new
    push    rax
    mov     rdi, rax
    call    node_at
    movzx   ecx, byte [rbx]
    cmp     byte [opt_i], 0
    je      .storechar
    push    rax
    mov     al, cl
    call    upper_al
    movzx   ecx, al
    pop     rax
.storechar:
    mov     [rax + ND_A], rcx
    pop     rax
    jmp     .out
.any:
    inc     qword [rx_p]
    mov     rdi, N_ANY
    call    node_new
    jmp     .out
.bracket:
    call    rx_bracket                  ;-> rax = which set of bytes
    mov     r12, rax
    mov     rdi, N_CLASS
    call    node_new
    mov     r13, rax
    mov     rdi, rax
    call    node_at
    mov     [rax + ND_A], r12
    mov     rax, r13
    jmp     .out
.caret:
    cmp     byte [opt_E], 0
    jne     .isanchor
    cmp     qword [rx_atstart], 0
    je      .literal
.isanchor:
    inc     qword [rx_p]
    mov     rdi, N_BOL
    call    node_new
    jmp     .out
.dollar:
    cmp     byte [opt_E], 0
    jne     .isend
    cmp     byte [rbx + 1], 0
    je      .isend
    push    rbx
    inc     qword [rx_p]
    call    rx_at_bar
    mov     r12b, al
    call    rx_at_close
    or      al, r12b
    pop     rbx
    dec     qword [rx_p]
    test    al, al
    jz      .literal
.isend:
    inc     qword [rx_p]
    mov     rdi, N_EOL
    call    node_new
    jmp     .out
.group:
    inc     qword [rx_p]
    jmp     .groupbody
.escape:
    movzx   eax, byte [rbx + 1]
    test    al, al
    jz      .literal
    cmp     al, '1'
    jb      .escother
    cmp     al, '9'
    ja      .escother
    add     qword [rx_p], 2
    mov     rdi, N_BACKREF
    call    node_new
    push    rax
    mov     rdi, rax
    call    node_at
    movzx   ecx, byte [rbx + 1]
    sub     rcx, '0'
    mov     [rax + ND_A], rcx
    pop     rax
    jmp     .out
.escother:
    cmp     byte [opt_E], 0
    jne     .escliteral
    cmp     al, '('
    jne     .escliteral
    add     qword [rx_p], 2
    jmp     .groupbody
.escliteral:
    inc     rbx
    add     qword [rx_p], 2
    mov     rdi, N_CHAR
    call    node_new
    push    rax
    mov     rdi, rax
    call    node_at
    movzx   ecx, byte [rbx]
    cmp     byte [opt_i], 0
    je      .storeesc
    push    rax
    mov     al, cl
    call    upper_al
    movzx   ecx, al
    pop     rax
.storeesc:
    mov     [rax + ND_A], rcx
    pop     rax
    jmp     .out

.groupbody:
    mov     r13, [rx_group]
    inc     qword [rx_group]
    mov     rdi, N_GSTART
    call    node_new
    mov     rbx, rax
    mov     rdi, rbx
    call    node_at
    mov     [rax + ND_A], r13
    call    rx_alt
    mov     r12, rax                    ;the chain inside the group
    call    rx_at_close
    test    al, al
    jz      bad_regex
    call    rx_skip_close
    mov     rdi, N_GEND
    call    node_new
    push    rax
    mov     rdi, rax
    call    node_at
    mov     [rax + ND_A], r13
    pop     r13                         ;the end marker
    test    r12, r12
    jnz     .joinbody
    mov     rdi, rbx
    call    node_at
    mov     [rax + ND_NEXT], r13
    jmp     .grouped
.joinbody:
    mov     rdi, rbx
    call    node_at
    mov     [rax + ND_NEXT], r12
    mov     rdi, r12
    call    chain_tail
    mov     rdi, rax
    call    node_at
    mov     [rax + ND_NEXT], r13
.grouped:
    mov     rax, rbx
    jmp     .out
.none:
    xor     rax, rax
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

rx_skip_close:
    cmp     byte [opt_E], 0
    je      .basic
    inc     qword [rx_p]
    ret
.basic:
    add     qword [rx_p], 2
    ret


; ---------------------------------------------------------------------------
; rx_bracket: a bracket expression, kept as a bitmap of the bytes it accepts,
; so that matching one is a single bit test.
; ---------------------------------------------------------------------------
rx_bracket:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r14, [classcount]
    inc     qword [classcount]
    imul    rdi, r14, 32
    add     rdi, classes
    mov     rsi, 32
    call    zero_bytes
    mov     rbx, [rx_p]
    inc     rbx
    xor     r13, r13                    ;whether the set is turned inside out
    cmp     byte [rbx], '^'
    jne     .nonegate
    mov     r13, 1
    inc     rbx
.nonegate:
    xor     r12, r12                    ;items taken so far
.item:
    movzx   eax, byte [rbx]
    test    al, al
    jz      bad_regex
    cmp     al, ']'
    jne     .notclose
    test    r12, r12
    jnz     .close
.notclose:
    cmp     al, '['
    jne     .plain
    movzx   eax, byte [rbx + 1]
cmp     al, ':'
    je      .named
    cmp     al, '='
    je      .bracketed
    cmp     al, '.'
    je      .bracketed
.plain:
; a range needs a dash with something other than the closing bracket after it
    cmp     byte [rbx + 1], '-'
    jne     .single
    movzx   eax, byte [rbx + 2]
    test    al, al
    jz      .single
    cmp     al, ']'
    je      .single
    movzx   edi, byte [rbx]
    movzx   esi, byte [rbx + 2]
    mov     rdx, r14
    call    class_add_range
    add     rbx, 3
    inc     r12
    jmp     .item
.single:
    movzx   edi, byte [rbx]
    mov     rsi, rdi
    mov     rdx, r14
    call    class_add_range
    inc     rbx
    inc     r12
    jmp     .item
.bracketed:
; [=x=] and [.x.] stand for the single character between the markers
    movzx   edi, byte [rbx + 2]
    mov     rsi, rdi
    mov     rdx, r14
    call    class_add_range
    add     rbx, 5
    inc     r12
    jmp     .item
.named:
    lea     rdi, [rbx + 2]
    mov     rsi, r14
    call    class_add_named             ;-> rax = characters consumed
    add     rbx, rax
    inc     r12
    jmp     .item
.close:
    inc     rbx
    mov     [rx_p], rbx
    test    r13, r13
    jz      .done
    imul    rcx, r14, 32
    add     rcx, classes
    xor     rdx, rdx
.invert:
    cmp     rdx, 32
    jae     .done
    not     byte [rcx + rdx]
    inc     rdx
    jmp     .invert
.done:
    mov     rax, r14
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; class_add_range: the bytes rdi through rsi join set rdx, and their other
; case with them when the match is to ignore case.
class_add_range:
    push    rbx
    imul    rbx, rdx, 32
    add     rbx, classes
    mov     rcx, rdi
.byte:
    cmp     rcx, rsi
    ja      .out
    mov     rax, rcx
    call    class_set_bit
    cmp     byte [opt_i], 0
    je      .next
    mov     rax, rcx
    cmp     al, 'a'
    jb      .upper
    cmp     al, 'z'
    ja      .next
    sub     al, 32
    call    class_set_bit
    jmp     .next
.upper:
    cmp     al, 'A'
    jb      .next
    cmp     al, 'Z'
    ja      .next
    add     al, 32
    call    class_set_bit
.next:
    inc     rcx
    jmp     .byte
.out:
    pop     rbx
    ret

; class_set_bit: byte al joins the set whose bitmap starts at rbx.
class_set_bit:
    push    rcx
    push    rdx
    movzx   eax, al
    mov     rdx, rax
    shr     rdx, 3
    and     rax, 7
    mov     cl, al
    mov     al, 1
    shl     al, cl
    or      [rbx + rdx], al
    pop     rdx
    pop     rcx
    ret

; class_add_named: the named class at rdi joins set rsi. rax is how many
; characters of the pattern it took, counting the brackets and colons.
class_add_named:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    imul    rbx, rsi, 32
    add     rbx, classes
    xor     r13, r13
.len:
    movzx   eax, byte [r12 + r13]
cmp     al, ':'
    je      .named
    test    al, al
    jz      bad_regex
    inc     r13
    jmp     .len
.named:
    xor     r14, r14                    ;the byte being considered
.byte:
    cmp     r14, 256
    jae     .done
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    call    in_named_class
    test    al, al
    jz      .nextbyte
    mov     rax, r14
    call    class_set_bit
.nextbyte:
    inc     r14
    jmp     .byte
.done:
lea     rax, [r13 + 4]              ;"[:" name ":]"
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; in_named_class: does byte rdx belong to the class named by the rsi
; characters at rdi?
in_named_class:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, rbx
    mov     rsi, r12
    mov     rcx, cls_alpha
    call    name_is
    test    al, al
    jnz     .alpha
    mov     rcx, cls_digit
    call    name_is
    test    al, al
    jnz     .digit
    mov     rcx, cls_alnum
    call    name_is
    test    al, al
    jnz     .alnum
    mov     rcx, cls_upper
    call    name_is
    test    al, al
    jnz     .upper
    mov     rcx, cls_lower
    call    name_is
    test    al, al
    jnz     .lower
    mov     rcx, cls_space
    call    name_is
    test    al, al
    jnz     .space
    mov     rcx, cls_blank
    call    name_is
    test    al, al
    jnz     .blank
    mov     rcx, cls_punct
    call    name_is
    test    al, al
    jnz     .punct
    mov     rcx, cls_print
    call    name_is
    test    al, al
    jnz     .print
    mov     rcx, cls_graph
    call    name_is
    test    al, al
    jnz     .graph
    mov     rcx, cls_cntrl
    call    name_is
    test    al, al
    jnz     .cntrl
    mov     rcx, cls_xdigit
    call    name_is
    test    al, al
    jnz     .xdigit
    jmp     .no
.alpha:
    call    is_alpha_dl
    jmp     .out
.digit:
    call    is_digit_dl
    jmp     .out
.alnum:
    call    is_alpha_dl
    test    al, al
    jnz     .out
    call    is_digit_dl
    jmp     .out
.upper:
    xor     al, al
    cmp     dl, 'A'
    jb      .out
    cmp     dl, 'Z'
    ja      .out
    mov     al, 1
    jmp     .out
.lower:
    xor     al, al
    cmp     dl, 'a'
    jb      .out
    cmp     dl, 'z'
    ja      .out
    mov     al, 1
    jmp     .out
.space:
    xor     al, al
    cmp     dl, WHITESPACE_SPACE
    je      .yes
    cmp     dl, 9
    jb      .out
    cmp     dl, 13
    jbe     .yes
    jmp     .out
.blank:
    xor     al, al
    cmp     dl, WHITESPACE_SPACE
    je      .yes
    cmp     dl, 9
    je      .yes
    jmp     .out
.punct:
    xor     al, al
    cmp     dl, 33
    jb      .out
    cmp     dl, 126
    ja      .out
    call    is_alpha_dl
    test    al, al
    jnz     .no
    call    is_digit_dl
    test    al, al
    jnz     .no
    mov     al, 1
    jmp     .out
.print:
    xor     al, al
    cmp     dl, 32
    jb      .out
    cmp     dl, 126
    ja      .out
    mov     al, 1
    jmp     .out
.graph:
    xor     al, al
    cmp     dl, 33
    jb      .out
    cmp     dl, 126
    ja      .out
    mov     al, 1
    jmp     .out
.cntrl:
    xor     al, al
    cmp     dl, 32
    jb      .yes
    cmp     dl, 127
    je      .yes
    jmp     .out
.xdigit:
    call    is_digit_dl
    test    al, al
    jnz     .out
    xor     al, al
    cmp     dl, 'a'
    jb      .xupper
    cmp     dl, 'f'
    jbe     .yes
    jmp     .out
.xupper:
    cmp     dl, 'A'
    jb      .out
    cmp     dl, 'F'
    jbe     .yes
    jmp     .out
.yes:
    mov     al, 1
    jmp     .out
.no:
    xor     al, al
.out:
    pop     r12
    pop     rbx
    ret

is_alpha_dl:
    xor     al, al
    cmp     dl, 'A'
    jb      .out
    cmp     dl, 'Z'
    jbe     .yes
    cmp     dl, 'a'
    jb      .out
    cmp     dl, 'z'
    ja      .out
.yes:
    mov     al, 1
.out:
    ret

is_digit_dl:
    xor     al, al
    cmp     dl, '0'
    jb      .out
    cmp     dl, '9'
    ja      .out
    mov     al, 1
.out:
    ret

; name_is: al = 1 when the rsi characters at rdi are exactly the name at rcx.
name_is:
    push    rbx
    xor     rbx, rbx
.byte:
    movzx   eax, byte [rcx + rbx]
    test    al, al
    jz      .ended
    cmp     rbx, rsi
    jae     .no
    cmp     al, [rdi + rbx]
    jne     .no
    inc     rbx
    jmp     .byte
.ended:
    cmp     rbx, rsi
    jne     .no
    mov     al, 1
    pop     rbx
    ret
.no:
    xor     al, al
    pop     rbx
    ret

zero_bytes:
    test    rsi, rsi
    jz      .out
    mov     byte [rdi], 0
    inc     rdi
    dec     rsi
    jmp     zero_bytes
.out:
    ret

; ---------------------------------------------------------------------------
; Matching a compiled pattern. Every way the pattern could fit is tried and
; the longest kept, because POSIX asks for the longest match rather than the
; first one found. What is left to do after the piece in hand is carried as
; a continuation, which is how a group or a repeat knows where to go once its
; own contents have matched.
; ---------------------------------------------------------------------------

; regex_exec: pattern rdi against the rdx characters at rsi, with rcx saying
; whether the start of that text is really the start of a line.
;   al = 1 on a match, with rx_mso and rx_meo bracketing it.
regex_exec:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     [m_text], rsi
    mov     [m_len], rdx
    mov     [m_notbol], rcx
    xor     r12, r12
.start:
    cmp     r12, [m_len]
    ja      .nomatch
    mov     qword [conttop], 0
    mov     qword [have_best], 0
    mov     qword [best_end], -1
    mov     rcx, MAXGROUPS
.clear:
    dec     rcx
    mov     qword [cap_s + rcx * 8], -1
    mov     qword [cap_e + rcx * 8], -1
    test    rcx, rcx
    jnz     .clear
    mov     [m_start], r12
    mov     rdi, rbx
    mov     rsi, r12
    xor     rdx, rdx
    call    rx_match
    cmp     qword [have_best], 0
    jne     .found
    inc     r12
    jmp     .start
.found:
    mov     [rx_mso], r12
    mov     rax, [best_end]
    mov     [rx_meo], rax
    mov     al, 1
    pop     r13
    pop     r12
    pop     rbx
    ret
.nomatch:
    xor     al, al
    pop     r13
    pop     r12
    pop     rbx
    ret

; cont_push: record that rdi is still to be done afterwards. rax is the new
; continuation, rsi its parent.
cont_push:
    mov     rax, [conttop]
    cmp     rax, MAXCONTS
    jae     bad_regex
    inc     qword [conttop]
    imul    rax, rax, CT_SIZE
    add     rax, conts
    mov     qword [rax + CT_KIND], 0
    mov     [rax + CT_NODE], rdi
    mov     [rax + CT_PARENT], rsi
    ret

; cont_push_rep: record that a repeat has one more turn available.
;   rdi = the repeat, rsi = parent, rdx = turns taken, rcx = where this turn
;   began
cont_push_rep:
    mov     rax, [conttop]
    cmp     rax, MAXCONTS
    jae     bad_regex
    inc     qword [conttop]
    imul    rax, rax, CT_SIZE
    add     rax, conts
    mov     qword [rax + CT_KIND], 1
    mov     [rax + CT_NODE], rdi
    mov     [rax + CT_PARENT], rsi
    mov     [rax + CT_COUNT], rdx
    mov     [rax + CT_START], rcx
    ret

; rx_match: work through the chain at rdi from position rsi, with rdx left
; to do afterwards.
rx_match:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
.step:
    test    rbx, rbx
    jz      .chainend
    imul    r14, rbx, ND_SIZE
    add     r14, nodes
    mov     rax, [r14 + ND_TYPE]
    cmp     rax, N_CHAR
    je      .char
    cmp     rax, N_ANY
    je      .any
    cmp     rax, N_CLASS
    je      .class
    cmp     rax, N_BOL
    je      .bol
    cmp     rax, N_EOL
    je      .eol
    cmp     rax, N_GSTART
    je      .gstart
    cmp     rax, N_GEND
    je      .gend
    cmp     rax, N_BACKREF
    je      .backref
    cmp     rax, N_ALT
    je      .alt
    jmp     .rep

.char:
    cmp     r12, [m_len]
    jae     .out
    mov     rax, [m_text]
    movzx   eax, byte [rax + r12]
    cmp     byte [opt_i], 0
    je      .charcmp
    call    upper_al
    movzx   eax, al
.charcmp:
    cmp     rax, [r14 + ND_A]
    jne     .out
    inc     r12
    mov     rbx, [r14 + ND_NEXT]
    jmp     .step
.any:
    cmp     r12, [m_len]
    jae     .out
    inc     r12
    mov     rbx, [r14 + ND_NEXT]
    jmp     .step
.class:
    cmp     r12, [m_len]
    jae     .out
    mov     rax, [m_text]
    movzx   eax, byte [rax + r12]
    mov     rcx, [r14 + ND_A]
    imul    rcx, rcx, 32
    add     rcx, classes
    mov     rdx, rax
    shr     rdx, 3
    and     rax, 7
    movzx   esi, byte [rcx + rdx]
    mov     rcx, rax
    shr     rsi, cl
    test    rsi, 1
    jz      .out
    inc     r12
    mov     rbx, [r14 + ND_NEXT]
    jmp     .step
.bol:
    test    r12, r12
    jnz     .out
    cmp     qword [m_notbol], 0
    jne     .out
    mov     rbx, [r14 + ND_NEXT]
    jmp     .step
.eol:
    cmp     r12, [m_len]
    jne     .out
    mov     rbx, [r14 + ND_NEXT]
    jmp     .step
.gstart:
    mov     r15, [r14 + ND_A]
    mov     rax, [cap_s + r15 * 8]
    push    rax
    mov     [cap_s + r15 * 8], r12
    mov     rdi, [r14 + ND_NEXT]
    mov     rsi, r12
    mov     rdx, r13
    call    rx_match
    pop     rax
    mov     [cap_s + r15 * 8], rax
    jmp     .out
.gend:
    mov     r15, [r14 + ND_A]
    mov     rax, [cap_e + r15 * 8]
    push    rax
    mov     [cap_e + r15 * 8], r12
    mov     rdi, [r14 + ND_NEXT]
    mov     rsi, r12
    mov     rdx, r13
    call    rx_match
    pop     rax
    mov     [cap_e + r15 * 8], rax
    jmp     .out
.backref:
    mov     r15, [r14 + ND_A]
    mov     rax, [cap_s + r15 * 8]
    cmp     rax, 0
    jl      .out
    mov     rcx, [cap_e + r15 * 8]
    cmp     rcx, 0
    jl      .out
    sub     rcx, rax                    ;how long the earlier text was
    mov     rdx, r12
    add     rdx, rcx
    cmp     rdx, [m_len]
    ja      .out
    mov     rsi, [m_text]
    xor     rdx, rdx
.refbyte:
    cmp     rdx, rcx
    jae     .refok
    push    rax
    mov     rdi, rax
    add     rdi, rdx
    movzx   eax, byte [rsi + rdi]
    cmp     byte [opt_i], 0
    je      .refleft
    call    upper_al
.refleft:
    mov     rdi, rax
    mov     rax, r12
    add     rax, rdx
    movzx   eax, byte [rsi + rax]
    cmp     byte [opt_i], 0
    je      .refcmp
    call    upper_al
.refcmp:
    cmp     al, dil
    pop     rax
    jne     .out
    inc     rdx
    jmp     .refbyte
.refok:
    add     r12, rcx
    mov     rbx, [r14 + ND_NEXT]
    jmp     .step
.alt:
    mov     rax, [conttop]
    push    rax
    mov     rdi, [r14 + ND_NEXT]
    mov     rsi, r13
    call    cont_push
    mov     r15, rax
    mov     rcx, [r14 + ND_A]
    push    rcx
    xor     rcx, rcx
    push    rcx
.altbranch:
    mov     rcx, [rsp]
    cmp     rcx, [r14 + ND_B]
    jae     .altdone
    mov     rdx, [rsp + 8]
    add     rdx, rcx
    mov     rdi, [altlist + rdx * 8]
    mov     rsi, r12
    mov     rdx, r15
    call    rx_match
    inc     qword [rsp]
    jmp     .altbranch
.altdone:
    add     rsp, 16
    pop     rax
    mov     [conttop], rax
    jmp     .out
.rep:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    xor     rcx, rcx
    call    rep_enter
    jmp     .out
.chainend:
    mov     rdi, r13
    mov     rsi, r12
    call    follow_cont
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; rep_enter: a repeat at rdi from rsi, with rdx to do afterwards and rcx
; turns already taken.
rep_enter:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r15, rcx
    imul    r14, rbx, ND_SIZE
    add     r14, nodes
    mov     rax, [r14 + ND_C]
    cmp     rax, -1
    je      .again
    cmp     r15, rax
    jae     .enough
.again:
    mov     rax, [conttop]
    push    rax
    mov     rdi, rbx
    mov     rsi, r13
    lea     rdx, [r15 + 1]
    mov     rcx, r12
    call    cont_push_rep
    mov     rdx, rax
    mov     rdi, [r14 + ND_A]
    mov     rsi, r12
    call    rx_match
    pop     rax
    mov     [conttop], rax
.enough:
    cmp     r15, [r14 + ND_B]
    jb      .out
    mov     rdi, [r14 + ND_NEXT]
    mov     rsi, r12
    mov     rdx, r13
    call    rx_match
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; follow_cont: nothing is left of the piece in hand, so pick up whatever was
; put aside.
follow_cont:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    test    rbx, rbx
    jz      .whole
    cmp     qword [rbx + CT_KIND], 0
    jne     .repeat
    mov     rdi, [rbx + CT_NODE]
    mov     rsi, r12
    mov     rdx, [rbx + CT_PARENT]
    call    rx_match
    jmp     .out
.repeat:
    mov     rax, [rbx + CT_START]
    cmp     rax, r12
    jne     .keepgoing
; the body matched nothing, so going round again would never end
    mov     r13, [rbx + CT_NODE]
    imul    rax, r13, ND_SIZE
    add     rax, nodes
    mov     rcx, [rbx + CT_COUNT]
    cmp     rcx, [rax + ND_B]
    jb      .out
    mov     rdi, [rax + ND_NEXT]
    mov     rsi, r12
    mov     rdx, [rbx + CT_PARENT]
    call    rx_match
    jmp     .out
.keepgoing:
    mov     rdi, [rbx + CT_NODE]
    mov     rsi, r12
    mov     rdx, [rbx + CT_PARENT]
    mov     rcx, [rbx + CT_COUNT]
    call    rep_enter
    jmp     .out
.whole:
; the whole pattern fitted; keep it when it reaches further than any before
    cmp     qword [have_best], 0
    je      .better
    cmp     r12, [best_end]
    jbe     .out
.better:
    mov     [best_end], r12
    mov     qword [have_best], 1
    mov     rcx, MAXGROUPS
.save:
    dec     rcx
    mov     rax, [cap_s + rcx * 8]
    mov     [best_s + rcx * 8], rax
    mov     rax, [cap_e + rcx * 8]
    mov     [best_e + rcx * 8], rax
    test    rcx, rcx
    jnz     .save
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; The direct match. A plain pattern is filed under its first literal
; character, so at each position only the patterns that could possibly start
; there are tried, longest first.
;
; The pattern cursor moves on its own: a backslash steps it forward so that
; the character after it is compared, while the position in the line keeps
; counting from where the match began.
; ---------------------------------------------------------------------------

; fast_match: look for a plain pattern in the line from g_start onwards.
;   al = 1 on a match, with g_so and g_eo bracketing it, measured from
;   g_start.
fast_match:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    cmp     qword [patcount], 0
    je      .nomatch
    mov     r12, [g_start]              ;the position being tried
.position:
    mov     rax, [g_ulen]
    cmp     r12, rax
    ja      .nomatch
    mov     rcx, [g_line]
    movzx   eax, byte [rcx + r12]
    cmp     r12, [g_ulen]
    jne     .havechar
    xor     eax, eax                    ;past the end, nothing stands there
.havechar:
    cmp     byte [opt_i], 0
    je      .keyready
    call    upper_al
    movzx   eax, al
.keyready:
    mov     r13, [bucket + rax * 8]
.pattern:
    cmp     r13, -1
    je      .nextposition
    mov     rbx, [pat_ptr + r13 * 8]
    cmp     byte [opt_F], 0
    jne     .nocaret
    cmp     byte [rbx], '^'
    jne     .nocaret
    cmp     r12, [g_start]
    jne     .nextpattern
    inc     rbx
.nocaret:
    xor     r14, r14                    ;characters matched so far
.compare:
    movzx   eax, byte [rbx + r14]
    test    al, al
    jz      .ended
    mov     rcx, r12
    add     rcx, r14
    cmp     rcx, [g_ulen]
    jae     .ended
    cmp     byte [opt_F], 0
    jne     .literal
    cmp     al, '.'
    je      .anychar
    cmp     al, '\'
    jne     .maybedollar
    cmp     byte [rbx + r14 + 1], 0
    je      .literal
    inc     rbx
    jmp     .literal
.maybedollar:
    cmp     al, '$'
    jne     .literal
    cmp     byte [rbx + r14 + 1], 0
    je      .ended
.literal:
    movzx   eax, byte [rbx + r14]
    mov     rcx, [g_line]
    mov     rdx, r12
    add     rdx, r14
    movzx   ecx, byte [rcx + rdx]
    cmp     byte [opt_i], 0
    je      .compareraw
    push    rcx
    call    upper_al
    pop     rcx
    push    rax
    mov     al, cl
    call    upper_al
    mov     rcx, rax
    pop     rax
.compareraw:
    cmp     al, cl
    jne     .nextpattern
.anychar:
    inc     r14
    jmp     .compare
.ended:
; the pattern is spent, unless what is left of it is a trailing dollar
; standing at the end of the line
    movzx   eax, byte [rbx + r14]
    test    al, al
    jz      .matched
    cmp     al, '$'
    jne     .nextpattern
    cmp     byte [rbx + r14 + 1], 0
    jne     .nextpattern
    mov     rcx, r12
    add     rcx, r14
    cmp     rcx, [g_ulen]
    jb      .nextpattern
.matched:
    mov     rax, r12
    sub     rax, [g_start]
    mov     [g_so], rax
    add     rax, r14
    mov     [g_eo], rax
    mov     rdi, [g_so]
    mov     rsi, [g_eo]
    call    match_word
    test    al, al
    jz      .nextpattern
    mov     al, 1
    jmp     .out
.nextpattern:
    mov     r13, [pat_next + r13 * 8]
    jmp     .pattern
.nextposition:
    cmp     byte [opt_x], 0
    jne     .nomatch
    inc     r12
    jmp     .position
.nomatch:
    xor     al, al
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; match_word: under -w a match has to be bounded by something that is not
; part of a word. rdi and rsi bracket it, measured from g_start.
match_word:
    cmp     byte [opt_w], 0
    je      .yes
    mov     rax, rdi
    add     rax, [g_start]
    test    rax, rax
    jz      .after
    mov     rcx, [g_line]
    add     rcx, [g_start]
    add     rcx, rdi
    movzx   eax, byte [rcx - 1]
    call    is_word_char
    test    al, al
    jnz     .no
.after:
    mov     rcx, [g_line]
    add     rcx, [g_start]
    movzx   eax, byte [rcx + rsi]
    call    is_word_char
    test    al, al
    jnz     .no
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

is_word_char:
    cmp     al, '_'
    je      .yes
    cmp     al, '0'
    jb      .no
    cmp     al, '9'
    jbe     .yes
    cmp     al, 'A'
    jb      .no
    cmp     al, 'Z'
    jbe     .yes
    cmp     al, 'a'
    jb      .no
    cmp     al, 'z'
    ja      .no
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; line_match: the best match on the line from g_start -- the leftmost, and
; the longest of those. Plain patterns are tried first and a compiled one
; only replaces the answer when it reaches further left, or as far left and
; at least as far right.
;   al = 1 when something matched.
; ---------------------------------------------------------------------------
line_match:
    push    rbx
    push    r12
    push    r13
    mov     qword [g_so], 0
    mov     qword [g_eo], 0
    mov     qword [g_mso], 0
    mov     qword [g_meo], 0
    mov     qword [g_rc], 1
    call    fast_match
    test    al, al
    jz      .regexes
    mov     rax, [g_so]
    mov     [g_mso], rax
    mov     rax, [g_eo]
    mov     [g_meo], rax
    mov     qword [g_rc], 0
    jmp     .done
.regexes:
    xor     r12, r12
.regex:
    cmp     r12, [regexcount]
    jae     .done
    cmp     qword [rx_rc + r12 * 8], 0
    jne     .nextregex
    mov     rax, [rx_so + r12 * 8]
    sub     rax, [g_move]
    mov     [rx_so + r12 * 8], rax
    mov     rcx, [rx_eo + r12 * 8]
    sub     rcx, [g_move]
    mov     [rx_eo + r12 * 8], rcx
    cmp     qword [g_matched], 0
    je      .execute
    cmp     rax, 0
    jge     .usecached
.execute:
    xor     r13, r13                    ;how far past the start to look
.retry:
    mov     rdi, [regexes + r12 * 8]
    mov     rsi, [g_line]
    add     rsi, [g_start]
    add     rsi, r13
    mov     rdx, [g_ulen]
    sub     rdx, [g_start]
    sub     rdx, r13
    xor     rcx, rcx
    mov     rax, [g_start]
    add     rax, r13
    test    rax, rax
    jz      .exec
    mov     rcx, 1
.exec:
    call    regex_exec
    test    al, al
    jz      .failed
    mov     rax, [rx_mso]
    add     rax, r13
    mov     [rx_so + r12 * 8], rax
    mov     rcx, [rx_meo]
    add     rcx, r13
    mov     [rx_eo + r12 * 8], rcx
; under -w a match that runs into a word is no use, but a later one may do
    mov     rdi, rax
    mov     rsi, rcx
    call    match_word
    test    al, al
    jnz     .accepted
    mov     r13, [rx_so + r12 * 8]
    inc     r13
    mov     rax, [g_ulen]
    sub     rax, [g_start]
    cmp     r13, rax
    ja      .failed
    jmp     .retry
.accepted:
    mov     qword [rx_rc + r12 * 8], 0
    jmp     .usecached
.failed:
    mov     qword [rx_rc + r12 * 8], 1
.usecached:
    mov     rdi, [rx_so + r12 * 8]
    mov     rsi, [rx_eo + r12 * 8]
    call    match_word
    test    al, al
    jz      .nextregex
    cmp     qword [rx_rc + r12 * 8], 0
    jne     .nextregex
    cmp     qword [g_rc], 0
    jne     .take
    mov     rax, [rx_so + r12 * 8]
    cmp     rax, [g_mso]
    jb      .take
    jne     .nextregex
    mov     rax, [rx_eo + r12 * 8]
    cmp     rax, [g_meo]
    jb      .nextregex
.take:
    mov     rax, [rx_so + r12 * 8]
    mov     [g_mso], rax
    mov     rax, [rx_eo + r12 * 8]
    mov     [g_meo], rax
    mov     qword [g_rc], 0
.nextregex:
    inc     r12
    jmp     .regex
.done:
    xor     al, al
    cmp     qword [g_rc], 0
    jne     .out
    mov     al, 1
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; outline: one line of output, with whichever prefixes are in force.
;   rdi = text or zero, sil = the character after a prefix, rdx = name,
;   rcx = line number, r8 = byte offset plus one, r9 = how much text
; ---------------------------------------------------------------------------
outline:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rdx
    mov     r13, rcx
    mov     r14, r8
    mov     r15, r9
    mov     [g_dash], sil
    test    r15, r15
    jnz     .prefix
    cmp     byte [opt_o], 0
    jne     .out
.prefix:
    test    r12, r12
    jz      .nonames
    cmp     byte [opt_H], 0
    je      .nonames
    mov     rdi, c_purple
    call    out_color
    mov     rdi, r12
    call    out_str
    mov     rdi, c_cyan
    call    out_color
    movzx   eax, byte [g_dash]
    call    out_char
.nonames:
    cmp     byte [opt_c], 0
    je      .linenum
    mov     rdi, c_grey
    call    out_color
    mov     rdi, r13
    call    out_number
    movzx   eax, byte [delim]
    call    out_char
    jmp     .byteoff
.linenum:
    test    r13, r13
    jz      .byteoff
    cmp     byte [opt_n], 0
    je      .byteoff
    mov     rdi, r13
    call    out_numdash
.byteoff:
    test    r14, r14
    jz      .text
    cmp     byte [opt_b], 0
    je      .text
    lea     rdi, [r14 - 1]
    call    out_numdash
.text:
    test    rbx, rbx
    jz      .out
    cmp     byte [opt_color], 0
    je      .plain
    cmp     byte [opt_o], 0
    je      .greytext
    mov     rdi, c_red
    call    out_color
    jmp     .plain
.greytext:
    mov     rdi, c_grey
    call    out_color
.plain:
    mov     rdi, rbx
    mov     rsi, r15
    call    out_bytes
    movzx   eax, byte [delim]
    call    out_char
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

out_numdash:
    push    rbx
    mov     rbx, rdi
    mov     rdi, c_green
    call    out_color
    mov     rdi, rbx
    call    out_number
    mov     rdi, c_cyan
    call    out_color
    movzx   eax, byte [g_dash]
    call    out_char
    pop     rbx
    ret

out_color:
    cmp     byte [opt_color], 0
    je      .out
    jmp     out_str
.out:
    ret

; ---------------------------------------------------------------------------
; Reading a file a line at a time. The delimiter is a newline, or a NUL byte
; under -z.
; ---------------------------------------------------------------------------
reader_init:
    mov     [readfd], rdi
    mov     qword [readpos], 0
    mov     qword [readend], 0
    mov     qword [readeof], 0
    ret

; read_line: rax is how many bytes the line took up including its delimiter,
; or zero at the end. g_ulen is the length without it.
read_line:
    push    rbx
    push    r12
    xor     rbx, rbx                    ;bytes gathered
.byte:
    mov     rax, [readpos]
    cmp     rax, [readend]
    jb      .have
    cmp     qword [readeof], 0
    jne     .done
    mov     rax, SYS_READ
    mov     rdi, [readfd]
    mov     rsi, readbuf
    mov     rdx, READCAP
    syscall
    test    rax, rax
    jg      .filled
    mov     qword [readeof], 1
    jmp     .done
.filled:
    mov     qword [readpos], 0
    mov     [readend], rax
    jmp     .byte
.have:
    movzx   ecx, byte [readbuf + rax]
    inc     rax
    mov     [readpos], rax
    cmp     rbx, LINECAP - 2
    jae     .store
    mov     [linebuf + rbx], cl
    inc     rbx
.store:
    cmp     cl, [delim]
    jne     .byte
.done:
    test    rbx, rbx
    jz      .empty
    mov     r12, rbx
    mov     al, [delim]
    cmp     [linebuf + rbx - 1], al
    jne     .noterm
    dec     rbx
.noterm:
    mov     [g_ulen], rbx
    mov     byte [linebuf + rbx], 0
    mov     qword [g_line], linebuf
    mov     rax, r12
    pop     r12
    pop     rbx
    ret
.empty:
    xor     rax, rax
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; do_grep: one file, from its descriptor rdi, called rsi.
; ---------------------------------------------------------------------------
do_grep:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15, rdi
    mov     [curname], rsi
    cmp     byte [opt_r], 0
    jne     .named
    inc     qword [tried]
.named:
    test    r15, r15
    jnz     .binary
    mov     qword [curname], s_stdin
.binary:
    mov     qword [is_binary], 0
    cmp     byte [opt_a], 0
    jne     .start
    mov     rdi, r15
    call    check_binary
    cmp     qword [is_binary], 0
    je      .start
    cmp     byte [opt_I], 0
    je      .start
    jmp     .out
.start:
    mov     rdi, r15
    call    reader_init
    mov     qword [g_lcount], 0
    mov     qword [g_mcount], 0
    mov     qword [g_offset], 0
    mov     qword [g_after], 0
    mov     qword [g_before], 0
    mov     qword [g_new], 1
    mov     qword [barspending], 0
    mov     qword [ctx_count], 0
    mov     qword [ctx_head], 0
    mov     qword [ctxw], 0
.line:
    call    read_line
    test    rax, rax
    jz      .eof
    mov     [g_rawlen], rax
    inc     qword [g_lcount]
    mov     qword [g_start], 0
    mov     qword [g_matched], 0
    mov     qword [g_move], 0
    xor     rcx, rcx
.clearrx:
    cmp     rcx, [regexcount]
    jae     .cleared
    mov     qword [rx_rc + rcx * 8], 0
    inc     rcx
    jmp     .clearrx
.cleared:
    cmp     qword [g_new], 0
    je      .afterline

.matchloop:
    call    line_match
; a match of no length under -o gets us nowhere, so step past it
    cmp     qword [g_rc], 0
    jne     .checkx
    cmp     byte [opt_o], 0
    je      .checkx
    cmp     qword [g_meo], 0
    jne     .checkx
    mov     rax, [g_ulen]
    cmp     rax, [g_start]
    jbe     .checkx
    mov     qword [g_move], 1
    jmp     .advance
.checkx:
    cmp     qword [g_rc], 0
    jne     .invert
    cmp     byte [opt_x], 0
    je      .invert
    cmp     qword [g_mso], 0
    jne     .notwhole
    mov     rax, [g_ulen]
    sub     rax, [g_start]
    cmp     rax, [g_meo]
    je      .invert
.notwhole:
    mov     qword [g_rc], 1
.invert:
    cmp     byte [opt_v], 0
    je      .plain
    cmp     byte [opt_o], 0
    je      .vwhole
    cmp     qword [g_rc], 0
    jne     .vnomatch
    cmp     qword [g_mso], 0
    jne     .vtrim
    mov     rax, [g_meo]
    mov     [g_move], rax
    jmp     .advance
.vtrim:
    mov     rax, [g_mso]
    mov     [g_meo], rax
    jmp     .vdone
.vnomatch:
    mov     rax, [g_ulen]
    sub     rax, [g_start]
    mov     [g_meo], rax
    jmp     .vdone
.vwhole:
    cmp     qword [g_rc], 0
    je      .endmatch
    mov     rax, [g_ulen]
    sub     rax, [g_start]
    mov     [g_meo], rax
.vdone:
    mov     qword [g_mso], 0
    jmp     .accept
.plain:
    cmp     qword [g_rc], 0
    jne     .endmatch
.accept:
    cmp     qword [barspending], 0
    je      .nobars
    mov     rdi, s_bars
    mov     rsi, 3
    call    out_bytes
    mov     qword [barspending], 0
.nobars:
    inc     qword [g_matched]
    mov     qword [found], 1
    cmp     byte [opt_q], 0
    je      .notquiet
    mov     qword [exitcode], 0
    call    out_flush
    mov     rax, SYS_EXIT
    xor     rdi, rdi
    syscall
.notquiet:
    cmp     byte [opt_L], 0
    jne     .out
    cmp     byte [opt_l], 0
    je      .display
    mov     rdi, [curname]
    call    out_str
    xor     eax, eax
    cmp     byte [opt_Z], 0
    jne     .lnodelim
    mov     al, WHITESPACE_NL
.lnodelim:
    call    out_char
    jmp     .out
.display:
    cmp     byte [opt_c], 0
    jne     .step
; the byte the match starts at, counted from the beginning of the file
    mov     r13, 1
    add     r13, [g_offset]
    add     r13, [g_start]
    cmp     byte [opt_o], 0
    je      .havebcount
    add     r13, [g_mso]
.havebcount:
    cmp     qword [is_binary], 0
    je      .notbinary
    cmp     qword [g_matched], 1
    jne     .step
    mov     rdi, s_binary1
    mov     rsi, s_binary1_l
    call    out_bytes
    mov     rdi, [curname]
    call    out_str
    mov     rdi, s_binary2
    mov     rsi, s_binary2_l
    call    out_bytes
    jmp     .step
.notbinary:
    cmp     byte [opt_o], 0
    je      .wholeline
    mov     rdi, [g_line]
    add     rdi, [g_start]
    add     rdi, [g_mso]
mov     sil, ':'
    mov     rdx, [curname]
    mov     rcx, [g_lcount]
    mov     r8, r13
    mov     r9, [g_meo]
    sub     r9, [g_mso]
    call    outline
    jmp     .step
.wholeline:
    call    flush_context
    cmp     qword [g_matched], 1
    jne     .colorpart
    mov     rdi, [g_line]
    cmp     byte [opt_color], 0
    je      .haveline
    xor     rdi, rdi
.haveline:
mov     sil, ':'
    mov     rdx, [curname]
    mov     rcx, [g_lcount]
    mov     r8, r13
    mov     r9, [g_ulen]
    call    outline
.colorpart:
    cmp     byte [opt_color], 0
    je      .setafter
    mov     rdi, c_grey
    call    out_str
    mov     rdi, [g_line]
    add     rdi, [g_start]
    mov     rsi, [g_mso]
    call    out_bytes
    mov     rdi, c_red
    call    out_str
    mov     rdi, [g_line]
    add     rdi, [g_start]
    add     rdi, [g_mso]
    mov     rsi, [g_meo]
    sub     rsi, [g_mso]
    call    out_bytes
.setafter:
    cmp     qword [opt_A], 0
    je      .step
    mov     rax, [opt_A]
    inc     rax
    mov     [g_after], rax
.step:
    mov     rax, [g_meo]
    mov     [g_move], rax
    cmp     rax, [g_mso]
    je      .endmatch
.advance:
    mov     rax, [g_start]
    add     rax, [g_move]
    mov     [g_start], rax
    cmp     rax, [g_ulen]
    jae     .endmatch
    mov     rcx, [g_line]
    cmp     byte [rcx + rax], 0
    je      .endmatch
    jmp     .matchloop

.endmatch:
.afterline:
    mov     rax, [g_rawlen]
    add     [g_offset], rax
    cmp     qword [g_matched], 0
    je      .nomatch
    cmp     byte [opt_color], 0
    je      .counted
    cmp     byte [opt_o], 0
    jne     .counted
    mov     rdi, c_grey
    call    out_str
    mov     rax, [g_ulen]
    cmp     rax, [g_start]
    jbe     .tailend
    mov     rdi, [g_line]
    add     rdi, [g_start]
    mov     rsi, [g_ulen]
    sub     rsi, [g_start]
    call    out_bytes
.tailend:
    movzx   eax, byte [delim]
    call    out_char
.counted:
    inc     qword [g_mcount]
    jmp     .limit
.nomatch:
    xor     r14, r14                    ;whether this line is being dropped
    cmp     qword [g_after], 0
    jne     .discarding
    cmp     qword [opt_B], 0
    je      .nodiscard
.discarding:
    mov     r14, 1
.nodiscard:
    cmp     qword [g_after], 0
    je      .holdback
    dec     qword [g_after]
    cmp     qword [g_after], 0
    je      .holdback
    mov     rdi, [g_line]
    mov     sil, '-'
    mov     rdx, [curname]
    mov     rcx, [g_lcount]
    xor     r8, r8
    mov     r9, [g_ulen]
    call    outline
    xor     r14, r14
.holdback:
    test    r14, r14
    jz      .maybebars
    cmp     qword [opt_B], 0
    je      .maybebars
    call    push_context
    mov     rax, [g_before]
    inc     rax
    mov     [g_before], rax
    cmp     rax, [opt_B]
    ja      .dropoldest
    xor     r14, r14
    jmp     .maybebars
.dropoldest:
    call    pop_context
    dec     qword [g_before]
.maybebars:
    test    r14, r14
    jz      .limit
    cmp     qword [g_mcount], 0
    je      .limit
    mov     qword [barspending], 1
.limit:
    cmp     byte [have_m], 0
    je      .line
    mov     rax, [g_mcount]
    cmp     rax, [opt_m]
    jb      .line
    cmp     qword [g_after], 0
    je      .eof
    mov     qword [g_new], 0
    jmp     .line

.eof:
    cmp     byte [opt_L], 0
    je      .maybecount
    mov     rdi, [curname]
    call    out_str
    movzx   eax, byte [delim]
    call    out_char
    jmp     .out
.maybecount:
    cmp     byte [opt_c], 0
    je      .out
    xor     rdi, rdi
mov     sil, ':'
    mov     rdx, [curname]
    mov     rcx, [g_mcount]
    xor     r8, r8
    mov     r9, 1
    call    outline
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; push_context / pop_context / flush_context: the lines held back so that -B
; can show what came before a match.
push_context:
    push    rbx
    push    r12
    mov     rax, [ctxw]
    mov     rcx, [g_ulen]
    add     rcx, rax
    inc     rcx
    cmp     rcx, LINECAP
    jb      .room
    xor     rax, rax
    mov     [ctxw], rax
.room:
    mov     rbx, [ctx_head]
    add     rbx, [ctx_count]
    and     rbx, MAXDEPTH - 1
    mov     [ctx_off + rbx * 8], rax
    mov     rcx, [g_ulen]
    mov     [ctx_len + rbx * 8], rcx
    mov     rdx, [g_offset]
    sub     rdx, [g_rawlen]
    mov     [ctx_boff + rbx * 8], rdx
    lea     rdi, [ctxbuf + rax]
    mov     rsi, [g_line]
    mov     rdx, [g_ulen]
    call    copy_bytes
    mov     rax, [ctxw]
    add     rax, [g_ulen]
    inc     rax
    mov     [ctxw], rax
    inc     qword [ctx_count]
    pop     r12
    pop     rbx
    ret

pop_context:
    mov     rax, [ctx_head]
    inc     rax
    and     rax, MAXDEPTH - 1
    mov     [ctx_head], rax
    dec     qword [ctx_count]
    ret

flush_context:
    push    rbx
    push    r12
.entry:
    cmp     qword [ctx_count], 0
    je      .out
    mov     rbx, [ctx_head]
    mov     rdi, ctxbuf
    add     rdi, [ctx_off + rbx * 8]
    mov     sil, '-'
    mov     rdx, [curname]
    mov     rcx, [g_lcount]
    sub     rcx, [g_before]
    mov     r8, [ctx_boff + rbx * 8]
    inc     r8
    mov     r9, [ctx_len + rbx * 8]
    call    outline
    call    pop_context
    dec     qword [g_before]
    jmp     .entry
.out:
    pop     r12
    pop     rbx
    ret

; check_binary: a file whose first bytes are not valid UTF-8 is treated as
; binary. Only a file that can be seeked is looked at, since a pipe cannot be
; put back.
check_binary:
    push    rbx
    push    r12
    push    r13
    mov     r13, rdi
    mov     rax, SYS_LSEEK_ID
    mov     rdi, r13
    xor     rsi, rsi
    mov     rdx, 1                      ;SEEK_CUR
    syscall
    test    rax, rax
    jnz     .out
    mov     rax, SYS_READ
    mov     rdi, r13
    mov     rsi, readbuf
    mov     rdx, 256
    syscall
    test    rax, rax
    jle     .out
    mov     r12, rax
    push    r12
    mov     rax, SYS_LSEEK_ID
    mov     rdi, r13
    mov     rsi, r12
    neg     rsi
    mov     rdx, 1
    syscall
    pop     r12
    xor     rbx, rbx
.scan:
    cmp     rbx, r12
    jae     .out
    mov     rdi, readbuf
    add     rdi, rbx
    mov     rsi, r12
    sub     rsi, rbx
    call    utf8_step                   ;-> rax bytes, or 0 when it is not
    test    rax, rax
    jz      .binary
    add     rbx, rax
    jmp     .scan
.binary:
    mov     qword [is_binary], 1
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; utf8_step: how many bytes the character at rdi takes, or zero when the rsi
; bytes there are not a whole valid one.
utf8_step:
    movzx   eax, byte [rdi]
    test    al, 0x80
    jz      .one
    mov     rcx, 1
    mov     dl, al
    and     dl, 0xE0
    cmp     dl, 0xC0
    je      .two
    mov     dl, al
    and     dl, 0xF0
    cmp     dl, 0xE0
    je      .three
    mov     dl, al
    and     dl, 0xF8
    cmp     dl, 0xF0
    je      .four
    xor     rax, rax
    ret
.two:
    mov     rcx, 2
    jmp     .check
.three:
    mov     rcx, 3
    jmp     .check
.four:
    mov     rcx, 4
.check:
    cmp     rcx, rsi
    ja      .truncated
    mov     rdx, 1
.cont:
    cmp     rdx, rcx
    jae     .ok
    movzx   eax, byte [rdi + rdx]
    and     al, 0xC0
    cmp     al, 0x80
    jne     .bad
    inc     rdx
    jmp     .cont
.ok:
    mov     rax, rcx
    ret
.bad:
    xor     rax, rax
    ret
.truncated:
    mov     rax, rsi                    ;a character cut short is not binary
    ret
.one:
    mov     rax, 1
    ret

; ---------------------------------------------------------------------------
; run_grep: settle the options against each other, build the patterns, then
; work through whatever was named.
; ---------------------------------------------------------------------------
run_grep:
    push    rbx
    push    r12
    push    r13
; colour only goes to a terminal unless it was asked for outright
    cmp     byte [opt_color], 0
    je      .nocolor
    mov     rax, [color_arg]
    test    rax, rax
    jz      .checktty
    mov     rdi, rax
    mov     rsi, s_auto
    call    str_equal
    test    al, al
    jz      .nocolor
.checktty:
    call    stdout_is_tty
    test    al, al
    jnz     .nocolor
    mov     byte [opt_color], 0
.nocolor:
    cmp     qword [opt_A], 0
    jne     .haveafter
    mov     rax, [opt_C]
    mov     [opt_A], rax
.haveafter:
    cmp     qword [opt_B], 0
    jne     .havebefore
    mov     rax, [opt_C]
    mov     [opt_B], rax
.havebefore:
    mov     rax, [opt_B]
    cmp     rax, MAXDEPTH - 1
    jbe     .boundedb
    mov     qword [opt_B], MAXDEPTH - 1
.boundedb:
    xor     eax, eax
    cmp     byte [opt_z], 0
    jne     .havedelim
    mov     al, WHITESPACE_NL
.havedelim:
    mov     [delim], al
; without -e or -f the first thing named is the pattern
    cmp     byte [have_e], 0
    jne     .patterns
    cmp     byte [have_f], 0
    jne     .patterns
    cmp     qword [filecount], 0
    jne     .takefirst
    call    out_flush
    write   STDERR_FILENO, e_noregex, e_noregex_l
    exit    2
.takefirst:
    mov     rdi, [files]
    call    add_pattern_text
    mov     rcx, 1
.shift:
    cmp     rcx, [filecount]
    jae     .shifted
    mov     rax, [files + rcx * 8]
    mov     [files + rcx * 8 - 8], rax
    inc     rcx
    jmp     .shift
.shifted:
    dec     qword [filecount]
.patterns:
    call    sort_patterns
    cmp     byte [opt_h], 0
    jne     .files
    cmp     qword [filecount], 1
    jbe     .files
    mov     byte [opt_H], 1
.files:
    cmp     byte [opt_r], 0
    jne     .recursive
    cmp     qword [filecount], 0
    jne     .eachfile
    xor     rdi, rdi
    mov     rsi, s_dash
    call    do_grep
    jmp     .finished
.eachfile:
    xor     r12, r12
.onefile:
    cmp     r12, [filecount]
    jae     .finished
    mov     rbx, [files + r12 * 8]
    mov     rdi, rbx
    mov     rsi, s_dash
    call    str_equal
    test    al, al
    jz      .openit
    xor     rdi, rdi
    mov     rsi, rbx
    call    do_grep
    jmp     .nextfile
.openit:
    mov     rax, SYS_OPEN
    mov     rdi, rbx
    mov     rsi, O_RDONLY | O_NONBLOCK_FLAG | O_NOCTTY_FLAG
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .cannotopen
    mov     r13, rax
    mov     rdi, rax
    mov     rsi, rbx
    call    do_grep
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
    jmp     .nextfile
.cannotopen:
    mov     rdi, rbx
    call    report_missing
.nextfile:
    inc     r12
    jmp     .onefile

.recursive:
    cmp     qword [filecount], 0
    jne     .eachtree
    mov     qword [files], s_dot
    mov     qword [filecount], 1
.eachtree:
    xor     r12, r12
.onetree:
    cmp     r12, [filecount]
    jae     .finished
    mov     rbx, [files + r12 * 8]
    inc     qword [tried]
    mov     rdi, rbx
    mov     rsi, s_dash
    call    str_equal
    test    al, al
    jz      .walkit
    xor     rdi, rdi
    mov     rsi, rbx
    call    do_grep
    jmp     .nexttree
.walkit:
    mov     rdi, rbx
    call    path_set
    mov     rdi, 1
    call    walk_path
.nexttree:
    inc     r12
    jmp     .onetree

.finished:
    call    out_flush
    mov     rax, [tried]
    cmp     rax, [filecount]
    jae     .settle
    cmp     byte [opt_q], 0
    je      .out
    cmp     qword [found], 0
    je      .out
.settle:
    mov     rax, 1
    cmp     qword [found], 0
    je      .store
    xor     rax, rax
.store:
    mov     [exitcode], rax
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

report_missing:
    cmp     byte [opt_s], 0
    jne     .out
    push    rdi
    call    out_flush
    write   STDERR_FILENO, e_prefix, e_prefix_l
    pop     rdi
    push    rdi
    call    strlen_of
    mov     rdx, rax
    pop     rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    write   STDERR_FILENO, e_nofile, e_nofile_l
.out:
    ret

; ---------------------------------------------------------------------------
; Walking a directory. A name that is not a directory is searched; a
; directory is descended into unless --exclude-dir turns it away.
; ---------------------------------------------------------------------------

; path_set: pathbuf becomes the NUL terminated name at rdi.
path_set:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rdi + rcx]
    mov     [pathbuf + rcx], al
    test    al, al
    jz      .done
    inc     rcx
    jmp     .byte
.done:
    mov     [pathlen], rcx
    ret

; walk_path: what pathbuf names, with rdi saying whether it was named on the
; command line rather than found inside a directory.
walk_path:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15, rdi
    mov     rax, SYS_LSTAT_ID
    cmp     byte [opt_R], 0
    je      .stat
    mov     rax, SYS_STAT
.stat:
    mov     rdi, pathbuf
    mov     rsi, stbuf
    syscall
    test    rax, rax
    js      .missing
    mov     eax, [stbuf + ST_MODE_OFF]
    and     eax, S_IFMT
    cmp     eax, S_IFDIR
    je      .directory
; a plain file, unless a filter turns it away
    call    name_filtered
    test    al, al
    jnz     .out
    test    r15, r15
    jnz     .noforce
    cmp     byte [opt_h], 0
    jne     .noforce
    mov     byte [opt_H], 1
.noforce:
    mov     rax, SYS_OPEN
    mov     rdi, pathbuf
    mov     rsi, O_RDONLY | O_NONBLOCK_FLAG | O_NOCTTY_FLAG
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .openfailed
    mov     r13, rax
    mov     rdi, rax
    mov     rsi, pathbuf
    call    do_grep
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
    jmp     .out
.openfailed:
    mov     rdi, pathbuf
    call    report_missing
    jmp     .out
.missing:
    mov     rdi, pathbuf
    call    report_missing
    jmp     .out

.directory:
    test    r15, r15
    jnz     .enter
    mov     rdi, pathbuf
    call    basename_of
    mov     rdi, rax
    call    dir_excluded
    test    al, al
    jnz     .out
.enter:
    mov     rax, SYS_OPEN
    mov     rdi, pathbuf
    mov     rsi, O_RDONLY | O_DIRECTORY_FLAG
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .out
    mov     r13, rax
    mov     r14, [pathlen]
.chunk:
    mov     rax, SYS_GETDENTS_ID
    mov     rdi, r13
    mov     rsi, dirbuf
    mov     rdx, DIRCAP
    syscall
    test    rax, rax
    jle     .closedir
    mov     r12, rax
    xor     rbx, rbx
.entry:
    cmp     rbx, r12
    jae     .chunk
    lea     rdi, [dirbuf + rbx + 19]
    call    is_dot_name
    test    al, al
    jnz     .nextentry
    mov     [pathlen], r14
    mov     byte [pathbuf + r14], '/'
    lea     rdi, [pathbuf + r14 + 1]
    lea     rsi, [dirbuf + rbx + 19]
    call    copy_name
    lea     rcx, [r14 + 1]
    add     rcx, rax
    mov     [pathlen], rcx
    mov     byte [pathbuf + rcx], 0
    push    rbx
    xor     rdi, rdi
    call    walk_path
    pop     rbx
.nextentry:
    movzx   eax, word [dirbuf + rbx + 16]
    add     rbx, rax
    jmp     .entry
.closedir:
    mov     [pathlen], r14
    mov     byte [pathbuf + r14], 0
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

is_dot_name:
    cmp     byte [rdi], '.'
    jne     .no
    cmp     byte [rdi + 1], 0
    je      .yes
    cmp     byte [rdi + 1], '.'
    jne     .no
    cmp     byte [rdi + 2], 0
    je      .yes
.no:
    xor     al, al
    ret
.yes:
    mov     al, 1
    ret

copy_name:
    xor     rax, rax
.byte:
    movzx   ecx, byte [rsi + rax]
    test    cl, cl
    jz      .out
    mov     [rdi + rax], cl
    inc     rax
    jmp     .byte
.out:
    ret

basename_of:
    mov     rax, rdi
    mov     rcx, rdi
.byte:
    movzx   edx, byte [rcx]
    test    dl, dl
    jz      .out
    cmp     dl, '/'
    jne     .step
    lea     rax, [rcx + 1]
.step:
    inc     rcx
    jmp     .byte
.out:
    ret

dir_excluded:
    push    rbx
    push    r12
    mov     rbx, rdi
    xor     r12, r12
.pattern:
    cmp     r12, [excl_dircnt]
    jae     .no
    mov     rdi, [excl_dir + r12 * 8]
    mov     rsi, rbx
    call    glob_match
    test    al, al
    jnz     .yes
    inc     r12
    jmp     .pattern
.no:
    xor     al, al
    pop     r12
    pop     rbx
    ret
.yes:
    mov     al, 1
    pop     r12
    pop     rbx
    ret

; name_filtered: al = 1 when --exclude or --include says to leave this file
; alone.
name_filtered:
    push    rbx
    push    r12
    mov     rax, [excl_patcnt]
    or      rax, [incl_patcnt]
    test    rax, rax
    jz      .no
    mov     rdi, pathbuf
    call    basename_of
    mov     rbx, rax
    xor     r12, r12
.excluded:
    cmp     r12, [excl_patcnt]
    jae     .checkinclude
    mov     rdi, [excl_pat + r12 * 8]
    mov     rsi, rbx
    call    glob_match
    test    al, al
    jnz     .yes
    inc     r12
    jmp     .excluded
.checkinclude:
    cmp     qword [incl_patcnt], 0
    je      .no
    xor     r12, r12
.included:
    cmp     r12, [incl_patcnt]
    jae     .yes
    mov     rdi, [incl_pat + r12 * 8]
    mov     rsi, rbx
    call    glob_match
    test    al, al
    jnz     .no
    inc     r12
    jmp     .included
.no:
    xor     al, al
    pop     r12
    pop     rbx
    ret
.yes:
    mov     al, 1
    pop     r12
    pop     rbx
    ret

; glob_match: the shell's own kind of pattern, rdi against the name rsi.
glob_match:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    movzx   eax, byte [rbx]
    test    al, al
    jz      .atend
    cmp     al, '*'
    je      .star
    cmp     al, '?'
    je      .single
    cmp     al, '['
    je      .set
    cmp     al, [r12]
    jne     .no
    cmp     byte [r12], 0
    je      .no
    lea     rdi, [rbx + 1]
    lea     rsi, [r12 + 1]
    call    glob_match
    jmp     .out
.single:
    cmp     byte [r12], 0
    je      .no
    lea     rdi, [rbx + 1]
    lea     rsi, [r12 + 1]
    call    glob_match
    jmp     .out
.star:
    lea     rdi, [rbx + 1]
    mov     rsi, r12
    call    glob_match
    test    al, al
    jnz     .out
    cmp     byte [r12], 0
    je      .no
    mov     rdi, rbx
    lea     rsi, [r12 + 1]
    call    glob_match
    jmp     .out
.set:
    cmp     byte [r12], 0
    je      .no
    lea     rdi, [rbx + 1]
    movzx   esi, byte [r12]
    call    glob_set                    ;-> al match, rax past the bracket
    test    cl, cl
    jz      .no
    mov     rdi, rax
    lea     rsi, [r12 + 1]
    call    glob_match
    jmp     .out
.atend:
    cmp     byte [r12], 0
    jne     .no
    mov     al, 1
    jmp     .out
.no:
    xor     al, al
.out:
    pop     r12
    pop     rbx
    ret

; glob_set: does the byte rsi fall in the set starting at rdi? cl says so and
; rax points past the closing bracket.
glob_set:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    xor     r13, r13                    ;whether the set is turned inside out
    cmp     byte [rbx], '!'
    je      .negate
    cmp     byte [rbx], '^'
    jne     .items
.negate:
    mov     r13, 1
    inc     rbx
.items:
    xor     r12, r12                    ;whether the byte was found
.item:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .done
    cmp     al, ']'
    je      .done
    cmp     byte [rbx + 1], '-'
    jne     .single
    cmp     byte [rbx + 2], ']'
    je      .single
    cmp     sil, al
    jb      .skiprange
    movzx   ecx, byte [rbx + 2]
    cmp     sil, cl
    ja      .skiprange
    mov     r12, 1
.skiprange:
    add     rbx, 3
    jmp     .item
.single:
    cmp     sil, al
    jne     .skipone
    mov     r12, 1
.skipone:
    inc     rbx
    jmp     .item
.done:
    cmp     byte [rbx], ']'
    jne     .past
    inc     rbx
.past:
    test    r13, r13
    jz      .plain
    xor     r12, 1
.plain:
    mov     rcx, r12
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

stdout_is_tty:
    mov     rax, 16                     ;ioctl
    mov     rdi, STDOUT_FILENO
    mov     rsi, 0x5401                 ;TCGETS
    mov     rdx, stbuf
    syscall
    test    rax, rax
    jnz     .no
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

str_equal:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rdi + rcx]
    cmp     al, [rsi + rcx]
    jne     .no
    test    al, al
    jz      .yes
    inc     rcx
    jmp     .byte
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

strlen_of:
    xor     rax, rax
.byte:
    cmp     byte [rdi + rax], 0
    je      .out
    inc     rax
    jmp     .byte
.out:
    ret

; ---------------------------------------------------------------------------
; Output, buffered so that a match is not a write of its own.
; ---------------------------------------------------------------------------
out_char:
    push    rcx
    mov     rcx, [outlen]
    mov     [outbuf + rcx], al
    inc     rcx
    mov     [outlen], rcx
    cmp     rcx, OUTCAP - 16
    jb      .out
    call    out_flush
.out:
    pop     rcx
    ret

out_bytes:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
.byte:
    test    r12, r12
    jz      .out
    mov     al, [rbx]
    call    out_char
    inc     rbx
    dec     r12
    jmp     .byte
.out:
    pop     r12
    pop     rbx
    ret

out_str:
    push    rbx
    mov     rbx, rdi
.byte:
    mov     al, [rbx]
    test    al, al
    jz      .out
    call    out_char
    inc     rbx
    jmp     .byte
.out:
    pop     rbx
    ret

out_number:
    push    rbx
    push    r12
    mov     rax, rdi
    mov     rbx, numbuf + 31
    mov     r12, 10
    test    rax, rax
    jnz     .digit
    mov     byte [rbx], '0'
    dec     rbx
    jmp     .emit
.digit:
    test    rax, rax
    jz      .emit
    xor     rdx, rdx
    div     r12
    add     dl, '0'
    mov     [rbx], dl
    dec     rbx
    jmp     .digit
.emit:
    inc     rbx
    mov     rdi, rbx
    mov     rsi, numbuf + 32
    sub     rsi, rbx
    call    out_bytes
    pop     r12
    pop     rbx
    ret

out_flush:
    push    rcx
    push    rdi
    push    rsi
    push    rdx
    mov     rdx, [outlen]
    test    rdx, rdx
    jz      .out
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, outbuf
    syscall
    mov     qword [outlen], 0
.out:
    pop     rdx
    pop     rsi
    pop     rdi
    pop     rcx
    ret
