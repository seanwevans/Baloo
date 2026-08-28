; src/diff.asm -- diff(1): report the differences between two files.
; Usage: diff [-u|-U N] [-q] [-r] [-L LABEL] [--label LABEL]
;             [--strip-trailing-cr] [--no-dereference]
;             [--show-function-line=RE] [--unchanged-line-format=FMT]
;             [--old-line-format=FMT] [--new-line-format=FMT] FILE1 FILE2
;
; The common subsequence is found with Hunt-Szymanski rather than the usual
; edit-distance walk: each line is hashed, every line of the second file is
; looked up among the first file's lines with the same hash, and a threshold
; table extended by binary search. That costs about (matches + lines) log
; lines, so a hundred thousand lines against a quarter of them stays quick,
; where an edit-distance algorithm would be quadratic in the difference.
;
; Exit status is 0 when the files match, 1 when they differ and 2 when diff
; could not do the comparison at all.

    %include "include/sysdefs.inc"

    %define SYS_LSTAT 6
    %define SYS_FSTAT 5

    %define FILECAP (16 * 1024 * 1024)
    %define MAXLINES 200000
    %define HASHBITS 18
    %define HASHSIZE (1 << HASHBITS)
    %define HASHMASK (HASHSIZE - 1)
    %define MAXNODES 1000000
    %define MAXEDITS (2 * MAXLINES)
    %define MAXHUNKS 100000
    %define OUTCAP 262144
    %define OUTHIGH (OUTCAP - 8192)
    %define PATHCAP 4096
    %define FMTCAP 1024
    %define MAXELEM 256
    %define MAXCLASS 32
    %define DIRCAP 65536
    %define MAXNAMES 20000
    %define NAMEARENA (4 * 1024 * 1024)
    %define LISTARENA (2 * 1024 * 1024)

    %define ST_MODE 24
    %define S_IFMT 0o170000
    %define S_IFIFO 0o010000
    %define S_IFCHR 0o020000
    %define S_IFDIR 0o040000
    %define S_IFBLK 0o060000
    %define S_IFREG 0o100000
    %define S_IFLNK 0o120000
    %define S_IFSOCK 0o140000

    %define ED_KEEP 0
    %define ED_DEL 1
    %define ED_INS 2

    %define T_LIT 0
    %define T_ANY 1
    %define T_CLASS 2
    %define T_BOL 3
    %define T_EOL 4

    struc dirent64
    .d_ino      resq 1
    .d_off      resq 1
    .d_reclen   resw 1
    .d_type     resb 1
    .d_name     resb 1
    endstruc

section .bss
    fileA       resb FILECAP
    fileB       resb FILECAP
    offA        resq MAXLINES
    lenA        resq MAXLINES
    hashA       resq MAXLINES
    offB        resq MAXLINES
    lenB        resq MAXLINES
    hashB       resq MAXLINES
    chain       resq MAXLINES
    buckets     resq HASHSIZE
    thresh      resq (MAXLINES + 2)
    linkk       resq (MAXLINES + 2)
    nodes       resq (3 * MAXNODES)
    edits       resb MAXEDITS
    hunks       resq (6 * MAXHUNKS)
    outbuf      resb OUTCAP
    pathA       resb PATHCAP
    pathB       resb PATHCAP
    linkbufA    resb PATHCAP
    linkbufB    resb PATHCAP
    stA         resb 160
    stB         resb 160
    namearena   resb NAMEARENA
    listarena   resb LISTARENA
    listfree    resq 1
    pairA       resq MAXLINES
    pairB       resq MAXLINES
    hash_out    resq 1
    rx_compiled resq 1
    chg_edit    resq 1
    chg_a       resq 1
    chg_b       resq 1
    chg_dels    resq 1
    chg_inss    resq 1
    dirbuf      resb DIRCAP
    numbuf      resb 64
    e_type      resb MAXELEM
    e_ch        resb MAXELEM
    e_cls       resb MAXELEM
    e_star      resb MAXELEM
    classes     resb (MAXCLASS * 32)
    nelem       resq 1
    nclass      resq 1
    rx_subj     resq 1
    rx_len      resq 1
    nlinesA     resq 1
    nlinesB     resq 1
    lenAfile    resq 1
    lenBfile    resq 1
    nedits      resq 1
    nhunks      resq 1
    nnodes      resq 1
    lcslen      resq 1
    outlen      resq 1
    ctxlines    resq 1
    labelA      resq 1
    labelB      resq 1
    nlabels     resq 1
    pathAlen    resq 1
    pathBlen    resq 1
    namefree    resq 1
    fmt_same    resq 1
    fmt_old     resq 1
    fmt_new     resq 1
    funcre      resq 1
    operand1    resq 1
    operand2    resq 1
    noperands   resq 1
    status      resb 1
    opt_unified resb 1
    opt_brief   resb 1
    opt_recurse resb 1
    opt_stripcr resb 1
    opt_nodrf   resb 1
    have_fmt    resb 1
    reported    resb 1

section .data
    l_label     db "--label", 0
    l_stripcr   db "--strip-trailing-cr", 0
    l_nodrf     db "--no-dereference", 0
    l_unified   db "--unified", 0
    l_brief     db "--brief", 0
    l_recurse   db "--recursive", 0
    l_samefmt   db "--unchanged-line-format", 0
    l_oldfmt    db "--old-line-format", 0
    l_newfmt    db "--new-line-format", 0
    l_funcline  db "--show-function-line", 0
    l_text      db "--text", 0

    s_dash      db "-", 0
    s_minus3    db "--- ", 0
    s_plus3     db "+++ ", 0
    s_at        db "@@ -", 0
    s_atplus    db " +", 0
    s_atend     db " @@", 0
    s_files     db "Files ", 0
    s_and       db " and ", 0
    s_differ    db " differ", 10, 0
    s_symlinks  db "Symbolic links ", 0
    s_file1     db "File ", 0
    s_isa       db " is a ", 0
    s_while     db " while file ", 0
    s_onlyin    db "Only in ", 0
s_onlysep   db ": ", 0
    s_sep3      db "---", 10, 0
    s_lt        db "< ", 0
    s_gt        db "> ", 0
    s_diffhdr   db "diff ", 0

    t_regular   db "regular file", 0
    t_symlink   db "symbolic link", 0
    t_fifo      db "fifo", 0
    t_dir       db "directory", 0
    t_chardev   db "character special file", 0
    t_blockdev  db "block special file", 0
    t_socket    db "socket", 0
    t_unknown   db "special file", 0

e_open_pre  db "diff: ", 0
e_open_post db ": No such file or directory", 10, 0
e_badopt    db "diff: unrecognized option", 10
    e_badopt_len equ $ - e_badopt
e_usage     db "Usage: diff [-u] [-q] [-r] FILE1 FILE2", 10
    e_usage_len equ $ - e_usage

section .text
global _start

_start:
    mov     qword [ctxlines], 3
    mov     qword [namefree], namearena
    mov     qword [listfree], listarena

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    jle     ready
    mov     rdi, [r13]
    test    rdi, rdi
    jz      ready
    cmp     byte [rdi], '-'
    jne     .operand
    cmp     byte [rdi + 1], 0
    je      .operand                    ;"-" is standard input
    cmp     byte [rdi + 1], '-'
    jne     .short
    cmp     byte [rdi + 2], 0
    jne     .long
    add     r13, 8                      ;"--" ends the options
    dec     r12
    jmp     .tail
.long:
    mov     rsi, l_label
    call    longmatch
    test    al, al
    jnz     .set_label
    mov     rsi, l_stripcr
    call    longmatch
    test    al, al
    jnz     .set_stripcr
    mov     rsi, l_nodrf
    call    longmatch
    test    al, al
    jnz     .set_nodrf
    mov     rsi, l_unified
    call    longmatch
    test    al, al
    jnz     .set_unified
    mov     rsi, l_brief
    call    longmatch
    test    al, al
    jnz     .set_brief
    mov     rsi, l_recurse
    call    longmatch
    test    al, al
    jnz     .set_recurse
    mov     rsi, l_samefmt
    call    longmatch
    test    al, al
    jnz     .set_samefmt
    mov     rsi, l_oldfmt
    call    longmatch
    test    al, al
    jnz     .set_oldfmt
    mov     rsi, l_newfmt
    call    longmatch
    test    al, al
    jnz     .set_newfmt
    mov     rsi, l_funcline
    call    longmatch
    test    al, al
    jnz     .set_funcline
    mov     rsi, l_text
    call    longmatch
    test    al, al
    jnz     .next
    jmp     bad_option
.set_label:
    cmp     al, 2
    je      .label_have
    call    next_value
.label_have:
    call    add_label
    jmp     .next
.set_stripcr:
    mov     byte [opt_stripcr], 1
    jmp     .next
.set_nodrf:
    mov     byte [opt_nodrf], 1
    jmp     .next
.set_unified:
    mov     byte [opt_unified], 1
    jmp     .next
.set_brief:
    mov     byte [opt_brief], 1
    jmp     .next
.set_recurse:
    mov     byte [opt_recurse], 1
    jmp     .next
.set_samefmt:
    cmp     al, 2
    je      .samefmt_have
    call    next_value
.samefmt_have:
    mov     [fmt_same], rdx
    mov     byte [have_fmt], 1
    jmp     .next
.set_oldfmt:
    cmp     al, 2
    je      .oldfmt_have
    call    next_value
.oldfmt_have:
    mov     [fmt_old], rdx
    mov     byte [have_fmt], 1
    jmp     .next
.set_newfmt:
    cmp     al, 2
    je      .newfmt_have
    call    next_value
.newfmt_have:
    mov     [fmt_new], rdx
    mov     byte [have_fmt], 1
    jmp     .next
.set_funcline:
    cmp     al, 2
    je      .func_have
    call    next_value
.func_have:
    mov     [funcre], rdx
    jmp     .next

.short:
    lea     rsi, [rdi + 1]
.flag:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .next
    inc     rsi
    cmp     al, 'u'
    je      .f_u
    cmp     al, 'U'
    je      .f_U
    cmp     al, 'q'
    je      .f_q
    cmp     al, 'r'
    je      .f_r
    cmp     al, 'L'
    je      .f_L
    cmp     al, 'N'
    je      .flag
    cmp     al, 'a'
    je      .flag
    jmp     bad_option
.f_u:
    mov     byte [opt_unified], 1
    jmp     .flag
.f_U:
    mov     byte [opt_unified], 1
    call    opt_value
    mov     rdi, rdx
    call    atou
    mov     [ctxlines], rax
    jmp     .next
.f_q:
    mov     byte [opt_brief], 1
    jmp     .flag
.f_r:
    mov     byte [opt_recurse], 1
    jmp     .flag
.f_L:
    call    opt_value
    call    add_label
    jmp     .next
.operand:
    call    add_operand
.next:
    add     r13, 8
    dec     r12
    jmp     parse
.tail:
    cmp     r12, 0
    jle     ready
    mov     rdi, [r13]
    test    rdi, rdi
    jz      ready
    call    add_operand
    add     r13, 8
    dec     r12
    jmp     .tail

add_label:
    mov     rcx, [nlabels]
    cmp     rcx, 2
    jae     .out
    mov     [labelA + rcx * 8], rdx
    inc     rcx
    mov     [nlabels], rcx
.out:
    ret

add_operand:
    mov     rcx, [noperands]
    cmp     rcx, 2
    jae     .out
    mov     [operand1 + rcx * 8], rdi
    inc     rcx
    mov     [noperands], rcx
.out:
    ret

opt_value:
    cmp     byte [rsi], 0
    je      next_value
    mov     rdx, rsi
    ret

next_value:
    add     r13, 8
    dec     r12
    mov     rdx, [r13]
    test    rdx, rdx
    jz      bad_usage
    ret

longmatch:
    push    rdi
    push    rsi
.scan:
    mov     al, [rsi]
    test    al, al
    jz      .end
    cmp     al, [rdi]
    jne     .no
    inc     rsi
    inc     rdi
    jmp     .scan
.end:
    cmp     byte [rdi], 0
    je      .bare
    cmp     byte [rdi], '='
    jne     .no
    lea     rdx, [rdi + 1]
    pop     rsi
    pop     rdi
    mov     al, 2
    ret
.bare:
    pop     rsi
    pop     rdi
    mov     al, 1
    ret
.no:
    pop     rsi
    pop     rdi
    xor     al, al
    ret

bad_option:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, e_badopt
    mov     rdx, e_badopt_len
    syscall
    exit    2

bad_usage:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, e_usage
    mov     rdx, e_usage_len
    syscall
    exit    2

ready:
    cmp     qword [noperands], 2
    jne     bad_usage
    mov     rdi, [operand1]
    call    set_pathA
    mov     rdi, [operand2]
    call    set_pathB
; comparing something with itself, "-" included, has nothing to report
    mov     rdi, [operand1]
    mov     rsi, [operand2]
    call    streq
    test    al, al
    jnz     .done
    call    compare_paths
.done:
    call    out_flush
    movzx   edi, byte [status]
    mov     rax, SYS_EXIT
    syscall

; ---------------------------------------------------------------------------
; compare_paths: stat both operands, reject mismatched kinds, and either walk
; two directories or diff two files.
; ---------------------------------------------------------------------------
compare_paths:
    push    rbx
    mov     rdi, pathA
    mov     rsi, stA
    call    stat_path
    test    al, al
    jz      .missingA
    mov     rdi, pathB
    mov     rsi, stB
    call    stat_path
    test    al, al
    jz      .missingB
    mov     eax, [stA + ST_MODE]
    and     eax, S_IFMT
    mov     ebx, [stB + ST_MODE]
    and     ebx, S_IFMT
    cmp     rax, S_IFDIR
    jne     .checkB
    cmp     rbx, S_IFDIR
    jne     .mismatch
    call    compare_dirs
    jmp     .out
.checkB:
    cmp     rbx, S_IFDIR
    je      .mismatch
; anything that can be read as a stream is compared by content, so a fifo and
; a regular file are diffed rather than called a mismatch. Only a symlink,
; which needs --no-dereference to survive the stat, stands apart.
    cmp     rax, S_IFLNK
    je      .aislink
    cmp     rbx, S_IFLNK
    je      .mismatch
    call    compare_files
    jmp     .out
.aislink:
    cmp     rbx, S_IFLNK
    jne     .mismatch
    jmp     .symlinks
.out:
    pop     rbx
    ret
.symlinks:
; with --no-dereference two links match only when they point the same way
    mov     rdi, pathA
    mov     rsi, linkbufA
    call    read_link
    mov     rdi, pathB
    mov     rsi, linkbufB
    call    read_link
    mov     rdi, linkbufA
    mov     rsi, linkbufB
    call    streq
    test    al, al
    jnz     .out
    mov     byte [status], 1
    mov     rsi, s_symlinks
    call    out_str
    mov     rsi, pathA
    call    out_str
    mov     rsi, s_and
    call    out_str
    mov     rsi, pathB
    call    out_str
    mov     rsi, s_differ
    call    out_str
    jmp     .out
.mismatch:
    mov     byte [status], 1
    mov     rsi, s_file1
    call    out_str
    mov     rsi, pathA
    call    out_str
    mov     rsi, s_isa
    call    out_str
    mov     eax, [stA + ST_MODE]
    call    type_name
    call    out_str
    mov     rsi, s_while
    call    out_str
    mov     rsi, pathB
    call    out_str
    mov     rsi, s_isa
    call    out_str
    mov     eax, [stB + ST_MODE]
    call    type_name
    call    out_str
    mov     al, WHITESPACE_NL
    call    out_char
    jmp     .out
.missingA:
    mov     rdi, pathA
    call    warn_missing
    mov     byte [status], 2
    jmp     .out
.missingB:
    mov     rdi, pathB
    call    warn_missing
    mov     byte [status], 2
    jmp     .out

; stat_path: stat rdi into rsi, honouring --no-dereference and reading "-"
; from standard input. al = 1 on success.
stat_path:
    push    rsi
    cmp     byte [rdi], '-'
    jne     .named
    cmp     byte [rdi + 1], 0
    jne     .named
    mov     rax, SYS_FSTAT              ;"-" is whatever stdin happens to be
    mov     rdi, STDIN_FILENO
    syscall
    jmp     .check
.named:
    mov     rax, SYS_STAT
    cmp     byte [opt_nodrf], 0
    je      .go
    mov     rax, SYS_LSTAT
.go:
    syscall
.check:
    pop     rsi
    test    rax, rax
    js      .fail
    mov     al, 1
    ret
.fail:
    xor     al, al
    ret

; type_name: the name diff uses for the file kind in eax.
type_name:
    and     eax, S_IFMT
    cmp     eax, S_IFREG
    je      .reg
    cmp     eax, S_IFLNK
    je      .lnk
    cmp     eax, S_IFIFO
    je      .fifo
    cmp     eax, S_IFDIR
    je      .dir
    cmp     eax, S_IFCHR
    je      .chr
    cmp     eax, S_IFBLK
    je      .blk
    cmp     eax, S_IFSOCK
    je      .sock
    mov     rsi, t_unknown
    ret
.reg:
    mov     rsi, t_regular
    ret
.lnk:
    mov     rsi, t_symlink
    ret
.fifo:
    mov     rsi, t_fifo
    ret
.dir:
    mov     rsi, t_dir
    ret
.chr:
    mov     rsi, t_chardev
    ret
.blk:
    mov     rsi, t_blockdev
    ret
.sock:
    mov     rsi, t_socket
    ret

read_link:
    push    rsi
    mov     rax, SYS_READLINK
    mov     rdx, PATHCAP - 1
    syscall
    pop     rsi
    test    rax, rax
    js      .empty
    mov     byte [rsi + rax], 0
    ret
.empty:
    mov     byte [rsi], 0
    ret

warn_missing:
    push    rdi
    mov     rsi, e_open_pre
    call    err_str
    pop     rsi
    call    err_str
    mov     rsi, e_open_post
    jmp     err_str

err_str:
    push    rsi
    mov     rdi, rsi
    call    strlen_z
    mov     rdx, rax
    pop     rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    ret

; ---------------------------------------------------------------------------
; compare_files: load both sides, match them up and print whatever the
; selected output mode wants.
; ---------------------------------------------------------------------------
compare_files:
    mov     rdi, pathA
    mov     rsi, fileA
    call    slurp
    cmp     rax, -1
    je      .failA
    mov     [lenAfile], rax
    mov     rdi, fileA
    mov     rsi, rax
    mov     rdx, offA
    mov     rcx, lenA
    mov     r8, hashA
    call    split_lines
    mov     [nlinesA], rax

    mov     rdi, pathB
    mov     rsi, fileB
    call    slurp
    cmp     rax, -1
    je      .failB
    mov     [lenBfile], rax
    mov     rdi, fileB
    mov     rsi, rax
    mov     rdx, offB
    mov     rcx, lenB
    mov     r8, hashB
    call    split_lines
    mov     [nlinesB], rax

    call    build_lcs
    call    build_edits
    cmp     byte [have_fmt], 0
    jne     .lineformat
    call    any_change
    test    al, al
    jz      .same
    mov     byte [status], 1
    cmp     byte [opt_brief], 0
    je      .full
    mov     rsi, s_files
    call    out_str
    mov     rsi, pathA
    call    out_str
    mov     rsi, s_and
    call    out_str
    mov     rsi, pathB
    call    out_str
    mov     rsi, s_differ
    call    out_str
    ret
.full:
    call    build_hunks
    cmp     byte [opt_unified], 0
    jne     .unified
    call    print_normal
    ret
.unified:
    call    print_unified
    ret
.lineformat:
    call    any_change
    test    al, al
    jz      .fmtprint
    mov     byte [status], 1
.fmtprint:
    call    print_line_formats
    ret
.same:
    ret
.failA:
    mov     rdi, pathA
    call    warn_missing
    mov     byte [status], 2
    ret
.failB:
    mov     rdi, pathB
    call    warn_missing
    mov     byte [status], 2
    ret

; any_change: al = 1 when the edit script is not all matches.
any_change:
    xor     rcx, rcx
.scan:
    cmp     rcx, [nedits]
    jge     .no
    cmp     byte [edits + rcx], ED_KEEP
    jne     .yes
    inc     rcx
    jmp     .scan
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; slurp: read the whole of rdi into rsi. "-" reads standard input. rax is the
; byte count, or -1 when the file could not be opened.
; ---------------------------------------------------------------------------
slurp:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    cmp     byte [rdi], '-'
    jne     .open
    cmp     byte [rdi + 1], 0
    jne     .open
    mov     r13, STDIN_FILENO
    jmp     .read
.open:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fail
    mov     r13, rax
.read:
    xor     rbx, rbx
.chunk:
    mov     rdx, FILECAP
    sub     rdx, rbx
    jz      .close
    mov     rax, SYS_READ
    mov     rdi, r13
    lea     rsi, [r12 + rbx]
    syscall
    test    rax, rax
    jle     .close
    add     rbx, rax
    jmp     .chunk
.close:
    cmp     r13, STDIN_FILENO
    je      .done
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
.done:
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret
.fail:
    mov     rax, -1
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; split_lines: index the rsi bytes at rdi into the offset, length and hash
; arrays at rdx, rcx and r8. rax is the line count. With
; --strip-trailing-cr the carriage return is dropped before hashing, so the
; two line endings compare equal.
; ---------------------------------------------------------------------------
split_lines:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi                    ;text
    mov     r13, rsi                    ;length
    mov     r14, rdx                    ;offsets
    mov     r15, rcx                    ;lengths
    mov     [hash_out], r8
    xor     rbx, rbx                    ;cursor
    xor     r9, r9                      ;line count
.line:
    cmp     rbx, r13
    jae     .done
    cmp     r9, MAXLINES
    jae     .done
    mov     [r14 + r9 * 8], rbx
    mov     rcx, rbx
.scan:
    cmp     rcx, r13
    jae     .end
    cmp     byte [r12 + rcx], WHITESPACE_NL
    je      .end
    inc     rcx
    jmp     .scan
.end:
    mov     rax, rcx
    sub     rax, rbx                    ;length without the newline
    cmp     byte [opt_stripcr], 0
    je      .store
    test    rax, rax
    jz      .store
    mov     rdx, rbx
    add     rdx, rax
    dec     rdx
    cmp     byte [r12 + rdx], 13
    jne     .store
    dec     rax
.store:
    mov     [r15 + r9 * 8], rax
    push    rcx
    push    r9
    lea     rdi, [r12 + rbx]
    mov     rsi, rax
    call    hash_line
    pop     r9
    pop     rcx
    mov     rdx, [hash_out]
    mov     [rdx + r9 * 8], rax
    inc     r9
    lea     rbx, [rcx + 1]              ;past the newline
    jmp     .line
.done:
    mov     rax, r9
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; hash_line: FNV-1a over the rsi bytes at rdi.
hash_line:
    mov     rax, 0xcbf29ce484222325
    mov     r10, 0x100000001b3
    xor     rcx, rcx
.byte:
    cmp     rcx, rsi
    jae     .out
    movzx   edx, byte [rdi + rcx]
    xor     rax, rdx
    mul     r10
    inc     rcx
    jmp     .byte
.out:
    ret

; line_equal: are line r8 of A and line r9 of B the same text?
line_equal:
    mov     rax, [hashA + r8 * 8]
    cmp     rax, [hashB + r9 * 8]
    jne     .no
    mov     rcx, [lenA + r8 * 8]
    cmp     rcx, [lenB + r9 * 8]
    jne     .no
    mov     rsi, [offA + r8 * 8]
    add     rsi, fileA
    mov     rdi, [offB + r9 * 8]
    add     rdi, fileB
    xor     rdx, rdx
.byte:
    cmp     rdx, rcx
    jae     .yes
    mov     al, [rsi + rdx]
    cmp     al, [rdi + rdx]
    jne     .no
    inc     rdx
    jmp     .byte
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; build_lcs: Hunt-Szymanski. Every line of A is filed under its hash; then
; each line of B walks its matching A positions from the highest down,
; extending a table of "smallest A index ending a common run of length k".
; Because that table is sorted, the right k is a binary search away.
; ---------------------------------------------------------------------------
build_lcs:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    xor     rcx, rcx
.clearbuckets:
    cmp     rcx, HASHSIZE
    jae     .fill
    mov     qword [buckets + rcx * 8], -1
    inc     rcx
    jmp     .clearbuckets
.fill:
; prepend each A line to its bucket so the chain runs from high index to low
    xor     rbx, rbx
.fileline:
    cmp     rbx, [nlinesA]
    jge     .init
    mov     rax, [hashA + rbx * 8]
    and     rax, HASHMASK
    mov     rcx, [buckets + rax * 8]
    mov     [chain + rbx * 8], rcx
    mov     [buckets + rax * 8], rbx
    inc     rbx
    jmp     .fileline
.init:
    mov     qword [thresh], -1
    mov     qword [linkk], 0
    mov     qword [lcslen], 0
    mov     qword [nnodes], 1           ;node 0 is the empty chain
    xor     r15, r15                    ;line of B
.bline:
    cmp     r15, [nlinesB]
    jge     .done
    mov     rax, [hashB + r15 * 8]
    and     rax, HASHMASK
    mov     r14, [buckets + rax * 8]
.candidate:
    cmp     r14, 0
    jl      .bnext
    mov     r8, r14
    mov     r9, r15
    call    line_equal
    test    al, al
    jz      .chainnext
    call    extend_thresh
.chainnext:
    mov     r14, [chain + r14 * 8]
    jmp     .candidate
.bnext:
    inc     r15
    jmp     .bline
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; extend_thresh: A line r14 matches B line r15. Find where it fits in the
; threshold table and record the link if it improves on what is there.
extend_thresh:
    push    rbx
    push    r12
    push    r13
    mov     rbx, 1                      ;low
    mov     r12, [lcslen]               ;high
.search:
    cmp     rbx, r12
    jg      .found
    mov     rax, rbx
    add     rax, r12
    shr     rax, 1                      ;mid
    mov     rcx, [thresh + rax * 8]
    cmp     rcx, r14
    jge     .high
    lea     rbx, [rax + 1]
    jmp     .search
.high:
    lea     r12, [rax - 1]
    jmp     .search
.found:
    mov     r13, rbx                    ;the run length this match can reach
    cmp     r13, [lcslen]
    jg      .place
    mov     rcx, [thresh + r13 * 8]
    cmp     r14, rcx
    jge     .out                        ;an earlier match already ends here
.place:
    mov     [thresh + r13 * 8], r14
    mov     rax, [nnodes]
    cmp     rax, MAXNODES
    jae     .out
    mov     rcx, rax
    imul    rcx, rcx, 3
    mov     [nodes + rcx * 8], r14
    mov     [nodes + rcx * 8 + 8], r15
    mov     rdx, r13
    dec     rdx
    mov     rdx, [linkk + rdx * 8]
    mov     [nodes + rcx * 8 + 16], rdx
    mov     [linkk + r13 * 8], rax
    inc     qword [nnodes]
    cmp     r13, [lcslen]
    jle     .out
    mov     [lcslen], r13
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; build_edits: turn the matched pairs into a flat script of keeps, deletes
; and inserts. The chain runs backwards, so it is reversed into pairbuf
; first.
; ---------------------------------------------------------------------------
build_edits:
    push    rbx
    push    r12
    push    r13
    mov     rax, [lcslen]
    mov     rcx, [linkk + rax * 8]
    mov     rbx, rax                    ;fill pairbuf from the end
.walk:
    test    rcx, rcx
    jz      .emit
    dec     rbx
    mov     rax, rcx
    imul    rax, rax, 3
    mov     rdx, [nodes + rax * 8]
    mov     [pairA + rbx * 8], rdx
    mov     rdx, [nodes + rax * 8 + 8]
    mov     [pairB + rbx * 8], rdx
    mov     rcx, [nodes + rax * 8 + 16]
    jmp     .walk
.emit:
    mov     qword [nedits], 0
    xor     r12, r12                    ;line of A
    xor     r13, r13                    ;line of B
    mov     rbx, 0
.pair:
    cmp     rbx, [lcslen]
    jge     .tail
    mov     rax, [pairA + rbx * 8]
.delto:
    cmp     r12, rax
    jge     .insto
    mov     dl, ED_DEL
    call    push_edit
    inc     r12
    mov     rax, [pairA + rbx * 8]
    jmp     .delto
.insto:
    mov     rax, [pairB + rbx * 8]
    cmp     r13, rax
    jge     .keep
    mov     dl, ED_INS
    call    push_edit
    inc     r13
    jmp     .insto
.keep:
    mov     dl, ED_KEEP
    call    push_edit
    inc     r12
    inc     r13
    inc     rbx
    jmp     .pair
.tail:
    cmp     r12, [nlinesA]
    jge     .tailins
    mov     dl, ED_DEL
    call    push_edit
    inc     r12
    jmp     .tail
.tailins:
    cmp     r13, [nlinesB]
    jge     .out
    mov     dl, ED_INS
    call    push_edit
    inc     r13
    jmp     .tailins
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

push_edit:
    mov     rax, [nedits]
    cmp     rax, MAXEDITS
    jae     .out
    mov     [edits + rax], dl
    inc     qword [nedits]
.out:
    ret

; ---------------------------------------------------------------------------
; build_hunks: group the changes, pad each with the context lines and merge
; any two whose padding would overlap.
; ---------------------------------------------------------------------------
build_hunks:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     qword [nhunks], 0
    xor     rbx, rbx                    ;edit index
.find:
    cmp     rbx, [nedits]
    jge     .out
    cmp     byte [edits + rbx], ED_KEEP
    je      .skip
; a change starts here: back off by the context, then run forward
    mov     r12, rbx
    sub     r12, [ctxlines]
    cmp     r12, 0
    jge     .haveStart
    xor     r12, r12
.haveStart:
    mov     r13, rbx
.extend:
    cmp     r13, [nedits]
    jge     .close
    cmp     byte [edits + r13], ED_KEEP
    jne     .advance
; count how many matches follow: two contexts' worth ends the hunk
    mov     r14, r13
    mov     r15, 0
.run:
    cmp     r14, [nedits]
    jge     .runend
    cmp     byte [edits + r14], ED_KEEP
    jne     .runend
    inc     r15
    inc     r14
    jmp     .run
.runend:
    mov     rax, [ctxlines]
    add     rax, rax
    cmp     r15, rax
    jg      .close
    cmp     r14, [nedits]
    jge     .close
    mov     r13, r14
    jmp     .extend
.advance:
    inc     r13
    jmp     .extend
.close:
; r13 is the first index past the last change; add trailing context
    mov     r14, r13
    add     r14, [ctxlines]
    cmp     r14, [nedits]
    jle     .haveEnd
    mov     r14, [nedits]
.haveEnd:
    mov     rdi, r12
    mov     rsi, r14
    call    record_hunk
    mov     rbx, r14
    jmp     .find
.skip:
    inc     rbx
    jmp     .find
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; record_hunk: store the hunk covering edits [rdi, rsi) along with the line
; numbers it starts at and how many lines each side contributes.
record_hunk:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
    xor     r8, r8                      ;A lines before the hunk
    xor     r9, r9                      ;B lines before the hunk
    xor     rcx, rcx
.count:
    cmp     rcx, r12
    jge     .measure
    movzx   eax, byte [edits + rcx]
    cmp     al, ED_INS
    je      .cins
    inc     r8
    cmp     al, ED_DEL
    je      .cnext
    inc     r9
    jmp     .cnext
.cins:
    inc     r9
.cnext:
    inc     rcx
    jmp     .count
.measure:
    xor     r10, r10                    ;A lines inside
    xor     r11, r11                    ;B lines inside
    mov     rcx, r12
.span:
    cmp     rcx, r13
    jge     .store
    movzx   eax, byte [edits + rcx]
    cmp     al, ED_INS
    je      .sins
    inc     r10
    cmp     al, ED_DEL
    je      .snext
    inc     r11
    jmp     .snext
.sins:
    inc     r11
.snext:
    inc     rcx
    jmp     .span
.store:
    mov     rax, [nhunks]
    cmp     rax, MAXHUNKS
    jae     .out
    imul    rbx, rax, 6
    mov     [hunks + rbx * 8], r12
    mov     [hunks + rbx * 8 + 8], r13
    mov     [hunks + rbx * 8 + 16], r8
    mov     [hunks + rbx * 8 + 24], r9
    mov     [hunks + rbx * 8 + 32], r10
    mov     [hunks + rbx * 8 + 40], r11
    inc     qword [nhunks]
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; print_unified: the "--- +++ @@" form.
; ---------------------------------------------------------------------------
print_unified:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rsi, s_minus3
    call    out_str
    mov     rsi, pathA
    cmp     qword [nlabels], 1
    jb      .nameA
    mov     rsi, [labelA]
.nameA:
    call    out_str
    mov     al, WHITESPACE_NL
    call    out_char
    mov     rsi, s_plus3
    call    out_str
    mov     rsi, pathB
    cmp     qword [nlabels], 2
    jb      .nameB
    mov     rsi, [labelB]
.nameB:
    call    out_str
    mov     al, WHITESPACE_NL
    call    out_char
    xor     rbx, rbx
.hunk:
    cmp     rbx, [nhunks]
    jge     .out
    imul    r12, rbx, 6
    mov     rsi, s_at
    call    out_str
    mov     rax, [hunks + r12 * 8 + 16]
    mov     rcx, [hunks + r12 * 8 + 32]
    call    out_range
    mov     rsi, s_atplus
    call    out_str
    mov     rax, [hunks + r12 * 8 + 24]
    mov     rcx, [hunks + r12 * 8 + 40]
    call    out_range
    mov     rsi, s_atend
    call    out_str
    cmp     qword [funcre], 0
    je      .noheader
    mov     rdi, [hunks + r12 * 8 + 16]
    call    function_line
.noheader:
    mov     al, WHITESPACE_NL
    call    out_char
; the body, walking the edits and the two line cursors together
    mov     r13, [hunks + r12 * 8]      ;edit cursor
    mov     r14, [hunks + r12 * 8 + 16] ;line of A
    mov     r15, [hunks + r12 * 8 + 24] ;line of B
.body:
    mov     rax, [hunks + r12 * 8 + 8]
    cmp     r13, rax
    jge     .nexthunk
    movzx   eax, byte [edits + r13]
    cmp     al, ED_DEL
    je      .del
    cmp     al, ED_INS
    je      .ins
    mov     al, WHITESPACE_SPACE
    call    out_char
    mov     rdi, r14
    call    out_lineA
    inc     r14
    inc     r15
    jmp     .bnext
.del:
    mov     al, '-'
    call    out_char
    mov     rdi, r14
    call    out_lineA
    inc     r14
    jmp     .bnext
.ins:
    mov     al, '+'
    call    out_char
    mov     rdi, r15
    call    out_lineB
    inc     r15
.bnext:
    inc     r13
    jmp     .body
.nexthunk:
    inc     rbx
    jmp     .hunk
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; out_range: the "start,count" of a hunk side, where a count of one is left
; implicit and an empty side points at the line before it.
out_range:
    push    rbx
    mov     rbx, rcx
    test    rbx, rbx
    jz      .empty
    inc     rax
    call    out_num
    cmp     rbx, 1
    je      .out
    mov     al, ','
    call    out_char
    mov     rax, rbx
    call    out_num
    jmp     .out
.empty:
    call    out_num
    mov     al, ','
    call    out_char
    xor     rax, rax
    call    out_num
.out:
    pop     rbx
    ret

; function_line: append the nearest line above the hunk that matches
; --show-function-line, the way diff labels a hunk with its enclosing
; function.
function_line:
    push    rbx
    mov     rbx, rdi
    cmp     qword [rx_compiled], 0
    jne     .search
    mov     rsi, [funcre]
    call    compile_regex
    mov     qword [rx_compiled], 1
.search:
    test    rbx, rbx
    jz      .out
    dec     rbx
.scan:
    cmp     rbx, 0
    jl      .out
    mov     rax, [offA + rbx * 8]
    add     rax, fileA
    mov     [rx_subj], rax
    mov     rax, [lenA + rbx * 8]
    mov     [rx_len], rax
    call    regex_search
    test    al, al
    jnz     .found
    dec     rbx
    jmp     .scan
.found:
    mov     al, WHITESPACE_SPACE
    call    out_char
    mov     rdi, rbx
    call    out_lineA_nonl
.out:
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; print_normal: the default "3a4" form with "<" and ">" bodies.
; ---------------------------------------------------------------------------
print_normal:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    xor     rbx, rbx
.hunk:
    cmp     rbx, [nhunks]
    jge     .out
    imul    r12, rbx, 6
; the normal form has no context, so walk the changes inside this hunk
    mov     r13, [hunks + r12 * 8]
    mov     r14, [hunks + r12 * 8 + 16]
    mov     r15, [hunks + r12 * 8 + 24]
.scan:
    mov     rax, [hunks + r12 * 8 + 8]
    cmp     r13, rax
    jge     .nexthunk
    cmp     byte [edits + r13], ED_KEEP
    jne     .change
    inc     r13
    inc     r14
    inc     r15
    jmp     .scan
.change:
    mov     [chg_edit], r13
    mov     [chg_a], r14
    mov     [chg_b], r15
    xor     r8, r8                      ;deleted lines
    xor     r9, r9                      ;inserted lines
.span:
    mov     rax, [hunks + r12 * 8 + 8]
    cmp     r13, rax
    jge     .emit
    movzx   eax, byte [edits + r13]
    cmp     al, ED_KEEP
    je      .emit
    cmp     al, ED_DEL
    je      .spandel
    inc     r9
    inc     r15
    jmp     .spannext
.spandel:
    inc     r8
    inc     r14
.spannext:
    inc     r13
    jmp     .span
.emit:
    mov     [chg_dels], r8
    mov     [chg_inss], r9
    call    emit_normal_change
    jmp     .scan
.nexthunk:
    inc     rbx
    jmp     .hunk
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

emit_normal_change:
    push    rbx
    push    r12
; the counts stay in memory: the output helpers use the scratch registers
    mov     rax, [chg_a]
    mov     rcx, [chg_dels]
    call    out_side_range
    mov     al, 'c'
    cmp     qword [chg_dels], 0
    jne     .havedels
    mov     al, 'a'
    jmp     .cmd
.havedels:
    cmp     qword [chg_inss], 0
    jne     .cmd
    mov     al, 'd'
.cmd:
    call    out_char
    mov     rax, [chg_b]
    mov     rcx, [chg_inss]
    call    out_side_range
    mov     al, WHITESPACE_NL
    call    out_char
    cmp     qword [chg_dels], 0
    je      .inserts
    mov     rbx, [chg_a]
    mov     r12, rbx
    add     r12, [chg_dels]
.delline:
    cmp     rbx, r12
    jge     .between
    mov     rsi, s_lt
    call    out_str
    mov     rdi, rbx
    call    out_lineA
    inc     rbx
    jmp     .delline
.between:
    cmp     qword [chg_inss], 0
    jz      .out
    mov     rsi, s_sep3
    call    out_str
.inserts:
    cmp     qword [chg_inss], 0
    je      .out
    mov     rbx, [chg_b]
    mov     r12, rbx
    add     r12, [chg_inss]
.insline:
    cmp     rbx, r12
    jge     .out
    mov     rsi, s_gt
    call    out_str
    mov     rdi, rbx
    call    out_lineB
    inc     rbx
    jmp     .insline
.out:
    pop     r12
    pop     rbx
    ret

; out_side_range: "N" or "N,M" for one side of a normal-form change. The end
; is worked out before printing, because writing a digit clobbers the low
; byte of the register holding the start.
out_side_range:
    push    rbx
    push    r12
    mov     rbx, rcx
    test    rbx, rbx
    jz      .empty
    inc     rax
    mov     r12, rax
    add     r12, rbx
    dec     r12                         ;last line of the run
    call    out_num
    cmp     rbx, 1
    je      .out
    mov     al, ','
    call    out_char
    mov     rax, r12
    call    out_num
    jmp     .out
.empty:
    call    out_num
.out:
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; print_line_formats: every line rendered through its own format string, the
; way --old-line-format and friends ask for.
; ---------------------------------------------------------------------------
print_line_formats:
    push    rbx
    push    r12
    push    r13
    xor     rbx, rbx
    xor     r12, r12                    ;line of A
    xor     r13, r13                    ;line of B
.step:
    cmp     rbx, [nedits]
    jge     .out
    movzx   eax, byte [edits + rbx]
    cmp     al, ED_DEL
    je      .del
    cmp     al, ED_INS
    je      .ins
    mov     rsi, [fmt_same]
    mov     rdi, r12
    xor     rdx, rdx
    call    emit_format
    inc     r12
    inc     r13
    jmp     .next
.del:
    mov     rsi, [fmt_old]
    mov     rdi, r12
    xor     rdx, rdx
    call    emit_format
    inc     r12
    jmp     .next
.ins:
    mov     rsi, [fmt_new]
    mov     rdi, r13
    mov     rdx, 1
    call    emit_format
    inc     r13
.next:
    inc     rbx
    jmp     .step
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; emit_format: render the format at rsi for line rdi of side rdx (0 = A).
; "%l" is the line without its newline, "%L" with one.
emit_format:
    push    rbx
    push    r12
    push    r13
    test    rsi, rsi
    jz      .out
    mov     rbx, rsi
    mov     r12, rdi
    mov     r13, rdx
.scan:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .out
    inc     rbx
    cmp     al, '%'
    jne     .literal
    movzx   eax, byte [rbx]
    test    al, al
    jz      .out
    inc     rbx
    cmp     al, 'l'
    je      .bare
    cmp     al, 'L'
    je      .withnl
    cmp     al, '%'
    je      .literal
    cmp     al, 'n'
    je      .newline
    jmp     .literal
.bare:
    mov     rdi, r12
    test    r13, r13
    jnz     .bareB
    call    out_lineA_nonl
    jmp     .scan
.bareB:
    call    out_lineB_nonl
    jmp     .scan
.withnl:
    mov     rdi, r12
    test    r13, r13
    jnz     .nlB
    call    out_lineA
    jmp     .scan
.nlB:
    call    out_lineB
    jmp     .scan
.newline:
    mov     al, WHITESPACE_NL
    call    out_char
    jmp     .scan
.literal:
    call    out_char
    jmp     .scan
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; compare_dirs: pair the two directories' entries by name. A name in only one
; of them is reported; a name in both is compared, recursing when both sides
; are directories.
;
; The name text and the two pointer arrays come from bump arenas whose marks
; are restored on the way out, so a nested directory cannot overwrite the
; listing its parent is still walking.
; ---------------------------------------------------------------------------
compare_dirs:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rax, [namefree]
    push    rax                         ;rsp+40 name arena mark
    mov     rax, [listfree]
    push    rax                         ;rsp+32 list arena mark
    mov     rax, [pathAlen]
    push    rax                         ;rsp+24 path A length
    mov     rax, [pathBlen]
    push    rax                         ;rsp+16 path B length
    push    rax                         ;rsp+8  count A, filled below
    push    rax                         ;rsp+0  count B, filled below

    mov     r14, [listfree]             ;names of the first directory
    mov     rdi, pathA
    mov     rsi, r14
    call    read_dir_names
    mov     [rsp + 8], rax
    lea     rcx, [r14 + rax * 8]
    mov     [listfree], rcx
    mov     r15, rcx                    ;names of the second directory
    mov     rdi, pathB
    mov     rsi, r15
    call    read_dir_names
    mov     [rsp], rax
    lea     rcx, [r15 + rax * 8]
    mov     [listfree], rcx

    mov     rdi, r14
    mov     rsi, [rsp + 8]
    call    sort_names
    mov     rdi, r15
    mov     rsi, [rsp]
    call    sort_names

    xor     r12, r12                    ;cursor into the first listing
    xor     r13, r13                    ;cursor into the second
.merge:
    cmp     r12, [rsp + 8]
    jge     .restB
    cmp     r13, [rsp]
    jge     .restA
    mov     rdi, [r14 + r12 * 8]
    mov     rsi, [r15 + r13 * 8]
    call    strcmp_z
    cmp     rax, 0
    jl      .onlyA
    jg      .onlyB
    mov     rsi, [r14 + r12 * 8]
    call    both_sides
    inc     r12
    inc     r13
    jmp     .merge
.onlyA:
    mov     rdi, pathA
    mov     rsi, [r14 + r12 * 8]
    call    report_only
    inc     r12
    jmp     .merge
.onlyB:
    mov     rdi, pathB
    mov     rsi, [r15 + r13 * 8]
    call    report_only
    inc     r13
    jmp     .merge
.restA:
    cmp     r12, [rsp + 8]
    jge     .done
    mov     rdi, pathA
    mov     rsi, [r14 + r12 * 8]
    call    report_only
    inc     r12
    jmp     .restA
.restB:
    cmp     r13, [rsp]
    jge     .restA
    mov     rdi, pathB
    mov     rsi, [r15 + r13 * 8]
    call    report_only
    inc     r13
    jmp     .restB
.done:
    pop     rax                         ;count B
    pop     rax                         ;count A
    pop     rax
    mov     [pathBlen], rax
    mov     byte [pathB + rax], 0
    pop     rax
    mov     [pathAlen], rax
    mov     byte [pathA + rax], 0
    pop     rax
    mov     [listfree], rax
    pop     rax
    mov     [namefree], rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; both_sides: compare the name at rsi under both directories, then put the
; two paths back the way they were.
both_sides:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rsi
    mov     r12, [pathAlen]
    mov     r13, [pathBlen]
    mov     rdi, pathA
    mov     rsi, rbx
    mov     rdx, pathAlen
    call    path_push
    mov     rdi, pathB
    mov     rsi, rbx
    mov     rdx, pathBlen
    call    path_push
    call    compare_paths
    mov     [pathAlen], r12
    mov     byte [pathA + r12], 0
    mov     [pathBlen], r13
    mov     byte [pathB + r13], 0
    pop     r13
    pop     r12
    pop     rbx
    ret

; report_only: a name that exists under rdi but not under the other side.
report_only:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    mov     byte [status], 1
    mov     rsi, s_onlyin
    call    out_str
    mov     rsi, rbx
    call    out_str
    mov     rsi, s_onlysep
    call    out_str
    mov     rsi, r12
    call    out_str
    mov     al, WHITESPACE_NL
    call    out_char
    pop     r12
    pop     rbx
    ret

; read_dir_names: collect the entries of the directory at rdi into the array
; at rsi, skipping "." and "..". rax is the count.
read_dir_names:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15, rsi
    xor     r14, r14
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .out
    mov     r13, rax
.batch:
    mov     rax, SYS_GETDENTS64
    mov     rdi, r13
    mov     rsi, dirbuf
    mov     rdx, DIRCAP
    syscall
    test    rax, rax
    jle     .close
    mov     r12, rax
    xor     rbx, rbx
.entry:
    cmp     rbx, r12
    jge     .batch
    lea     rdi, [dirbuf + rbx]
    movzx   rax, word [rdi + dirent64.d_reclen]
    add     rbx, rax
    lea     rsi, [rdi + dirent64.d_name]
    cmp     byte [rsi], '.'
    jne     .keep
    cmp     byte [rsi + 1], 0
    je      .entry
    cmp     byte [rsi + 1], '.'
    jne     .keep
    cmp     byte [rsi + 2], 0
    je      .entry
.keep:
    lea     rax, [r15 + r14 * 8 + 8]
    mov     rcx, listarena + LISTARENA
    cmp     rax, rcx
    jae     .entry                      ;no room left to remember it
    call    intern_name                 ;-> rax, or 0 when the arena is full
    test    rax, rax
    jz      .entry
    mov     [r15 + r14 * 8], rax
    inc     r14
    jmp     .entry
.close:
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
.out:
    mov     rax, r14
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; intern_name: copy the name at rsi into the arena. rax is its address, or 0
; when there is no room.
intern_name:
    mov     rdi, [namefree]
    mov     rax, rdi
    xor     rcx, rcx
.copy:
    lea     rdx, [rdi + rcx]
    mov     r8, namearena + NAMEARENA - 1
    cmp     rdx, r8
    jae     .full
    mov     dl, [rsi + rcx]
    mov     [rdi + rcx], dl
    test    dl, dl
    jz      .done
    inc     rcx
    jmp     .copy
.done:
    lea     rdx, [rdi + rcx + 1]
    mov     [namefree], rdx
    ret
.full:
    xor     rax, rax
    ret

; sort_names: insertion sort of the rsi pointers at rdi, by name.
sort_names:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    mov     r13, rsi
    mov     rbx, 1
.outer:
    cmp     rbx, r13
    jge     .out
    mov     r14, [r12 + rbx * 8]
    mov     rcx, rbx
.inner:
    test    rcx, rcx
    jz      .place
    mov     rdi, [r12 + rcx * 8 - 8]
    mov     rsi, r14
    push    rcx
    call    strcmp_z
    pop     rcx
    cmp     rax, 0
    jle     .place
    mov     rax, [r12 + rcx * 8 - 8]
    mov     [r12 + rcx * 8], rax
    dec     rcx
    jmp     .inner
.place:
    mov     [r12 + rcx * 8], r14
    inc     rbx
    jmp     .outer
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; path_push: append "/" and the name at rsi to the buffer at rdi, whose
; length lives at rdx.
path_push:
    push    rbx
    mov     rbx, rdx
    mov     rcx, [rbx]
    cmp     rcx, 0
    je      .name
    cmp     byte [rdi + rcx - 1], '/'
    je      .name
    mov     byte [rdi + rcx], '/'
    inc     rcx
.name:
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     rcx, PATHCAP - 2
    jae     .done
    mov     [rdi + rcx], al
    inc     rcx
    inc     rsi
    jmp     .name
.done:
    mov     byte [rdi + rcx], 0
    mov     [rbx], rcx
    pop     rbx
    ret

set_pathA:
    mov     rsi, rdi
    mov     rdi, pathA
    mov     rdx, pathAlen
    jmp     set_path
set_pathB:
    mov     rsi, rdi
    mov     rdi, pathB
    mov     rdx, pathBlen
set_path:
    xor     rcx, rcx
.copy:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .done
    cmp     rcx, PATHCAP - 2
    jae     .done
    mov     [rdi + rcx], al
    inc     rcx
    jmp     .copy
.done:
    mov     byte [rdi + rcx], 0
    mov     [rdx], rcx
    ret

; ---------------------------------------------------------------------------
; A small basic regular expression matcher, used only by
; --show-function-line. Literals, '.', bracket expressions, '*', '^' and '$'
; are enough to pick out a function header.
; ---------------------------------------------------------------------------
compile_regex:
    mov     qword [nelem], 0
    mov     qword [nclass], 0
    cmp     byte [rsi], '^'
    jne     .scan
    mov     al, T_BOL
    xor     ah, ah
    call    push_elem
    inc     rsi
.scan:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .out
    cmp     al, '\'
    je      .escape
    cmp     al, '.'
    je      .any
    cmp     al, '['
    je      .bracket
    cmp     al, '$'
    jne     .literal
    cmp     byte [rsi + 1], 0
    jne     .literal
    mov     al, T_EOL
    xor     ah, ah
    call    push_elem
    inc     rsi
    jmp     .scan
.literal:
    mov     ah, al
    mov     al, T_LIT
    call    push_elem
    inc     rsi
    jmp     .star
.any:
    mov     al, T_ANY
    xor     ah, ah
    call    push_elem
    inc     rsi
    jmp     .star
.escape:
    inc     rsi
    movzx   eax, byte [rsi]
    test    al, al
    jz      .out
    mov     ah, al
    mov     al, T_LIT
    call    push_elem
    inc     rsi
    jmp     .star
.bracket:
    call    push_class
.star:
    cmp     byte [rsi], '*'
    jne     .scan
    mov     rcx, [nelem]
    dec     rcx
    mov     byte [e_star + rcx], 1
    inc     rsi
    jmp     .scan
.out:
    ret

push_elem:
    mov     rcx, [nelem]
    cmp     rcx, MAXELEM
    jae     .out
    mov     [e_type + rcx], al
    mov     [e_ch + rcx], ah
    mov     byte [e_star + rcx], 0
    mov     byte [e_cls + rcx], 0
    inc     rcx
    mov     [nelem], rcx
.out:
    ret

push_class:
    push    rbx
    mov     rbx, [nclass]
    cmp     rbx, MAXCLASS
    jae     .out
    imul    rdi, rbx, 32
    add     rdi, classes
    xor     rcx, rcx
.clear:
    mov     byte [rdi + rcx], 0
    inc     rcx
    cmp     rcx, 32
    jb      .clear
    inc     rsi
    xor     r8, r8
    cmp     byte [rsi], '^'
    jne     .items
    mov     r8, 1
    inc     rsi
.items:
    xor     r9, r9
.item:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .finish
    cmp     al, ']'
    jne     .member
    test    r9, r9
    jnz     .close
.member:
    mov     r9, 1
    cmp     byte [rsi + 1], '-'
    jne     .single
    movzx   ecx, byte [rsi + 2]
    test    cl, cl
    jz      .single
    cmp     cl, ']'
    je      .single
    movzx   edx, byte [rsi]
.range:
    mov     rax, rdx
    call    class_set
    cmp     rdx, rcx
    jae     .rangedone
    inc     rdx
    jmp     .range
.rangedone:
    add     rsi, 3
    jmp     .item
.single:
    movzx   eax, byte [rsi]
    call    class_set
    inc     rsi
    jmp     .item
.close:
    inc     rsi
.finish:
    test    r8, r8
    jz      .store
    imul    rdi, rbx, 32
    add     rdi, classes
    xor     rcx, rcx
.invert:
    not     byte [rdi + rcx]
    inc     rcx
    cmp     rcx, 32
    jb      .invert
.store:
    mov     al, T_CLASS
    xor     ah, ah
    call    push_elem
    mov     rcx, [nelem]
    dec     rcx
    mov     [e_cls + rcx], bl
    inc     qword [nclass]
.out:
    pop     rbx
    ret

class_set:
    push    rcx
    push    rdx
    push    rdi
    movzx   eax, al
    imul    rdi, rbx, 32
    add     rdi, classes
    mov     rcx, rax
    shr     rcx, 3
    add     rdi, rcx
    mov     rcx, rax
    and     rcx, 7
    mov     dl, 1
    shl     dl, cl
    or      [rdi], dl
    pop     rdi
    pop     rdx
    pop     rcx
    ret

; regex_search: does the pattern match anywhere in the subject? al = 1/0.
regex_search:
    push    rbx
    xor     rbx, rbx
.start:
    cmp     rbx, [rx_len]
    ja      .no
    xor     rdi, rdi
    mov     rsi, rbx
    call    rx_match
    test    al, al
    jnz     .yes
    inc     rbx
    jmp     .start
.yes:
    mov     al, 1
    pop     rbx
    ret
.no:
    xor     al, al
    pop     rbx
    ret

; rx_match: element rdi against the subject from rsi.
rx_match:
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    mov     r13, rsi
    cmp     r12, [nelem]
    jb      .element
    mov     al, 1
    jmp     .out
.element:
    movzx   eax, byte [e_type + r12]
    cmp     al, T_BOL
    je      .bol
    cmp     al, T_EOL
    je      .eol
    cmp     byte [e_star + r12], 0
    jne     .star
    cmp     r13, [rx_len]
    jae     .fail
    mov     rdi, r12
    mov     rsi, r13
    call    rx_elem
    test    al, al
    jz      .fail
    lea     rdi, [r12 + 1]
    lea     rsi, [r13 + 1]
    call    rx_match
    jmp     .out
.star:
    xor     r14, r14
.grow:
    lea     rax, [r13 + r14]
    cmp     rax, [rx_len]
    jae     .shrink
    mov     rdi, r12
    lea     rsi, [r13 + r14]
    call    rx_elem
    test    al, al
    jz      .shrink
    inc     r14
    jmp     .grow
.shrink:
    lea     rdi, [r12 + 1]
    lea     rsi, [r13 + r14]
    call    rx_match
    test    al, al
    jnz     .out
    test    r14, r14
    jz      .fail
    dec     r14
    jmp     .shrink
.bol:
    test    r13, r13
    jnz     .fail
    lea     rdi, [r12 + 1]
    mov     rsi, r13
    call    rx_match
    jmp     .out
.eol:
    cmp     r13, [rx_len]
    jne     .fail
    lea     rdi, [r12 + 1]
    mov     rsi, r13
    call    rx_match
    jmp     .out
.fail:
    xor     al, al
.out:
    pop     r14
    pop     r13
    pop     r12
    ret

rx_elem:
    mov     r8, [rx_subj]
    movzx   ecx, byte [r8 + rsi]
    movzx   eax, byte [e_type + rdi]
    cmp     al, T_ANY
    je      .yes
    cmp     al, T_CLASS
    je      .class
    cmp     al, T_LIT
    jne     .no
    cmp     cl, [e_ch + rdi]
    je      .yes
    jmp     .no
.class:
    movzx   r9d, byte [e_cls + rdi]
    imul    r9, r9, 32
    add     r9, classes
    mov     rax, rcx
    shr     rax, 3
    add     r9, rax
    and     rcx, 7
    mov     al, [r9]
    shr     al, cl
    and     al, 1
    ret
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; Output helpers.
; ---------------------------------------------------------------------------
out_lineA:
    call    out_lineA_nonl
    mov     al, WHITESPACE_NL
    jmp     out_char

out_lineB:
    call    out_lineB_nonl
    mov     al, WHITESPACE_NL
    jmp     out_char

out_lineA_nonl:
    mov     rsi, [offA + rdi * 8]
    add     rsi, fileA
    mov     rdx, [lenA + rdi * 8]
    jmp     out_bytes

out_lineB_nonl:
    mov     rsi, [offB + rdi * 8]
    add     rsi, fileB
    mov     rdx, [lenB + rdi * 8]
    jmp     out_bytes

out_char:
    push    rcx
    mov     rcx, [outlen]
    mov     [outbuf + rcx], al
    inc     rcx
    mov     [outlen], rcx
    cmp     rcx, OUTHIGH
    jb      .out
    call    out_flush
.out:
    pop     rcx
    ret

out_bytes:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, rdx
    xor     rbx, rbx
.copy:
    cmp     rbx, r13
    jae     .out
    mov     al, [r12 + rbx]
    call    out_char
    inc     rbx
    jmp     .copy
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

out_str:
    push    rbx
    mov     rbx, rsi
.copy:
    mov     al, [rbx]
    test    al, al
    jz      .out
    call    out_char
    inc     rbx
    jmp     .copy
.out:
    pop     rbx
    ret

out_num:
    push    rbx
    mov     rdi, numbuf
    call    u64_to_dec
    mov     rdx, rdi
    mov     rsi, numbuf
    sub     rdx, rsi
    call    out_bytes
    pop     rbx
    ret

out_flush:
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    mov     rdx, [outlen]
    test    rdx, rdx
    jz      .out
    mov     rsi, outbuf
.write:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    test    rax, rax
    jle     .done
    add     rsi, rax
    sub     rdx, rax
    jnz     .write
.done:
    mov     qword [outlen], 0
.out:
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi
    ret

u64_to_dec:
    push    rbx
    mov     rbx, rdi
    mov     rcx, 10
    xor     r8, r8
.split:
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    push    rdx
    inc     r8
    test    rax, rax
    jnz     .split
.emit:
    pop     rdx
    mov     [rbx], dl
    inc     rbx
    dec     r8
    jnz     .emit
    mov     rdi, rbx
    pop     rbx
    ret

streq:
    push    rdi
    push    rsi
.scan:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .no
    test    al, al
    jz      .yes
    inc     rdi
    inc     rsi
    jmp     .scan
.yes:
    mov     al, 1
    pop     rsi
    pop     rdi
    ret
.no:
    xor     al, al
    pop     rsi
    pop     rdi
    ret

strcmp_z:
    push    rdi
    push    rsi
.scan:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]
    cmp     al, cl
    jne     .differ
    test    al, al
    jz      .same
    inc     rdi
    inc     rsi
    jmp     .scan
.differ:
    cmp     al, cl
    jb      .less
    mov     rax, 1
    pop     rsi
    pop     rdi
    ret
.less:
    mov     rax, -1
    pop     rsi
    pop     rdi
    ret
.same:
    xor     rax, rax
    pop     rsi
    pop     rdi
    ret

strlen_z:
    xor     rax, rax
.scan:
    cmp     byte [rdi + rax], 0
    je      .out
    inc     rax
    jmp     .scan
.out:
    ret

atou:
    xor     rax, rax
.scan:
    movzx   rcx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .out
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .scan
.out:
    ret
