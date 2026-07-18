; src/stat.asm -- print file metadata in a user format (stat -c FORMAT).
; Usage: stat -c FORMAT FILE...
; Supported directives: %n %s %i %h %u %g %f %a %A %F %b %o %d %%
; (Does not follow symlinks, matching coreutils stat's default lstat
; behaviour. The bare multi-line default output is not implemented; a
; format is required.)

    %include "include/sysdefs.inc"

    %define OUTBUF_SIZE 65536
    %define SYS_LSTAT 6

section .bss
    statbuf  resb 160
    fmt_ptr  resq 1
    cur_name resq 1
    fail     resq 1
    numtmp   resb 32
    outbuf   resb OUTBUF_SIZE
    outlen   resq 1
    dt_tod   resq 1
    dt_nsec  resq 1
    dt_year  resq 1
    dt_month resq 1
    dt_day   resq 1

section .data
    digits db "0123456789abcdef"
usage_msg db "Usage: stat -c FORMAT FILE...", 10
    usage_len equ $ - usage_msg
err_stat db "stat: cannot stat file", 10
    err_stat_len equ $ - err_stat
    str_reg db "regular file", 0
    str_reg_empty db "regular empty file", 0
    str_dir db "directory", 0
    str_lnk db "symbolic link", 0
    str_chr db "character special file", 0
    str_blk db "block special file", 0
    str_fifo db "fifo", 0
    str_sock db "socket", 0
    str_unknown db "weird file", 0

section .text
global _start

_start:
    mov     qword [outlen], 0
    mov     qword [fail], 0
    pop     rax                         ;argc
    pop     rdi                         ;argv[0] discarded
    cmp     rax, 4
    jl      .usage
    pop     rsi                         ;argv[1] (must be -c)
    cmp     byte [rsi], '-'
    jne     .usage
    cmp     byte [rsi + 1], 'c'
    jne     .usage
    cmp     byte [rsi + 2], 0
    jne     .usage
    pop     rsi                         ;argv[2] = format
    mov     [fmt_ptr], rsi
    sub     rax, 3
    mov     r14, rax                    ;file count
    mov     r15, rsp                    ;&argv[3]
    xor     r12, r12                    ;file index
.file_loop:
    cmp     r12, r14
    jge     .done
    mov     rdi, [r15 + r12*8]
    mov     [cur_name], rdi
    mov     rax, SYS_LSTAT
    mov     rsi, statbuf
    syscall
    test    rax, rax
    js      .stat_err
    mov     r13, [fmt_ptr]
.scan:
    mov     al, [r13]
    test    al, al
    jz      .line_done
    cmp     al, '%'
    je      .directive
    call    out_char
    inc     r13
    jmp     .scan
.directive:
    inc     r13
    mov     al, [r13]
    test    al, al
    jz      .trailing_pct
    cmp     al, 'n'
    je      .d_name
    cmp     al, 's'
    je      .d_size
    cmp     al, 'i'
    je      .d_ino
    cmp     al, 'h'
    je      .d_nlink
    cmp     al, 'u'
    je      .d_uid
    cmp     al, 'g'
    je      .d_gid
    cmp     al, 'd'
    je      .d_dev
    cmp     al, 'o'
    je      .d_blksize
    cmp     al, 'b'
    je      .d_blocks
    cmp     al, 'f'
    je      .d_rawmode
    cmp     al, 'a'
    je      .d_perms_oct
    cmp     al, 'A'
    je      .d_perms_sym
    cmp     al, 'F'
    je      .d_type
    cmp     al, 'X'
    je      .d_atime
    cmp     al, 'Y'
    je      .d_mtime
    cmp     al, 'x'
    je      .d_atime_str
    cmp     al, 'y'
    je      .d_mtime_str
    cmp     al, '%'
    je      .d_pct
    mov     al, '?'                     ;unknown directive -> '?'
    call    out_char
    inc     r13
    jmp     .scan
.trailing_pct:
    mov     al, '%'                     ;a '%' at end of format is literal
    call    out_char
    jmp     .line_done
.d_name:
    mov     rsi, [cur_name]
    call    emit_str
    inc     r13
    jmp     .scan
.d_size:
    mov     rdi, [statbuf + 48]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_ino:
    mov     rdi, [statbuf + 8]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_nlink:
    mov     rdi, [statbuf + 16]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_uid:
    mov     edi, [statbuf + 28]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_gid:
    mov     edi, [statbuf + 32]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_dev:
    mov     rdi, [statbuf + 0]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_blksize:
    mov     rdi, [statbuf + 56]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_blocks:
    mov     rdi, [statbuf + 64]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_rawmode:
    movzx   rdi, word [statbuf + 24]
    mov     rsi, 16
    call    emit_base
    inc     r13
    jmp     .scan
.d_perms_oct:
    mov     edi, [statbuf + 24]
    and     edi, 0o7777
    mov     rsi, 8
    call    emit_base
    inc     r13
    jmp     .scan
.d_perms_sym:
    call    emit_perms
    inc     r13
    jmp     .scan
.d_type:
    call    emit_type
    inc     r13
    jmp     .scan
.d_atime:
    mov     rdi, [statbuf + 72]         ;st_atime seconds
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_mtime:
    mov     rdi, [statbuf + 88]         ;st_mtime seconds
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_atime_str:
    mov     rdi, [statbuf + 72]
    mov     rsi, [statbuf + 80]         ;st_atime nanoseconds
    call    emit_datetime
    inc     r13
    jmp     .scan
.d_mtime_str:
    mov     rdi, [statbuf + 88]
    mov     rsi, [statbuf + 96]         ;st_mtime nanoseconds
    call    emit_datetime
    inc     r13
    jmp     .scan
.d_pct:
    mov     al, '%'
    call    out_char
    inc     r13
    jmp     .scan
.line_done:
    mov     al, 10
    call    out_char
    inc     r12
    jmp     .file_loop
.stat_err:
    mov     qword [fail], 1
    push    r12
    push    r14
    push    r15
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, err_stat
    mov     rdx, err_stat_len
    syscall
    pop     r15
    pop     r14
    pop     r12
    inc     r12
    jmp     .file_loop
.done:
    call    out_flush
    mov     rdi, [fail]
    mov     rax, SYS_EXIT
    syscall
.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

; emit_base: rdi = value, rsi = base -> digits via out_char (register-safe)
emit_base:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    push    rsi
    mov     rax, rdi
    mov     rbx, rsi
    lea     rcx, [numtmp + 32]
    test    rax, rax
    jnz     .loop
    dec     rcx
    mov     byte [rcx], '0'
    jmp     .emit
.loop:
    xor     rdx, rdx
    div     rbx
    mov     dl, [digits + rdx]
    dec     rcx
    mov     [rcx], dl
    test    rax, rax
    jnz     .loop
.emit:
    lea     rdi, [numtmp + 32]
.eloop:
    cmp     rcx, rdi
    jge     .edone
    mov     al, [rcx]
    call    out_char
    inc     rcx
    jmp     .eloop
.edone:
    pop     rsi
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; emit_padded: rdi = value, rsi = minimum width; emit decimal, zero-padded
emit_padded:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    r8
    lea     rcx, [numtmp + 32]
    mov     rax, rdi
    xor     r8, r8                      ;digit count
.lp:
    xor     rdx, rdx
    mov     rbx, 10
    div     rbx
    add     dl, '0'
    dec     rcx
    mov     [rcx], dl
    inc     r8
    test    rax, rax
    jnz     .lp
.pad:
    cmp     r8, rsi
    jge     .emit
    dec     rcx
    mov     byte [rcx], '0'
    inc     r8
    jmp     .pad
.emit:
    mov     al, [rcx]
    call    out_char
    inc     rcx
    dec     r8
    jnz     .emit
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; emit_datetime: rdi = epoch seconds, rsi = nanoseconds. Emits UTC as
; "YYYY-MM-DD HH:MM:SS.NNNNNNNNN +0000" (matches TZ=UTC coreutils stat).
emit_datetime:
    push    rbx
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10
    push    r11
    mov     [dt_nsec], rsi
;split epoch into whole days and the seconds-of-day
    mov     rax, rdi
    xor     rdx, rdx
    mov     rcx, 86400
    div     rcx                         ;rax = days, rdx = seconds-of-day
    mov     [dt_tod], rdx
;civil_from_days(days) -> year/month/day (valid for days >= 0)
    add     rax, 719468                 ;shift epoch to 0000-03-01
    xor     rdx, rdx
    mov     rcx, 146097
    div     rcx                         ;rax = era, rdx = doe
    mov     r11, rax                    ;era
    mov     r8, rdx                     ;doe
;yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365
    mov     rax, r8
    xor     rdx, rdx
    mov     rcx, 1460
    div     rcx
    mov     r9, rax                     ;doe/1460
    mov     rax, r8
    xor     rdx, rdx
    mov     rcx, 36524
    div     rcx
    mov     r10, rax                    ;doe/36524
    mov     rax, r8
    xor     rdx, rdx
    mov     rcx, 146096
    div     rcx                         ;rax = doe/146096
    mov     rcx, r8
    sub     rcx, r9
    add     rcx, r10
    sub     rcx, rax
    mov     rax, rcx
    xor     rdx, rdx
    mov     rcx, 365
    div     rcx
    mov     r9, rax                     ;yoe
;year = yoe + era*400
    mov     rax, r11
    imul    rax, rax, 400
    add     rax, r9
    mov     r11, rax                    ;year (pre month adjust)
;doy = doe - (365*yoe + yoe/4 - yoe/100)
    mov     rax, r9
    imul    rax, rax, 365
    mov     rcx, r9
    shr     rcx, 2                      ;yoe/4
    add     rax, rcx
    mov     rbx, rax                    ;365*yoe + yoe/4
    mov     rax, r9
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx                         ;yoe/100
    mov     rcx, rbx
    sub     rcx, rax                    ;365*yoe + yoe/4 - yoe/100
    mov     r10, r8
    sub     r10, rcx                    ;doy
;mp = (5*doy + 2)/153
    mov     rax, r10
    imul    rax, rax, 5
    add     rax, 2
    xor     rdx, rdx
    mov     rcx, 153
    div     rcx
    mov     r8, rax                     ;mp
;day = doy - (153*mp + 2)/5 + 1
    mov     rax, r8
    imul    rax, rax, 153
    add     rax, 2
    xor     rdx, rdx
    mov     rcx, 5
    div     rcx
    mov     rcx, r10
    sub     rcx, rax
    inc     rcx
    mov     [dt_day], rcx
;month = mp < 10 ? mp+3 : mp-9
    cmp     r8, 10
    jb      .mp_lt
    sub     r8, 9
    jmp     .mp_done
.mp_lt:
    add     r8, 3
.mp_done:
    mov     [dt_month], r8
;year += (month <= 2)
    cmp     r8, 2
    ja      .year_ok
    inc     r11
.year_ok:
    mov     [dt_year], r11
;--- emit the formatted string ---
    mov     rdi, [dt_year]
    mov     rsi, 4
    call    emit_padded
    mov     al, '-'
    call    out_char
    mov     rdi, [dt_month]
    mov     rsi, 2
    call    emit_padded
    mov     al, '-'
    call    out_char
    mov     rdi, [dt_day]
    mov     rsi, 2
    call    emit_padded
    mov     al, ' '
    call    out_char
;hour = tod/3600
    mov     rax, [dt_tod]
    xor     rdx, rdx
    mov     rcx, 3600
    div     rcx
    mov     rdi, rax                    ;hour
    mov     r10, rdx                    ;remaining seconds
    mov     rsi, 2
    call    emit_padded
mov     al, ':'
    call    out_char
;minute = (tod%3600)/60, second = tod%60
    mov     rax, r10
    xor     rdx, rdx
    mov     rcx, 60
    div     rcx
    mov     rdi, rax                    ;minute
    mov     r10, rdx                    ;second
    mov     rsi, 2
    call    emit_padded
mov     al, ':'
    call    out_char
    mov     rdi, r10                    ;second
    mov     rsi, 2
    call    emit_padded
    mov     al, '.'
    call    out_char
    mov     rdi, [dt_nsec]
    mov     rsi, 9
    call    emit_padded
    mov     al, ' '
    call    out_char
    mov     al, '+'
    call    out_char
    mov     al, '0'
    call    out_char
    mov     al, '0'
    call    out_char
    mov     al, '0'
    call    out_char
    mov     al, '0'
    call    out_char
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; emit_str: rsi = NUL-terminated string -> out_char (register-safe)
emit_str:
    push    rsi
.loop:
    mov     al, [rsi]
    test    al, al
    jz      .done
    call    out_char
    inc     rsi
    jmp     .loop
.done:
    pop     rsi
    ret

; emit_type: emit the %F file-type string from statbuf
emit_type:
    push    rsi
    mov     eax, [statbuf + 24]
    and     eax, 0o170000
    cmp     eax, 0o100000
    je      .reg
    cmp     eax, 0o040000
    je      .dir
    cmp     eax, 0o120000
    je      .lnk
    cmp     eax, 0o020000
    je      .chr
    cmp     eax, 0o060000
    je      .blk
    cmp     eax, 0o010000
    je      .fifo
    cmp     eax, 0o140000
    je      .sock
    mov     rsi, str_unknown
    jmp     .out
.reg:
    mov     rax, [statbuf + 48]
    test    rax, rax
    jnz     .reg_ne
    mov     rsi, str_reg_empty
    jmp     .out
.reg_ne:
    mov     rsi, str_reg
    jmp     .out
.dir:
    mov     rsi, str_dir
    jmp     .out
.lnk:
    mov     rsi, str_lnk
    jmp     .out
.chr:
    mov     rsi, str_chr
    jmp     .out
.blk:
    mov     rsi, str_blk
    jmp     .out
.fifo:
    mov     rsi, str_fifo
    jmp     .out
.sock:
    mov     rsi, str_sock
.out:
    call    emit_str
    pop     rsi
    ret

; emit_perms: emit the 10-character %A symbolic permissions
emit_perms:
    push    rbx
    mov     ebx, [statbuf + 24]
    mov     eax, ebx
    and     eax, 0o170000
    cmp     eax, 0o040000
    je      .t_dir
    cmp     eax, 0o120000
    je      .t_lnk
    cmp     eax, 0o020000
    je      .t_chr
    cmp     eax, 0o060000
    je      .t_blk
    cmp     eax, 0o010000
    je      .t_fifo
    cmp     eax, 0o140000
    je      .t_sock
    mov     al, '-'
    jmp     .t_emit
.t_dir:
    mov     al, 'd'
    jmp     .t_emit
.t_lnk:
    mov     al, 'l'
    jmp     .t_emit
.t_chr:
    mov     al, 'c'
    jmp     .t_emit
.t_blk:
    mov     al, 'b'
    jmp     .t_emit
.t_fifo:
    mov     al, 'p'
    jmp     .t_emit
.t_sock:
    mov     al, 's'
.t_emit:
    call    out_char

    mov     al, '-'
    test    ebx, 0o400
    jz      .ur
    mov     al, 'r'
.ur:
    call    out_char
    mov     al, '-'
    test    ebx, 0o200
    jz      .uw
    mov     al, 'w'
.uw:
    call    out_char
    test    ebx, 0o4000
    jnz     .ux_suid
    mov     al, '-'
    test    ebx, 0o100
    jz      .ux_emit
    mov     al, 'x'
    jmp     .ux_emit
.ux_suid:
    mov     al, 'S'
    test    ebx, 0o100
    jz      .ux_emit
    mov     al, 's'
.ux_emit:
    call    out_char

    mov     al, '-'
    test    ebx, 0o40
    jz      .gr
    mov     al, 'r'
.gr:
    call    out_char
    mov     al, '-'
    test    ebx, 0o20
    jz      .gw
    mov     al, 'w'
.gw:
    call    out_char
    test    ebx, 0o2000
    jnz     .gx_sgid
    mov     al, '-'
    test    ebx, 0o10
    jz      .gx_emit
    mov     al, 'x'
    jmp     .gx_emit
.gx_sgid:
    mov     al, 'S'
    test    ebx, 0o10
    jz      .gx_emit
    mov     al, 's'
.gx_emit:
    call    out_char

    mov     al, '-'
    test    ebx, 0o4
    jz      .or
    mov     al, 'r'
.or:
    call    out_char
    mov     al, '-'
    test    ebx, 0o2
    jz      .ow
    mov     al, 'w'
.ow:
    call    out_char
    test    ebx, 0o1000
    jnz     .ox_sticky
    mov     al, '-'
    test    ebx, 0o1
    jz      .ox_emit
    mov     al, 'x'
    jmp     .ox_emit
.ox_sticky:
    mov     al, 'T'
    test    ebx, 0o1
    jz      .ox_emit
    mov     al, 't'
.ox_emit:
    call    out_char
    pop     rbx
    ret

out_char:
    push    rdx
    mov     rdx, [outlen]
    cmp     rdx, OUTBUF_SIZE
    jl      .store
    call    out_flush
    xor     rdx, rdx
.store:
    mov     [outbuf + rdx], al
    inc     rdx
    mov     [outlen], rdx
    pop     rdx
    ret

out_flush:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r11
    mov     rdx, [outlen]
    test    rdx, rdx
    jz      .empty
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, outbuf
    syscall
    mov     qword [outlen], 0
.empty:
    pop     r11
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret
