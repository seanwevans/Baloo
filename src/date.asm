; src/date.asm -- date(1): show or set the date and time.
; Usage: date [-u] [-r FILE] [-d DATE] [-I[SPEC]] [+FORMAT]
;
; Times are held as seconds since the epoch plus nanoseconds. Converting to
; and from a wall clock reads the zone file and takes the offset in effect at
; that instant, so a date either side of a daylight saving change comes out
; right and carries the abbreviation that was in force -- CET or CEST, PST or
; PDT.
;
; Going the other way is a fixed point: the offset depends on the very
; instant being computed. The wall clock is first read as though it were UTC,
; the offset at that guess is taken, and the guess corrected once, which
; settles everywhere except inside the hour a transition skips.
;
; -d accepts an @epoch, an ISO date with an optional time and zone, a bare
; time of day, and date's own output format, so its output can be fed back
; in. A leading TZ="..." picks the zone the date is read in, independently of
; the zone it is printed in.

    %include "include/sysdefs.inc"

    %define SYS_CLOCK_GETTIME_ID 228
    %define SYS_SETTIMEOFDAY 164

    %define TZCAP 65536
    %define OUTCAP 8192
    %define PATHCAP 4096
    %define STRCAP 1024

    %define ST_MTIME 88
    %define ST_MTIMENS 96

section .bss
    tzbuf       resb TZCAP
    tzpath      resb PATHCAP
    tzname_buf  resb 256
    outbuf      resb OUTCAP
    numbuf      resb 64
    abbrbuf     resb 64
    parsebuf    resb STRCAP
    stbuf       resb 160
    tsbuf       resq 2
    outlen      resq 1
    tz_len      resq 1
    tz_timecnt  resq 1
    tz_typecnt  resq 1
    tz_transoff resq 1
    tz_idxoff   resq 1
    tz_ttoff    resq 1
    tz_abbroff  resq 1
    tz_blocklen resq 1
    tz_wide     resq 1
    cur_off     resq 1
    cur_abbr    resq 1
    epoch       resq 1
    nanos       resq 1
    cv_year     resq 1
    cv_mon      resq 1
    cv_day      resq 1
    cv_hour     resq 1
    cv_min      resq 1
    cv_sec      resq 1
    cv_wday     resq 1
    cv_yday     resq 1
    in_year     resq 1
    in_mon      resq 1
    in_day      resq 1
    in_hour     resq 1
    in_min      resq 1
    in_sec      resq 1
    in_nanos    resq 1
    in_offset   resq 1
    have_offset resq 1
    dstring     resq 1
    dformat     resq 1
    have_epoch  resq 1
    rfile       resq 1
    format      resq 1
    isospec     resq 1
    setarg      resq 1
    envp        resq 1
    opt_utc     resb 1
    have_iso    resb 1
    tz_loaded   resb 1

section .data
    tz_env      db "TZ", 0
    zoneinfo    db "/usr/share/zoneinfo/", 0
    localtime_p db "/etc/localtime", 0
    utc_name    db "UTC", 0

def_format  db "%a %b %e %H:%M:%S %Z %Y", 0
    wdays       db "SunMonTueWedThuFriSat"
    wdays_full  db "Sunday", 0, "Monday", 0, "Tuesday", 0, "Wednesday", 0
    db "Thursday", 0, "Friday", 0, "Saturday", 0
    months      db "JanFebMarAprMayJunJulAugSepOctNovDec"
    months_full db "January", 0, "February", 0, "March", 0, "April", 0
    db "May", 0, "June", 0, "July", 0, "August", 0
    db "September", 0, "October", 0, "November", 0, "December", 0
    am_str      db "AM", 0
    pm_str      db "PM", 0
    utc_abbr    db "UTC", 0

e_baddate   db "date: bad date", 10
    e_baddate_len equ $ - e_baddate
e_usage     db "Usage: date [-u] [-r FILE] [-d DATE] [-I[SPEC]] [+FORMAT]", 10
    e_usage_len equ $ - e_usage

section .text
global _start

_start:
    mov     rax, [rsp]                  ;argc
    lea     rcx, [rsp + rax * 8 + 16]
    mov     [envp], rcx
    mov     r12, rax
    lea     r13, [rsp + 16]
    dec     r12

parse:
    cmp     r12, 0
    jle     run
    mov     rdi, [r13]
    test    rdi, rdi
    jz      run
    cmp     byte [rdi], '+'
    je      .setformat
    cmp     byte [rdi], '-'
    jne     .operand
    cmp     byte [rdi + 1], 0
    je      .operand
    lea     rsi, [rdi + 1]
.flag:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .next
    inc     rsi
    cmp     al, 'u'
    je      .f_utc
    cmp     al, 'd'
    je      .f_d
    cmp     al, 'r'
    je      .f_r
    cmp     al, 'D'
    je      .f_D
    cmp     al, 'I'
    je      .f_I
    jmp     usage
.f_utc:
    mov     byte [opt_utc], 1
    jmp     .flag
.f_d:
    call    opt_value
    mov     [dstring], rdx
    jmp     .next
.f_r:
    call    opt_value
    mov     [rfile], rdx
    jmp     .next
.f_D:
    call    opt_value
    mov     [dformat], rdx              ;the shape -d's argument is written in
    jmp     .next
.f_I:
    mov     byte [have_iso], 1
    mov     [isospec], rsi              ;the rest of the bundle is the spec
    jmp     .next
.setformat:
    lea     rax, [rdi + 1]
    mov     [format], rax
    jmp     .next
.operand:
    mov     [setarg], rdi
.next:
    add     r13, 8
    dec     r12
    jmp     parse

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
    mov     rsi, e_usage
    mov     rdx, e_usage_len
    syscall
    exit    1

bad_date:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, e_baddate
    mov     rdx, e_baddate_len
    syscall
    exit    1

; ---------------------------------------------------------------------------
; run: work out which instant is meant, then print it.
; ---------------------------------------------------------------------------
run:
    mov     rax, [rfile]
    test    rax, rax
    jz      .fromd
    mov     rax, SYS_STAT
    mov     rdi, [rfile]
    mov     rsi, stbuf
    syscall
    test    rax, rax
    js      bad_date
    mov     rax, [stbuf + ST_MTIME]
    mov     [epoch], rax
    mov     rax, [stbuf + ST_MTIMENS]
    mov     [nanos], rax
    jmp     .output
.fromd:
    mov     rax, [dstring]
    test    rax, rax
    jz      .fromset
    mov     rdi, rax
    call    parse_date
    jmp     .output
.fromset:
    mov     rax, [setarg]
    test    rax, rax
    jz      .now
    mov     rdi, rax
    call    parse_setarg                ;refuses anything it cannot read
    jmp     .output
.now:
    mov     rax, SYS_CLOCK_GETTIME_ID
    xor     rdi, rdi
    mov     rsi, tsbuf
    syscall
    mov     rax, [tsbuf]
    mov     [epoch], rax
    mov     rax, [tsbuf + 8]
    mov     [nanos], rax
.output:
    call    load_output_zone
    mov     rdi, [epoch]
    call    zone_at                     ;-> cur_off, cur_abbr
    mov     rdi, [epoch]
    add     rdi, [cur_off]
    call    civil_from_epoch
    cmp     byte [have_iso], 0
    jne     .iso
    mov     rsi, [format]
    test    rsi, rsi
    jnz     .render
    mov     rsi, def_format
.render:
    call    strftime
    mov     al, WHITESPACE_NL
    call    out_char
    jmp     .flush
.iso:
    call    print_iso
    mov     al, WHITESPACE_NL
    call    out_char
.flush:
    call    out_flush
    exit    0

; ---------------------------------------------------------------------------
; load_output_zone: the zone the answer is printed in -- UTC under -u, and
; whatever TZ names otherwise.
; ---------------------------------------------------------------------------
load_output_zone:
    cmp     byte [opt_utc], 0
    je      .fromenv
xor     rdi, rdi                    ;no zone file: fixed at UTC
    jmp     tz_load
.fromenv:
    mov     rdi, tz_env
    call    getenv_value
    mov     rdi, rax
    jmp     tz_load

; ---------------------------------------------------------------------------
; parse_date: read the -d argument. A leading TZ="..." names the zone the
; date is written in, which need not be the zone it will be printed in.
; ---------------------------------------------------------------------------
parse_date:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     qword [have_offset], 0
    mov     qword [in_nanos], 0
    xor     r12, r12                    ;zone name for reading, if any
    call    skip_spaces_rbx
; TZ="NAME" in front of the date picks the zone it is read in
    cmp     byte [rbx], 'T'
    jne     .nozone
    cmp     byte [rbx + 1], 'Z'
    jne     .nozone
    cmp     byte [rbx + 2], '='
    jne     .nozone
    add     rbx, 3
    mov     r12, tzname_buf
    xor     rcx, rcx
    cmp     byte [rbx], '"'
    jne     .zoneplain
    inc     rbx
.zonequoted:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .zonedone
    cmp     al, '"'
    je      .zoneclose
    mov     [tzname_buf + rcx], al
    inc     rcx
    inc     rbx
    jmp     .zonequoted
.zoneclose:
    inc     rbx
    jmp     .zonedone
.zoneplain:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .zonedone
    cmp     al, WHITESPACE_SPACE
    je      .zonedone
    mov     [tzname_buf + rcx], al
    inc     rcx
    inc     rbx
    jmp     .zoneplain
.zonedone:
    mov     byte [tzname_buf + rcx], 0
    call    skip_spaces_rbx
.nozone:
; @SECONDS is an instant already, with no zone to apply
    cmp     byte [rbx], '@'
    jne     .civil
    inc     rbx
    mov     rdi, rbx
    call    parse_epoch_arg
    pop     r12
    pop     rbx
    ret
.civil:
    mov     rdi, r12
    call    load_parse_zone
    mov     rdi, rbx
    cmp     qword [dformat], 0
    je      .plain
    mov     rsi, [dformat]
    call    parse_by_format
    pop     r12
    pop     rbx
    ret
.plain:
    call    parse_civil
    pop     r12
    pop     rbx
    ret

; load_parse_zone: the zone a written date is read in. Under -u, or with no
; name, that is the same zone the answer is printed in.
load_parse_zone:
    test    rdi, rdi
    jnz     tz_load
    cmp     byte [opt_utc], 0
    jne     .utc
    mov     rdi, tz_env
    call    getenv_value
    mov     rdi, rax
    jmp     tz_load
.utc:
    xor     rdi, rdi
    jmp     tz_load

; parse_epoch_arg: "@SECONDS[.FRACTION]" and nothing else after it.
parse_epoch_arg:
    push    rbx
    mov     rbx, rdi
    xor     r8, r8                      ;negative?
    cmp     byte [rbx], '-'
    jne     .digits
    mov     r8, 1
    inc     rbx
.digits:
    xor     rax, rax
    xor     r9, r9
.digit:
    movzx   rcx, byte [rbx]
    sub     cl, '0'
    cmp     cl, 9
    ja      .fraction
    imul    rax, rax, 10
    add     rax, rcx
    inc     r9
    inc     rbx
    jmp     .digit
.fraction:
    test    r9, r9
    jz      bad_date
    test    r8, r8
    jz      .store
    neg     rax
.store:
    mov     [epoch], rax
    mov     qword [nanos], 0
    cmp     byte [rbx], '.'
    jne     .end
    inc     rbx
    xor     rax, rax
    xor     r9, r9
.fracdigit:
    movzx   rcx, byte [rbx]
    sub     cl, '0'
    cmp     cl, 9
    ja      .fracscale
    cmp     r9, 9
    jae     .fracskip
    imul    rax, rax, 10
    add     rax, rcx
    inc     r9
.fracskip:
    inc     rbx
    jmp     .fracdigit
.fracscale:
    cmp     r9, 9
    jae     .fracstore
    imul    rax, rax, 10
    inc     r9
    jmp     .fracscale
.fracstore:
    mov     [nanos], rax
.end:
    call    skip_spaces_rbx
    cmp     byte [rbx], 0
    jne     bad_date                    ;"@0x123" is not a time
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; parse_civil: an ISO date, a bare time of day, or date's own output. Each
; leaves the fields in in_* and the result in epoch.
; ---------------------------------------------------------------------------
parse_civil:
    push    rbx
    mov     rbx, rdi
    call    default_today
    call    skip_spaces_rbx
    mov     rdi, rbx
    call    try_posix                   ;MMDDhhmm[[CC]YY][.ss], all digits
    test    al, al
    jnz     .finish
    mov     rdi, rbx
    call    try_month_name              ;-> al = 1 when it looked like our own
    test    al, al
    jnz     .finish
    mov     rdi, rbx
    call    try_iso
    test    al, al
    jnz     .finish
    mov     rdi, rbx
    call    try_time_only
    test    al, al
    jnz     .finish
    jmp     bad_date
.finish:
    call    finish_civil
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; try_posix: the POSIX shape MMDDhhmm[[CC]YY][.ss], which is nothing but
; digits. Eight of them leave the year as today's, ten give a two-digit year
; and twelve give it in full. al = 1 when it fitted.
; ---------------------------------------------------------------------------
try_posix:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    xor     rcx, rcx
.grab:
    movzx   eax, byte [rbx + rcx]
    sub     al, '0'
    cmp     al, 9
    ja      .grabbed
    cmp     rcx, 12
    jae     .no
    mov     [parsebuf + rcx], al
    inc     rcx
    jmp     .grab
.grabbed:
    cmp     rcx, 8
    je      .lenok
    cmp     rcx, 10
    je      .lenok
    cmp     rcx, 12
    jne     .no
.lenok:
    mov     r12, rcx                    ;how many digits there were
    add     rbx, rcx
    mov     qword [in_sec], 0
    cmp     byte [rbx], '.'
    jne     .nosec
    inc     rbx
    movzx   eax, byte [rbx]
    sub     al, '0'
    cmp     al, 9
    ja      .no
    movzx   r13d, al
    imul    r13, r13, 10
    movzx   eax, byte [rbx + 1]
    sub     al, '0'
    cmp     al, 9
    ja      .no
    movzx   eax, al
    add     r13, rax
    mov     [in_sec], r13
    add     rbx, 2
.nosec:
    cmp     byte [rbx], 0
    jne     .no
    xor     rdi, rdi
    call    posix_pair
    mov     [in_mon], rax
    mov     rdi, 2
    call    posix_pair
    mov     [in_day], rax
    mov     rdi, 4
    call    posix_pair
    mov     [in_hour], rax
    mov     rdi, 6
    call    posix_pair
    mov     [in_min], rax
    cmp     r12, 8
    je      .checked
    cmp     r12, 10
    je      .twodigit
    mov     rdi, 8
    call    posix_pair
    imul    rax, rax, 100
    mov     r13, rax
    mov     rdi, 10
    call    posix_pair
    add     rax, r13
    mov     [in_year], rax
    jmp     .checked
.twodigit:
    mov     rdi, 8
    call    posix_pair
    cmp     rax, 69
    jb      .after2000
    add     rax, 1900
    mov     [in_year], rax
    jmp     .checked
.after2000:
    add     rax, 2000
    mov     [in_year], rax
.checked:
    cmp     qword [in_mon], 1
    jb      .no
    cmp     qword [in_mon], 12
    ja      .no
    cmp     qword [in_day], 1
    jb      .no
    cmp     qword [in_day], 31
    ja      .no
    cmp     qword [in_hour], 23
    ja      .no
    cmp     qword [in_min], 59
    ja      .no
    cmp     qword [in_sec], 60
    ja      .no
    mov     al, 1
    jmp     .out
.no:
    xor     al, al
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; posix_pair: the two digits parsebuf holds at rdi, as a number.
posix_pair:
    movzx   eax, byte [parsebuf + rdi]
    imul    eax, eax, 10
    movzx   edx, byte [parsebuf + rdi + 1]
    add     eax, edx
    ret

; ---------------------------------------------------------------------------
; parse_by_format: read the -d argument in the shape -D gave, rather than
; guessing at it. Whitespace in the format matches any run of whitespace, and
; anything else outside a conversion must appear literally.
; ---------------------------------------------------------------------------
parse_by_format:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     qword [have_epoch], 0
    call    default_today
.step:
    movzx   eax, byte [r12]
    test    al, al
    jz      .done
    cmp     al, '%'
    je      .conv
    cmp     al, WHITESPACE_SPACE
    je      .space
    cmp     al, WHITESPACE_TAB
    je      .space
    cmp     al, [rbx]
    jne     bad_date
    inc     rbx
    inc     r12
    jmp     .step
.space:
    inc     r12
    call    skip_spaces_rbx
    jmp     .step
.conv:
    inc     r12
    movzx   eax, byte [r12]
    test    al, al
    jz      bad_date
    inc     r12
    cmp     al, '%'
    je      .pct
    cmp     al, 'n'
    je      .white
    cmp     al, 't'
    je      .white
    cmp     al, 'Y'
    je      .year
    cmp     al, 'y'
    je      .shortyear
    cmp     al, 'm'
    je      .mon
    cmp     al, 'd'
    je      .day
    cmp     al, 'e'
    je      .day
    cmp     al, 'H'
    je      .hour
    cmp     al, 'M'
    je      .minute
    cmp     al, 'S'
    je      .second
    cmp     al, 's'
    je      .epochsecs
    cmp     al, 'b'
    je      .monname
    cmp     al, 'B'
    je      .monname
    cmp     al, 'h'
    je      .monname
    cmp     al, 'a'
    je      .wdayname
    cmp     al, 'A'
    je      .wdayname
    cmp     al, 'z'
    je      .zone
    cmp     al, 'Z'
    je      .zone
    cmp     al, 'T'
    je      .clock
    cmp     al, 'F'
    je      .isodate
    jmp     bad_date
.pct:
    cmp     byte [rbx], '%'
    jne     bad_date
    inc     rbx
    jmp     .step
.white:
    call    skip_spaces_rbx
    jmp     .step
.year:
    call    skip_spaces_rbx
    mov     r13, 4
    call    scan_digits_n
    test    rcx, rcx
    jz      bad_date
    mov     [in_year], rax
    jmp     .step
.shortyear:
    call    field2
    cmp     rax, 69
    jb      .yy2000
    add     rax, 1900
    mov     [in_year], rax
    jmp     .step
.yy2000:
    add     rax, 2000
    mov     [in_year], rax
    jmp     .step
.mon:
    call    field2
    mov     [in_mon], rax
    jmp     .step
.day:
    call    field2
    mov     [in_day], rax
    jmp     .step
.hour:
    call    field2
    mov     [in_hour], rax
    jmp     .step
.minute:
    call    field2
    mov     [in_min], rax
    jmp     .step
.second:
    call    field2
    mov     [in_sec], rax
    jmp     .step
.epochsecs:
    call    skip_spaces_rbx
    xor     r10, r10
    cmp     byte [rbx], '-'
    jne     .unsigned
    mov     r10, 1
    inc     rbx
.unsigned:
    call    scan_digits
    test    rcx, rcx
    jz      bad_date
    test    r10, r10
    jz      .keepepoch
    neg     rax
.keepepoch:
    mov     [epoch], rax
    mov     qword [have_epoch], 1
    jmp     .step
.monname:
    call    skip_spaces_rbx
    mov     rdi, rbx
    call    month_by_name
    test    rax, rax
    jz      bad_date
    mov     [in_mon], rax
    call    skip_alpha_word
    jmp     .step
.wdayname:
    call    skip_spaces_rbx
    call    skip_alpha_word
    jmp     .step
.zone:
    call    scan_zone
    jmp     .step
.clock:
    call    field2
    mov     [in_hour], rax
    call    want_colon
    call    field2
    mov     [in_min], rax
    call    want_colon
    call    field2
    mov     [in_sec], rax
    jmp     .step
.isodate:
    call    skip_spaces_rbx
    mov     r13, 4
    call    scan_digits_n
    test    rcx, rcx
    jz      bad_date
    mov     [in_year], rax
    call    want_dash
    call    field2
    mov     [in_mon], rax
    call    want_dash
    call    field2
    mov     [in_day], rax
    jmp     .step
.done:
    call    skip_spaces_rbx
    cmp     byte [rbx], 0
    jne     bad_date
    cmp     qword [have_epoch], 0
    je      .civil
    mov     qword [nanos], 0
    jmp     .out
.civil:
    call    finish_civil
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; field2: one or two digits at rbx, after any spaces padding them.
field2:
    call    skip_spaces_rbx
    mov     r13, 2
    call    scan_digits_n
    test    rcx, rcx
    jz      bad_date
    ret

want_colon:
cmp     byte [rbx], ':'
    jne     bad_date
    inc     rbx
    ret

want_dash:
    cmp     byte [rbx], '-'
    jne     bad_date
    inc     rbx
    ret

; scan_digits_n: at most r13 digits at rbx -> rax, with rcx of them read.
scan_digits_n:
    xor     rax, rax
    xor     rcx, rcx
.digit:
    cmp     rcx, r13
    jae     .out
    movzx   rdx, byte [rbx]
    sub     dl, '0'
    cmp     dl, 9
    ja      .out
    imul    rax, rax, 10
    add     rax, rdx
    inc     rcx
    inc     rbx
    jmp     .digit
.out:
    ret

; default_today: fields not given default to today, so "-d 12:34" means today
; at that time.
default_today:
    push    rbx
    mov     rax, SYS_CLOCK_GETTIME_ID
    xor     rdi, rdi
    mov     rsi, tsbuf
    syscall
    mov     rdi, [tsbuf]
    push    rdi
    call    zone_at
    pop     rdi
    add     rdi, [cur_off]
    call    civil_from_epoch
    mov     rax, [cv_year]
    mov     [in_year], rax
    mov     rax, [cv_mon]
    mov     [in_mon], rax
    mov     rax, [cv_day]
    mov     [in_day], rax
    mov     qword [in_hour], 0
    mov     qword [in_min], 0
    mov     qword [in_sec], 0
    pop     rbx
    ret

; finish_civil: fold the fields into an instant, applying an explicit offset
; when the text carried one and the zone's own offset otherwise.
finish_civil:
    mov     rdi, [in_year]
    mov     rsi, [in_mon]
    mov     rdx, [in_day]
    call    days_from_civil
    imul    rax, rax, 86400
    mov     rcx, [in_hour]
    imul    rcx, rcx, 3600
    add     rax, rcx
    mov     rcx, [in_min]
    imul    rcx, rcx, 60
    add     rax, rcx
    add     rax, [in_sec]
    cmp     qword [have_offset], 0
    je      .zone
    sub     rax, [in_offset]
    mov     [epoch], rax
    mov     rcx, [in_nanos]
    mov     [nanos], rcx
    ret
.zone:
; the offset depends on the instant being computed, so take the offset at the
; wall clock read as UTC and correct the guess once
    push    rax
    mov     rdi, rax
    call    zone_at
    pop     rax
    mov     rcx, [cur_off]
    push    rax
    push    rcx
    sub     rax, rcx
    mov     rdi, rax
    call    zone_at
    pop     rcx
    pop     rax
    sub     rax, [cur_off]
    mov     [epoch], rax
    mov     rcx, [in_nanos]
    mov     [nanos], rcx
    ret

; ---------------------------------------------------------------------------
; try_iso: "YYYY-MM-DD[[T| ]HH:MM[:SS[.frac]]][ZONE]". al = 1 when it fitted.
; ---------------------------------------------------------------------------
try_iso:
    push    rbx
    mov     rbx, rdi
    call    scan_digits                 ;-> rax value, rcx digits
    cmp     rcx, 4
    jb      .no
    mov     [in_year], rax
    cmp     byte [rbx], '-'
    jne     .no
    inc     rbx
    call    scan_digits
    test    rcx, rcx
    jz      .no
    mov     [in_mon], rax
    cmp     byte [rbx], '-'
    jne     .no
    inc     rbx
    call    scan_digits
    test    rcx, rcx
    jz      .no
    mov     [in_day], rax
    mov     qword [in_hour], 0
    mov     qword [in_min], 0
    mov     qword [in_sec], 0
    call    skip_spaces_rbx
    cmp     byte [rbx], 'T'
    jne     .maybetime
    inc     rbx
.maybetime:
    call    skip_spaces_rbx
    call    scan_digits
    test    rcx, rcx
    jz      .zone
    mov     [in_hour], rax
cmp     byte [rbx], ':'
    jne     .zone
    inc     rbx
    call    scan_digits
    test    rcx, rcx
    jz      .no
    mov     [in_min], rax
cmp     byte [rbx], ':'
    jne     .zone
    inc     rbx
    call    scan_digits
    test    rcx, rcx
    jz      .no
    mov     [in_sec], rax
    cmp     byte [rbx], '.'
    jne     .zone
    inc     rbx
    call    scan_fraction
    mov     [in_nanos], rax
.zone:
    call    scan_zone
    call    skip_spaces_rbx
    cmp     byte [rbx], 0
    jne     .no
    mov     al, 1
    pop     rbx
    ret
.no:
    xor     al, al
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; try_time_only: "HH:MM[:SS]", which means today at that time.
; ---------------------------------------------------------------------------
try_time_only:
    push    rbx
    mov     rbx, rdi
    call    scan_digits
    test    rcx, rcx
    jz      .no
cmp     byte [rbx], ':'
    jne     .no
    mov     [in_hour], rax
    inc     rbx
    call    scan_digits
    test    rcx, rcx
    jz      .no
    mov     [in_min], rax
    mov     qword [in_sec], 0
cmp     byte [rbx], ':'
    jne     .zone
    inc     rbx
    call    scan_digits
    test    rcx, rcx
    jz      .no
    mov     [in_sec], rax
    cmp     byte [rbx], '.'
    jne     .zone
    inc     rbx
    call    scan_fraction
    mov     [in_nanos], rax
.zone:
    call    scan_zone
    call    skip_spaces_rbx
    cmp     byte [rbx], 0
    jne     .no
    mov     al, 1
    pop     rbx
    ret
.no:
    xor     al, al
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; try_month_name: date's own output, "Wed Aug 26 23:20:18 CEST 2020", so what
; date prints can be handed straight back to it.
; ---------------------------------------------------------------------------
try_month_name:
    push    rbx
    push    r12
    mov     rbx, rdi
    call    skip_alpha_word             ;an optional weekday name
    call    skip_spaces_rbx
    mov     rdi, rbx
    call    month_by_name               ;-> rax = 1..12, or 0
    test    rax, rax
    jz      .no
    mov     [in_mon], rax
    add     rbx, 3
    call    skip_spaces_rbx
    call    scan_digits
    test    rcx, rcx
    jz      .no
    mov     [in_day], rax
    call    skip_spaces_rbx
    call    scan_digits
    test    rcx, rcx
    jz      .no
    mov     [in_hour], rax
cmp     byte [rbx], ':'
    jne     .no
    inc     rbx
    call    scan_digits
    test    rcx, rcx
    jz      .no
    mov     [in_min], rax
    mov     qword [in_sec], 0
cmp     byte [rbx], ':'
    jne     .year
    inc     rbx
    call    scan_digits
    test    rcx, rcx
    jz      .no
    mov     [in_sec], rax
.year:
    call    skip_spaces_rbx
    call    scan_zone                   ;an abbreviation, or a numeric offset
    call    skip_spaces_rbx
    call    scan_digits
    cmp     rcx, 4
    jb      .no
    mov     [in_year], rax
    call    skip_spaces_rbx
    cmp     byte [rbx], 0
    jne     .no
    mov     al, 1
    pop     r12
    pop     rbx
    ret
.no:
    xor     al, al
    pop     r12
    pop     rbx
    ret

; month_by_name: the month the three letters at rdi name, or 0.
month_by_name:
    push    r8
    push    r9
    push    r10
    xor     r8, r8                      ;the month being tried, 0..11
.month:
    cmp     r8, 12
    jae     .none
    mov     r9, r8
    imul    r9, r9, 3                   ;where its three letters sit
    xor     r10, r10
.letter:
    cmp     r10, 3
    jae     .found
    mov     rax, r9
    add     rax, r10
    movzx   eax, byte [months + rax]
    call    fold_upper_al
    mov     dl, al
    mov     rax, r10
    movzx   eax, byte [rdi + rax]
    call    fold_upper_al
    cmp     al, dl
    jne     .next
    inc     r10
    jmp     .letter
.found:
    lea     rax, [r8 + 1]
    jmp     .out
.next:
    inc     r8
    jmp     .month
.none:
    xor     rax, rax
.out:
    pop     r10
    pop     r9
    pop     r8
    ret

; fold_upper_al: al upper-cased, so names match whatever case they came in.
fold_upper_al:
    cmp     al, 'a'
    jb      .out
    cmp     al, 'z'
    ja      .out
    sub     al, 32
.out:
    ret

; ---------------------------------------------------------------------------
; scan_zone: a trailing zone, in any of the shapes date accepts. "Z", "UTC"
; and "GMT" mean no offset; a sign introduces one, where three digits are an
; hour and two minutes and four are two of each. Any other name is left to
; the zone already chosen, since the abbreviation alone does not identify it.
; ---------------------------------------------------------------------------
scan_zone:
    call    skip_spaces_rbx
    movzx   eax, byte [rbx]
    cmp     al, '+'
    je      .offset
    cmp     al, '-'
    je      .offset
    cmp     al, 'Z'
    je      .zulu
    cmp     al, 'U'
    je      .maybeutc
    cmp     al, 'G'
    je      .maybegmt
    cmp     al, 'A'
    jb      .out
    cmp     al, 'Z'
    jbe     .named
    cmp     al, 'a'
    jb      .out
    cmp     al, 'z'
    jbe     .named
.out:
    ret
.zulu:
    inc     rbx
    mov     qword [in_offset], 0
    mov     qword [have_offset], 1
    ret
.maybeutc:
    cmp     byte [rbx + 1], 'T'
    jne     .named
    cmp     byte [rbx + 2], 'C'
    jne     .named
    add     rbx, 3
    mov     qword [in_offset], 0
    mov     qword [have_offset], 1
    ret
.maybegmt:
    cmp     byte [rbx + 1], 'M'
    jne     .named
    cmp     byte [rbx + 2], 'T'
    jne     .named
    add     rbx, 3
    mov     qword [in_offset], 0
    mov     qword [have_offset], 1
    ret
.named:
call    skip_alpha_word             ;a local abbreviation: the zone stands
    ret
.offset:
    push    r12
    xor     r12, r12
    cmp     byte [rbx], '-'
    jne     .positive
    mov     r12, 1
.positive:
    inc     rbx
    call    skip_spaces_rbx
    call    scan_digits                 ;-> rax, rcx digits
    test    rcx, rcx
    jz      .noOffset
    mov     r8, rax
    mov     r9, rcx
    call    skip_spaces_rbx
cmp     byte [rbx], ':'
    je      .withcolon
; no colon: one or two digits are hours, three are H MM, four are HH MM
    cmp     r9, 3
    jb      .hoursonly
    cmp     r9, 3
    je      .threedigits
    mov     rax, r8
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    mov     r10, rax                    ;hours
    mov     r11, rdx                    ;minutes
    jmp     .combine
.threedigits:
    mov     rax, r8
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    mov     r10, rax
    mov     r11, rdx
    jmp     .combine
.hoursonly:
    mov     r10, r8
    xor     r11, r11
    jmp     .combine
.withcolon:
    inc     rbx
    call    skip_spaces_rbx
    mov     r10, r8
    call    scan_digits
    mov     r11, rax
.combine:
    imul    r10, r10, 3600
    imul    r11, r11, 60
    add     r10, r11
    test    r12, r12
    jz      .storeoffset
    neg     r10
.storeoffset:
    mov     [in_offset], r10
    mov     qword [have_offset], 1
    pop     r12
    ret
.noOffset:
    pop     r12
    ret

; ---------------------------------------------------------------------------
; strftime: render the format at rsi for the fields already in cv_*.
; ---------------------------------------------------------------------------
strftime:
    push    rbx
    push    r12
    mov     rbx, rsi
.scan:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .out
    inc     rbx
    cmp     al, '%'
    jne     .literal
    movzx   eax, byte [rbx]
    test    al, al
    jz      .trailing                   ;a lone trailing % prints as itself
; %N may be preceded by how many digits are wanted
    mov     r12, 9
    sub     al, '0'
    cmp     al, 9
    ja      .directive
    movzx   r12d, al
    inc     rbx
    movzx   eax, byte [rbx]
    test    al, al
    jz      .out
.directive:
    movzx   eax, byte [rbx]
    inc     rbx
    cmp     al, 'a'
    je      .wday_short
    cmp     al, 'A'
    je      .wday_full
    cmp     al, 'b'
    je      .mon_short
    cmp     al, 'h'
    je      .mon_short
    cmp     al, 'B'
    je      .mon_full
    cmp     al, 'C'
    je      .century
    cmp     al, 'd'
    je      .day2
    cmp     al, 'D'
    je      .mdy
    cmp     al, 'e'
    je      .day_space
    cmp     al, 'F'
    je      .isodate
    cmp     al, 'H'
    je      .hour2
    cmp     al, 'I'
    je      .hour12
    cmp     al, 'j'
    je      .yday
    cmp     al, 'k'
    je      .hour_space
    cmp     al, 'l'
    je      .hour12_space
    cmp     al, 'm'
    je      .mon2
    cmp     al, 'M'
    je      .min2
    cmp     al, 'n'
    je      .newline
    cmp     al, 'N'
    je      .nanos
    cmp     al, 'p'
    je      .ampm
    cmp     al, 'r'
    je      .time12
    cmp     al, 'R'
    je      .hhmm
    cmp     al, 's'
    je      .epochsecs
    cmp     al, 'S'
    je      .sec2
    cmp     al, 't'
    je      .tab
    cmp     al, 'T'
    je      .hhmmss
    cmp     al, 'u'
    je      .wday_iso
    cmp     al, 'w'
    je      .wday_num
    cmp     al, 'y'
    je      .year2
    cmp     al, 'Y'
    je      .year4
    cmp     al, 'z'
    je      .numeric_zone
    cmp     al, 'Z'
    je      .zone_abbr
    cmp     al, '%'
    je      .literal
    call    out_char
    jmp     .scan
.trailing:
    mov     al, '%'
    call    out_char
    jmp     .scan
.literal:
    call    out_char
    jmp     .scan
.wday_short:
    mov     rax, [cv_wday]
    imul    rax, rax, 3
    lea     rsi, [wdays + rax]
    mov     rdx, 3
    call    out_bytes
    jmp     .scan
.wday_full:
    mov     rax, [cv_wday]
    mov     rsi, wdays_full
    call    nth_string
    call    out_str
    jmp     .scan
.mon_short:
    mov     rax, [cv_mon]
    dec     rax
    imul    rax, rax, 3
    lea     rsi, [months + rax]
    mov     rdx, 3
    call    out_bytes
    jmp     .scan
.mon_full:
    mov     rax, [cv_mon]
    dec     rax
    mov     rsi, months_full
    call    nth_string
    call    out_str
    jmp     .scan
.century:
    mov     rax, [cv_year]
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    call    out_pad2
    jmp     .scan
.day2:
    mov     rax, [cv_day]
    call    out_pad2
    jmp     .scan
.day_space:
    mov     rax, [cv_day]
    call    out_space2
    jmp     .scan
.mon2:
    mov     rax, [cv_mon]
    call    out_pad2
    jmp     .scan
.hour2:
    mov     rax, [cv_hour]
    call    out_pad2
    jmp     .scan
.hour_space:
    mov     rax, [cv_hour]
    call    out_space2
    jmp     .scan
.hour12:
    call    hour12_value
    call    out_pad2
    jmp     .scan
.hour12_space:
    call    hour12_value
    call    out_space2
    jmp     .scan
.min2:
    mov     rax, [cv_min]
    call    out_pad2
    jmp     .scan
.sec2:
    mov     rax, [cv_sec]
    call    out_pad2
    jmp     .scan
.year4:
    mov     rax, [cv_year]
    call    out_num
    jmp     .scan
.year2:
    mov     rax, [cv_year]
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    mov     rax, rdx
    call    out_pad2
    jmp     .scan
.yday:
    mov     rax, [cv_yday]
    inc     rax
    mov     rcx, 3
    call    out_padded
    jmp     .scan
.wday_num:
    mov     rax, [cv_wday]
    call    out_num
    jmp     .scan
.wday_iso:
    mov     rax, [cv_wday]
    test    rax, rax
    jnz     .isoday
    mov     rax, 7
.isoday:
    call    out_num
    jmp     .scan
.isodate:
    mov     rax, [cv_year]
    call    out_num
    mov     al, '-'
    call    out_char
    mov     rax, [cv_mon]
    call    out_pad2
    mov     al, '-'
    call    out_char
    mov     rax, [cv_day]
    call    out_pad2
    jmp     .scan
.mdy:
    mov     rax, [cv_mon]
    call    out_pad2
    mov     al, '/'
    call    out_char
    mov     rax, [cv_day]
    call    out_pad2
    mov     al, '/'
    call    out_char
    mov     rax, [cv_year]
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    mov     rax, rdx
    call    out_pad2
    jmp     .scan
.hhmm:
    mov     rax, [cv_hour]
    call    out_pad2
mov     al, ':'
    call    out_char
    mov     rax, [cv_min]
    call    out_pad2
    jmp     .scan
.hhmmss:
    mov     rax, [cv_hour]
    call    out_pad2
mov     al, ':'
    call    out_char
    mov     rax, [cv_min]
    call    out_pad2
mov     al, ':'
    call    out_char
    mov     rax, [cv_sec]
    call    out_pad2
    jmp     .scan
.time12:
    call    hour12_value
    call    out_pad2
mov     al, ':'
    call    out_char
    mov     rax, [cv_min]
    call    out_pad2
mov     al, ':'
    call    out_char
    mov     rax, [cv_sec]
    call    out_pad2
    mov     al, WHITESPACE_SPACE
    call    out_char
    call    put_ampm
    jmp     .scan
.ampm:
    call    put_ampm
    jmp     .scan
.epochsecs:
    mov     rax, [epoch]
    call    out_signed
    jmp     .scan
.nanos:
    mov     rax, [nanos]
    mov     rcx, 9
    call    out_padded                  ;always nine, then trimmed below
    mov     rcx, 9
    sub     rcx, r12
    jle     .scan
    sub     [outlen], rcx               ;keep only the digits asked for
    jmp     .scan
.newline:
    mov     al, WHITESPACE_NL
    call    out_char
    jmp     .scan
.tab:
    mov     al, WHITESPACE_TAB
    call    out_char
    jmp     .scan
.numeric_zone:
    mov     rax, [cur_off]
    call    put_offset
    jmp     .scan
.zone_abbr:
    mov     rsi, [cur_abbr]
    call    out_str
    jmp     .scan
.out:
    pop     r12
    pop     rbx
    ret

hour12_value:
    mov     rax, [cv_hour]
    xor     rdx, rdx
    mov     rcx, 12
    div     rcx
    mov     rax, rdx
    test    rax, rax
    jnz     .out
    mov     rax, 12
.out:
    ret

put_ampm:
    mov     rsi, am_str
    cmp     qword [cv_hour], 12
    jb      .emit
    mov     rsi, pm_str
.emit:
    jmp     out_str

; nth_string: the rax'th NUL-terminated string in the table at rsi.
nth_string:
    test    rax, rax
    jz      .out
.skip:
    cmp     byte [rsi], 0
    je      .next
    inc     rsi
    jmp     .skip
.next:
    inc     rsi
    dec     rax
    jnz     .skip
.out:
    ret

; put_offset: the UTC offset as +HHMM.
put_offset:
    mov     rcx, rax
    mov     al, '+'
    test    rcx, rcx
    jns     .sign
    mov     al, '-'
    neg     rcx
.sign:
    call    out_char
    mov     rax, rcx
    xor     rdx, rdx
    mov     rcx, 3600
    div     rcx
    push    rdx
    call    out_pad2
    pop     rax
    xor     rdx, rdx
    mov     rcx, 60
    div     rcx
    jmp     out_pad2

; ---------------------------------------------------------------------------
; print_iso: -I, in the shape its argument asks for.
; ---------------------------------------------------------------------------
print_iso:
    mov     rax, [cv_year]
    call    out_num
    mov     al, '-'
    call    out_char
    mov     rax, [cv_mon]
    call    out_pad2
    mov     al, '-'
    call    out_char
    mov     rax, [cv_day]
    call    out_pad2
    mov     rsi, [isospec]
    test    rsi, rsi
    jz      .out
    movzx   eax, byte [rsi]
    test    al, al
    jz      .out
    cmp     al, 'd'
    je      .out
    cmp     al, 'h'
    je      .hours
    cmp     al, 'm'
    je      .minutes
    cmp     al, 's'
    je      .seconds
    cmp     al, 'n'
    je      .nanoseconds
    jmp     .out
.hours:
    mov     al, 'T'
    call    out_char
    mov     rax, [cv_hour]
    call    out_pad2
    jmp     .offset
.minutes:
    mov     al, 'T'
    call    out_char
    mov     rax, [cv_hour]
    call    out_pad2
mov     al, ':'
    call    out_char
    mov     rax, [cv_min]
    call    out_pad2
    jmp     .offset
.seconds:
    call    .hhmmss
    jmp     .offset
.nanoseconds:
    call    .hhmmss
    mov     al, ','
    call    out_char
    mov     rax, [nanos]
    mov     rcx, 9
    call    out_padded
    jmp     .offset
.hhmmss:
    mov     al, 'T'
    call    out_char
    mov     rax, [cv_hour]
    call    out_pad2
mov     al, ':'
    call    out_char
    mov     rax, [cv_min]
    call    out_pad2
mov     al, ':'
    call    out_char
    mov     rax, [cv_sec]
    call    out_pad2
    ret
.offset:
    mov     rcx, [cur_off]
    mov     al, '+'
    test    rcx, rcx
    jns     .sign
    mov     al, '-'
    neg     rcx
.sign:
    call    out_char
    mov     rax, rcx
    xor     rdx, rdx
    mov     rcx, 3600
    div     rcx
    push    rdx
    call    out_pad2
mov     al, ':'
    call    out_char
    pop     rax
    xor     rdx, rdx
    mov     rcx, 60
    div     rcx
    call    out_pad2
.out:
    ret

; ---------------------------------------------------------------------------
; The zone file. It lists the instants the offset changes and a table of the
; offsets and their abbreviations; a version 2 file repeats all of it with
; 64-bit times, and that second copy is the one worth reading.
; ---------------------------------------------------------------------------
; tz_load: read the zone named by rdi, or /etc/localtime when it is null.
; A null name with -u leaves the fixed UTC fallback in place.
tz_load:
    push    rbx
    mov     qword [tz_timecnt], 0
    mov     qword [tz_typecnt], 0
    mov     qword [tz_wide], 0
    mov     qword [tz_len], 0
    test    rdi, rdi
    jz      .localtime
    cmp     byte [rdi], 0
    je      .localtime
    mov     rsi, rdi
cmp     byte [rsi], ':'
    jne     .build
    inc     rsi
.build:
    cmp     byte [rsi], '/'
    je      .absolute
    mov     rdi, tzpath
    xor     rcx, rcx
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
    jmp     .open
.absolute:
    mov     rdi, rsi
    jmp     .open
.localtime:
    cmp     byte [opt_utc], 0
    jne     .out                        ;-u wants UTC, not the machine's zone
    mov     rdi, localtime_p
.open:
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
    push    r8
    push    r9
    syscall
    pop     r9
    pop     r8
    test    rax, rax
    jle     .close
    add     r9, rax
    jmp     .read
.close:
    mov     [tz_len], r9
    push    r9
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    pop     r9
    cmp     r9, 44
    jb      .out
    cmp     dword [tzbuf], 0x66695A54   ;"TZif"
    jne     .out
    xor     rdi, rdi
    call    tz_parse_block
    cmp     byte [tzbuf + 4], '2'
jb      .out                        ;version 1: that block is all there is
    mov     rdi, [tz_blocklen]
    cmp     rdi, [tz_len]
    jae     .out
    mov     qword [tz_wide], 1
    call    tz_parse_block
.out:
    pop     rbx
    ret

; tz_parse_block: read the header at offset rdi and note where its tables
; live. The six counts sit at offset 20 and the data follows the 44-byte
; header; the block's total length is how the 64-bit copy is found.
tz_parse_block:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    lea     rbx, [tzbuf + rdi]
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
    mov     r15, rax
    lea     rdi, [rbx + 36]
    call    read_be32
    mov     [tz_typecnt], rax
    mov     r8, rax
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
    mov     [tz_abbroff], rdi
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
    sub     rax, tzbuf
    mov     [tz_blocklen], rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; zone_at: the offset and abbreviation in force at the instant in rdi.
; ---------------------------------------------------------------------------
zone_at:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     qword [cur_off], 0
    mov     qword [cur_abbr], utc_abbr
    cmp     qword [tz_typecnt], 0
    je      .out
    cmp     qword [tz_timecnt], 0
    je      .firsttype
    xor     rbx, rbx
    mov     r13, -1
.scan:
    cmp     rbx, [tz_timecnt]
    jge     .found
    mov     rdi, rbx
    call    tz_transition
    cmp     rax, r12
    jg      .found
    mov     r13, rbx
    inc     rbx
    jmp     .scan
.found:
    cmp     r13, 0
    jl      .firsttype                  ;before the first recorded change
    mov     rax, [tz_idxoff]
    add     rax, r13
    movzx   edi, byte [rax]
    call    tz_use_type
    jmp     .out
.firsttype:
    xor     rdi, rdi
    call    tz_use_type
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; tz_transition: the rdi'th transition time, four or eight bytes wide.
tz_transition:
    cmp     qword [tz_wide], 0
    jne     .wide
    mov     rax, [tz_transoff]
    lea     rdi, [rax + rdi * 4]
    call    read_be32
    movsxd  rax, eax
    ret
.wide:
    mov     rax, [tz_transoff]
    lea     rdi, [rax + rdi * 8]
    jmp     read_be64

; tz_use_type: take the offset and abbreviation of type rdi.
tz_use_type:
    push    rbx
    mov     rax, [tz_ttoff]
    imul    rcx, rdi, 6
    add     rax, rcx
    mov     rbx, rax
    mov     rdi, rax
    call    read_be32
    movsxd  rax, eax
    mov     [cur_off], rax
    movzx   eax, byte [rbx + 5]         ;index into the abbreviation strings
    mov     rcx, [tz_abbroff]
    add     rcx, rax
    mov     [cur_abbr], rcx
    pop     rbx
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

; ---------------------------------------------------------------------------
; The civil calendar, counted from a March-based era so the leap day falls at
; the end of a year and needs no special case.
; ---------------------------------------------------------------------------
; civil_from_epoch: split the wall clock in rdi into the cv_* fields.
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

    mov     rax, rbx                    ;1970-01-01 was a Thursday
    add     rax, 4
    mov     rcx, 7
    cqo
    idiv    rcx
    test    rdx, rdx
    jns     .wday
    add     rdx, rcx
.wday:
    mov     [cv_wday], rdx

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
    sub     rax, r11                    ;day of year, counted from March
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

; the day of the year, from the first of January
    mov     rdi, [cv_year]
    mov     rsi, 1
    mov     rdx, 1
    call    days_from_civil
    mov     rcx, rax
    mov     rax, rbx
    sub     rax, rcx
    mov     [cv_yday], rax
    pop     rbx
    ret

; days_from_civil: the day number for the year in rdi, month rsi, day rdx.
days_from_civil:
    push    rbx
    mov     r11, rdx                    ;day of month
    mov     rax, rdi
    cmp     rsi, 2
    ja      .keep
    dec     rax                         ;March starts the year here
.keep:
    mov     r8, rax
    mov     rcx, 400
    cqo
    idiv    rcx
    mov     r9, rax                     ;era
    test    rdx, rdx
    jns     .yoe
    dec     r9
.yoe:
    mov     rax, r9
    imul    rax, rax, 400
    mov     r10, r8
    sub     r10, rax                    ;year of era
    mov     rax, rsi
    cmp     rax, 2
    jbe     .early
    sub     rax, 3
    jmp     .doy
.early:
    add     rax, 9
.doy:
    imul    rax, rax, 153
    add     rax, 2
    xor     rdx, rdx
    mov     rcx, 5
    div     rcx
    add     rax, r11
    dec     rax                         ;day of year
    mov     rbx, rax
    mov     rax, r10
    imul    rax, rax, 365
    mov     rcx, r10
    shr     rcx, 2
    add     rax, rcx
    push    rax
    mov     rax, r10
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    mov     rcx, rax
    pop     rax
    sub     rax, rcx
    add     rax, rbx                    ;day of era
    mov     rcx, r9
    imul    rcx, rcx, 146097
    add     rax, rcx
    sub     rax, 719468
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; parse_setarg: a bare operand asks to set the clock, in MMDDhhmm form. Only
; well-formed values are accepted; setting it needs privileges we may not
; have, and failing that is reported.
; ---------------------------------------------------------------------------
parse_setarg:
    push    rbx
    mov     rbx, rdi
    call    default_today
    mov     rdi, rbx
    call    scan_digits_at              ;-> rax, rcx digits
    cmp     rcx, 8
    jb      bad_date
    mov     r8, rax
    mov     r9, rcx
; the leading eight digits are MMDDhhmm
    mov     rax, r8
    mov     r10, r9
.trim:
    cmp     r10, 8
    jbe     .fields
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    dec     r10
    jmp     .trim
.fields:
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    mov     [in_min], rdx
    xor     rdx, rdx
    div     rcx
    mov     [in_hour], rdx
    xor     rdx, rdx
    div     rcx
    mov     [in_day], rdx
    mov     [in_mon], rax
    cmp     qword [in_mon], 1
    jb      bad_date
    cmp     qword [in_mon], 12
    ja      bad_date
    cmp     qword [in_day], 1
    jb      bad_date
    cmp     qword [in_day], 31
    ja      bad_date
    cmp     qword [in_hour], 23
    ja      bad_date
    cmp     qword [in_min], 59
    ja      bad_date
    mov     qword [in_sec], 0
    call    load_output_zone
    call    finish_civil
    mov     rax, [epoch]
    mov     [tsbuf], rax
    mov     qword [tsbuf + 8], 0
    mov     rax, SYS_SETTIMEOFDAY
    mov     rdi, tsbuf
    xor     rsi, rsi
    syscall
    test    rax, rax
    js      bad_date                    ;not permitted, most likely
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Scanning helpers. The parsers keep their cursor in rbx.
; ---------------------------------------------------------------------------
skip_spaces_rbx:
    mov     al, [rbx]
    cmp     al, WHITESPACE_SPACE
    je      .step
    cmp     al, WHITESPACE_TAB
    jne     .out
.step:
    inc     rbx
    jmp     skip_spaces_rbx
.out:
    ret

skip_alpha_word:
    movzx   eax, byte [rbx]
    cmp     al, 'A'
    jb      .out
    cmp     al, 'Z'
    jbe     .step
    cmp     al, 'a'
    jb      .out
    cmp     al, 'z'
    ja      .out
.step:
    inc     rbx
    jmp     skip_alpha_word
.out:
    ret

; scan_digits: digits at rbx, advancing it. rax = value, rcx = how many.
scan_digits:
    xor     rax, rax
    xor     rcx, rcx
.digit:
    movzx   rdx, byte [rbx]
    sub     dl, '0'
    cmp     dl, 9
    ja      .out
    imul    rax, rax, 10
    add     rax, rdx
    inc     rcx
    inc     rbx
    jmp     .digit
.out:
    ret

; scan_digits_at: the same, reading from rdi and leaving it alone.
scan_digits_at:
    xor     rax, rax
    xor     rcx, rcx
.digit:
    movzx   rdx, byte [rdi]
    sub     dl, '0'
    cmp     dl, 9
    ja      .out
    imul    rax, rax, 10
    add     rax, rdx
    inc     rcx
    inc     rdi
    jmp     .digit
.out:
    ret

; scan_fraction: a decimal fraction at rbx, scaled to nanoseconds.
scan_fraction:
    xor     rax, rax
    xor     r8, r8
.digit:
    movzx   rdx, byte [rbx]
    sub     dl, '0'
    cmp     dl, 9
    ja      .scale
    cmp     r8, 9
    jae     .skip
    imul    rax, rax, 10
    add     rax, rdx
    inc     r8
.skip:
    inc     rbx
    jmp     .digit
.scale:
    cmp     r8, 9
    jae     .out
    imul    rax, rax, 10
    inc     r8
    jmp     .scale
.out:
    ret

; ---------------------------------------------------------------------------
; Output.
; ---------------------------------------------------------------------------
out_char:
    push    rcx
    mov     rcx, [outlen]
    cmp     rcx, OUTCAP - 1
    jae     .out
    mov     [outbuf + rcx], al
    inc     qword [outlen]
.out:
    pop     rcx
    ret

out_bytes:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, rdx
    xor     rbx, rbx
.copy:
    cmp     rbx, r13
    jae     .out
    mov     al, [r12 + rbx]
    call    out_char
    inc     rbx
    jmp     .copy
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

out_str:
    push    rbx
    mov     rbx, rsi
.copy:
    mov     al, [rbx]
    test    al, al
    jz      .out
    call    out_char
    inc     rbx
    jmp     .copy
.out:
    pop     rbx
    ret

out_num:
    push    rbx
    mov     rdi, numbuf
    call    u64_to_dec
    mov     byte [rdi], 0
    mov     rsi, numbuf
    call    out_str
    pop     rbx
    ret

out_signed:
    test    rax, rax
    jns     out_num
    push    rax
    mov     al, '-'
    call    out_char
    pop     rax
    neg     rax
    jmp     out_num

; out_pad2: two digits, zero filled.
out_pad2:
    mov     rcx, 2
    jmp     out_padded

; out_space2: two columns, space filled.
out_space2:
    cmp     rax, 10
    jae     out_num
    push    rax
    mov     al, WHITESPACE_SPACE
    call    out_char
    pop     rax
    jmp     out_num

; out_padded: rax as at least rcx digits, zero filled on the left.
out_padded:
    push    rbx
    push    r12
    mov     r12, rcx
    mov     rbx, rax
    call    numlen
    mov     rcx, r12
    sub     rcx, rax
    jle     .digits
.zeros:
    push    rcx
    mov     al, '0'
    call    out_char
    pop     rcx
    dec     rcx
    jnz     .zeros
.digits:
    mov     rax, rbx
    call    out_num
    pop     r12
    pop     rbx
    ret

numlen:
    push    rax
    push    rdx
    mov     r9, 1
    mov     r10, 10
.step:
    cmp     rax, r10
    jb      .out
    xor     rdx, rdx
    div     r10
    inc     r9
    jmp     .step
.out:
    pop     rdx
    pop     rax
    mov     rax, r9
    ret

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

out_flush:
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
    ret
