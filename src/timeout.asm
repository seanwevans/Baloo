; src/timeout.asm -- timeout(1): run a command, and stop it if it takes too long.
; Usage: timeout [-iv] [-k DURATION] [-s SIGNAL] [--foreground]
;                [--preserve-status] DURATION COMMAND [ARG...]
;
; The command runs as a child. The parent has to wait for two things at once
; -- the clock running out, and the child finishing -- so it waits on a pipe
; that the child holds the far end of: when the child and everything it
; started are gone the pipe closes, and until then the wait ends of its own
; accord when the time is up.
;
; The exit status carries the reason. A command that finished on its own hands
; back its own status. One that had to be stopped gives 124, or 137 when it
; was killed outright, unless --preserve-status asks for what the child
; really exited with. A command that could not be run at all gives 126, one
; that could not be found gives 127, and anything wrong with the arguments
; gives 125.

    %include "include/sysdefs.inc"

    %define SYS_POLL_ID 7
    %define SYS_PIPE_ID 22
    %define SYS_DUP2_ID 33
    %define SYS_FORK_ID 57
    %define SYS_EXECVE_ID 59
    %define SYS_WAIT4_ID 61
    %define SYS_KILL_ID 62
    %define SYS_SETPGID_ID 109

    %define POLLIN_EVENT 1
    %define POLLHUP_EVENT 0x10

    %define SIGKILL_NUM 9
    %define SIGTERM_NUM 15

    %define PATHCAP 4096
    %define MAXARGS 256

section .bss
    pollfds     resb 8
    pipefds     resd 2
    childpid    resq 1
    waitstatus  resd 2
    pathbuf     resb PATHCAP
    childargv   resq MAXARGS
    envp        resq 1
    duration_ms resq 1
    kill_ms     resq 1
    signum      resq 1
    exitcode    resq 1
    childrc     resq 1
    opt_i       resb 1
    opt_v       resb 1
    opt_fg      resb 1
    opt_preserve resb 1
    have_k      resb 1
    passbuf     resb 65536

section .data
    l_foreground db "foreground", 0
    l_preserve  db "preserve-status", 0
    l_signal    db "signal", 0

e_usage     db "timeout: usage: timeout [-iv] [-k DURATION] [-s SIGNAL] DURATION COMMAND...", 10
    e_usage_len equ $ - e_usage
e_badsig    db "timeout: bad -s", 10
    e_badsig_l  equ $ - e_badsig
e_badtime   db "timeout: bad duration", 10
    e_badtime_l equ $ - e_badtime
v_head      db "timeout: sending signal ", 0
    v_middle    db " to command ", 0

    signames    db "HUP", 0, "INT", 0, "QUIT", 0, "ILL", 0, "TRAP", 0
    db "ABRT", 0, "BUS", 0, "FPE", 0, "KILL", 0, "USR1", 0
    db "SEGV", 0, "USR2", 0, "PIPE", 0, "ALRM", 0, "TERM", 0
    db "STKFLT", 0, "CHLD", 0, "CONT", 0, "STOP", 0, "TSTP", 0
    db "TTIN", 0, "TTOU", 0, "URG", 0, "XCPU", 0, "XFSZ", 0
    db "VTALRM", 0, "PROF", 0, "WINCH", 0, "IO", 0, "PWR", 0
    db "SYS", 0
    signame_count equ 31

    env_path    db "PATH=", 0
default_path db "/usr/bin:/bin", 0

section .text
global _start

_start:
    mov     r14, [rsp]                  ;argc
    lea     r15, [rsp + 8]              ;argv
    lea     rax, [rsp + r14 * 8 + 16]
    mov     [envp], rax
    mov     qword [signum], SIGTERM_NUM
    mov     r12, 1
.arg:
    cmp     r12, r14
    jae     .parsed
    mov     rbx, [r15 + r12 * 8]
    cmp     byte [rbx], '-'
    jne     .parsed                     ;the first thing that is not an option
    cmp     byte [rbx + 1], 0
    je      .parsed
    cmp     byte [rbx + 1], '-'
    je      .longopt
    inc     rbx
.letter:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .nextarg
    inc     rbx
    cmp     al, 'i'
    je      .f_i
    cmp     al, 'v'
    je      .f_v
    cmp     al, 'k'
    je      .f_k
    cmp     al, 's'
    je      .f_s
    jmp     usage_error
.f_i:
    mov     byte [opt_i], 1
    jmp     .letter
.f_v:
    mov     byte [opt_v], 1
    jmp     .letter
.f_k:
    call    option_value
    mov     rdi, rax
    call    parse_duration
    mov     [kill_ms], rax
    mov     byte [have_k], 1
    jmp     .nextarg
.f_s:
    call    option_value
    mov     rdi, rax
    call    parse_signal
    mov     [signum], rax
    jmp     .nextarg
.longopt:
    add     rbx, 2
    mov     rdi, rbx
    mov     rsi, l_foreground
    call    same_string
    test    al, al
    jz      .l_preserve
    mov     byte [opt_fg], 1
    jmp     .nextarg
.l_preserve:
    mov     rdi, rbx
    mov     rsi, l_preserve
    call    same_string
    test    al, al
    jz      .l_signal
    mov     byte [opt_preserve], 1
    jmp     .nextarg
.l_signal:
    mov     rdi, rbx
    mov     rsi, l_signal
    call    long_value                  ;-> rax, or zero when it is not this
    test    rax, rax
    jz      usage_error
    mov     rdi, rax
    call    parse_signal
    mov     [signum], rax
.nextarg:
    inc     r12
    jmp     .arg

.parsed:
; a duration and a command, at the least
    mov     rax, r14
    sub     rax, r12
    cmp     rax, 2
    jl      usage_error
    mov     rdi, [r15 + r12 * 8]
    call    parse_duration
    mov     [duration_ms], rax
    inc     r12
; the command and its arguments, as the child will see them
    xor     rcx, rcx
.copyarg:
    cmp     r12, r14
    jae     .copied
    cmp     rcx, MAXARGS - 1
    jae     .copied
    mov     rax, [r15 + r12 * 8]
    mov     [childargv + rcx * 8], rax
    inc     rcx
    inc     r12
    jmp     .copyarg
.copied:
    mov     qword [childargv + rcx * 8], 0
    call    run_child
    mov     rdi, [exitcode]
    mov     rax, SYS_EXIT
    syscall

option_value:
    cmp     byte [rbx], 0
    jne     .attached
    inc     r12
    cmp     r12, r14
    jae     usage_error
    mov     rax, [r15 + r12 * 8]
    ret
.attached:
    mov     rax, rbx
    ret

; long_value: the text after "name=", or the next argument, or zero when the
; option at rdi is not the one named by rsi.
long_value:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    xor     rcx, rcx
.byte:
    movzx   eax, byte [r12 + rcx]
    test    al, al
    jz      .matched
    cmp     al, [rbx + rcx]
    jne     .no
    inc     rcx
    jmp     .byte
.matched:
    movzx   eax, byte [rbx + rcx]
    test    al, al
    jz      .separate
    cmp     al, '='
    jne     .no
    lea     rax, [rbx + rcx + 1]
    pop     r12
    pop     rbx
    ret
.separate:
    pop     r12
    pop     rbx
    inc     r12
    cmp     r12, r14
    jae     usage_error
    mov     rax, [r15 + r12 * 8]
    ret
.no:
    xor     rax, rax
    pop     r12
    pop     rbx
    ret

usage_error:
    write   STDERR_FILENO, e_usage, e_usage_len
    exit    125

bad_signal:
    write   STDERR_FILENO, e_badsig, e_badsig_l
    exit    125

bad_duration:
    write   STDERR_FILENO, e_badtime, e_badtime_l
    exit    125

; ---------------------------------------------------------------------------
; parse_duration: a decimal number of seconds, which may have a fraction and
; may be followed by m, h or d. rax comes back in milliseconds.
; ---------------------------------------------------------------------------
parse_duration:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    xor     r12, r12                    ;whole seconds
    xor     r13, r13                    ;thousandths
    xor     rcx, rcx                    ;digits of the fraction taken
    cmp     byte [rbx], 0
    je      bad_duration
    xor     r8, r8                      ;digits seen at all
.whole:
    movzx   eax, byte [rbx]
    sub     al, '0'
    cmp     al, 9
    ja      .fraction
    imul    r12, r12, 10
    movzx   edx, al
    add     r12, rdx
    inc     rbx
    inc     r8
    jmp     .whole
.fraction:
    cmp     byte [rbx], '.'
    jne     .suffix
    inc     rbx
.fracdigit:
    movzx   eax, byte [rbx]
    sub     al, '0'
    cmp     al, 9
    ja      .suffix
    inc     r8
    cmp     rcx, 3
    jae     .skipdigit
    imul    r13, r13, 10
    movzx   edx, al
    add     r13, rdx
    inc     rcx
.skipdigit:
    inc     rbx
    jmp     .fracdigit
.suffix:
    test    r8, r8
    jz      bad_duration
.pad:
    cmp     rcx, 3
    jae     .scaled
    imul    r13, r13, 10
    inc     rcx
    jmp     .pad
.scaled:
    imul    r12, r12, 1000
    add     r12, r13
    movzx   eax, byte [rbx]
    test    al, al
    jz      .done
    cmp     al, 's'
    je      .oneleft
    cmp     al, 'm'
    je      .minutes
    cmp     al, 'h'
    je      .hours
    cmp     al, 'd'
    je      .days
    jmp     bad_duration
.minutes:
    imul    r12, r12, 60
    jmp     .oneleft
.hours:
    imul    r12, r12, 3600
    jmp     .oneleft
.days:
    imul    r12, r12, 86400
.oneleft:
    cmp     byte [rbx + 1], 0
    jne     bad_duration
.done:
    mov     rax, r12
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; parse_signal: a number, or a name with or without its SIG in front.
; ---------------------------------------------------------------------------
parse_signal:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    movzx   eax, byte [rbx]
    sub     al, '0'
    cmp     al, 9
    ja      .byname
    xor     rax, rax
    xor     rcx, rcx
.digit:
    movzx   edx, byte [rbx + rcx]
    test    dl, dl
    jz      .checked
    sub     dl, '0'
    cmp     dl, 9
    ja      bad_signal
    imul    rax, rax, 10
    movzx   edx, dl
    add     rax, rdx
    inc     rcx
    jmp     .digit
.checked:
    test    rax, rax
    jz      bad_signal
    cmp     rax, 64
    ja      bad_signal
    pop     r13
    pop     r12
    pop     rbx
    ret
.byname:
    mov     rdi, rbx
    mov     rsi, sig_prefix
    call    starts_with_word
    test    al, al
    jz      .search
    add     rbx, 3
.search:
    mov     r12, signames
    xor     r13, r13
.name:
    cmp     r13, signame_count
    jae     bad_signal
    mov     rdi, rbx
    mov     rsi, r12
    call    same_string_fold
    test    al, al
    jnz     .found
    mov     rdi, r12
    call    strlen_of
    lea     r12, [r12 + rax + 1]
    inc     r13
    jmp     .name
.found:
    lea     rax, [r13 + 1]
    pop     r13
    pop     r12
    pop     rbx
    ret

starts_with_word:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rsi + rcx]
    test    al, al
    jz      .yes
    movzx   edx, byte [rdi + rcx]
    call    upper_dl
    cmp     al, dl
    jne     .no
    inc     rcx
    jmp     .byte
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

upper_dl:
    cmp     dl, 'a'
    jb      .out
    cmp     dl, 'z'
    ja      .out
    sub     dl, 32
.out:
    ret

same_string_fold:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rsi + rcx]
    movzx   edx, byte [rdi + rcx]
    call    upper_dl
    cmp     al, dl
    jne     .no
    test    al, al
    jz      .yes
    inc     rcx
    jmp     .byte
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

same_string:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rdi + rcx]
    cmp     al, [rsi + rcx]
    jne     .no
    test    al, al
    jz      .yes
    inc     rcx
    jmp     .byte
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

strlen_of:
    xor     rax, rax
.byte:
    cmp     byte [rdi + rax], 0
    je      .out
    inc     rax
    jmp     .byte
.out:
    ret

; ---------------------------------------------------------------------------
; run_child: start the command and wait for whichever comes first, the
; command finishing or the clock running out.
; ---------------------------------------------------------------------------
run_child:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rax, SYS_PIPE_ID
    mov     rdi, pipefds
    syscall
    mov     rax, SYS_FORK_ID
    syscall
    test    rax, rax
    js      .forkfailed
    jnz     .parent
; the child keeps the far end of the pipe, so that its closing says the
; command is over
    mov     rax, SYS_CLOSE
    mov     edi, [pipefds]
    syscall
    cmp     byte [opt_fg], 0
    jne     .nogroup
    mov     rax, SYS_SETPGID_ID
    xor     rdi, rdi
    xor     rsi, rsi
    syscall
.nogroup:
    cmp     byte [opt_i], 0
    je      .keepstdout
    mov     rax, SYS_DUP2_ID
    mov     edi, [pipefds + 4]
    mov     rsi, STDOUT_FILENO
    syscall
.keepstdout:
    call    exec_command
    jmp     .out                        ;never reached
.parent:
    mov     [childpid], rax
    cmp     byte [opt_fg], 0
    jne     .nosetgroup
    mov     rax, SYS_SETPGID_ID
    mov     rdi, [childpid]
    mov     rsi, rdi
    syscall
.nosetgroup:
    mov     rax, SYS_CLOSE
    mov     edi, [pipefds + 4]
    syscall
    mov     eax, [pipefds]
    mov     [pollfds], eax
    mov     word [pollfds + 4], POLLIN_EVENT
    mov     r13, [duration_ms]
    mov     r14, [signum]
.wait:
    mov     word [pollfds + 6], 0
    mov     rax, SYS_POLL_ID
    mov     rdi, pollfds
    mov     rsi, 1
    mov     rdx, r13
    syscall
    cmp     rax, 0
    jl      .interrupted
    je      .timedout
    movzx   eax, word [pollfds + 6]
    test    al, POLLIN_EVENT
    jz      .checkhup
    call    pass_output
    test    al, al
    jz      .finished
    cmp     byte [opt_i], 0
    je      .wait
    mov     r13, [duration_ms]          ;-i counts idleness, not elapsed time
    jmp     .wait
.checkhup:
    movzx   eax, word [pollfds + 6]
    test    al, POLLHUP_EVENT
    jnz     .finished
    jmp     .wait
.interrupted:
    cmp     rax, -4                     ;EINTR
    je      .wait
    jmp     .finished
.timedout:
    cmp     byte [opt_v], 0
    je      .signal
    call    say_signal
.signal:
    mov     qword [exitcode], 124
    cmp     r14, SIGKILL_NUM
    jne     .storesig
    mov     qword [exitcode], 137
.storesig:
    mov     rax, SYS_KILL_ID
    mov     rdi, [childpid]
    cmp     byte [opt_fg], 0
    jne     .sendone
    neg     rdi
.sendone:
    mov     rsi, r14
    syscall
    cmp     byte [have_k], 0
    je      .finished
    cmp     r14, SIGKILL_NUM
    je      .finished
    mov     r14, SIGKILL_NUM
    mov     r13, [kill_ms]
    jmp     .wait
.finished:
    mov     rax, SYS_CLOSE
    mov     edi, [pipefds]
    syscall
    mov     rax, SYS_WAIT4_ID
    mov     rdi, [childpid]
    mov     rsi, waitstatus
    xor     rdx, rdx
    xor     r10, r10
    syscall
    mov     eax, [waitstatus]
    mov     ecx, eax
    and     ecx, 0x7F
    test    ecx, ecx
    jnz     .bysignal
    shr     eax, 8
    and     eax, 0xFF
    mov     [childrc], rax
    jmp     .settle
.bysignal:
    add     rcx, 128
    mov     [childrc], rcx
.settle:
    cmp     byte [opt_preserve], 0
    jne     .takechild
    cmp     qword [exitcode], 0
    jne     .out
.takechild:
    mov     rax, [childrc]
    mov     [exitcode], rax
    jmp     .out
.forkfailed:
    mov     qword [exitcode], 125
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; pass_output: what the command wrote, handed on. al = 1 while there is more
; to come.
pass_output:
    push    rbx
    mov     rax, SYS_READ
    mov     edi, [pipefds]
    mov     rsi, passbuf
    mov     rdx, 65536
    syscall
    cmp     rax, 0
    jg      .write
    cmp     rax, -4                     ;EINTR
    je      .more
    xor     al, al
    pop     rbx
    ret
.write:
    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, passbuf
    syscall
.more:
    mov     al, 1
    pop     rbx
    ret

; say_signal: what is about to be sent, and to what.
say_signal:
    push    rbx
    push    r12
    mov     rdi, v_head
    call    err_str
    mov     rdi, r14
    call    signal_name                 ;-> rax
    mov     rdi, rax
    call    err_str
    mov     rdi, v_middle
    call    err_str
    mov     rdi, [childargv]
    call    err_str
    mov     byte [pathbuf], WHITESPACE_NL
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, pathbuf
    mov     rdx, 1
    syscall
    pop     r12
    pop     rbx
    ret

; signal_name: the name of signal rdi, or its number when it has none.
signal_name:
    push    rbx
    push    r12
    mov     rbx, rdi
    cmp     rbx, 1
    jb      .number
    cmp     rbx, signame_count
    ja      .number
    mov     r12, signames
    dec     rbx
.step:
    test    rbx, rbx
    jz      .found
    mov     rdi, r12
    call    strlen_of
    lea     r12, [r12 + rax + 1]
    dec     rbx
    jmp     .step
.found:
    mov     rax, r12
    pop     r12
    pop     rbx
    ret
.number:
    mov     rax, rbx
    mov     rcx, pathbuf + 32
    mov     byte [rcx], 0
    mov     r12, 10
.digit:
    dec     rcx
    xor     rdx, rdx
    div     r12
    add     dl, '0'
    mov     [rcx], dl
    test    rax, rax
    jnz     .digit
    mov     rax, rcx
    pop     r12
    pop     rbx
    ret

err_str:
    push    rbx
    push    r12
    mov     rbx, rdi
    call    strlen_of
    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, rbx
    syscall
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; exec_command: become the command. A name with a slash in it is taken as it
; stands; anything else is looked for along PATH. Not being able to run
; something and not being able to find it are told apart, since the two have
; different exit statuses.
; ---------------------------------------------------------------------------
exec_command:
    push    rbx
    push    r12
    push    r13
    mov     rbx, [childargv]
    mov     rdi, rbx
    call    has_slash
    test    al, al
    jz      .search
    mov     rax, SYS_EXECVE_ID
    mov     rdi, rbx
    mov     rsi, childargv
    mov     rdx, [envp]
    syscall
    mov     rdi, 126
    cmp     rax, -2                     ;ENOENT
    jne     .quit
    mov     rdi, 127
    jmp     .quit
.search:
    mov     rdi, env_path
    call    getenv_value
    mov     r12, rax
    test    r12, r12
    jnz     .walk
    mov     r12, default_path
.walk:
    mov     r13, 127                    ;nothing found so far
    xor     rcx, rcx
.component:
    movzx   eax, byte [r12]
    test    al, al
    jz      .lastone
cmp     al, ':'
    je      .attempt
    mov     [pathbuf + rcx], al
    inc     rcx
    inc     r12
    jmp     .component
.attempt:
    push    rcx
    call    try_exec
    pop     rcx
    inc     r12
    xor     rcx, rcx
    jmp     .component
.lastone:
    call    try_exec
    mov     rdi, r13
.quit:
    mov     rax, SYS_EXIT
    syscall

; try_exec: try to become childargv[0] found under the rcx characters already
; in pathbuf. Returns when it could not.
try_exec:
    push    rbx
    mov     byte [pathbuf + rcx], '/'
    inc     rcx
    xor     rdx, rdx
.name:
    movzx   eax, byte [rbx + rdx]
    mov     [pathbuf + rcx + rdx], al
    test    al, al
    jz      .ready
    inc     rdx
    jmp     .name
.ready:
    mov     rax, SYS_EXECVE_ID
    mov     rdi, pathbuf
    mov     rsi, childargv
    mov     rdx, [envp]
    syscall
    cmp     rax, -2                     ;ENOENT leaves the verdict alone
    je      .out
    mov     r13, 126                    ;it is there, but it would not run
.out:
    pop     rbx
    ret

has_slash:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rdi + rcx]
    test    al, al
    jz      .no
    cmp     al, '/'
    je      .yes
    inc     rcx
    jmp     .byte
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

getenv_value:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, [envp]
.entry:
    mov     rsi, [r12]
    test    rsi, rsi
    jz      .none
    mov     rdi, rbx
    call    prefix_of
    test    al, al
    jnz     .found
    add     r12, 8
    jmp     .entry
.found:
    mov     rdi, rbx
    call    strlen_of
    add     rax, [r12]
    pop     r12
    pop     rbx
    ret
.none:
    xor     rax, rax
    pop     r12
    pop     rbx
    ret

prefix_of:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rdi + rcx]
    test    al, al
    jz      .yes
    cmp     al, [rsi + rcx]
    jne     .no
    inc     rcx
    jmp     .byte
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

section .data
    sig_prefix  db "SIG", 0
