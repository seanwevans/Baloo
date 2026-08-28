; src/ps.asm -- ps(1): report process status.
; Usage: ps [-e|-A] [-f] [-p PIDLIST] [-o FIELD[=HEADER][,FIELD...]] [PID...]
;
; Each process is read from /proc/PID/stat. The command name there is wrapped
; in parentheses and may itself contain spaces or parentheses, so the numeric
; fields are found by scanning back to the *last* ')' rather than splitting
; the line on spaces.
;
; -o picks the columns and their order, with "field=HEADER" renaming one.
; Bare numeric operands and -p both narrow the listing to those pids.
;
; Columns are padded to fixed widths -- numbers right, text left -- so the
; output lines up without having to buffer every row to measure it first.

    %include "include/sysdefs.inc"

    %define SYS_FSTAT 5

    %define DIRCAP 32768
    %define STATCAP 4096
    %define LINECAP 8192
    %define FLDCAP 4096
    %define PWCAP 65536
    %define MAXFIELDS 32
    %define MAXPIDS 256
    %define NSTATFIELDS 24
    %define USER_HZ 100

    %define ST_UID 28
    %define ST_GID 32

    %define F_PID 1
    %define F_PPID 2
    %define F_PGID 3
    %define F_SID 4
    %define F_TTY 5
    %define F_TIME 6
    %define F_COMM 7
    %define F_ARGS 8
    %define F_STAT 9
    %define F_STATE 10
    %define F_NI 11
    %define F_PRI 12
    %define F_RSS 13
    %define F_VSZ 14
    %define F_UID 15
    %define F_USER 16
    %define F_GID 17
    %define F_GROUP 18
    %define F_NLWP 19

    struc dirent64
    .d_ino      resq 1
    .d_off      resq 1
    .d_reclen   resw 1
    .d_type     resb 1
    .d_name     resb 1
    endstruc

section .bss
    dirbuf      resb DIRCAP
    statbuf     resb STATCAP
    cmdbuf      resb FLDCAP
    linebuf     resb LINECAP
    fldbuf      resb FLDCAP
    pathbuf     resb 256
    numbuf      resb 64
    pwbuf       resb PWCAP
    grbuf       resb PWCAP
    stbuf       resb 160
    statfields  resq NSTATFIELDS
    field_id    resq MAXFIELDS
    field_hdr   resq MAXFIELDS
    pidlist     resq MAXPIDS
    nfields     resq 1
    npids       resq 1
    dirfd       resq 1
    linelen     resq 1
    comm_ptr    resq 1
    comm_len    resq 1
    cur_pid     resq 1
    cur_uid     resq 1
    cur_gid     resq 1
    pwlen       resq 1
    grlen       resq 1
    col_right   resb 1
    pw_loaded   resb 1
    gr_loaded   resb 1

section .data
    proc_dir    db "/proc", 0
    passwd_path db "/etc/passwd", 0
    group_path  db "/etc/group", 0
    s_stat      db "/stat", 0
    s_cmdline   db "/cmdline", 0

    n_pid       db "PID", 0
    n_ppid      db "PPID", 0
    n_pgid      db "PGID", 0
    n_sid       db "SID", 0
    n_tty       db "TTY", 0
    n_tt        db "TT", 0
    n_time      db "TIME", 0
    n_comm      db "COMM", 0
    n_ucomm     db "UCOMM", 0
    n_cmd       db "CMD", 0
    n_args      db "ARGS", 0
    n_command   db "COMMAND", 0
    n_stat      db "STAT", 0
    n_state     db "STATE", 0
    n_s         db "S", 0
    n_ni        db "NI", 0
    n_nice      db "NICE", 0
    n_pri       db "PRI", 0
    n_rss       db "RSS", 0
    n_vsz       db "VSZ", 0
    n_uid       db "UID", 0
    n_user      db "USER", 0
    n_gid       db "GID", 0
    n_group     db "GROUP", 0
    n_nlwp      db "NLWP", 0

    h_pid       db "PID", 0
    h_ppid      db "PPID", 0
    h_pgid      db "PGID", 0
    h_sid       db "SID", 0
    h_tt        db "TT", 0
    h_time      db "TIME", 0
    h_command   db "COMMAND", 0
    h_cmd       db "CMD", 0
    h_stat      db "STAT", 0
    h_s         db "S", 0
    h_ni        db "NI", 0
    h_pri       db "PRI", 0
    h_rss       db "RSS", 0
    h_vsz       db "VSZ", 0
    h_uid       db "UID", 0
    h_user      db "USER", 0
    h_gid       db "GID", 0
    h_group     db "GROUP", 0
    h_nlwp      db "NLWP", 0

    unknown_tty db "?", 0
    pts_prefix  db "pts/", 0
    tty_prefix  db "tty", 0

usage_msg   db "Usage: ps [-efA] [-p PIDLIST] [-o FIELD[,FIELD...]] "
    db "[PID...]", 10
    usage_len   equ $ - usage_msg
badfld_msg  db "ps: unknown field", 10
    badfld_len  equ $ - badfld_msg
    newline     db WHITESPACE_NL

section .text
global _start

_start:
    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    jle     defaults
    mov     rdi, [r13]
    test    rdi, rdi
    jz      defaults
    cmp     byte [rdi], '-'
    je      .flags
    call    is_number
    test    al, al
jz      .next                       ;a BSD-style option word: ignore it
    mov     rdi, [r13]
    call    add_pid_list
    jmp     .next
.flags:
    cmp     byte [rdi + 1], 0
    je      .next
    lea     rsi, [rdi + 1]
.flag:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .next
    inc     rsi
    cmp     al, 'o'
    je      .f_o
    cmp     al, 'p'
    je      .f_p
jmp     .flag                       ;-e/-A/-f and friends: list everything
.f_o:
    call    opt_value
    mov     rdi, rdx
    call    add_fields
    jmp     .next
.f_p:
    call    opt_value
    mov     rdi, rdx
    call    add_pid_list
.next:
    add     r13, 8
    dec     r12
    jmp     parse

; opt_value: the rest of this bundle is the value, or the next argument is.
opt_value:
    cmp     byte [rsi], 0
    je      .separate
    mov     rdx, rsi
    ret
.separate:
    add     r13, 8
    dec     r12
    mov     rdx, [r13]
    test    rdx, rdx
    jz      usage
    ret

usage:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, usage_msg
    mov     rdx, usage_len
    syscall
    exit    1

bad_field:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, badfld_msg
    mov     rdx, badfld_len
    syscall
    exit    1

defaults:
    cmp     qword [nfields], 0
    jne     header
    mov     qword [field_id], F_PID
    mov     qword [field_hdr], h_pid
    mov     qword [field_id + 8], F_TTY
    mov     qword [field_hdr + 8], h_tt
    mov     qword [field_id + 16], F_TIME
    mov     qword [field_hdr + 16], h_time
    mov     qword [field_id + 24], F_COMM
    mov     qword [field_hdr + 24], h_cmd
    mov     qword [nfields], 4

header:
    mov     qword [linelen], 0
    xor     rbx, rbx
.column:
    cmp     rbx, [nfields]
    jge     .emit
    mov     rdi, [field_hdr + rbx * 8]
    call    copy_to_fld                 ;-> rax = length
    mov     rdx, rax
    call    place_column
    inc     rbx
    jmp     .column
.emit:
    call    flush_line

scan:
    mov     rax, SYS_OPEN
    mov     rdi, proc_dir
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fail
    mov     [dirfd], rax
.batch:
    mov     rax, SYS_GETDENTS64
    mov     rdi, [dirfd]
    mov     rsi, dirbuf
    mov     rdx, DIRCAP
    syscall
    test    rax, rax
    jle     .done
    mov     r14, rax                    ;bytes in this batch
    xor     r15, r15                    ;offset
.entry:
    cmp     r15, r14
    jge     .batch
    lea     rbx, [dirbuf + r15]
    movzx   rax, word [rbx + dirent64.d_reclen]
    add     r15, rax
    lea     rdi, [rbx + dirent64.d_name]
    call    is_number
    test    al, al
    jz      .entry
    lea     rdi, [rbx + dirent64.d_name]
    call    atou
    mov     [cur_pid], rax
    cmp     qword [npids], 0
    je      .show
    call    pid_wanted
    test    al, al
    jz      .entry
.show:
    call    emit_process
    jmp     .entry
.done:
    mov     rax, SYS_CLOSE
    mov     rdi, [dirfd]
    syscall
    exit    0
.fail:
    exit    1

; pid_wanted: is cur_pid in the requested list? al = 1/0.
pid_wanted:
    xor     rcx, rcx
.scan:
    cmp     rcx, [npids]
    jge     .no
    mov     rax, [pidlist + rcx * 8]
    cmp     rax, [cur_pid]
    je      .yes
    inc     rcx
    jmp     .scan
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; emit_process: read the current pid's stat file and print its row.
; ---------------------------------------------------------------------------
emit_process:
    push    r14
    push    r15
    mov     rsi, s_stat
    call    read_proc_file              ;-> rax = length, in statbuf
    cmp     rax, 0
    jle     .out
    call    split_stat
    test    al, al
    jz      .out
    mov     qword [linelen], 0
    mov     qword [cur_uid], -1
    xor     rbx, rbx
.column:
    cmp     rbx, [nfields]
    jge     .emit
    mov     rdi, [field_id + rbx * 8]
    call    render_field                ;-> rax = length, in fldbuf
    mov     rdx, rax
    call    place_column
    inc     rbx
    jmp     .column
.emit:
    call    flush_line
.out:
    pop     r15
    pop     r14
    ret

; ---------------------------------------------------------------------------
; split_stat: point statfields at the numeric fields after the command name.
; The name is parenthesised and can contain anything, so the scan for its end
; goes backwards from the end of the line. al = 1 when the line made sense.
; ---------------------------------------------------------------------------
split_stat:
    mov     rcx, rax
    mov     byte [statbuf + rcx], 0
    mov     r8, rcx
.findclose:
    test    r8, r8
    jz      .bad
    dec     r8
    cmp     byte [statbuf + r8], ')'
    jne     .findclose
    mov     r9, 0
.findopen:
    cmp     r9, r8
    jae     .bad
    cmp     byte [statbuf + r9], '('
    je      .name
    inc     r9
    jmp     .findopen
.name:
    inc     r9
    mov     [comm_ptr], r9
    mov     rax, r8
    sub     rax, r9
    mov     [comm_len], rax
    inc     r8                          ;just past ')'
    xor     rdx, rdx                    ;field index
.fields:
    cmp     rdx, NSTATFIELDS
    jae     .ok
.skipspace:
    cmp     r8, rcx
    jae     .ok
    cmp     byte [statbuf + r8], WHITESPACE_SPACE
    jne     .start
    inc     r8
    jmp     .skipspace
.start:
    cmp     r8, rcx
    jae     .ok
    lea     rax, [statbuf + r8]
    mov     [statfields + rdx * 8], rax
    inc     rdx
.token:
    cmp     r8, rcx
    jae     .ok
    cmp     byte [statbuf + r8], WHITESPACE_SPACE
    je      .fields
    inc     r8
    jmp     .token
.ok:
    mov     al, 1
    ret
.bad:
    xor     al, al
    ret

; stat_num: the signed value of stat field rdi, in rax.
stat_num:
    cmp     rdi, NSTATFIELDS
    jae     .zero
    mov     rsi, [statfields + rdi * 8]
    test    rsi, rsi
    jz      .zero
    mov     rdi, rsi
    jmp     atoi_signed
.zero:
    xor     rax, rax
    ret

; ---------------------------------------------------------------------------
; render_field: build the text of field rdi in fldbuf, returning its length.
; ---------------------------------------------------------------------------
render_field:
    cmp     rdi, F_PID
    je      .pid
    cmp     rdi, F_PPID
    je      .ppid
    cmp     rdi, F_PGID
    je      .pgid
    cmp     rdi, F_SID
    je      .sid
    cmp     rdi, F_TTY
    je      .tty
    cmp     rdi, F_TIME
    je      .time
    cmp     rdi, F_COMM
    je      .comm
    cmp     rdi, F_ARGS
    je      .args
    cmp     rdi, F_STAT
    je      .stat
    cmp     rdi, F_STATE
    je      .stat
    cmp     rdi, F_NI
    je      .ni
    cmp     rdi, F_PRI
    je      .pri
    cmp     rdi, F_RSS
    je      .rss
    cmp     rdi, F_VSZ
    je      .vsz
    cmp     rdi, F_UID
    je      .uid
    cmp     rdi, F_USER
    je      .user
    cmp     rdi, F_GID
    je      .gid
    cmp     rdi, F_GROUP
    je      .group
    cmp     rdi, F_NLWP
    je      .nlwp
    xor     rax, rax
    ret
.pid:
    mov     rax, [cur_pid]
    jmp     num_to_fld
.ppid:
    mov     rdi, 1
    jmp     .statnum
.pgid:
    mov     rdi, 2
    jmp     .statnum
.sid:
    mov     rdi, 3
    jmp     .statnum
.pri:
    mov     rdi, 15
    call    stat_num
    mov     rcx, 39                     ;ps counts priority the other way up
    sub     rcx, rax
    mov     rax, rcx
    jmp     num_to_fld
.ni:
    mov     rdi, 16
    jmp     .statnum
.nlwp:
    mov     rdi, 17
.statnum:
    call    stat_num
    jmp     num_to_fld
.vsz:
    mov     rdi, 20
    call    stat_num
    shr     rax, 10                     ;bytes to kilobytes
    jmp     num_to_fld
.rss:
    mov     rdi, 21
    call    stat_num
    shl     rax, 2                      ;pages of 4K to kilobytes
    jmp     num_to_fld
.stat:
    mov     rsi, [statfields]
    test    rsi, rsi
    jz      .empty
    mov     al, [rsi]
    mov     [fldbuf], al
    mov     rax, 1
    ret
.uid:
    call    load_ids
    mov     rax, [cur_uid]
    jmp     num_to_fld
.gid:
    call    load_ids
    mov     rax, [cur_gid]
    jmp     num_to_fld
.user:
    call    load_ids
    mov     rdi, [cur_uid]
    mov     rsi, pwbuf
    mov     rdx, [pwlen]
    call    id_to_name
    test    rax, rax
    jnz     .name
    mov     rax, [cur_uid]
    jmp     num_to_fld
.group:
    call    load_ids
    mov     rdi, [cur_gid]
    mov     rsi, grbuf
    mov     rdx, [grlen]
    call    id_to_name
    test    rax, rax
    jnz     .name
    mov     rax, [cur_gid]
    jmp     num_to_fld
.name:
    mov     rdi, rax
    jmp     copy_to_fld
.tty:
    mov     rdi, 4
    call    stat_num
    jmp     tty_to_fld
.time:
    mov     rdi, 11
    call    stat_num
    mov     r8, rax
    mov     rdi, 12
    call    stat_num
    add     rax, r8
    jmp     time_to_fld
.comm:
    mov     rsi, statbuf
    add     rsi, [comm_ptr]
    mov     rcx, [comm_len]
    jmp     bytes_to_fld
.args:
    call    read_cmdline
    test    rax, rax
    jnz     .havecmd
    mov     rsi, statbuf                ;a kernel thread has no command line
    add     rsi, [comm_ptr]
    mov     rcx, [comm_len]
    jmp     bytes_to_fld
.havecmd:
    mov     rsi, cmdbuf
    mov     rcx, rax
    jmp     bytes_to_fld
.empty:
    xor     rax, rax
    ret

; load_ids: the owner of /proc/PID, which is the process owner.
load_ids:
    cmp     qword [cur_uid], -1
    jne     .out
    mov     qword [cur_uid], 0
    mov     qword [cur_gid], 0
    mov     rsi, 0
    call    build_path
    mov     rax, SYS_STAT
    mov     rdi, pathbuf
    mov     rsi, stbuf
    syscall
    test    rax, rax
    js      .out
    mov     eax, [stbuf + ST_UID]
    mov     [cur_uid], rax
    mov     eax, [stbuf + ST_GID]
    mov     [cur_gid], rax
    call    load_passwd
.out:
    ret

; ---------------------------------------------------------------------------
; Field text helpers. Each leaves the text in fldbuf and its length in rax.
; ---------------------------------------------------------------------------
num_to_fld:
    mov     rdi, fldbuf
    call    i64_to_dec
    mov     rax, rdi
    sub     rax, fldbuf
    ret

copy_to_fld:
    mov     rsi, rdi
    xor     rax, rax
.copy:
    mov     cl, [rsi + rax]
    test    cl, cl
    jz      .out
    cmp     rax, FLDCAP - 1
    jae     .out
    mov     [fldbuf + rax], cl
    inc     rax
    jmp     .copy
.out:
    ret

bytes_to_fld:
    xor     rax, rax
.copy:
    cmp     rax, rcx
    jae     .out
    cmp     rax, FLDCAP - 1
    jae     .out
    mov     dl, [rsi + rax]
    mov     [fldbuf + rax], dl
    inc     rax
    jmp     .copy
.out:
    ret

; tty_to_fld: turn a tty_nr into a device name, or "?" when there is none.
tty_to_fld:
    test    rax, rax
    jz      .none
    mov     r8, rax
    shr     r8, 8
    and     r8, 0xFFF                   ;major
    mov     r9, rax
    and     r9, 0xFF
    mov     r10, rax
    shr     r10, 12
    and     r10, 0xFFF00
    or      r9, r10                     ;minor
    cmp     r8, 136
    je      .pts
    cmp     r8, 4
    je      .console
    jmp     .none
.pts:
    mov     rdi, pts_prefix
    jmp     .withnum
.console:
    mov     rdi, tty_prefix
.withnum:
    push    r9
    call    copy_to_fld
    pop     r9
    lea     rdi, [fldbuf + rax]
    mov     rax, r9
    call    i64_to_dec
    mov     rax, rdi
    sub     rax, fldbuf
    ret
.none:
    mov     rdi, unknown_tty
    jmp     copy_to_fld

; time_to_fld: clock ticks as HH:MM:SS.
time_to_fld:
    xor     rdx, rdx
    mov     rcx, USER_HZ
    div     rcx                         ;seconds
    xor     rdx, rdx
    mov     rcx, 60
    div     rcx
    mov     r8, rdx                     ;seconds
    xor     rdx, rdx
    div     rcx
    mov     r9, rdx                     ;minutes
    mov     r10, rax                    ;hours
    mov     rdi, fldbuf
    mov     rax, r10
    call    two_digits
mov     byte [rdi], ':'
    inc     rdi
    mov     rax, r9
    call    two_digits
mov     byte [rdi], ':'
    inc     rdi
    mov     rax, r8
    call    two_digits
    mov     rax, rdi
    sub     rax, fldbuf
    ret

; two_digits: rax as at least two digits at rdi, advancing rdi.
two_digits:
    cmp     rax, 10
    jae     .wide
    mov     byte [rdi], '0'
    inc     rdi
.wide:
    jmp     i64_to_dec

; ---------------------------------------------------------------------------
; place_column: append the rdx-byte field to the line, padded to the column's
; width -- numbers to the right, text to the left. rbx is the column index.
; ---------------------------------------------------------------------------
place_column:
    push    rbx
    push    rdx
    cmp     qword [linelen], 0
    je      .body
    mov     rcx, [linelen]
    mov     byte [linebuf + rcx], WHITESPACE_SPACE
    inc     qword [linelen]
.body:
    mov     rdi, [field_id + rbx * 8]
    call    column_width                ;-> rax width, col_right alignment
    pop     rdx
    push    rdx
    mov     rcx, rax
    sub     rcx, rdx
    jle     .text
    cmp     byte [col_right], 0
    je      .text
.padleft:
    push    rcx
    mov     rcx, [linelen]
    mov     byte [linebuf + rcx], WHITESPACE_SPACE
    inc     qword [linelen]
    pop     rcx
    dec     rcx
    jnz     .padleft
.text:
    pop     rdx
    push    rdx
    xor     rcx, rcx
.copy:
    cmp     rcx, rdx
    jae     .padded
    mov     r9, [linelen]
    cmp     r9, LINECAP - 2
    jae     .padded
    mov     al, [fldbuf + rcx]
    mov     [linebuf + r9], al
    inc     qword [linelen]
    inc     rcx
    jmp     .copy
.padded:
    mov     rax, rbx
    inc     rax
    cmp     rax, [nfields]
    jge     .out                        ;never pad the last column
    mov     rdi, [field_id + rbx * 8]
    call    column_width
    cmp     byte [col_right], 0
    jne     .out                        ;right aligned columns need no tail
    pop     rdx
    push    rdx
    mov     rcx, rax
    sub     rcx, rdx
    jle     .out
.padright:
    push    rcx
    mov     rcx, [linelen]
    cmp     rcx, LINECAP - 2
    jae     .stop
    mov     byte [linebuf + rcx], WHITESPACE_SPACE
    inc     qword [linelen]
.stop:
    pop     rcx
    dec     rcx
    jnz     .padright
.out:
    pop     rdx
    pop     rbx
    ret

; column_width: the column's width in rax, with col_right set when the field
; is a number and should sit against the right of it.
column_width:
    mov     byte [col_right], 0
    cmp     rdi, F_PID
    je      .w5r
    cmp     rdi, F_PPID
    je      .w5r
    cmp     rdi, F_PGID
    je      .w5r
    cmp     rdi, F_SID
    je      .w5r
    cmp     rdi, F_UID
    je      .w5r
    cmp     rdi, F_GID
    je      .w5r
    cmp     rdi, F_NI
    je      .w3r
    cmp     rdi, F_PRI
    je      .w3r
    cmp     rdi, F_NLWP
    je      .w4r
    cmp     rdi, F_RSS
    je      .w6r
    cmp     rdi, F_VSZ
    je      .w6r
    cmp     rdi, F_TIME
    je      .w8r
    cmp     rdi, F_TTY
    je      .w8l
    cmp     rdi, F_USER
    je      .w8l
    cmp     rdi, F_GROUP
    je      .w8l
    cmp     rdi, F_STAT
    je      .w4l
    cmp     rdi, F_STATE
    je      .w1l
    xor     rax, rax                    ;command columns run to the end
    ret
.w1l:
    mov     rax, 1
    ret
.w4l:
    mov     rax, 4
    ret
.w8l:
    mov     rax, 8
    ret
.w3r:
    mov     rax, 3
    jmp     .right
.w4r:
    mov     rax, 4
    jmp     .right
.w5r:
    mov     rax, 5
    jmp     .right
.w6r:
    mov     rax, 6
    jmp     .right
.w8r:
    mov     rax, 8
.right:
    mov     byte [col_right], 1
    ret

flush_line:
    mov     rcx, [linelen]
    mov     byte [linebuf + rcx], WHITESPACE_NL
    inc     rcx
    mov     rdx, rcx
    mov     rsi, linebuf
.write:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    test    rax, rax
    jle     .out
    add     rsi, rax
    sub     rdx, rax
    jnz     .write
.out:
    mov     qword [linelen], 0
    ret

; ---------------------------------------------------------------------------
; Reading out of /proc.
; ---------------------------------------------------------------------------
; build_path: "/proc/<cur_pid>" plus the suffix at rsi (0 for none).
build_path:
    push    rsi
    mov     rdi, pathbuf
    mov     rsi, proc_dir
    call    append_str
    mov     byte [rdi], '/'
    inc     rdi
    mov     rax, [cur_pid]
    call    i64_to_dec
    pop     rsi
    test    rsi, rsi
    jz      .done
    call    append_str
.done:
    mov     byte [rdi], 0
    ret

; read_proc_file: read /proc/<cur_pid><rsi> into statbuf. rax = bytes.
read_proc_file:
    call    build_path
    mov     rax, SYS_OPEN
    mov     rdi, pathbuf
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fail
    mov     r10, rax
    mov     rax, SYS_READ
    mov     rdi, r10
    mov     rsi, statbuf
    mov     rdx, STATCAP - 1
    syscall
    mov     r11, rax
    push    r11
    mov     rax, SYS_CLOSE
    mov     rdi, r10
    syscall
    pop     rax
    ret
.fail:
    xor     rax, rax
    ret

; read_cmdline: the process's argument vector with NULs turned into spaces,
; in cmdbuf. rax = length, zero for a kernel thread.
read_cmdline:
    mov     rsi, s_cmdline
    call    build_path
    mov     rax, SYS_OPEN
    mov     rdi, pathbuf
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .none
    mov     r10, rax
    mov     rax, SYS_READ
    mov     rdi, r10
    mov     rsi, cmdbuf
    mov     rdx, FLDCAP - 1
    syscall
    mov     r11, rax
    push    r11
    mov     rax, SYS_CLOSE
    mov     rdi, r10
    syscall
    pop     rax
    cmp     rax, 0
    jle     .none
.trim:
    cmp     rax, 0
    jle     .none
    cmp     byte [cmdbuf + rax - 1], 0
    jne     .spaces
    dec     rax
    jmp     .trim
.spaces:
    xor     rcx, rcx
.space:
    cmp     rcx, rax
    jae     .out
    cmp     byte [cmdbuf + rcx], 0
    jne     .next
    mov     byte [cmdbuf + rcx], WHITESPACE_SPACE
.next:
    inc     rcx
    jmp     .space
.out:
    ret
.none:
    xor     rax, rax
    ret

; ---------------------------------------------------------------------------
; Name lookups out of /etc/passwd and /etc/group.
; ---------------------------------------------------------------------------
load_passwd:
    cmp     byte [pw_loaded], 0
    jne     .out
    mov     byte [pw_loaded], 1
    mov     rdi, passwd_path
    mov     rsi, pwbuf
    call    slurp
    mov     [pwlen], rax
    mov     rdi, group_path
    mov     rsi, grbuf
    call    slurp
    mov     [grlen], rax
.out:
    ret

; slurp: read the file named by rdi into rsi, at most PWCAP bytes.
slurp:
    push    rsi
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    pop     rsi
    test    rax, rax
    js      .none
    mov     r10, rax
    xor     r11, r11
.read:
    push    rsi
    push    r11
    mov     rax, SYS_READ
    mov     rdi, r10
    lea     rsi, [rsi + r11]
    mov     rdx, PWCAP
    sub     rdx, r11
    jle     .full
    syscall
    pop     r11
    pop     rsi
    test    rax, rax
    jle     .close
    add     r11, rax
    jmp     .read
.full:
    pop     r11
    pop     rsi
.close:
    push    r11
    mov     rax, SYS_CLOSE
    mov     rdi, r10
    syscall
    pop     rax
    ret
.none:
    xor     rax, rax
    ret

; id_to_name: find the colon-separated line in [rsi, rsi+rdx) whose third
; field is the id in rdi, and return a pointer to its NUL-terminated name.
; rax = 0 when there is no such line.
id_to_name:
    test    rdx, rdx
    jz      .none
    mov     r8, rdi                     ;wanted id
    mov     r9, rsi                     ;buffer
    mov     r10, rdx                    ;length
    xor     rcx, rcx                    ;line start
.line:
    cmp     rcx, r10
    jae     .none
    mov     r11, rcx                    ;cursor
.name_end:
    cmp     r11, r10
    jae     .none
    mov     al, [r9 + r11]
cmp     al, ':'
    je      .after_name
    cmp     al, WHITESPACE_NL
    je      .next_line
    inc     r11
    jmp     .name_end
.after_name:
    mov     rdi, r11                    ;where the name ends
    inc     r11
.skip_passwd:
    cmp     r11, r10
    jae     .none
    mov     al, [r9 + r11]
    inc     r11
cmp     al, ':'
    jne     .skip_passwd
    xor     rax, rax                    ;parse the id field
    xor     rsi, rsi                    ;digits seen
.id_digit:
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
    jmp     .id_digit
.compare:
    test    rsi, rsi
    jz      .next_line
    cmp     rax, r8
    jne     .next_line
    mov     byte [r9 + rdi], 0          ;terminate the name in place
    lea     rax, [r9 + rcx]
    ret
.next_line:
    cmp     r11, r10
    jae     .none
    cmp     byte [r9 + r11], WHITESPACE_NL
    je      .advance
    inc     r11
    jmp     .next_line
.advance:
    lea     rcx, [r11 + 1]
    jmp     .line
.none:
    xor     rax, rax
    ret

; ---------------------------------------------------------------------------
; Option values.
; ---------------------------------------------------------------------------
; add_fields: split the -o list at rdi on commas and spaces, resolving each
; name and honouring "field=HEADER".
add_fields:
    mov     rsi, rdi
.token:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .out
    cmp     al, ','
    je      .skip
    cmp     al, WHITESPACE_SPACE
    je      .skip
    mov     rdi, numbuf
    xor     rcx, rcx
    xor     r8, r8                      ;header override
.copy:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .have
    cmp     al, ','
    je      .have
    cmp     al, WHITESPACE_SPACE
    je      .have
    cmp     al, '='
    jne     .store
    inc     rsi
    mov     r8, rsi                     ;the rest of the token names the header
.rest:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .have
    cmp     al, ','
    je      .have
    inc     rsi
    jmp     .rest
.store:
    cmp     rcx, 62
    jae     .skipchar
    mov     [numbuf + rcx], al
    inc     rcx
.skipchar:
    inc     rsi
    jmp     .copy
.have:
    mov     byte [numbuf + rcx], 0
    test    rcx, rcx
    jz      .token
    push    rsi
    push    r8
    call    field_by_name               ;-> rax id, rdx default header
    pop     r8
    pop     rsi
    test    rax, rax
    jz      bad_field
    mov     rcx, [nfields]
    cmp     rcx, MAXFIELDS
    jae     .token
    mov     [field_id + rcx * 8], rax
    test    r8, r8
    jz      .default_header
    mov     [field_hdr + rcx * 8], r8
    jmp     .count
.default_header:
    mov     [field_hdr + rcx * 8], rdx
.count:
    inc     rcx
    mov     [nfields], rcx
    jmp     .token
.skip:
    inc     rsi
    jmp     .token
.out:
    ret

; field_by_name: resolve the name in numbuf. rax = id (0 unknown), rdx = the
; default header for it.
field_by_name:
    mov     rdi, numbuf
    call    upcase
    mov     rsi, n_pid
    call    nameeq
    test    al, al
    jnz     .pid
    mov     rsi, n_ppid
    call    nameeq
    test    al, al
    jnz     .ppid
    mov     rsi, n_pgid
    call    nameeq
    test    al, al
    jnz     .pgid
    mov     rsi, n_sid
    call    nameeq
    test    al, al
    jnz     .sid
    mov     rsi, n_tty
    call    nameeq
    test    al, al
    jnz     .tty
    mov     rsi, n_tt
    call    nameeq
    test    al, al
    jnz     .tty
    mov     rsi, n_time
    call    nameeq
    test    al, al
    jnz     .time
    mov     rsi, n_comm
    call    nameeq
    test    al, al
    jnz     .comm
    mov     rsi, n_ucomm
    call    nameeq
    test    al, al
    jnz     .comm
    mov     rsi, n_cmd
    call    nameeq
    test    al, al
    jnz     .cmd
    mov     rsi, n_args
    call    nameeq
    test    al, al
    jnz     .args
    mov     rsi, n_command
    call    nameeq
    test    al, al
    jnz     .args
    mov     rsi, n_stat
    call    nameeq
    test    al, al
    jnz     .stat
    mov     rsi, n_state
    call    nameeq
    test    al, al
    jnz     .state
    mov     rsi, n_s
    call    nameeq
    test    al, al
    jnz     .state
    mov     rsi, n_ni
    call    nameeq
    test    al, al
    jnz     .ni
    mov     rsi, n_nice
    call    nameeq
    test    al, al
    jnz     .ni
    mov     rsi, n_pri
    call    nameeq
    test    al, al
    jnz     .pri
    mov     rsi, n_rss
    call    nameeq
    test    al, al
    jnz     .rss
    mov     rsi, n_vsz
    call    nameeq
    test    al, al
    jnz     .vsz
    mov     rsi, n_uid
    call    nameeq
    test    al, al
    jnz     .uid
    mov     rsi, n_user
    call    nameeq
    test    al, al
    jnz     .user
    mov     rsi, n_gid
    call    nameeq
    test    al, al
    jnz     .gid
    mov     rsi, n_group
    call    nameeq
    test    al, al
    jnz     .group
    mov     rsi, n_nlwp
    call    nameeq
    test    al, al
    jnz     .nlwp
    xor     rax, rax
    ret
.pid:
    mov     rax, F_PID
    mov     rdx, h_pid
    ret
.ppid:
    mov     rax, F_PPID
    mov     rdx, h_ppid
    ret
.pgid:
    mov     rax, F_PGID
    mov     rdx, h_pgid
    ret
.sid:
    mov     rax, F_SID
    mov     rdx, h_sid
    ret
.tty:
    mov     rax, F_TTY
    mov     rdx, h_tt
    ret
.time:
    mov     rax, F_TIME
    mov     rdx, h_time
    ret
.comm:
    mov     rax, F_COMM
    mov     rdx, h_command
    ret
.cmd:
    mov     rax, F_ARGS
    mov     rdx, h_cmd
    ret
.args:
    mov     rax, F_ARGS
    mov     rdx, h_command
    ret
.stat:
    mov     rax, F_STAT
    mov     rdx, h_stat
    ret
.state:
    mov     rax, F_STATE
    mov     rdx, h_s
    ret
.ni:
    mov     rax, F_NI
    mov     rdx, h_ni
    ret
.pri:
    mov     rax, F_PRI
    mov     rdx, h_pri
    ret
.rss:
    mov     rax, F_RSS
    mov     rdx, h_rss
    ret
.vsz:
    mov     rax, F_VSZ
    mov     rdx, h_vsz
    ret
.uid:
    mov     rax, F_UID
    mov     rdx, h_uid
    ret
.user:
    mov     rax, F_USER
    mov     rdx, h_user
    ret
.gid:
    mov     rax, F_GID
    mov     rdx, h_gid
    ret
.group:
    mov     rax, F_GROUP
    mov     rdx, h_group
    ret
.nlwp:
    mov     rax, F_NLWP
    mov     rdx, h_nlwp
    ret

; add_pid_list: collect the comma or space separated pids at rdi.
add_pid_list:
    mov     rsi, rdi
.token:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .out
    cmp     al, ','
    je      .skip
    cmp     al, WHITESPACE_SPACE
    je      .skip
    xor     rax, rax
    xor     r8, r8
.digit:
    movzx   rcx, byte [rsi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .have
    imul    rax, rax, 10
    add     rax, rcx
    inc     r8
    inc     rsi
    jmp     .digit
.have:
    test    r8, r8
    jz      .skip
    mov     rcx, [npids]
    cmp     rcx, MAXPIDS
    jae     .token
    mov     [pidlist + rcx * 8], rax
    inc     rcx
    mov     [npids], rcx
    jmp     .token
.skip:
    inc     rsi
    jmp     .token
.out:
    ret

; ---------------------------------------------------------------------------
; Small helpers.
; ---------------------------------------------------------------------------
upcase:
    xor     rcx, rcx
.scan:
    movzx   eax, byte [rdi + rcx]
    test    al, al
    jz      .out
    cmp     al, 'a'
    jb      .next
    cmp     al, 'z'
    ja      .next
    sub     al, 32
    mov     [rdi + rcx], al
.next:
    inc     rcx
    jmp     .scan
.out:
    ret

; nameeq: does numbuf equal the literal at rsi? al = 1/0.
nameeq:
    push    rsi
    mov     rdi, numbuf
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
    ret
.no:
    xor     al, al
    pop     rsi
    ret

; is_number: is the string at rdi all digits and non-empty? al = 1/0.
is_number:
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

atoi_signed:
    xor     r8, r8
    cmp     byte [rdi], '-'
    jne     .digits
    mov     r8, 1
    inc     rdi
.digits:
    call    atou
    test    r8, r8
    jz      .out
    neg     rax
.out:
    ret

; i64_to_dec: write rax as a signed decimal at rdi, advancing rdi.
i64_to_dec:
    push    rbx
    test    rax, rax
    jns     .digits
    mov     byte [rdi], '-'
    inc     rdi
    neg     rax
.digits:
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

; append_str: copy the NUL-terminated string at rsi to rdi, advancing rdi.
append_str:
    mov     al, [rsi]
    test    al, al
    jz      .out
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     append_str
.out:
    ret
