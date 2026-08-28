; src/xargs.asm -- xargs(1): build command lines from input and run them.
; Usage: xargs [-0rt] [-a FILE] [-n MAX] [-s SIZE] [-E EOFSTR] [-P PROCS]
;              [--process-slot-var=VAR] [COMMAND [ARG...]]
;
; Words are collected from the input until the next one would push the command
; line past -s bytes or -n arguments, at which point the batch is run and a
; fresh one started. The size is counted the way xargs counts it: every word,
; the command's own words included, costs its length plus a terminator, which
; is why "-s 13 echo ' ' ' '" has room for exactly one more argument.
;
; Each batch runs in a forked child, so -P can keep several in flight at once;
; a free slot is what limits the fan-out, and --process-slot-var names that
; slot to the child. Child exit statuses follow the usual xargs rules: 1-125
; collapse to 123, 126 and 127 pass through, and 255 prints a message and
; aborts with 124 without starting anything further.

    %include "include/sysdefs.inc"

    %define INCAP 65536
    %define WORDCAP 200000
    %define STORECAP 262144
    %define MAXARGV 70000
    %define MAXPROC 512
    %define MAXENV 4096
    %define DEFAULT_SIZE 131072

section .bss
    inbuf       resb INCAP
    wordbuf     resb WORDCAP
    argstore    resb STORECAP
    argv        resq MAXARGV
    envcopy     resq MAXENV
    slotbuf     resb 64
    slotpid     resq MAXPROC
    envp        resq 1
    infd        resq 1
    afile       resq 1
    eofstr      resq 1
    slotvar     resq 1
    ncmd        resq 1
    nargv       resq 1
    used        resq 1
    wordlen     resq 1
    maxsize     resq 1
    maxargs     resq 1
    maxproc     resq 1
    basesize    resq 1
    cursize     resq 1
    batchcount  resq 1
    running     resq 1
    wstatus     resq 1
    scanpos     resq 1
    scanlen     resq 1
    wordneed    resq 1
    opt_null    resb 1
    opt_trace   resb 1
    opt_norun   resb 1
    eof_seen    resb 1
    ran_any     resb 1
    aborting    resb 1
    final       resb 1

section .data
    default_cmd db "echo", 0
usage_msg   db "Usage: xargs [-0rt] [-a FILE] [-n MAX] [-s SIZE] "
    db "[-E EOFSTR] [-P PROCS] [COMMAND...]", 10
    usage_len   equ $ - usage_msg
toolong_msg db "xargs: argument line too long", 10
    toolong_len equ $ - toolong_msg
openfail    db "xargs: cannot open input file", 10
    openfail_len equ $ - openfail
abort_pre   db "xargs: "
    abort_pre_len equ $ - abort_pre
abort_post  db ": exited with status 255; aborting", 10
    abort_post_len equ $ - abort_post
    l_slotvar   db "--process-slot-var", 0
    l_norun     db "--no-run-if-empty", 0
    l_null      db "--null", 0
    space_ch    db WHITESPACE_SPACE
    newline_ch  db WHITESPACE_NL

section .text
global _start

_start:
    mov     rcx, [rsp]                  ;argc
    lea     rax, [rsp + rcx * 8 + 16]   ;&envp[0]
    mov     [envp], rax
    mov     qword [infd], STDIN_FILENO
    mov     qword [maxsize], DEFAULT_SIZE
    mov     qword [maxproc], 1

    mov     r12, rcx
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    jle     command
    mov     rdi, [r13]
    test    rdi, rdi
    jz      command
    cmp     byte [rdi], '-'
    jne     command                     ;the command starts here
    cmp     byte [rdi + 1], 0
    je      command                     ;a lone "-" is the command
    cmp     byte [rdi + 1], '-'
    jne     .short
    cmp     byte [rdi + 2], 0
    jne     .long
    add     r13, 8                      ;"--" ends the options
    dec     r12
    jmp     command
.long:
    mov     rsi, l_slotvar
    call    longmatch
    test    al, al
    jnz     .set_slotvar
    mov     rsi, l_norun
    call    longmatch
    test    al, al
    jnz     .set_norun
    mov     rsi, l_null
    call    longmatch
    test    al, al
    jnz     .set_null
    jmp     usage
.set_slotvar:
    cmp     al, 2
    je      .slotvar_have
    call    next_value
.slotvar_have:
    mov     [slotvar], rdx
    jmp     .next
.set_norun:
    mov     byte [opt_norun], 1
    jmp     .next
.set_null:
    mov     byte [opt_null], 1
    jmp     .next

.short:
    lea     rsi, [rdi + 1]
.flag:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .next
    inc     rsi
    cmp     al, '0'
    je      .f_null
    cmp     al, 'r'
    je      .f_norun
    cmp     al, 't'
    je      .f_trace
    cmp     al, 'x'
je      .flag                       ;-x is implied: we always split
    cmp     al, 'a'
    je      .f_a
    cmp     al, 'n'
    je      .f_n
    cmp     al, 's'
    je      .f_s
    cmp     al, 'P'
    je      .f_p
    cmp     al, 'E'
    je      .f_e
    cmp     al, 'e'
    je      .f_e
    jmp     usage
.f_null:
    mov     byte [opt_null], 1
    jmp     .flag
.f_norun:
    mov     byte [opt_norun], 1
    jmp     .flag
.f_trace:
    mov     byte [opt_trace], 1
    jmp     .flag
.f_a:
    call    opt_value
    mov     [afile], rdx
    jmp     .next
.f_e:
    call    opt_value
    mov     [eofstr], rdx
    jmp     .next
.f_n:
    call    opt_value
    mov     rdi, rdx
    call    atou
    test    rax, rax
    jz      usage                       ;-n 0 makes no sense
    mov     [maxargs], rax
    jmp     .next
.f_s:
    call    opt_value
    mov     rdi, rdx
    call    atou
    mov     [maxsize], rax
    jmp     .next
.f_p:
    call    opt_value
    mov     rdi, rdx
    call    atou
    test    rax, rax
    jnz     .p_have
    mov     rax, MAXPROC                ;-P 0 means "as many as we can"
.p_have:
    cmp     rax, MAXPROC
    jbe     .p_set
    mov     rax, MAXPROC
.p_set:
    mov     [maxproc], rax
.next:
    add     r13, 8
    dec     r12
    jmp     parse

; opt_value: the rest of this bundle is the value, or the next argument is.
; Leaves the value in rdx.
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

; next_value: the value is the following argument. Leaves it in rdx.
next_value:
    add     r13, 8
    dec     r12
    mov     rdx, [r13]
    test    rdx, rdx
    jz      usage
    ret

; longmatch: does rdi equal the option at rsi, or start with "NAME="? al is 1
; for a bare match, 2 with rdx pointing at an inline value, 0 for no match.
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

; The remaining arguments are the command; with none, xargs runs echo.
command:
    xor     rbx, rbx
.collect:
    cmp     r12, 0
    jle     .done
    mov     rax, [r13]
    test    rax, rax
    jz      .done
    cmp     rbx, MAXARGV - 2
    jae     .done
    mov     [argv + rbx * 8], rax
    inc     rbx
    add     r13, 8
    dec     r12
    jmp     .collect
.done:
    test    rbx, rbx
    jnz     .have
    mov     qword [argv], default_cmd
    mov     rbx, 1
.have:
    mov     [ncmd], rbx
    mov     [nargv], rbx
; Every word costs its length plus a terminator, the command's words included.
    xor     r14, r14
    xor     rcx, rcx
.measure:
    cmp     rcx, rbx
    jge     .sized
    mov     rdi, [argv + rcx * 8]
    call    strlen_z
    add     r14, rax
    inc     r14
    inc     rcx
    jmp     .measure
.sized:
    mov     [basesize], r14
    mov     [cursize], r14
    cmp     r14, [maxsize]
    ja      too_long                    ;no room for the command itself

    mov     rax, [afile]
    test    rax, rax
    jz      read_input
    mov     rax, SYS_OPEN
    mov     rdi, [afile]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .openfail
    mov     [infd], rax
    jmp     read_input
.openfail:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, openfail
    mov     rdx, openfail_len
    syscall
    exit    1

usage:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, usage_msg
    mov     rdx, usage_len
    syscall
    exit    1

too_long:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, toolong_msg
    mov     rdx, toolong_len
    syscall
    call    reap_all
    exit    1

; ---------------------------------------------------------------------------
; read_input: split the input into words, running a batch whenever the next
; word would not fit.
; ---------------------------------------------------------------------------
read_input:
    mov     rax, SYS_READ
    mov     rdi, [infd]
    mov     rsi, inbuf
    mov     rdx, INCAP
    syscall
    test    rax, rax
    jle     input_done
    mov     [scanlen], rax
    mov     qword [scanpos], 0
.byte:
    mov     rcx, [scanpos]
    cmp     rcx, [scanlen]
    jge     read_input
    movzx   eax, byte [inbuf + rcx]
    inc     rcx
    mov     [scanpos], rcx
    cmp     byte [opt_null], 0
    je      .whitespace
    test    al, al
    jz      .boundary
    jmp     .keep
.whitespace:
    cmp     al, WHITESPACE_SPACE
    je      .boundary
    cmp     al, WHITESPACE_NL
    je      .boundary
    cmp     al, WHITESPACE_TAB
    je      .boundary
    cmp     al, 11                      ;vertical tab
    je      .boundary
    cmp     al, 12                      ;form feed
    je      .boundary
    cmp     al, 13                      ;carriage return
    je      .boundary
.keep:
    mov     rcx, [wordlen]
    cmp     rcx, WORDCAP - 1
    jae     too_long
    mov     [wordbuf + rcx], al
    inc     rcx
    mov     [wordlen], rcx
    jmp     .byte
.boundary:
    cmp     qword [wordlen], 0
    je      .byte
    call    finish_word
    cmp     byte [eof_seen], 0
    jne     input_done
    cmp     byte [aborting], 0
    jne     input_done
    jmp     .byte

input_done:
    cmp     byte [aborting], 0
    jne     .wait
    cmp     qword [wordlen], 0
    je      .last
    cmp     byte [eof_seen], 0
    jne     .last
    call    finish_word
.last:
    cmp     byte [aborting], 0
    jne     .wait
    cmp     qword [batchcount], 0
    jne     .flush
    cmp     byte [ran_any], 0
    jne     .wait
    cmp     byte [opt_norun], 0
jne     .wait                       ;-r: nothing to do with no input
.flush:
    call    run_batch
.wait:
    call    reap_all
    movzx   edi, byte [final]
    mov     rax, SYS_EXIT
    syscall

; ---------------------------------------------------------------------------
; finish_word: take the word in wordbuf into the pending batch, running the
; batch first when the word will not fit alongside what is already there.
; ---------------------------------------------------------------------------
finish_word:
    mov     rcx, [wordlen]
    mov     byte [wordbuf + rcx], 0
    mov     rax, [eofstr]
    test    rax, rax
    jz      .fits
    mov     rdi, wordbuf
    mov     rsi, rax
    call    streq
    test    al, al
    jz      .fits
    mov     byte [eof_seen], 1
    mov     qword [wordlen], 0
    ret
.fits:
    mov     rax, [wordlen]
    inc     rax                         ;the word plus its terminator
    mov     [wordneed], rax
    add     rax, [cursize]
    cmp     rax, [maxsize]
    jbe     .room
    cmp     qword [batchcount], 0
    je      too_long                    ;not even one word fits
    call    run_batch
    mov     rax, [cursize]
    add     rax, [wordneed]
    cmp     rax, [maxsize]
    ja      too_long
.room:
    mov     rax, [nargv]
    cmp     rax, MAXARGV - 2
    jae     .split
    mov     rax, [used]
    add     rax, [wordneed]
    cmp     rax, STORECAP
    jb      .store
.split:
    cmp     qword [batchcount], 0
    je      too_long
    call    run_batch
.store:
    mov     rdi, argstore
    add     rdi, [used]
    mov     rax, [nargv]
    mov     [argv + rax * 8], rdi
    inc     rax
    mov     [nargv], rax
    mov     rsi, wordbuf
    mov     rcx, [wordlen]
    inc     rcx                         ;copy the terminator too
    rep     movsb
    mov     rax, [wordlen]
    inc     rax
    add     [used], rax
    add     [cursize], rax
    inc     qword [batchcount]
    mov     qword [wordlen], 0
    mov     rax, [maxargs]
    test    rax, rax
    jz      .out
    cmp     [batchcount], rax
    jb      .out
    call    run_batch
.out:
    ret

; ---------------------------------------------------------------------------
; run_batch: fork a child for the arguments gathered so far, waiting first if
; every -P slot is busy, then reset the batch.
; ---------------------------------------------------------------------------
run_batch:
    cmp     byte [aborting], 0
    jne     .reset
    mov     rax, [nargv]
    mov     qword [argv + rax * 8], 0
    cmp     byte [opt_trace], 0
    je      .space
    call    trace
.space:
    mov     rax, [running]
    cmp     rax, [maxproc]
    jb      .slot
    call    reap_one
    cmp     byte [aborting], 0
    jne     .reset
.slot:
    call    free_slot                   ;-> rbx
    mov     rax, SYS_FORK
    syscall
    test    rax, rax
    js      .reset
    jnz     .parent
; child
    mov     rdi, rbx
    call    child_env
    mov     rdi, [argv]
    mov     rsi, argv
    mov     rdx, [envp]
    call    exec_path
    exit    127                         ;nothing on PATH matched
.parent:
    mov     [slotpid + rbx * 8], rax
    inc     qword [running]
    mov     byte [ran_any], 1
.reset:
    mov     rax, [ncmd]
    mov     [nargv], rax
    mov     qword [used], 0
    mov     qword [batchcount], 0
    mov     rax, [basesize]
    mov     [cursize], rax
    ret

; free_slot: index of a slot with no child in it, in rbx.
free_slot:
    xor     rbx, rbx
.scan:
    cmp     rbx, [maxproc]
    jge     .out
    cmp     qword [slotpid + rbx * 8], 0
    je      .out
    inc     rbx
    jmp     .scan
.out:
    cmp     rbx, MAXPROC
    jb      .ok
    xor     rbx, rbx
.ok:
    ret

; reap_one: wait for any child and fold its status into the exit code.
reap_one:
    cmp     qword [running], 0
    je      .out
    mov     rax, SYS_WAIT4
    mov     rdi, -1
    mov     rsi, wstatus
    xor     rdx, rdx
    xor     r10, r10
    syscall
    test    rax, rax
    js      .out
    mov     rbx, rax
    dec     qword [running]
    xor     rcx, rcx
.find:
    cmp     rcx, MAXPROC
    jge     .status
    cmp     [slotpid + rcx * 8], rbx
    jne     .fnext
    mov     qword [slotpid + rcx * 8], 0
    jmp     .status
.fnext:
    inc     rcx
    jmp     .find
.status:
    call    note_status
.out:
    ret

; reap_all: drain the remaining children.
reap_all:
    cmp     qword [running], 0
    je      .out
    call    reap_one
    jmp     reap_all
.out:
    ret

; note_status: apply the xargs rules to one child's wait status.
note_status:
    mov     eax, [wstatus]
    mov     ecx, eax
    and     ecx, 0x7f
    test    ecx, ecx
    jnz     .signalled
    shr     eax, 8
    and     eax, 0xff
    test    al, al
    jz      .out
    cmp     al, 255
    je      .abort
    cmp     al, 126
    je      .keep
    cmp     al, 127
    je      .keep
    mov     al, 123                     ;1-125 all report as 123
.keep:
    cmp     byte [final], 124
    je      .out                        ;an abort already decided this
    mov     [final], al
    ret
.signalled:
    cmp     byte [final], 124
    je      .out
    mov     byte [final], 125
    ret
.abort:
    mov     byte [aborting], 1
    mov     byte [final], 124
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, abort_pre
    mov     rdx, abort_pre_len
    syscall
    mov     rdi, [argv]
    call    strlen_z
    mov     rdx, rax
    mov     rsi, [argv]
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, abort_post
    mov     rdx, abort_post_len
    syscall
.out:
    ret

; trace: echo the command line on stderr, each word followed by a space.
trace:
    push    rbx
    xor     rbx, rbx
.word:
    mov     rsi, [argv + rbx * 8]
    test    rsi, rsi
    jz      .eol
    mov     rdi, rsi
    call    strlen_z
    mov     rdx, rax
    mov     rsi, [argv + rbx * 8]
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, space_ch
    mov     rdx, 1
    syscall
    inc     rbx
    jmp     .word
.eol:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, newline_ch
    mov     rdx, 1
    syscall
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; child_env: with --process-slot-var, hand the child an environment carrying
; VAR=<slot in rdi>; otherwise leave the environment alone.
; ---------------------------------------------------------------------------
child_env:
    mov     rax, [slotvar]
    test    rax, rax
    jz      .out
    push    rdi
    mov     rsi, rax
    mov     rdi, slotbuf
.name:
    mov     al, [rsi]
    test    al, al
    jz      .eq
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     .name
.eq:
    mov     byte [rdi], '='
    inc     rdi
    pop     rax
    call    u64_to_dec
    mov     byte [rdi], 0
    mov     rcx, rdi
    sub     rcx, slotbuf                ;length including the '='
    mov     r9, [slotvar]
    call    strlen_z_r9
    inc     rax                         ;compare through the '='
    mov     r10, rax
    mov     r8, [envp]
    xor     rcx, rcx                    ;destination index
    xor     rbx, rbx                    ;source index
.copy:
    mov     rsi, [r8 + rbx * 8]
    test    rsi, rsi
    jz      .append
    cmp     rcx, MAXENV - 2
    jae     .append
    mov     rdi, slotbuf
    mov     rdx, r10
    call    memeq
    test    al, al
    jnz     .skip                       ;drop any existing VAR=
    mov     rax, [r8 + rbx * 8]
    mov     [envcopy + rcx * 8], rax
    inc     rcx
.skip:
    inc     rbx
    jmp     .copy
.append:
    mov     qword [envcopy + rcx * 8], slotbuf
    inc     rcx
    mov     qword [envcopy + rcx * 8], 0
    mov     qword [envp], envcopy
.out:
    ret

; memeq: are the first rdx bytes at rdi and rsi the same? al = 1/0.
memeq:
    push    rcx
    xor     rcx, rcx
.scan:
    cmp     rcx, rdx
    jge     .yes
    mov     al, [rdi + rcx]
    cmp     al, [rsi + rcx]
    jne     .no
    inc     rcx
    jmp     .scan
.yes:
    mov     al, 1
    pop     rcx
    ret
.no:
    xor     al, al
    pop     rcx
    ret

; streq: are the NUL-terminated strings at rdi and rsi equal? al = 1/0.
streq:
    push    rdi
    push    rsi
.scan:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .no
    test    al, al
    jz      .yes
    inc     rdi
    inc     rsi
    jmp     .scan
.yes:
    mov     al, 1
    pop     rsi
    pop     rdi
    ret
.no:
    xor     al, al
    pop     rsi
    pop     rdi
    ret

; strlen_z: length of the NUL-terminated string at rdi, in rax.
strlen_z:
    xor     rax, rax
.scan:
    cmp     byte [rdi + rax], 0
    je      .out
    inc     rax
    jmp     .scan
.out:
    ret

; strlen_z_r9: the same, for the string at r9.
strlen_z_r9:
    xor     rax, rax
.scan:
    cmp     byte [r9 + rax], 0
    je      .out
    inc     rax
    jmp     .scan
.out:
    ret

; u64_to_dec: append rax as decimal at rdi, leaving rdi past the last digit.
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

; atou: rdi -> unsigned decimal in rax.
atou:
    xor     rax, rax
.scan:
    movzx   rcx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .out
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .scan
.out:
    ret

; ---------------------------------------------------------------------------
; exec_path: execve rdi with argv rsi and envp rdx, searching PATH when the
; name has no slash in it. Returns only when nothing could be executed.
; ---------------------------------------------------------------------------
exec_path:
    mov     r13, rdi                    ;command name
    mov     r14, rsi                    ;argv
    mov     r15, rdx                    ;envp
    xor     rcx, rcx
.slash:
    mov     al, [r13 + rcx]
    test    al, al
    je      .search
    cmp     al, '/'
    je      .direct
    inc     rcx
    jmp     .slash
.direct:
    mov     rdi, r13
    mov     rsi, r14
    mov     rdx, r15
    mov     rax, SYS_EXECVE
    syscall
    ret
.search:
    mov     rbx, r15
.env:
    mov     rdi, [rbx]
    test    rdi, rdi
    je      .out
    cmp     dword [rdi], 'PATH'
    jne     .envnext
    cmp     byte [rdi + 4], '='
    je      .havepath
.envnext:
    add     rbx, 8
    jmp     .env
.havepath:
    lea     r12, [rdi + 5]
.dir:
    mov     al, [r12]
    test    al, al
    je      .out
    mov     rdi, path_buf
    mov     rbx, rdi
cmp     al, ':'
    jne     .copydir
    mov     byte [rbx], '.'
    inc     rbx
    jmp     .enddir
.copydir:
    mov     al, [r12]
    test    al, al
    je      .enddir
cmp     al, ':'
    je      .enddir
    mov     [rbx], al
    inc     rbx
    inc     r12
    mov     rax, path_buf + 4094
    cmp     rbx, rax
    jae     .nextdir
    jmp     .copydir
.enddir:
    cmp     rbx, rdi
    je      .emptydir
    mov     al, [rbx - 1]
    cmp     al, '/'
    je      .copycmd
    mov     byte [rbx], '/'
    inc     rbx
    jmp     .copycmd
.emptydir:
    mov     byte [rbx], '.'
    inc     rbx
    mov     byte [rbx], '/'
    inc     rbx
.copycmd:
    xor     rcx, rcx
.cmdbyte:
    mov     al, [r13 + rcx]
    mov     [rbx], al
    test    al, al
    je      .try
    inc     rbx
    inc     rcx
    mov     rax, path_buf + 4095
    cmp     rbx, rax
    jae     .nextdir
    jmp     .cmdbyte
.try:
    mov     rdi, path_buf
    mov     rsi, r14
    mov     rdx, r15
    mov     rax, SYS_EXECVE
    syscall
.nextdir:
    mov     al, [r12]
cmp     al, ':'
    jne     .dir
    inc     r12
    jmp     .dir
.out:
    ret

section .bss
    path_buf    resb 4096
