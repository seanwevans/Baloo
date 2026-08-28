; src/find.asm -- find(1): walk directory trees testing each file.
; Usage: find [-HLP] [PATH...] [EXPRESSION]
;
; The expression is parsed into a tree -- or, and, not, parentheses and the
; primaries -- and evaluated per file with the short-circuiting those
; operators imply, so "-exec false \; -print" prints nothing while
; "-print -o -print" prints once. When the expression contains no action at
; all, an implied -print is appended.
;
; The walk is pre-order: a directory is tested before its contents, which is
; what lets -quit stop on the directory itself and what -maxdepth counts.
;
; -H and -L decide whether a symlink is followed. Under -L a link that leads
; nowhere quietly falls back to the link itself, but one that leads to itself
; is reported, because a loop is a real error while a dangling link is a
; perfectly ordinary file.

    %include "include/sysdefs.inc"

    %define SYS_LSTAT 6
    %define SYS_FSTAT 5
    %define SYS_FORK 57
    %define SYS_WAIT4 61

    %define MAXNODES 4096
    %define NODESIZE 64
    %define MAXPATHS 1024
    %define PATHCAP 4096
    %define DIRCAP 32768
    %define OUTCAP 65536
    %define OUTHIGH (OUTCAP - 4096)
    %define PWCAP 65536
    %define MAXDEPTH 128
    %define EXECCAP 4096
    %define EXECARGS 8192
    %define EXECBUF (1024 * 1024)
    %define LINKCAP 4096

    %define N_AND 1
    %define N_OR 2
    %define N_NOT 3
    %define N_TYPE 10
    %define N_NAME 11
    %define N_PATH 13
    %define N_LNAME 15
    %define N_PERM 20
    %define N_USER 21
    %define N_NEWER 22
    %define N_SIZE 23
    %define N_SAMEFILE 24
    %define N_TRUE 30
    %define N_FALSE 31
    %define N_PRINT 40
    %define N_PRINT0 41
    %define N_PRINTF 42
    %define N_EXEC 43
    %define N_QUIT 45
    %define N_PRUNE 46
    %define N_EMPTY 47

    %define ND_TYPE 0
    %define ND_LEFT 8
    %define ND_RIGHT 16
    %define ND_ARG 24
    %define ND_NUM 32
    %define ND_NUM2 40
    %define ND_FLAG 48

    %define ST_DEV 0
    %define ST_INO 8
    %define ST_MODE 24
    %define ST_UID 28
    %define ST_SIZE 48
    %define ST_ATIME 72
    %define ST_ATIMENS 80
    %define ST_MTIME 88
    %define ST_MTIMENS 96
    %define ST_CTIME 104
    %define ST_CTIMENS 112

    %define S_IFMT 0o170000
    %define S_IFIFO 0o010000
    %define S_IFCHR 0o020000
    %define S_IFDIR 0o040000
    %define S_IFBLK 0o060000
    %define S_IFREG 0o100000
    %define S_IFLNK 0o120000
    %define S_IFSOCK 0o140000

    %define ELOOP_ERR 40
    %define ENOENT_ERR 2

    struc dirent64
    .d_ino      resq 1
    .d_off      resq 1
    .d_reclen   resw 1
    .d_type     resb 1
    .d_name     resb 1
    endstruc

section .bss
    nodes       resb (MAXNODES * NODESIZE)
    nnodes      resq 1
    roots       resq MAXPATHS
    nroots      resq 1
    pathbuf     resb PATHCAP
    pathlen     resq 1
    rootlen     resq 1
    linkbuf     resb LINKCAP
    lowerbuf    resb PATHCAP
    lowerpat    resb PATHCAP
    outbuf      resb OUTCAP
    outlen      resq 1
    stbuf       resb 160
    tmpstat     resb 160
    pwbuf       resb PWCAP
    pwlen       resq 1
    numbuf      resb 64
    execargv    resq EXECCAP
    execbuf     resb EXECBUF
    execfree    resq 1
    execcount   resq 1
    execnode    resq 1
    dirfds      resq MAXDEPTH
    argv0       resq 1
    argp        resq 1
    argn        resq 1
    root        resq 1
    curdepth    resq 1
    maxdepth    resq 1
    mindepth    resq 1
    envp        resq 1
    cur_uid     resq 1
    cur_ino     resq 1
    cur_dev     resq 1
    follow      resb 1
    follow_root resb 1
    have_action resb 1
    quitting    resb 1
    pw_loaded   resb 1
    status      resb 1

section .data
    p_and       db "-a", 0
    p_and2      db "-and", 0
    p_or        db "-o", 0
    p_or2       db "-or", 0
    p_not       db "-not", 0
    p_bang      db "!", 0
    p_lparen    db "(", 0
    p_rparen    db ")", 0
    p_type      db "-type", 0
    p_name      db "-name", 0
    p_iname     db "-iname", 0
    p_path      db "-path", 0
    p_wholename db "-wholename", 0
    p_ipath     db "-ipath", 0
    p_iwholename db "-iwholename", 0
    p_lname     db "-lname", 0
    p_ilname    db "-ilname", 0
    p_perm      db "-perm", 0
    p_user      db "-user", 0
    p_newer     db "-newer", 0
    p_neweraa   db "-neweraa", 0
    p_newerat   db "-newerat", 0
    p_newermt   db "-newermt", 0
    p_newerct   db "-newerct", 0
    p_size      db "-size", 0
    p_samefile  db "-samefile", 0
    p_true      db "-true", 0
    p_false     db "-false", 0
    p_print     db "-print", 0
    p_print0    db "-print0", 0
    p_printf    db "-printf", 0
    p_exec      db "-exec", 0
    p_quit      db "-quit", 0
    p_prune     db "-prune", 0
    p_empty     db "-empty", 0
    p_maxdepth  db "-maxdepth", 0
    p_mindepth  db "-mindepth", 0
    p_depth     db "-depth", 0
    p_xdev      db "-xdev", 0
    p_nouser    db "-nouser", 0
    p_semi      db ";", 0
    p_plus      db "+", 0
    p_brace     db "{}", 0
    p_dot       db ".", 0

    passwd_path db "/etc/passwd", 0
e_pre       db "find: ", 0
e_needarg   db ": needs an argument", 10, 0
e_badexpr   db "find: bad expression", 10, 0
e_noexec    db "find: -exec needs a terminating ; or +", 10, 0
e_loop      db ": Too many levels of symbolic links", 10, 0
e_noent     db ": No such file or directory", 10, 0
e_toomany   db "find: expression too large", 10, 0

section .text
global _start

_start:
    mov     qword [maxdepth], -1
    mov     rax, [rsp]                  ;argc
    mov     [argn], rax
    lea     rcx, [rsp + 8]
    mov     [argp], rcx
    lea     rcx, [rsp + rax * 8 + 16]
    mov     [envp], rcx
    call    arg_next                    ;drop the program name

; leading -H, -L and -P choose how symlinks are treated
.options:
    call    arg_peek
    test    rax, rax
    jz      .paths
    mov     rdi, rax
    cmp     byte [rdi], '-'
    jne     .paths
    cmp     byte [rdi + 2], 0
    jne     .paths
    movzx   ecx, byte [rdi + 1]
    cmp     cl, 'H'
    je      .set_H
    cmp     cl, 'L'
    je      .set_L
    cmp     cl, 'P'
    je      .set_P
    jmp     .paths
.set_H:
    mov     byte [follow_root], 1
    mov     byte [follow], 0
    call    arg_next
    jmp     .options
.set_L:
    mov     byte [follow], 1
    mov     byte [follow_root], 1
    call    arg_next
    jmp     .options
.set_P:
    mov     byte [follow], 0
    mov     byte [follow_root], 0
    call    arg_next
    jmp     .options

; then the starting points, up to the first word that looks like a test
.paths:
    call    arg_peek
    test    rax, rax
    jz      .expression
    mov     rdi, rax
    cmp     byte [rdi], '-'
    je      .expression
    cmp     byte [rdi], '('
    je      .checkparen
    cmp     byte [rdi], '!'
    je      .checkbang
.addpath:
    mov     rcx, [nroots]
    cmp     rcx, MAXPATHS
    jae     .skippath
    mov     [roots + rcx * 8], rdi
    inc     qword [nroots]
.skippath:
    call    arg_next
    jmp     .paths
.checkparen:
    cmp     byte [rdi + 1], 0
    je      .expression
    jmp     .addpath
.checkbang:
    cmp     byte [rdi + 1], 0
    je      .expression
    jmp     .addpath

.expression:
    call    parse_or                    ;-> rax = tree, 0 when empty
    mov     [tree], rax
    call    arg_peek
    test    rax, rax
    jnz     bad_expr                    ;a stray ")" or leftover word
    cmp     byte [have_action], 0
    jne     .roots
    call    append_print
.roots:
    cmp     qword [nroots], 0
    jne     .walk
    mov     qword [roots], p_dot        ;no starting point means "."
    mov     qword [nroots], 1
.walk:
    xor     rbx, rbx
.each:
    cmp     rbx, [nroots]
    jge     .finish
    cmp     byte [quitting], 0
    jne     .finish
    mov     rdi, [roots + rbx * 8]
    call    walk_root
    inc     rbx
    jmp     .each
.finish:
    call    flush_exec
    call    out_flush
    movzx   edi, byte [status]
    mov     rax, SYS_EXIT
    syscall

; arg_peek: the current argument, or 0 at the end.
arg_peek:
    cmp     qword [argn], 0
    jle     .none
    mov     rax, [argp]
    mov     rax, [rax]
    ret
.none:
    xor     rax, rax
    ret

; arg_next: consume the current argument and return it.
arg_next:
    call    arg_peek
    push    rax
    add     qword [argp], 8
    dec     qword [argn]
    pop     rax
    ret

bad_expr:
    mov     rsi, e_badexpr
    call    err_str
    exit    2

; need_arg: the primary named by rsi wants a value that is not there.
need_arg:
    push    rsi
    mov     rsi, e_pre
    call    err_str
    pop     rsi
    call    err_str
    mov     rsi, e_needarg
    call    err_str
    exit    2

; ---------------------------------------------------------------------------
; The expression parser. Precedence, lowest first: -o, then -a (which is also
; what juxtaposition means), then -not, then a primary or a parenthesised
; group.
; ---------------------------------------------------------------------------
parse_or:
    call    parse_and
    mov     rbx, rax
.loop:
    call    arg_peek
    test    rax, rax
    jz      .done
    mov     rdi, rax
    mov     rsi, p_or
    call    streq
    test    al, al
    jnz     .take
    call    arg_peek
    mov     rdi, rax
    mov     rsi, p_or2
    call    streq
    test    al, al
    jz      .done
.take:
    call    arg_next
    push    rbx
    call    parse_and
    pop     rbx
    test    rax, rax
    jz      bad_expr
    mov     rdi, N_OR
    mov     rsi, rbx
    mov     rdx, rax
    call    new_binary
    mov     rbx, rax
    jmp     .loop
.done:
    mov     rax, rbx
    ret

parse_and:
    call    parse_not
    mov     rbx, rax
.loop:
    call    arg_peek
    test    rax, rax
    jz      .done
    mov     rdi, rax
    mov     rsi, p_rparen
    call    streq
    test    al, al
    jnz     .done
    call    arg_peek
    mov     rdi, rax
    mov     rsi, p_or
    call    streq
    test    al, al
    jnz     .done
    call    arg_peek
    mov     rdi, rax
    mov     rsi, p_or2
    call    streq
    test    al, al
    jnz     .done
; "-a" is optional: two primaries in a row are already an and
    call    arg_peek
    mov     rdi, rax
    mov     rsi, p_and
    call    streq
    test    al, al
    jnz     .explicit
    call    arg_peek
    mov     rdi, rax
    mov     rsi, p_and2
    call    streq
    test    al, al
    jz      .implicit
.explicit:
    call    arg_next
.implicit:
    push    rbx
    call    parse_not
    pop     rbx
    test    rax, rax
    jz      .done2
    test    rbx, rbx
    jz      .first
    mov     rdi, N_AND
    mov     rsi, rbx
    mov     rdx, rax
    call    new_binary
    mov     rbx, rax
    jmp     .loop
.first:
    mov     rbx, rax
    jmp     .loop
.done2:
    mov     rax, rbx
    ret
.done:
    mov     rax, rbx
    ret

parse_not:
    call    arg_peek
    test    rax, rax
    jz      parse_primary
    mov     rdi, rax
    mov     rsi, p_bang
    call    streq
    test    al, al
    jnz     .negate
    call    arg_peek
    mov     rdi, rax
    mov     rsi, p_not
    call    streq
    test    al, al
    jz      parse_primary
.negate:
    call    arg_next
    call    parse_not
    test    rax, rax
    jz      bad_expr
    mov     rdi, N_NOT
    mov     rsi, rax
    xor     rdx, rdx
    jmp     new_binary

; new_binary: a node of kind rdi with children rsi and rdx.
new_binary:
    mov     rax, [nnodes]
    cmp     rax, MAXNODES
    jae     too_many
    imul    rcx, rax, NODESIZE
    add     rcx, nodes
    mov     [rcx + ND_TYPE], rdi
    mov     [rcx + ND_LEFT], rsi
    mov     [rcx + ND_RIGHT], rdx
    mov     qword [rcx + ND_ARG], 0
    mov     qword [rcx + ND_NUM], 0
    mov     qword [rcx + ND_NUM2], 0
    mov     qword [rcx + ND_FLAG], 0
    inc     qword [nnodes]
    mov     rax, rcx
    ret

too_many:
    mov     rsi, e_toomany
    call    err_str
    exit    2

; new_leaf: a primary of kind rdi.
new_leaf:
    mov     rsi, 0
    mov     rdx, 0
    jmp     new_binary

; ---------------------------------------------------------------------------
; parse_primary: one test, one action, or a parenthesised expression. Returns
; 0 when the next word is not part of the expression at all.
; ---------------------------------------------------------------------------
parse_primary:
    call    arg_peek
    test    rax, rax
    jz      .none
    mov     rbx, rax
    mov     rdi, rbx
    mov     rsi, p_lparen
    call    streq
    test    al, al
    jnz     .group
    mov     rdi, rbx
    mov     rsi, p_rparen
    call    streq
    test    al, al
    jnz     .none

    mov     rsi, p_type
    call    match_word
    test    al, al
    jnz     .type
    mov     rsi, p_name
    call    match_word
    test    al, al
    jnz     .name
    mov     rsi, p_iname
    call    match_word
    test    al, al
    jnz     .iname
    mov     rsi, p_path
    call    match_word
    test    al, al
    jnz     .path
    mov     rsi, p_wholename
    call    match_word
    test    al, al
    jnz     .path
    mov     rsi, p_ipath
    call    match_word
    test    al, al
    jnz     .ipath
    mov     rsi, p_iwholename
    call    match_word
    test    al, al
    jnz     .ipath
    mov     rsi, p_lname
    call    match_word
    test    al, al
    jnz     .lname
    mov     rsi, p_ilname
    call    match_word
    test    al, al
    jnz     .ilname
    mov     rsi, p_perm
    call    match_word
    test    al, al
    jnz     .perm
    mov     rsi, p_user
    call    match_word
    test    al, al
    jnz     .user
    mov     rsi, p_newer
    call    match_word
    test    al, al
    jnz     .newer
    mov     rsi, p_newerat
    call    match_word
    test    al, al
    jnz     .newerat
    mov     rsi, p_newermt
    call    match_word
    test    al, al
    jnz     .newermt
    mov     rsi, p_newerct
    call    match_word
    test    al, al
    jnz     .newerct
    mov     rsi, p_size
    call    match_word
    test    al, al
    jnz     .size
    mov     rsi, p_samefile
    call    match_word
    test    al, al
    jnz     .samefile
    mov     rsi, p_true
    call    match_word
    test    al, al
    jnz     .true
    mov     rsi, p_false
    call    match_word
    test    al, al
    jnz     .false
    mov     rsi, p_print0
    call    match_word
    test    al, al
    jnz     .print0
    mov     rsi, p_printf
    call    match_word
    test    al, al
    jnz     .printf
    mov     rsi, p_print
    call    match_word
    test    al, al
    jnz     .print
    mov     rsi, p_exec
    call    match_word
    test    al, al
    jnz     .exec
    mov     rsi, p_quit
    call    match_word
    test    al, al
    jnz     .quit
    mov     rsi, p_prune
    call    match_word
    test    al, al
    jnz     .prune
    mov     rsi, p_empty
    call    match_word
    test    al, al
    jnz     .empty
    mov     rsi, p_maxdepth
    call    match_word
    test    al, al
    jnz     .maxdepth
    mov     rsi, p_mindepth
    call    match_word
    test    al, al
    jnz     .mindepth
    mov     rsi, p_depth
    call    match_word
    test    al, al
    jnz     .true
    mov     rsi, p_xdev
    call    match_word
    test    al, al
    jnz     .true
    jmp     bad_expr

.none:
    xor     rax, rax
    ret
.group:
    call    arg_next
    call    parse_or
    push    rax
    call    arg_peek
    test    rax, rax
    jz      .unbalanced
    mov     rdi, rax
    mov     rsi, p_rparen
    call    streq
    test    al, al
    jz      .unbalanced
    call    arg_next
    pop     rax
    test    rax, rax
    jz      bad_expr
    ret
.unbalanced:
    pop     rax
    jmp     bad_expr

.type:
    mov     rsi, p_type
    call    take_value
    push    rax
    mov     rdi, N_TYPE
    call    new_leaf
    pop     rcx
    mov     [rax + ND_ARG], rcx
    ret
.name:
    mov     rsi, p_name
    call    take_value
    push    rax
    mov     rdi, N_NAME
    call    new_leaf
    pop     rcx
    mov     [rax + ND_ARG], rcx
    ret
.iname:
    mov     rsi, p_iname
    call    take_value
    push    rax
    mov     rdi, N_NAME
    call    new_leaf
    pop     rcx
    mov     [rax + ND_ARG], rcx
    mov     qword [rax + ND_FLAG], 1    ;fold case
    ret
.path:
    mov     rsi, p_path
    call    take_value
    push    rax
    mov     rdi, N_PATH
    call    new_leaf
    pop     rcx
    mov     [rax + ND_ARG], rcx
    ret
.ipath:
    mov     rsi, p_ipath
    call    take_value
    push    rax
    mov     rdi, N_PATH
    call    new_leaf
    pop     rcx
    mov     [rax + ND_ARG], rcx
    mov     qword [rax + ND_FLAG], 1
    ret
.lname:
    mov     rsi, p_lname
    call    take_value
    push    rax
    mov     rdi, N_LNAME
    call    new_leaf
    pop     rcx
    mov     [rax + ND_ARG], rcx
    ret
.ilname:
    mov     rsi, p_ilname
    call    take_value
    push    rax
    mov     rdi, N_LNAME
    call    new_leaf
    pop     rcx
    mov     [rax + ND_ARG], rcx
    mov     qword [rax + ND_FLAG], 1
    ret
.perm:
    mov     rsi, p_perm
    call    take_value
    mov     rbx, rax
    mov     rdi, N_PERM
    call    new_leaf
    mov     rcx, rbx
    mov     qword [rax + ND_FLAG], 0    ;exact match by default
    cmp     byte [rcx], '-'
    jne     .permvalue
    mov     qword [rax + ND_FLAG], 1    ;"-" means all these bits present
    inc     rcx
.permvalue:
    push    rax
    mov     rdi, rcx
    call    atoo
    pop     rcx
    mov     [rcx + ND_NUM], rax
    mov     rax, rcx
    ret
.user:
    mov     rsi, p_user
    call    take_value
    push    rax
    mov     rdi, N_USER
    call    new_leaf
    pop     rcx
    push    rax
    mov     rdi, rcx
    call    user_id                     ;-> rax
    pop     rcx
    mov     [rcx + ND_NUM], rax
    mov     rax, rcx
    ret
.newer:
    mov     rsi, p_newer
    call    take_value
    push    rax
    mov     rdi, N_NEWER
    call    new_leaf
    pop     rcx
    push    rax
    mov     rdi, rcx
    mov     rsi, tmpstat
    call    stat_follow
    pop     rax
    mov     rcx, [tmpstat + ST_MTIME]
    mov     [rax + ND_NUM], rcx
    mov     rcx, [tmpstat + ST_MTIMENS]
    mov     [rax + ND_NUM2], rcx
    mov     qword [rax + ND_FLAG], 'm'  ;compare against mtime
    ret
.newerat:
    mov     rsi, p_newerat
    mov     r8, 'a'
    jmp     .newerX
.newermt:
    mov     rsi, p_newermt
    mov     r8, 'm'
    jmp     .newerX
.newerct:
    mov     rsi, p_newerct
    mov     r8, 'c'
.newerX:
    push    r8
    call    take_value
    push    rax
    mov     rdi, N_NEWER
    call    new_leaf
    pop     rcx
    pop     r8
    push    rax
    push    r8
    mov     rdi, rcx
    call    parse_timespec              ;-> rax seconds, rdx nanoseconds
    pop     r8
    pop     rcx
    mov     [rcx + ND_NUM], rax
    mov     [rcx + ND_NUM2], rdx
    mov     [rcx + ND_FLAG], r8
    mov     rax, rcx
    ret
.size:
    mov     rsi, p_size
    call    take_value
    push    rax
    mov     rdi, N_SIZE
    call    new_leaf
    pop     rcx
    push    rax
    mov     rdi, rcx
    call    parse_size                  ;-> rax bytes, rdx comparison
    pop     rcx
    mov     [rcx + ND_NUM], rax
    mov     [rcx + ND_FLAG], rdx
    mov     rax, rcx
    ret
.samefile:
    mov     rsi, p_samefile
    call    take_value
    push    rax
    mov     rdi, N_SAMEFILE
    call    new_leaf
    pop     rcx
    push    rax
    mov     rdi, rcx
    mov     rsi, tmpstat
    call    stat_follow
    pop     rax
    mov     rcx, [tmpstat + ST_INO]
    mov     [rax + ND_NUM], rcx
    mov     rcx, [tmpstat + ST_DEV]
    mov     [rax + ND_NUM2], rcx
    ret
.true:
    mov     rdi, N_TRUE
    jmp     new_leaf
.false:
    mov     rdi, N_FALSE
    jmp     new_leaf
.empty:
    mov     rdi, N_EMPTY
    jmp     new_leaf
.print:
    mov     byte [have_action], 1
    mov     rdi, N_PRINT
    jmp     new_leaf
.print0:
    mov     byte [have_action], 1
    mov     rdi, N_PRINT0
    jmp     new_leaf
.printf:
    mov     byte [have_action], 1
    mov     rsi, p_printf
    call    take_value
    push    rax
    mov     rdi, N_PRINTF
    call    new_leaf
    pop     rcx
    mov     [rax + ND_ARG], rcx
    ret
.quit:
    mov     byte [have_action], 1
    mov     rdi, N_QUIT
    jmp     new_leaf
.prune:
    mov     rdi, N_PRUNE
    jmp     new_leaf
.exec:
    mov     byte [have_action], 1
    call    parse_exec
    ret
.maxdepth:
    mov     rsi, p_maxdepth
    call    take_value
    mov     rdi, rax
    call    atou
    mov     [maxdepth], rax
    mov     rdi, N_TRUE
    jmp     new_leaf
.mindepth:
    mov     rsi, p_mindepth
    call    take_value
    mov     rdi, rax
    call    atou
    mov     [mindepth], rax
    mov     rdi, N_TRUE
    jmp     new_leaf

; match_word: is the current argument the literal at rsi? Consumes it if so.
match_word:
    push    rsi
    call    arg_peek
    pop     rsi
    test    rax, rax
    jz      .no
    mov     rdi, rax
    push    rsi
    call    streq
    pop     rsi
    test    al, al
    jz      .no
    push    rsi
    call    arg_next
    pop     rsi
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; take_value: the argument after a primary, or a diagnostic naming it.
take_value:
    push    rsi
    call    arg_peek
    test    rax, rax
    jz      .missing
    call    arg_next
    pop     rsi
    ret
.missing:
    pop     rsi
    jmp     need_arg

; ---------------------------------------------------------------------------
; parse_exec: collect the words up to ";" or "+". The "+" form batches the
; paths onto one command line instead of running once per file.
; ---------------------------------------------------------------------------
parse_exec:
    mov     rdi, N_EXEC
    call    new_leaf
    mov     rbx, rax
    mov     rcx, [nnodes]
    mov     [rbx + ND_ARG], rcx         ;where this command's words start
    mov     rax, [execcount]
    mov     [rbx + ND_ARG], rax
    xor     r12, r12                    ;words collected
.word:
    call    arg_peek
    test    rax, rax
    jz      .unterminated
    mov     rdi, rax
    mov     rsi, p_semi
    call    streq
    test    al, al
    jnz     .endsemi
    call    arg_peek
    mov     rdi, rax
    mov     rsi, p_plus
    call    streq
    test    al, al
    jnz     .endplus
    call    arg_next
    mov     rcx, [execcount]
    cmp     rcx, EXECCAP - 2
    jae     .unterminated
    mov     [execargv + rcx * 8], rax
    inc     qword [execcount]
    inc     r12
    jmp     .word
.endsemi:
    call    arg_next
    mov     [rbx + ND_NUM], r12
    mov     qword [rbx + ND_FLAG], 0
    mov     rax, rbx
    ret
.endplus:
    call    arg_next
    mov     [rbx + ND_NUM], r12
    mov     qword [rbx + ND_FLAG], 1
    mov     rax, [execfree]
    mov     [rbx + ND_NUM2], rax
    mov     rax, rbx
    ret
.unterminated:
    mov     rsi, e_noexec
    call    err_str
    exit    2

; append_print: with no action anywhere, find prints what matched.
append_print:
    mov     rdi, N_PRINT
    call    new_leaf
    mov     rcx, [tree]
    test    rcx, rcx
    jnz     .combine
    mov     [tree], rax
    ret
.combine:
    mov     rdi, N_AND
    mov     rsi, rcx
    mov     rdx, rax
    call    new_binary
    mov     [tree], rax
    ret

; ---------------------------------------------------------------------------
; walk_root: descend from one starting point. The root itself is stat'd with
; -H or -L honoured; deeper entries follow only under -L.
; ---------------------------------------------------------------------------
walk_root:
    push    rbx
    mov     rsi, rdi
    call    set_path
    mov     rax, [pathlen]
    mov     [rootlen], rax
    mov     qword [curdepth], 0
    cmp     qword [pathlen], 0
    je      .empty
    mov     al, [follow_root]
    call    stat_current
    test    al, al
    jz      .missing
    call    visit
    pop     rbx
    ret
.missing:
    mov     byte [status], 1
    call    warn_path
    pop     rbx
    ret
.empty:
    mov     byte [status], 1
    call    warn_path                   ;an empty starting point names nothing
    pop     rbx
    ret

; stat_current: fill stbuf for pathbuf. al on entry says whether to follow a
; symlink. al = 1 on success.
;
; Under -L a link that goes nowhere falls back to the link itself and stays
; quiet, because a dangling link is an ordinary file; a link that loops is
; reported, because that is a real error.
stat_current:
    push    rbx
    movzx   ebx, al
    test    rbx, rbx
    jz      .lstat
    mov     rax, SYS_STAT
    mov     rdi, pathbuf
    mov     rsi, stbuf
    syscall
    test    rax, rax
    jns     .ok
    cmp     rax, -ELOOP_ERR
    je      .loop
.lstat:
    mov     rax, SYS_LSTAT
    mov     rdi, pathbuf
    mov     rsi, stbuf
    syscall
    test    rax, rax
    js      .fail
.ok:
    mov     rax, [stbuf + ST_INO]
    mov     [cur_ino], rax
    mov     rax, [stbuf + ST_DEV]
    mov     [cur_dev], rax
    mov     al, 1
    pop     rbx
    ret
.loop:
    mov     byte [status], 1
    mov     rsi, e_loop
    call    warn_path_reason
    xor     al, al
    pop     rbx
    ret
.fail:
    xor     al, al
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; visit: test the file now in pathbuf, then descend into it when it is a
; directory. Pre-order, so a directory is seen before its contents.
; ---------------------------------------------------------------------------
visit:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rax, [curdepth]
    cmp     rax, [mindepth]
    jl      .descend                    ;too shallow to report, but still walk
    mov     rdi, [tree]
    call    eval
.descend:
    cmp     byte [quitting], 0
    jne     .out
    mov     rax, [stbuf + ST_MODE]
    and     rax, S_IFMT
    cmp     rax, S_IFDIR
    jne     .out
    mov     rax, [maxdepth]
    cmp     rax, -1
    je      .enter
    cmp     rax, [curdepth]
    jle     .out
.enter:
    call    read_children
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; read_children: list pathbuf and visit each entry. The names are copied out
; of the kernel's buffer before recursing, since the recursion reuses it.
read_children:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rax, SYS_OPEN
    mov     rdi, pathbuf
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .out
    mov     r15, rax
    mov     rax, [pathlen]
    push    rax
    inc     qword [curdepth]
    mov     rax, [curdepth]
    cmp     rax, MAXDEPTH
    jb      .haveslot
    xor     rax, rax                    ;deeper than we can hold a listing for
    jmp     .slotpushed
.haveslot:
    imul    rax, rax, DIRCAP
    add     rax, dirbufs
.slotpushed:
    push    rax
    test    rax, rax
    jz      .close
.batch:
    mov     rax, SYS_GETDENTS64
    mov     rdi, r15
    mov     rsi, [rsp]
    mov     rdx, DIRCAP
    syscall
    test    rax, rax
    jle     .close
    mov     r13, rax
    xor     r12, r12
.entry:
    cmp     byte [quitting], 0
    jne     .close
    cmp     r12, r13
    jge     .batch
    mov     rbx, [rsp]
    add     rbx, r12
    movzx   rax, word [rbx + dirent64.d_reclen]
    add     r12, rax
    lea     rsi, [rbx + dirent64.d_name]
    cmp     byte [rsi], '.'
    jne     .keep
    cmp     byte [rsi + 1], 0
    je      .entry
    cmp     byte [rsi + 1], '.'
    jne     .keep
    cmp     byte [rsi + 2], 0
    je      .entry
.keep:
    mov     rdi, namestash
    call    copy_str
    mov     rax, [pathlen]
    mov     r14, rax
    mov     rsi, namestash
    call    path_push
    mov     al, [follow]
    call    stat_current
    test    al, al
    jz      .restore
    push    r12
    push    r13
    call    visit
    pop     r13
    pop     r12
.restore:
    mov     [pathlen], r14
    mov     byte [pathbuf + r14], 0
    jmp     .entry
.close:
    pop     rax                         ;this level's listing buffer
    dec     qword [curdepth]
    pop     rax
    mov     [pathlen], rax
    mov     byte [pathbuf + rax], 0
    mov     rax, SYS_CLOSE
    mov     rdi, r15
    syscall
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; eval: run the expression tree against the current file. al = 1 for true.
; -a and -o stop as soon as the answer is known, which is what stops
; "-exec false \; -print" from printing.
; ---------------------------------------------------------------------------
eval:
    test    rdi, rdi
    jz      .true
    push    rbx
    mov     rbx, rdi
    mov     rax, [rbx + ND_TYPE]
    cmp     rax, N_AND
    je      .and
    cmp     rax, N_OR
    je      .or
    cmp     rax, N_NOT
    je      .not
    mov     rdi, rbx
    call    eval_leaf
    pop     rbx
    ret
.and:
    mov     rdi, [rbx + ND_LEFT]
    call    eval
    test    al, al
    jz      .false
    mov     rdi, [rbx + ND_RIGHT]
    call    eval
    pop     rbx
    ret
.or:
    mov     rdi, [rbx + ND_LEFT]
    call    eval
    test    al, al
    jnz     .true2
    mov     rdi, [rbx + ND_RIGHT]
    call    eval
    pop     rbx
    ret
.not:
    mov     rdi, [rbx + ND_LEFT]
    call    eval
    test    al, al
    jz      .true2
.false:
    xor     al, al
    pop     rbx
    ret
.true2:
    mov     al, 1
    pop     rbx
    ret
.true:
    mov     al, 1
    ret

; ---------------------------------------------------------------------------
; eval_leaf: one primary against the current file.
; ---------------------------------------------------------------------------
eval_leaf:
    push    rbx
    mov     rbx, rdi
    mov     rax, [rbx + ND_TYPE]
    cmp     rax, N_TYPE
    je      .type
    cmp     rax, N_NAME
    je      .name
    cmp     rax, N_PATH
    je      .path
    cmp     rax, N_LNAME
    je      .lname
    cmp     rax, N_PERM
    je      .perm
    cmp     rax, N_USER
    je      .user
    cmp     rax, N_NEWER
    je      .newer
    cmp     rax, N_SIZE
    je      .size
    cmp     rax, N_SAMEFILE
    je      .samefile
    cmp     rax, N_TRUE
    je      .true
    cmp     rax, N_FALSE
    je      .false
    cmp     rax, N_EMPTY
    je      .empty
    cmp     rax, N_PRINT
    je      .print
    cmp     rax, N_PRINT0
    je      .print0
    cmp     rax, N_PRINTF
    je      .printf
    cmp     rax, N_EXEC
    je      .exec
    cmp     rax, N_QUIT
    je      .quit
    cmp     rax, N_PRUNE
    je      .true
.true:
    mov     al, 1
    pop     rbx
    ret
.false:
    xor     al, al
    pop     rbx
    ret

.type:
; a comma separated list, so "-type l,f" accepts either
    mov     rsi, [rbx + ND_ARG]
    mov     rdx, [stbuf + ST_MODE]
    and     rdx, S_IFMT
.typechar:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .false
    cmp     al, ','
    je      .typenext
    call    type_letter                 ;-> rcx = the mode this letter means
    cmp     rcx, rdx
    je      .true
.typenext:
    inc     rsi
    jmp     .typechar

.name:
    call    basename_of                 ;-> rsi
    mov     rdi, [rbx + ND_ARG]
    mov     rdx, [rbx + ND_FLAG]
    call    glob_match
    pop     rbx
    ret
.path:
    mov     rsi, pathbuf
    mov     rdi, [rbx + ND_ARG]
    mov     rdx, [rbx + ND_FLAG]
    call    glob_match
    pop     rbx
    ret
.lname:
    mov     rax, [stbuf + ST_MODE]
    and     rax, S_IFMT
    cmp     rax, S_IFLNK
    jne     .false
    mov     rax, SYS_READLINK
    mov     rdi, pathbuf
    mov     rsi, linkbuf
    mov     rdx, LINKCAP - 1
    syscall
    test    rax, rax
    js      .false
    mov     byte [linkbuf + rax], 0
    mov     rsi, linkbuf
    mov     rdi, [rbx + ND_ARG]
    mov     rdx, [rbx + ND_FLAG]
    call    glob_match
    pop     rbx
    ret
.perm:
    mov     rax, [stbuf + ST_MODE]
    and     rax, 0o7777
    mov     rcx, [rbx + ND_NUM]
    cmp     qword [rbx + ND_FLAG], 0
    jne     .permall
    cmp     rax, rcx
    je      .true
    jmp     .false
.permall:
    and     rax, rcx
    cmp     rax, rcx
    je      .true
    jmp     .false
.user:
    mov     eax, [stbuf + ST_UID]
    cmp     rax, [rbx + ND_NUM]
    je      .true
    jmp     .false
.newer:
    mov     rcx, [rbx + ND_FLAG]
    cmp     rcx, 'a'
    je      .newer_a
    cmp     rcx, 'c'
    je      .newer_c
    mov     rax, [stbuf + ST_MTIME]
    mov     rdx, [stbuf + ST_MTIMENS]
    jmp     .newer_cmp
.newer_a:
    mov     rax, [stbuf + ST_ATIME]
    mov     rdx, [stbuf + ST_ATIMENS]
    jmp     .newer_cmp
.newer_c:
    mov     rax, [stbuf + ST_CTIME]
    mov     rdx, [stbuf + ST_CTIMENS]
.newer_cmp:
    cmp     rax, [rbx + ND_NUM]
    jg      .true
    jl      .false
    cmp     rdx, [rbx + ND_NUM2]
    jg      .true
    jmp     .false
.size:
; only regular files have a size worth comparing
    mov     rax, [stbuf + ST_MODE]
    and     rax, S_IFMT
    cmp     rax, S_IFREG
    jne     .false
    mov     rax, [stbuf + ST_SIZE]
    mov     rcx, [rbx + ND_NUM]
    mov     rdx, [rbx + ND_FLAG]
    cmp     rdx, '+'
    je      .sizegt
    cmp     rdx, '-'
    je      .sizelt
    cmp     rax, rcx
    je      .true
    jmp     .false
.sizegt:
    cmp     rax, rcx
    jg      .true
    jmp     .false
.sizelt:
    cmp     rax, rcx
    jl      .true
    jmp     .false
.samefile:
    mov     rax, [stbuf + ST_INO]
    cmp     rax, [rbx + ND_NUM]
    jne     .false
    mov     rax, [stbuf + ST_DEV]
    cmp     rax, [rbx + ND_NUM2]
    jne     .false
    jmp     .true
.empty:
    mov     rax, [stbuf + ST_SIZE]
    test    rax, rax
    jz      .true
    jmp     .false
.print:
    mov     rsi, pathbuf
    call    out_str
    mov     al, WHITESPACE_NL
    call    out_char
    jmp     .true
.print0:
    mov     rsi, pathbuf
    call    out_str
    xor     al, al
    call    out_char
    jmp     .true
.printf:
    mov     rsi, [rbx + ND_ARG]
    call    do_printf
    jmp     .true
.exec:
    mov     rdi, rbx
    call    do_exec                     ;-> al
    pop     rbx
    ret
.quit:
    mov     byte [quitting], 1
    jmp     .true

; type_letter: the file mode the letter in al stands for, in rcx.
type_letter:
    cmp     al, 'f'
    je      .reg
    cmp     al, 'd'
    je      .dir
    cmp     al, 'l'
    je      .lnk
    cmp     al, 'p'
    je      .fifo
    cmp     al, 's'
    je      .sock
    cmp     al, 'b'
    je      .blk
    cmp     al, 'c'
    je      .chr
    mov     rcx, -1
    ret
.reg:
    mov     rcx, S_IFREG
    ret
.dir:
    mov     rcx, S_IFDIR
    ret
.lnk:
    mov     rcx, S_IFLNK
    ret
.fifo:
    mov     rcx, S_IFIFO
    ret
.sock:
    mov     rcx, S_IFSOCK
    ret
.blk:
    mov     rcx, S_IFBLK
    ret
.chr:
    mov     rcx, S_IFCHR
    ret

; basename_of: the last component of pathbuf, in rsi.
basename_of:
    mov     rsi, pathbuf
    mov     rcx, pathbuf
.scan:
    mov     al, [rcx]
    test    al, al
    jz      .out
    cmp     al, '/'
    jne     .next
    lea     rsi, [rcx + 1]
.next:
    inc     rcx
    jmp     .scan
.out:
    ret

; ---------------------------------------------------------------------------
; glob_match: shell-style matching of the subject at rsi against the pattern
; at rdi. rdx non-zero folds case. al = 1/0.
; ---------------------------------------------------------------------------
glob_match:
    test    rdx, rdx
    jz      glob_here
    push    rsi
    mov     rsi, rdi                    ;fold the pattern
    mov     rdi, lowerpat
    call    copy_lower
    pop     rsi                         ;and the subject
    mov     rdi, lowerbuf
    call    copy_lower
    mov     rdi, lowerpat
    mov     rsi, lowerbuf
    jmp     glob_here

; copy_lower: copy the string at rsi to rdi, lowercased. The text is decoded
; as UTF-8 so -iname folds accented and non-Latin names too, not just ASCII.
; A lowered character can be wider than the one it replaces -- U+023A is two
; bytes and its lowercase U+2C65 is three -- so the destination is bounded on
; every write rather than assumed to be the same length.
copy_lower:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rsi
    mov     r13, rdi
    xor     r14, r14                    ;bytes written
.next:
    movzx   eax, byte [r12]
    test    al, al
    jz      .done
    mov     rbx, 1                      ;bytes in this character
    cmp     al, 0x80
    jb      .have
    mov     rcx, rax
    and     rcx, 0xE0
    cmp     rcx, 0xC0
    je      .two
    mov     rcx, rax
    and     rcx, 0xF0
    cmp     rcx, 0xE0
    je      .three
    mov     rcx, rax
    and     rcx, 0xF8
    cmp     rcx, 0xF0
    je      .four
jmp     .have                       ;not a lead byte: pass it through
.two:
    and     rax, 0x1F
    mov     rbx, 2
    jmp     .continuation
.three:
    and     rax, 0x0F
    mov     rbx, 3
    jmp     .continuation
.four:
    and     rax, 0x07
    mov     rbx, 4
.continuation:
    mov     rcx, 1
.contbyte:
    cmp     rcx, rbx
    jae     .have
    movzx   edx, byte [r12 + rcx]
    mov     r8, rdx
    and     r8, 0xC0
    cmp     r8, 0x80
jne     .raw                        ;truncated sequence: copy it verbatim
    shl     rax, 6
    and     rdx, 0x3F
    or      rax, rdx
    inc     rcx
    jmp     .contbyte
.raw:
    movzx   eax, byte [r12]
    mov     rbx, 1
.have:
    call    lower_codepoint
    mov     rdi, r13
    add     rdi, r14
    mov     rcx, r13
    add     rcx, PATHCAP - 8
    cmp     rdi, rcx
    jae     .done
    call    encode_utf8                 ;-> rax = bytes written
    add     r14, rax
    add     r12, rbx
    jmp     .next
.done:
    mov     byte [r13 + r14], 0
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; lower_codepoint: the lowercase of the code point in rax, for the ranges
; that map by a fixed offset plus the handful of Latin letters whose
; lowercase lives far away in the table.
lower_codepoint:
    cmp     rax, 'A'
    jb      .out
    cmp     rax, 'Z'
    jbe     .plus32
    cmp     rax, 0xC0
    jb      .out
    cmp     rax, 0xDE
    ja      .latinext
    cmp     rax, 0xD7
    je      .out                        ;multiplication sign, not a letter
    jmp     .plus32
.latinext:
    cmp     rax, 0x100
    jb      .out
    cmp     rax, 0x137
    ja      .range139
    test    rax, 1
    jnz     .out
    jmp     .plus1
.range139:
    cmp     rax, 0x139
    jb      .out
    cmp     rax, 0x148
    ja      .range14a
    test    rax, 1
    jz      .out
    jmp     .plus1
.range14a:
    cmp     rax, 0x14A
    jb      .out
    cmp     rax, 0x177
    ja      .single178
    test    rax, 1
    jnz     .out
    jmp     .plus1
.single178:
    cmp     rax, 0x178
    jne     .range179
    mov     rax, 0xFF
    ret
.range179:
    cmp     rax, 0x179
    jb      .out
    cmp     rax, 0x17E
    ja      .single23a
    test    rax, 1
    jz      .out
    jmp     .plus1
.single23a:
    cmp     rax, 0x23A
    jne     .single23e
    mov     rax, 0x2C65                 ;capital A with stroke
    ret
.single23e:
    cmp     rax, 0x23E
    jne     .greek
    mov     rax, 0x2C66                 ;capital T with diagonal stroke
    ret
.greek:
    cmp     rax, 0x391
    jb      .cyrillic
    cmp     rax, 0x3A1
    jbe     .plus32
    cmp     rax, 0x3A3
    jb      .out
    cmp     rax, 0x3AB
    jbe     .plus32
    jmp     .out
.cyrillic:
    cmp     rax, 0x400
    jb      .out
    cmp     rax, 0x40F
    jbe     .plus80
    cmp     rax, 0x410
    jb      .out
    cmp     rax, 0x42F
    jbe     .plus32
.out:
    ret
.plus1:
    inc     rax
    ret
.plus32:
    add     rax, 32
    ret
.plus80:
    add     rax, 0x50
    ret

; encode_utf8: write the code point in rax at rdi. rax comes back as the
; number of bytes written.
encode_utf8:
    cmp     rax, 0x80
    jb      .one
    cmp     rax, 0x800
    jb      .two
    cmp     rax, 0x10000
    jb      .three
    mov     rcx, rax
    shr     rcx, 18
    or      cl, 0xF0
    mov     [rdi], cl
    mov     rcx, rax
    shr     rcx, 12
    and     cl, 0x3F
    or      cl, 0x80
    mov     [rdi + 1], cl
    mov     rcx, rax
    shr     rcx, 6
    and     cl, 0x3F
    or      cl, 0x80
    mov     [rdi + 2], cl
    and     al, 0x3F
    or      al, 0x80
    mov     [rdi + 3], al
    mov     rax, 4
    ret
.three:
    mov     rcx, rax
    shr     rcx, 12
    or      cl, 0xE0
    mov     [rdi], cl
    mov     rcx, rax
    shr     rcx, 6
    and     cl, 0x3F
    or      cl, 0x80
    mov     [rdi + 1], cl
    and     al, 0x3F
    or      al, 0x80
    mov     [rdi + 2], al
    mov     rax, 3
    ret
.two:
    mov     rcx, rax
    shr     rcx, 6
    or      cl, 0xC0
    mov     [rdi], cl
    and     al, 0x3F
    or      al, 0x80
    mov     [rdi + 1], al
    mov     rax, 2
    ret
.one:
    mov     [rdi], al
    mov     rax, 1
    ret

; glob_here: pattern rdi against subject rsi, with '*', '?' and '[...]'.
glob_here:
    movzx   eax, byte [rdi]
    test    al, al
    jz      .end
    cmp     al, '*'
    je      .star
    cmp     al, '['
    je      .class
    cmp     byte [rsi], 0
    je      .no
    cmp     al, '?'
    je      .single
    cmp     al, [rsi]
    jne     .no
.single:
    inc     rdi
    inc     rsi
    jmp     glob_here
.star:
    inc     rdi
    cmp     byte [rdi], 0
    je      .yes                        ;a trailing star matches the rest
.trystar:
    push    rdi
    push    rsi
    call    glob_here
    pop     rsi
    pop     rdi
    test    al, al
    jnz     .yes
    cmp     byte [rsi], 0
    je      .no
    inc     rsi
    jmp     .trystar
.class:
    cmp     byte [rsi], 0
    je      .no
    push    rdi
    push    rsi
    call    class_match                 ;-> al, rdi past the class
    mov     rcx, rdi
    pop     rsi
    pop     rdi
    test    al, al
    jz      .no
    mov     rdi, rcx
    inc     rsi
    jmp     glob_here
.end:
    cmp     byte [rsi], 0
    je      .yes
.no:
    xor     al, al
    ret
.yes:
    mov     al, 1
    ret

; class_match: does the byte at rsi satisfy the bracket expression at rdi?
; rdi comes back just past the closing bracket.
class_match:
    movzx   edx, byte [rsi]
    inc     rdi                         ;past '['
    xor     r8, r8                      ;negated?
    cmp     byte [rdi], '!'
    je      .negate
    cmp     byte [rdi], '^'
    jne     .items
.negate:
    mov     r8, 1
    inc     rdi
.items:
    xor     r9, r9                      ;matched?
    xor     r10, r10                    ;first item?
.item:
    movzx   eax, byte [rdi]
    test    al, al
    jz      .done
    cmp     al, ']'
    jne     .member
    test    r10, r10
    jnz     .done
.member:
    mov     r10, 1
    cmp     byte [rdi + 1], '-'
    jne     .single
    movzx   ecx, byte [rdi + 2]
    test    cl, cl
    jz      .single
    cmp     cl, ']'
    je      .single
    cmp     dl, al
    jb      .skiprange
    cmp     dl, cl
    ja      .skiprange
    mov     r9, 1
.skiprange:
    add     rdi, 3
    jmp     .item
.single:
    cmp     dl, al
    jne     .skipone
    mov     r9, 1
.skipone:
    inc     rdi
    jmp     .item
.done:
    cmp     byte [rdi], ']'
    jne     .result
    inc     rdi
.result:
    test    r8, r8
    jz      .plain
    test    r9, r9
    jz      .yes
    jmp     .no
.plain:
    test    r9, r9
    jnz     .yes
.no:
    xor     al, al
    ret
.yes:
    mov     al, 1
    ret

; ---------------------------------------------------------------------------
; do_printf: -printf, with %f, %p, %P and %s, an optional ".N" that truncates,
; and the escapes find understands. "\c" stops this format early rather than
; ending the run.
; ---------------------------------------------------------------------------
do_printf:
    push    rbx
    push    r12
    mov     rbx, rsi
.scan:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .out
    inc     rbx
    cmp     al, '\'
    je      .escape
    cmp     al, '%'
    je      .directive
    call    out_char
    jmp     .scan
.escape:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .out
    inc     rbx
    cmp     al, 'n'
    je      .e_nl
    cmp     al, 't'
    je      .e_tab
    cmp     al, 'r'
    je      .e_cr
    cmp     al, 'a'
    je      .e_bel
    cmp     al, 'b'
    je      .e_bs
    cmp     al, 'f'
    je      .e_ff
    cmp     al, 'v'
    je      .e_vt
    cmp     al, '\'
    je      .e_lit
    cmp     al, 'c'
    je      .out                        ;"\\c" ends this format only
    cmp     al, '0'
    jb      .e_lit
    cmp     al, '7'
    ja      .e_lit
; an octal escape of up to three digits
    movzx   r8d, al
    sub     r8b, '0'
    mov     r9, 1
.octal:
    cmp     r9, 3
    jae     .octdone
    movzx   eax, byte [rbx]
    sub     al, '0'
    cmp     al, 7
    ja      .octdone
    shl     r8, 3
    movzx   eax, al
    add     r8, rax
    inc     rbx
    inc     r9
    jmp     .octal
.octdone:
    mov     al, r8b
    call    out_char
    jmp     .scan
.e_nl:
    mov     al, WHITESPACE_NL
    call    out_char
    jmp     .scan
.e_tab:
    mov     al, WHITESPACE_TAB
    call    out_char
    jmp     .scan
.e_cr:
    mov     al, 13
    call    out_char
    jmp     .scan
.e_bel:
    mov     al, 7
    call    out_char
    jmp     .scan
.e_bs:
    mov     al, 8
    call    out_char
    jmp     .scan
.e_ff:
    mov     al, 12
    call    out_char
    jmp     .scan
.e_vt:
    mov     al, 11
    call    out_char
    jmp     .scan
.e_lit:
    call    out_char
    jmp     .scan
.directive:
    mov     r12, -1                     ;no precision given
    cmp     byte [rbx], '.'
    jne     .conversion
    inc     rbx
    xor     r12, r12
.precision:
    movzx   eax, byte [rbx]
    sub     al, '0'
    cmp     al, 9
    ja      .conversion
    imul    r12, r12, 10
    movzx   eax, al
    add     r12, rax
    inc     rbx
    jmp     .precision
.conversion:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .out
    inc     rbx
    cmp     al, 'f'
    je      .conv_f
    cmp     al, 'p'
    je      .conv_p
    cmp     al, 'P'
    je      .conv_P
    cmp     al, 's'
    je      .conv_s
    cmp     al, '%'
    je      .conv_pct
    call    out_char
    jmp     .scan
.conv_f:
    call    basename_of
    mov     rdi, r12
    call    out_str_limited
    jmp     .scan
.conv_p:
    mov     rsi, pathbuf
    mov     rdi, r12
    call    out_str_limited
    jmp     .scan
.conv_P:
; the path with the starting point, and the slash after it, taken off
    mov     rsi, pathbuf
    add     rsi, [rootlen]
    cmp     byte [rsi], '/'
    jne     .relative
    inc     rsi
.relative:
    mov     rdi, r12
    call    out_str_limited
    jmp     .scan
.conv_s:
    mov     rax, [stbuf + ST_SIZE]
    call    out_num
    jmp     .scan
.conv_pct:
    mov     al, '%'
    call    out_char
    jmp     .scan
.out:
    pop     r12
    pop     rbx
    ret

; out_str_limited: the string at rsi, at most rdi bytes when rdi is not -1.
out_str_limited:
    push    rbx
    push    r12
    mov     rbx, rsi
    mov     r12, rdi
.copy:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .out
    cmp     r12, -1
    je      .emit
    test    r12, r12
    jz      .out
    dec     r12
.emit:
    call    out_char
    inc     rbx
    jmp     .copy
.out:
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; do_exec: run the command in the node at rdi. The ";" form runs once per
; file and reports its exit status; the "+" form gathers paths and runs when
; the batch is full or the walk ends, and is always true.
; ---------------------------------------------------------------------------
do_exec:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    cmp     qword [rbx + ND_FLAG], 0
    jne     .batch

; build argv, substituting the path for every "{}"
    mov     r12, [rbx + ND_ARG]
    mov     r13, [rbx + ND_NUM]
    xor     rcx, rcx
.word:
    cmp     rcx, r13
    jge     .terminate
    lea     rax, [r12 + rcx]
    mov     rax, [execargv + rax * 8]
    push    rcx
    mov     rdi, rax
    mov     rsi, p_brace
    call    streq
    pop     rcx
    test    al, al
    jz      .plainword
    mov     qword [runargv + rcx * 8], pathbuf
    jmp     .wordnext
.plainword:
    lea     rax, [r12 + rcx]
    mov     rax, [execargv + rax * 8]
    mov     [runargv + rcx * 8], rax
.wordnext:
    inc     rcx
    jmp     .word
.terminate:
    mov     qword [runargv + rcx * 8], 0
    call    run_argv                    ;-> al = 1 when it exited zero
    pop     r13
    pop     r12
    pop     rbx
    ret
.batch:
    mov     rdi, rbx
    call    stash_path
    pop     r13
    pop     r12
    pop     rbx
    mov     al, 1
    ret

; stash_path: remember the current path for a "+" style -exec.
stash_path:
    push    rbx
    mov     rbx, rdi
    mov     rax, [execnode]
    cmp     rax, rbx
    je      .append
    test    rax, rax
    jz      .start
call    flush_exec                  ;a different command: run the old one
.start:
    mov     [execnode], rbx
    mov     qword [batchcount], 0
    mov     qword [execfree], 0
.append:
    mov     rcx, [batchcount]
    cmp     rcx, EXECARGS - 4
    jae     .full
    mov     rax, [execfree]
    lea     rdx, [rax + PATHCAP]
    cmp     rdx, EXECBUF
    jae     .full
    lea     rdi, [execbuf + rax]
    mov     [batchargs + rcx * 8], rdi
    mov     rsi, pathbuf
    call    copy_str                    ;-> rax = length copied
    mov     rcx, [execfree]
    add     rcx, rax
    inc     rcx
    mov     [execfree], rcx
    inc     qword [batchcount]
    pop     rbx
    ret
.full:
    call    flush_exec
    pop     rbx
    mov     rdi, rbx
    jmp     stash_path

; flush_exec: run the pending "+" batch, if there is one.
flush_exec:
    push    rbx
    push    r12
    push    r13
    mov     rbx, [execnode]
    test    rbx, rbx
    jz      .out
    cmp     qword [batchcount], 0
    je      .out
    mov     r12, [rbx + ND_ARG]
    mov     r13, [rbx + ND_NUM]
    xor     rcx, rcx
    xor     r8, r8                      ;destination index
.word:
    cmp     rcx, r13
    jge     .paths
    lea     rax, [r12 + rcx]
    mov     rax, [execargv + rax * 8]
    push    rcx
    push    r8
    mov     rdi, rax
    mov     rsi, p_brace
    call    streq
    pop     r8
    pop     rcx
    test    al, al
    jnz     .skipbrace                  ;the paths go where "{}" was
    lea     rax, [r12 + rcx]
    mov     rax, [execargv + rax * 8]
    mov     [runargv + r8 * 8], rax
    inc     r8
.skipbrace:
    inc     rcx
    jmp     .word
.paths:
    xor     rcx, rcx
.path:
    cmp     rcx, [batchcount]
    jge     .terminate
    mov     rax, [batchargs + rcx * 8]
    mov     [runargv + r8 * 8], rax
    inc     r8
    inc     rcx
    jmp     .path
.terminate:
    mov     qword [runargv + r8 * 8], 0
    call    run_argv
    mov     qword [batchcount], 0
    mov     qword [execfree], 0
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; run_argv: fork and run runargv. al = 1 when the child exited zero.
run_argv:
    push    rbx
    mov     rax, SYS_FORK
    syscall
    test    rax, rax
    js      .fail
    jnz     .parent
    call    out_flush                   ;the child inherits our buffer
    mov     rdi, [runargv]
    mov     rsi, runargv
    mov     rdx, [envp]
    call    exec_path
    exit    127
.parent:
    mov     rbx, rax
    call    out_flush                   ;keep our output ahead of the child's
    mov     rax, SYS_WAIT4
    mov     rdi, rbx
    mov     rsi, wstatus
    xor     rdx, rdx
    xor     r10, r10
    syscall
    mov     eax, [wstatus]
    test    eax, eax
    jnz     .fail
    mov     al, 1
    pop     rbx
    ret
.fail:
    xor     al, al
    pop     rbx
    ret

section .bss
    runargv     resq EXECCAP
    batchargs   resq EXECARGS
    batchcount  resq 1
    wstatus     resq 1
    namestash   resb PATHCAP
    execpath    resb PATHCAP
    dirbufs     resb (MAXDEPTH * DIRCAP)
    tree        resq 1
    levelbuf    resq 1

section .text

; ---------------------------------------------------------------------------
; exec_path: execve rdi with argv rsi and envp rdx, searching PATH when the
; command name has no slash in it -- "-exec ls" has to find ls the way a
; shell would. Returns only when nothing could be executed.
; ---------------------------------------------------------------------------
exec_path:
    mov     r13, rdi
    mov     r14, rsi
    mov     r15, rdx
    xor     rcx, rcx
.slash:
    mov     al, [r13 + rcx]
    test    al, al
    je      .search
    cmp     al, '/'
    je      .direct
    inc     rcx
    jmp     .slash
.direct:
    mov     rdi, r13
    mov     rsi, r14
    mov     rdx, r15
    mov     rax, SYS_EXECVE
    syscall
    ret
.search:
    mov     rbx, r15
.env:
    mov     rdi, [rbx]
    test    rdi, rdi
    je      .out
    cmp     dword [rdi], 'PATH'
    jne     .envnext
    cmp     byte [rdi + 4], '='
    je      .havepath
.envnext:
    add     rbx, 8
    jmp     .env
.havepath:
    lea     r12, [rdi + 5]
.dir:
    mov     al, [r12]
    test    al, al
    je      .out
    mov     rdi, execpath
    mov     rbx, rdi
cmp     al, ':'
    jne     .copydir
    mov     byte [rbx], '.'
    inc     rbx
    jmp     .enddir
.copydir:
    mov     al, [r12]
    test    al, al
    je      .enddir
cmp     al, ':'
    je      .enddir
    mov     [rbx], al
    inc     rbx
    inc     r12
    mov     rax, execpath + PATHCAP - 2
    cmp     rbx, rax
    jae     .nextdir
    jmp     .copydir
.enddir:
    cmp     rbx, rdi
    je      .emptydir
    mov     al, [rbx - 1]
    cmp     al, '/'
    je      .copycmd
    mov     byte [rbx], '/'
    inc     rbx
    jmp     .copycmd
.emptydir:
    mov     byte [rbx], '.'
    inc     rbx
    mov     byte [rbx], '/'
    inc     rbx
.copycmd:
    xor     rcx, rcx
.cmdbyte:
    mov     al, [r13 + rcx]
    mov     [rbx], al
    test    al, al
    je      .try
    inc     rbx
    inc     rcx
    mov     rax, execpath + PATHCAP - 1
    cmp     rbx, rax
    jae     .nextdir
    jmp     .cmdbyte
.try:
    mov     rdi, execpath
    mov     rsi, r14
    mov     rdx, r15
    mov     rax, SYS_EXECVE
    syscall
.nextdir:
    mov     al, [r12]
cmp     al, ':'
    jne     .dir
    inc     r12
    jmp     .dir
.out:
    ret

; ---------------------------------------------------------------------------
; Paths.
; ---------------------------------------------------------------------------
; set_path: pathbuf becomes the string at rsi, with any trailing slashes
; trimmed so "/etc/" plus "passwd" does not come out doubled.
set_path:
    xor     rcx, rcx
.copy:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .trim
    cmp     rcx, PATHCAP - 2
    jae     .trim
    mov     [pathbuf + rcx], al
    inc     rcx
    jmp     .copy
.trim:
    cmp     rcx, 1
    jbe     .done
    cmp     byte [pathbuf + rcx - 1], '/'
    jne     .done
    dec     rcx
    jmp     .trim
.done:
    mov     byte [pathbuf + rcx], 0
    mov     [pathlen], rcx
    ret

; path_push: append "/" and the name at rsi to pathbuf.
path_push:
    mov     rcx, [pathlen]
    cmp     rcx, 0
    je      .name
    cmp     byte [pathbuf + rcx - 1], '/'
    je      .name
    cmp     rcx, PATHCAP - 2
    jae     .name
    mov     byte [pathbuf + rcx], '/'
    inc     rcx
.name:
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     rcx, PATHCAP - 2
    jae     .done
    mov     [pathbuf + rcx], al
    inc     rcx
    inc     rsi
    jmp     .name
.done:
    mov     byte [pathbuf + rcx], 0
    mov     [pathlen], rcx
    ret

; copy_str: copy the string at rsi to rdi. rax is the length copied.
copy_str:
    xor     rcx, rcx
.copy:
    mov     al, [rsi + rcx]
    mov     [rdi + rcx], al
    test    al, al
    jz      .out
    inc     rcx
    cmp     rcx, PATHCAP - 1
    jae     .term
    jmp     .copy
.term:
    mov     byte [rdi + rcx], 0
.out:
    mov     rax, rcx
    ret

; stat_follow: stat rdi into rsi, following symlinks.
stat_follow:
    mov     rax, SYS_STAT
    syscall
    ret

; warn_path: report the current path as unreachable.
warn_path:
    mov     rsi, e_noent
warn_path_reason:
    push    rsi
    mov     rsi, e_pre
    call    err_str
    mov     rsi, pathbuf
    call    err_str
    pop     rsi
    jmp     err_str

; ---------------------------------------------------------------------------
; Values.
; ---------------------------------------------------------------------------
; parse_size: "[+-]N[cwbkMG]". rax is the value in bytes, rdx the comparison
; ('+', '-' or 0 for exact).
parse_size:
    xor     rdx, rdx
    movzx   eax, byte [rdi]
    cmp     al, '+'
    je      .signed
    cmp     al, '-'
    jne     .digits
.signed:
    movzx   edx, al
    inc     rdi
.digits:
    push    rdx
    call    atou
    pop     rdx
    movzx   ecx, byte [rdi]
    cmp     cl, 'c'
    je      .out
    cmp     cl, 'w'
    je      .words
    cmp     cl, 'k'
    je      .kilo
    cmp     cl, 'M'
    je      .mega
    cmp     cl, 'G'
    je      .giga
    shl     rax, 9                      ;512-byte blocks by default
    ret
.words:
    shl     rax, 1
    ret
.kilo:
    shl     rax, 10
    ret
.mega:
    shl     rax, 20
    ret
.giga:
    shl     rax, 30
.out:
    ret

; parse_timespec: "@SECONDS[.FRACTION]". rax is seconds, rdx nanoseconds.
parse_timespec:
    xor     rdx, rdx
    cmp     byte [rdi], '@'
    jne     .plain
    inc     rdi
.plain:
    call    atou
    push    rax
    cmp     byte [rdi], '.'
    jne     .none
    inc     rdi
    xor     rax, rax
    xor     r8, r8
.frac:
    movzx   ecx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .scale
    cmp     r8, 9
    jae     .skip
    imul    rax, rax, 10
    movzx   ecx, cl
    add     rax, rcx
    inc     r8
.skip:
    inc     rdi
    jmp     .frac
.scale:
    cmp     r8, 9
    jae     .done
    imul    rax, rax, 10
    inc     r8
    jmp     .scale
.done:
    mov     rdx, rax
    pop     rax
    ret
.none:
    pop     rax
    xor     rdx, rdx
    ret

; user_id: the numeric id of the user named by rdi, from /etc/passwd. A name
; that is already a number is taken as one.
user_id:
    push    rbx
    mov     rbx, rdi
    call    all_digits
    test    al, al
    jz      .lookup
    mov     rdi, rbx
    call    atou
    pop     rbx
    ret
.lookup:
    call    load_passwd
    mov     rdi, rbx
    call    passwd_uid
    pop     rbx
    ret

all_digits:
    xor     rcx, rcx
.scan:
    movzx   eax, byte [rdi + rcx]
    test    al, al
    jz      .end
    sub     al, '0'
    cmp     al, 9
    ja      .no
    inc     rcx
    jmp     .scan
.end:
    test    rcx, rcx
    jz      .no
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

load_passwd:
    cmp     byte [pw_loaded], 0
    jne     .out
    mov     byte [pw_loaded], 1
    mov     rax, SYS_OPEN
    mov     rdi, passwd_path
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .out
    mov     r8, rax
    xor     r9, r9
.read:
    mov     rax, SYS_READ
    mov     rdi, r8
    lea     rsi, [pwbuf + r9]
    mov     rdx, PWCAP
    sub     rdx, r9
    jle     .close
    push    r8
    push    r9
    syscall
    pop     r9
    pop     r8
    test    rax, rax
    jle     .close
    add     r9, rax
    jmp     .read
.close:
    mov     [pwlen], r9
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
.out:
    ret

; passwd_uid: the id belonging to the login name at rdi, or -1.
passwd_uid:
    push    rbx
    mov     r10, [pwlen]
    xor     rcx, rcx                    ;line start
.line:
    cmp     rcx, r10
    jae     .none
    mov     r11, rcx
    xor     rbx, rbx                    ;index into the wanted name
.name:
    cmp     r11, r10
    jae     .none
    movzx   eax, byte [pwbuf + r11]
cmp     al, ':'
    je      .checkname
    cmp     al, WHITESPACE_NL
    je      .nextline
    movzx   edx, byte [rdi + rbx]
    cmp     al, dl
    jne     .skipline
    inc     rbx
    inc     r11
    jmp     .name
.checkname:
    cmp     byte [rdi + rbx], 0
    jne     .skipline
    inc     r11
.skippw:
    cmp     r11, r10
    jae     .none
    movzx   eax, byte [pwbuf + r11]
    inc     r11
cmp     al, ':'
    jne     .skippw
    xor     rax, rax
    xor     rbx, rbx
.digit:
    cmp     r11, r10
    jae     .found
    movzx   edx, byte [pwbuf + r11]
    sub     dl, '0'
    cmp     dl, 9
    ja      .found
    imul    rax, rax, 10
    add     rax, rdx
    inc     rbx
    inc     r11
    jmp     .digit
.found:
    test    rbx, rbx
    jz      .none
    pop     rbx
    ret
.skipline:
.nextline:
    cmp     r11, r10
    jae     .none
    cmp     byte [pwbuf + r11], WHITESPACE_NL
    je      .advance
    inc     r11
    jmp     .nextline
.advance:
    lea     rcx, [r11 + 1]
    jmp     .line
.none:
    mov     rax, -1
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Small helpers and output.
; ---------------------------------------------------------------------------
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

; atoo: an octal number, as -perm writes them.
atoo:
    xor     rax, rax
.scan:
    movzx   rcx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 7
    ja      .out
    shl     rax, 3
    add     rax, rcx
    inc     rdi
    jmp     .scan
.out:
    ret

err_str:
    push    rsi
    call    out_flush
    pop     rsi
    push    rsi
    mov     rdi, rsi
    call    strlen_z
    mov     rdx, rax
    pop     rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    ret

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
    mov     byte [rdi], 0
    mov     rsi, numbuf
    call    out_str
    pop     rbx
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
