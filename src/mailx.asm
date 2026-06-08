; src/mailx.asm
;
; mailx - compose and deliver a mail message (send mode).
;
; Supported usage
;   mailx [-s SUBJECT] [-f MAILBOX] recipient...
;
; The message body is read from standard input. An RFC 5322 message is
; composed (To, Subject, and a Date header) and appended, in mbox format
; with a "From " envelope line, to a mailbox file: the -f MAILBOX when
; given, else the $MAIL mailbox, else /var/mail/<user>. This performs a
; local mbox delivery rather than handing the message to a mail transfer
; agent.
;
; Interactive reading of a mailbox, the tilde escapes, Cc/Bcc, MIME, and
; handing off to an MTA are out of scope.

    %include "include/sysdefs.inc"

section .bss
    bodybuf     resb 1048576
    msgbuf      resb 1100000
    mboxpath    resb 4096
    date_scr    resb 32

    as_days     resq 1
    as_hour     resq 1
    as_min      resq 1
    as_sec      resq 1
    as_year     resq 1
    as_mon      resq 1
    as_day      resq 1

    subject_ptr resq 1
    mbox_ptr    resq 1
    sender_ptr  resq 1
    rcpts       resq 256
    nrcpt       resq 1
    body_len    resq 1
    envp_ptr    resq 1

section .data
    s_from      db "From ", 0
s_to        db "To: ", 0
s_subject   db "Subject: ", 0
    logname_pre db "LOGNAME=", 0
    user_pre    db "USER=", 0
    mail_pre    db "MAIL=", 0
    var_mail    db "/var/mail/", 0
    default_user db "user", 0
    wday_names  db "SunMonTueWedThuFriSat"
    mon_names   db "JanFebMarAprMayJunJulAugSepOctNovDec"
norcpt_msg  db "mailx: no recipients specified", 10
    norcpt_len  equ $ - norcpt_msg
open_msg    db "mailx: cannot open mailbox", 10
    open_len    equ $ - open_msg

section .text
global _start

_start:
    pop     rbx                         ;argc
    mov     r12, rsp                    ;argv pointer
    lea     r13, [r12 + rbx*8 + 8]      ;envp
    mov     [envp_ptr], r13

    mov     qword [subject_ptr], 0
    mov     qword [mbox_ptr], 0
    mov     qword [nrcpt], 0

    mov     rcx, 1
.parse:
    cmp     rcx, rbx
    jae     .parsed
    mov     rsi, [r12 + rcx*8]
    cmp     byte [rsi], '-'
    jne     .rcpt
    cmp     byte [rsi + 1], 0
    je      .rcpt
    mov     al, [rsi + 1]
    cmp     al, 's'
    je      .opt_s
    cmp     al, 'f'
    je      .opt_f
    inc     rcx                         ;ignore other options
    jmp     .parse

.opt_s:
    cmp     byte [rsi + 2], 0
    je      .s_sep
    lea     rax, [rsi + 2]
    mov     [subject_ptr], rax
    inc     rcx
    jmp     .parse
.s_sep:
    inc     rcx
    cmp     rcx, rbx
    jae     .parsed
    mov     rax, [r12 + rcx*8]
    mov     [subject_ptr], rax
    inc     rcx
    jmp     .parse

.opt_f:
    cmp     byte [rsi + 2], 0
    je      .f_sep
    lea     rax, [rsi + 2]
    mov     [mbox_ptr], rax
    inc     rcx
    jmp     .parse
.f_sep:
    inc     rcx
    cmp     rcx, rbx
    jae     .parsed
    mov     rax, [r12 + rcx*8]
    mov     [mbox_ptr], rax
    inc     rcx
    jmp     .parse

.rcpt:
    mov     rax, [nrcpt]
    mov     [rcpts + rax*8], rsi
    inc     rax
    mov     [nrcpt], rax
    inc     rcx
    jmp     .parse

.parsed:
    cmp     qword [nrcpt], 0
    je      .no_rcpt

; sender = $LOGNAME or $USER or "user"
    mov     rdi, logname_pre
    mov     rsi, [envp_ptr]
    call    __find_env
    test    rax, rax
    jnz     .have_sender
    mov     rdi, user_pre
    mov     rsi, [envp_ptr]
    call    __find_env
    test    rax, rax
    jnz     .have_sender
    mov     rax, default_user
.have_sender:
    mov     [sender_ptr], rax

; read the message body from standard input
    xor     rdi, rdi
    mov     rsi, bodybuf
    mov     rdx, 1048576
    call    slurp
    mov     [body_len], rax

; choose the destination mailbox
    cmp     qword [mbox_ptr], 0
    jne     .build_msg
    mov     rdi, mail_pre
    mov     rsi, [envp_ptr]
    call    __find_env
    test    rax, rax
    jz      .default_box
    mov     [mbox_ptr], rax
    jmp     .build_msg
.default_box:
    mov     rdi, mboxpath               ;/var/mail/<sender>
    mov     rsi, var_mail
    call    app_strz_to
    mov     rsi, [sender_ptr]
    call    app_strz_to
    mov     byte [rdi], 0
    mov     qword [mbox_ptr], mboxpath

;------------------------------------------------------------------
; compose the mbox message in msgbuf
;------------------------------------------------------------------
.build_msg:
    mov     rbx, msgbuf

    mov     rsi, s_from                 ;"From "
    call    app_strz
    mov     rsi, [sender_ptr]
    call    app_strz
    mov     al, ' '
    call    app_byte

    mov     rax, SYS_TIME               ;date for the envelope and header
    xor     rdi, rdi
    syscall
    mov     rdi, rax
    call    format_asctime
    mov     rsi, date_scr
    mov     rcx, 24
    call    app_mem
    mov     al, 10
    call    app_byte

    mov     rsi, s_to                   ;the To header and recipients
    call    app_strz
    xor     r14, r14
.to_loop:
    cmp     r14, [nrcpt]
    jae     .to_done
    test    r14, r14
    jz      .to_nospace
    mov     al, ' '
    call    app_byte
.to_nospace:
    mov     rsi, [rcpts + r14*8]
    call    app_strz
    inc     r14
    jmp     .to_loop
.to_done:
    mov     al, 10
    call    app_byte

    cmp     qword [subject_ptr], 0      ;the Subject header when given
    je      .no_subject
    mov     rsi, s_subject
    call    app_strz
    mov     rsi, [subject_ptr]
    call    app_strz
    mov     al, 10
    call    app_byte
.no_subject:

    mov     al, 10                      ;blank line before the body
    call    app_byte

    mov     rsi, bodybuf                ;body
    mov     rcx, [body_len]
    call    app_mem

    mov     rcx, [body_len]             ;ensure the body ends with a newline
    test    rcx, rcx
    jz      .add_nl
    cmp     byte [bodybuf + rcx - 1], 10
    je      .body_nl_ok
.add_nl:
    mov     al, 10
    call    app_byte
.body_nl_ok:
    mov     al, 10                      ;blank line separates mbox messages
    call    app_byte

;------------------------------------------------------------------
; append the message to the mailbox
;------------------------------------------------------------------
    mov     rax, SYS_OPEN
    mov     rdi, [mbox_ptr]
    mov     rsi, O_WRONLY | O_CREAT | O_APPEND
    mov     rdx, 384                    ;0600
    syscall
    test    rax, rax
    js      .open_err
    mov     r15, rax
    mov     rax, SYS_WRITE
    mov     rdi, r15
    mov     rsi, msgbuf
    mov     rdx, rbx
    sub     rdx, msgbuf
    syscall
    mov     rax, SYS_CLOSE
    mov     rdi, r15
    syscall
    exit    0

.no_rcpt:
    write   STDERR_FILENO, norcpt_msg, norcpt_len
    exit    1
.open_err:
    write   STDERR_FILENO, open_msg, open_len
    exit    1

;------------------------------------------------------------------
; app_strz - append the NUL-terminated string at rsi to [rbx].
; app_mem  - append rcx bytes at rsi to [rbx].
; app_byte - append al to [rbx]. All advance rbx.
;------------------------------------------------------------------
app_strz:
    mov     al, [rsi]
    test    al, al
    jz      .done
    mov     [rbx], al
    inc     rbx
    inc     rsi
    jmp     app_strz
.done:
    ret

app_mem:
    test    rcx, rcx
    jz      .done
.l:
    mov     al, [rsi]
    mov     [rbx], al
    inc     rsi
    inc     rbx
    dec     rcx
    jnz     .l
.done:
    ret

app_byte:
    mov     [rbx], al
    inc     rbx
    ret

;------------------------------------------------------------------
; app_strz_to - append the NUL-terminated string at rsi to [rdi].
;------------------------------------------------------------------
app_strz_to:
    mov     al, [rsi]
    test    al, al
    jz      .done
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     app_strz_to
.done:
    ret

;------------------------------------------------------------------
; format_asctime - render unix time rdi into date_scr as the 24-byte
; asctime "Www Mmm _D HH:MM:SS YYYY".
;------------------------------------------------------------------
format_asctime:
    push    rbx                         ;the caller keeps its buffer cursor here
    mov     rax, rdi
    xor     rdx, rdx
    mov     rcx, 86400
    div     rcx
    mov     [as_days], rax
    mov     rax, rdx
    xor     rdx, rdx
    mov     rcx, 3600
    div     rcx
    mov     [as_hour], rax
    mov     rax, rdx
    xor     rdx, rdx
    mov     rcx, 60
    div     rcx
    mov     [as_min], rax
    mov     [as_sec], rdx

    mov     r8, [as_days]               ;civil date from days
    mov     rax, r8
    add     rax, 719468
    xor     rdx, rdx
    mov     rcx, 146097
    div     rcx
    mov     r11, rax                    ;era
    mov     rsi, rdx                    ;doe
    mov     rax, rsi
    xor     rdx, rdx
    mov     rcx, 1460
    div     rcx
    mov     rbx, rax
    mov     rax, rsi
    xor     rdx, rdx
    mov     rcx, 36524
    div     rcx
    mov     r9, rsi
    sub     r9, rbx
    add     r9, rax
    mov     rax, rsi
    xor     rdx, rdx
    mov     rcx, 146096
    div     rcx
    sub     r9, rax
    mov     rax, r9
    xor     rdx, rdx
    mov     rcx, 365
    div     rcx
    mov     r10, rax                    ;yoe
    mov     rax, r11
    imul    rax, rax, 400
    add     rax, r10
    mov     r14, rax                    ;year (pre-adjust)
    mov     rax, r10
    imul    rax, rax, 365
    mov     rbx, rax
    mov     rax, r10
    xor     rdx, rdx
    mov     rcx, 4
    div     rcx
    add     rbx, rax
    mov     rax, r10
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    sub     rbx, rax
    mov     rax, rsi
    sub     rax, rbx                    ;doy
    mov     r15, rax
    imul    rax, rax, 5
    add     rax, 2
    xor     rdx, rdx
    mov     rcx, 153
    div     rcx
    mov     rbx, rax                    ;mp
    mov     rax, rbx
    imul    rax, rax, 153
    add     rax, 2
    xor     rdx, rdx
    mov     rcx, 5
    div     rcx
    mov     rcx, r15
    sub     rcx, rax
    inc     rcx
    mov     [as_day], rcx               ;day
    mov     rax, rbx
    cmp     rax, 10
    jb      .m_lt
    sub     rax, 9
    jmp     .m_done
.m_lt:
    add     rax, 3
.m_done:
    mov     [as_mon], rax               ;month 1..12
    cmp     rax, 2
    ja      .no_inc
    inc     r14
.no_inc:
    mov     [as_year], r14

; weekday = (days + 4) % 7
    mov     rax, [as_days]
    add     rax, 4
    xor     rdx, rdx
    mov     rcx, 7
    div     rcx                         ;rdx = weekday

; format into date_scr
    mov     rdi, date_scr
    imul    rax, rdx, 3                 ;weekday name
    mov     rsi, wday_names
    add     rsi, rax
    mov     al, [rsi]
    mov     [rdi], al
    mov     al, [rsi + 1]
    mov     [rdi + 1], al
    mov     al, [rsi + 2]
    mov     [rdi + 2], al
    mov     byte [rdi + 3], ' '

    mov     rax, [as_mon]               ;month name (month-1)*3
    dec     rax
    imul    rax, rax, 3
    mov     rsi, mon_names
    add     rsi, rax
    mov     al, [rsi]
    mov     [rdi + 4], al
    mov     al, [rsi + 1]
    mov     [rdi + 5], al
    mov     al, [rsi + 2]
    mov     [rdi + 6], al
    mov     byte [rdi + 7], ' '

    mov     rax, [as_day]               ;space-padded day at 8..9
    mov     rcx, 10
    xor     rdx, rdx
    div     rcx
    test    al, al
    jnz     .day_tens
    mov     byte [rdi + 8], ' '
    jmp     .day_ones
.day_tens:
    add     al, '0'
    mov     [rdi + 8], al
.day_ones:
    add     dl, '0'
    mov     [rdi + 9], dl
    mov     byte [rdi + 10], ' '

    mov     rax, [as_hour]
    lea     rdi, [date_scr + 11]
    call    put2
    mov     byte [date_scr + 13], 58    ;colon
    mov     rax, [as_min]
    lea     rdi, [date_scr + 14]
    call    put2
    mov     byte [date_scr + 16], 58    ;colon
    mov     rax, [as_sec]
    lea     rdi, [date_scr + 17]
    call    put2
    mov     byte [date_scr + 19], ' '

    mov     rax, [as_year]
    lea     rdi, [date_scr + 20]
    call    put4
    pop     rbx
    ret

;------------------------------------------------------------------
; put2 - two zero-padded decimal digits of rax at rdi.
; put4 - four zero-padded decimal digits of rax at rdi.
;------------------------------------------------------------------
put2:
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    add     al, '0'
    mov     [rdi], al
    add     dl, '0'
    mov     [rdi + 1], dl
    ret

put4:
    xor     rdx, rdx
    mov     rcx, 1000
    div     rcx
    add     al, '0'
    mov     [rdi], al
    mov     rax, rdx
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    add     al, '0'
    mov     [rdi + 1], al
    mov     rax, rdx
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    add     al, '0'
    mov     [rdi + 2], al
    add     dl, '0'
    mov     [rdi + 3], dl
    ret

;------------------------------------------------------------------
; slurp - read fd rdi into [rsi] up to rdx bytes; rax = byte count.
;------------------------------------------------------------------
slurp:
    mov     r10, rsi
    mov     r11, rdx
    xor     r9, r9
.rd:
    mov     rdx, r11
    sub     rdx, r9
    jz      .done
    mov     rax, SYS_READ
    mov     rsi, r10
    add     rsi, r9
    syscall
    test    rax, rax
    jle     .done
    add     r9, rax
    jmp     .rd
.done:
    mov     rax, r9
    ret
