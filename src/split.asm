; src/split.asm -- split(1): break input into pieces.
; Usage: split [-l N] [-b N] [-n N] [-a LEN] [INPUT [PREFIX]]  ("-" = stdin).
;
; The input is buffered, then written to PREFIXaa, PREFIXab, ... : -l groups
; lines (default 1000), -b groups bytes, -n makes N equal byte-sized pieces.
; -a sets the suffix length (default 2); running out of suffixes is an error
; after the files produced so far.

    %include "include/sysdefs.inc"

    %define BUFCAP (8 * 1024 * 1024)

section .bss
    buf         resb BUFCAP
    namebuf     resb 256
    inputname   resq 1
    prefix_ptr  resq 1
    prefix_len  resq 1
    alen        resq 1
    maxsfx      resq 1
    ncount      resq 1
    mode        resb 1                  ;'l', 'b', or 'n'
    sidx        resq 1
    inlen       resq 1
    in_fd       resq 1
    out_fd      resq 1
    posn        resq 1
    wc_start    resq 1
    wc_len      resq 1

section .data
    def_x       db "x", 0
err_exh     db "split: suffixes exhausted", WHITESPACE_NL
    err_exh_len equ $ - err_exh
err_in      db "split: cannot open input", WHITESPACE_NL
    err_in_len  equ $ - err_in

section .text
global _start

_start:
    mov     byte [mode], 'l'
    mov     qword [ncount], 1000
    mov     qword [alen], 2
    mov     qword [inputname], 0
    mov     qword [prefix_ptr], def_x
    mov     qword [posn], 0
    mov     qword [sidx], 0

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    je      after_parse
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .pos
    cmp     byte [rdi + 1], 0
    je      .pos                        ;lone "-" -> stdin operand
    lea     rsi, [rdi + 1]
.oc:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .pnext
    cmp     al, 'l'
    je      .setl
    cmp     al, 'b'
    je      .setb
    cmp     al, 'n'
    je      .setn
    cmp     al, 'a'
    je      .seta
    inc     rsi
    jmp     .oc
.setl:
    mov     byte [mode], 'l'
    call    optval
    mov     [ncount], rax
    jmp     .pnext
.setb:
    mov     byte [mode], 'b'
    call    optval
    mov     [ncount], rax
    jmp     .pnext
.setn:
    mov     byte [mode], 'n'
    call    optval
    mov     [ncount], rax
    jmp     .pnext
.seta:
    call    optval
    mov     [alen], rax
    jmp     .pnext
.pos:
    cmp     qword [posn], 0
    jne     .pos1
    mov     [inputname], rdi
    inc     qword [posn]
    jmp     .pnext
.pos1:
    mov     [prefix_ptr], rdi
    inc     qword [posn]
.pnext:
    add     r13, 8
    dec     r12
    jmp     parse

; optval: value follows the current option char in rsi, else it is the next
; argv. Returns the parsed number in rax; advances r13/r12 when it consumes
; the next argument.
optval:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .here
    add     r13, 8
    dec     r12
    mov     rsi, [r13]
.here:
    mov     rdi, rsi
jmp     atou                        ;tail call: returns to parse

after_parse:
    mov     rdi, [prefix_ptr]
    call    strlen_r
    mov     [prefix_len], rax

    mov     rax, 1                      ;maxsfx = 26^alen
    mov     rcx, [alen]
.pw:
    test    rcx, rcx
    jz      .pwd
    imul    rax, 26
    dec     rcx
    jmp     .pw
.pwd:
    mov     [maxsfx], rax

;read the whole input
    mov     qword [in_fd], STDIN_FILENO
    cmp     qword [inputname], 0
    je      .rdall
    mov     rdi, [inputname]
    cmp     byte [rdi], '-'
    jne     .openin
    cmp     byte [rdi + 1], 0
    je      .rdall
.openin:
    mov     rax, SYS_OPEN
    mov     rdi, [inputname]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      input_err
    mov     [in_fd], rax
.rdall:
    xor     r15, r15
.rl:
    mov     rdx, BUFCAP
    sub     rdx, r15
    jz      .rdone
    mov     rax, SYS_READ
    mov     rdi, [in_fd]
    lea     rsi, [buf + r15]
    syscall
    test    rax, rax
    jle     .rdone
    add     r15, rax
    jmp     .rl
.rdone:
    mov     [inlen], r15

    cmp     byte [mode], 'b'
    je      do_bytes
    cmp     byte [mode], 'n'
    je      do_chunks

; -l: group lines
do_lines:
    xor     r12, r12                    ;chunk start
    xor     r13, r13                    ;pos
    xor     r14, r14                    ;line count
.l:
    cmp     r13, [inlen]
    jge     .tail
    cmp     byte [buf + r13], WHITESPACE_NL
    jne     .adv
    inc     r14
    cmp     r14, [ncount]
    jne     .adv
    lea     rsi, [buf + r12]
    lea     rdx, [r13 + 1]
    sub     rdx, r12
    call    write_chunk
    lea     r12, [r13 + 1]
    xor     r14, r14
.adv:
    inc     r13
    jmp     .l
.tail:
    cmp     r12, [inlen]
    jge     done
    lea     rsi, [buf + r12]
    mov     rdx, [inlen]
    sub     rdx, r12
    call    write_chunk
    jmp     done

; -b: fixed byte chunks
do_bytes:
    xor     r12, r12
.l:
    cmp     r12, [inlen]
    jge     done
    mov     r13, [ncount]
    mov     rax, [inlen]
    sub     rax, r12
    cmp     r13, rax
    jbe     .have
    mov     r13, rax
.have:
    lea     rsi, [buf + r12]
    mov     rdx, r13
    call    write_chunk
    add     r12, r13
    jmp     .l

; -n: N pieces of floor(size/N) bytes; the last piece takes the remainder
do_chunks:
    mov     rax, [inlen]
    xor     rdx, rdx
    div     qword [ncount]
    mov     r15, rax                    ;per-chunk size
    xor     r12, r12                    ;chunk index
    xor     r13, r13                    ;start offset
.l:
    cmp     r12, [ncount]
    jge     done
    lea     rax, [r12 + 1]
    cmp     rax, [ncount]
    je      .last
    mov     rdx, r15                    ;full chunk
    jmp     .have
.last:
mov     rdx, [inlen]                ;last chunk: remainder to end
    sub     rdx, r13
.have:
    lea     rsi, [buf + r13]
    add     r13, rdx
    call    write_chunk
    inc     r12
    jmp     .l

done:
    xor     rdi, rdi
    mov     rax, SYS_EXIT
    syscall

; write_chunk: rsi = ptr, rdx = length -> next output file. Preserves r12-r15.
write_chunk:
    mov     rax, [sidx]
    cmp     rax, [maxsfx]
    jae     exhaust
    mov     [wc_start], rsi
    mov     [wc_len], rdx
    call    make_filename
    mov     rax, SYS_OPEN
    mov     rdi, namebuf
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 0o644
    syscall
    test    rax, rax
    js      exhaust
    mov     [out_fd], rax
    mov     rax, SYS_WRITE
    mov     rdi, [out_fd]
    mov     rsi, [wc_start]
    mov     rdx, [wc_len]
    syscall
    mov     rax, SYS_CLOSE
    mov     rdi, [out_fd]
    syscall
    inc     qword [sidx]
    ret

; make_filename: build PREFIX + base-26 suffix of [sidx] into namebuf.
make_filename:
    mov     rsi, [prefix_ptr]
    mov     rdi, namebuf
    xor     rcx, rcx
.cp:
    cmp     rcx, [prefix_len]
    jge     .suffix
    mov     al, [rsi + rcx]
    mov     [rdi + rcx], al
    inc     rcx
    jmp     .cp
.suffix:
    mov     rax, [sidx]
    mov     rdi, namebuf
    add     rdi, [prefix_len]
    add     rdi, [alen]                 ;one past the last suffix char
    mov     rcx, [alen]
    mov     rbx, 26
.sd:
    xor     rdx, rdx
    div     rbx
    add     dl, 'a'
    dec     rdi
    mov     [rdi], dl
    dec     rcx
    jnz     .sd
    mov     rdi, namebuf
    add     rdi, [prefix_len]
    add     rdi, [alen]
    mov     byte [rdi], 0
    ret

exhaust:
    write   STDERR_FILENO, err_exh, err_exh_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall

input_err:
    write   STDERR_FILENO, err_in, err_in_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall

; strlen_r: rdi -> rax length.
strlen_r:
    xor     rax, rax
.l:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .l
.done:
    ret

; atou: rdi -> unsigned decimal in rax.
atou:
    xor     rax, rax
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
    ret
