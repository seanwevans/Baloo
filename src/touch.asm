; src/touch.asm -- touch(1): create files and/or set their timestamps.
; Usage: touch [-cam] [-t [[CC]YY]MMDDhhmm[.SS]] [-d DATE] [-r REF] FILE...
;
; Without a time option the current time is used. -t and -d are interpreted in
; UTC; -r copies both tspec from a reference file. -a/-m limit the change to the
; access/modification time. A file operand of "-" updates the stdout fd.

    %include "include/sysdefs.inc"

    %define UTIME_NOW  0x3fffffff
    %define UTIME_OMIT 0x3ffffffe

section .bss
    stat_buf    resb 160
tspec       resq 4                  ;two timespecs: [atv_sec,atv_nsec,mtv_sec,mtv_nsec]
    files       resq 256
    nfiles      resq 1
    nocreate    resb 1
    a_flag      resb 1
    m_flag      resb 1
    tmode       resq 1                  ;0 now, 1 explicit value, 2 reference
    at_sec      resq 1
    at_nsec     resq 1
    mt_sec      resq 1
    mt_nsec     resq 1
    t_year      resq 1
    t_mon       resq 1
    t_day       resq 1
    t_hour      resq 1
    t_min       resq 1
    t_sec       resq 1
    t_nsec      resq 1

section .data
usage_msg   db "Usage: touch [-cam] [-t STAMP] [-d DATE] [-r REF] FILE...", 10
    usage_len   equ $ - usage_msg
    dash        db "-", 0

section .text
global _start

_start:
    mov     byte [nocreate], 0
    mov     byte [a_flag], 0
    mov     byte [m_flag], 0
    mov     qword [tmode], 0
    mov     qword [nfiles], 0

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    je      after_parse
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .file
    cmp     byte [rdi + 1], 0
    je      .file                       ;lone "-" is a filename
    lea     rsi, [rdi + 1]
.opt:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 'c'
    je      .set_c
    cmp     al, 'a'
    je      .set_a
    cmp     al, 'm'
    je      .set_m
    cmp     al, 't'
    je      .opt_t
    cmp     al, 'd'
    je      .opt_d
    cmp     al, 'r'
    je      .opt_r
    inc     rsi                         ;ignore -h and unknown
    jmp     .opt
.set_c:
    mov     byte [nocreate], 1
    inc     rsi
    jmp     .opt
.set_a:
    mov     byte [a_flag], 1
    inc     rsi
    jmp     .opt
.set_m:
    mov     byte [m_flag], 1
    inc     rsi
    jmp     .opt
.opt_t:
    call    optarg
    call    parse_t
    call    civil_store
    mov     qword [tmode], 1
    jmp     .nextarg
.opt_d:
    call    optarg
    call    parse_d
    call    civil_store
    mov     qword [tmode], 1
    jmp     .nextarg
.opt_r:
    call    optarg
    call    ref_store
    mov     qword [tmode], 2
    jmp     .nextarg
.file:
    mov     rcx, [nfiles]
    mov     [files + rcx*8], rdi
    inc     qword [nfiles]
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

after_parse:
    cmp     qword [nfiles], 0
    jne     build_times
    write   STDERR_FILENO, usage_msg, usage_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall

build_times:
;determine which tspec change
    movzx   eax, byte [a_flag]
    movzx   ecx, byte [m_flag]
;change_atime = a || (!a && !m); change_mtime = m || (!a && !m)
    mov     r8, 1                       ;change_atime
    mov     r9, 1                       ;change_mtime
    test    al, al
    jnz     .have
    test    cl, cl
    jz      .have                       ;neither -> both change
    xor     r8, r8                      ;only -m
.have:
    test    cl, cl
    jnz     .have2
    test    al, al
    jz      .have2
    xor     r9, r9                      ;only -a
.have2:
;tspec[0] = atime
    test    r8, r8
    jz      .a_omit
    cmp     qword [tmode], 0
    jne     .a_val
    mov     qword [tspec + 0], 0
    mov     qword [tspec + 8], UTIME_NOW
    jmp     .mtime
.a_val:
    mov     rax, [at_sec]
    mov     [tspec + 0], rax
    mov     rax, [at_nsec]
    mov     [tspec + 8], rax
    jmp     .mtime
.a_omit:
    mov     qword [tspec + 0], 0
    mov     qword [tspec + 8], UTIME_OMIT
.mtime:
    test    r9, r9
    jz      .m_omit
    cmp     qword [tmode], 0
    jne     .m_val
    mov     qword [tspec + 16], 0
    mov     qword [tspec + 24], UTIME_NOW
    jmp     .apply
.m_val:
    mov     rax, [mt_sec]
    mov     [tspec + 16], rax
    mov     rax, [mt_nsec]
    mov     [tspec + 24], rax
    jmp     .apply
.m_omit:
    mov     qword [tspec + 16], 0
    mov     qword [tspec + 24], UTIME_OMIT

.apply:
    xor     r14, r14
.floop:
    cmp     r14, [nfiles]
    jge     .done
    mov     rdi, [files + r14*8]
    call    touch_one
    inc     r14
    jmp     .floop
.done:
    xor     rdi, rdi
    mov     rax, SYS_EXIT
    syscall

; touch_one: rdi = filename. "-" targets the stdout fd; otherwise create the
; file (unless -c) then set its tspec.
touch_one:
    mov     r15, rdi
    cmp     byte [rdi], '-'
    jne     .regular
    cmp     byte [rdi + 1], 0
    jne     .regular
;futimens(1, tspec) == utimensat(1, NULL, tspec, 0)
    mov     rax, SYS_UTIMENSAT
    mov     rdi, STDOUT_FILENO
    xor     rsi, rsi
    mov     rdx, tspec
    xor     r10, r10
    syscall
    ret
.regular:
    cmp     byte [nocreate], 1
    je      .settime
    mov     rax, SYS_OPEN
    mov     rsi, O_WRONLY | O_CREAT
    mov     rdx, 0o666
    syscall
    test    rax, rax
    js      .settime
    mov     rdi, rax
    mov     rax, SYS_CLOSE
    syscall
.settime:
    mov     rax, SYS_UTIMENSAT
    mov     rdi, AT_FDCWD
    mov     rsi, r15
    mov     rdx, tspec
    xor     r10, r10
    syscall
    ret

; optarg: the option value is the rest of the current arg, else the next argv.
; Returns the pointer in rax; consumes the next argv (r13/r12) when needed. The
; caller jumps to .nextarg afterwards, so the option scan does not resume.
optarg:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .here
    add     r13, 8
    dec     r12
    mov     rax, [r13]
    ret
.here:
    mov     rax, rsi
    ret

; parse_t: rax -> broken-down time in t_* ([[CC]YY]MMDDhhmm[.SS]).
parse_t:
    mov     rdi, rax
    xor     r8, r8                      ;digit count
.len:
    movzx   ecx, byte [rdi + r8]
    cmp     cl, '0'
    jb      .lend
    cmp     cl, '9'
    ja      .lend
    inc     r8
    jmp     .len
.lend:
    mov     qword [t_sec], 0
    mov     qword [t_nsec], 0
    cmp     byte [rdi + r8], '.'
    jne     .nosec
    lea     rsi, [rdi + r8 + 1]
    call    d2_at
    mov     [t_sec], rax
.nosec:
    mov     r9, r8
    sub     r9, 8                       ;prefix (year) digit count
    lea     r10, [rdi + r9]             ;MMDDhhmm
    mov     rsi, r10
    call    d2_at
    mov     [t_mon], rax
    lea     rsi, [r10 + 2]
    call    d2_at
    mov     [t_day], rax
    lea     rsi, [r10 + 4]
    call    d2_at
    mov     [t_hour], rax
    lea     rsi, [r10 + 6]
    call    d2_at
    mov     [t_min], rax
    cmp     r9, 4
    je      .y4
    cmp     r9, 2
    je      .y2
    call    current_year
    mov     [t_year], rax
    ret
.y4:
    mov     rsi, rdi
    call    d4_at
    mov     [t_year], rax
    ret
.y2:
    mov     rsi, rdi
    call    d2_at
    cmp     rax, 69
    jae     .y19
    add     rax, 2000
    jmp     .ys
.y19:
    add     rax, 1900
.ys:
    mov     [t_year], rax
    ret

; parse_d: rax -> broken-down time (YYYY-MM-DD[T ]HH:MM:SS[.frac][Z]).
parse_d:
    mov     rdi, rax
    mov     rsi, rdi
    call    d4_at
    mov     [t_year], rax
    lea     rsi, [rdi + 5]
    call    d2_at
    mov     [t_mon], rax
    lea     rsi, [rdi + 8]
    call    d2_at
    mov     [t_day], rax
    lea     rsi, [rdi + 11]
    call    d2_at
    mov     [t_hour], rax
    lea     rsi, [rdi + 14]
    call    d2_at
    mov     [t_min], rax
    lea     rsi, [rdi + 17]
    call    d2_at
    mov     [t_sec], rax
    mov     qword [t_nsec], 0
    cmp     byte [rdi + 19], '.'
    jne     .done
    lea     rsi, [rdi + 20]
    xor     rax, rax
    xor     rcx, rcx
.fl:
    movzx   r8d, byte [rsi]
    sub     r8b, '0'
    cmp     r8b, 9
    ja      .pad
    imul    rax, rax, 10
    movzx   r8, r8b
    add     rax, r8
    inc     rcx
    inc     rsi
    cmp     rcx, 9
    jl      .fl
.pad:
    cmp     rcx, 9
    jge     .store
    imul    rax, rax, 10
    inc     rcx
    jmp     .pad
.store:
    mov     [t_nsec], rax
.done:
    ret

; civil_store: convert t_* (UTC) to an epoch and copy to both time slots.
civil_store:
    call    civil_to_epoch
    mov     [at_sec], rax
    mov     [mt_sec], rax
    mov     rax, [t_nsec]
    mov     [at_nsec], rax
    mov     [mt_nsec], rax
    ret

; civil_to_epoch: t_year/mon/day/hour/min/sec -> rax epoch seconds (UTC).
civil_to_epoch:
    mov     rax, [t_year]
    cmp     qword [t_mon], 2
    ja      .m1
    dec     rax
.m1:
    mov     r8, rax                     ;y
    xor     rdx, rdx
    mov     rcx, 400
    div     rcx
    mov     r9, rax                     ;era
    imul    rax, rax, 400
    mov     r10, r8
    sub     r10, rax                    ;yoe
    mov     rax, [t_mon]
    cmp     rax, 2
    jbe     .mle2
    sub     rax, 3
    jmp     .mc
.mle2:
    add     rax, 9
.mc:
    imul    rax, rax, 153
    add     rax, 2
    xor     rdx, rdx
    mov     rcx, 5
    div     rcx
    add     rax, [t_day]
    dec     rax
    mov     r11, rax                    ;doy
    mov     rax, r10
    imul    rax, rax, 365
    mov     rsi, rax
    mov     rax, r10
    xor     rdx, rdx
    mov     rcx, 4
    div     rcx
    add     rsi, rax
    mov     rax, r10
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    sub     rsi, rax
    add     rsi, r11                    ;doe
    mov     rax, r9
    imul    rax, rax, 146097
    add     rax, rsi
    sub     rax, 719468                 ;days since epoch
    imul    rax, rax, 86400
    mov     rcx, [t_hour]
    imul    rcx, rcx, 3600
    add     rax, rcx
    mov     rcx, [t_min]
    imul    rcx, rcx, 60
    add     rax, rcx
    add     rax, [t_sec]
    ret

; current_year: today's UTC year in rax.
current_year:
    mov     rax, SYS_TIME
    xor     rdi, rdi
    syscall
    xor     rdx, rdx
    mov     rcx, 86400
    div     rcx                         ;rax = days
    add     rax, 719468
    xor     rdx, rdx
    mov     rcx, 146097
    div     rcx
    mov     r8, rax                     ;era
    mov     r9, rdx                     ;doe
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
    mov     rsi, rax
    mov     rax, r9
    sub     rax, r10
    add     rax, r11
    sub     rax, rsi
    xor     rdx, rdx
    mov     rcx, 365
    div     rcx                         ;yoe
    mov     rcx, r8
    imul    rcx, rcx, 400
    add     rax, rcx                    ;y0 = yoe + era*400
    ret

; ref_store: rax = reference filename -> copy its atime/mtime.
ref_store:
    mov     rdi, rax
    mov     rsi, stat_buf
    mov     rax, SYS_STAT
    syscall
    mov     rax, [stat_buf + 72]        ;st_atim.tv_sec
    mov     [at_sec], rax
    mov     rax, [stat_buf + 80]        ;st_atim.tv_nsec
    mov     [at_nsec], rax
    mov     rax, [stat_buf + 88]        ;st_mtim.tv_sec
    mov     [mt_sec], rax
    mov     rax, [stat_buf + 96]        ;st_mtim.tv_nsec
    mov     [mt_nsec], rax
    ret

; d2_at / d4_at: parse 2 or 4 decimal digits at rsi -> rax.
d2_at:
    movzx   eax, byte [rsi]
    sub     eax, '0'
    imul    eax, eax, 10
    movzx   ecx, byte [rsi + 1]
    sub     ecx, '0'
    add     eax, ecx
    ret
d4_at:
    movzx   eax, byte [rsi]
    sub     eax, '0'
    imul    eax, eax, 10
    movzx   ecx, byte [rsi + 1]
    sub     ecx, '0'
    add     eax, ecx
    imul    eax, eax, 10
    movzx   ecx, byte [rsi + 2]
    sub     ecx, '0'
    add     eax, ecx
    imul    eax, eax, 10
    movzx   ecx, byte [rsi + 3]
    sub     ecx, '0'
    add     eax, ecx
    ret
