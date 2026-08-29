; src/man.asm -- man(1): read the manual.
; Usage: man [-M PATH] [-k STRING] | [SECTION] PAGE
;
; A manual page is troff, and troff is a typesetting language; what is
; wanted on a terminal is the words. So the page is read a line at a time
; and reduced: the escapes that stand for a character become that character,
; the requests that only change the type are dropped, and the ones that
; break the page -- a paragraph, a heading, an item in a list -- become a
; blank line. What is left is the text, run together into paragraphs, with
; a space in front of each line that carries any.
;
; Pages are looked for under each directory of the manual path in turn, and
; within each of those through the sections in the order 1 8 3 2 5 4 6 7,
; trying the compressed spellings of the name before the plain one. A page
; that is compressed is handed to the matching decompressor, since knowing
; how to read a manual page and knowing how to undo deflate are two
; different jobs.
;
; -k reads the short description out of every page instead, which is the
; line before the first request in it, or the page a .so points at.

    %include "include/sysdefs.inc"

    %define SYS_FORK_ID 57
    %define SYS_EXECVE_ID 59
    %define SYS_WAIT4_ID 61
    %define SYS_PIPE_ID 22
    %define SYS_DUP2_ID 33
    %define SYS_GETDENTS_ID 217

    %define O_DIRECTORY_FLAG 0x10000

    %define SRCCAP 4194304
    %define LINECAP 65536
    %define OUTCAP 65536
    %define PATHCAP 4096
    %define DIRCAP 65536
    %define MAXPATHS 64
    %define MAXSECTS 16

section .bss
    srcbuf      resb SRCCAP
    srclen      resq 1
    linebuf     resb LINECAP
    linestart   resq 1                  ;the line as it was read
    lineptr     resq 1                  ;and as trimming has left it
    outbuf      resb OUTCAP
    outlen      resq 1
    pathbuf     resb PATHCAP
    namebuf     resb PATHCAP
    zpathbuf    resb PATHCAP
    dirbuf      resb DIRCAP

    manpaths    resq MAXPATHS
    manpathcnt  resq 1
sections    resq MAXSECTS
sectioncnt  resq 1
    pathtext    resb PATHCAP

    opt_k       resq 1
    opt_M       resq 1
    args        resq 8
    argcount    resq 1
    envp        resq 1

    any         resq 1                  ;whether anything is on this line yet
    cell        resq 1                  ;how far into a table entry we are
    example     resq 1                  ;inside .EX, where the text is kept
    k_done      resq 1
    k_name      resq 1                  ;the file a description came from

    pipefds     resd 2
    childpid    resq 1
    statusbuf   resq 1
    stbuf       resb 160
    argvbuf     resq 4
    envbuf      resq 1

section .data
    suf_bz2     db ".bz2", 0
    suf_gz      db ".gz", 0
    suf_xz      db ".xz", 0
    suf_none    db 0
    suffixes    dq suf_bz2, suf_gz, suf_xz, suf_none
    suffixcnt   equ 4
    decoders    dq d_bzcat, d_zcat, d_xzcat
    d_bzcat     db "bzcat", 0
    d_zcat      db "zcat", 0
    d_xzcat     db "xzcat", 0

    sect_1      db "1", 0
    sect_8      db "8", 0
    sect_3      db "3", 0
    sect_2      db "2", 0
    sect_5      db "5", 0
    sect_4      db "4", 0
    sect_6      db "6", 0
    sect_7      db "7", 0
    default_sects dq sect_1, sect_8, sect_3, sect_2, sect_5, sect_4, sect_6
    dq sect_7
    default_sectn equ 8

    env_manpath db "MANPATH=", 0
    default_man db "/usr/share/man", 0
    man_dir     db "/man", 0
    s_see       db "See ", 0
    s_dashsp    db "- ", 0
    s_seek      db " - See ", 0

e_usage     db "usage: man [-M PATH] [-k STRING] | [SECTION] PAGE", 10
    e_usage_len equ $ - e_usage
e_prefix    db "man: "
    e_prefix_l  equ $ - e_prefix
    e_no        db "no "
    e_no_l      equ $ - e_no
    e_section   db "section "
    e_section_l equ $ - e_section

; the substitutions, applied in this order: what troff writes on the left,
; what it means on the right
sub_pairs:
    dq p_fB, p_empty
    dq p_fI, p_empty
    dq p_fP, p_empty
    dq p_fR, p_empty
    dq p_aq, p_quote
    dq p_cq, p_quote
    dq p_dq, p_dquote
    dq p_lq, p_dquote
    dq p_rq, p_dquote
    dq p_bu, p_star
    dq p_bv, p_bar
    dq p_amp, p_empty
    dq p_fCW, p_empty
    dq p_dash, p_hyphen
    dq p_paren, p_empty
    dq p_caret, p_empty
    dq p_bsle, p_backslash
    dq p_star2, p_hash
    sub_count   equ 18

    p_fB        db "\fB", 0
    p_fI        db "\fI", 0
    p_fP        db "\fP", 0
    p_fR        db "\fR", 0
    p_aq        db "\(aq", 0
    p_cq        db "\(cq", 0
    p_dq        db "\(dq", 0
    p_lq        db "\*(lq", 0
    p_rq        db "\*(rq", 0
    p_bu        db "\(bu", 0
    p_bv        db "\(bv", 0
    p_amp       db "\&", 0
    p_fCW       db "\f(CW", 0
    p_dash      db "\-", 0
    p_paren     db "\(", 0
    p_caret     db "\^", 0
    p_bsle      db "\e", 0
    p_star2     db "\*(", 0
    p_empty     db 0
    p_quote     db "'", 0
    p_dquote    db '"', 0
    p_star      db "*", 0
    p_bar       db "|", 0
    p_hyphen    db "-", 0
    p_backslash db "\", 0
    p_hash      db "#", 0

    r_BR        db ".BR", 0
    r_BRsp      db ".BR ", 0
    r_IP        db ".IP", 0
    r_IPsp      db ".IP ", 0
    r_IR        db ".IR", 0
    r_IRsp      db ".IR ", 0
    r_Bsp       db ".B ", 0
    r_BIsp      db ".BI ", 0
    r_FNsp      db ".FN ", 0
    r_Isp       db ".I ", 0
    r_ifn       db ".if n ", 0
    r_E         db ".E", 0
    r_PP        db ".PP", 0
    r_SM        db ".SM", 0
    r_S         db ".S", 0
    r_so        db ".so", 0
    r_TH        db ".TH", 0
    r_TP        db ".TP", 0
    r_dot       db ".", 0
    r_tick      db "'", 0
    r_space     db " ", 0
    r_dquote    db '"', 0
    r_slash     db "/", 0
    env_path    db "PATH=", 0
default_path db "/usr/bin:/bin", 0

section .text
global _start

_start:
    mov     r14, [rsp]                  ;argc
    lea     r15, [rsp + 8]              ;argv
    lea     rax, [rsp + r14 * 8 + 16]
    mov     [envp], rax
    mov     r12, 1
.arg:
    cmp     r12, r14
    jae     .parsed
    mov     rbx, [r15 + r12 * 8]
    cmp     byte [rbx], '-'
    jne     .operand
    cmp     byte [rbx + 1], 0
    je      .operand
    movzx   eax, byte [rbx + 1]
    cmp     al, 'k'
    je      .flag_k
    cmp     al, 'M'
    je      .flag_M
    jmp     usage_error
.flag_k:
    lea     rbx, [rbx + 2]
    call    option_value
    mov     [opt_k], rax
    jmp     .nextarg
.flag_M:
    lea     rbx, [rbx + 2]
    call    option_value
    mov     [opt_M], rax
    jmp     .nextarg
.operand:
    mov     rcx, [argcount]
    cmp     rcx, 8
    jae     .nextarg
    mov     [args + rcx * 8], rbx
    inc     qword [argcount]
.nextarg:
    inc     r12
    jmp     .arg

.parsed:
    call    build_manpath
    call    build_sections
    cmp     qword [opt_k], 0
    je      .lookup
    call    keyword_search
    call    out_flush
    exit    0
.lookup:
    cmp     qword [argcount], 0
    jne     .haveargs
    jmp     usage_error
.haveargs:
    cmp     qword [argcount], 1
    jne     .withsection
    mov     rdi, [args]
    call    has_slash
    test    al, al
    jz      .search
    mov     rdi, [args]
    call    zread
    test    al, al
    jz      .notfound
    jmp     .render
.search:
    mov     rdi, [args]
    call    find_page
    test    al, al
    jnz     .render
.notfound:
    call    out_flush
    write   STDERR_FILENO, e_prefix, e_prefix_l
    write   STDERR_FILENO, e_no, e_no_l
    mov     rdi, [args]
    call    err_line
    exit    1
.withsection:
    mov     rax, [args]
    mov     [sections], rax
    mov     qword [sectioncnt], 1
    mov     rdi, [args + 8]
    call    find_page
    test    al, al
    jnz     .render
    call    out_flush
    write   STDERR_FILENO, e_prefix, e_prefix_l
    write   STDERR_FILENO, e_section, e_section_l
    mov     rdi, [args]
    call    err_word
    mov     rdi, e_no
    mov     rsi, e_no_l
    call    err_bytes
    mov     rdi, [args + 8]
    call    err_line
    exit    1
.render:
    call    render_page
    call    out_flush
    exit    0

; option_value: what follows the option letter, or the argument after it.
option_value:
    cmp     byte [rbx], 0
    jne     .attached
    inc     r12
    cmp     r12, r14
    jae     usage_error
    mov     rax, [r15 + r12 * 8]
    ret
.attached:
    mov     rax, rbx
    ret

usage_error:
    call    out_flush
    write   STDERR_FILENO, e_usage, e_usage_len
    exit    1

; err_word / err_line: a word with a space after it, or one with a newline.
err_word:
    push    rbx
    mov     rbx, rdi
    call    strlen_of
    mov     rdx, rax
    mov     rsi, rbx
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    write   STDERR_FILENO, r_space, 1
    pop     rbx
    ret

err_line:
    push    rbx
    mov     rbx, rdi
    call    strlen_of
    mov     rdx, rax
    mov     rsi, rbx
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    mov     byte [pathbuf], WHITESPACE_NL
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, pathbuf
    mov     rdx, 1
    syscall
    pop     rbx
    ret

err_bytes:
    mov     rdx, rsi
    mov     rsi, rdi
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    ret

; ---------------------------------------------------------------------------
; build_manpath: -M, or MANPATH, or the usual place, split at colons. An
; empty setting is one empty directory, which finds nothing -- that is what
; it means.
; ---------------------------------------------------------------------------
build_manpath:
    push    rbx
    push    r12
    push    r13
    mov     rbx, [opt_M]
    test    rbx, rbx
    jnz     .split
    mov     rdi, env_manpath
    call    getenv_value
    mov     rbx, rax
    test    rbx, rbx
    jnz     .split
    mov     rbx, default_man
.split:
    xor     r12, r12                    ;where in pathtext we are writing
    lea     r13, [pathtext]
    mov     rcx, [manpathcnt]
    mov     [manpaths + rcx * 8], r13
    inc     qword [manpathcnt]
.byte:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .last
cmp     al, ':'
    je      .colon
    mov     [r13], al
    inc     r13
    inc     rbx
    jmp     .byte
.colon:
    mov     byte [r13], 0
    inc     r13
    inc     rbx
    mov     rcx, [manpathcnt]
    cmp     rcx, MAXPATHS
    jae     .byte
    mov     [manpaths + rcx * 8], r13
    inc     qword [manpathcnt]
    jmp     .byte
.last:
    mov     byte [r13], 0
    pop     r13
    pop     r12
    pop     rbx
    ret

build_sections:
    mov     rcx, default_sectn
    mov     [sectioncnt], rcx
.copy:
    dec     rcx
    mov     rax, [default_sects + rcx * 8]
    mov     [sections + rcx * 8], rax
    test    rcx, rcx
    jnz     .copy
    ret

getenv_value:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, [envp]
.entry:
    mov     rsi, [r12]
    test    rsi, rsi
    jz      .none
    mov     rdi, rbx
    call    prefix_of
    test    al, al
    jnz     .found
    add     r12, 8
    jmp     .entry
.found:
    mov     rdi, rbx
    call    strlen_of
    add     rax, [r12]
    pop     r12
    pop     rbx
    ret
.none:
    xor     rax, rax
    pop     r12
    pop     rbx
    ret

; prefix_of: al = 1 when rsi begins with rdi.
prefix_of:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rdi + rcx]
    test    al, al
    jz      .yes
    cmp     al, [rsi + rcx]
    jne     .no
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

has_slash:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rdi + rcx]
    test    al, al
    jz      .no
    cmp     al, '/'
    je      .yes
    inc     rcx
    jmp     .byte
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; base_name: the part of rdi after the last slash.
base_name:
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

; path_append: add the NUL terminated rsi to pathbuf, which rdi says is
; already that long. rax is the new length.
path_append:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rsi + rcx]
    test    al, al
    jz      .done
    mov     [pathbuf + rdi], al
    inc     rdi
    inc     rcx
    jmp     .byte
.done:
    mov     byte [pathbuf + rdi], 0
    mov     rax, rdi
    ret

; ---------------------------------------------------------------------------
; Finding a page. Each directory of the manual path is tried in turn, and
; within it each section, and within that each way the file might be named:
; with the section in the name or without it, compressed or not.
; ---------------------------------------------------------------------------

; find_page: the page named rdi. al = 1 when one was read into srcbuf.
find_page:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    xor     r12, r12
.path:
    cmp     r12, [manpathcnt]
    jae     .nomatch
    xor     r13, r13
.section:
    cmp     r13, [sectioncnt]
    jae     .nextpath
    mov     rdi, [manpaths + r12 * 8]
    mov     rsi, [sections + r13 * 8]
    mov     rdx, rbx
    call    try_file
    test    al, al
    jnz     .found
    inc     r13
    jmp     .section
.nextpath:
    inc     r12
    jmp     .path
.found:
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

; try_file: directory rdi, section rsi, page rdx. The name is tried with the
; section in it and without, and with each compressed spelling.
try_file:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
; "DIR/manSECTION/PAGE"
    xor     rdi, rdi
    mov     rsi, rbx
    call    path_append
    mov     rdi, rax
    mov     rsi, man_dir
    call    path_append
    mov     rdi, rax
    mov     rsi, r12
    call    path_append
    mov     rdi, rax
    mov     rsi, r_slash
    call    path_append
    mov     rdi, rax
    mov     rsi, r13
    call    path_append
    mov     r15, rax                    ;the name without the section on it
; and then with ".SECTION" after it
    mov     rdi, rax
    mov     rsi, r_dot
    call    path_append
    mov     rdi, rax
    mov     rsi, r12
    call    path_append
    mov     r14, rax
; the fuller name first, then the barer one
    mov     rdi, r14
    call    try_suffixes
    test    al, al
    jnz     .out
    mov     rdi, r15
    call    try_suffixes
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; try_suffixes: pathbuf, rdi long, with each compressed spelling in turn.
try_suffixes:
    push    rbx
    push    r12
    mov     rbx, rdi
    xor     r12, r12
.suffix:
    cmp     r12, suffixcnt
    jae     .nomatch
    mov     rdi, rbx
    mov     rsi, [suffixes + r12 * 8]
    call    path_append
    mov     rdi, pathbuf
    call    zread
    test    al, al
    jnz     .found
    inc     r12
    jmp     .suffix
.found:
    mov     al, 1
    pop     r12
    pop     rbx
    ret
.nomatch:
    xor     al, al
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; zread: read the file named by rdi into srcbuf, handing it to a
; decompressor first when its name says it is compressed. al = 1 when the
; file could be opened at all -- an unreadable one still counts, and simply
; has nothing in it.
; ---------------------------------------------------------------------------
zread:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     qword [srclen], 0
    mov     rax, SYS_OPEN
    mov     rdi, rbx
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .missing
    mov     r13, rax
    mov     rdi, rbx
    call    last_dot                    ;-> rax = the suffix, or zero
    test    rax, rax
    jz      .plain
    mov     rdi, rax
    call    which_decoder               ;-> rax = index, or minus one
    cmp     rax, -1
    je      .plain
    mov     r12, rax
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
    mov     rdi, [decoders + r12 * 8]
    mov     rsi, rbx
    call    read_through
    mov     al, 1
    jmp     .out
.plain:
    mov     rdi, r13
    call    read_all
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
    mov     al, 1
    jmp     .out
.missing:
    xor     al, al
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; last_dot: the last dot in rdi, or zero when there is none.
last_dot:
    xor     rax, rax
    xor     rcx, rcx
.byte:
    movzx   edx, byte [rdi + rcx]
    test    dl, dl
    jz      .out
    cmp     dl, '.'
    jne     .step
    lea     rax, [rdi + rcx]
.step:
    inc     rcx
    jmp     .byte
.out:
    ret

; which_decoder: which decompressor the suffix rdi calls for, or minus one.
which_decoder:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rbx
    mov     rsi, suf_bz2
    call    same_string
    test    al, al
    jnz     .bzip
    mov     rdi, rbx
    mov     rsi, suf_gz
    call    same_string
    test    al, al
    jnz     .gzip
    mov     rdi, rbx
    mov     rsi, suf_xz
    call    same_string
    test    al, al
    jnz     .xz
    mov     rax, -1
    pop     rbx
    ret
.bzip:
    xor     rax, rax
    pop     rbx
    ret
.gzip:
    mov     rax, 1
    pop     rbx
    ret
.xz:
    mov     rax, 2
    pop     rbx
    ret

same_string:
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

; read_all: everything the descriptor rdi has, into srcbuf.
read_all:
    push    rbx
    push    r12
    mov     r12, rdi
    mov     rbx, [srclen]
.chunk:
    mov     rax, SYS_READ
    mov     rdi, r12
    lea     rsi, [srcbuf + rbx]
    mov     rdx, 65536
    cmp     rbx, SRCCAP - 65536
    jae     .done
    syscall
    test    rax, rax
    jle     .done
    add     rbx, rax
    jmp     .chunk
.done:
    mov     [srclen], rbx
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; read_through: run the decompressor rdi over the file rsi and keep what it
; writes. Undoing deflate is a job of its own, and the system already has a
; program that does it.
; ---------------------------------------------------------------------------
read_through:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
; the file's name is kept aside, since looking for the decompressor is about
; to write over the buffer it came from
    push    rdi
    mov     rdi, zpathbuf
    call    copy_name
    pop     rdi
    mov     r12, zpathbuf
    mov     rax, SYS_PIPE_ID
    mov     rdi, pipefds
    syscall
    test    rax, rax
    js      .out
    mov     rax, SYS_FORK_ID
    syscall
    test    rax, rax
    js      .closeboth
    jnz     .parent
; the child writes down the pipe and becomes the decompressor
    mov     rax, SYS_DUP2_ID
    mov     edi, [pipefds + 4]
    mov     rsi, STDOUT_FILENO
    syscall
    mov     rax, SYS_CLOSE
    mov     edi, [pipefds]
    syscall
    mov     rax, SYS_CLOSE
    mov     edi, [pipefds + 4]
    syscall
    mov     [argvbuf], rbx
    mov     [argvbuf + 8], r12
    mov     qword [argvbuf + 16], 0
    mov     rdi, rbx
    call    exec_on_path
    mov     rax, SYS_EXIT
    mov     rdi, 127
    syscall
.parent:
    mov     [childpid], rax
    mov     rax, SYS_CLOSE
    mov     edi, [pipefds + 4]
    syscall
    mov     edi, [pipefds]
    call    read_all
    mov     rax, SYS_CLOSE
    mov     edi, [pipefds]
    syscall
    mov     rax, SYS_WAIT4_ID
    mov     rdi, [childpid]
    mov     rsi, statusbuf
    xor     rdx, rdx
    xor     r10, r10
    syscall
    jmp     .out
.closeboth:
    mov     rax, SYS_CLOSE
    mov     edi, [pipefds]
    syscall
    mov     rax, SYS_CLOSE
    mov     edi, [pipefds + 4]
    syscall
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; exec_on_path: try to become the program named rdi, looking for it in each
; directory of PATH. Returns only when none of them worked.
exec_on_path:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     rdi, env_path
    call    getenv_value
    mov     r12, rax
    test    r12, r12
    jnz     .search
    mov     r12, default_path
.search:
    xor     r13, r13                    ;how much of pathbuf is the directory
.component:
    movzx   eax, byte [r12]
    test    al, al
    jz      .last
cmp     al, ':'
    je      .try
    mov     [pathbuf + r13], al
    inc     r13
    inc     r12
    jmp     .component
.try:
    call    .attempt
    inc     r12
    xor     r13, r13
    jmp     .component
.last:
    call    .attempt
    pop     r13
    pop     r12
    pop     rbx
    ret
.attempt:
    mov     byte [pathbuf + r13], '/'
    lea     rdi, [r13 + 1]
    mov     rsi, rbx
    call    path_append
    mov     rax, SYS_EXECVE_ID
    mov     rdi, pathbuf
    mov     rsi, argvbuf
    mov     rdx, [envp]
    syscall
    ret

; ---------------------------------------------------------------------------
; Rendering. Each line is reduced in place: the escapes that stand for a
; character become it, the requests that only change the type are dropped,
; and the ones that break the page turn into a blank line.
; ---------------------------------------------------------------------------
render_page:
    push    rbx
    push    r12
    mov     qword [any], 0
    mov     qword [cell], 0
    mov     qword [example], 0
    xor     rbx, rbx
.line:
    cmp     rbx, [srclen]
    jae     .eof
    mov     r12, rbx
.scan:
    cmp     r12, [srclen]
    jae     .copy
    cmp     byte [srcbuf + r12], WHITESPACE_NL
    je      .withnewline
    inc     r12
    jmp     .scan
.withnewline:
    inc     r12
.copy:
    mov     rdx, r12
    sub     rdx, rbx
    cmp     rdx, LINECAP - 2
    jb      .sized
    mov     rdx, LINECAP - 2
.sized:
    mov     rdi, linebuf
    lea     rsi, [srcbuf + rbx]
    push    rdx
    call    copy_bytes
    pop     rdx
    mov     byte [linebuf + rdx], 0
    mov     qword [linestart], linebuf
    mov     qword [lineptr], linebuf
    call    do_man
    mov     rbx, r12
    jmp     .line
.eof:
    call    newln
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

do_man:
    push    rbx
    push    r12
    cmp     qword [opt_k], 0
    je      .render
    call    k_line
    jmp     .out
.render:
    xor     rbx, rbx
.substitute:
    cmp     rbx, sub_count
    jae     .requests
    mov     rax, rbx
    shl     rax, 1
    mov     rdi, [sub_pairs + rax * 8]
    mov     rsi, [sub_pairs + rax * 8 + 8]
    call    subst
    inc     rbx
    jmp     .substitute
.requests:
    mov     rdi, r_BR
    call    starts_with
    test    al, al
    jz      .checkIP
    mov     rdi, r_BRsp
    call    trim
    mov     rdi, r_space
    mov     rsi, p_empty
    call    subst
.checkIP:
    mov     rdi, r_IP
    call    starts_with
    test    al, al
    jz      .checkIR
    call    newln
    mov     rdi, r_IPsp
    call    trim
.checkIR:
    mov     rdi, r_IR
    call    starts_with
    test    al, al
    jz      .trims
    mov     rdi, r_IRsp
    call    trim
    mov     rdi, r_space
    mov     rsi, p_empty
    call    subst
.trims:
    mov     rdi, r_Bsp
    call    trim
    mov     rdi, r_BIsp
    call    trim
    mov     rdi, r_FNsp
    call    trim
    mov     rdi, r_Isp
    call    trim
    mov     rdi, r_ifn
    call    trim
; the request that decides what happens to the line
    mov     rdi, r_E
    call    starts_with
    test    al, al
    jz      .isPP
    mov     rax, [lineptr]
    xor     rcx, rcx
    cmp     byte [rax + 2], 'X'
    jne     .storeex
    mov     rcx, 1
.storeex:
    mov     [example], rcx
    jmp     .out
.isPP:
    mov     rdi, r_PP
    call    starts_with
    test    al, al
    jz      .isSM
    call    newln
    jmp     .out
.isSM:
    mov     rdi, r_SM
    call    starts_with
    test    al, al
    jnz     .out
    mov     rdi, r_S
    call    starts_with
    test    al, al
    jz      .isso
    call    newln
    mov     rdi, [lineptr]
    add     rdi, 4
    call    put
    call    newln
    jmp     .out
.isso:
    mov     rdi, r_so
    call    starts_with
    test    al, al
    jz      .isTH
    mov     rdi, s_see
    call    put
    mov     rdi, [lineptr]
    add     rdi, 4
    call    base_name
    mov     rdi, rax
    call    put
    jmp     .out
.isTH:
    mov     rdi, r_TH
    call    starts_with
    test    al, al
    jz      .isTP
    mov     rdi, r_dquote
    mov     rsi, r_space
    call    subst
    mov     rdi, [lineptr]
    add     rdi, 4
    call    put
    jmp     .out
.isTP:
    mov     rdi, r_TP
    call    starts_with
    test    al, al
    jz      .isrequest
    call    newln
    mov     qword [cell], 1
    jmp     .out
.isrequest:
    mov     rdi, r_dot
    call    starts_with
    test    al, al
    jnz     .out
    mov     rdi, r_tick
    call    starts_with
    test    al, al
    jnz     .out
    mov     rax, [lineptr]
    cmp     byte [rax], 0
    je      .out
; ordinary text
    cmp     qword [cell], 0
    je      .nocell
    inc     qword [cell]
.nocell:
    cmp     qword [example], 0
    jne     .body
    mov     rdi, r_space
    call    put
.body:
    mov     rdi, [lineptr]
    call    put
.out:
    pop     r12
    pop     rbx
    ret

; newln: end the line that has been building up, and the paragraph with it
; unless a table entry has only just started.
newln:
    cmp     qword [opt_k], 0
    jne     .out
    cmp     qword [any], 0
    je      .reset
    mov     al, WHITESPACE_NL
    call    out_char
    cmp     qword [cell], 2
    je      .reset
    mov     al, WHITESPACE_NL
    call    out_char
.reset:
    mov     qword [any], 0
    mov     qword [cell], 0
.out:
    ret

; put: write out the text at rdi, stopping at the newline unless the page is
; showing an example, where the line breaks are the point.
put:
    push    rbx
    mov     rbx, rdi
.byte:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .out
    cmp     al, WHITESPACE_NL
    jne     .write
    cmp     qword [example], 0
    je      .out
.write:
    mov     [any], rax
    call    out_char
    inc     rbx
    jmp     .byte
.out:
    pop     rbx
    ret

; starts_with: al = 1 when the line begins with rdi.
starts_with:
    mov     rsi, [lineptr]
    jmp     prefix_of

; trim: when the line begins with rdi, step over it.
trim:
    push    rbx
    mov     rbx, rdi
    call    starts_with
    test    al, al
    jz      .out
    mov     rdi, rbx
    call    strlen_of
    add     [lineptr], rax
.out:
    pop     rbx
    ret

; subst: every rdi in the line becomes rsi, which is never the longer of the
; two, so the line can be rewritten where it stands.
subst:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rsi
    mov     rdi, r12
    call    strlen_of
    mov     r14, rax                    ;what is being replaced
    mov     rdi, r13
    call    strlen_of
    mov     r15, rax                    ;what replaces it
    mov     rbx, [lineptr]
    xor     rcx, rcx
.scan:
    movzx   eax, byte [rbx + rcx]
    test    al, al
    jz      .out
    push    rcx
    lea     rdi, [rbx + rcx]
    mov     rsi, r12
    mov     rdx, r14
    call    same_prefix
    pop     rcx
    test    al, al
    jz      .step
    push    rcx
    lea     rdi, [rbx + rcx]
    mov     rsi, r13
    mov     rdx, r15
    call    copy_bytes
    pop     rcx
    lea     rdx, [rcx + r15]            ;where the tail is to land
    lea     rax, [rcx + r14]            ;where the tail is now
    mov     r8, rdx                     ;and where to carry on looking
.shift:
    movzx   ecx, byte [rbx + rax]
    mov     [rbx + rdx], cl
    test    cl, cl
    jz      .shifted
    inc     rax
    inc     rdx
    jmp     .shift
.shifted:
    mov     rcx, r8
    jmp     .scan
.step:
    inc     rcx
    jmp     .scan
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; same_prefix: al = 1 when the rdx bytes at rdi and rsi match.
same_prefix:
    xor     rcx, rcx
.byte:
    cmp     rcx, rdx
    jae     .yes
    mov     al, [rdi + rcx]
    cmp     al, [rsi + rcx]
    jne     .no
    inc     rcx
    jmp     .byte
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; -k: the short description of every page under the manual path. That is the
; first line of a page that is not a request, cut at the dash that separates
; the name from the description, or the page a .so points at.
; ---------------------------------------------------------------------------
keyword_search:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    xor     r12, r12
.path:
    cmp     r12, [manpathcnt]
    jae     .out
    xor     r13, r13
.section:
    cmp     r13, [sectioncnt]
    jae     .nextpath
    xor     rdi, rdi
    mov     rsi, [manpaths + r12 * 8]
    call    path_append
    mov     rdi, rax
    mov     rsi, man_dir
    call    path_append
    mov     rdi, rax
    mov     rsi, [sections + r13 * 8]
    call    path_append
    mov     r14, rax                    ;how long the directory name is
    mov     rax, SYS_OPEN
    mov     rdi, pathbuf
    mov     rsi, O_RDONLY | O_DIRECTORY_FLAG
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .nextsection
    mov     r15, rax
.chunk:
    mov     rax, SYS_GETDENTS_ID
    mov     rdi, r15
    mov     rsi, dirbuf
    mov     rdx, DIRCAP
    syscall
    test    rax, rax
    jle     .closedir
    mov     rbx, rax
    push    rbx
    xor     rbx, rbx
.entry:
    cmp     rbx, [rsp]
    jae     .nextchunk
    lea     rdi, [dirbuf + rbx + 19]
    cmp     byte [rdi], '.'
    je      .nextentry
    mov     rsi, rdi
    mov     rdi, namebuf
    call    copy_name
    mov     qword [k_name], namebuf
    mov     rdi, r14
    mov     rsi, r_slash
    call    path_append
    mov     rdi, rax
    mov     rsi, namebuf
    call    path_append
    mov     rdi, pathbuf
    call    zread
    test    al, al
    jz      .nextentry
    mov     qword [k_done], 0
    call    render_page
.nextentry:
    movzx   eax, word [dirbuf + rbx + 16]
    add     rbx, rax
    jmp     .entry
.nextchunk:
    pop     rbx
    jmp     .chunk
.closedir:
    mov     rax, SYS_CLOSE
    mov     rdi, r15
    syscall
.nextsection:
    inc     r13
    jmp     .section
.nextpath:
    inc     r12
    jmp     .path
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

copy_name:
    xor     rax, rax
.byte:
    movzx   ecx, byte [rsi + rax]
    mov     [rdi + rax], cl
    test    cl, cl
    jz      .out
    inc     rax
    jmp     .byte
.out:
    ret

; k_line: one line of a page being read for its description. Only the first
; line that could be one is looked at.
k_line:
    push    rbx
    push    r12
    cmp     qword [k_done], 0
    jne     .out
    mov     rdi, r_dot
    call    starts_with
    test    al, al
    jnz     .maybeso
    mov     rdi, r_tick
    call    starts_with
    test    al, al
    jnz     .out
    mov     rdi, [linestart]
    mov     rsi, s_dashsp
    call    find_substring              ;-> rax, or zero
    mov     rbx, rax
    mov     qword [k_done], 2
    test    rbx, rbx
    jz      .nodash
    mov     [lineptr], rbx
.nodash:
    call    k_matches
    test    al, al
    jz      .out
    mov     rdi, [k_name]
    call    out_str
    mov     al, WHITESPACE_SPACE
    call    out_char
    test    rbx, rbx
    jnz     .justline
    mov     rdi, s_dashsp
    call    out_str
.justline:
    mov     rdi, [lineptr]
    call    out_str
    jmp     .out
.maybeso:
    mov     rdi, r_so
    call    starts_with
    test    al, al
    jz      .out
    mov     rdi, [linestart]
    add     rdi, 4
    call    base_name
    mov     [lineptr], rax
    mov     qword [k_done], 2
    call    k_matches
    test    al, al
    jz      .out
    mov     rdi, [k_name]
    call    out_str
    mov     rdi, s_seek
    call    out_str
    mov     rdi, [lineptr]
    call    out_str
.out:
    pop     r12
    pop     rbx
    ret

; k_matches: does the keyword turn up in the file's name or in the line?
k_matches:
    push    rbx
    mov     rdi, [opt_k]
    mov     rsi, [k_name]
    call    re_search
    test    al, al
    jnz     .yes
    mov     rdi, [opt_k]
    mov     rsi, [lineptr]
    call    re_search
    pop     rbx
    ret
.yes:
    mov     al, 1
    pop     rbx
    ret

; find_substring: where rsi first turns up inside rdi, or zero.
find_substring:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, r12
    call    strlen_of
    mov     r13, rax
    xor     rcx, rcx
.at:
    movzx   eax, byte [rbx + rcx]
    test    al, al
    jz      .none
    push    rcx
    lea     rdi, [rbx + rcx]
    mov     rsi, r12
    mov     rdx, r13
    call    same_prefix
    pop     rcx
    test    al, al
    jnz     .found
    inc     rcx
    jmp     .at
.found:
    lea     rax, [rbx + rcx]
    pop     r13
    pop     r12
    pop     rbx
    ret
.none:
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; A small regular expression matcher, enough for what -k is given: literal
; text, a dot, a repeat, a bracketed set and the two anchors, matched
; without regard to case.
; ---------------------------------------------------------------------------

; re_search: does the pattern rdi turn up anywhere in the text rsi?
re_search:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    cmp     byte [rbx], '^'
    jne     .anywhere
    lea     rdi, [rbx + 1]
    mov     rsi, r12
    call    re_here
    pop     r12
    pop     rbx
    ret
.anywhere:
    mov     rdi, rbx
    mov     rsi, r12
    call    re_here
    test    al, al
    jnz     .yes
    cmp     byte [r12], 0
    je      .no
    inc     r12
    jmp     .anywhere
.yes:
    mov     al, 1
    pop     r12
    pop     rbx
    ret
.no:
    xor     al, al
    pop     r12
    pop     rbx
    ret

; re_here: does the pattern rdi fit the text rsi starting where it stands?
re_here:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    movzx   eax, byte [rbx]
    test    al, al
    jz      .yes
    cmp     al, '$'
    jne     .atom
    cmp     byte [rbx + 1], 0
    jne     .atom
    cmp     byte [r12], 0
    je      .yes
    cmp     byte [r12], WHITESPACE_NL
    jne     .no
    cmp     byte [r12 + 1], 0
    je      .yes
    jmp     .no
.atom:
    mov     rdi, rbx
    call    re_atom_len
    mov     r13, rax
    cmp     byte [rbx + r13], '*'
    je      .star
    cmp     byte [r12], 0
    je      .no
    mov     rdi, rbx
    movzx   esi, byte [r12]
    call    re_atom_match
    test    al, al
    jz      .no
    lea     rdi, [rbx + r13]
    lea     rsi, [r12 + 1]
    call    re_here
    jmp     .done
.star:
    xor     r14, r14                    ;how many the repeat can swallow
.count:
    movzx   eax, byte [r12 + r14]
    test    al, al
    jz      .counted
    mov     rdi, rbx
    movzx   esi, al
    call    re_atom_match
    test    al, al
    jz      .counted
    inc     r14
    jmp     .count
.counted:
    lea     rdi, [rbx + r13 + 1]
    lea     rsi, [r12 + r14]
    call    re_here
    test    al, al
    jnz     .yes
    test    r14, r14
    jz      .no
    dec     r14
    jmp     .counted
.yes:
    mov     al, 1
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.no:
    xor     al, al
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; re_atom_len: how much of the pattern at rdi one piece takes up.
re_atom_len:
    movzx   eax, byte [rdi]
    cmp     al, '\'
    je      .escaped
    cmp     al, '['
    je      .bracket
    mov     rax, 1
    ret
.escaped:
    mov     rax, 2
    ret
.bracket:
    mov     rcx, 1
    cmp     byte [rdi + rcx], '^'
    jne     .firstitem
    inc     rcx
.firstitem:
    cmp     byte [rdi + rcx], ']'
    jne     .items
    inc     rcx
.items:
    movzx   eax, byte [rdi + rcx]
    test    al, al
    jz      .ended
    cmp     al, ']'
    je      .ended
    inc     rcx
    jmp     .items
.ended:
    lea     rax, [rcx + 1]
    ret

; re_atom_match: does the piece at rdi accept the byte rsi?
re_atom_match:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    movzx   eax, byte [rbx]
    cmp     al, '.'
    je      .yes
    cmp     al, '['
    je      .bracket
    cmp     al, '\'
    jne     .literal
    movzx   eax, byte [rbx + 1]
.literal:
    call    fold_case
    mov     rcx, rax
    mov     rax, r12
    call    fold_case
    cmp     al, cl
    jne     .no
.yes:
    mov     al, 1
    pop     r12
    pop     rbx
    ret
.no:
    xor     al, al
    pop     r12
    pop     rbx
    ret
.bracket:
    mov     rcx, 1
    xor     rdx, rdx                    ;whether the set is turned inside out
    cmp     byte [rbx + rcx], '^'
    jne     .scan
    mov     rdx, 1
    inc     rcx
.scan:
    xor     r8, r8                      ;whether the byte was found
.item:
    movzx   eax, byte [rbx + rcx]
    test    al, al
    jz      .decide
    cmp     al, ']'
    jne     .notend
    cmp     rcx, 1
    je      .single
    mov     r9, rcx
    dec     r9
    cmp     byte [rbx + r9], '^'
    je      .single
    jmp     .decide
.notend:
    cmp     byte [rbx + rcx + 1], '-'
    jne     .single
    cmp     byte [rbx + rcx + 2], ']'
    je      .single
    movzx   r9d, byte [rbx + rcx + 2]
    mov     r10, rax
    call    range_holds
    test    al, al
    jz      .skiprange
    mov     r8, 1
.skiprange:
    add     rcx, 3
    jmp     .item
.single:
    push    rcx
    push    rdx
    push    r8
    call    fold_case
    mov     rcx, rax
    mov     rax, r12
    call    fold_case
    cmp     al, cl
    pop     r8
    pop     rdx
    pop     rcx
    jne     .skipone
    mov     r8, 1
.skipone:
    inc     rcx
    jmp     .item
.decide:
    test    rdx, rdx
    jz      .plain
    xor     r8, 1
.plain:
    test    r8, r8
    jnz     .yes
    jmp     .no

; range_holds: does the byte r12 fall between rax and r9, either case?
range_holds:
    push    rbx
    push    rcx
    push    rdx
    mov     rbx, rax
    call    fold_case
    mov     rbx, rax
    mov     rax, r9
    call    fold_case
    mov     rcx, rax
    mov     rax, r12
    call    fold_case
    xor     rdx, rdx
    cmp     al, bl
    jb      .out
    cmp     al, cl
    ja      .out
    mov     rdx, 1
.out:
    mov     rax, rdx
    pop     rdx
    pop     rcx
    pop     rbx
    ret

fold_case:
    cmp     al, 'A'
    jb      .out
    cmp     al, 'Z'
    ja      .out
    add     al, 32
.out:
    movzx   eax, al
    ret

; ---------------------------------------------------------------------------
; Output, buffered.
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
