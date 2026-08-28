; src/tail.asm -- tail(1): print the last part of input.
; Usage: tail [-f|-F] [-q|-v] [-s SEC] [-n [+]N] [-c [+]N] [-N] [FILE...]
;   (no FILE, or "-", reads standard input).
;
; Each operand is buffered whole, so counting lines/bytes back from the end
; and the "+N" from-the-start forms are both handled by slicing that buffer.
; The last of -n/-c/-N wins; the default is the last ten lines. With more
; than one operand a "==> NAME <==" banner precedes each one, and -q/-v
; force the banners off/on.
;
; -f watches the operands with inotify, so appends to different files are
; reported in the order the writes actually happened. -F cannot use inotify
; because it must also notice truncation and the file being replaced, so it
; polls every -s seconds (50ms by default) comparing the size and inode.

    %include "include/sysdefs.inc"

    %define SYS_FSTAT 5
    %define SYS_NANOSLEEP 35
    %define SYS_INOTIFY_ADD_WATCH 254
    %define SYS_INOTIFY_INIT1 294

    %define ST_DEV 0
    %define ST_INO 8
    %define ST_SIZE 48

    %define IN_MODIFY 0x00000002
    %define IN_DELETE_SELF 0x00000400
    %define IN_MOVE_SELF 0x00000800

    %define BUFCAP (8 * 1024 * 1024)
    %define MAXFILES 64
    %define EVBUFCAP 4096
    %define NAMECAP 4096
    %define DEFAULT_NS 50000000

section .bss
    buf         resb BUFCAP
    evbuf       resb EVBUFCAP
    namebuf     resb NAMECAP
    statbuf     resb 160
    fnames      resq MAXFILES
    fds         resq MAXFILES
    offs        resq MAXFILES
    inos        resq MAXFILES
    devs        resq MAXFILES
    wds         resq MAXFILES
    nfiles      resq 1
    kcount      resq 1
    inlen       resq 1
    lastidx     resq 1
    ifd         resq 1
    evlen       resq 1
    evpos       resq 1
    ts          resq 2
    mode        resb 1                  ;'l' lines, 'c' chars
    fromstart   resb 1
    follow      resb 1                  ;0 none, 1 -f, 2 -F
    hdrmode     resb 1                  ;0 auto, 1 always (-v), 2 never (-q)
    showhdr     resb 1
    anyout      resb 1
    status      resb 1

section .data
    hdr_open    db "==> "
    hdr_close   db " <==", 10
    stdin_name  db "standard input", 0
err_pre     db "tail: cannot open '"
    err_pre_len equ $ - err_pre
    err_post    db "'", 10
    err_post_len equ $ - err_post

section .text
global _start

_start:
    mov     byte [mode], 'l'
    mov     byte [fromstart], 0
    mov     qword [kcount], 10
    mov     qword [lastidx], -1
    mov     qword [ts], 0
    mov     qword [ts + 8], DEFAULT_NS

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
    jne     .file
    cmp     byte [rdi + 1], 0
    je      .file                       ;lone "-" -> stdin
    movzx   eax, byte [rdi + 1]
    cmp     al, '0'
    jb      .opts
    cmp     al, '9'
    ja      .opts
;"-N" shorthand: last N lines
    mov     byte [mode], 'l'
    mov     byte [fromstart], 0
    lea     rdi, [rdi + 1]
    call    atou
    mov     [kcount], rax
    jmp     .nextarg
.opts:
    lea     rsi, [rdi + 1]
.oc:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 'n'
    je      .nc
    cmp     al, 'c'
    je      .nc
    cmp     al, 's'
    je      .sleepopt
    cmp     al, 'f'
    je      .followopt
    cmp     al, 'F'
    je      .retryopt
    cmp     al, 'q'
    je      .quietopt
    cmp     al, 'v'
    je      .verboseopt
    inc     rsi                         ;ignore anything else
    jmp     .oc
.followopt:
    mov     byte [follow], 1
    inc     rsi
    jmp     .oc
.retryopt:
    mov     byte [follow], 2
    inc     rsi
    jmp     .oc
.quietopt:
    mov     byte [hdrmode], 2
    inc     rsi
    jmp     .oc
.verboseopt:
    mov     byte [hdrmode], 1
    inc     rsi
    jmp     .oc
.sleepopt:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .havesleep
    add     r13, 8                      ;value in the next argv
    dec     r12
    mov     rsi, [r13]
    test    rsi, rsi
    jz      .nextarg
.havesleep:
    mov     rdi, rsi
    call    parse_interval
    jmp     .nextarg
.nc:
    cmp     al, 'c'
    jne     .isline
    mov     byte [mode], 'c'
    jmp     .value
.isline:
    mov     byte [mode], 'l'
.value:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .haveval
    add     r13, 8                      ;value in the next argv
    dec     r12
    mov     rsi, [r13]
    test    rsi, rsi
    jz      .nextarg
.haveval:
    mov     byte [fromstart], 0
    cmp     byte [rsi], '+'
    jne     .notplus
    mov     byte [fromstart], 1
    inc     rsi
    jmp     .doatou
.notplus:
    cmp     byte [rsi], '-'
    jne     .doatou
    inc     rsi
.doatou:
    mov     rdi, rsi
    call    atou
    mov     [kcount], rax
    jmp     .nextarg
.file:
    mov     rcx, [nfiles]
    cmp     rcx, MAXFILES
    jae     .nextarg
    mov     [fnames + rcx * 8], rdi
    inc     rcx
    mov     [nfiles], rcx
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

run:
    cmp     qword [nfiles], 0
    jne     .banners
mov     qword [fnames], 0           ;no operands: a single stdin "file"
    mov     qword [nfiles], 1
.banners:
    cmp     byte [hdrmode], 1
    je      .hdron
    cmp     byte [hdrmode], 2
    je      .hdroff
    cmp     qword [nfiles], 1
    jbe     .hdroff
.hdron:
    mov     byte [showhdr], 1
    jmp     .first
.hdroff:
    mov     byte [showhdr], 0
.first:
    xor     rbx, rbx
.iloop:
    cmp     rbx, [nfiles]
    jge     .idone
    mov     qword [fds + rbx * 8], -1
    mov     qword [offs + rbx * 8], 0
    mov     qword [wds + rbx * 8], -1
    mov     rdi, [fnames + rbx * 8]
    test    rdi, rdi
    jz      .usestdin
    cmp     byte [rdi], '-'
    jne     .doopen
    cmp     byte [rdi + 1], 0
    je      .usestdin
.doopen:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .openfail
    mov     [fds + rbx * 8], rax
    jmp     .opened
.usestdin:
    mov     qword [fds + rbx * 8], STDIN_FILENO
.opened:
    call    dump_initial
    jmp     .inext
.openfail:
    mov     byte [status], 1
    call    warn_open
.inext:
    inc     rbx
    jmp     .iloop
.idone:
    cmp     byte [follow], 0
    jne     follow_start
    jmp     done

; ---------------------------------------------------------------------------
; dump_initial: read all of fds[rbx], print its banner and the requested tail.
; ---------------------------------------------------------------------------
dump_initial:
    push    rbx
    xor     r15, r15                    ;bytes read
.rl:
    mov     rdx, BUFCAP
    sub     rdx, r15
    jz      .rdone
    mov     rax, SYS_READ
    mov     rdi, [fds + rbx * 8]
    lea     rsi, [buf + r15]
    syscall
    test    rax, rax
    jle     .rdone
    add     r15, rax
    jmp     .rl
.rdone:
    mov     [inlen], r15
    call    compute_slice               ;-> r14 = slice start
    call    print_header
    mov     rdx, [inlen]
    sub     rdx, r14
    jle     .noout
    lea     rsi, [buf + r14]
    call    out
.noout:
    mov     rax, [inlen]
    mov     [offs + rbx * 8], rax
    call    record_ident
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; compute_slice: with [mode]/[fromstart]/[kcount]/[inlen], set r14 to the
; offset in buf where the output should start.
; ---------------------------------------------------------------------------
compute_slice:
    cmp     byte [mode], 'c'
    je      chars
    cmp     byte [fromstart], 1
    je      lines_from_start

; last K lines
lines_from_end:
mov     r14, 0                      ;default: the whole buffer
    mov     rcx, [inlen]
    test    rcx, rcx
    jz      .out
    mov     rsi, rcx
    dec     rsi                         ;i = len-1
    cmp     byte [buf + rsi], WHITESPACE_NL
    jne     .scan
    dec     rsi                         ;skip a trailing newline
.scan:
    xor     r8, r8                      ;newlines seen
.loop:
    cmp     rsi, 0
    jl      .out
    cmp     byte [buf + rsi], WHITESPACE_NL
    jne     .dec
    inc     r8
    cmp     r8, [kcount]
    jne     .dec
    lea     r14, [rsi + 1]
    jmp     .out
.dec:
    dec     rsi
    jmp     .loop
.out:
    ret

; from line K (1-based)
lines_from_start:
mov     r14, [inlen]                ;default: nothing
    cmp     qword [kcount], 1
    jbe     .whole
    mov     rdx, [kcount]
    dec     rdx                         ;newlines to pass
    xor     rsi, rsi                    ;i
    xor     r8, r8                      ;newlines seen
.loop:
    cmp     rsi, [inlen]
    jge     .out
    cmp     byte [buf + rsi], WHITESPACE_NL
    jne     .next
    inc     r8
    cmp     r8, rdx
    jne     .next
    lea     r14, [rsi + 1]
    jmp     .out
.next:
    inc     rsi
    jmp     .loop
.whole:
    xor     r14, r14
.out:
    ret

chars:
    cmp     byte [fromstart], 1
    je      .fromstart
;last K bytes
    mov     r14, [inlen]
    sub     r14, [kcount]
    jns     .out
    xor     r14, r14
    jmp     .out
.fromstart:
;from byte K (1-based)
    mov     r14, [kcount]
    test    r14, r14
    jz      .zero
    dec     r14
.zero:
    cmp     r14, [inlen]
    jbe     .out
    mov     r14, [inlen]
.out:
    ret

; ---------------------------------------------------------------------------
; follow_start: -f uses inotify for ordered events, -F falls back to polling.
; ---------------------------------------------------------------------------
follow_start:
    cmp     byte [follow], 1
    jne     poll_follow
    mov     rax, SYS_INOTIFY_INIT1
    xor     rdi, rdi
    syscall
    test    rax, rax
    js      poll_follow
    mov     [ifd], rax
    xor     rbx, rbx
    xor     r15, r15                    ;watches registered
.watch:
    cmp     rbx, [nfiles]
    jge     .watched
    mov     rax, [fnames + rbx * 8]
    test    rax, rax
    jz      .wnext                      ;stdin cannot be watched by name
    mov     rax, SYS_INOTIFY_ADD_WATCH
    mov     rdi, [ifd]
    mov     rsi, [fnames + rbx * 8]
    mov     rdx, IN_MODIFY | IN_MOVE_SELF | IN_DELETE_SELF
    syscall
    test    rax, rax
    js      .wnext
    mov     [wds + rbx * 8], rax
    inc     r15
.wnext:
    inc     rbx
    jmp     .watch
.watched:
    test    r15, r15
jz      poll_follow                 ;nothing watchable: poll instead
.wait:
    mov     rax, SYS_READ
    mov     rdi, [ifd]
    mov     rsi, evbuf
    mov     rdx, EVBUFCAP
    syscall
    test    rax, rax
    js      done
    jz      .wait
    mov     [evlen], rax
    mov     qword [evpos], 0
.event:
    mov     rax, [evpos]
    add     rax, 16
    cmp     rax, [evlen]
    ja      .wait                       ;a partial header cannot happen
    mov     rcx, rax
    sub     rcx, 16
    mov     r8d, [evbuf + rcx]          ;wd
    mov     edx, [evbuf + rcx + 12]     ;name length
    add     rax, rdx
    mov     [evpos], rax
    xor     rbx, rbx
.find:
    cmp     rbx, [nfiles]
    jge     .event
    mov     eax, [wds + rbx * 8]
    cmp     eax, r8d
    je      .hit
    inc     rbx
    jmp     .find
.hit:
    call    check_growth
    jmp     .event

poll_follow:
    mov     rax, SYS_NANOSLEEP
    mov     rdi, ts
    xor     rsi, rsi
    syscall
    xor     rbx, rbx
.scan:
    cmp     rbx, [nfiles]
    jge     poll_follow
    cmp     byte [follow], 2
    jne     .grew
    call    retry_open
.grew:
    call    check_growth
    inc     rbx
    jmp     .scan

; ---------------------------------------------------------------------------
; check_growth: print whatever fds[rbx] has gained since offs[rbx]. A file
; that shrank was truncated, so start reading it again from the beginning.
; ---------------------------------------------------------------------------
check_growth:
    push    rbx
    mov     rdi, [fds + rbx * 8]
    cmp     rdi, 0
    jl      .out
    mov     rax, SYS_FSTAT
    mov     rsi, statbuf
    syscall
    test    rax, rax
    js      .out
    mov     rax, [statbuf + ST_SIZE]
    cmp     rax, [offs + rbx * 8]
    jae     .cmp
    mov     qword [offs + rbx * 8], 0
.cmp:
    mov     rax, [statbuf + ST_SIZE]
    cmp     rax, [offs + rbx * 8]
    jbe     .out
    mov     rax, SYS_LSEEK
    mov     rdi, [fds + rbx * 8]
    mov     rsi, [offs + rbx * 8]
    mov     rdx, SEEK_SET
    syscall
    mov     rax, [lastidx]
    cmp     rax, rbx
    je      .copy
    call    print_header
.copy:
    mov     rax, SYS_READ
    mov     rdi, [fds + rbx * 8]
    mov     rsi, buf
    mov     rdx, BUFCAP
    syscall
    test    rax, rax
    jle     .out
    add     [offs + rbx * 8], rax
    mov     rdx, rax
    mov     rsi, buf
    call    out
    jmp     .copy
.out:
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; retry_open (-F): open the name if it is not open yet, or reopen it when the
; name now refers to a different inode than the descriptor we hold.
; ---------------------------------------------------------------------------
retry_open:
    push    rbx
    mov     rdi, [fnames + rbx * 8]
    test    rdi, rdi
    jz      .out
    mov     rax, SYS_STAT
    mov     rsi, statbuf
    syscall
    test    rax, rax
    js      .out
    cmp     qword [fds + rbx * 8], 0
    jl      .reopen
    mov     rax, [statbuf + ST_INO]
    cmp     rax, [inos + rbx * 8]
    jne     .reopen
    mov     rax, [statbuf + ST_DEV]
    cmp     rax, [devs + rbx * 8]
    je      .out
.reopen:
    mov     rdi, [fds + rbx * 8]
    cmp     rdi, 2
    jle     .fresh
    mov     rax, SYS_CLOSE
    syscall
.fresh:
    mov     rax, SYS_OPEN
    mov     rdi, [fnames + rbx * 8]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .out
    mov     [fds + rbx * 8], rax
    mov     qword [offs + rbx * 8], 0
    call    record_ident
.out:
    pop     rbx
    ret

; record_ident: remember the device and inode behind fds[rbx].
record_ident:
    push    rbx
    mov     rdi, [fds + rbx * 8]
    cmp     rdi, 0
    jl      .out
    mov     rax, SYS_FSTAT
    mov     rsi, statbuf
    syscall
    test    rax, rax
    js      .out
    mov     rax, [statbuf + ST_INO]
    mov     [inos + rbx * 8], rax
    mov     rax, [statbuf + ST_DEV]
    mov     [devs + rbx * 8], rax
.out:
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; print_header: emit "==> NAME <==" for fds[rbx] when banners are on, blank
; separated from whatever came before, and record the file as the current one.
; ---------------------------------------------------------------------------
print_header:
    push    rbx
    mov     [lastidx], rbx
    cmp     byte [showhdr], 0
    je      .out
    mov     rdi, namebuf
    cmp     byte [anyout], 0
    je      .banner
    mov     byte [rdi], WHITESPACE_NL
    inc     rdi
.banner:
    mov     rsi, hdr_open
    mov     rcx, 4
    rep     movsb
    mov     rsi, [fnames + rbx * 8]
    test    rsi, rsi
    jnz     .name
    mov     rsi, stdin_name
.name:
    mov     al, [rsi]
    test    al, al
    jz      .close
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     .name
.close:
    mov     rsi, hdr_close
    mov     rcx, 5
    rep     movsb
    mov     rsi, namebuf
    mov     rdx, rdi
    sub     rdx, rsi
    call    out
.out:
    pop     rbx
    ret

; warn_open: report an operand that could not be opened, on stderr.
warn_open:
    push    rbx
    mov     rdi, namebuf
    mov     rsi, err_pre
    mov     rcx, err_pre_len
    rep     movsb
    mov     rsi, [fnames + rbx * 8]
    test    rsi, rsi
    jnz     .name
    mov     rsi, stdin_name
.name:
    mov     al, [rsi]
    test    al, al
    jz      .close
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     .name
.close:
    mov     rsi, err_post
    mov     rcx, err_post_len
    rep     movsb
    mov     rdx, rdi
    mov     rsi, namebuf
    sub     rdx, rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    pop     rbx
    ret

; out: write rdx bytes at rsi to stdout, resuming after short writes.
out:
    test    rdx, rdx
    jle     .out
    mov     byte [anyout], 1
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
    ret

; parse_interval: rdi -> "SEC[.FRACTION]", stored in ts as a timespec.
parse_interval:
    xor     rax, rax
.whole:
    movzx   rcx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .fraction
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .whole
.fraction:
    mov     [ts], rax
    xor     rax, rax                    ;fraction digits, scaled below
    xor     r8, r8                      ;digits taken
    cmp     byte [rdi], '.'
    jne     .scale
    inc     rdi
.digit:
    movzx   rcx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .scale
    cmp     r8, 9
    jae     .skip
    imul    rax, rax, 10
    add     rax, rcx
    inc     r8
.skip:
    inc     rdi
    jmp     .digit
.scale:
    cmp     r8, 9
    jae     .store
    imul    rax, rax, 10
    inc     r8
    jmp     .scale
.store:
    mov     [ts + 8], rax
    mov     rcx, [ts]
    or      rcx, rax
    jnz     .out
    mov     qword [ts + 8], DEFAULT_NS  ;a zero interval would just spin
.out:
    ret

; atou: rdi -> unsigned decimal in rax.
atou:
    xor     rax, rax
.l:
    movzx   rcx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .done
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .l
.done:
    ret

done:
    movzx   edi, byte [status]
    mov     rax, SYS_EXIT
    syscall
