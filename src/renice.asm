; src/renice.asm -- renice(1): adjust process nice values.
; Usage: renice -n INCREMENT [-p|-g|-u] ID...
;
; -n gives a relative adjustment applied to each target's current nice value
; (getpriority returns 20-nice). -p (the default), -g and -u say whether the
; ids that follow name processes, process groups or users; a user may be given
; by name, resolved through /etc/passwd, or by number. Failures on individual
; ids produce a non-zero exit, but the remaining ids are still adjusted.

    %include "include/sysdefs.inc"

    %define PRIO_PROCESS 0
    %define PRIO_PGRP 1
    %define PRIO_USER 2
    %define MAX_IDS 256
    %define PASSWD_CAP 65536

section .bss
    ids         resq MAX_IDS
    kinds       resb MAX_IDS            ;PRIO_* each id was given under
    nids        resq 1
    nval        resq 1
    kind        resb 1                  ;how the ids that follow are read
    pw_buf      resb PASSWD_CAP
    pw_len      resq 1
    pw_loaded   resb 1
    had_err     resb 1
    f_id        resq 1                  ;the id a failed call was given
    f_err       resq 1
    f_kind      resb 1
    numbuf      resb 32

section .data
    passwd_path db "/etc/passwd", 0
usage_msg   db "Usage: renice -n INCREMENT [-p|-g|-u] ID...", WHITESPACE_NL
    usage_len   equ $ - usage_msg
err_pre     db "renice: "
    err_pre_len equ $ - err_pre
    err_incr    db "invalid increment "
    err_incr_len equ $ - err_incr
    err_id      db "invalid id "
    err_id_len  equ $ - err_id
    err_user    db "unknown user "
    err_user_len equ $ - err_user
err_many    db "renice: too many ids", WHITESPACE_NL
    err_many_len equ $ - err_many
    quote       db "'"
    newline     db WHITESPACE_NL
colon_sp    db ": "
    colon_sp_len equ $ - colon_sp
    tag_pid     db "pid ", 0
    tag_pgid    db "pgid ", 0
    tag_uid     db "uid ", 0
    r_eperm     db "operation not permitted", WHITESPACE_NL
    r_eperm_len equ $ - r_eperm
    r_esrch     db "no such process", WHITESPACE_NL
    r_esrch_len equ $ - r_esrch
    r_eacces    db "permission denied", WHITESPACE_NL
    r_eacces_len equ $ - r_eacces
    r_einval    db "invalid argument", WHITESPACE_NL
    r_einval_len equ $ - r_einval
    r_other     db "cannot set priority", WHITESPACE_NL
    r_other_len equ $ - r_other

section .text
global _start

_start:
    mov     byte [kind], PRIO_PROCESS
    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12
parse:
    cmp     r12, 0
    je      after_parse
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .id
    cmp     byte [rdi + 1], 0
    je      .id                         ;a lone "-" is not an option
    mov     al, [rdi + 1]
    cmp     al, 'n'
    je      .increment
    cmp     al, 'p'
    je      .as_process
    cmp     al, 'g'
    je      .as_pgrp
    cmp     al, 'u'
    je      .as_user
    jmp     usage
.as_process:
    cmp     byte [rdi + 2], 0
    jne     usage
    mov     byte [kind], PRIO_PROCESS
    jmp     .nextarg
.as_pgrp:
    cmp     byte [rdi + 2], 0
    jne     usage
    mov     byte [kind], PRIO_PGRP
    jmp     .nextarg
.as_user:
    cmp     byte [rdi + 2], 0
    jne     usage
    mov     byte [kind], PRIO_USER
    jmp     .nextarg
.increment:
    cmp     byte [rdi + 2], 0
    jne     .attached
    cmp     r12, 1
    jle     usage                       ;"-n" with no increment after it
    add     r13, 8
    dec     r12
    mov     rdi, [r13]
    jmp     .parse_incr
.attached:
    lea     rdi, [rdi + 2]
.parse_incr:
    mov     r15, rdi
    call    parse_signed
    test    rdx, rdx
    jz      .bad_incr
    mov     [nval], rax
    jmp     .nextarg
.bad_incr:
    mov     rdi, r15
    mov     rsi, err_incr
    mov     rdx, err_incr_len
    call    fail_arg
.id:
    mov     r15, rdi
    call    parse_unsigned
    test    rdx, rdx
    jnz     .store
    cmp     byte [kind], PRIO_USER
    jne     .bad_id
    mov     rdi, r15                    ;-u takes names as well as numbers
    call    user_id
    test    rdx, rdx
    jnz     .store
    mov     rdi, r15
    mov     rsi, err_user
    mov     rdx, err_user_len
    call    fail_arg
.bad_id:
    mov     rdi, r15
    mov     rsi, err_id
    mov     rdx, err_id_len
    call    fail_arg
.store:
    mov     rcx, [nids]
    cmp     rcx, MAX_IDS
    jae     .too_many
    mov     [ids + rcx*8], rax
    mov     dl, [kind]
    mov     [kinds + rcx], dl
    inc     qword [nids]
    jmp     .nextarg
.too_many:
    write   STDERR_FILENO, err_many, err_many_len
    exit    1
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

after_parse:
    cmp     qword [nids], 0
    je      usage
    xor     r14, r14
.each:
    cmp     r14, [nids]
    jge     .done
    movzx   r15d, byte [kinds + r14]    ;PRIO_PROCESS, PRIO_PGRP or PRIO_USER
    mov     rax, SYS_GETPRIORITY
    mov     rdi, r15
    mov     rsi, [ids + r14*8]
    syscall
    test    rax, rax
    js      .fail
;current nice = 20 - raw; new = nice + inc
    mov     rcx, 20
    sub     rcx, rax
    add     rcx, [nval]
    mov     rax, SYS_SETPRIORITY
    mov     rdi, r15
    mov     rsi, [ids + r14*8]
    mov     rdx, rcx
    syscall
    test    rax, rax
    js      .fail
    jmp     .next
.fail:
    mov     rsi, rax                    ;-errno from whichever call failed
    mov     rdi, [ids + r14*8]
    movzx   edx, byte [kinds + r14]
    call    report_failure
    mov     byte [had_err], 1
.next:
    inc     r14
    jmp     .each
.done:
    movzx   edi, byte [had_err]
    mov     rax, SYS_EXIT
    syscall

; report_failure: say which id could not be changed, and why.
;   rdi = the id, rsi = -errno, rdx = the PRIO_* it was given under
report_failure:
    mov     [f_id], rdi
    mov     [f_err], rsi
    mov     [f_kind], dl
    write   STDERR_FILENO, err_pre, err_pre_len
    movzx   eax, byte [f_kind]
    cmp     al, PRIO_PGRP
    je      .pgrp
    cmp     al, PRIO_USER
    je      .user
    mov     rdi, tag_pid
    jmp     .tagged
.pgrp:
    mov     rdi, tag_pgid
    jmp     .tagged
.user:
    mov     rdi, tag_uid
.tagged:
    call    err_str
    mov     rdi, [f_id]
    call    err_num
    write   STDERR_FILENO, colon_sp, colon_sp_len
    mov     rax, [f_err]
    neg     rax
    cmp     rax, EPERM
    je      .eperm
    cmp     rax, ESRCH
    je      .esrch
    cmp     rax, EACCES
    je      .eacces
    cmp     rax, EINVAL
    je      .einval
    write   STDERR_FILENO, r_other, r_other_len
    ret
.eperm:
    write   STDERR_FILENO, r_eperm, r_eperm_len
    ret
.esrch:
    write   STDERR_FILENO, r_esrch, r_esrch_len
    ret
.eacces:
    write   STDERR_FILENO, r_eacces, r_eacces_len
    ret
.einval:
    write   STDERR_FILENO, r_einval, r_einval_len
    ret

; err_str: rdi = NUL-terminated string, to stderr.
err_str:
    mov     rsi, rdi
    call    strlen                      ;rbx = length
    write   STDERR_FILENO, rsi, rbx
    ret

; err_num: rdi = value, in decimal, to stderr.
err_num:
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
    mov     rdi, STDERR_FILENO
    syscall
    ret

; fail_arg: report "renice: MSG 'ARG'" on stderr and exit 1.
;   rdi = the offending argument, rsi = message, rdx = message length
fail_arg:
    push    rdi
    push    rsi
    push    rdx
    write   STDERR_FILENO, err_pre, err_pre_len
    pop     rdx
    pop     rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    write   STDERR_FILENO, quote, 1
    pop     rsi
    push    rsi
    call    strlen                      ;rbx = length
    pop     rsi
    write   STDERR_FILENO, rsi, rbx
    write   STDERR_FILENO, quote, 1
    write   STDERR_FILENO, newline, 1
    exit    1

; user_id: rdi = user name -> rax = uid, rdx = 1 when /etc/passwd lists it.
user_id:
    push    r12
    push    r13
    push    r14
    mov     r14, rdi
    cmp     byte [pw_loaded], 0
    jne     .scan
    mov     byte [pw_loaded], 1
    mov     rdi, passwd_path
    mov     rsi, pw_buf
    call    read_passwd
    mov     [pw_len], rax
.scan:
    xor     r12, r12                    ;line start
.line:
    cmp     r12, [pw_len]
    jae     .none
    mov     r13, r12
    xor     rcx, rcx
.match:
    mov     al, [r14 + rcx]
    test    al, al
    jz      .name_end
    cmp     r13, [pw_len]
    jae     .nextline
    cmp     al, [pw_buf + r13]
    jne     .nextline
    inc     r13
    inc     rcx
    jmp     .match
.name_end:
    cmp     r13, [pw_len]
    jae     .nextline
cmp     byte [pw_buf + r13], ':'
    jne     .nextline
    inc     r13                         ;past the name's colon
.skip_pw:
    cmp     r13, [pw_len]
    jae     .none
    mov     al, [pw_buf + r13]
cmp     al, ':'
    je      .at_uid
    cmp     al, WHITESPACE_NL
    je      .nextline
    inc     r13
    jmp     .skip_pw
.at_uid:
    inc     r13                         ;past the password's colon
    xor     rax, rax
    xor     rcx, rcx
.digit:
    cmp     r13, [pw_len]
    jae     .end
    movzx   edx, byte [pw_buf + r13]
    sub     dl, '0'
    cmp     dl, 9
    ja      .end
    imul    rax, rax, 10
    movzx   rdx, dl
    add     rax, rdx
    inc     rcx
    inc     r13
    jmp     .digit
.end:
    test    rcx, rcx
    jz      .none
    mov     rdx, 1
    jmp     .out
.nextline:
    cmp     r12, [pw_len]
    jae     .none
    cmp     byte [pw_buf + r12], WHITESPACE_NL
    je      .nl
    inc     r12
    jmp     .nextline
.nl:
    inc     r12
    jmp     .line
.none:
    xor     rax, rax
    xor     rdx, rdx
.out:
    pop     r14
    pop     r13
    pop     r12
    ret

; read_passwd: rdi = path, rsi = buffer -> rax = length.
read_passwd:
    mov     r10, rsi
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .empty
    mov     r8, rax                     ;fd
    xor     r9, r9                      ;bytes so far
.rd:
    mov     rdx, PASSWD_CAP
    sub     rdx, r9
    jle     .close
    mov     rax, SYS_READ
    mov     rdi, r8
    lea     rsi, [r10 + r9]
    syscall
    test    rax, rax
    jle     .close
    add     r9, rax
    jmp     .rd
.close:
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    mov     rax, r9
    ret
.empty:
    xor     rax, rax
    ret

; parse_signed: rdi = string -> rax = value, rdx = 1 when the whole string is a
; decimal number with an optional sign.
parse_signed:
    xor     rax, rax
    xor     rcx, rcx                    ;digits seen
    xor     r8, r8                      ;negative?
    mov     r10, 0xffffffff
    cmp     byte [rdi], '-'
    jne     .plus
    mov     r8, 1
    inc     rdi
    jmp     .digits
.plus:
    cmp     byte [rdi], '+'
    jne     .digits
    inc     rdi
.digits:
    movzx   r9d, byte [rdi]
    test    r9b, r9b
    jz      .end
    sub     r9b, '0'
    cmp     r9b, 9
    ja      .bad
    imul    rax, rax, 10
    movzx   r9, r9b
    add     rax, r9
    cmp     rax, r10
    ja      .bad
    inc     rcx
    inc     rdi
    jmp     .digits
.end:
    test    rcx, rcx
    jz      .bad
    test    r8, r8
    jz      .positive
    neg     rax
.positive:
    mov     rdx, 1
    ret
.bad:
    xor     rax, rax
    xor     rdx, rdx
    ret

; parse_unsigned: rdi = string -> rax = value, rdx = 1 when the whole string is
; a decimal number that fits in 32 bits.
parse_unsigned:
    xor     rax, rax
    xor     rcx, rcx
    mov     r10, 0xffffffff
.digits:
    movzx   r9d, byte [rdi]
    test    r9b, r9b
    jz      .end
    sub     r9b, '0'
    cmp     r9b, 9
    ja      .bad
    imul    rax, rax, 10
    movzx   r9, r9b
    add     rax, r9
    cmp     rax, r10
    ja      .bad
    inc     rcx
    inc     rdi
    jmp     .digits
.end:
    test    rcx, rcx
    jz      .bad
    mov     rdx, 1
    ret
.bad:
    xor     rax, rax
    xor     rdx, rdx
    ret
