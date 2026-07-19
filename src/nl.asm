; src/nl.asm -- nl(1): number lines of input.
; Usage: nl [-n rn|ln|rz] [-b a|t|n|pREGEX] [-w WIDTH] [-v START] [-s SEP]
;           [-l NUM] [FILE...]   ("-" or no FILE = stdin).
;
; Each numbered line is printed as NUMBER + SEP + text; a non-numbered line
; keeps the same columns but with the number field and separator replaced by
; spaces. -b selects which lines get numbered (a=all, t=non-empty [default],
; n=none, p=matching REGEX -- here a literal substring). -n selects the number
; format (rn right, ln left, rz right zero-filled). -l NUM groups runs of blank
; lines so only every NUMth blank in a run is numbered (with -b a).

    %include "include/sysdefs.inc"

    %define BUFCAP (8 * 1024 * 1024)

section .bss
    inbuf       resb BUFCAP
    files       resq 256
    numbuf      resb 32
    spacebuf    resb 1
    nfiles      resq 1
    counter     resq 1
    width       resq 1
    lval        resq 1
    blankrun    resq 1
    sep_ptr     resq 1
    sep_len     resq 1
    pat_ptr     resq 1
    pat_len     resq 1
    btype       resb 1
    nfmt        resb 1
    had_err     resb 1
    fi          resq 1
    tmpname     resq 1
    rap_fd      resq 1
    buflen      resq 1
    e_ptr       resq 1
    e_len       resq 1
    rn_digptr   resq 1
    rn_diglen   resq 1
    rn_sign     resq 1
    rn_total    resq 1

section .data
    def_sep     db 9
err_msg     db "nl: cannot open file", WHITESPACE_NL
    err_len     equ $ - err_msg

section .text
global _start

_start:
    mov     qword [counter], 1
    mov     qword [width], 6
    mov     qword [lval], 1
    mov     qword [blankrun], 0
    mov     byte [btype], 't'
    mov     byte [nfmt], 0
    mov     qword [sep_ptr], def_sep
    mov     qword [sep_len], 1
    mov     qword [pat_len], 0
    mov     qword [nfiles], 0
    mov     byte [had_err], 0

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    je      parsed
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .file
    cmp     byte [rdi + 1], 0
    je      .file                       ;lone "-" operand
    lea     rsi, [rdi + 1]
.optchar:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 'b'
    je      .takearg
    cmp     al, 'n'
    je      .takearg
    cmp     al, 's'
    je      .takearg
    cmp     al, 'w'
    je      .takearg
    cmp     al, 'v'
    je      .takearg
    cmp     al, 'l'
    je      .takearg
    cmp     al, 'd'
    je      .takearg
    cmp     al, 'f'
    je      .takearg
    cmp     al, 'h'
    je      .takearg
    inc     rsi                         ;ignore -E, -p, unknown
    jmp     .optchar
.takearg:
    mov     r15d, eax                   ;flag char
    inc     rsi
    cmp     byte [rsi], 0
    jne     .haveval
    add     r13, 8                      ;value is the next argv
    dec     r12
    mov     rsi, [r13]
.haveval:
    call    apply_flag
    jmp     .nextarg
.file:
    mov     rcx, [nfiles]
    mov     [files + rcx*8], rdi
    inc     qword [nfiles]
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

parsed:
    cmp     qword [nfiles], 0
    jne     .files
    mov     rdi, STDIN_FILENO
    call    read_and_process
    jmp     .done
.files:
    mov     qword [fi], 0
.floop:
    mov     rax, [fi]
    cmp     rax, [nfiles]
    jge     .done
    mov     rcx, [fi]
    mov     rdi, [files + rcx*8]
    cmp     byte [rdi], '-'
    jne     .open
    cmp     byte [rdi + 1], 0
    jne     .open
    mov     rdi, STDIN_FILENO
    jmp     .proc
.open:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .openfail
    mov     rdi, rax
.proc:
    call    read_and_process
.fnext:
    inc     qword [fi]
    jmp     .floop
.openfail:
    write   STDERR_FILENO, err_msg, err_len
    mov     byte [had_err], 1
    jmp     .fnext
.done:
    movzx   eax, byte [had_err]
    mov     rdi, rax
    mov     rax, SYS_EXIT
    syscall

; apply_flag: r15 = flag char, rsi = value string. Preserves r12/r13.
apply_flag:
    cmp     r15b, 'b'
    je      .b
    cmp     r15b, 'n'
    je      .n
    cmp     r15b, 's'
    je      .s
    cmp     r15b, 'w'
    je      .w
    cmp     r15b, 'v'
    je      .v
    cmp     r15b, 'l'
    je      .l
    ret                                 ;d, f, h ignored
.b:
    mov     al, [rsi]
    mov     [btype], al
    cmp     al, 'p'
    jne     .ret
    lea     rdi, [rsi + 1]
    mov     [pat_ptr], rdi
    call    mystrlen
    mov     [pat_len], rax
    ret
.n:
    mov     al, [rsi]
    cmp     al, 'l'
    je      .n_ln
    mov     al, [rsi + 1]
    cmp     al, 'z'
    je      .n_rz
    mov     byte [nfmt], 0              ;rn
    ret
.n_ln:
    mov     byte [nfmt], 1
    ret
.n_rz:
    mov     byte [nfmt], 2
    ret
.s:
    mov     [sep_ptr], rsi
    mov     rdi, rsi
    call    mystrlen
    mov     [sep_len], rax
    ret
.w:
    mov     rdi, rsi
    call    atoi_signed
    mov     [width], rax
    ret
.v:
    mov     rdi, rsi
    call    atoi_signed
    mov     [counter], rax
    ret
.l:
    mov     rdi, rsi
    call    atoi_signed
    mov     [lval], rax
.ret:
    ret

; read_and_process: rdi = fd. Reads the whole input into inbuf then numbers
; its lines. Closes non-stdin descriptors. Keeps numbering state across calls.
read_and_process:
    mov     [rap_fd], rdi
    xor     r14, r14                    ;bytes read (survives syscalls)
.rl:
    mov     rdx, BUFCAP
    sub     rdx, r14
    jz      .rdone
    mov     rax, SYS_READ
    mov     rdi, [rap_fd]
    lea     rsi, [inbuf + r14]
    syscall
    test    rax, rax
    jle     .rdone
    add     r14, rax
    jmp     .rl
.rdone:
    mov     [buflen], r14
    mov     rdi, [rap_fd]
    cmp     rdi, STDIN_FILENO
    je      .scan_init
    mov     rax, SYS_CLOSE
    syscall
.scan_init:
    xor     r12, r12                    ;pos
    xor     r13, r13                    ;line start
.scan:
    mov     rax, r12
    cmp     rax, [buflen]
    jge     .tail
    cmp     byte [inbuf + r12], WHITESPACE_NL
    jne     .adv
    lea     rdi, [inbuf + r13]
    mov     rsi, r12
    sub     rsi, r13
    call    emit_line
    lea     r13, [r12 + 1]
.adv:
    inc     r12
    jmp     .scan
.tail:
    cmp     r13, [buflen]
    jge     .filedone
    lea     rdi, [inbuf + r13]
    mov     rsi, [buflen]
    sub     rsi, r13
    call    emit_line
.filedone:
    ret

; emit_line: rdi = text ptr, rsi = length. Preserves r12/r13.
emit_line:
    mov     [e_ptr], rdi
    mov     [e_len], rsi
    xor     r8, r8                      ;empty flag
    test    rsi, rsi
    jnz     .notempty
    mov     r8, 1
.notempty:
    call    should_number
    test    rax, rax
    jz      .unnumbered
    call    render_number
    mov     rsi, [sep_ptr]
    mov     rdx, [sep_len]
    call    put_bytes
    inc     qword [counter]
    jmp     .text
.unnumbered:
    mov     rdi, [width]
    call    put_spaces
    mov     rdi, [sep_len]
    call    put_spaces
.text:
    mov     rsi, [e_ptr]
    mov     rdx, [e_len]
    call    put_bytes
    mov     byte [spacebuf], WHITESPACE_NL
    mov     rsi, spacebuf
    mov     rdx, 1
    call    put_bytes
    ret

; should_number: r8 = empty flag -> rax = 1 if this line gets a number.
should_number:
    movzx   eax, byte [btype]
    cmp     al, 'n'
    je      .no
    cmp     al, 'a'
    je      .all
    cmp     al, 'p'
    je      .pat
test    r8, r8                      ;'t': number non-empty only
    jnz     .no
    mov     rax, 1
    ret
.all:
    test    r8, r8
    jnz     .a_empty
    mov     qword [blankrun], 0
    mov     rax, 1
    ret
.a_empty:
    inc     qword [blankrun]
    mov     rax, [blankrun]
    cmp     rax, [lval]
    jl      .no
    mov     qword [blankrun], 0
    mov     rax, 1
    ret
.pat:
    call    pattern_match
    ret
.no:
    xor     rax, rax
    ret

; pattern_match: literal substring search of [pat_ptr] within the line
; [e_ptr]/[e_len]. rax = 1 on match.
pattern_match:
    mov     r8, [pat_len]
    test    r8, r8
    jz      .yes
    mov     rcx, [e_len]
    sub     rcx, r8                     ;last valid start index
    js      .no
    xor     r9, r9
.outer:
    cmp     r9, rcx
    jg      .no
    mov     rsi, [e_ptr]
    add     rsi, r9
    mov     rdi, [pat_ptr]
    xor     r10, r10
.inner:
    cmp     r10, r8
    jge     .yes
    mov     al, [rsi + r10]
    cmp     al, [rdi + r10]
    jne     .nextpos
    inc     r10
    jmp     .inner
.nextpos:
    inc     r9
    jmp     .outer
.yes:
    mov     rax, 1
    ret
.no:
    xor     rax, rax
    ret

; render_number: write [counter] in the selected format and width to stdout.
render_number:
    mov     rax, [counter]
    xor     r10, r10                    ;sign
    test    rax, rax
    jns     .abs
    mov     r10, 1
    neg     rax
.abs:
    lea     rcx, [numbuf + 31]
    mov     r8, 10
    xor     r9, r9
.dl:
    xor     rdx, rdx
    div     r8
    add     dl, '0'
    dec     rcx
    mov     [rcx], dl
    inc     r9
    test    rax, rax
    jnz     .dl
    mov     [rn_digptr], rcx
    mov     [rn_diglen], r9
    mov     [rn_sign], r10
    add     r9, r10
    mov     [rn_total], r9
    movzx   eax, byte [nfmt]
    cmp     al, 1
    je      .ln
    cmp     al, 2
    je      .rz
;rn: pad with spaces on the left
    mov     rdi, [width]
    sub     rdi, [rn_total]
    call    put_spaces
    call    put_sign
    mov     rsi, [rn_digptr]
    mov     rdx, [rn_diglen]
    jmp     put_bytes
.ln:
    call    put_sign
    mov     rsi, [rn_digptr]
    mov     rdx, [rn_diglen]
    call    put_bytes
    mov     rdi, [width]
    sub     rdi, [rn_total]
    jmp     put_spaces
.rz:
    call    put_sign
    mov     rdi, [width]
    sub     rdi, [rn_total]
    call    put_zeros
    mov     rsi, [rn_digptr]
    mov     rdx, [rn_diglen]
    jmp     put_bytes

; put_sign: emit '-' when [rn_sign] is set.
put_sign:
    cmp     qword [rn_sign], 0
    je      .done
    mov     byte [spacebuf], '-'
    mov     rsi, spacebuf
    mov     rdx, 1
    jmp     put_bytes
.done:
    ret

; put_bytes: rsi = ptr, rdx = length -> stdout (nothing when length <= 0).
put_bytes:
    test    rdx, rdx
    jle     .done
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
.done:
    ret

; put_spaces: rdi = count spaces to stdout (preserves the counter across write).
put_spaces:
    test    rdi, rdi
    jle     .done
    mov     byte [spacebuf], ' '
.l:
    push    rdi
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, spacebuf
    mov     rdx, 1
    syscall
    pop     rdi
    dec     rdi
    jnz     .l
.done:
    ret

; put_zeros: rdi = count '0' characters to stdout.
put_zeros:
    test    rdi, rdi
    jle     .done
    mov     byte [spacebuf], '0'
.l:
    push    rdi
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, spacebuf
    mov     rdx, 1
    syscall
    pop     rdi
    dec     rdi
    jnz     .l
.done:
    ret

; mystrlen: rdi -> rax length.
mystrlen:
    xor     rax, rax
.l:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .l
.done:
    ret

; atoi_signed: rdi -> signed decimal in rax.
atoi_signed:
    xor     rax, rax
    xor     r8, r8
    cmp     byte [rdi], '-'
    jne     .l
    mov     r8, 1
    inc     rdi
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
    test    r8, r8
    jz      .ret
    neg     rax
.ret:
    ret
