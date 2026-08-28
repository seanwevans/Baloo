; src/dd.asm -- dd(1): convert and copy a file.
; Usage: dd [if=FILE] [of=FILE] [bs=N] [ibs=N] [obs=N] [count=N] [skip=N]
;           [seek=N] [conv=LIST] [iflag=LIST] [oflag=LIST] [status=LEVEL]
;
; Input is read in ibs-sized records and repacked into obs-sized output
; records, which is what makes the "N+M records in/out" tallies meaningful:
; the left number counts whole records and the right one counts short ones.
; bs=N sets both sizes.
;
; Numbers accept the usual c/w/b/k/K/M/G/T suffixes (a trailing B selects the
; decimal multiplier) and NxM products; a negative value is an error.
;
; The output file is opened without O_TRUNC and truncated explicitly at the
; seek offset before any data is written, so "dd if=f of=f" empties the file
; before reading it, exactly as it does elsewhere.

    %include "include/sysdefs.inc"

    %define SEEK_CUR 1
    %define MAX_BS (16 * 1024 * 1024)

    %define ST_NONE 2
    %define ST_NOXFER 1

section .bss
    inbuf       resb MAX_BS
    outbuf      resb MAX_BS
    msgbuf      resb 512
    ibs         resq 1
    obs         resq 1
    count       resq 1
    remaining   resq 1
    skip_n      resq 1
    seek_n      resq 1
    in_fd       resq 1
    out_fd      resq 1
    if_path     resq 1
    of_path     resq 1
    obuf_len    resq 1
    bytes_out   resq 1
    rec_in_full resq 1
    rec_in_part resq 1
    rec_out_full resq 1
    rec_out_part resq 1
    n_read      resq 1
    have_of     resb 1
    c_notrunc   resb 1
    c_noerror   resb 1
    c_fsync     resb 1
    c_sync      resb 1
    c_nocreat   resb 1
    i_countbytes resb 1
    i_skipbytes resb 1
    o_seekbytes resb 1
    o_append    resb 1
    status_mode resb 1

section .data
    k_if        db "if", 0
    k_of        db "of", 0
    k_ibs       db "ibs", 0
    k_obs       db "obs", 0
    k_bs        db "bs", 0
    k_count     db "count", 0
    k_skip      db "skip", 0
    k_seek      db "seek", 0
    k_conv      db "conv", 0
    k_iflag     db "iflag", 0
    k_oflag     db "oflag", 0
    k_status    db "status", 0

    w_notrunc   db "notrunc", 0
    w_noerror   db "noerror", 0
    w_fsync     db "fsync", 0
    w_sync      db "sync", 0
    w_nocreat   db "nocreat", 0
    w_countb    db "count_bytes", 0
    w_skipb     db "skip_bytes", 0
    w_seekb     db "seek_bytes", 0
    w_append    db "append", 0
    w_noxfer    db "noxfer", 0
    w_none      db "none", 0

    s_recin     db " records in", 10, 0
    s_recout    db " records out", 10, 0
    s_copied    db " bytes copied", 10, 0
s_badnum    db "dd: invalid number", 10
    s_badnum_len equ $ - s_badnum
s_pfx       db "dd: "
    s_pfx_len   equ $ - s_pfx
s_noopen    db ": cannot open", 10, 0
s_nowrite   db "dd: write error", 10
    s_nowrite_len equ $ - s_nowrite
s_noread    db "dd: read error", 10
    s_noread_len equ $ - s_noread

section .text
global _start

_start:
    mov     qword [ibs], 512
    mov     qword [obs], 512
    mov     qword [count], -1
    mov     qword [in_fd], STDIN_FILENO
    mov     qword [out_fd], STDOUT_FILENO

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    jle     opened
    mov     r14, [r13]
    test    r14, r14
    jz      opened

    mov     rdi, r14
    mov     rsi, k_if
    call    keymatch
    test    al, al
    jnz     .set_if
    mov     rdi, r14
    mov     rsi, k_of
    call    keymatch
    test    al, al
    jnz     .set_of
    mov     rdi, r14
    mov     rsi, k_ibs
    call    keymatch
    test    al, al
    jnz     .set_ibs
    mov     rdi, r14
    mov     rsi, k_obs
    call    keymatch
    test    al, al
    jnz     .set_obs
    mov     rdi, r14
    mov     rsi, k_bs
    call    keymatch
    test    al, al
    jnz     .set_bs
    mov     rdi, r14
    mov     rsi, k_count
    call    keymatch
    test    al, al
    jnz     .set_count
    mov     rdi, r14
    mov     rsi, k_skip
    call    keymatch
    test    al, al
    jnz     .set_skip
    mov     rdi, r14
    mov     rsi, k_seek
    call    keymatch
    test    al, al
    jnz     .set_seek
    mov     rdi, r14
    mov     rsi, k_conv
    call    keymatch
    test    al, al
    jnz     .set_conv
    mov     rdi, r14
    mov     rsi, k_iflag
    call    keymatch
    test    al, al
    jnz     .set_iflag
    mov     rdi, r14
    mov     rsi, k_oflag
    call    keymatch
    test    al, al
    jnz     .set_oflag
    mov     rdi, r14
    mov     rsi, k_status
    call    keymatch
    test    al, al
    jnz     .set_status
jmp     .next                       ;unknown operand: ignore

.set_if:
    mov     [if_path], rdx
    jmp     .next
.set_of:
    mov     [of_path], rdx
    mov     byte [have_of], 1
    jmp     .next
.set_ibs:
    mov     rsi, rdx
    call    parse_size
    mov     [ibs], rax
    jmp     .next
.set_obs:
    mov     rsi, rdx
    call    parse_size
    mov     [obs], rax
    jmp     .next
.set_bs:
    mov     rsi, rdx
    call    parse_size
    mov     [ibs], rax
    mov     [obs], rax
    jmp     .next
.set_count:
    mov     rsi, rdx
    call    parse_size
    mov     [count], rax
    jmp     .next
.set_skip:
    mov     rsi, rdx
    call    parse_size
    mov     [skip_n], rax
    jmp     .next
.set_seek:
    mov     rsi, rdx
    call    parse_size
    mov     [seek_n], rax
    jmp     .next
.set_conv:
    mov     rsi, rdx
    mov     rbx, conv_word
    call    each_word
    jmp     .next
.set_iflag:
    mov     rsi, rdx
    mov     rbx, iflag_word
    call    each_word
    jmp     .next
.set_oflag:
    mov     rsi, rdx
    mov     rbx, oflag_word
    call    each_word
    jmp     .next
.set_status:
    mov     rsi, rdx
    mov     rbx, status_word
    call    each_word
.next:
    add     r13, 8
    dec     r12
    jmp     parse

; Operands are all known before anything is opened, so conv=nocreat and
; oflag=append apply no matter where they appear on the command line.
opened:
    mov     rax, [if_path]
    test    rax, rax
    jz      .output
    mov     rax, SYS_OPEN
    mov     rdi, [if_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .in_fail
    mov     [in_fd], rax
.output:
    cmp     byte [have_of], 0
    je      begin
    mov     rsi, O_WRONLY
    cmp     byte [c_nocreat], 0
    jne     .flags
    or      rsi, O_CREAT
.flags:
    cmp     byte [o_append], 0
    je      .doopen
    or      rsi, O_APPEND
.doopen:
    mov     rax, SYS_OPEN
    mov     rdi, [of_path]
    mov     rdx, DEFAULT_MODE
    syscall
    test    rax, rax
    js      .out_fail
    mov     [out_fd], rax
    jmp     begin
.in_fail:
    mov     rdi, [if_path]
    call    die_open
.out_fail:
    mov     rdi, [of_path]
    call    die_open

begin:
    mov     rax, [count]
    mov     [remaining], rax
    call    do_skip
    call    do_seek
    call    do_truncate

copy:
    mov     rdx, [ibs]
    cmp     qword [count], -1
    je      .read
    cmp     byte [i_countbytes], 0
    je      .blocks
    mov     rax, [remaining]
    cmp     rax, 0
    jle     finish
    cmp     rax, rdx
    jae     .read
    mov     rdx, rax
    jmp     .read
.blocks:
    cmp     qword [remaining], 0
    jle     finish
.read:
    mov     rax, SYS_READ
    mov     rdi, [in_fd]
    mov     rsi, inbuf
    syscall
    test    rax, rax
    js      .failed
    jz      finish
    mov     [n_read], rax
    cmp     rax, [ibs]
    jb      .short
    inc     qword [rec_in_full]
    jmp     .send
.short:
    inc     qword [rec_in_part]
    cmp     byte [c_sync], 0
    je      .send
    lea     rdi, [inbuf + rax]          ;conv=sync pads the record with NULs
    mov     rcx, [ibs]
    sub     rcx, rax
    xor     al, al
    rep     stosb
    mov     rax, [ibs]
.send:
    mov     rsi, inbuf
    mov     rdx, rax
    call    emit
    cmp     qword [count], -1
    je      copy
    cmp     byte [i_countbytes], 0
    je      .oneblock
    mov     rax, [n_read]
    sub     [remaining], rax
    jmp     copy
.oneblock:
    dec     qword [remaining]
    jmp     copy
.failed:
    cmp     byte [c_noerror], 0
    jne     finish
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, s_noread
    mov     rdx, s_noread_len
    syscall
    call    report
    exit    1

finish:
    mov     rdx, [obuf_len]
    test    rdx, rdx
    jz      .sync
    mov     rsi, outbuf
    call    write_all
    inc     qword [rec_out_part]
    mov     qword [obuf_len], 0
.sync:
    cmp     byte [c_fsync], 0
    je      .report
    mov     rax, SYS_FSYNC
    mov     rdi, [out_fd]
    syscall
.report:
    call    report
    exit    0

; ---------------------------------------------------------------------------
; do_skip: drop skip records (or bytes) of input, by seeking when the input
; supports it and by reading them away when it does not.
; ---------------------------------------------------------------------------
do_skip:
    mov     rax, [skip_n]
    test    rax, rax
    jz      .out
    mov     rcx, [ibs]
    cmp     byte [i_skipbytes], 0
    je      .scale
    mov     rcx, 1
.scale:
    imul    rax, rcx
    mov     r9, rax                     ;bytes still to drop
    mov     rsi, rax
    mov     rax, SYS_LSEEK
    mov     rdi, [in_fd]
    mov     rdx, SEEK_CUR
    syscall
    test    rax, rax
    jns     .out
.drop:
    test    r9, r9
    jz      .out
    mov     rdx, r9
    cmp     rdx, MAX_BS
    jbe     .chunk
    mov     rdx, MAX_BS
.chunk:
    mov     rax, SYS_READ
    mov     rdi, [in_fd]
    mov     rsi, inbuf
    syscall
    test    rax, rax
    jle     .out
    sub     r9, rax
    jmp     .drop
.out:
    ret

; do_seek: position the output at seek records (or bytes).
do_seek:
    cmp     byte [o_append], 0
    jne     .out                        ;O_APPEND already picks the position
    mov     rax, [seek_n]
    test    rax, rax
    jz      .out
    mov     rcx, [obs]
    cmp     byte [o_seekbytes], 0
    je      .scale
    mov     rcx, 1
.scale:
    imul    rax, rcx
    mov     rsi, rax
    mov     rax, SYS_LSEEK
    mov     rdi, [out_fd]
    mov     rdx, SEEK_SET
    syscall
.out:
    ret

; do_truncate: cut a named output file back to the seek offset before writing
; anything, so reading and writing the same file starts from an empty one.
do_truncate:
    cmp     byte [have_of], 0
    je      .out
    cmp     byte [c_notrunc], 0
    jne     .out
    cmp     byte [o_append], 0
    jne     .out
    mov     rax, SYS_LSEEK
    mov     rdi, [out_fd]
    xor     rsi, rsi
    mov     rdx, SEEK_CUR
    syscall
    test    rax, rax
    js      .out
    mov     rsi, rax
    mov     rax, SYS_FTRUNCATE
    mov     rdi, [out_fd]
    syscall                             ;a device that cannot be sized is fine
.out:
    ret

; ---------------------------------------------------------------------------
; emit: append rdx bytes at rsi to the output record, writing it out whenever
; it reaches obs bytes.
; ---------------------------------------------------------------------------
emit:
    test    rdx, rdx
    jz      .out
    mov     rax, [obs]
    sub     rax, [obuf_len]
    mov     rcx, rax
    cmp     rcx, rdx
    jbe     .copy
    mov     rcx, rdx
.copy:
    push    rsi
    push    rdx
    push    rcx
    mov     rdi, outbuf
    add     rdi, [obuf_len]
    rep     movsb
    pop     rcx
    pop     rdx
    pop     rsi
    add     rsi, rcx
    sub     rdx, rcx
    add     [obuf_len], rcx
    mov     rax, [obuf_len]
    cmp     rax, [obs]
    jb      emit
    push    rsi
    push    rdx
    mov     rsi, outbuf
    mov     rdx, [obs]
    call    write_all
    inc     qword [rec_out_full]
    mov     qword [obuf_len], 0
    pop     rdx
    pop     rsi
    jmp     emit
.out:
    ret

; write_all: write rdx bytes at rsi to the output, resuming after short writes.
write_all:
    test    rdx, rdx
    jz      .out
    mov     rax, SYS_WRITE
    mov     rdi, [out_fd]
    syscall
    test    rax, rax
    jle     .failed
    add     [bytes_out], rax
    add     rsi, rax
    sub     rdx, rax
    jmp     write_all
.failed:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, s_nowrite
    mov     rdx, s_nowrite_len
    syscall
    exit    1
.out:
    ret

; ---------------------------------------------------------------------------
; report: the record tallies on stderr, unless status= turned them off.
; ---------------------------------------------------------------------------
report:
    cmp     byte [status_mode], ST_NONE
    je      .out
    mov     rdi, msgbuf
    mov     rax, [rec_in_full]
    call    u64_to_dec
    mov     byte [rdi], '+'
    inc     rdi
    mov     rax, [rec_in_part]
    call    u64_to_dec
    mov     rsi, s_recin
    call    append_str
    mov     rax, [rec_out_full]
    call    u64_to_dec
    mov     byte [rdi], '+'
    inc     rdi
    mov     rax, [rec_out_part]
    call    u64_to_dec
    mov     rsi, s_recout
    call    append_str
    cmp     byte [status_mode], ST_NOXFER
    je      .write
    mov     rax, [bytes_out]
    call    u64_to_dec
    mov     rsi, s_copied
    call    append_str
.write:
    mov     rdx, rdi
    mov     rsi, msgbuf
    sub     rdx, rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
.out:
    ret

; die_open: report the path in rdi as unopenable and exit non-zero.
die_open:
    push    rdi
    mov     rdi, msgbuf
    mov     rsi, s_pfx
    mov     rcx, s_pfx_len
    rep     movsb
    pop     rsi
    call    append_str
    mov     rsi, s_noopen
    call    append_str
    mov     rdx, rdi
    mov     rsi, msgbuf
    sub     rdx, rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    exit    1

; ---------------------------------------------------------------------------
; keymatch: does the operand at rdi start with the NUL-terminated key at rsi
; followed by '='? al = 1 when it does, and rdx points at the value.
; ---------------------------------------------------------------------------
keymatch:
    push    rdi
    push    rsi
.scan:
    mov     al, [rsi]
    test    al, al
    jz      .sep
    cmp     al, [rdi]
    jne     .no
    inc     rsi
    inc     rdi
    jmp     .scan
.sep:
    cmp     byte [rdi], '='
    jne     .no
    lea     rdx, [rdi + 1]
    pop     rsi
    pop     rdi
    mov     al, 1
    ret
.no:
    pop     rsi
    pop     rdi
    xor     al, al
    ret

; each_word: split the comma list at rsi and call the handler in rbx with the
; word at rdi and its length in rcx.
each_word:
    mov     rdi, rsi
    xor     rcx, rcx
.len:
    mov     al, [rdi + rcx]
    test    al, al
    jz      .call
    cmp     al, ','
    je      .call
    inc     rcx
    jmp     .len
.call:
    push    rsi
    push    rcx
    push    rdi
    call    rbx
    pop     rdi
    pop     rcx
    pop     rsi
    add     rsi, rcx
    cmp     byte [rsi], ','
    jne     .out
    inc     rsi
    jmp     each_word
.out:
    ret

; wordmatch: is the rcx-byte word at rdi exactly the literal at rsi? al = 1/0.
wordmatch:
    push    rdi
    push    rsi
    push    rcx
    xor     r8, r8
.scan:
    cmp     r8, rcx
    je      .end
    mov     al, [rsi + r8]
    test    al, al
    jz      .no
    cmp     al, [rdi + r8]
    jne     .no
    inc     r8
    jmp     .scan
.end:
    cmp     byte [rsi + r8], 0
    jne     .no
    mov     al, 1
    jmp     .out
.no:
    xor     al, al
.out:
    pop     rcx
    pop     rsi
    pop     rdi
    ret

conv_word:
    mov     rsi, w_notrunc
    call    wordmatch
    test    al, al
    jnz     .notrunc
    mov     rsi, w_noerror
    call    wordmatch
    test    al, al
    jnz     .noerror
    mov     rsi, w_fsync
    call    wordmatch
    test    al, al
    jnz     .fsync
    mov     rsi, w_sync
    call    wordmatch
    test    al, al
    jnz     .sync
    mov     rsi, w_nocreat
    call    wordmatch
    test    al, al
    jnz     .nocreat
    ret
.notrunc:
    mov     byte [c_notrunc], 1
    ret
.noerror:
    mov     byte [c_noerror], 1
    ret
.fsync:
    mov     byte [c_fsync], 1
    ret
.sync:
    mov     byte [c_sync], 1
    ret
.nocreat:
    mov     byte [c_nocreat], 1
    ret

iflag_word:
    mov     rsi, w_countb
    call    wordmatch
    test    al, al
    jnz     .countb
    mov     rsi, w_skipb
    call    wordmatch
    test    al, al
    jnz     .skipb
    ret
.countb:
    mov     byte [i_countbytes], 1
    ret
.skipb:
    mov     byte [i_skipbytes], 1
    ret

oflag_word:
    mov     rsi, w_seekb
    call    wordmatch
    test    al, al
    jnz     .seekb
    mov     rsi, w_append
    call    wordmatch
    test    al, al
    jnz     .append
    ret
.seekb:
    mov     byte [o_seekbytes], 1
    ret
.append:
    mov     byte [o_append], 1
    ret

status_word:
    mov     rsi, w_noxfer
    call    wordmatch
    test    al, al
    jnz     .noxfer
    mov     rsi, w_none
    call    wordmatch
    test    al, al
    jnz     .none
    ret
.noxfer:
    mov     byte [status_mode], ST_NOXFER
    ret
.none:
    mov     byte [status_mode], ST_NONE
    ret

; ---------------------------------------------------------------------------
; parse_size: rsi -> a dd number; the value comes back in rax and a bad one
; exits rather than returning, since dd has nothing sensible to do with it.
; ---------------------------------------------------------------------------
parse_size:
    call    parse_num
    test    dl, dl
    jz      .bad
    cmp     rax, 0
    jl      .bad
    ret
.bad:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, s_badnum
    mov     rdx, s_badnum_len
    syscall
    exit    1

; parse_num: rsi -> number with optional suffix. rax = value, dl = 1 when the
; whole operand parsed, 0 otherwise. Leading blanks are skipped so "count= 2"
; works; a leading '-' is always an error.
parse_num:
    mov     al, [rsi]
    cmp     al, ' '
    je      .blank
    cmp     al, WHITESPACE_TAB
    jne     .signed
.blank:
    inc     rsi
    jmp     parse_num
.signed:
    cmp     al, '-'
    je      .bad
    cmp     al, '+'
    jne     .digits
    inc     rsi
.digits:
    xor     rax, rax
    xor     r9, r9                      ;digits seen
.digit:
    movzx   rcx, byte [rsi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .suffix
    imul    rax, rax, 10
    add     rax, rcx
    inc     rsi
    inc     r9
    jmp     .digit
.suffix:
    test    r9, r9
    jz      .bad
    movzx   rcx, byte [rsi]
    test    cl, cl
    jz      .ok
    cmp     cl, 'x'
    je      .product
    cmp     cl, 'X'
    je      .product
    cmp     cl, 'c'
    je      .unit1
    cmp     cl, 'w'
    je      .unit2
    cmp     cl, 'b'
    je      .unit512
    cmp     cl, 'k'
    je      .kilo
    cmp     cl, 'K'
    je      .kilo
    cmp     cl, 'M'
    je      .mega
    cmp     cl, 'G'
    je      .giga
    cmp     cl, 'T'
    je      .tera
    jmp     .bad
.kilo:
    mov     r10, 1024
    mov     r11, 1000
    jmp     .scaled
.mega:
    mov     r10, 1048576
    mov     r11, 1000000
    jmp     .scaled
.giga:
    mov     r10, 1073741824
    mov     r11, 1000000000
    jmp     .scaled
.tera:
    mov     r10, 1099511627776
    mov     r11, 1000000000000
.scaled:
    inc     rsi
    cmp     byte [rsi], 'B'             ;a trailing B means powers of ten
    jne     .apply
    inc     rsi
    mov     r10, r11
.apply:
    imul    rax, r10
    jmp     .chain
.unit1:
    mov     r10, 1
    jmp     .plain
.unit2:
    mov     r10, 2
    jmp     .plain
.unit512:
    mov     r10, 512
.plain:
    inc     rsi
    imul    rax, r10
.chain:
    movzx   rcx, byte [rsi]
    test    cl, cl
    jz      .ok
    cmp     cl, 'x'
    je      .product
    cmp     cl, 'X'
    je      .product
    jmp     .bad
.product:
    inc     rsi
    push    rax
    call    parse_num
    pop     rcx
    test    dl, dl
    jz      .bad
    imul    rax, rcx
    mov     dl, 1
    ret
.ok:
    mov     dl, 1
    ret
.bad:
    xor     edx, edx
    ret

; u64_to_dec: append rax as decimal at rdi, leaving rdi past the last digit.
u64_to_dec:
    push    rbx
    mov     rbx, rdi
    mov     rcx, 10
    xor     r8, r8                      ;digits pushed
.emit:
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    push    rdx
    inc     r8
    test    rax, rax
    jnz     .emit
.pop:
    pop     rdx
    mov     [rbx], dl
    inc     rbx
    dec     r8
    jnz     .pop
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
