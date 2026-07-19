; src/test.asm -- test(1): evaluate a conditional expression, exit 0 if true.
; Implements the POSIX 0..4-argument rules plus leading '!' stacking, with
; string, integer, file-type and file-comparison operators.

    %include "include/sysdefs.inc"

    %define SYS_LSTAT 6
    %define TCGETS 0x5401
    %define S_IFMT 0o170000

section .bss
    statbuf     resb 160
    statbuf2    resb 160
    tcbuf       resb 64
    argvp       resq 1

section .data
    str_bang    db "!", 0
    str_lparen  db "(", 0
    str_rparen  db ")", 0
    unary_ops   db "-n",0,"-z",0,"-e",0,"-f",0,"-d",0,"-b",0,"-c",0,"-p",0
    db "-S",0,"-h",0,"-L",0,"-s",0,"-t",0,"-r",0,"-w",0,"-x",0
    db "-g",0,"-u",0,"-k",0,"-O",0,"-G",0,"-N",0,0
    binary_ops  db "=",0,"==",0,"!=",0,"<",0,">",0,"-eq",0,"-ne",0,"-gt",0
    db "-ge",0,"-lt",0,"-le",0,"-ef",0,"-nt",0,"-ot",0,0

section .text
global _start

_start:
    mov     rax, [rsp]                  ;argc
    lea     rcx, [rsp + 16]             ;&argv[1]
    mov     [argvp], rcx
    dec     rax                         ;operand count
    xor     rdi, rdi                    ;i = 0
    mov     rsi, rax                    ;n
    call    eval
    test    rax, rax
    jz      .false
    xor     rdi, rdi
    jmp     .exit
.false:
    mov     rdi, 1
.exit:
    mov     rax, SYS_EXIT
    syscall

; eval: rdi = start index, rsi = token count -> rax = 1 (true) / 0 (false)
eval:
    push    r12
    push    r13
    push    r14
    mov     r12, rdi                    ;i
    mov     r13, rsi                    ;n
    mov     r14, [argvp]                ;base of the operand vector
    cmp     r13, 0
    je      .false
    cmp     r13, 1
    je      .n1
    cmp     r13, 2
    je      .n2
    cmp     r13, 3
    je      .n3
    cmp     r13, 4
    je      .n4
;n >= 5: only a leading '!' is supported
    mov     rdi, [r14 + r12*8]
    lea     rsi, [str_bang]
    call    streq
    jne     syntax_error
    lea     rdi, [r12 + 1]
    mov     rsi, r13
    dec     rsi
    call    eval
    xor     rax, 1
    jmp     .ret
.false:
    xor     rax, rax
    jmp     .ret
.n1:
    mov     rdi, [r14 + r12*8]
    call    nonempty
    jmp     .ret
.n2:
    mov     rdi, [r14 + r12*8]
    lea     rsi, [str_bang]
    call    streq
    je      .n2_bang
    mov     rdi, [r14 + r12*8]
    lea     rsi, [unary_ops]
    call    in_set
    test    rax, rax
    jz      syntax_error
    mov     rdi, [r14 + r12*8]
    mov     rsi, [r14 + r12*8 + 8]
    call    do_unary
    jmp     .ret
.n2_bang:
    lea     rdi, [r12 + 1]
    mov     rsi, 1
    call    eval
    xor     rax, 1
    jmp     .ret
.n3:
    mov     rdi, [r14 + r12*8 + 8]      ;op
    lea     rsi, [binary_ops]
    call    in_set
    test    rax, rax
    jnz     .n3_bin
    mov     rdi, [r14 + r12*8]
    lea     rsi, [str_bang]
    call    streq
    je      .n3_bang
    mov     rdi, [r14 + r12*8]
    lea     rsi, [str_lparen]
    call    streq
    jne     syntax_error
    mov     rdi, [r14 + r12*8 + 16]
    lea     rsi, [str_rparen]
    call    streq
    jne     syntax_error
    lea     rdi, [r12 + 1]
    mov     rsi, 1
    call    eval
    jmp     .ret
.n3_bin:
    mov     rdi, [r14 + r12*8]
    mov     rsi, [r14 + r12*8 + 8]
    mov     rdx, [r14 + r12*8 + 16]
    call    do_binary
    jmp     .ret
.n3_bang:
    lea     rdi, [r12 + 1]
    mov     rsi, 2
    call    eval
    xor     rax, 1
    jmp     .ret
.n4:
    mov     rdi, [r14 + r12*8]
    lea     rsi, [str_bang]
    call    streq
    jne     .n4_paren
    lea     rdi, [r12 + 1]
    mov     rsi, 3
    call    eval
    xor     rax, 1
    jmp     .ret
.n4_paren:
    mov     rdi, [r14 + r12*8]
    lea     rsi, [str_lparen]
    call    streq
    jne     syntax_error
    mov     rdi, [r14 + r12*8 + 24]
    lea     rsi, [str_rparen]
    call    streq
    jne     syntax_error
    lea     rdi, [r12 + 1]
    mov     rsi, 2
    call    eval
.ret:
    and     rax, 1
    pop     r14
    pop     r13
    pop     r12
    ret

syntax_error:
    mov     rdi, 2
    mov     rax, SYS_EXIT
    syscall

; nonempty: rdi -> string; rax = 1 if the first byte is non-NUL
nonempty:
    cmp     byte [rdi], 0
    je      .z
    mov     rax, 1
    ret
.z:
    xor     rax, rax
    ret

; do_unary: rdi = operator, rsi = operand -> rax = 1/0
do_unary:
    mov     al, [rdi + 1]
    cmp     al, 'n'
    je      .u_n
    cmp     al, 'z'
    je      .u_z
    cmp     al, 't'
    je      .u_t
    cmp     al, 'r'
    je      .u_r
    cmp     al, 'w'
    je      .u_w
    cmp     al, 'x'
    je      .u_x
    mov     rdi, rsi                    ;path
    cmp     al, 'e'
    je      .u_e
    cmp     al, 'f'
    je      .u_f
    cmp     al, 'd'
    je      .u_d
    cmp     al, 'b'
    je      .u_b
    cmp     al, 'c'
    je      .u_c
    cmp     al, 'p'
    je      .u_p
    cmp     al, 'S'
    je      .u_sock
    cmp     al, 'h'
    je      .u_lnk
    cmp     al, 'L'
    je      .u_lnk
    cmp     al, 's'
    je      .u_size
    cmp     al, 'g'
    je      .u_sgid
    cmp     al, 'u'
    je      .u_suid
    cmp     al, 'k'
    je      .u_sticky
    xor     rax, rax                    ;-O/-G/-N unsupported
    ret
.u_n:
    mov     rdi, rsi
    call    nonempty
    ret
.u_z:
    cmp     byte [rsi], 0
    je      .true1
    jmp     .false1
.u_t:
    mov     rdi, rsi
    call    atou
    mov     rdi, rax
    mov     rax, SYS_IOCTL
    mov     rsi, TCGETS
    mov     rdx, tcbuf
    syscall
    test    rax, rax
    jz      .true1
    jmp     .false1
.u_r:
    mov     rdi, rsi
    mov     rsi, R_OK
    jmp     .access
.u_w:
    mov     rdi, rsi
    mov     rsi, W_OK
    jmp     .access
.u_x:
    mov     rdi, rsi
    mov     rsi, X_OK
.access:
    mov     rax, SYS_ACCESS
    syscall
    test    rax, rax
    jz      .true1
    jmp     .false1
.u_e:
    call    stat_path
    jns     .true1
    jmp     .false1
.u_f:
    xor     r8, r8
    mov     r9, 0o100000
    jmp     type_is
.u_d:
    xor     r8, r8
    mov     r9, 0o040000
    jmp     type_is
.u_b:
    xor     r8, r8
    mov     r9, 0o060000
    jmp     type_is
.u_c:
    xor     r8, r8
    mov     r9, 0o020000
    jmp     type_is
.u_p:
    xor     r8, r8
    mov     r9, 0o010000
    jmp     type_is
.u_sock:
    xor     r8, r8
    mov     r9, 0o140000
    jmp     type_is
.u_lnk:
mov     r8, 1                       ;lstat: do not follow
    mov     r9, 0o120000
    jmp     type_is
.u_size:
    call    stat_path
    js      .false1
    mov     rax, [statbuf + 48]
    test    rax, rax
    jnz     .true1
    jmp     .false1
.u_sgid:
    mov     r10, 0o2000
    jmp     .bit
.u_suid:
    mov     r10, 0o4000
    jmp     .bit
.u_sticky:
    mov     r10, 0o1000
.bit:
    call    stat_path
    js      .false1
    mov     eax, [statbuf + 24]
    and     rax, r10
    jnz     .true1
    jmp     .false1
.true1:
    mov     rax, 1
    ret
.false1:
    xor     rax, rax
    ret

; stat_path: rdi -> path; stat into statbuf; sign flag set on failure
stat_path:
    mov     rsi, statbuf
    mov     rax, SYS_STAT
    syscall
    test    rax, rax
    ret

; type_is: rdi = path, r8 = follow(0)/lstat(1), r9 = target S_IFMT value
type_is:
    mov     rsi, statbuf
    test    r8, r8
    jnz     .lstat
    mov     rax, SYS_STAT
    jmp     .go
.lstat:
    mov     rax, SYS_LSTAT
.go:
    syscall
    test    rax, rax
    js      .no
    mov     eax, [statbuf + 24]
    and     eax, S_IFMT
    cmp     rax, r9
    je      .yes
.no:
    xor     rax, rax
    ret
.yes:
    mov     rax, 1
    ret

; do_binary: rdi = a, rsi = operator, rdx = b -> rax = 1/0
do_binary:
    cmp     byte [rsi], '-'
    je      .dash
    cmp     byte [rsi], '='
    je      .b_eq
    cmp     byte [rsi], '!'
    je      .b_ne
    cmp     byte [rsi], '<'
    je      .b_lt
    cmp     byte [rsi], '>'
    je      .b_gt
    jmp     syntax_error
.b_eq:
    mov     rsi, rdx
    call    streq
    je      .true2
    jmp     .false2
.b_ne:
    mov     rsi, rdx
    call    streq
    jne     .true2
    jmp     .false2
.b_lt:
    mov     rsi, rdx
    call    strcmp_sign
    cmp     rax, 0
    jl      .true2
    jmp     .false2
.b_gt:
    mov     rsi, rdx
    call    strcmp_sign
    cmp     rax, 0
    jg      .true2
    jmp     .false2
.dash:
    mov     al, [rsi + 1]
    mov     bl, [rsi + 2]
    cmp     al, 'e'
    je      .d_e
    cmp     al, 'n'
    je      .d_n
    cmp     al, 'g'
    je      .d_g
    cmp     al, 'l'
    je      .d_l
    cmp     al, 'o'
    je      .d_o
    jmp     syntax_error
.d_e:
    cmp     bl, 'q'
    je      .int_eq
    cmp     bl, 'f'
    je      .file_ef
    jmp     syntax_error
.d_n:
    cmp     bl, 'e'
    je      .int_ne
    cmp     bl, 't'
    je      .file_nt
    jmp     syntax_error
.d_g:
    cmp     bl, 't'
    je      .int_gt
    cmp     bl, 'e'
    je      .int_ge
    jmp     syntax_error
.d_l:
    cmp     bl, 't'
    je      .int_lt
    cmp     bl, 'e'
    je      .int_le
    jmp     syntax_error
.d_o:
    cmp     bl, 't'
    je      .file_ot
    jmp     syntax_error
.int_eq:
    call    int_pair
    cmp     r8, r9
    je      .true2
    jmp     .false2
.int_ne:
    call    int_pair
    cmp     r8, r9
    jne     .true2
    jmp     .false2
.int_gt:
    call    int_pair
    cmp     r8, r9
    jg      .true2
    jmp     .false2
.int_ge:
    call    int_pair
    cmp     r8, r9
    jge     .true2
    jmp     .false2
.int_lt:
    call    int_pair
    cmp     r8, r9
    jl      .true2
    jmp     .false2
.int_le:
    call    int_pair
    cmp     r8, r9
    jle     .true2
    jmp     .false2
.file_ef:
    call    stat_ab
    test    r8, r8
    jz      .false2
    test    r9, r9
    jz      .false2
    mov     rax, [statbuf + 0]
    cmp     rax, [statbuf2 + 0]
    jne     .false2
    mov     rax, [statbuf + 8]
    cmp     rax, [statbuf2 + 8]
    jne     .false2
    jmp     .true2
.file_nt:
    call    stat_ab
    test    r8, r8
    jz      .false2
    test    r9, r9
    jz      .true2
    mov     rax, [statbuf + 88]
    cmp     rax, [statbuf2 + 88]
    jg      .true2
    jmp     .false2
.file_ot:
    call    stat_ab
    test    r9, r9
    jz      .false2
    test    r8, r8
    jz      .true2
    mov     rax, [statbuf + 88]
    cmp     rax, [statbuf2 + 88]
    jl      .true2
    jmp     .false2
.true2:
    mov     rax, 1
    ret
.false2:
    xor     rax, rax
    ret

; int_pair: rdi = a, rdx = b -> r8 = a value, r9 = b value
int_pair:
    mov     r10, rdx
    call    parse_int
    mov     r8, rax
    mov     rdi, r10
    call    parse_int
    mov     r9, rax
    ret

; stat_ab: rdi = a, rdx = b; stat both; r8 = a exists, r9 = b exists
stat_ab:
    mov     r10, rdx
    mov     rsi, statbuf
    mov     rax, SYS_STAT
    syscall
    xor     r8, r8
    test    rax, rax
    js      .a_no
    inc     r8
.a_no:
    mov     rdi, r10
    mov     rsi, statbuf2
    mov     rax, SYS_STAT
    syscall
    xor     r9, r9
    test    rax, rax
    js      .b_no
    inc     r9
.b_no:
    ret

; parse_int: rdi -> signed decimal, result in rax
parse_int:
    xor     rax, rax
    xor     r11, r11
    mov     dl, [rdi]
    cmp     dl, '-'
    jne     .p
    mov     r11, 1
    inc     rdi
    jmp     .d
.p:
    cmp     dl, '+'
    jne     .d
    inc     rdi
.d:
    movzx   rdx, byte [rdi]
    sub     dl, '0'
    cmp     dl, 9
    ja      .end
    imul    rax, rax, 10
    add     rax, rdx
    inc     rdi
    jmp     .d
.end:
    test    r11, r11
    jz      .ret
    neg     rax
.ret:
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

; streq: rdi, rsi -> ZF=1 if the strings are equal (preserves rdi/rsi)
streq:
    push    rdi
    push    rsi
.l:
    mov     al, [rdi]
    mov     dl, [rsi]
    cmp     al, dl
    jne     .done
    test    al, al
    jz      .done
    inc     rdi
    inc     rsi
    jmp     .l
.done:
    pop     rsi
    pop     rdi
    ret

; strcmp_sign: rdi, rsi -> rax = -1/0/1 by unsigned byte order
strcmp_sign:
    push    rcx
    xor     rcx, rcx
.l:
    movzx   rax, byte [rdi + rcx]
    movzx   rdx, byte [rsi + rcx]
    cmp     rax, rdx
    jb      .less
    ja      .greater
    test    rax, rax
    jz      .equal
    inc     rcx
    jmp     .l
.less:
    mov     rax, -1
    pop     rcx
    ret
.greater:
    mov     rax, 1
    pop     rcx
    ret
.equal:
    xor     rax, rax
    pop     rcx
    ret

; in_set: rdi -> string, rsi -> NUL-separated set (double NUL end); rax = 1/0
in_set:
.next:
    cmp     byte [rsi], 0
    je      .no
    call    streq
    je      .yes
.skip:
    cmp     byte [rsi], 0
    je      .skip_nul
    inc     rsi
    jmp     .skip
.skip_nul:
    inc     rsi
    jmp     .next
.yes:
    mov     rax, 1
    ret
.no:
    xor     rax, rax
    ret
