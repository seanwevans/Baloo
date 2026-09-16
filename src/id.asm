; src/id.asm -- id(1): print user and group ids.
; Usage: id [-nr] [-u|-g|-G] [USER...]
;
; With no USER operand the process's own ids are printed, and its group list
; comes from getgroups(2). A USER operand is looked up in /etc/passwd by name
; and then, failing that, as a numeric id; its groups are the primary one plus
; every /etc/group entry naming it as a member. An unknown USER is reported on
; stderr and makes the exit status 1, leaving stdout untouched.
;
; -u, -g and -G select a single id or the group list, -n prints names instead
; of numbers, and -r uses the real rather than the effective ids. Names that
; have no table entry fall back to the numeric id.

    %include "include/sysdefs.inc"

    %define TABLE_CAP  65536
    %define MAX_GIDS   256
    %define MAX_USERS  64
    %define NAME_CAP   256

section .bss
    pw_buf      resb TABLE_CAP          ;/etc/passwd, as read
    gr_buf      resb TABLE_CAP          ;/etc/group, as read
    pw_len      resq 1
    gr_len      resq 1
    users       resq MAX_USERS          ;USER operands
    nusers      resq 1
    gids        resq MAX_GIDS           ;group list of the current entry
    ngids       resq 1
    grp_raw     resd MAX_GIDS           ;getgroups(2) landing area
    user_name   resb NAME_CAP           ;name of the current entry
    name_buf    resb NAME_CAP           ;scratch for table lookups
    numbuf      resb 32
    cur_uid     resq 1
    cur_gid     resq 1
    opt_u       resb 1
    opt_g       resb 1
    opt_G       resb 1
    opt_n       resb 1
    opt_r       resb 1
    endopts     resb 1
    had_err     resb 1

section .data
    passwd_path db "/etc/passwd", 0
    group_path  db "/etc/group", 0
    uid_prefix  db "uid=", 0
    gid_prefix  db " gid=", 0
    grp_prefix  db " groups=", 0
    newline     db WHITESPACE_NL
    comma       db ","
    space       db " "
    lparen      db "("
    rparen      db ")"
err_pre     db "id: '"
    err_pre_len equ $ - err_pre
err_post    db "': no such user", WHITESPACE_NL
    err_post_len equ $ - err_post
err_many    db `id: cannot print "only" of more than one choice`, WHITESPACE_NL
    err_many_len equ $ - err_many
err_plain   db "id: cannot print only names or real IDs in default format", WHITESPACE_NL
    err_plain_len equ $ - err_plain
usage_msg   db "Usage: id [-nr] [-u|-g|-G] [USER...]", WHITESPACE_NL
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12
parse:
    cmp     r12, 0
    je      after_parse
    mov     rdi, [r13]
    cmp     byte [endopts], 0
    jne     .operand
    cmp     byte [rdi], '-'
    jne     .operand
    cmp     byte [rdi + 1], 0
    je      .operand                    ;a lone "-" is an operand
    cmp     byte [rdi + 1], '-'
    jne     .flags
    cmp     byte [rdi + 2], 0
    jne     .badopt
    mov     byte [endopts], 1           ;"--" ends the options
    jmp     .nextarg
.flags:
    inc     rdi
.flag_loop:
    mov     al, [rdi]
    test    al, al
    jz      .nextarg
    cmp     al, 'u'
    je      .f_u
    cmp     al, 'g'
    je      .f_g
    cmp     al, 'G'
    je      .f_G
    cmp     al, 'n'
    je      .f_n
    cmp     al, 'r'
    je      .f_r
    cmp     al, 'a'
    je      .f_next                     ;accepted and ignored, as in id(1)
    jmp     .badopt
.f_u:
    mov     byte [opt_u], 1
    jmp     .f_next
.f_g:
    mov     byte [opt_g], 1
    jmp     .f_next
.f_G:
    mov     byte [opt_G], 1
    jmp     .f_next
.f_n:
    mov     byte [opt_n], 1
    jmp     .f_next
.f_r:
    mov     byte [opt_r], 1
.f_next:
    inc     rdi
    jmp     .flag_loop
.badopt:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1
.operand:
    mov     rcx, [nusers]
    cmp     rcx, MAX_USERS
    jae     .nextarg
    mov     [users + rcx*8], rdi
    inc     qword [nusers]
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

after_parse:
;-u, -g and -G pick one thing to print, and -n/-r need one of them
    movzx   eax, byte [opt_u]
    movzx   ecx, byte [opt_g]
    add     eax, ecx
    movzx   ecx, byte [opt_G]
    add     eax, ecx
    cmp     eax, 1
    jle     .modes_ok
    write   STDERR_FILENO, err_many, err_many_len
    exit    1
.modes_ok:
    test    eax, eax
    jnz     .load
    movzx   eax, byte [opt_n]
    movzx   ecx, byte [opt_r]
    or      eax, ecx
    jz      .load
    write   STDERR_FILENO, err_plain, err_plain_len
    exit    1
.load:
    mov     rdi, passwd_path
    mov     rsi, pw_buf
    mov     rdx, TABLE_CAP
    call    slurp
    mov     [pw_len], rax
    mov     rdi, group_path
    mov     rsi, gr_buf
    mov     rdx, TABLE_CAP
    call    slurp
    mov     [gr_len], rax

    cmp     qword [nusers], 0
    jne     each_user

;no operand: this process's own ids, with its own supplementary groups
    mov     rax, SYS_GETEUID
    cmp     byte [opt_r], 0
    je      .euid
    mov     rax, SYS_GETUID
.euid:
    syscall
    mov     [cur_uid], rax
    mov     rax, SYS_GETEGID
    cmp     byte [opt_r], 0
    je      .egid
    mov     rax, SYS_GETGID
.egid:
    syscall
    mov     [cur_gid], rax
    mov     byte [user_name], 0
    mov     rdi, [cur_uid]
    call    uid_name
    test    rax, rax
    jz      .own_groups
    mov     rsi, rax
    mov     rdi, user_name
    call    strcpy_c
.own_groups:
    call    collect_own_groups
    call    print_entry
    exit    0

each_user:
    xor     r14, r14                    ;operand index
.each:
    cmp     r14, [nusers]
    jae     .done
    xor     rdi, rdi                    ;match by name
    mov     rsi, [users + r14*8]
    call    pw_scan
    test    rax, rax
    jnz     .have
    mov     rdi, [users + r14*8]        ;or as a numeric id
    call    parse_id
    test    rdx, rdx
    jz      .unknown
    mov     rsi, rax
    mov     rdi, 1
    call    pw_scan
    test    rax, rax
    jnz     .have
.unknown:
    write   STDERR_FILENO, err_pre, err_pre_len
    mov     rdi, [users + r14*8]
    call    err_str
    write   STDERR_FILENO, err_post, err_post_len
    mov     byte [had_err], 1
    jmp     .next
.have:
    call    collect_user_groups
    call    print_entry
.next:
    inc     r14
    jmp     .each
.done:
    movzx   edi, byte [had_err]
    mov     rax, SYS_EXIT
    syscall

; ---------------------------------------------------------------------------
; Output
; ---------------------------------------------------------------------------
; print_entry: one line for cur_uid/cur_gid/gids, in the selected format.
print_entry:
    push    r12
    cmp     byte [opt_u], 0
    jne     .only_uid
    cmp     byte [opt_g], 0
    jne     .only_gid
    cmp     byte [opt_G], 0
    jne     .only_groups

    mov     rdi, uid_prefix
    call    put_str
    mov     rdi, [cur_uid]
    call    put_uid_named
    mov     rdi, gid_prefix
    call    put_str
    mov     rdi, [cur_gid]
    call    put_gid_named
    mov     rdi, grp_prefix
    call    put_str
    xor     r12, r12
.grp_loop:
    cmp     r12, [ngids]
    jae     .end
    test    r12, r12
    jz      .grp_put
    write   STDOUT_FILENO, comma, 1
.grp_put:
    mov     rdi, [gids + r12*8]
    call    put_gid_named
    inc     r12
    jmp     .grp_loop

.only_uid:
    cmp     byte [opt_n], 0
    je      .uid_num
    cmp     byte [user_name], 0
    je      .uid_num
    mov     rdi, user_name
    call    put_str
    jmp     .end
.uid_num:
    mov     rdi, [cur_uid]
    call    put_num
    jmp     .end

.only_gid:
    cmp     byte [opt_n], 0
    je      .gid_num
    mov     rdi, [cur_gid]
    call    gid_name
    test    rax, rax
    jz      .gid_num
    mov     rdi, rax
    call    put_str
    jmp     .end
.gid_num:
    mov     rdi, [cur_gid]
    call    put_num
    jmp     .end

.only_groups:
    xor     r12, r12
.list_loop:
    cmp     r12, [ngids]
    jae     .end
    test    r12, r12
    jz      .list_put
    write   STDOUT_FILENO, space, 1
.list_put:
    cmp     byte [opt_n], 0
    je      .list_num
    mov     rdi, [gids + r12*8]
    call    gid_name
    test    rax, rax
    jz      .list_num
    mov     rdi, rax
    call    put_str
    jmp     .list_next
.list_num:
    mov     rdi, [gids + r12*8]
    call    put_num
.list_next:
    inc     r12
    jmp     .list_loop
.end:
    write   STDOUT_FILENO, newline, 1
    pop     r12
    ret

; put_uid_named: rdi = uid -> "uid(name)", or just the number when /etc/passwd
; has no entry for it.
put_uid_named:
    push    rdi
    call    put_num
    pop     rdi
    call    uid_name
    test    rax, rax
    jz      .out
    mov     rdi, rax
    call    put_paren
.out:
    ret

; put_gid_named: rdi = gid -> "gid(name)", or just the number.
put_gid_named:
    push    rdi
    call    put_num
    pop     rdi
    call    gid_name
    test    rax, rax
    jz      .out
    mov     rdi, rax
    call    put_paren
.out:
    ret

; put_paren: rdi = NUL-terminated name -> "(name)".
put_paren:
    push    rdi
    write   STDOUT_FILENO, lparen, 1
    pop     rdi
    call    put_str
    write   STDOUT_FILENO, rparen, 1
    ret

; put_num: rdi = value, in decimal.
put_num:
    mov     rax, rdi
    mov     rsi, numbuf + 31
    mov     rcx, 10
.digit:
    xor     rdx, rdx
    div     rcx
    dec     rsi
    add     dl, '0'
    mov     [rsi], dl
    test    rax, rax
    jnz     .digit
    mov     rdx, numbuf + 31
    sub     rdx, rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    ret

; put_str: rdi = NUL-terminated string, to stdout.
put_str:
    mov     rsi, rdi
    call    strlen                      ;rbx = length
    write   STDOUT_FILENO, rsi, rbx
    ret

; err_str: rdi = NUL-terminated string, to stderr.
err_str:
    mov     rsi, rdi
    call    strlen
    write   STDERR_FILENO, rsi, rbx
    ret

; ---------------------------------------------------------------------------
; Group lists
; ---------------------------------------------------------------------------
; collect_own_groups: the effective gid first, then getgroups(2).
collect_own_groups:
    push    r12
    push    r13
    mov     qword [ngids], 0
    mov     rdi, [cur_gid]
    call    add_gid
    mov     rax, SYS_GETGROUPS
    mov     rdi, MAX_GIDS
    mov     rsi, grp_raw
    syscall
    test    rax, rax
    js      .out
    mov     r12, rax
    xor     r13, r13
.loop:
    cmp     r13, r12
    jae     .out
    mov     edi, [grp_raw + r13*4]
    call    add_gid
    inc     r13
    jmp     .loop
.out:
    pop     r13
    pop     r12
    ret

; collect_user_groups: the primary gid first, then every /etc/group entry whose
; member list names user_name.
collect_user_groups:
    push    rbx
    push    r12
    mov     qword [ngids], 0
    mov     rdi, [cur_gid]
    call    add_gid
    xor     r12, r12                    ;line start
.line:
    cmp     r12, [gr_len]
    jae     .out
    mov     rsi, gr_buf
    mov     rdx, [gr_len]
    mov     rdi, r12
    call    line_end
    mov     rbx, rax
    mov     rsi, gr_buf
    mov     rdi, r12
    mov     rdx, rbx
    mov     rcx, 3                      ;the member list
    call    field
    cmp     rax, -1
    je      .next
    mov     rsi, gr_buf
    call    members_have_user
    test    rax, rax
    jz      .next
    mov     rsi, gr_buf
    mov     rdi, r12
    mov     rdx, rbx
    mov     rcx, 2                      ;the gid
    call    field
    cmp     rax, -1
    je      .next
    mov     rsi, gr_buf
    call    range_num
    test    rcx, rcx
    jz      .next
    mov     rdi, rax
    call    add_gid
.next:
    lea     r12, [rbx + 1]
    jmp     .line
.out:
    pop     r12
    pop     rbx
    ret

; add_gid: rdi = gid, appended to gids unless it is already listed.
add_gid:
    xor     rcx, rcx
.scan:
    cmp     rcx, [ngids]
    jae     .append
    cmp     [gids + rcx*8], rdi
    je      .out
    inc     rcx
    jmp     .scan
.append:
    mov     rax, [ngids]
    cmp     rax, MAX_GIDS
    jae     .out
    mov     [gids + rax*8], rdi
    inc     qword [ngids]
.out:
    ret

; members_have_user: rsi = buffer, rax = field start, rdx = field end.
; rax = 1 when the comma-separated member list holds user_name exactly.
members_have_user:
    mov     r8, rax                     ;start of this member
    mov     r9, rax                     ;cursor
.scan:
    cmp     r9, rdx
    jae     .last
    cmp     byte [rsi + r9], ','
    je      .check
    inc     r9
    jmp     .scan
.last:
    cmp     r8, r9
    je      .none                       ;empty list, or a trailing comma
.check:
    xor     r10, r10
.cmp:
    movzx   r11d, byte [user_name + r10]
    test    r11b, r11b
    jz      .name_end
    lea     rcx, [r8 + r10]
    cmp     rcx, r9
    jae     .mismatch
    cmp     r11b, [rsi + rcx]
    jne     .mismatch
    inc     r10
    jmp     .cmp
.name_end:
    lea     rcx, [r8 + r10]
    cmp     rcx, r9
    jne     .mismatch                   ;the member is longer than the name
    mov     rax, 1
    ret
.mismatch:
    cmp     r9, rdx
    jae     .none
    inc     r9                          ;step over the comma
    mov     r8, r9
    jmp     .scan
.none:
    xor     rax, rax
    ret

; ---------------------------------------------------------------------------
; /etc/passwd and /etc/group lookups
; ---------------------------------------------------------------------------
; pw_scan: find one /etc/passwd entry and load it.
;   rdi = 0 to match the name at rsi, 1 to match the uid in rsi
;   rax = 1 when found, with cur_uid, cur_gid and user_name filled in.
pw_scan:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r13, rdi                    ;mode
    mov     r14, rsi                    ;name pointer or uid
    xor     r12, r12                    ;line start
.line:
    cmp     r12, [pw_len]
    jae     .none
    mov     rsi, pw_buf
    mov     rdx, [pw_len]
    mov     rdi, r12
    call    line_end
    mov     rbx, rax
    test    r13, r13
    jnz     .by_id
    mov     rsi, pw_buf
    mov     rdi, r12
    mov     rdx, rbx
    xor     rcx, rcx                    ;the login name
    call    field
    cmp     rax, -1
    je      .next
    mov     rdi, r14
    mov     rsi, pw_buf
    call    range_eq
    test    rax, rax
    jz      .next
    jmp     .found
.by_id:
    mov     rsi, pw_buf
    mov     rdi, r12
    mov     rdx, rbx
    mov     rcx, 2                      ;the uid
    call    field
    cmp     rax, -1
    je      .next
    mov     rsi, pw_buf
    call    range_num
    test    rcx, rcx
    jz      .next
    cmp     rax, r14
    jne     .next
.found:
    mov     rsi, pw_buf
    mov     rdi, r12
    mov     rdx, rbx
    mov     rcx, 2
    call    field
    cmp     rax, -1
    je      .next
    mov     rsi, pw_buf
    call    range_num
    test    rcx, rcx
    jz      .next
    mov     [cur_uid], rax
    mov     rsi, pw_buf
    mov     rdi, r12
    mov     rdx, rbx
    mov     rcx, 3                      ;the primary gid
    call    field
    cmp     rax, -1
    je      .next
    mov     rsi, pw_buf
    call    range_num
    test    rcx, rcx
    jz      .next
    mov     [cur_gid], rax
    mov     rsi, pw_buf
    mov     rdi, r12
    mov     rdx, rbx
    xor     rcx, rcx
    call    field
    mov     rsi, pw_buf
    mov     rdi, user_name
    call    range_copy
    mov     rax, 1
    jmp     .out
.next:
    lea     r12, [rbx + 1]
    jmp     .line
.none:
    xor     rax, rax
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; uid_name: rdi = uid -> rax = name_buf, or 0 when /etc/passwd has no entry.
uid_name:
    mov     rsi, pw_buf
    mov     rdx, [pw_len]
    jmp     id_to_name

; gid_name: rdi = gid -> rax = name_buf, or 0 when /etc/group has no entry.
gid_name:
    mov     rsi, gr_buf
    mov     rdx, [gr_len]

; id_to_name: rdi = id, rsi = table, rdx = table length. Copies the first field
; of the line whose third field is that id into name_buf, and returns it in
; rax; rax = 0 when no line matches. The table itself is left untouched.
id_to_name:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r14, rdi                    ;wanted id
    mov     r12, rsi                    ;table
    mov     r13, rdx                    ;length
    xor     r15, r15                    ;line start
.line:
    cmp     r15, r13
    jae     .none
    mov     rsi, r12
    mov     rdx, r13
    mov     rdi, r15
    call    line_end
    mov     rbx, rax
    mov     rsi, r12
    mov     rdi, r15
    mov     rdx, rbx
    mov     rcx, 2
    call    field
    cmp     rax, -1
    je      .next
    mov     rsi, r12
    call    range_num
    test    rcx, rcx
    jz      .next
    cmp     rax, r14
    jne     .next
    mov     rsi, r12
    mov     rdi, r15
    mov     rdx, rbx
    xor     rcx, rcx
    call    field
    cmp     rax, -1
    je      .next
    mov     rsi, r12
    mov     rdi, name_buf
    call    range_copy
    mov     rax, name_buf
    jmp     .out
.next:
    lea     r15, [rbx + 1]
    jmp     .line
.none:
    xor     rax, rax
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Colon-delimited table helpers. Callers get offsets into the buffer and copy
; out what they need, so a lookup never has to modify the table.
; ---------------------------------------------------------------------------
; line_end: rsi = buffer, rdx = length, rdi = line start -> rax = offset of the
; line's newline, or the buffer length at the end.
line_end:
    mov     rax, rdi
.scan:
    cmp     rax, rdx
    jae     .out
    cmp     byte [rsi + rax], WHITESPACE_NL
    je      .out
    inc     rax
    jmp     .scan
.out:
    ret

; field: rsi = buffer, rdi = line start, rdx = line end, rcx = field index
; -> rax = field start, rdx = field end; rax = -1 when the line is too short.
field:
    mov     r8, rdi
.skip:
    test    rcx, rcx
    jz      .at_field
.to_colon:
    cmp     r8, rdx
    jae     .none
cmp     byte [rsi + r8], ':'
    je      .past_colon
    inc     r8
    jmp     .to_colon
.past_colon:
    inc     r8
    dec     rcx
    jmp     .skip
.at_field:
    mov     rax, r8
.to_end:
    cmp     r8, rdx
    jae     .out
cmp     byte [rsi + r8], ':'
    je      .out
    inc     r8
    jmp     .to_end
.out:
    mov     rdx, r8
    ret
.none:
    mov     rax, -1
    ret

; range_eq: rdi = NUL-terminated string, rsi = buffer, rax = start, rdx = end
; -> rax = 1 when the string matches the range exactly.
range_eq:
    mov     r8, rax
    xor     rcx, rcx
.cmp:
    movzx   r9d, byte [rdi + rcx]
    test    r9b, r9b
    jz      .end
    lea     rax, [r8 + rcx]
    cmp     rax, rdx
    jae     .no
    cmp     r9b, [rsi + rax]
    jne     .no
    inc     rcx
    jmp     .cmp
.end:
    lea     rax, [r8 + rcx]
    cmp     rax, rdx
    jne     .no
    mov     rax, 1
    ret
.no:
    xor     rax, rax
    ret

; range_num: rsi = buffer, rax = start, rdx = end -> rax = value, rcx = number
; of digits consumed (0 when the range does not start with a digit).
range_num:
    mov     r8, rax
    xor     rax, rax
    xor     rcx, rcx
.digit:
    cmp     r8, rdx
    jae     .out
    movzx   r9d, byte [rsi + r8]
    sub     r9b, '0'
    cmp     r9b, 9
    ja      .out
    imul    rax, rax, 10
    movzx   r9, r9b
    add     rax, r9
    inc     rcx
    inc     r8
    jmp     .digit
.out:
    ret

; range_copy: rsi = buffer, rax = start, rdx = end, rdi = destination.
; Copies at most NAME_CAP-1 bytes and NUL-terminates.
range_copy:
    mov     r8, rax
    xor     rcx, rcx
.copy:
    cmp     r8, rdx
    jae     .out
    cmp     rcx, NAME_CAP - 1
    jae     .out
    mov     al, [rsi + r8]
    mov     [rdi + rcx], al
    inc     r8
    inc     rcx
    jmp     .copy
.out:
    mov     byte [rdi + rcx], 0
    ret

; parse_id: rdi = NUL-terminated string -> rax = value, rdx = 1 when the whole
; string is a decimal id that fits in 32 bits, 0 otherwise.
parse_id:
    xor     rax, rax
    xor     rcx, rcx
    mov     r9, 0xffffffff              ;ids are 32 bits wide
.digit:
    movzx   r8d, byte [rdi]
    test    r8b, r8b
    jz      .end
    sub     r8b, '0'
    cmp     r8b, 9
    ja      .bad
    imul    rax, rax, 10
    movzx   r8, r8b
    add     rax, r8
    cmp     rax, r9
    ja      .bad
    inc     rcx
    inc     rdi
    jmp     .digit
.end:
    test    rcx, rcx
    jz      .bad
    mov     rdx, 1
    ret
.bad:
    xor     rax, rax
    xor     rdx, rdx
    ret

; strcpy_c: rsi -> rdi, NUL-terminated.
strcpy_c:
    xor     rax, rax
.copy:
    mov     cl, [rsi + rax]
    mov     [rdi + rax], cl
    test    cl, cl
    jz      .out
    inc     rax
    jmp     .copy
.out:
    ret

; slurp: rdi = path, rsi = buffer, rdx = capacity -> rax = bytes read, 0 when
; the file cannot be opened.
slurp:
    push    r12
    push    r13
    mov     r12, rsi                    ;buffer
    mov     r13, rdx                    ;capacity; syscalls clobber rcx and r11
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .none
    mov     r8, rax                     ;fd
    xor     r9, r9                      ;bytes so far
.read:
    mov     rdx, r13
    sub     rdx, r9
    jle     .close
    mov     rax, SYS_READ
    mov     rdi, r8
    lea     rsi, [r12 + r9]
    syscall
    test    rax, rax
    jle     .close
    add     r9, rax
    jmp     .read
.close:
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    mov     rax, r9
    jmp     .out
.none:
    xor     rax, rax
.out:
    pop     r13
    pop     r12
    ret
