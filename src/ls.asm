; src/ls.asm -- ls(1): list directory contents.
; Usage: ls [-1CxmlodaAFpiRrtcuSXUfkbqNZ] [-w COLS] [--full-time]
;           [--group-directories-first] [FILE...]
;
; Entries are collected, stat'd, sorted and only then printed, because every
; layout needs to know the whole set first: column widths, the -l field
; widths, and the "total" line all depend on it.
;
; Column mode packs as many columns as fit. A column is as wide as its widest
; entry plus two spaces, except the last, which needs no trailing gap; the
; screen budget is the requested width plus two, matching how -w is counted.
; Vertical order (-C) fills down each column, and when the last column comes
; up short the remaining entries shift along the right edge so the rows stay
; rectangular.
;
; Which timestamp is used, and whether it also sorts, follows ls's rule: -u
; and -c choose atime or ctime, -t sorts by whichever that is, and with -l but
; no -t they only change what is shown while the order stays by name.
;
; Timestamps are rendered in local time by reading the zoneinfo file and
; taking the offset in effect at that moment, so entries either side of a
; daylight saving change are each shown correctly.

    %include "include/sysdefs.inc"

    %define SYS_LSTAT 6
    %define SYS_FSTATAT 262
    %define SYS_CLOCK_GETTIME_ID 228

    %define AT_SYMLINK_NOFOLLOW 0x100

    %define ENTCAP 200000
    %define ENTSIZE 144
    %define NAMECAP (8 * 1024 * 1024)
    %define DIRCAP 65536
    %define OUTCAP 65536
    %define OUTHIGH (OUTCAP - 4096)
    %define PATHCAP 4096
    %define PWCAP 65536
    %define TZCAP 65536
    %define MAXOPERANDS 4096
    %define MAXCOLS 1024

; entry record fields
    %define E_NAME 0
    %define E_NAMELEN 8
    %define E_MODE 16
    %define E_NLINK 24
    %define E_UID 32
    %define E_GID 40
    %define E_SIZE 48
    %define E_MTIME 56
    %define E_ATIME 64
    %define E_CTIME 72
    %define E_INO 80
    %define E_BLOCKS 88
    %define E_RDEV 96
    %define E_MTIMENS 104
    %define E_ATIMENS 112
    %define E_CTIMENS 120
    %define E_STATOK 128
    %define E_DISPLEN 136

; struct stat offsets
    %define ST_DEV 0
    %define ST_INO 8
    %define ST_NLINK 16
    %define ST_MODE 24
    %define ST_UID 28
    %define ST_GID 32
    %define ST_RDEV 40
    %define ST_SIZE 48
    %define ST_BLOCKS 64
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
    %define S_ISUID 0o4000
    %define S_ISGID 0o2000
    %define S_ISVTX 0o1000

; sort keys
    %define SORT_NAME 0
    %define SORT_TIME 1
    %define SORT_SIZE 2
    %define SORT_EXT 3
    %define SORT_NONE 4

    struc dirent64
    .d_ino      resq 1
    .d_off      resq 1
    .d_reclen   resw 1
    .d_type     resb 1
    .d_name     resb 1
    endstruc

section .bss
    entries     resb ENTCAP * ENTSIZE
    entptr      resq 1
    ordarena    resq (2 * ENTCAP)
    ordfree     resq 1
    colsizes    resd MAXCOLS
    namearena   resb NAMECAP
    namefree    resq 1
    dirbuf      resb DIRCAP
    outbuf      resb OUTCAP
    outlen      resq 1
    pathbuf     resb PATHCAP
    pathlen     resq 1
    linkbuf     resb PATHCAP
    dispbuf     resb PATHCAP
    displen     resq 1
    numbuf      resb 64
    datebuf     resb 128
    modebuf     resb 16
    pwbuf       resb PWCAP
    grbuf       resb PWCAP
    tzbuf       resb TZCAP
    stbuf       resb 160
    tsbuf       resq 2
    operands    resq MAXOPERANDS
    noperands   resq 1
    fileidx     resq MAXOPERANDS
    nfileops    resq 1
    diridx      resq MAXOPERANDS
    ndirops     resq 1
    nents       resq 1
    screen_w    resq 1
    now         resq 1
    tz_offset   resq 1
    tz_len      resq 1
    tz_v2off    resq 1
    tz_timecnt  resq 1
    tz_typecnt  resq 1
    tz_transoff resq 1
    tz_idxoff   resq 1
    tz_ttoff    resq 1
    tz_wide     resq 1
    pwlen       resq 1
    grlen       resq 1
    envp        resq 1
    dirfd       resq 1
    batchlen    resq 1
    batchpos    resq 1
    curent      resq 1
    totpad      resq 1
    ncols       resq 1
    datelen     resq 1
    sizelen     resq 1
    tz_len_of_block resq 1
    cv_year     resq 1
    cv_mon      resq 1
    cv_day      resq 1
    cv_hour     resq 1
    cv_min      resq 1
    cv_sec      resq 1
    tzpath      resb PATHCAP
    idbuf       resb 32
    ubuf        resb 256
    gbuf        resb 256
    lk_dest     resq 1
    winbuf      resb 64
    w_ino       resq 1
    w_nlink     resq 1
    w_user      resq 1
    w_group     resq 1
    w_size      resq 1
    w_ctx       resq 1
    total_blocks resq 1
    anyout      resb 1
    tz_loaded   resb 1
    pw_loaded   resb 1
    opt_one     resb 1
    opt_col     resb 1
    opt_across  resb 1
    opt_comma   resb 1
    opt_long    resb 1
    opt_nogroup resb 1
    opt_all     resb 1
    opt_almost  resb 1
    opt_dironly resb 1
    opt_recurse resb 1
    opt_slash   resb 1
    opt_class   resb 1
    opt_inode   resb 1
    opt_rev     resb 1
    opt_time    resb 1
    opt_ctime   resb 1
    opt_atime   resb 1
    opt_size    resb 1
    opt_ext     resb 1
    opt_nosort  resb 1
    opt_escape  resb 1
    opt_quest   resb 1
    opt_raw     resb 1
    opt_ctx     resb 1
    opt_fulltime resb 1
    opt_human   resb 1
    opt_dirsfirst resb 1
    sortkey     resb 1
    timefield   resb 1
    status      resb 1
    is_dirlist  resb 1
    have_w      resb 1

section .data
    l_fulltime  db "--full-time", 0
    l_dirsfirst db "--group-directories-first", 0
    l_showctl   db "--show-control-chars", 0
    l_all       db "--all", 0
    l_almost    db "--almost-all", 0
    l_reverse   db "--reverse", 0
    l_recursive db "--recursive", 0
    l_width     db "--width", 0
    l_color     db "--color", 0

    dot_name    db ".", 0
    zoneinfo    db "/usr/share/zoneinfo/", 0
    localtime_p db "/etc/localtime", 0
    tz_env      db "TZ", 0
    passwd_path db "/etc/passwd", 0
    group_path  db "/etc/group", 0
    tzif_magic  db "TZif"

    months      db "JanFebMarAprMayJunJulAugSepOctNovDec"
    size_units  db "KMGTPE"
    total_str   db "total ", 0
    arrow_str   db " -> ", 0
    comma_str   db ", ", 0
colon_str   db ":", 0
    noctx_str   db "?", 0
err_pre     db "ls: cannot access '", 0
err_post    db "': No such file or directory", 10, 0
usage_msg   db "Usage: ls [-1CxmlodaAFpiRrtcuSXUfkbqNZ] [-w COLS] [FILE...]", 10
    usage_len   equ $ - usage_msg
    modechars   db "rwxrwxrwx"
    typechars   db "?pc?d?b?-?l?s???"
    esc_letters db "abtnvfr"

section .text
global _start

_start:
    mov     qword [namefree], namearena
    mov     qword [entptr], entries
    mov     qword [ordfree], ordarena
    mov     qword [screen_w], 80

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12
    lea     rax, [rsp + r12 * 8 + 24]
    mov     [envp], rax

parse:
    cmp     r12, 0
    jle     setup
    mov     rdi, [r13]
    test    rdi, rdi
    jz      setup
    cmp     byte [rdi], '-'
    jne     .operand
    cmp     byte [rdi + 1], 0
    je      .operand                    ;a lone "-" is a file name
    cmp     byte [rdi + 1], '-'
    jne     .short
    cmp     byte [rdi + 2], 0
    jne     .long
    add     r13, 8                      ;"--" ends the options
    dec     r12
    jmp     .tail
.long:
    mov     rsi, l_fulltime
    call    longmatch
    test    al, al
    jnz     .f_fulltime
    mov     rsi, l_dirsfirst
    call    longmatch
    test    al, al
    jnz     .f_dirsfirst
    mov     rsi, l_showctl
    call    longmatch
    test    al, al
    jnz     .f_raw
    mov     rsi, l_all
    call    longmatch
    test    al, al
    jnz     .f_all
    mov     rsi, l_almost
    call    longmatch
    test    al, al
    jnz     .f_almost
    mov     rsi, l_reverse
    call    longmatch
    test    al, al
    jnz     .f_rev
    mov     rsi, l_recursive
    call    longmatch
    test    al, al
    jnz     .f_recurse
    mov     rsi, l_width
    call    longmatch
    test    al, al
    jnz     .f_widthlong
    mov     rsi, l_color
    call    longmatch
    test    al, al
    jnz     .next                       ;colour is never used here
    jmp     usage
.f_fulltime:
    mov     byte [opt_fulltime], 1
    mov     byte [opt_long], 1
    jmp     .next
.f_dirsfirst:
    mov     byte [opt_dirsfirst], 1
    jmp     .next
.f_widthlong:
    cmp     al, 2
    je      .widthval
    call    next_value
.widthval:
    mov     rdi, rdx
    call    atou
    mov     [screen_w], rax
    mov     byte [have_w], 1
    jmp     .next

.short:
    lea     rsi, [rdi + 1]
.flag:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .next
    inc     rsi
    cmp     al, '1'
    je      .f_one
    cmp     al, 'C'
    je      .f_col
    cmp     al, 'x'
    je      .f_across
    cmp     al, 'm'
    je      .f_comma
    cmp     al, 'l'
    je      .f_long
    cmp     al, 'o'
    je      .f_o
    cmp     al, 'a'
    je      .f_all
    cmp     al, 'A'
    je      .f_almost
    cmp     al, 'd'
    je      .f_dironly
    cmp     al, 'R'
    je      .f_recurse
    cmp     al, 'p'
    je      .f_slash
    cmp     al, 'F'
    je      .f_class
    cmp     al, 'i'
    je      .f_inode
    cmp     al, 'r'
    je      .f_rev
    cmp     al, 't'
    je      .f_time
    cmp     al, 'c'
    je      .f_ctime
    cmp     al, 'u'
    je      .f_atime
    cmp     al, 'S'
    je      .f_size
    cmp     al, 'X'
    je      .f_ext
    cmp     al, 'U'
    je      .f_nosort
    cmp     al, 'f'
    je      .f_f
    cmp     al, 'b'
    je      .f_escape
    cmp     al, 'q'
    je      .f_quest
    cmp     al, 'N'
    je      .f_raw
    cmp     al, 'Z'
    je      .f_ctx
    cmp     al, 'w'
    je      .f_width
    cmp     al, 'k'
    je      .flag                       ;sizes are already in 1K units
    cmp     al, 'h'
    je      .f_human
    cmp     al, 'L'
    je      .flag
    cmp     al, 'H'
    je      .flag
    cmp     al, 'g'
    je      .f_long
    cmp     al, 'n'
    je      .f_long
    cmp     al, 's'
    je      .flag
    jmp     usage
.f_one:
    mov     byte [opt_one], 1
    jmp     .flag
.f_col:
    mov     byte [opt_col], 1
    jmp     .flag
.f_across:
    mov     byte [opt_across], 1
    jmp     .flag
.f_comma:
    mov     byte [opt_comma], 1
    jmp     .flag
.f_long:
    mov     byte [opt_long], 1
    jmp     .flag
.f_o:
    mov     byte [opt_long], 1
    mov     byte [opt_nogroup], 1
    jmp     .flag
.f_all:
    mov     byte [opt_all], 1
    jmp     .flag
.f_almost:
    mov     byte [opt_almost], 1
    jmp     .flag
.f_dironly:
    mov     byte [opt_dironly], 1
    mov     byte [opt_recurse], 0
    jmp     .flag
.f_recurse:
    mov     byte [opt_recurse], 1
    jmp     .flag
.f_slash:
    mov     byte [opt_slash], 1
    jmp     .flag
.f_class:
    mov     byte [opt_class], 1
    jmp     .flag
.f_inode:
    mov     byte [opt_inode], 1
    jmp     .flag
.f_rev:
    mov     byte [opt_rev], 1
    jmp     .flag
.f_time:
    mov     byte [opt_time], 1
    jmp     .flag
.f_ctime:
    mov     byte [opt_ctime], 1
    jmp     .flag
.f_atime:
    mov     byte [opt_atime], 1
    jmp     .flag
.f_size:
    mov     byte [opt_size], 1
    jmp     .flag
.f_ext:
    mov     byte [opt_ext], 1
    jmp     .flag
.f_nosort:
    mov     byte [opt_nosort], 1
    jmp     .flag
.f_f:
    mov     byte [opt_nosort], 1
    mov     byte [opt_all], 1
    jmp     .flag
.f_escape:
    mov     byte [opt_escape], 1
    jmp     .flag
.f_quest:
    mov     byte [opt_quest], 1
    jmp     .flag
.f_raw:
    mov     byte [opt_raw], 1
    jmp     .flag
.f_human:
    mov     byte [opt_human], 1
    jmp     .flag
.f_ctx:
    mov     byte [opt_ctx], 1
    jmp     .flag
.f_width:
    call    opt_value
    mov     rdi, rdx
    call    atou
    mov     [screen_w], rax
    mov     byte [have_w], 1
    jmp     .next
.operand:
    call    add_operand
.next:
    add     r13, 8
    dec     r12
    jmp     parse
.tail:
    cmp     r12, 0
    jle     setup
    mov     rdi, [r13]
    test    rdi, rdi
    jz      setup
    call    add_operand
    add     r13, 8
    dec     r12
    jmp     .tail

; opt_value: the rest of this bundle is the value, or the next argument is.
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
    jz      usage
    ret

; longmatch: rdi against the option at rsi. al = 1 bare, 2 with rdx = value.
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

add_operand:
    mov     rcx, [noperands]
    cmp     rcx, MAXOPERANDS
    jae     .out
    mov     [operands + rcx * 8], rdi
    inc     rcx
    mov     [noperands], rcx
.out:
    ret

usage:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, usage_msg
    mov     rdx, usage_len
    syscall
    exit    2

; ---------------------------------------------------------------------------
; setup: resolve the flags that depend on each other, and on whether stdout
; is a terminal.
; ---------------------------------------------------------------------------
setup:
    call    is_tty
    test    al, al
    jz      .notty
    cmp     byte [opt_raw], 0
    jne     .ttymode
    mov     byte [opt_escape], 1        ;a terminal gets control characters hidden
.ttymode:
    cmp     byte [opt_long], 0
    je      .maybecol
    mov     byte [opt_one], 1
    jmp     .width
.maybecol:
    cmp     byte [opt_one], 0
    jne     .width
    cmp     byte [opt_across], 0
    jne     .width
    cmp     byte [opt_comma], 0
    jne     .width
    mov     byte [opt_col], 1
    jmp     .width
.notty:
    cmp     byte [opt_comma], 0
    jne     .width
    mov     byte [opt_one], 1
.width:
    cmp     byte [opt_raw], 0
    je      .screen
    mov     byte [opt_escape], 0        ;-N turns the escaping back off
.screen:
    cmp     byte [have_w], 0
    je      .defwidth
    mov     rax, [screen_w]
    add     rax, 2                      ;-w counts the usable columns
    mov     [screen_w], rax
    jmp     .clamp
.defwidth:
    call    terminal_width
.clamp:
    cmp     qword [screen_w], 2
    jae     .sortkey
    mov     qword [screen_w], 2

.sortkey:
    mov     al, SORT_NAME
    cmp     byte [opt_nosort], 0
    jne     .setnone
    cmp     byte [opt_ext], 0
    jne     .setext
    cmp     byte [opt_size], 0
    jne     .setsize
    cmp     byte [opt_time], 0
    jne     .settime
; -u and -c sort by their timestamp on their own, but with -l they only
; change which one is displayed
    cmp     byte [opt_long], 0
    jne     .store
    cmp     byte [opt_ctime], 0
    jne     .settime
    cmp     byte [opt_atime], 0
    jne     .settime
    jmp     .store
.setnone:
    mov     al, SORT_NONE
    jmp     .store
.setext:
    mov     al, SORT_EXT
    jmp     .store
.setsize:
    mov     al, SORT_SIZE
    jmp     .store
.settime:
    mov     al, SORT_TIME
.store:
    mov     [sortkey], al
    mov     al, 'm'
    cmp     byte [opt_ctime], 0
    je      .checkatime
    mov     al, 'c'
    jmp     .settimefield
.checkatime:
    cmp     byte [opt_atime], 0
    je      .settimefield
    mov     al, 'a'
.settimefield:
    mov     [timefield], al

    call    read_now
    cmp     qword [noperands], 0
    jne     run
    mov     qword [operands], dot_name
    mov     qword [noperands], 1

; ---------------------------------------------------------------------------
; run: operands split into non-directories, listed together first, and
; directories, each listed in turn.
; ---------------------------------------------------------------------------
run:
    xor     rbx, rbx
.classify:
    cmp     rbx, [noperands]
    jge     .files
    mov     rdi, [operands + rbx * 8]
    call    stat_operand                ;-> al = 1 when it could be stat'd
    test    al, al
    jz      .missing
    cmp     byte [opt_dironly], 0
    jne     .asfile
    mov     eax, [stbuf + ST_MODE]
    and     eax, S_IFMT
    cmp     eax, S_IFDIR
    je      .asdir
.asfile:
    mov     rcx, [nfileops]
    mov     [fileidx + rcx * 8], rbx
    inc     qword [nfileops]
    jmp     .cnext
.asdir:
    mov     rcx, [ndirops]
    mov     [diridx + rcx * 8], rbx
    inc     qword [ndirops]
    jmp     .cnext
.missing:
    mov     byte [status], 2
    mov     rdi, [operands + rbx * 8]
    call    warn_missing
.cnext:
    inc     rbx
    jmp     .classify

.files:
    cmp     qword [nfileops], 0
    je      .dirs
    mov     byte [is_dirlist], 0        ;operands are not a directory listing
    mov     r13, [entptr]               ;first entry of this batch
    xor     rbx, rbx
.filoop:
    cmp     rbx, [nfileops]
    jge     .fildone
    mov     rcx, [fileidx + rbx * 8]
    mov     rdi, [operands + rcx * 8]
    call    set_path
    mov     rsi, rdi
    call    add_entry                   ;operand names are shown verbatim
    inc     rbx
    jmp     .filoop
.fildone:
    mov     rdi, r13
    mov     rsi, [nfileops]
    call    sort_range                  ;-> rax = order array
    mov     r14, rax
    mov     r15, [nfileops]
    mov     rdi, r14
    mov     rsi, r15
    call    print_list

.dirs:
    xor     rbx, rbx
.dirloop:
    cmp     rbx, [ndirops]
    jge     .done
    mov     rcx, [diridx + rbx * 8]
    mov     rdi, [operands + rcx * 8]
    call    set_path
    call    want_header
    call    list_directory
    inc     rbx
    jmp     .dirloop
.done:
    call    out_flush
    movzx   edi, byte [status]
    mov     rax, SYS_EXIT
    syscall

; want_header: a directory gets a "name:" banner when there is more than one
; operand to tell apart, or when -R is walking a tree.
want_header:
    cmp     byte [opt_recurse], 0
    jne     .yes
    mov     rax, [noperands]
    cmp     rax, 1
    ja      .yes
    xor     al, al
    ret
.yes:
    mov     al, 1
    ret

; ---------------------------------------------------------------------------
; list_directory: list the directory named by pathbuf, then recurse into its
; subdirectories for -R. al says whether to print the banner.
;
; Entries, names and the sort order all come from bump arenas whose marks are
; restored on the way out, so a recursive call cannot disturb the level above
; it -- the parent still needs its own sorted order to walk into.
; ---------------------------------------------------------------------------
list_directory:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    movzx   eax, al
    push    rax                         ;banner
    mov     rax, [entptr]
    push    rax                         ;entry mark
    mov     rax, [namefree]
    push    rax                         ;name mark
    mov     rax, [pathlen]
    push    rax                         ;path mark

    mov     rax, [ordfree]
    push    rax                         ;rsp+0 order mark, shifting the rest up

    mov     rax, SYS_OPEN
    mov     rdi, pathbuf
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .cannot
    mov     byte [is_dirlist], 1
    mov     r12, rax                    ;directory descriptor
    mov     r13, [entptr]               ;first entry of this level
    xor     r15, r15                    ;entries collected
.batch:
    mov     rax, SYS_GETDENTS64
    mov     rdi, r12
    mov     rsi, dirbuf
    mov     rdx, DIRCAP
    syscall
    test    rax, rax
    jle     .close
    mov     [batchlen], rax
    mov     qword [batchpos], 0
.entry:
    mov     rax, [batchpos]
    cmp     rax, [batchlen]
    jge     .batch
    lea     rbx, [dirbuf + rax]
    movzx   rcx, word [rbx + dirent64.d_reclen]
    add     rax, rcx
    mov     [batchpos], rax
    lea     rdi, [rbx + dirent64.d_name]
    call    hidden_wanted
    test    al, al
    jz      .entry
    lea     rdi, [rbx + dirent64.d_name]
    call    add_entry_in_dir
    test    al, al
    jz      .entry
    inc     r15
    jmp     .entry
.close:
    mov     rax, SYS_CLOSE
    mov     rdi, r12
    syscall
    mov     rdi, r13
    mov     rsi, r15
    call    sort_range
    mov     r14, rax                    ;this level's order, kept across recursion

    mov     rax, [rsp + 32]             ;banner flag
    test    rax, rax
    jz      .body
    call    print_banner
.body:
    mov     byte [is_dirlist], 1
    mov     rdi, r14
    mov     rsi, r15
    call    print_list
    cmp     byte [opt_recurse], 0
    je      .restore
    mov     rdi, r14
    mov     rsi, r15
    call    recurse_subdirs
.restore:
    pop     rax                         ;order mark
    mov     [ordfree], rax
    pop     rax                         ;path mark
    mov     [pathlen], rax
    mov     byte [pathbuf + rax], 0
    pop     rax                         ;name mark
    mov     [namefree], rax
    pop     rax                         ;entry mark
    mov     [entptr], rax
    pop     rax                         ;banner
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.cannot:
    mov     byte [status], 2
    mov     rdi, pathbuf
    call    warn_missing
    jmp     .restore

; ---------------------------------------------------------------------------
; recurse_subdirs: walk into each subdirectory of the level just printed,
; in the order it was listed. rdi = order array, rsi = count.
; ---------------------------------------------------------------------------
recurse_subdirs:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
    xor     rbx, rbx
.loop:
    cmp     rbx, r13
    jge     .out
    mov     rdi, [r12 + rbx * 8]
    mov     rax, [rdi + E_MODE]
    and     rax, S_IFMT
    cmp     rax, S_IFDIR
    jne     .next
    mov     rsi, [rdi + E_NAME]
    call    is_dot_entry
    test    al, al
    jnz     .next                       ;"." and ".." would never terminate
    mov     rax, [pathlen]
    push    rax
    mov     rdi, [r12 + rbx * 8]
    mov     rsi, [rdi + E_NAME]
    call    path_push
    mov     al, 1
    call    list_directory
    pop     rax
    mov     [pathlen], rax
    mov     byte [pathbuf + rax], 0
.next:
    inc     rbx
    jmp     .loop
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; is_dot_entry: is the name at rsi "." or ".."? al = 1/0.
is_dot_entry:
    cmp     byte [rsi], '.'
    jne     .no
    cmp     byte [rsi + 1], 0
    je      .yes
    cmp     byte [rsi + 1], '.'
    jne     .no
    cmp     byte [rsi + 2], 0
    jne     .no
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; Path handling. pathbuf always holds the path of whatever is being stat'd.
; ---------------------------------------------------------------------------
set_path:
    mov     rsi, rdi
    mov     rdi, pathbuf
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
    mov     [pathlen], rcx
    mov     rdi, pathbuf
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

; stat_operand: lstat rdi into stbuf. al = 1 on success.
stat_operand:
    mov     rax, SYS_LSTAT
    mov     rsi, stbuf
    syscall
    test    rax, rax
    js      .fail
    mov     al, 1
    ret
.fail:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; hidden_wanted: does this directory entry survive the -a/-A filter?
; ---------------------------------------------------------------------------
hidden_wanted:
    cmp     byte [rdi], '.'
    jne     .yes
    cmp     byte [opt_all], 0
    jne     .yes
    cmp     byte [opt_almost], 0
    je      .no
; -A keeps dotfiles but still drops "." and ".."
    cmp     byte [rdi + 1], 0
    je      .no
    cmp     byte [rdi + 1], '.'
    jne     .yes
    cmp     byte [rdi + 2], 0
    je      .no
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; add_entry_in_dir: stat the name at rdi inside pathbuf and record it. The
; path is restored afterwards so the caller keeps its directory.
; ---------------------------------------------------------------------------
add_entry_in_dir:
    push    rbx
    push    r12
    mov     r12, rdi
    mov     rax, [pathlen]
    mov     rbx, rax
    mov     rsi, r12
    call    path_push
    mov     rsi, r12
    call    add_entry
    mov     [pathlen], rbx
    mov     byte [pathbuf + rbx], 0
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; add_entry: record one entry whose path is in pathbuf and whose displayed
; name is at rsi. al = 1 when an entry was added.
; ---------------------------------------------------------------------------
add_entry:
    push    rbx
    push    r12
    mov     r12, rsi
    mov     rbx, [entptr]
    mov     rax, rbx
    add     rax, ENTSIZE
    mov     rcx, entries + ENTCAP * ENTSIZE
    cmp     rax, rcx
    jae     .full

; the name is copied into the arena; the directory buffer gets reused
    mov     rdi, [namefree]
    mov     [rbx + E_NAME], rdi
    xor     rcx, rcx
.copy:
    mov     al, [r12 + rcx]
    test    al, al
    jz      .named
    mov     [rdi + rcx], al
    inc     rcx
    jmp     .copy
.named:
    mov     byte [rdi + rcx], 0
    mov     [rbx + E_NAMELEN], rcx
    lea     rax, [rdi + rcx + 1]
    mov     [namefree], rax

    mov     rax, SYS_LSTAT
    mov     rdi, pathbuf
    mov     rsi, stbuf
    syscall
    test    rax, rax
    js      .nostat
    mov     qword [rbx + E_STATOK], 1
    mov     eax, [stbuf + ST_MODE]
    mov     [rbx + E_MODE], rax
    mov     rax, [stbuf + ST_NLINK]
    mov     [rbx + E_NLINK], rax
    mov     eax, [stbuf + ST_UID]
    mov     [rbx + E_UID], rax
    mov     eax, [stbuf + ST_GID]
    mov     [rbx + E_GID], rax
    mov     rax, [stbuf + ST_SIZE]
    mov     [rbx + E_SIZE], rax
    mov     rax, [stbuf + ST_MTIME]
    mov     [rbx + E_MTIME], rax
    mov     rax, [stbuf + ST_MTIMENS]
    mov     [rbx + E_MTIMENS], rax
    mov     rax, [stbuf + ST_ATIME]
    mov     [rbx + E_ATIME], rax
    mov     rax, [stbuf + ST_ATIMENS]
    mov     [rbx + E_ATIMENS], rax
    mov     rax, [stbuf + ST_CTIME]
    mov     [rbx + E_CTIME], rax
    mov     rax, [stbuf + ST_CTIMENS]
    mov     [rbx + E_CTIMENS], rax
    mov     rax, [stbuf + ST_INO]
    mov     [rbx + E_INO], rax
    mov     rax, [stbuf + ST_BLOCKS]
    mov     [rbx + E_BLOCKS], rax
    mov     rax, [stbuf + ST_RDEV]
    mov     [rbx + E_RDEV], rax
    jmp     .commit
.nostat:
    mov     qword [rbx + E_STATOK], 0
    mov     qword [rbx + E_MODE], 0
    mov     qword [rbx + E_NLINK], 0
    mov     qword [rbx + E_UID], 0
    mov     qword [rbx + E_GID], 0
    mov     qword [rbx + E_SIZE], 0
    mov     qword [rbx + E_MTIME], 0
    mov     qword [rbx + E_MTIMENS], 0
    mov     qword [rbx + E_ATIME], 0
    mov     qword [rbx + E_ATIMENS], 0
    mov     qword [rbx + E_CTIME], 0
    mov     qword [rbx + E_CTIMENS], 0
    mov     qword [rbx + E_INO], 0
    mov     qword [rbx + E_BLOCKS], 0
    mov     qword [rbx + E_RDEV], 0
.commit:
    add     rbx, ENTSIZE
    mov     [entptr], rbx
    mov     al, 1
    pop     r12
    pop     rbx
    ret
.full:
    xor     al, al
    pop     r12
    pop     rbx
    ret

; warn_missing: report an operand ls could not reach.
warn_missing:
    push    rdi
    mov     rsi, err_pre
    call    err_str
    pop     rsi
    call    err_str
    mov     rsi, err_post
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
; sort_range: order the rsi entries starting at rdi. Returns an array of
; pointers in rax, taken from the order arena so nested listings each keep
; their own. A bottom-up merge sort keeps this linear-ish on big directories,
; where an insertion sort would not.
; ---------------------------------------------------------------------------
sort_range:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi                    ;first entry
    mov     r13, rsi                    ;count
    mov     r14, [ordfree]              ;order array
    mov     rax, r13
    shl     rax, 4                      ;two arrays of qwords
    add     rax, r14
    mov     [ordfree], rax
    lea     r15, [r14 + r13 * 8]        ;scratch array
    xor     rbx, rbx
.fill:
    cmp     rbx, r13
    jge     .sorted
    mov     rax, rbx
    imul    rax, rax, ENTSIZE
    add     rax, r12
    mov     [r14 + rbx * 8], rax
    inc     rbx
    jmp     .fill
.sorted:
    cmp     byte [sortkey], SORT_NONE
    je      .done
    cmp     r13, 2
    jb      .done
; bottom-up merge: double the run length until it covers everything
    mov     rbx, 1                      ;current run length
.pass:
    cmp     rbx, r13
    jae     .done
    xor     r8, r8                      ;left start
.merge:
    cmp     r8, r13
    jge     .swap
    mov     r9, r8
    add     r9, rbx                     ;mid
    cmp     r9, r13
    jbe     .haveright
    mov     r9, r13
.haveright:
    mov     r10, r9
    add     r10, rbx                    ;end
    cmp     r10, r13
    jbe     .havelimit
    mov     r10, r13
.havelimit:
    mov     rdi, r8
    mov     rsi, r9
    mov     rdx, r10
    call    merge_runs
    mov     r8, r10
    jmp     .merge
.swap:
    mov     rax, r14                    ;the merged result becomes the source
    mov     r14, r15
    mov     r15, rax
    shl     rbx, 1
    jmp     .pass
.done:
    mov     rax, r14
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; merge_runs: merge [rdi,rsi) and [rsi,rdx) of r14 into r15.
merge_runs:
    push    rbx
    mov     r11, rdi                    ;left cursor
    mov     rcx, rsi                    ;right cursor
    mov     rbx, rdi                    ;output cursor
.step:
    cmp     rbx, rdx
    jge     .out
    cmp     r11, rsi
    jge     .takeright
    cmp     rcx, rdx
    jge     .takeleft
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    push    r11
    mov     rdi, [r14 + r11 * 8]
    mov     rsi, [r14 + rcx * 8]
    call    entry_cmp                   ;-> rax negative when rdi comes first
    pop     r11
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi
    cmp     rax, 0
    jle     .takeleft
.takeright:
    mov     rax, [r14 + rcx * 8]
    mov     [r15 + rbx * 8], rax
    inc     rcx
    inc     rbx
    jmp     .step
.takeleft:
    mov     rax, [r14 + r11 * 8]
    mov     [r15 + rbx * 8], rax
    inc     r11
    inc     rbx
    jmp     .step
.out:
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; entry_cmp: order two entries. Directories can be pulled to the front first,
; outside the -r reversal, so grouping survives a reversed sort.
; ---------------------------------------------------------------------------
entry_cmp:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
    cmp     byte [opt_dirsfirst], 0
    je      .key
    mov     rax, [r12 + E_MODE]
    and     rax, S_IFMT
    xor     rbx, rbx
    cmp     rax, S_IFDIR
    jne     .second
    mov     rbx, 1
.second:
    mov     rax, [r13 + E_MODE]
    and     rax, S_IFMT
    xor     rcx, rcx
    cmp     rax, S_IFDIR
    jne     .compare
    mov     rcx, 1
.compare:
    cmp     rbx, rcx
    je      .key
    mov     rax, -1
    cmp     rbx, rcx
    ja      .out
    mov     rax, 1
    jmp     .out
.key:
    movzx   eax, byte [sortkey]
    cmp     al, SORT_TIME
    je      .bytime
    cmp     al, SORT_SIZE
    je      .bysize
    cmp     al, SORT_EXT
    je      .byext
    call    cmp_names
    jmp     .reverse
.bytime:
    mov     rdi, r12
    call    entry_time_full
    mov     rbx, rax
    mov     rdi, r13
    call    entry_time_full
    cmp     rbx, rax
    ja      .newer
    jb      .older
    call    cmp_names
    jmp     .reverse
.newer:
    mov     rax, -1                     ;newest first
    jmp     .reverse
.older:
    mov     rax, 1
    jmp     .reverse
.bysize:
    mov     rbx, [r12 + E_SIZE]
    mov     rax, [r13 + E_SIZE]
    cmp     rbx, rax
    ja      .newer                      ;largest first
    jb      .older
    call    cmp_names
    jmp     .reverse
.byext:
    mov     rdi, r12
    call    entry_ext
    mov     rbx, rax
    mov     rdi, r13
    call    entry_ext
    mov     rdi, rbx
    mov     rsi, rax
    call    strcmp_z
    test    rax, rax
    jnz     .reverse
    call    cmp_names
.reverse:
    cmp     byte [opt_rev], 0
    je      .out
    neg     rax
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; cmp_names: byte order comparison of the two entries in r12 and r13.
cmp_names:
    mov     rdi, [r12 + E_NAME]
    mov     rsi, [r13 + E_NAME]
    jmp     strcmp_z

; entry_time_full: the selected timestamp in nanoseconds. Sorting needs the
; sub-second part: files written in quick succession share a whole second,
; and comparing only seconds would leave them all tied.
entry_time_full:
    push    rdi
    call    entry_time
    mov     rcx, 1000000000
    imul    rax, rcx
    mov     rcx, rax
    pop     rdi
    call    entry_ns
    add     rax, rcx
    ret

; entry_ns: the nanoseconds beside the selected timestamp, for the entry in
; rdi.
entry_ns:
    cmp     byte [timefield], 'a'
    je      .atime
    cmp     byte [timefield], 'c'
    je      .ctime
    mov     rax, [rdi + E_MTIMENS]
    ret
.atime:
    mov     rax, [rdi + E_ATIMENS]
    ret
.ctime:
    mov     rax, [rdi + E_CTIMENS]
    ret

; entry_time: the timestamp -c/-u selected, for the entry in rdi.
entry_time:
    cmp     byte [timefield], 'a'
    je      .atime
    cmp     byte [timefield], 'c'
    je      .ctime
    mov     rax, [rdi + E_MTIME]
    ret
.atime:
    mov     rax, [rdi + E_ATIME]
    ret
.ctime:
    mov     rax, [rdi + E_CTIME]
    ret

; entry_ext: a pointer to the entry's extension, or to its terminator when it
; has none, so extensionless names sort first.
entry_ext:
    mov     rsi, [rdi + E_NAME]
    mov     rcx, [rdi + E_NAMELEN]
    lea     rdx, [rsi + rcx]            ;the empty string at the end
.scan:
    test    rcx, rcx
    jz      .out
    dec     rcx
    cmp     byte [rsi + rcx], '.'
    jne     .scan
    lea     rdx, [rsi + rcx]
.out:
    mov     rax, rdx
    ret

; ---------------------------------------------------------------------------
; print_banner: the "path:" line that separates directories, with a blank
; line before every one but the first thing printed.
; ---------------------------------------------------------------------------
print_banner:
    cmp     byte [anyout], 0
    je      .name
    mov     al, WHITESPACE_NL
    call    out_char
.name:
    mov     rsi, pathbuf
    call    out_str
    mov     rsi, colon_str
    call    out_str
    mov     al, WHITESPACE_NL
    call    out_char
    mov     byte [anyout], 1
    ret

; ---------------------------------------------------------------------------
; print_list: rdi = order array, rsi = count. Measures the set, then hands it
; to whichever layout is in force.
; ---------------------------------------------------------------------------
print_list:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
    test    r13, r13
    jnz     .have
    cmp     byte [opt_long], 0
    je      .out
    cmp     byte [is_dirlist], 0
    je      .out
    mov     qword [total_blocks], 0     ;an empty directory still says "total 0"
    call    print_total
    jmp     .out
.have:
    mov     byte [anyout], 1
    call    measure_set
    cmp     byte [opt_long], 0
    jne     .long
    cmp     byte [opt_comma], 0
    jne     .comma
    cmp     byte [opt_col], 0
    jne     .columns
    cmp     byte [opt_across], 0
    jne     .columns
.one:
    xor     rbx, rbx
.oneloop:
    cmp     rbx, r13
    jge     .out
    mov     rdi, [r12 + rbx * 8]
    call    print_name_line
    inc     rbx
    jmp     .oneloop
.long:
    cmp     byte [is_dirlist], 0
    je      .longrows
    call    print_total
.longrows:
    xor     rbx, rbx
.longloop:
    cmp     rbx, r13
    jge     .out
    mov     rdi, [r12 + rbx * 8]
    call    print_long_row
    inc     rbx
    jmp     .longloop
.comma:
    call    print_comma
    jmp     .out
.columns:
    mov     rdi, r12
    mov     rsi, r13
    call    print_columns
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; measure_set: the widths every layout needs -- the displayed length of each
; name, and the column widths for -i, -Z and the -l fields.
; ---------------------------------------------------------------------------
measure_set:
    push    rbx
    mov     qword [w_ino], 0
    mov     qword [w_nlink], 0
    mov     qword [w_user], 0
    mov     qword [w_group], 0
    mov     qword [w_size], 0
    mov     qword [w_ctx], 0
    mov     qword [total_blocks], 0
    xor     rbx, rbx
.loop:
    cmp     rbx, r13
    jge     .totpad
    mov     rdi, [r12 + rbx * 8]
    call    display_length
    mov     rdi, [r12 + rbx * 8]
    mov     [rdi + E_DISPLEN], rax
    mov     rax, [rdi + E_BLOCKS]
    shr     rax, 1                      ;512-byte blocks to 1K units
    add     [total_blocks], rax
    cmp     byte [opt_inode], 0
    je      .nlink
    mov     rax, [rdi + E_INO]
    call    numlen
    cmp     rax, [w_ino]
    jbe     .nlink
    mov     [w_ino], rax
.nlink:
    cmp     byte [opt_ctx], 0
    je      .longfields
    mov     qword [w_ctx], 1            ;no security labels here, just "?"
.longfields:
    cmp     byte [opt_long], 0
    je      .next
    mov     rdi, [r12 + rbx * 8]
    mov     rax, [rdi + E_NLINK]
    call    numlen
    cmp     rax, [w_nlink]
    jbe     .user
    mov     [w_nlink], rax
.user:
    mov     rdi, [r12 + rbx * 8]
    mov     rdi, [rdi + E_UID]
    call    user_name
    mov     rdi, rax
    call    strlen_z
    cmp     rax, [w_user]
    jbe     .group
    mov     [w_user], rax
.group:
    mov     rdi, [r12 + rbx * 8]
    mov     rdi, [rdi + E_GID]
    call    group_name
    mov     rdi, rax
    call    strlen_z
    cmp     rax, [w_group]
    jbe     .size
    mov     [w_group], rax
.size:
    mov     rdi, [r12 + rbx * 8]
    call    size_text                   ;-> rax = length, in numbuf
    cmp     rax, [w_size]
    jbe     .next
    mov     [w_size], rax
.next:
    inc     rbx
    jmp     .loop
.totpad:
; -i and -Z sit in front of every name, so column mode has to budget for them
    xor     rax, rax
    cmp     qword [w_ino], 0
    je      .ctxpad
    add     rax, [w_ino]
    inc     rax
.ctxpad:
    cmp     qword [w_ctx], 0
    je      .storepad
    add     rax, [w_ctx]
    inc     rax
.storepad:
    mov     [totpad], rax
    pop     rbx
    ret

; display_length: how wide the entry in rdi prints, name plus any classifier.
display_length:
    push    rbx
    push    r12
    mov     rbx, rdi
    call    build_display               ;-> displen holds the escaped name
    mov     r12, [displen]              ;classifier needs rax for the mode
    mov     rdi, rbx
    call    classifier                  ;-> al = suffix, 0 for none
    test    al, al
    jz      .out
    inc     r12
.out:
    mov     rax, r12
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; build_display: render the entry's name into dispbuf, applying -b or -q.
; ---------------------------------------------------------------------------
build_display:
    push    rbx
    push    r14
    mov     rsi, [rdi + E_NAME]
    mov     rbx, 0                      ;output length
    cmp     byte [opt_escape], 0
    jne     .escape
    cmp     byte [opt_quest], 0
    jne     .quest
.raw:
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     rbx, PATHCAP - 8
    jae     .done
    mov     [dispbuf + rbx], al
    inc     rbx
    inc     rsi
    jmp     .raw
.quest:
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     rbx, PATHCAP - 8
    jae     .done
    cmp     al, WHITESPACE_SPACE
    jb      .qmark
    cmp     al, 126
    jbe     .qkeep
.qmark:
    mov     al, '?'
.qkeep:
    mov     [dispbuf + rbx], al
    inc     rbx
    inc     rsi
    jmp     .quest
.escape:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .done
    cmp     rbx, PATHCAP - 8
    jae     .done
    inc     rsi
    cmp     al, '\'
    je      .backslash
    cmp     al, WHITESPACE_SPACE
    je      .spacechar
    cmp     al, 7
    jb      .octal
    cmp     al, 13
    jbe     .named
    cmp     al, 32
    jb      .octal
    cmp     al, 126
    ja      .octal
    mov     [dispbuf + rbx], al
    inc     rbx
    jmp     .escape
.backslash:
    mov     byte [dispbuf + rbx], '\'
    mov     byte [dispbuf + rbx + 1], '\'
    add     rbx, 2
    jmp     .escape
.spacechar:
    mov     byte [dispbuf + rbx], '\'
    mov     byte [dispbuf + rbx + 1], WHITESPACE_SPACE
    add     rbx, 2
    jmp     .escape
.named:
    sub     al, 7
    movzx   eax, al
    mov     cl, [esc_letters + rax]
    mov     byte [dispbuf + rbx], '\'
    mov     [dispbuf + rbx + 1], cl
    add     rbx, 2
    jmp     .escape
.octal:
    mov     r14, rax
    mov     byte [dispbuf + rbx], '\'
    mov     rax, r14
    shr     rax, 6
    and     al, 7
    add     al, '0'
    mov     [dispbuf + rbx + 1], al
    mov     rax, r14
    shr     rax, 3
    and     al, 7
    add     al, '0'
    mov     [dispbuf + rbx + 2], al
    mov     rax, r14
    and     al, 7
    add     al, '0'
    mov     [dispbuf + rbx + 3], al
    add     rbx, 4
    jmp     .escape
.done:
    mov     byte [dispbuf + rbx], 0
    mov     [displen], rbx
    pop     r14
    pop     rbx
    ret

; classifier: the -p or -F suffix for the entry in rdi, or 0 for none.
classifier:
    mov     rax, [rdi + E_MODE]
    and     rax, S_IFMT
    cmp     rax, S_IFDIR
    je      .dir
    cmp     byte [opt_class], 0
    je      .none
    cmp     rax, S_IFLNK
    je      .link
    cmp     rax, S_IFIFO
    je      .fifo
    cmp     rax, S_IFSOCK
    je      .sock
    cmp     rax, S_IFREG
    jne     .none
    mov     rax, [rdi + E_MODE]
    test    rax, 0o111
    jz      .none
    mov     al, '*'
    ret
.dir:
    cmp     byte [opt_slash], 0
    jne     .slash
    cmp     byte [opt_class], 0
    je      .none
.slash:
    mov     al, '/'
    ret
.link:
    mov     al, '@'
    ret
.fifo:
    mov     al, '|'
    ret
.sock:
    mov     al, '='
    ret
.none:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; print_columns: fit as many columns as the screen budget allows, then print
; the grid. rdi = order array, rsi = count.
;
; A column is as wide as its widest entry plus two spaces, except the last,
; which needs no trailing gap. The running total starts at the column count
; so a one-character name still claims a cell.
; ---------------------------------------------------------------------------
print_columns:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rsi

    mov     r14, MAXCOLS
    mov     rax, [screen_w]
    shr     rax, 1                      ;one character plus one space each
    cmp     r14, rax
    jbe     .cap2
    mov     r14, rax
.cap2:
    cmp     r14, r13
    jbe     .try
    mov     r14, r13
.try:
    cmp     r14, 1
    jbe     .single
    mov     rdi, r14
    call    columns_fit                 ;-> al = 1 when this many fit
    test    al, al
    jnz     .layout
    dec     r14
    jmp     .try
.single:
    mov     r14, 1
    mov     rdi, r14
    call    columns_fit
.layout:
    mov     [ncols], r14
; walk the grid in printed order, breaking the line at the end of each row
    xor     rbx, rbx
.cell:
    cmp     rbx, r13
    jge     .out
    mov     rdi, rbx
    mov     rsi, r13
    mov     rdx, r14
    call    next_column                 ;-> rax = entry index, rdx = column
    mov     r15, rdx
    mov     rdi, [r12 + rax * 8]
    mov     [curent], rdi
    call    print_prefix
    mov     rdi, [curent]
    call    print_display
    mov     rax, rbx
    inc     rax
    cmp     rax, r13
    jge     .endline                    ;nothing left to put beside it
    mov     rdi, rax
    mov     rsi, r13
    mov     rdx, r14
    call    next_column                 ;where does the next entry land?
    cmp     rdx, r15
    jbe     .endline                    ;it wrapped, so this row is done
    mov     rdi, [curent]
    mov     rcx, [rdi + E_DISPLEN]
    add     rcx, [totpad]
    mov     eax, [colsizes + r15 * 4]
    sub     rax, rcx
    jle     .nextcell
.pad:
    push    rax
    mov     al, WHITESPACE_SPACE
    call    out_char
    pop     rax
    dec     rax
    jnz     .pad
.nextcell:
    inc     rbx
    jmp     .cell
.endline:
    mov     al, WHITESPACE_NL
    call    out_char
    inc     rbx
    jmp     .cell
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; columns_fit: would rdi columns stay inside the screen budget? Fills in
; colsizes as a side effect, so the accepted layout is ready to print.
columns_fit:
    push    rbx
    push    r14
    push    r15
    mov     r15, rdi                    ;columns
    xor     rcx, rcx
.clear:
    cmp     rcx, r15
    jae     .start
    mov     dword [colsizes + rcx * 4], 0
    inc     rcx
    jmp     .clear
.start:
    mov     r14, r15                    ;running total starts at one per column
    xor     rbx, rbx
.item:
    cmp     rbx, r13
    jge     .fits
    mov     rdi, rbx
    mov     rsi, r13
    mov     rdx, r15
    call    next_column
    cmp     rax, r13
    jae     .no                         ;ragged tail does not line up
    mov     rdi, [r12 + rax * 8]
    mov     rcx, [rdi + E_DISPLEN]
    add     rcx, [totpad]
    mov     rax, r15
    dec     rax
    cmp     rdx, rax
    jge     .measure
    add     rcx, 2                      ;two spaces before the next column
.measure:
    mov     eax, [colsizes + rdx * 4]
    cmp     rcx, rax
    jbe     .next
    sub     rcx, rax
    add     r14, rcx
    add     rcx, rax
    mov     [colsizes + rdx * 4], ecx
    cmp     r14, [screen_w]
    ja      .no
.next:
    inc     rbx
    jmp     .item
.fits:
    mov     al, 1
    pop     r15
    pop     r14
    pop     rbx
    ret
.no:
    xor     al, al
    pop     r15
    pop     r14
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; next_column: for cell rdi of rsi entries across rdx columns, which entry
; goes there (rax) and in which column (rdx).
;
; -x reads straight across. -C fills down each column; when the entries do
; not fill the grid the short columns are the rightmost ones, so the tail
; shifts along the right edge and the rows stay rectangular.
; ---------------------------------------------------------------------------
next_column:
    cmp     byte [opt_col], 0
    jne     .vertical
    mov     rax, rdi                    ;-x reads straight across
    mov     r8, rdx
    xor     rdx, rdx
    div     r8
    mov     rax, rdi
    ret
.vertical:
    push    rbx
    mov     r8, rdi                     ;cell
    mov     r9, rsi                     ;count
    mov     r10, rdx                    ;columns
    mov     rax, r9
    add     rax, r10
    dec     rax
    xor     rdx, rdx
    div     r10
    mov     r11, rax                    ;height, rounded up
    test    r11, r11
    jnz     .extra
    mov     r11, 1
.extra:
    mov     rax, r9
    xor     rdx, rdx
    div     r11
mov     rbx, rdx                    ;count modulo height: full columns
    test    rbx, rbx
    jz      .plain
    mov     rax, rbx
    imul    rax, r10
    cmp     r8, rax
    jb      .plain
sub     r8, rax                     ;past the full block: one column narrower
    dec     r10
    jmp     .place
.plain:
    xor     rbx, rbx
.place:
    mov     rax, r8
    xor     rdx, rdx
    div     r10
    mov     rcx, rax                    ;row within the column
    mov     rax, rdx                    ;column
    push    rdx
    imul    rax, r11
    add     rax, rbx
    add     rax, rcx
    pop     rdx
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; print_comma: -m, names separated by ", " and wrapped at the screen width.
; ---------------------------------------------------------------------------
print_comma:
    push    rbx
    push    r14
    xor     rbx, rbx
    xor     r14, r14                    ;characters on this line
.item:
    cmp     rbx, r13
    jge     .eol
    mov     rdi, [r12 + rbx * 8]
    mov     rcx, [rdi + E_DISPLEN]
    test    rbx, rbx
    jz      .emit
    mov     rax, r14
    add     rax, rcx
    add     rax, 2
    cmp     rax, [screen_w]
    jb      .separator
    mov     al, ','
    call    out_char
    mov     al, WHITESPACE_NL
    call    out_char
    xor     r14, r14
    jmp     .emit
.separator:
    mov     rsi, comma_str
    call    out_str
    add     r14, 2
.emit:
    mov     rdi, [r12 + rbx * 8]
    call    print_prefix
    mov     rdi, [r12 + rbx * 8]
    call    print_display
    mov     rdi, [r12 + rbx * 8]
    add     r14, [rdi + E_DISPLEN]
    inc     rbx
    jmp     .item
.eol:
    mov     al, WHITESPACE_NL
    call    out_char
    pop     r14
    pop     rbx
    ret

; print_name_line: one entry on a line of its own.
print_name_line:
    push    rdi
    call    print_prefix
    pop     rdi
    call    print_display
    mov     al, WHITESPACE_NL
    jmp     out_char

; print_prefix: the -i inode and -Z context columns that lead every name.
print_prefix:
    push    rbx
    mov     rbx, rdi
    cmp     qword [w_ino], 0
    je      .context
    mov     rax, [rbx + E_INO]
    mov     rcx, [w_ino]
    call    out_num_right
    mov     al, WHITESPACE_SPACE
    call    out_char
.context:
    cmp     qword [w_ctx], 0
    je      .out
    mov     rsi, noctx_str
    call    out_str
    mov     al, WHITESPACE_SPACE
    call    out_char
.out:
    pop     rbx
    ret

; print_display: the escaped name and its classifier.
print_display:
    push    rbx
    mov     rbx, rdi
    call    build_display
    mov     rsi, dispbuf
    mov     rdx, [displen]
    call    out_bytes
    mov     rdi, rbx
    call    classifier
    test    al, al
    jz      .out
    call    out_char
.out:
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; print_total: the "total" line that heads a long directory listing, in 1K
; units like the sizes below it.
; ---------------------------------------------------------------------------
print_total:
    mov     rsi, total_str
    call    out_str
    mov     rax, [total_blocks]
    cmp     byte [opt_human], 0
    je      .plain
    shl     rax, 10                     ;the count is in 1K units
    mov     rdi, numbuf
    call    human_size
    mov     rdx, rdi
    mov     rsi, numbuf
    sub     rdx, rsi
    call    out_bytes
    mov     al, WHITESPACE_NL
    jmp     out_char
.plain:
    call    out_num
    mov     al, WHITESPACE_NL
    jmp     out_char

; ---------------------------------------------------------------------------
; human_size: write rax at rdi the way -h does -- a plain count below 1024,
; otherwise scaled to K/M/G/T/P/E and rounded up, with one decimal while the
; number is still a single digit. rdi ends past the text.
; ---------------------------------------------------------------------------
human_size:
    push    rbx
    cmp     rax, 1024
    jb      .plain
    xor     rbx, rbx                    ;unit index
.scale:
    mov     rcx, 1048576
    cmp     rax, rcx
    jb      .split
    cmp     rbx, 5
    jae     .split
    mov     rcx, 1024
    xor     rdx, rdx
    div     rcx
    inc     rbx
    jmp     .scale
.split:
    mov     rcx, 1024
    xor     rdx, rdx
    div     rcx                         ;rax whole units, rdx remainder
    mov     r8, rax
    mov     rax, rdx
    imul    rax, rax, 10
    add     rax, 1023
    xor     rdx, rdx
    div     rcx                         ;tenths, rounded up
    mov     r9, rax
    cmp     r9, 10
    jb      .whole
    inc     r8
    xor     r9, r9
.whole:
    cmp     r8, 10
    jb      .decimal
    test    r9, r9
    jz      .integer
    inc     r8                          ;two digits round up to the whole unit
.integer:
    mov     rax, r8
    call    u64_to_dec
    jmp     .suffix
.decimal:
    mov     rax, r8
    call    u64_to_dec
    mov     byte [rdi], '.'
    inc     rdi
    mov     rax, r9
    call    u64_to_dec
.suffix:
    mov     al, [size_units + rbx]
    mov     [rdi], al
    inc     rdi
    pop     rbx
    ret
.plain:
    call    u64_to_dec
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; print_long_row: mode, links, owner, group, context, size, time, name -- and
; the target for a symlink.
; ---------------------------------------------------------------------------
print_long_row:
    push    rbx
    mov     rbx, rdi
    cmp     qword [w_ino], 0
    je      .mode
    mov     rax, [rbx + E_INO]
    mov     rcx, [w_ino]
    call    out_num_right
    mov     al, WHITESPACE_SPACE
    call    out_char
.mode:
    mov     rdi, rbx
    call    build_mode
    mov     rsi, modebuf
    mov     rdx, 10
    call    out_bytes
    mov     al, WHITESPACE_SPACE
    call    out_char
    mov     rax, [rbx + E_NLINK]
    mov     rcx, [w_nlink]
    call    out_num_right
    mov     al, WHITESPACE_SPACE
    call    out_char
    mov     rdi, [rbx + E_UID]
    call    user_name
    mov     rcx, [w_user]
    call    out_str_left
    mov     al, WHITESPACE_SPACE
    call    out_char
    cmp     byte [opt_nogroup], 0
    jne     .context
    mov     rdi, [rbx + E_GID]
    call    group_name
    mov     rcx, [w_group]
    call    out_str_left
    mov     al, WHITESPACE_SPACE
    call    out_char
.context:
    cmp     qword [w_ctx], 0
    je      .size
    mov     rsi, noctx_str
    call    out_str
    mov     al, WHITESPACE_SPACE
    call    out_char
.size:
    mov     rdi, rbx
    call    size_text                   ;-> rax = length, text in numbuf
    mov     rcx, [w_size]
    sub     rcx, rax
    jle     .sizetext
.sizepad:
    push    rcx
    mov     al, WHITESPACE_SPACE
    call    out_char
    pop     rcx
    dec     rcx
    jnz     .sizepad
.sizetext:
    mov     rsi, numbuf
    mov     rdx, [sizelen]
    call    out_bytes
    mov     al, WHITESPACE_SPACE
    call    out_char
    mov     rdi, rbx
    call    entry_time
    mov     rdi, rax
    mov     rsi, rbx
    call    format_time
    mov     rsi, datebuf
    mov     rdx, [datelen]
    call    out_bytes
    mov     al, WHITESPACE_SPACE
    call    out_char
    mov     rdi, rbx
    call    print_display
    mov     rax, [rbx + E_MODE]
    and     rax, S_IFMT
    cmp     rax, S_IFLNK
    jne     .eol
    mov     rsi, arrow_str
    call    out_str
    call    read_link_target
    test    al, al
    jz      .eol
    mov     rsi, linkbuf
    call    out_str
.eol:
    mov     al, WHITESPACE_NL
    call    out_char
    pop     rbx
    ret

; read_link_target: the symlink target of the entry in rbx, into linkbuf.
read_link_target:
    push    rbx
    mov     rax, [pathlen]
    push    rax
    mov     rsi, [rbx + E_NAME]
    cmp     byte [is_dirlist], 0
    je      .direct
    call    path_push                   ;names inside a listing need the prefix
    jmp     .read
.direct:
    mov     rdi, rsi
    call    set_path
.read:
    mov     rax, SYS_READLINK
    mov     rdi, pathbuf
    mov     rsi, linkbuf
    mov     rdx, PATHCAP - 1
    syscall
    pop     rcx
    mov     [pathlen], rcx
    mov     byte [pathbuf + rcx], 0
    test    rax, rax
    js      .fail
    mov     byte [linkbuf + rax], 0
    mov     al, 1
    pop     rbx
    ret
.fail:
    xor     al, al
    pop     rbx
    ret

; build_mode: the ten-character mode string for the entry in rdi.
build_mode:
    push    rbx
    mov     rbx, [rdi + E_MODE]
    mov     rax, rbx
    shr     rax, 12
    and     rax, 15
    mov     al, [typechars + rax]
    mov     [modebuf], al
    xor     rcx, rcx
.bits:
    cmp     rcx, 9
    jae     .special
    mov     rax, 8
    sub     rax, rcx
    mov     rdx, 1
    push    rcx
    mov     ecx, eax
    shl     rdx, cl
    pop     rcx
    test    rbx, rdx
    jz      .clear
    mov     al, [modechars + rcx]
    jmp     .store
.clear:
    mov     al, '-'
.store:
    mov     [modebuf + rcx + 1], al
    inc     rcx
    jmp     .bits
.special:
    test    rbx, S_ISUID
    jz      .setgid
    mov     al, 's'
    cmp     byte [modebuf + 3], 'x'
    je      .setuid_store
    mov     al, 'S'
.setuid_store:
    mov     [modebuf + 3], al
.setgid:
    test    rbx, S_ISGID
    jz      .sticky
    mov     al, 's'
    cmp     byte [modebuf + 6], 'x'
    je      .setgid_store
    mov     al, 'S'
.setgid_store:
    mov     [modebuf + 6], al
.sticky:
    test    rbx, S_ISVTX
    jz      .out
    mov     al, 't'
    cmp     byte [modebuf + 9], 'x'
    je      .sticky_store
    mov     al, 'T'
.sticky_store:
    mov     [modebuf + 9], al
.out:
    pop     rbx
    ret

; size_text: the size column for the entry in rdi, into numbuf. Devices show
; their major and minor numbers instead of a byte count. rax = length.
size_text:
    push    rbx
    mov     rbx, rdi
    mov     rax, [rbx + E_MODE]
    and     rax, S_IFMT
    cmp     rax, S_IFCHR
    je      .device
    cmp     rax, S_IFBLK
    je      .device
    mov     rax, [rbx + E_SIZE]
    mov     rdi, numbuf
    cmp     byte [opt_human], 0
    je      .plain
    call    human_size
    jmp     .length
.plain:
    call    u64_to_dec
    jmp     .length
.device:
    mov     rax, [rbx + E_RDEV]
    mov     r8, rax
    shr     r8, 8
    and     r8, 0xFFF
    mov     r9, rax
    and     r9, 0xFF
    mov     r10, rax
    shr     r10, 12
    and     r10, 0xFFF00
    or      r9, r10
    mov     rdi, numbuf
    mov     rax, r8
    call    u64_to_dec
    mov     byte [rdi], ','
    inc     rdi
    mov     byte [rdi], WHITESPACE_SPACE
    inc     rdi
    mov     rax, r9
    call    u64_to_dec
.length:
    mov     rax, rdi
    sub     rax, numbuf
    mov     [sizelen], rax
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; format_time: render the timestamp in rdi for the entry in rsi into datebuf.
;
; --full-time gives the full date, the nanoseconds and the offset. Otherwise
; the year is dropped for anything within the last six months, where the time
; of day is more useful, and shown instead for older entries.
; ---------------------------------------------------------------------------
format_time:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi                    ;seconds since the epoch
    mov     r13, rsi                    ;entry, for its nanoseconds
    mov     rdi, r12
    call    tz_offset_for               ;-> rax = offset at that moment
    mov     rbx, rax
    mov     rdi, r12
    add     rdi, rbx
    call    civil_from_epoch            ;fills cv_* with local wall clock
    mov     rdi, datebuf
    cmp     byte [opt_fulltime], 0
    jne     .full

; recent entries show the time of day, older ones the year
    mov     rax, [now]
    sub     rax, r12
    cmp     rax, 15778476               ;about six months
    jg      .oldstyle
    mov     rax, r12
    sub     rax, [now]
    cmp     rax, 3600
    jg      .oldstyle
    call    put_month
    mov     byte [rdi], WHITESPACE_SPACE
    inc     rdi
    mov     rax, [cv_day]
    call    put_2space
    mov     byte [rdi], WHITESPACE_SPACE
    inc     rdi
    mov     rax, [cv_hour]
    call    put_2zero
mov     byte [rdi], ':'
    inc     rdi
    mov     rax, [cv_min]
    call    put_2zero
    jmp     .done
.oldstyle:
    call    put_month
    mov     byte [rdi], WHITESPACE_SPACE
    inc     rdi
    mov     rax, [cv_day]
    call    put_2space
    mov     byte [rdi], WHITESPACE_SPACE
    inc     rdi
    mov     byte [rdi], WHITESPACE_SPACE
    inc     rdi
    mov     rax, [cv_year]
    call    u64_to_dec
    jmp     .done
.full:
    mov     rax, [cv_year]
    call    u64_to_dec
    mov     byte [rdi], '-'
    inc     rdi
    mov     rax, [cv_mon]
    call    put_2zero
    mov     byte [rdi], '-'
    inc     rdi
    mov     rax, [cv_day]
    call    put_2zero
    mov     byte [rdi], WHITESPACE_SPACE
    inc     rdi
    mov     rax, [cv_hour]
    call    put_2zero
mov     byte [rdi], ':'
    inc     rdi
    mov     rax, [cv_min]
    call    put_2zero
mov     byte [rdi], ':'
    inc     rdi
    mov     rax, [cv_sec]
    call    put_2zero
    mov     byte [rdi], '.'
    inc     rdi
    mov     rdx, r13
    call    entry_nanos                 ;-> rax
    mov     rcx, 9
    call    put_padded
    mov     byte [rdi], WHITESPACE_SPACE
    inc     rdi
    mov     rax, rbx
    call    put_offset
.done:
    mov     byte [rdi], 0
    mov     rax, rdi
    sub     rax, datebuf
    mov     [datelen], rax
    pop     r13
    pop     r12
    pop     rbx
    ret

; entry_nanos: the nanoseconds beside whichever timestamp -c/-u selected.
entry_nanos:
    cmp     byte [timefield], 'a'
    je      .atime
    cmp     byte [timefield], 'c'
    je      .ctime
    mov     rax, [rdx + E_MTIMENS]
    ret
.atime:
    mov     rax, [rdx + E_ATIMENS]
    ret
.ctime:
    mov     rax, [rdx + E_CTIMENS]
    ret

; put_month: the three letter month name at rdi.
put_month:
    mov     rax, [cv_mon]
    dec     rax
    imul    rax, rax, 3
    mov     cl, [months + rax]
    mov     [rdi], cl
    mov     cl, [months + rax + 1]
    mov     [rdi + 1], cl
    mov     cl, [months + rax + 2]
    mov     [rdi + 2], cl
    add     rdi, 3
    ret

; put_2zero / put_2space: two digits, padded with a zero or a space.
put_2zero:
    cmp     rax, 10
    jae     u64_to_dec
    mov     byte [rdi], '0'
    inc     rdi
    jmp     u64_to_dec

put_2space:
    cmp     rax, 10
    jae     u64_to_dec
    mov     byte [rdi], WHITESPACE_SPACE
    inc     rdi
    jmp     u64_to_dec

; put_padded: rax as exactly rcx digits, zero filled on the left.
put_padded:
    push    rbx
    mov     rbx, rcx
    mov     rcx, rax
    call    numlen                      ;rax already holds the value
    mov     rdx, rbx
    sub     rdx, rax
    mov     rax, rcx
    jle     .digits
.zeros:
    mov     byte [rdi], '0'
    inc     rdi
    dec     rdx
    jnz     .zeros
.digits:
    call    u64_to_dec
    pop     rbx
    ret

; put_offset: the UTC offset as +HHMM.
put_offset:
    mov     rcx, rax
    mov     byte [rdi], '+'
    test    rcx, rcx
    jns     .value
    mov     byte [rdi], '-'
    neg     rcx
.value:
    inc     rdi
    mov     rax, rcx
    xor     rdx, rdx
    mov     rcx, 3600
    div     rcx
    push    rdx
    call    put_2zero
    pop     rax
    xor     rdx, rdx
    mov     rcx, 60
    div     rcx
    jmp     put_2zero

; ---------------------------------------------------------------------------
; civil_from_epoch: split the local wall clock in rdi into cv_year, cv_mon,
; cv_day, cv_hour, cv_min and cv_sec.
; ---------------------------------------------------------------------------
civil_from_epoch:
    push    rbx
    mov     rax, rdi
    mov     rcx, 86400
    cqo
    idiv    rcx
    mov     rbx, rax                    ;days
    test    rdx, rdx
    jns     .time
    dec     rbx                         ;floor, not truncate
    add     rdx, rcx
.time:
    mov     rax, rdx
    xor     rdx, rdx
    mov     rcx, 60
    div     rcx
    mov     [cv_sec], rdx
    xor     rdx, rdx
    div     rcx
    mov     [cv_min], rdx
    mov     [cv_hour], rax

; the civil calendar, counted from a March-based era so leap days land last
    mov     rax, rbx
    add     rax, 719468
    mov     rcx, 146097
    cqo
    idiv    rcx
    mov     r8, rax                     ;era
    test    rdx, rdx
    jns     .doe
    dec     r8
    add     rdx, rcx
.doe:
    mov     r9, rdx                     ;day of era
    mov     rax, r9
    xor     rdx, rdx
    mov     rcx, 1460
    div     rcx
    mov     r10, rax
    mov     rax, r9
    xor     rdx, rdx
    mov     rcx, 36524
    div     rcx
    mov     r11, rax
    mov     rax, r9
    xor     rdx, rdx
    mov     rcx, 146096
    div     rcx
    mov     rcx, rax
    mov     rax, r9
    sub     rax, r10
    add     rax, r11
    sub     rax, rcx
    xor     rdx, rdx
    mov     rcx, 365
    div     rcx
    mov     r10, rax                    ;year of era
    mov     rax, r10
    imul    rax, rax, 365
    mov     r11, rax
    mov     rax, r10
    shr     rax, 2
    add     r11, rax
    mov     rax, r10
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    sub     r11, rax
    mov     rax, r9
    sub     rax, r11                    ;day of year, March based
    mov     r11, rax
    imul    rax, rax, 5
    add     rax, 2
    xor     rdx, rdx
    mov     rcx, 153
    div     rcx
    mov     rcx, rax                    ;month position
    imul    rax, rax, 153
    add     rax, 2
    xor     rdx, rdx
    push    rcx
    mov     rcx, 5
    div     rcx
    pop     rcx
    mov     rdx, r11
    sub     rdx, rax
    inc     rdx
    mov     [cv_day], rdx
    mov     rax, rcx
    cmp     rax, 10
    jb      .early
    sub     rax, 9
    jmp     .month
.early:
    add     rax, 3
.month:
    mov     [cv_mon], rax
    mov     rdx, r8
    imul    rdx, rdx, 400
    add     rdx, r10
    cmp     rax, 2
    ja      .year
    inc     rdx                         ;January and February belong to the next
.year:
    mov     [cv_year], rdx
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; tz_offset_for: the UTC offset in effect at the instant in rdi.
;
; The zoneinfo file lists the moments the offset changes and a table of the
; offsets themselves. Looking the timestamp up in that list, rather than
; taking one fixed offset, is what makes entries either side of a daylight
; saving change come out right.
; ---------------------------------------------------------------------------
tz_offset_for:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    call    load_timezone
    cmp     qword [tz_timecnt], 0
    je      .fallback
    xor     rbx, rbx
    mov     r13, -1                     ;last transition already passed
.scan:
    cmp     rbx, [tz_timecnt]
    jge     .found
    mov     rdi, rbx
    call    tz_transition               ;-> rax = when it takes effect
    cmp     rax, r12
    jg      .found
    mov     r13, rbx
    inc     rbx
    jmp     .scan
.found:
    cmp     r13, 0
    jl      .fallback                   ;before the first recorded change
    mov     rax, [tz_idxoff]
    add     rax, r13
    movzx   edi, byte [rax]
    call    tz_type_offset
    pop     r13
    pop     r12
    pop     rbx
    ret
.fallback:
    cmp     qword [tz_typecnt], 0
    je      .zero
    xor     rdi, rdi
    call    tz_type_offset
    pop     r13
    pop     r12
    pop     rbx
    ret
.zero:
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    ret

; tz_transition: the rdi'th transition time, four or eight bytes wide.
tz_transition:
    cmp     qword [tz_wide], 0
    jne     .wide
    mov     rax, [tz_transoff]
    lea     rcx, [rax + rdi * 4]
    mov     rdi, rcx
    call    read_be32
    movsxd  rax, eax
    ret

.wide:
    mov     rax, [tz_transoff]
    lea     rcx, [rax + rdi * 8]
    mov     rdi, rcx
    jmp     read_be64

; tz_type_offset: the offset belonging to type rdi.
tz_type_offset:
    mov     rax, [tz_ttoff]
    imul    rcx, rdi, 6
    add     rax, rcx
    mov     rdi, rax
    call    read_be32
    movsxd  rax, eax
    ret

; ---------------------------------------------------------------------------
; load_timezone: read the zone file once and note where its tables start.
; A version 2 file repeats everything with 64-bit times after the 32-bit
; block, and that second copy is the one worth reading.
; ---------------------------------------------------------------------------
load_timezone:
    cmp     byte [tz_loaded], 0
    jne     .out
    mov     byte [tz_loaded], 1
    mov     qword [tz_timecnt], 0
    mov     qword [tz_typecnt], 0
    call    tz_path                     ;-> rdi = file to open
    mov     rax, SYS_OPEN
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
    lea     rsi, [tzbuf + r9]
    mov     rdx, TZCAP
    sub     rdx, r9
    jle     .close
    syscall
    test    rax, rax
    jle     .close
    add     r9, rax
    jmp     .read
.close:
    push    r9
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    pop     r9
    mov     [tz_len], r9
    cmp     r9, 44
    jb      .out
    cmp     dword [tzbuf], 0x66695A54   ;"TZif" little endian in memory
    jne     .out
    mov     qword [tz_wide], 0
    xor     rdi, rdi
    call    tz_parse_block
    cmp     byte [tzbuf + 4], '2'
jb      .out                        ;version 1: that block is all there is
    mov     rdi, [tz_len_of_block]      ;the 64-bit copy follows the 32-bit one
    cmp     rdi, [tz_len]
    jae     .out
    mov     qword [tz_wide], 1
    call    tz_parse_block
.out:
    ret

; tz_parse_block: read the header at rdi and record where the transition
; times, type indices and offset table live. The six counts sit at offset 20
; and the data follows the 44-byte header. Also records the block's total
; length, which is how the 64-bit copy is found.
tz_parse_block:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    lea     rbx, [tzbuf + rdi]          ;rdi is an offset into the file
    lea     rdi, [rbx + 20]
    call    read_be32
    mov     r12, rax                    ;isutcnt
    lea     rdi, [rbx + 24]
    call    read_be32
    mov     r13, rax                    ;isstdcnt
    lea     rdi, [rbx + 28]
    call    read_be32
    mov     r14, rax                    ;leapcnt
    lea     rdi, [rbx + 32]
    call    read_be32
    mov     [tz_timecnt], rax
    mov     r15, rax                    ;timecnt
    lea     rdi, [rbx + 36]
    call    read_be32
    mov     [tz_typecnt], rax
    mov     r8, rax                     ;typecnt
    lea     rdi, [rbx + 40]
    call    read_be32
    mov     r9, rax                     ;charcnt

    lea     rdi, [rbx + 44]
    mov     [tz_transoff], rdi
    mov     rax, r15
    cmp     qword [tz_wide], 0
    je      .narrow
    shl     rax, 3
    jmp     .indices
.narrow:
    shl     rax, 2
.indices:
    add     rdi, rax
    mov     [tz_idxoff], rdi
    add     rdi, r15
    mov     [tz_ttoff], rdi
    imul    rax, r8, 6
    add     rdi, rax
    add     rdi, r9
    mov     rax, r14
    cmp     qword [tz_wide], 0
    je      .leapnarrow
    imul    rax, rax, 12
    jmp     .leapdone
.leapnarrow:
    shl     rax, 3
.leapdone:
    add     rdi, rax
    add     rdi, r13
    add     rdi, r12
    mov     rax, rdi
    sub     rax, rbx
    mov     [tz_len_of_block], rax
    mov     rax, rbx
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; tz_path: the zone file to read, from TZ when it names one.
tz_path:
    mov     rdi, tz_env
    call    getenv_value                ;-> rax = value, or 0
    test    rax, rax
    jz      .local
    cmp     byte [rax], 0
    je      .local
    mov     rsi, rax
cmp     byte [rsi], ':'
    jne     .build
    inc     rsi
.build:
    cmp     byte [rsi], '/'
    je      .absolute
    mov     rdi, tzpath
    mov     rcx, 0
.prefix:
    mov     al, [zoneinfo + rcx]
    test    al, al
    jz      .name
    mov     [rdi + rcx], al
    inc     rcx
    jmp     .prefix
.name:
    mov     al, [rsi]
    test    al, al
    jz      .term
    cmp     rcx, PATHCAP - 2
    jae     .term
    mov     [rdi + rcx], al
    inc     rcx
    inc     rsi
    jmp     .name
.term:
    mov     byte [rdi + rcx], 0
    mov     rdi, tzpath
    ret
.absolute:
    mov     rdi, rsi
    ret
.local:
    mov     rdi, localtime_p
    ret

; getenv_value: look rdi up in the environment. rax = the value, or 0.
getenv_value:
    mov     r8, [envp]
.entry:
    mov     rsi, [r8]
    test    rsi, rsi
    jz      .none
    xor     rcx, rcx
.match:
    mov     al, [rdi + rcx]
    test    al, al
    jz      .sep
    cmp     al, [rsi + rcx]
    jne     .next
    inc     rcx
    jmp     .match
.sep:
    cmp     byte [rsi + rcx], '='
    jne     .next
    lea     rax, [rsi + rcx + 1]
    ret
.next:
    add     r8, 8
    jmp     .entry
.none:
    xor     rax, rax
    ret

read_be32:
    xor     rax, rax
    movzx   edx, byte [rdi]
    shl     rdx, 24
    or      rax, rdx
    movzx   edx, byte [rdi + 1]
    shl     rdx, 16
    or      rax, rdx
    movzx   edx, byte [rdi + 2]
    shl     rdx, 8
    or      rax, rdx
    movzx   edx, byte [rdi + 3]
    or      rax, rdx
    ret

read_be64:
    xor     rax, rax
    xor     rcx, rcx
.byte:
    cmp     rcx, 8
    jae     .out
    shl     rax, 8
    movzx   edx, byte [rdi + rcx]
    or      rax, rdx
    inc     rcx
    jmp     .byte
.out:
    ret

; read_now: the current time, for deciding which entries count as recent.
read_now:
    mov     rax, SYS_CLOCK_GETTIME_ID
    xor     rdi, rdi                    ;CLOCK_REALTIME
    mov     rsi, tsbuf
    syscall
    mov     rax, [tsbuf]
    mov     [now], rax
    ret

; ---------------------------------------------------------------------------
; Name lookups out of /etc/passwd and /etc/group, with the numeric id as the
; fallback when there is no entry.
; ---------------------------------------------------------------------------
user_name:
    push    rdi
    call    load_accounts
    pop     rdi
    mov     qword [lk_dest], ubuf
    push    rdi
    mov     rsi, pwbuf
    mov     rdx, [pwlen]
    call    id_to_name
    pop     rdi
    test    rax, rax
    jnz     .out
    mov     rax, rdi
    mov     rdi, ubuf
    call    u64_to_dec
    mov     byte [rdi], 0
    mov     rax, ubuf
.out:
    ret

group_name:
    push    rdi
    call    load_accounts
    pop     rdi
    mov     qword [lk_dest], gbuf
    push    rdi
    mov     rsi, grbuf
    mov     rdx, [grlen]
    call    id_to_name
    pop     rdi
    test    rax, rax
    jnz     .out
    mov     rax, rdi
    mov     rdi, gbuf
    call    u64_to_dec
    mov     byte [rdi], 0
    mov     rax, gbuf
.out:
    ret

load_accounts:
    cmp     byte [pw_loaded], 0
    jne     .out
    mov     byte [pw_loaded], 1
    mov     rdi, passwd_path
    mov     rsi, pwbuf
    call    slurp_file
    mov     [pwlen], rax
    mov     rdi, group_path
    mov     rsi, grbuf
    call    slurp_file
    mov     [grlen], rax
.out:
    ret

slurp_file:
    push    rsi
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    pop     rsi
    test    rax, rax
    js      .none
    mov     r8, rax
    xor     r9, r9
.read:
    push    rsi
    push    r9
    mov     rax, SYS_READ
    mov     rdi, r8
    lea     rsi, [rsi + r9]
    mov     rdx, PWCAP
    sub     rdx, r9
    jle     .stop
    syscall
    pop     r9
    pop     rsi
    test    rax, rax
    jle     .close
    add     r9, rax
    jmp     .read
.stop:
    pop     r9
    pop     rsi
.close:
    push    r9
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    pop     rax
    ret
.none:
    xor     rax, rax
    ret

; id_to_name: find the line in [rsi, rsi+rdx) whose third colon field is the
; id in rdi, and copy its name to lk_dest. rax = lk_dest, or 0 when there is
; no such line. The table itself is left alone -- terminating the name in
; place would corrupt the line for every later lookup.
id_to_name:
    test    rdx, rdx
    jz      .none
    mov     r8, rdi
    mov     r9, rsi
    mov     r10, rdx
    xor     rcx, rcx
.line:
    cmp     rcx, r10
    jae     .none
    mov     r11, rcx
.namend:
    cmp     r11, r10
    jae     .none
    mov     al, [r9 + r11]
cmp     al, ':'
    je      .aftername
    cmp     al, WHITESPACE_NL
    je      .nextline
    inc     r11
    jmp     .namend
.aftername:
    mov     rdi, r11
    inc     r11
.skippw:
    cmp     r11, r10
    jae     .none
    mov     al, [r9 + r11]
    inc     r11
cmp     al, ':'
    jne     .skippw
    xor     rax, rax
    xor     rsi, rsi
.digit:
    cmp     r11, r10
    jae     .compare
    movzx   rdx, byte [r9 + r11]
    sub     dl, '0'
    cmp     dl, 9
    ja      .compare
    imul    rax, rax, 10
    add     rax, rdx
    inc     rsi
    inc     r11
    jmp     .digit
.compare:
    test    rsi, rsi
    jz      .nextline
    cmp     rax, r8
    jne     .nextline
    mov     r11, [lk_dest]
    mov     rax, rcx
.copy:
    cmp     rax, rdi
    jae     .copied
    mov     dl, [r9 + rax]
    mov     [r11], dl
    inc     r11
    inc     rax
    jmp     .copy
.copied:
    mov     byte [r11], 0
    mov     rax, [lk_dest]
    ret
.nextline:
    cmp     r11, r10
    jae     .none
    cmp     byte [r9 + r11], WHITESPACE_NL
    je      .advance
    inc     r11
    jmp     .nextline
.advance:
    lea     rcx, [r11 + 1]
    jmp     .line
.none:
    xor     rax, rax
    ret

; ---------------------------------------------------------------------------
; Terminal queries.
; ---------------------------------------------------------------------------
is_tty:
    mov     rax, SYS_IOCTL
    mov     rdi, STDOUT_FILENO
    mov     rsi, 0x5401                 ;TCGETS
    mov     rdx, winbuf
    syscall
    test    rax, rax
    js      .no
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

terminal_width:
    mov     rax, SYS_IOCTL
    mov     rdi, STDOUT_FILENO
    mov     rsi, 0x5413                 ;TIOCGWINSZ
    mov     rdx, winbuf
    syscall
    test    rax, rax
    js      .out
    movzx   eax, word [winbuf + 2]      ;ws_col
    test    rax, rax
    jz      .out
    mov     [screen_w], rax
.out:
    ret

; ---------------------------------------------------------------------------
; Output buffering and number formatting.
; ---------------------------------------------------------------------------
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
    push    rcx
    push    rsi
    push    rdx
    xor     rcx, rcx
.copy:
    cmp     rcx, rdx
    jae     .out
    mov     al, [rsi + rcx]
    push    rcx
    push    rsi
    push    rdx
    call    out_char
    pop     rdx
    pop     rsi
    pop     rcx
    inc     rcx
    jmp     .copy
.out:
    pop     rdx
    pop     rsi
    pop     rcx
    ret

out_str:
    push    rsi
.copy:
    mov     al, [rsi]
    test    al, al
    jz      .out
    push    rsi
    call    out_char
    pop     rsi
    inc     rsi
    jmp     .copy
.out:
    pop     rsi
    ret

; out_str_left: the string at rax, padded with spaces to rcx columns.
out_str_left:
    push    rbx
    mov     rbx, rcx
    mov     rsi, rax
    mov     rdi, rax
    push    rsi
    call    strlen_z
    pop     rsi
    mov     rcx, rbx
    sub     rcx, rax
    push    rcx
    call    out_str
    pop     rcx
    cmp     rcx, 0
    jle     .out
.pad:
    push    rcx
    mov     al, WHITESPACE_SPACE
    call    out_char
    pop     rcx
    dec     rcx
    jnz     .pad
.out:
    pop     rbx
    ret

; out_num_right: rax as decimal, right aligned in rcx columns.
out_num_right:
    push    rbx
    mov     rbx, rax
    call    numlen
    mov     rdx, rcx
    sub     rdx, rax
    cmp     rdx, 0
    jle     .digits
.pad:
    push    rdx
    mov     al, WHITESPACE_SPACE
    call    out_char
    pop     rdx
    dec     rdx
    jnz     .pad
.digits:
    mov     rax, rbx
    pop     rbx
    jmp     out_num

out_num:
    mov     rdi, numbuf
    call    u64_to_dec
    mov     rdx, rdi
    mov     rsi, numbuf
    sub     rdx, rsi
    jmp     out_bytes

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

; u64_to_dec: write rax as decimal at rdi, advancing rdi past the digits.
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

; numlen: how many digits rax prints as. Counts in r9 rather than rcx, which
; callers are holding a field width in.
numlen:
    push    rax
    push    rdx
    mov     r9, 1
    mov     r8, 10
.step:
    cmp     rax, r8
    jb      .out
    xor     rdx, rdx
    div     r8
    inc     r9
    jmp     .step
.out:
    pop     rdx
    pop     rax
    mov     rax, r9
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

strcmp_z:
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
    ret
.less:
    mov     rax, -1
    ret
.same:
    xor     rax, rax
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
