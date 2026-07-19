; src/cmp.asm -- cmp(1): compare two files.
; Usage: cmp [-l] [-s] [-n N] FILE1 FILE2 [SKIP1 [SKIP2]]   ("-" = stdin).

    %include "include/sysdefs.inc"

    %define BUFSZ 1048576

section .bss
    buf1        resb BUFSZ
    buf2        resb BUFSZ
    numbuf      resb 32
    name1       resq 1
    name2       resq 1
    n1          resq 1
    n2          resq 1
    skip1       resq 1
    skip2       resq 1
    limit       resq 1
    eff1v       resq 1
    eff2v       resq 1
    l_flag      resb 1
    s_flag      resb 1

section .data
s_differ    db " differ: char "
    s_differ_len equ $ - s_differ
    s_line      db ", line "
    s_line_len  equ $ - s_line
s_eof       db "cmp: EOF on "
    s_eof_len   equ $ - s_eof
    s_after     db " after byte "
    s_after_len equ $ - s_after
s_open      db "cmp: cannot open file", WHITESPACE_NL
    s_open_len  equ $ - s_open
    spc         db " "
    nl          db WHITESPACE_NL
    dash        db "-", 0

section .text
global _start

_start:
    mov     byte [l_flag], 0
    mov     byte [s_flag], 0
    mov     qword [limit], -1
    mov     qword [skip1], 0
    mov     qword [skip2], 0
    mov     qword [name1], 0
    mov     qword [name2], 0

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12
    xor     r14, r14                    ;positional index

parse:
    cmp     r12, 0
    je      run
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .positional
    cmp     byte [rdi + 1], 0
    je      .positional                 ;lone "-" is an operand
    inc     rdi
.char:
    movzx   eax, byte [rdi]
    test    al, al
    je      .next
    cmp     al, 'l'
    je      .set_l
    cmp     al, 's'
    je      .set_s
    cmp     al, 'n'
    je      .set_n
    inc     rdi
    jmp     .char
.set_l:
    mov     byte [l_flag], 1
    inc     rdi
    jmp     .char
.set_s:
    mov     byte [s_flag], 1
    inc     rdi
    jmp     .char
.set_n:
    inc     rdi
    cmp     byte [rdi], 0
    jne     .n_here
    add     r13, 8
    dec     r12
    mov     rdi, [r13]
.n_here:
    call    atou
    mov     [limit], rax
    jmp     .next
.positional:
    mov     rdi, [r13]
    cmp     r14, 0
    je      .p0
    cmp     r14, 1
    je      .p1
    cmp     r14, 2
    je      .p2
    call    atou
    mov     [skip2], rax
    jmp     .padv
.p0:
    mov     [name1], rdi
    jmp     .padv
.p1:
    mov     [name2], rdi
    jmp     .padv
.p2:
    call    atou
    mov     [skip1], rax
.padv:
    inc     r14
.next:
    add     r13, 8
    dec     r12
    jmp     parse

run:
    cmp     qword [name1], 0
    je      usage
    cmp     qword [name2], 0
    jne     .have2
    mov     qword [name2], dash         ;a single file compares against stdin
.have2:

    mov     rdi, [name1]
    mov     rsi, buf1
    call    read_file
    cmp     rax, -1
    je      open_error
    mov     [n1], rax

    mov     rdi, [name2]
    mov     rsi, buf2
    call    read_file
    cmp     rax, -1
    je      open_error
    mov     [n2], rax

;effective lengths after the skips
    mov     rax, [n1]
    sub     rax, [skip1]
    jns     .e1ok
    xor     rax, rax
.e1ok:
    mov     r8, rax                     ;eff1
    mov     rax, [n2]
    sub     rax, [skip2]
    jns     .e2ok
    xor     rax, rax
.e2ok:
    mov     r9, rax                     ;eff2
    mov     [eff1v], r8
    mov     [eff2v], r9

;minlen = min(eff1, eff2)
    mov     r13, r8
    cmp     r9, r13
    jae     .have_min
    mov     r13, r9
.have_min:
;cmplen = min(minlen, limit); r14 survives the -l loop's write syscalls
    mov     r14, r13
    cmp     r14, [limit]
    jbe     .have_cmp
    mov     r14, [limit]
.have_cmp:
    mov     rbx, buf1
    add     rbx, [skip1]                ;compare base 1
    mov     rbp, buf2
    add     rbp, [skip2]                ;compare base 2

    xor     r15, r15                    ;i
    xor     r10, r10                    ;newline count in matched prefix
    xor     r12, r12                    ;any-difference flag
.loop:
    cmp     r15, r14
    jge     .after
    movzx   rax, byte [rbx + r15]
    movzx   rdx, byte [rbp + r15]
    cmp     al, dl
    jne     .diff
    cmp     al, WHITESPACE_NL
    jne     .adv
    inc     r10
.adv:
    inc     r15
    jmp     .loop
.diff:
    mov     r12, 1                      ;a difference was seen
    cmp     byte [l_flag], 1
    je      .diff_l
;default: report first difference and stop
    cmp     byte [s_flag], 1
    je      .exit_diff
;"NAME1 NAME2 differ: char POS, line LINE"
    mov     rsi, [name1]
    call    put_cstr_stdout
    write   STDOUT_FILENO, spc, 1
    mov     rsi, [name2]
    call    put_cstr_stdout
    write   STDOUT_FILENO, s_differ, s_differ_len
    lea     rdi, [r15 + 1]
    call    put_dec_stdout
    write   STDOUT_FILENO, s_line, s_line_len
    lea     rdi, [r10 + 1]
    call    put_dec_stdout
    write   STDOUT_FILENO, nl, 1
.exit_diff:
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall
.diff_l:
;list this byte: "POS OCT1 OCT2"
    cmp     byte [s_flag], 1
    je      .adv
    push    rax
    push    rdx
    lea     rdi, [r15 + 1]
    call    put_dec_stdout
    write   STDOUT_FILENO, spc, 1
    pop     rdx
    pop     rax
    push    rdx
    mov     rdi, rax
    call    put_oct_stdout
    write   STDOUT_FILENO, spc, 1
    pop     rdx
    mov     rdi, rdx
    call    put_oct_stdout
    write   STDOUT_FILENO, nl, 1
    jmp     .adv

.after:
    mov     r8, [eff1v]
    mov     r9, [eff2v]
;compared cmplen bytes with no early exit (default) or listed diffs (-l)
    cmp     r14, r13
jb      .finish                     ;stopped at the -n limit: no EOF
;cmplen == minlen: EOF unless the effective lengths are equal
    cmp     r8, r9
    je      .finish
;the shorter file hit EOF
    mov     r12, 1
    cmp     byte [s_flag], 1
    je      .finish
;pick the shorter file's name
    mov     rsi, [name1]
    cmp     r8, r9
    jb      .have_name
    mov     rsi, [name2]
.have_name:
    push    rsi
    write   STDERR_FILENO, s_eof, s_eof_len
    pop     rsi
    call    put_cstr_stderr
    write   STDERR_FILENO, s_after, s_after_len
    mov     rdi, r13                    ;byte = minlen
    call    put_dec_stderr
    cmp     byte [l_flag], 1
    je      .eof_nl
    write   STDERR_FILENO, s_line, s_line_len
    lea     rdi, [r10]                  ;line = newlines in the matched prefix
    call    put_dec_stderr
.eof_nl:
    write   STDERR_FILENO, nl, 1
.finish:
    mov     rdi, r12                    ;1 if any difference/EOF else 0
    mov     rax, SYS_EXIT
    syscall

usage:
    write   STDERR_FILENO, s_open, s_open_len
    mov     rdi, 2
    mov     rax, SYS_EXIT
    syscall

open_error:
    cmp     byte [s_flag], 1
    je      .quiet
    write   STDERR_FILENO, s_open, s_open_len
.quiet:
    mov     rdi, 2
    mov     rax, SYS_EXIT
    syscall

; read_file: rdi = name ("-" = stdin), rsi = buffer; rax = length or -1
read_file:
    mov     r10, rsi                    ;buffer base
    cmp     byte [rdi], '-'
    jne     .open
    cmp     byte [rdi + 1], 0
    jne     .open
    xor     r8, r8                      ;stdin
    jmp     .rd
.open:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fail
    mov     r8, rax                     ;fd
.rd:
    xor     r9, r9                      ;bytes read so far (r11 is clobbered by syscall)
.loop:
    mov     rdx, BUFSZ
    sub     rdx, r9
    jle     .done
    mov     rax, SYS_READ
    mov     rdi, r8
    lea     rsi, [r10 + r9]
    syscall
    cmp     rax, 0
    jle     .done
    add     r9, rax
    jmp     .loop
.done:
    test    r8, r8
    jz      .ret
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
.ret:
    mov     rax, r9
    ret
.fail:
    mov     rax, -1
    ret

; --- number/string output helpers ---
put_cstr_stdout:
    mov     r9, STDOUT_FILENO
    jmp     put_cstr
put_cstr_stderr:
    mov     r9, STDERR_FILENO
put_cstr:
    push    rsi
    call    strlen
    mov     rax, SYS_WRITE
    mov     rdi, r9
    pop     rsi
    mov     rdx, rbx
    syscall
    ret

put_dec_stdout:
    mov     r9, STDOUT_FILENO
    jmp     put_dec
put_dec_stderr:
    mov     r9, STDERR_FILENO
put_dec:
    mov     rcx, numbuf
    add     rcx, 31
    mov     r8, 10
    jmp     put_num
put_oct_stdout:
    mov     r9, STDOUT_FILENO
put_oct:
    mov     rcx, numbuf
    add     rcx, 31
    mov     r8, 8
put_num:
    mov     rax, rdi
.d:
    xor     rdx, rdx
    div     r8
    add     dl, '0'
    dec     rcx
    mov     [rcx], dl
    test    rax, rax
    jnz     .d
    mov     rax, SYS_WRITE
    mov     rdi, r9
    mov     rsi, rcx
    mov     rdx, numbuf
    add     rdx, 31
    sub     rdx, rcx
    syscall
    ret

; atou: rdi -> unsigned decimal, result in rax
atou:
    xor     rax, rax
.l:
    movzx   rdx, byte [rdi]
    sub     dl, '0'
    cmp     dl, 9
    ja      .d
    imul    rax, rax, 10
    add     rax, rdx
    inc     rdi
    jmp     .l
.d:
    ret
