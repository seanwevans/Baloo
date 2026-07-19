; src/chmod.asm -- chmod(1): change file modes.
; Supports octal and symbolic modes ([ugoa][+-=][rwxXst]...), -R (recursive),
; and -c/-v (report changes), -f (silent).

    %include "include/sysdefs.inc"

    %define SYS_LSTAT 6
    %define SYS_FSTAT 5
    %define SYS_GETDENTS64 217
    %define S_IFMT 0o170000
    %define S_IFDIR 0o040000
    %define S_IFLNK 0o120000
    %define O_DIRECTORY 0o200000

section .bss
    statbuf     resb 160
    pathbuf     resb 4096
    umask_val   resq 1
    mode_str    resq 1                  ;pointer to the mode argument
    r_flag      resb 1
    c_flag      resb 1
    v_flag      resb 1
    f_flag      resb 1
    exit_status resq 1
    octbuf      resb 8
    symbuf      resb 16

section .data
usage_msg   db "Usage: chmod [-Rcvf] MODE FILE...", WHITESPACE_NL
    usage_len   equ $ - usage_msg
err_msg     db "chmod: cannot access file", WHITESPACE_NL
    err_len     equ $ - err_msg
    m_mode_of   db "mode of '"
    m_mode_of_len equ $ - m_mode_of
    m_changed   db "' changed from "
    m_changed_len equ $ - m_changed
    m_retained  db "' retained as "
    m_retained_len equ $ - m_retained
    m_to        db " to "
    m_to_len    equ $ - m_to
    m_lp        db " ("
    m_lp_len    equ $ - m_lp
    m_rp        db ")"
    m_rp_len    equ $ - m_rp
    m_nl        db WHITESPACE_NL

section .text
global      _start

_start:
    mov     byte [r_flag], 0
    mov     byte [c_flag], 0
    mov     byte [v_flag], 0
    mov     byte [f_flag], 0
    mov     qword [mode_str], 0
    mov     qword [exit_status], 0

;read the umask without changing it
    mov     rax, SYS_UMASK
    xor     rdi, rdi
    syscall
    mov     [umask_val], rax
    mov     rdi, rax
    mov     rax, SYS_UMASK
    syscall

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

opt_loop:
    cmp     r12, 0
    je      usage_error
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     got_mode
;a "-" followed by an operator char is a symbolic mode, not an option
    movzx   eax, byte [rdi + 1]
    cmp     al, 'r'
    je      got_mode
    cmp     al, 'w'
    je      got_mode
    cmp     al, 'x'
    je      got_mode
    cmp     al, 0
    je      got_mode
    inc     rdi
.char:
    movzx   eax, byte [rdi]
    test    al, al
    je      .next
    cmp     al, 'R'
    je      .set_r
    cmp     al, 'c'
    je      .set_c
    cmp     al, 'v'
    je      .set_v
    cmp     al, 'f'
    je      .set_f
    inc     rdi                         ;ignore unknown option letters
    jmp     .char
.set_r:
    mov     byte [r_flag], 1
    inc     rdi
    jmp     .char
.set_c:
    mov     byte [c_flag], 1
    inc     rdi
    jmp     .char
.set_v:
    mov     byte [v_flag], 1
    inc     rdi
    jmp     .char
.set_f:
    mov     byte [f_flag], 1
    inc     rdi
    jmp     .char
.next:
    add     r13, 8
    dec     r12
    jmp     opt_loop

got_mode:
    mov     rax, [r13]
    mov     [mode_str], rax
    add     r13, 8
    dec     r12
    cmp     r12, 0
    je      usage_error

files:
    cmp     r12, 0
    je      done
;copy the file name into pathbuf
    mov     rsi, [r13]
    mov     rdi, pathbuf
    xor     rcx, rcx
.cpy:
    mov     al, [rsi + rcx]
    mov     [rdi + rcx], al
    test    al, al
    je      .cpydone
    inc     rcx
    jmp     .cpy
.cpydone:
    mov     rdi, rcx                    ;path length
    mov     rsi, 1                      ;top-level operand
    call    do_one
    add     r13, 8
    dec     r12
    jmp     files

done:
    mov     rdi, [exit_status]
    mov     rax, SYS_EXIT
    syscall

usage_error:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

; do_one: pathbuf holds a NUL-terminated path of length rdi; rsi = 1 if this
; is a top-level operand (0 during recursion, when symlinks are skipped).
do_one:
    push    rbp
    push    rbx
    push    r14
    push    r15
    mov     rbp, rdi                    ;path length
    mov     r15, rsi                    ;top-level flag

;during recursion skip symlink entries
    test    r15, r15
    jnz     .stat
    mov     rax, SYS_LSTAT
    mov     rdi, pathbuf
    mov     rsi, statbuf
    syscall
    test    rax, rax
    js      .ret
    mov     eax, [statbuf + 24]
    and     eax, S_IFMT
    cmp     eax, S_IFLNK
    je      .ret                        ;skip symlinks in recursion
.stat:
    mov     rax, SYS_STAT
    mov     rdi, pathbuf
    mov     rsi, statbuf
    syscall
    test    rax, rax
    js      .stat_fail

    mov     r14d, [statbuf + 24]        ;full st_mode
    mov     ebx, r14d
    and     ebx, 0o7777                 ;old permission bits
;isdir?
    mov     eax, r14d
    and     eax, S_IFMT
    cmp     eax, S_IFDIR
    sete    al
    movzx   rsi, al                     ;isdir flag
    mov     rdi, rbx                    ;old mode
    call    compute_mode                ;rax = new mode
    mov     r14, rax                    ;new mode

    cmp     r14, rbx
    je      .unchanged
;apply the change
    mov     rax, SYS_CHMOD
    mov     rdi, pathbuf
    mov     rsi, r14
    syscall
    test    rax, rax
    js      .stat_fail
    cmp     byte [c_flag], 1
    je      .report_changed
    cmp     byte [v_flag], 1
    je      .report_changed
    jmp     .maybe_recurse
.report_changed:
    mov     rdi, rbx                    ;old bits
    mov     rsi, r14                    ;new bits
    call    report_changed
    jmp     .maybe_recurse
.unchanged:
    cmp     byte [v_flag], 1
    jne     .maybe_recurse
    mov     rdi, rbx
    call    report_retained

.maybe_recurse:
    cmp     byte [r_flag], 1
    jne     .ret
    mov     eax, [statbuf + 24]
    and     eax, S_IFMT
    cmp     eax, S_IFDIR
    jne     .ret
    call    recurse_dir
.ret:
    pop     r15
    pop     r14
    pop     rbx
    pop     rbp
    ret
.stat_fail:
    mov     qword [exit_status], 1
    cmp     byte [f_flag], 1
    je      .ret
    write   STDERR_FILENO, err_msg, err_len
    jmp     .ret

; recurse_dir: pathbuf (length rbp) is a directory; chmod its entries.
recurse_dir:
    push    rbp
    push    rbx
    push    r14
    push    r15
    sub     rsp, 32768                  ;getdents buffer on the stack
    mov     r14, rsp                    ;buffer base

    mov     rax, SYS_OPEN
    mov     rdi, pathbuf
    mov     rsi, O_RDONLY | O_DIRECTORY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .done
    mov     r15, rax                    ;dir fd
.read:
    mov     rax, SYS_GETDENTS64
    mov     rdi, r15
    mov     rsi, r14
    mov     rdx, 32768
    syscall
    test    rax, rax
    jle     .close
    mov     rbx, rax                    ;bytes in this batch
    xor     r13, r13                    ;offset in batch
.entry:
    cmp     r13, rbx
    jge     .read
    lea     rcx, [r14 + r13]            ;current dirent
    movzx   rax, word [rcx + 16]        ;d_reclen
    lea     rsi, [rcx + 19]             ;d_name
;skip "." and ".."
    cmp     byte [rsi], '.'
    jne     .use
    cmp     byte [rsi + 1], 0
    je      .skip
    cmp     byte [rsi + 1], '.'
    jne     .use
    cmp     byte [rsi + 2], 0
    je      .skip
.use:
;append "/name" to pathbuf at [rbp]
    push    rax
    push    rcx
    push    rsi
    mov     rdi, rbp                    ;current length
    mov     byte [pathbuf + rdi], '/'
    inc     rdi
.append:
    mov     al, [rsi]
    mov     [pathbuf + rdi], al
    test    al, al
    je      .appended
    inc     rdi
    inc     rsi
    jmp     .append
.appended:
;rdi now indexes the NUL; length = rdi
    mov     rsi, 0                      ;not top-level
    call    do_one
    pop     rsi
    pop     rcx
    pop     rax
;restore pathbuf terminator at rbp
    mov     byte [pathbuf + rbp], 0
.skip:
    add     r13, rax
    jmp     .entry
.close:
    mov     rax, SYS_CLOSE
    mov     rdi, r15
    syscall
.done:
    add     rsp, 32768
    pop     r15
    pop     r14
    pop     rbx
    pop     rbp
    ret

; compute_mode: rdi = old mode (0..07777), rsi = isdir; rax = new mode.
compute_mode:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15, rdi                    ;result (running mode)
    mov     r14, rdi                    ;original mode (for X)
    mov     r13, rsi                    ;isdir
    mov     rbx, [mode_str]

;octal mode?
    movzx   eax, byte [rbx]
    cmp     al, '0'
    jb      .symbolic
    cmp     al, '7'
    ja      .symbolic
    xor     r15, r15
.oct:
    movzx   eax, byte [rbx]
    cmp     al, '0'
    jb      .done
    cmp     al, '7'
    ja      .done
    sub     al, '0'
    shl     r15, 3
    or      r15b, al
    inc     rbx
    jmp     .oct

.symbolic:
.clause:
    cmp     byte [rbx], 0
    je      .done
;parse the who list
    xor     r12, r12                    ;who_mask
    xor     r10, r10                    ;who specified?
.who:
    movzx   eax, byte [rbx]
    cmp     al, 'u'
    je      .who_u
    cmp     al, 'g'
    je      .who_g
    cmp     al, 'o'
    je      .who_o
    cmp     al, 'a'
    je      .who_a
    jmp     .who_done
.who_u:
    or      r12, 0o4700
    mov     r10, 1
    inc     rbx
    jmp     .who
.who_g:
    or      r12, 0o2070
    mov     r10, 1
    inc     rbx
    jmp     .who
.who_o:
    or      r12, 0o1007
    mov     r10, 1
    inc     rbx
    jmp     .who
.who_a:
    or      r12, 0o7777
    mov     r10, 1
    inc     rbx
    jmp     .who
.who_done:
    test    r10, r10
    jnz     .ops
    mov     r12, 0o7777                 ;no who -> all (umask applied later)
.ops:
;expect an operator; if none, clause is done
    movzx   eax, byte [rbx]
    cmp     al, '+'
    je      .op
    cmp     al, '-'
    je      .op
    cmp     al, '='
    je      .op
;end of clause
    cmp     al, ','
    jne     .done_clause
    inc     rbx
    jmp     .clause
.op:
    mov     r11b, al                    ;operator
    inc     rbx
    xor     r9, r9                      ;perm value
.perm:
    movzx   eax, byte [rbx]
    cmp     al, 'r'
    je      .p_r
    cmp     al, 'w'
    je      .p_w
    cmp     al, 'x'
    je      .p_x
    cmp     al, 'X'
    je      .p_X
    cmp     al, 's'
    je      .p_s
    cmp     al, 't'
    je      .p_t
    jmp     .apply
.p_r:
    or      r9, 0o444
    inc     rbx
    jmp     .perm
.p_w:
    or      r9, 0o222
    inc     rbx
    jmp     .perm
.p_x:
    or      r9, 0o111
    inc     rbx
    jmp     .perm
.p_X:
    test    r13, r13
    jnz     .p_X_yes
    mov     rax, r14
    and     rax, 0o111
    jz      .p_X_skip
.p_X_yes:
    or      r9, 0o111
.p_X_skip:
    inc     rbx
    jmp     .perm
.p_s:
    or      r9, 0o6000
    inc     rbx
    jmp     .perm
.p_t:
    or      r9, 0o1000
    inc     rbx
    jmp     .perm
.apply:
    and     r9, r12                     ;restrict to the affected categories
;apply umask only for + and = when no who was given
    test    r10, r10
    jnz     .no_umask
    cmp     r11b, '-'
    je      .no_umask
    mov     rax, [umask_val]
    not     rax
    and     r9, rax
.no_umask:
    cmp     r11b, '+'
    je      .do_plus
    cmp     r11b, '-'
    je      .do_minus
;'='
    mov     rax, r12
    not     rax
    and     r15, rax
    or      r15, r9
    jmp     .ops
.do_plus:
    or      r15, r9
    jmp     .ops
.do_minus:
    mov     rax, r9
    not     rax
    and     r15, rax
    jmp     .ops
.done_clause:
.done:
    mov     rax, r15
    and     rax, 0o7777
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; report_changed: rdi = old bits, rsi = new bits; print the change line.
report_changed:
    push    rdi
    push    rsi
    write   STDOUT_FILENO, m_mode_of, m_mode_of_len
    mov     rsi, pathbuf
    call    strlen
    write   STDOUT_FILENO, pathbuf, rbx
    write   STDOUT_FILENO, m_changed, m_changed_len
    mov     rdi, [rsp + 8]              ;old
    call    print_mode
    write   STDOUT_FILENO, m_to, m_to_len
    mov     rdi, [rsp]                  ;new
    call    print_mode
    write   STDOUT_FILENO, m_nl, 1
    add     rsp, 16
    ret

; report_retained: rdi = mode bits; print "mode of 'PATH' retained as ...".
report_retained:
    push    rdi
    write   STDOUT_FILENO, m_mode_of, m_mode_of_len
    mov     rsi, pathbuf
    call    strlen
    write   STDOUT_FILENO, pathbuf, rbx
    write   STDOUT_FILENO, m_retained, m_retained_len
    pop     rdi
    call    print_mode
    write   STDOUT_FILENO, m_nl, 1
    ret

; print_mode: rdi = permission bits; print "OOOO (rwxrwxrwx)" fragment as
; "0OOO (SYM)" without the surrounding text.
print_mode:
    push    rdi
;octal: 4 digits
    mov     rax, rdi
    mov     rcx, 3
.od:
    mov     rdx, rax
    and     rdx, 7
    add     dl, '0'
    mov     [octbuf + rcx], dl
    shr     rax, 3
    dec     rcx
    jns     .od
    write   STDOUT_FILENO, octbuf, 4
    write   STDOUT_FILENO, m_lp, m_lp_len
    pop     rdi
    call    build_sym
    write   STDOUT_FILENO, symbuf, 9
    write   STDOUT_FILENO, m_rp, m_rp_len
    ret

; build_sym: rdi = permission bits -> symbuf holds 9 chars rwxrwxrwx (with
; s/S/t/T for the special bits).
build_sym:
    mov     r8, rdi
;owner
    mov     rax, r8
    shr     rax, 6
    and     rax, 7
    mov     rcx, 0                      ;base index
    call    .triad
;group
    mov     rax, r8
    shr     rax, 3
    and     rax, 7
    mov     rcx, 3
    call    .triad
;other
    mov     rax, r8
    and     rax, 7
    mov     rcx, 6
    call    .triad
;special bits: setuid -> owner x pos (2), setgid -> group x (5), sticky -> other x (8)
    test    r8, 0o4000
    jz      .no_suid
    mov     al, [symbuf + 2]
    cmp     al, 'x'
    mov     al, 'S'
    je      .suid_lower
    mov     byte [symbuf + 2], 'S'
    jmp     .no_suid
.suid_lower:
    mov     byte [symbuf + 2], 's'
.no_suid:
    test    r8, 0o2000
    jz      .no_sgid
    mov     al, [symbuf + 5]
    cmp     al, 'x'
    je      .sgid_lower
    mov     byte [symbuf + 5], 'S'
    jmp     .no_sgid
.sgid_lower:
    mov     byte [symbuf + 5], 's'
.no_sgid:
    test    r8, 0o1000
    jz      .no_stk
    mov     al, [symbuf + 8]
    cmp     al, 'x'
    je      .stk_lower
    mov     byte [symbuf + 8], 'T'
    jmp     .no_stk
.stk_lower:
    mov     byte [symbuf + 8], 't'
.no_stk:
    ret
; .triad: rax = 3-bit perm value, rcx = base index in symbuf
.triad:
    test    rax, 4
    jz      .t_nr
    mov     byte [symbuf + rcx], 'r'
    jmp     .t_w
.t_nr:
    mov     byte [symbuf + rcx], '-'
.t_w:
    test    rax, 2
    jz      .t_nw
    mov     byte [symbuf + rcx + 1], 'w'
    jmp     .t_x
.t_nw:
    mov     byte [symbuf + rcx + 1], '-'
.t_x:
    test    rax, 1
    jz      .t_nx
    mov     byte [symbuf + rcx + 2], 'x'
    ret
.t_nx:
    mov     byte [symbuf + rcx + 2], '-'
    ret
