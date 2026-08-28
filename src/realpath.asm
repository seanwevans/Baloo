; src/realpath.asm -- realpath(1): print the canonical name of each operand.
; Usage: realpath [-e|-m] [-s] [-L|-P] [-z] [-q]
;                 [--relative-to=DIR] [--relative-base=DIR] FILE...
;
; Resolution walks the operand one component at a time, keeping the part
; resolved so far on one side and the unresolved remainder on the other. ".."
; is applied to the resolved prefix, and a symlink is expanded by splicing its
; target onto the front of the remainder, so a target's own ".." lands where
; the link was. Chains are capped so a loop fails instead of spinning.
;
; The flags change what that walk does:
;   -e  every component must exist       -m  none of them need to
;   (default)                            all but the final one must exist
;   -s  do not resolve symlinks at all -- the result is purely lexical
;   -L  collapse ".." lexically before resolving, so "link/../x" is "x"
;       rather than the parent of whatever link points at
;
; --relative-to prints the result relative to a directory; --relative-base
; does the same but only when the result sits under that directory, and
; otherwise prints the absolute path.

    %include "include/sysdefs.inc"

    %define PATHCAP 4096
    %define RESTCAP 65536
    %define RESTMAX (RESTCAP - 512)
    %define MAXLINKS 40
    %define MAXARGS 256

    %define ST_MODE 24
    %define S_IFMT 0o170000
    %define S_IFDIR 0o040000

    %define ENOTDIR 20
    %define ELOOP 40

section .bss
    outbuf      resb PATHCAP
    resbuf      resb PATHCAP
    relbuf      resb PATHCAP
    basebuf     resb PATHCAP
    tmpbuf      resb PATHCAP
    relout      resb RESTCAP
    lbuf        resb PATHCAP
    restbuf     resb RESTCAP
    newrest     resb RESTCAP
    msgbuf      resb PATHCAP + 128
    statbuf     resb 160
    args        resq MAXARGS
    nargs       resq 1
    outlen      resq 1
    reslen      resq 1
    rellen      resq 1
    baselen     resq 1
    reloutlen   resq 1
    restptr     resq 1
    copy_end    resq 1
    pathptr     resq 1
    compstart   resq 1
    complen     resq 1
    linkcnt     resq 1
    relto_arg   resq 1
    relbase_arg resq 1
    fail_errno  resq 1
    failing_arg resq 1
    mode        resb 1                  ;0 default, 'e' or 'm'
    opt_s       resb 1
    opt_L       resb 1
    opt_z       resb 1
    c_nosym     resb 1
    c_nocheck   resb 1
    is_last     resb 1
    status      resb 1

section .data
    l_relto     db "--relative-to", 0
    l_relbase   db "--relative-base", 0
    l_strip     db "--strip", 0
    l_nosym     db "--no-symlinks", 0
    l_exist     db "--canonicalize-existing", 0
    l_missing   db "--canonicalize-missing", 0
    l_logical   db "--logical", 0
    l_physical  db "--physical", 0
    l_zero      db "--zero", 0
    l_quiet     db "--quiet", 0

usage_msg   db "Usage: realpath [-emsLPzq] [--relative-to=DIR] "
    db "[--relative-base=DIR] FILE...", 10
    usage_len   equ $ - usage_msg
pfx_msg     db "realpath: "
    pfx_len     equ $ - pfx_msg
e_noent     db ": No such file or directory", 10, 0
e_notdir    db ": Not a directory", 10, 0
e_loop      db ": Too many levels of symbolic links", 10, 0
e_other     db ": cannot resolve", 10, 0
    newline     db WHITESPACE_NL
    nulbyte     db 0

section .text
global _start

_start:
    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    jle     run
    mov     rdi, [r13]
    test    rdi, rdi
    jz      run
    cmp     byte [rdi], '-'
    jne     .operand
    cmp     byte [rdi + 1], 0
    je      .operand                    ;lone "-" is an operand
    cmp     byte [rdi + 1], '-'
    jne     .short
    cmp     byte [rdi + 2], 0
    jne     .long
    add     r13, 8                      ;"--" ends the options
    dec     r12
    jmp     .tail

.long:
    mov     rsi, l_relto
    call    longmatch
    test    al, al
    jnz     .set_relto
    mov     rsi, l_relbase
    call    longmatch
    test    al, al
    jnz     .set_relbase
    mov     rsi, l_strip
    call    longmatch
    test    al, al
    jnz     .set_s
    mov     rsi, l_nosym
    call    longmatch
    test    al, al
    jnz     .set_s
    mov     rsi, l_exist
    call    longmatch
    test    al, al
    jnz     .set_e
    mov     rsi, l_missing
    call    longmatch
    test    al, al
    jnz     .set_m
    mov     rsi, l_logical
    call    longmatch
    test    al, al
    jnz     .set_L
    mov     rsi, l_physical
    call    longmatch
    test    al, al
    jnz     .set_P
    mov     rsi, l_zero
    call    longmatch
    test    al, al
    jnz     .set_z
    mov     rsi, l_quiet
    call    longmatch
    test    al, al
    jnz     .next
    jmp     usage

.set_relto:
    cmp     al, 2
    je      .relto_inline
    add     r13, 8                      ;value is the next argument
    dec     r12
    mov     rdx, [r13]
    test    rdx, rdx
    jz      usage
.relto_inline:
    mov     [relto_arg], rdx
    jmp     .next
.set_relbase:
    cmp     al, 2
    je      .relbase_inline
    add     r13, 8
    dec     r12
    mov     rdx, [r13]
    test    rdx, rdx
    jz      usage
.relbase_inline:
    mov     [relbase_arg], rdx
    jmp     .next
.set_s:
    mov     byte [opt_s], 1
    jmp     .next
.set_e:
    mov     byte [mode], 'e'
    jmp     .next
.set_m:
    mov     byte [mode], 'm'
    jmp     .next
.set_L:
    mov     byte [opt_L], 1
    jmp     .next
.set_P:
    mov     byte [opt_L], 0
    jmp     .next
.set_z:
    mov     byte [opt_z], 1
    jmp     .next

.short:
    lea     rsi, [rdi + 1]
.flag:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .next
    inc     rsi
    cmp     al, 'e'
    je      .f_e
    cmp     al, 'm'
    je      .f_m
    cmp     al, 's'
    je      .f_s
    cmp     al, 'L'
    je      .f_L
    cmp     al, 'P'
    je      .f_P
    cmp     al, 'z'
    je      .f_z
    cmp     al, 'q'
    je      .flag
    jmp     usage
.f_e:
    mov     byte [mode], 'e'
    jmp     .flag
.f_m:
    mov     byte [mode], 'm'
    jmp     .flag
.f_s:
    mov     byte [opt_s], 1
    jmp     .flag
.f_L:
    mov     byte [opt_L], 1
    jmp     .flag
.f_P:
    mov     byte [opt_L], 0
    jmp     .flag
.f_z:
    mov     byte [opt_z], 1
    jmp     .flag

.operand:
    call    add_arg
.next:
    add     r13, 8
    dec     r12
    jmp     parse
.tail:
    cmp     r12, 0
    jle     run
    mov     rdi, [r13]
    test    rdi, rdi
    jz      run
    call    add_arg
    add     r13, 8
    dec     r12
    jmp     .tail

run:
    cmp     qword [nargs], 0
    je      usage
    mov     rdi, [relto_arg]
    test    rdi, rdi
    jz      .base
    mov     [failing_arg], rdi
    call    resolve
    test    al, al
    jz      .refail
    mov     rsi, outbuf
    mov     rdi, relbuf
    call    copy_path
    mov     rax, [outlen]
    mov     [rellen], rax
.base:
    mov     rdi, [relbase_arg]
    test    rdi, rdi
    jz      .each
    mov     [failing_arg], rdi
    call    resolve
    test    al, al
    jz      .refail
    mov     rsi, outbuf
    mov     rdi, basebuf
    call    copy_path
    mov     rax, [outlen]
    mov     [baselen], rax
.each:
    xor     rbx, rbx
.loop:
    cmp     rbx, [nargs]
    jge     .done
    mov     rdi, [args + rbx * 8]
    call    resolve
    test    al, al
    jz      .failed
    mov     rsi, outbuf
    mov     rdi, resbuf
    call    copy_path
    mov     rax, [outlen]
    mov     [reslen], rax
    call    present
    jmp     .next
.failed:
    mov     byte [status], 1
    mov     rdi, [args + rbx * 8]
    call    warn
.next:
    inc     rbx
    jmp     .loop
.done:
    movzx   edi, byte [status]
    mov     rax, SYS_EXIT
    syscall
.refail:
    mov     rdi, [failing_arg]
    call    warn
    exit    1

usage:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, usage_msg
    mov     rdx, usage_len
    syscall
    exit    1

; add_arg: remember the operand in rdi.
add_arg:
    mov     rcx, [nargs]
    cmp     rcx, MAXARGS
    jae     .out
    mov     [args + rcx * 8], rdi
    inc     rcx
    mov     [nargs], rcx
.out:
    ret

; longmatch: does rdi equal the option name at rsi, or start with "NAME="?
; al = 1 for a bare match (value is the next argument), 2 when rdx points at
; an inline value, 0 for no match.
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

; ---------------------------------------------------------------------------
; resolve: canonicalize the path in rdi into outbuf according to the flags.
; -s stays lexical; -L collapses ".." lexically first and then resolves what
; is left, which is what makes "link/../x" mean "x".
; ---------------------------------------------------------------------------
resolve:
    cmp     byte [opt_s], 0
    je      .physical
    mov     byte [c_nosym], 1
    mov     byte [c_nocheck], 0
    jmp     canon
.physical:
    cmp     byte [opt_L], 0
    je      .direct
    mov     byte [c_nosym], 1
mov     byte [c_nocheck], 1         ;lexical pass: collapse ".." only
    call    canon
    test    al, al
    jz      .out
    mov     rsi, outbuf
    mov     rdi, tmpbuf
    call    copy_path
    mov     rdi, tmpbuf
.direct:
    mov     byte [c_nosym], 0
    mov     byte [c_nocheck], 0
    jmp     canon
.out:
    ret

; ---------------------------------------------------------------------------
; present: print the resolved operand, relative to --relative-to when it was
; asked for and --relative-base does not veto it.
; ---------------------------------------------------------------------------
present:
    cmp     qword [baselen], 0
    je      .relto
    mov     rsi, resbuf
    mov     rdi, basebuf
    call    under
    test    al, al
jz      .absolute                   ;outside the base: print it in full
.relto:
    cmp     qword [rellen], 0
    jne     .against_relto
    cmp     qword [baselen], 0
    je      .absolute
    mov     rsi, resbuf
    mov     rdi, basebuf
    jmp     .relative
.against_relto:
    mov     rsi, resbuf
    mov     rdi, relbuf
.relative:
    call    relpath
    mov     rsi, relout
    mov     rdx, [reloutlen]
    jmp     .write
.absolute:
    mov     rsi, resbuf
    mov     rdx, [reslen]
.write:
    push    rbx
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    mov     rsi, newline
    cmp     byte [opt_z], 0
    je      .term
    mov     rsi, nulbyte
.term:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rdx, 1
    syscall
    pop     rbx
    ret

; under: is the path at rsi the directory at rdi, or inside it? al = 1/0.
under:
    push    rsi
    push    rdi
    xor     rcx, rcx
.scan:
    mov     al, [rdi + rcx]
    test    al, al
    jz      .end
    cmp     al, [rsi + rcx]
    jne     .no
    inc     rcx
    jmp     .scan
.end:
    cmp     rcx, 1
    jne     .tail
    cmp     byte [rdi], '/'
    je      .yes                        ;everything is under the root
.tail:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .yes
    cmp     al, '/'
    je      .yes
.no:
    xor     al, al
    jmp     .out
.yes:
    mov     al, 1
.out:
    pop     rdi
    pop     rsi
    ret

; ---------------------------------------------------------------------------
; relpath: express the absolute path at rsi relative to the directory at rdi,
; in relout. The common prefix has to end on a component boundary, so /a/bc
; and /a/bd share only /a.
; ---------------------------------------------------------------------------
relpath:
    push    rbx
    xor     rcx, rcx                    ;index
    xor     r8, r8                      ;last matching '/'
.scan:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .split
    cmp     al, [rdi + rcx]
    jne     .split
    cmp     al, '/'
    jne     .adv
    mov     r8, rcx
.adv:
    inc     rcx
    jmp     .scan
.split:
    mov     al, [rsi + rcx]
    mov     dl, [rdi + rcx]
    test    al, al
    jnz     .abs_more
    test    dl, dl
    jz      .common                     ;identical paths
    cmp     dl, '/'
    je      .common
    jmp     .boundary
.abs_more:
    test    dl, dl
    jnz     .boundary
    cmp     al, '/'
    je      .common
.boundary:
    mov     rcx, r8
.common:
    mov     rbx, relout
; one ".." for each component the base still has past the common prefix
    lea     rdi, [rdi + rcx]
.ups:
    cmp     byte [rdi], '/'
    jne     .upscan
    inc     rdi
    jmp     .ups
.upscan:
    cmp     byte [rdi], 0
    je      .tail
    mov     byte [rbx], '.'
    mov     byte [rbx + 1], '.'
    add     rbx, 2
.upskip:
    mov     al, [rdi]
    test    al, al
    jz      .sep
    cmp     al, '/'
    je      .sep
    inc     rdi
    jmp     .upskip
.sep:
    cmp     byte [rdi], 0
    je      .tail
    mov     byte [rbx], '/'
    inc     rbx
    jmp     .ups
.tail:
    lea     rsi, [rsi + rcx]
.tskip:
    cmp     byte [rsi], '/'
    jne     .tcopy
    inc     rsi
    jmp     .tskip
.tcopy:
    cmp     byte [rsi], 0
    je      .finish
    cmp     rbx, relout
    je      .copy
    mov     byte [rbx], '/'
    inc     rbx
.copy:
    mov     al, [rsi]
    test    al, al
    jz      .finish
    mov     [rbx], al
    inc     rbx
    inc     rsi
    jmp     .copy
.finish:
    cmp     rbx, relout
    jne     .len
    mov     byte [rbx], '.'             ;the path is the base itself
    inc     rbx
.len:
    mov     byte [rbx], 0
    sub     rbx, relout
    mov     [reloutlen], rbx
    pop     rbx
    ret

; warn: report the operand in rdi that could not be resolved.
warn:
    push    rbx
    push    rdi
    mov     rdi, msgbuf
    mov     rsi, pfx_msg
    mov     rcx, pfx_len
    rep     movsb
    pop     rsi
    call    append_str
    mov     rsi, e_other
    cmp     qword [fail_errno], ENOENT
    jne     .notdir
    mov     rsi, e_noent
    jmp     .emit
.notdir:
    cmp     qword [fail_errno], ENOTDIR
    jne     .loop
    mov     rsi, e_notdir
    jmp     .emit
.loop:
    cmp     qword [fail_errno], ELOOP
    jne     .emit
    mov     rsi, e_loop
.emit:
    call    append_str
    mov     rdx, rdi
    mov     rsi, msgbuf
    sub     rdx, rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
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

; copy_path: copy the NUL-terminated path at rsi to rdi.
copy_path:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .out
    inc     rsi
    inc     rdi
    jmp     copy_path
.out:
    ret

; ---------------------------------------------------------------------------
; canon: resolve the path in rdi into outbuf/outlen. al = 1 on success, and
; fail_errno carries why not. c_nosym leaves symlinks alone; c_nocheck skips
; every existence test.
; ---------------------------------------------------------------------------
canon:
    mov     [pathptr], rdi
    mov     qword [linkcnt], 0
    mov     qword [outlen], 0
    mov     byte [outbuf], 0
    mov     qword [fail_errno], 0
    cmp     byte [rdi], '/'
    je      .fromroot
    mov     rax, SYS_GETCWD
    mov     rdi, outbuf
    mov     rsi, PATHCAP
    syscall
    test    rax, rax
    js      .fail
    dec     rax                         ;getcwd counts the terminator
    mov     [outlen], rax
    cmp     rax, 1
    jne     .seed
    cmp     byte [outbuf], '/'
    jne     .seed
    mov     qword [outlen], 0           ;"/" is the empty prefix here
    mov     byte [outbuf], 0
    jmp     .seed
.fromroot:
    mov     qword [outlen], 0
.seed:
    mov     rsi, [pathptr]
    mov     rdi, restbuf
    mov     qword [copy_end], restbuf + RESTMAX
    call    copy_bounded
    test    al, al
    jz      .fail
    mov     qword [restptr], restbuf

.walk:
    mov     rsi, [restptr]
.skip:
    cmp     byte [rsi], '/'
    jne     .start
    inc     rsi
    jmp     .skip
.start:
    cmp     byte [rsi], 0
    je      .finish
    mov     rdi, rsi
.scan:
    mov     al, [rdi]
    test    al, al
    jz      .component
    cmp     al, '/'
    je      .component
    inc     rdi
    jmp     .scan
.component:
    mov     [compstart], rsi
    mov     rcx, rdi
    sub     rcx, rsi
    mov     [complen], rcx
    mov     [restptr], rdi
    cmp     rcx, 1
    jne     .dotdot
    cmp     byte [rsi], '.'
    je      .walk                       ;"." resolves to nothing
.dotdot:
    cmp     rcx, 2
    jne     .append
    cmp     byte [rsi], '.'
    jne     .append
    cmp     byte [rsi + 1], '.'
    jne     .append
    call    strip_last
    jmp     .walk
.append:
    mov     rsi, [restptr]
    call    only_slashes
    mov     [is_last], al
    mov     rax, [outlen]
    add     rax, [complen]
    add     rax, 2
    cmp     rax, PATHCAP
    jae     .fail
    mov     rdi, outbuf
    add     rdi, [outlen]
    mov     byte [rdi], '/'
    inc     rdi
    mov     rsi, [compstart]
    mov     rcx, [complen]
    rep     movsb
    mov     byte [rdi], 0
    mov     rax, rdi
    sub     rax, outbuf
    mov     [outlen], rax
    cmp     byte [c_nosym], 0
    jne     .plain
    mov     rax, SYS_READLINK
    mov     rdi, outbuf
    mov     rsi, lbuf
    mov     rdx, PATHCAP - 1
    syscall
    test    rax, rax
    js      .plain
    mov     byte [lbuf + rax], 0
    inc     qword [linkcnt]
    cmp     qword [linkcnt], MAXLINKS
    jbe     .splice
    mov     qword [fail_errno], ELOOP
    jmp     .fail
.splice:
    mov     rdi, newrest
    mov     rsi, lbuf
    mov     qword [copy_end], newrest + RESTMAX
    call    copy_bounded
    test    al, al
    jz      .fail
    mov     byte [rdi], '/'
    inc     rdi
    mov     rsi, [restptr]
    call    copy_bounded
    test    al, al
    jz      .fail
    mov     rsi, newrest
    mov     rdi, restbuf
    mov     qword [copy_end], restbuf + RESTMAX
    call    copy_bounded
    test    al, al
    jz      .fail
    mov     qword [restptr], restbuf
    call    strip_last                  ;drop the symlink's own name
    cmp     byte [lbuf], '/'
    jne     .walk
    mov     qword [outlen], 0           ;an absolute target restarts at root
    mov     byte [outbuf], 0
    jmp     .walk
.plain:
    cmp     byte [c_nocheck], 0
    jne     .walk
    cmp     byte [mode], 'm'
    je      .walk
    cmp     byte [is_last], 0
    jne     .final
    mov     rax, SYS_STAT
    mov     rdi, outbuf
    mov     rsi, statbuf
    syscall
    test    rax, rax
    js      .statfail
    mov     eax, [statbuf + ST_MODE]
    and     eax, S_IFMT
    cmp     eax, S_IFDIR
    je      .walk
    mov     qword [fail_errno], ENOTDIR ;something non-directory mid-path
    jmp     .fail
.final:
    cmp     byte [mode], 'e'
    jne     .walk                       ;the last component may be missing
    mov     rax, SYS_STAT
    mov     rdi, outbuf
    mov     rsi, statbuf
    syscall
    test    rax, rax
    js      .statfail
    jmp     .walk
.statfail:
    neg     rax
    mov     [fail_errno], rax
    jmp     .fail
.finish:
    cmp     qword [outlen], 0
    jne     .ok
    mov     byte [outbuf], '/'
    mov     byte [outbuf + 1], 0
    mov     qword [outlen], 1
.ok:
    mov     al, 1
    ret
.fail:
    xor     al, al
    ret

; strip_last: cut the final component off outbuf, stopping at the root.
strip_last:
    mov     rcx, [outlen]
    test    rcx, rcx
    jz      .out
.scan:
    dec     rcx
    cmp     byte [outbuf + rcx], '/'
    je      .cut
    test    rcx, rcx
    jnz     .scan
.cut:
    mov     [outlen], rcx
    mov     byte [outbuf + rcx], 0
.out:
    ret

; only_slashes: al = 1 when nothing but '/' remains at rsi.
only_slashes:
    push    rsi
.scan:
    mov     al, [rsi]
    test    al, al
    jz      .yes
    cmp     al, '/'
    jne     .no
    inc     rsi
    jmp     .scan
.yes:
    mov     al, 1
    jmp     .out
.no:
    xor     al, al
.out:
    pop     rsi
    ret

; copy_bounded: copy the string at rsi to rdi, leaving rdi on the terminator.
; The caller sets copy_end to the last writable byte; al = 0 when the copy
; would have run past it, so an oversized splice fails the operand instead of
; walking off the buffer.
copy_bounded:
.copy:
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     rdi, [copy_end]
    jae     .full
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     .copy
.done:
    mov     byte [rdi], 0
    mov     al, 1
    ret
.full:
    mov     byte [rdi], 0
    xor     al, al
    ret
