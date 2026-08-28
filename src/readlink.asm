; src/readlink.asm -- readlink(1): print a symlink target, or a resolved path.
; Usage: readlink [-f|-e|-m] [-n] [-z] [-q|-s|-v] FILE...
;
; With no mode flag each operand is a single readlink(2) and the raw target is
; printed unchanged, trailing slashes and all. -f/-e/-m instead canonicalize
; the operand: every component is resolved, ".." is applied to what has been
; resolved so far, and symlinks are expanded by pushing their target back onto
; the unresolved remainder. The modes differ only in what has to exist -- -e
; needs the whole path, -f allows the final component to be missing, and -m
; requires nothing. Chains are capped so a symlink loop fails instead of
; spinning.
;
; Errors are silent, as they are for readlink; failure only shows in the exit
; status. -n drops the terminator after the last operand and -z makes that
; terminator NUL.

    %include "include/sysdefs.inc"

    %define PATHCAP 4096
    %define RESTCAP 65536
    %define RESTMAX (RESTCAP - 512)
    %define MAXLINKS 40
    %define MAXARGS 256

    %define ST_MODE 24
    %define S_IFMT 0o170000
    %define S_IFDIR 0o040000

section .bss
    outbuf      resb PATHCAP
    lbuf        resb PATHCAP
    restbuf     resb RESTCAP
    newrest     resb RESTCAP
    statbuf     resb 160
    args        resq MAXARGS
    nargs       resq 1
    outlen      resq 1
    restptr     resq 1
    copy_end    resq 1
    pathptr     resq 1
    compstart   resq 1
    complen     resq 1
    linkcnt     resq 1
    mode        resb 1                  ;0 raw, 'f', 'e' or 'm'
    opt_n       resb 1
    opt_z       resb 1
    is_last     resb 1
    status      resb 1

section .data
usage_msg   db "Usage: readlink [-f|-e|-m] [-n] [-z] FILE...", 10
    usage_len   equ $ - usage_msg
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
    lea     rsi, [rdi + 1]
    cmp     byte [rsi], '-'
    jne     .flags
    cmp     byte [rsi + 1], 0
    jne     .operand                    ;long options are not supported
    add     r13, 8                      ;"--" ends the options
    dec     r12
    jmp     .rest
.flags:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .next
    cmp     al, 'f'
    je      .canon
    cmp     al, 'e'
    je      .canon
    cmp     al, 'm'
    je      .canon
    cmp     al, 'n'
    je      .noeol
    cmp     al, 'z'
    je      .zero
inc     rsi                         ;-q/-s/-v: errors are silent anyway
    jmp     .flags
.canon:
    mov     [mode], al
    inc     rsi
    jmp     .flags
.noeol:
    mov     byte [opt_n], 1
    inc     rsi
    jmp     .flags
.zero:
    mov     byte [opt_z], 1
    inc     rsi
    jmp     .flags
.operand:
    call    add_arg
.next:
    add     r13, 8
    dec     r12
    jmp     parse
.rest:
    cmp     r12, 0
    jle     run
    mov     rdi, [r13]
    test    rdi, rdi
    jz      run
    call    add_arg
    add     r13, 8
    dec     r12
    jmp     .rest

run:
    cmp     qword [nargs], 0
    je      usage
    xor     rbx, rbx
.loop:
    cmp     rbx, [nargs]
    jge     .done
    mov     rdi, [args + rbx * 8]
    cmp     byte [mode], 0
    je      .raw
    call    canonicalize
    jmp     .check
.raw:
    call    raw_link
.check:
    test    al, al
    jz      .failed
    call    emit
    jmp     .next
.failed:
    mov     byte [status], 1
.next:
    inc     rbx
    jmp     .loop
.done:
    movzx   edi, byte [status]
    mov     rax, SYS_EXIT
    syscall

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

; ---------------------------------------------------------------------------
; raw_link: readlink(2) the operand in rdi into outbuf. al = 1 on success.
; ---------------------------------------------------------------------------
raw_link:
    mov     rax, SYS_READLINK
    mov     rsi, outbuf
    mov     rdx, PATHCAP - 1
    syscall
    test    rax, rax
    js      .fail
    mov     [outlen], rax
    mov     byte [outbuf + rax], 0
    mov     al, 1
    ret
.fail:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; emit: write the resolved value, then its terminator unless -n suppressed it
; on the final operand. rbx holds the operand index.
; ---------------------------------------------------------------------------
emit:
    push    rbx
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, outbuf
    mov     rdx, [outlen]
    syscall
    pop     rbx
    cmp     byte [opt_n], 0
    je      .term
    mov     rax, rbx
    inc     rax
    cmp     rax, [nargs]
    jge     .out                        ;-n only drops the very last one
.term:
    push    rbx
    mov     rsi, newline
    cmp     byte [opt_z], 0
    je      .write
    mov     rsi, nulbyte
.write:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rdx, 1
    syscall
    pop     rbx
.out:
    ret

; ---------------------------------------------------------------------------
; canonicalize: resolve the path in rdi into outbuf. al = 1 on success.
;
; outbuf holds the part resolved so far, with no trailing slash; empty means
; the root. restbuf holds what is left to resolve, and expanding a symlink
; just splices its target onto the front of that.
; ---------------------------------------------------------------------------
canonicalize:
    mov     [pathptr], rdi
    mov     qword [linkcnt], 0
    mov     qword [outlen], 0
    mov     byte [outbuf], 0
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
    ja      .fail                       ;a loop, or a chain too deep to trust
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
    cmp     byte [mode], 'm'
    je      .walk                       ;-m never looks at the filesystem
    cmp     byte [is_last], 0
    jne     .final
    mov     rax, SYS_STAT
    mov     rdi, outbuf
    mov     rsi, statbuf
    syscall
    test    rax, rax
    js      .fail
    mov     eax, [statbuf + ST_MODE]
    and     eax, S_IFMT
    cmp     eax, S_IFDIR
    jne     .fail                       ;something non-directory mid-path
    jmp     .walk
.final:
    cmp     byte [mode], 'e'
    jne     .walk                       ;-f lets the last component be missing
    mov     rax, SYS_STAT
    mov     rdi, outbuf
    mov     rsi, statbuf
    syscall
    test    rax, rax
    js      .fail
    jmp     .walk
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
; would have run past it, so a splice that no longer fits fails the operand
; instead of walking off the buffer.
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
