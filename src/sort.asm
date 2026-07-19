; src/sort.asm -- sort(1): order lines of text.
; Usage: sort [-nrfbdiuscCsz] [-t X] [-k KEY]... [-o FILE] [FILE...]
;
; Lines are read into memory, compared by the -k key list (or the whole line),
; and emitted with a stable merge sort. Each key extracts a field range and is
; compared numerically (-n) or as text, optionally case-folded (-f); a final
; whole-line comparison breaks ties unless -s. -c/-C check order instead of
; sorting, -u drops duplicates, -o redirects output. -g is a general numeric
; compare (floats with NaN/inf ordering).

    %include "include/sysdefs.inc"

    %define BUFCAP (8 * 1024 * 1024)
    %define MAXLINES 500000
    %define KEYCAP 65536

    %define F_N 1
    %define F_R 2
    %define F_F 4
    %define F_G 8
    %define F_B 16
    %define F_BB 32
    %define F_D 64
    %define F_I 128
    %define F_M 256
    %define F_X 512
    %define F_V 1024

section .bss
    inbuf       resb BUFCAP
    lines       resq MAXLINES
    tmp         resq MAXLINES
    keyx        resb KEYCAP
    keyy        resb KEYCAP
    numbuf      resb 32
    nlb         resb 1

    files       resq 256
    nfiles      resq 1
    linecount   resq 1
    inlen       resq 1

    gflags      resq 1
    u_flag      resb 1
    c_flag      resb 1
    C_flag      resb 1
    s_flag      resb 1
    z_flag      resb 1
    tsep        resq 1                  ;separator char, or -1
    ofile       resq 1

    k_r0        resq 32
    k_r1        resq 32
    k_r2        resq 32
    k_r3        resq 32
    k_flags     resq 32
    nkeys       resq 1

    ck_x        resq 1
    ck_y        resq 1
    ck_ki       resq 1
    ck_kf       resq 1
    ck_xd       resq 1
    ck_yd       resq 1

    gk_src      resq 1
    gk_flags    resq 1
    gk_dest     resq 1
    gk_r0       resq 1
    gk_r1       resq 1
    gk_r2       resq 1
    gk_r3       resq 1
    gk_len      resq 1
    gk_start    resq 1
    gk_end      resq 1

    pk_slot     resq 1
    pk_flags    resq 1
    pk_idx      resq 1

    ms_n        resq 1
    ms_width    resq 1
    ms_bi       resq 1
    ms_lo       resq 1
    ms_mid      resq 1
    ms_hi       resq 1
    ms_i        resq 1
    ms_j        resq 1
    ms_k        resq 1

    ded_i       resq 1
    ded_j       resq 1
    chk_i       resq 1
    wl_i        resq 1
    wl_ptr      resq 1
    out_fd      resq 1
    in_fd       resq 1

    cv_x        resq 1
    cv_y        resq 1
    cv_xend     resq 1
    cv_yend     resq 1
    cv_dx       resq 1
    cv_dy       resq 1
    sd_start    resq 1
    sd_tmp      resq 1

section .data
chkmsg      db "sort: Check line "
    chkmsg_len  equ $ - chkmsg
    ten         dq 0x4024000000000000
    tenth       dq 0x3FB999999999999A
    signbit     dq 0x8000000000000000

section .text
global _start

_start:
    mov     qword [gflags], 0
    mov     byte [u_flag], 0
    mov     byte [c_flag], 0
    mov     byte [C_flag], 0
    mov     byte [s_flag], 0
    mov     byte [z_flag], 0
    mov     qword [tsep], -1
    mov     qword [ofile], 0
    mov     qword [nkeys], 0
    mov     qword [nfiles], 0
    mov     qword [linecount], 0

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
    je      .file                       ;lone "-" operand
    cmp     byte [rdi + 1], '-'
    je      .longopt
    lea     rsi, [rdi + 1]
.oc:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 'n'
    je      .f_n
    cmp     al, 'r'
    je      .f_r
    cmp     al, 'f'
    je      .f_f
    cmp     al, 'g'
    je      .f_g
    cmp     al, 'd'
    je      .f_d
    cmp     al, 'i'
    je      .f_i
    cmp     al, 'M'
    je      .f_M
    cmp     al, 'x'
    je      .f_x
    cmp     al, 'V'
    je      .f_V
    cmp     al, 'b'
    je      .f_b
    cmp     al, 'u'
    je      .f_u
    cmp     al, 'c'
    je      .f_c
    cmp     al, 'C'
    je      .f_C
    cmp     al, 's'
    je      .f_s
    cmp     al, 'z'
    je      .f_z
    cmp     al, 'm'
    je      .f_ign
    cmp     al, 't'
    je      .a_t
    cmp     al, 'o'
    je      .a_o
    cmp     al, 'k'
    je      .a_k
    cmp     al, 'S'
    je      .a_ign
    cmp     al, 'T'
    je      .a_ign
    jmp     exit2                       ;unknown option
.f_n:
    or      qword [gflags], F_N
    inc     rsi
    jmp     .oc
.f_r:
    or      qword [gflags], F_R
    inc     rsi
    jmp     .oc
.f_f:
    or      qword [gflags], F_F
    inc     rsi
    jmp     .oc
.f_g:
    or      qword [gflags], F_G
    inc     rsi
    jmp     .oc
.f_d:
    or      qword [gflags], F_D
    inc     rsi
    jmp     .oc
.f_i:
    or      qword [gflags], F_I
    inc     rsi
    jmp     .oc
.f_M:
    or      qword [gflags], F_M
    inc     rsi
    jmp     .oc
.f_x:
    or      qword [gflags], F_X
    inc     rsi
    jmp     .oc
.f_V:
    or      qword [gflags], F_V
    inc     rsi
    jmp     .oc
.f_b:
    or      qword [gflags], F_B | F_BB
    inc     rsi
    jmp     .oc
.f_u:
    mov     byte [u_flag], 1
    inc     rsi
    jmp     .oc
.f_c:
    mov     byte [c_flag], 1
    inc     rsi
    jmp     .oc
.f_C:
    mov     byte [C_flag], 1
    inc     rsi
    jmp     .oc
.f_s:
    mov     byte [s_flag], 1
    inc     rsi
    jmp     .oc
.f_z:
    mov     byte [z_flag], 1
    inc     rsi
    jmp     .oc
.f_ign:
    inc     rsi
    jmp     .oc
.a_t:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .t_here
    add     r13, 8
    dec     r12
    mov     rsi, [r13]
.t_here:
    movzx   eax, byte [rsi]
    mov     [tsep], rax
    jmp     .nextarg
.a_o:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .o_here
    add     r13, 8
    dec     r12
    mov     rsi, [r13]
.o_here:
    mov     [ofile], rsi
    jmp     .nextarg
.a_k:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .k_here
    add     r13, 8
    dec     r12
    mov     rsi, [r13]
.k_here:
    mov     rdi, rsi
    call    parse_key
    jmp     .nextarg
.a_ign:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .nextarg
    add     r13, 8
    dec     r12
    jmp     .nextarg
.longopt:
    cmp     byte [rdi + 2], 0
    je      .file                       ;"--" ends options
    jmp     exit2                       ;unknown long option
.file:
    mov     rcx, [nfiles]
    mov     [files + rcx*8], rdi
    inc     qword [nfiles]
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

after_parse:
    cmp     byte [u_flag], 1
    jne     .nou
    mov     byte [s_flag], 1            ;-u implies -s
.nou:
    cmp     qword [nkeys], 0
    jne     .haskeys
mov     qword [k_r0], 1             ;default: whole-line key
    mov     qword [k_r1], 0
    mov     qword [k_r2], 0
    mov     qword [k_r3], 0
    mov     qword [k_flags], 0
    mov     qword [nkeys], 1
.haskeys:
    xor     r15, r15                    ;total bytes read
    cmp     qword [nfiles], 0
    jne     .files
    mov     qword [in_fd], STDIN_FILENO
    call    read_fd
    jmp     .split
.files:
    xor     r14, r14
.floop:
    cmp     r14, [nfiles]
    jge     .split
    mov     rdi, [files + r14*8]
    cmp     byte [rdi], '-'
    jne     .openf
    cmp     byte [rdi + 1], 0
    jne     .openf
    mov     qword [in_fd], STDIN_FILENO
    jmp     .readf
.openf:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fnext
    mov     [in_fd], rax
.readf:
    call    read_fd
    mov     rdi, [in_fd]
    cmp     rdi, STDIN_FILENO
    je      .fnext
    mov     rax, SYS_CLOSE
    syscall
.fnext:
    inc     r14
    jmp     .floop

.split:
    mov     [inlen], r15
    mov     byte [inbuf + r15], 0
    xor     r14, r14                    ;line start
    xor     r15, r15                    ;pos
.sl:
    cmp     r15, [inlen]
    jge     .stail
    cmp     byte [inbuf + r15], WHITESPACE_NL
    jne     .sadv
    mov     byte [inbuf + r15], 0
    mov     rax, [linecount]
    lea     rcx, [inbuf + r14]
    mov     [lines + rax*8], rcx
    inc     qword [linecount]
    lea     r14, [r15 + 1]
.sadv:
    inc     r15
    jmp     .sl
.stail:
    cmp     r14, [inlen]
    jge     .ready
    mov     rax, [linecount]
    lea     rcx, [inbuf + r14]
    mov     [lines + rax*8], rcx
    inc     qword [linecount]
.ready:
    cmp     byte [c_flag], 1
    je      do_check
    cmp     byte [C_flag], 1
    je      do_check

    call    do_sort

    cmp     byte [u_flag], 1
    jne     output
    mov     qword [ded_j], 0
    mov     qword [ded_i], 1
.dl:
    mov     rax, [ded_i]
    cmp     rax, [linecount]
    jge     .ddone
    mov     rax, [ded_j]
    mov     rdi, [lines + rax*8]
    mov     rax, [ded_i]
    mov     rsi, [lines + rax*8]
    call    compare_keys
    test    rax, rax
    jnz     .keep
    inc     qword [ded_i]
    jmp     .dl
.keep:
    inc     qword [ded_j]
    mov     rax, [ded_i]
    mov     rcx, [lines + rax*8]
    mov     rax, [ded_j]
    mov     [lines + rax*8], rcx
    inc     qword [ded_i]
    jmp     .dl
.ddone:
    cmp     qword [linecount], 0
    je      output
    mov     rax, [ded_j]
    inc     rax
    mov     [linecount], rax

output:
    mov     qword [out_fd], STDOUT_FILENO
    cmp     qword [ofile], 0
    je      .wl
    mov     rax, SYS_OPEN
    mov     rdi, [ofile]
    mov     rsi, O_CREAT | O_TRUNC | O_WRONLY
    mov     rdx, 0o666
    syscall
    mov     [out_fd], rax
.wl:
    mov     rax, [wl_i]
    cmp     rax, [linecount]
    jge     .wdone
    mov     rdi, [lines + rax*8]
    mov     [wl_ptr], rdi
    call    strlen_z
    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, [out_fd]
    mov     rsi, [wl_ptr]
    syscall
    mov     byte [nlb], WHITESPACE_NL
    mov     rax, SYS_WRITE
    mov     rdi, [out_fd]
    mov     rsi, nlb
    mov     rdx, 1
    syscall
    inc     qword [wl_i]
    jmp     .wl
.wdone:
    xor     rdi, rdi
    mov     rax, SYS_EXIT
    syscall

do_check:
    mov     qword [chk_i], 1
.cl:
    mov     rax, [chk_i]
    cmp     rax, [linecount]
    jge     .ok
    mov     rax, [chk_i]
    dec     rax
    mov     rdi, [lines + rax*8]
    mov     rax, [chk_i]
    mov     rsi, [lines + rax*8]
    call    compare_keys
    cmp     byte [u_flag], 1
    je      .chku
    test    rax, rax
    jg      .fail
    jmp     .cnext
.chku:
    test    rax, rax
    jns     .fail
.cnext:
    inc     qword [chk_i]
    jmp     .cl
.ok:
    xor     rdi, rdi
    mov     rax, SYS_EXIT
    syscall
.fail:
    cmp     byte [C_flag], 1
    je      .quiet
    write   STDERR_FILENO, chkmsg, chkmsg_len
    mov     rdi, [chk_i]
    inc     rdi
    call    print_dec_err
    mov     byte [nlb], WHITESPACE_NL
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, nlb
    mov     rdx, 1
    syscall
.quiet:
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall

exit2:
    mov     rdi, 2
    mov     rax, SYS_EXIT
    syscall

; read_fd: read [in_fd] appending into inbuf at offset r15; updates r15.
read_fd:
.l:
    mov     rdx, BUFCAP
    sub     rdx, r15
    jz      .done
    mov     rax, SYS_READ
    mov     rdi, [in_fd]
    lea     rsi, [inbuf + r15]
    syscall
    test    rax, rax
    jle     .done
    add     r15, rax
    jmp     .l
.done:
    ret

; parse_key: rdi = key spec. Appends a key. Preserves r12/r13.
parse_key:
    mov     rax, [nkeys]
    mov     [pk_slot], rax
    mov     qword [k_r0 + rax*8], 0
    mov     qword [k_r1 + rax*8], 0
    mov     qword [k_r2 + rax*8], 0
    mov     qword [k_r3 + rax*8], 0
    mov     qword [pk_flags], 0
    mov     qword [pk_idx], 0
    mov     r11, rdi
.while:
    cmp     byte [r11], 0
    je      .done
    mov     rdi, r11
    call    strtol_adv
    mov     r11, rdx
    call    store_range0
    cmp     byte [r11], '.'
    jne     .flags
    inc     r11
    mov     rdi, r11
    call    strtol_adv
    mov     r11, rdx
    call    store_range1
.flags:
    movzx   eax, byte [r11]
    test    al, al
    jz      .done
    cmp     al, ','
    jne     .letter
    cmp     qword [pk_idx], 0
    jne     .keyerr
    mov     qword [pk_idx], 1
    inc     r11
    jmp     .while
.letter:
    cmp     al, 'n'
    je      .lN
    cmp     al, 'r'
    je      .lR
    cmp     al, 'f'
    je      .lF
    cmp     al, 'g'
    je      .lG
    cmp     al, 'b'
    je      .lB
    cmp     al, 'd'
    je      .lD
    cmp     al, 'i'
    je      .lI
    cmp     al, 'M'
    je      .lMo
    cmp     al, 'x'
    je      .lX
    cmp     al, 'V'
    je      .lV
    jmp     .keyerr
.lN:
    or      qword [pk_flags], F_N
    jmp     .lnext
.lR:
    or      qword [pk_flags], F_R
    jmp     .lnext
.lF:
    or      qword [pk_flags], F_F
    jmp     .lnext
.lG:
    or      qword [pk_flags], F_G
    jmp     .lnext
.lB:
    cmp     qword [pk_idx], 0
    jne     .lBB
    or      qword [pk_flags], F_B
    jmp     .lnext
.lBB:
    or      qword [pk_flags], F_BB
    jmp     .lnext
.lD:
    or      qword [pk_flags], F_D
    jmp     .lnext
.lI:
    or      qword [pk_flags], F_I
    jmp     .lnext
.lMo:
    or      qword [pk_flags], F_M
    jmp     .lnext
.lX:
    or      qword [pk_flags], F_X
    jmp     .lnext
.lV:
    or      qword [pk_flags], F_V
    jmp     .lnext
.lnext:
    inc     r11
    jmp     .flags
.done:
    mov     rax, [pk_slot]
    mov     rcx, [pk_flags]
    mov     [k_flags + rax*8], rcx
    inc     qword [nkeys]
    ret
.keyerr:
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall

store_range0:
    mov     rcx, [pk_slot]
    cmp     qword [pk_idx], 0
    jne     .end
    mov     [k_r0 + rcx*8], rax
    ret
.end:
    mov     [k_r2 + rcx*8], rax
    ret
store_range1:
    mov     rcx, [pk_slot]
    cmp     qword [pk_idx], 0
    jne     .end
    mov     [k_r1 + rcx*8], rax
    ret
.end:
    mov     [k_r3 + rcx*8], rax
    ret

; strtol_adv: rdi -> rax value, rdx = pointer after the number.
strtol_adv:
    xor     rax, rax
    xor     r8, r8
    cmp     byte [rdi], '-'
    jne     .p
    mov     r8, 1
    inc     rdi
    jmp     .d
.p:
    cmp     byte [rdi], '+'
    jne     .d
    inc     rdi
.d:
    movzx   ecx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .done
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    inc     rdi
    jmp     .d
.done:
    test    r8, r8
    jz      .ret
    neg     rax
.ret:
    mov     rdx, rdi
    ret

; do_sort: bottom-up stable merge sort over lines[0..linecount).
do_sort:
    mov     rax, [linecount]
    mov     [ms_n], rax
    mov     qword [ms_width], 1
.wloop:
    mov     rax, [ms_width]
    cmp     rax, [ms_n]
    jge     .done
    mov     qword [ms_bi], 0
.bloop:
    mov     rax, [ms_bi]
    cmp     rax, [ms_n]
    jge     .wnext
    mov     [ms_lo], rax
    add     rax, [ms_width]
    cmp     rax, [ms_n]
    jbe     .mok
    mov     rax, [ms_n]
.mok:
    mov     [ms_mid], rax
    mov     rax, [ms_bi]
    add     rax, [ms_width]
    add     rax, [ms_width]
    cmp     rax, [ms_n]
    jbe     .hok
    mov     rax, [ms_n]
.hok:
    mov     [ms_hi], rax
    call    merge_run
    mov     rax, [ms_bi]
    add     rax, [ms_width]
    add     rax, [ms_width]
    mov     [ms_bi], rax
    jmp     .bloop
.wnext:
    mov     rax, [ms_width]
    add     rax, rax
    mov     [ms_width], rax
    jmp     .wloop
.done:
    ret

; merge_run: merge lines[lo..mid) and [mid..hi) via tmp.
merge_run:
    mov     rax, [ms_lo]
.cp:
    cmp     rax, [ms_hi]
    jge     .cpd
    mov     rcx, [lines + rax*8]
    mov     [tmp + rax*8], rcx
    inc     rax
    jmp     .cp
.cpd:
    mov     rax, [ms_lo]
    mov     [ms_i], rax
    mov     rax, [ms_mid]
    mov     [ms_j], rax
    mov     rax, [ms_lo]
    mov     [ms_k], rax
.ml:
    mov     rax, [ms_i]
    cmp     rax, [ms_mid]
    jge     .leftdone
    mov     rax, [ms_j]
    cmp     rax, [ms_hi]
    jge     .rightdone
    mov     rax, [ms_i]
    mov     rdi, [tmp + rax*8]
    mov     rax, [ms_j]
    mov     rsi, [tmp + rax*8]
    call    compare_keys
    test    rax, rax
    jg      .takeright
    mov     rax, [ms_i]
    mov     rcx, [tmp + rax*8]
    mov     rax, [ms_k]
    mov     [lines + rax*8], rcx
    inc     qword [ms_i]
    inc     qword [ms_k]
    jmp     .ml
.takeright:
    mov     rax, [ms_j]
    mov     rcx, [tmp + rax*8]
    mov     rax, [ms_k]
    mov     [lines + rax*8], rcx
    inc     qword [ms_j]
    inc     qword [ms_k]
    jmp     .ml
.leftdone:
    mov     rax, [ms_j]
    cmp     rax, [ms_hi]
    jge     .done
    mov     rcx, [tmp + rax*8]
    mov     rax, [ms_k]
    mov     [lines + rax*8], rcx
    inc     qword [ms_j]
    inc     qword [ms_k]
    jmp     .leftdone
.rightdone:
    mov     rax, [ms_i]
    cmp     rax, [ms_mid]
    jge     .done
    mov     rcx, [tmp + rax*8]
    mov     rax, [ms_k]
    mov     [lines + rax*8], rcx
    inc     qword [ms_i]
    inc     qword [ms_k]
    jmp     .rightdone
.done:
    ret

; compare_keys: rdi = line x, rsi = line y -> rax signed order.
compare_keys:
    mov     [ck_x], rdi
    mov     [ck_y], rsi
    mov     qword [ck_ki], 0
.kloop:
    mov     rax, [ck_ki]
    cmp     rax, [nkeys]
    jge     .fallback
    mov     rax, [k_flags + rax*8]
    test    rax, rax
    jnz     .havekf
    mov     rax, [gflags]
.havekf:
    mov     [ck_kf], rax
    mov     rdi, [ck_x]
    mov     rsi, [ck_ki]
    mov     rdx, [ck_kf]
    mov     rcx, keyx
    call    get_key_data
    mov     [ck_xd], rax
    mov     rdi, [ck_y]
    mov     rsi, [ck_ki]
    mov     rdx, [ck_kf]
    mov     rcx, keyy
    call    get_key_data
    mov     [ck_yd], rax
    mov     rdi, [ck_kf]
    mov     rsi, [ck_xd]
    mov     rdx, [ck_yd]
    call    compare_values
    test    rax, rax
    jnz     .decided
    inc     qword [ck_ki]
    jmp     .kloop
.decided:
    mov     r8, [ck_kf]
    jmp     .applyrev
.fallback:
    cmp     byte [s_flag], 1
    je      .stable
    mov     rdi, [ck_x]
    mov     rsi, [ck_y]
    call    strcmp_s
    mov     r8, [gflags]
    jmp     .applyrev
.stable:
    xor     rax, rax
    mov     r8, [gflags]
.applyrev:
    test    r8, F_R
    jz      .ret
    neg     rax
.ret:
    ret

; compare_values: rdi = flags, rsi = x, rdx = y -> rax signed order.
compare_values:
    mov     r8, rsi
    mov     r9, rdx
    test    rdi, F_G
    jnz     compare_g
    test    rdi, F_N
    jnz     .num
    test    rdi, F_F
    jnz     .ci
    mov     rdi, r8
    mov     rsi, r9
    jmp     strcmp_s
.ci:
    mov     rdi, r8
    mov     rsi, r9
    jmp     strcasecmp_s
.num:
    mov     rdi, r8
    call    atoll
    mov     r10, rax
    mov     rdi, r9
    call    atoll
    cmp     r10, rax
    jl      .lt
    jg      .gt
    xor     rax, rax
    ret
.lt:
    mov     rax, -1
    ret
.gt:
    mov     rax, 1
    ret

; compare_g: general-numeric compare of x (r8) and y (r9). Ordering is
; not-a-number < NaN < -inf < finite numbers < +inf.
compare_g:
    mov     [cv_x], r8
    mov     [cv_y], r9
    mov     rdi, r8
    call    my_strtod
    mov     [cv_xend], rax
    movsd   [cv_dx], xmm0
    mov     rdi, [cv_y]
    call    my_strtod
    mov     [cv_yend], rax
    movsd   [cv_dy], xmm0
    mov     rax, [cv_xend]
    cmp     rax, [cv_x]
    jne     .xok
    mov     rax, [cv_yend]              ;x parsed nothing
    cmp     rax, [cv_y]
    je      .zero
    mov     rax, -1
    ret
.xok:
    mov     rax, [cv_yend]
    cmp     rax, [cv_y]
    jne     .bothnum
    mov     rax, 1                      ;y parsed nothing, x is a number
    ret
.bothnum:
    movsd   xmm0, [cv_dx]
    ucomisd xmm0, xmm0
    jp      .xnan
    movsd   xmm1, [cv_dy]
    ucomisd xmm1, xmm1
    jp      .ret1                       ;dy NaN, dx not
    jmp     .checkinf
.xnan:
    movsd   xmm1, [cv_dy]
    ucomisd xmm1, xmm1
    jp      .zero                       ;both NaN
    mov     rax, -1
    ret
.checkinf:
    mov     rax, [cv_dx]
    mov     rcx, 0x7FFFFFFFFFFFFFFF
    and     rax, rcx
    mov     rcx, 0x7FF0000000000000
    cmp     rax, rcx
    je      .xinf
    mov     rax, [cv_dy]
    mov     rcx, 0x7FFFFFFFFFFFFFFF
    and     rax, rcx
    mov     rcx, 0x7FF0000000000000
    cmp     rax, rcx
    je      .yinf
    jmp     .finite
.xinf:
    mov     rax, [cv_dx]
    test    rax, rax
    js      .xneginf
    mov     rax, [cv_dy]                ;+inf
    mov     rcx, 0x7FF0000000000000
    cmp     rax, rcx
    je      .zero
    mov     rax, 1
    ret
.xneginf:
    mov     rax, [cv_dy]
    mov     rcx, 0xFFF0000000000000
    cmp     rax, rcx
    je      .zero
    mov     rax, -1
    ret
.yinf:
    mov     rax, [cv_dy]                ;dx finite, dy inf
    test    rax, rax
    js      .ret1
    mov     rax, -1
    ret
.finite:
    movsd   xmm0, [cv_dx]
    movsd   xmm1, [cv_dy]
    ucomisd xmm0, xmm1
    jb      .lt
    ja      .ret1
    xor     rax, rax
    ret
.lt:
    mov     rax, -1
    ret
.ret1:
    mov     rax, 1
    ret
.zero:
    xor     rax, rax
    ret

; my_strtod: rdi -> xmm0 = value, rax = end pointer (== input when nothing
; parsed). Recognizes inf/infinity/nan (any case) and decimal floats.
my_strtod:
    mov     [sd_start], rdi
.ws:
    movzx   eax, byte [rdi]
    cmp     al, ' '
    je      .wa
    cmp     al, 9
    jb      .sign
    cmp     al, 13
    jbe     .wa
    jmp     .sign
.wa:
    inc     rdi
    jmp     .ws
.sign:
    xor     r10, r10
    movzx   eax, byte [rdi]
    cmp     al, '-'
    jne     .chkp
    mov     r10, 1
    inc     rdi
    jmp     .spec
.chkp:
    cmp     al, '+'
    jne     .spec
    inc     rdi
.spec:
    movzx   eax, byte [rdi]
    or      al, 0x20
    cmp     al, 'i'
    je      .maybeinf
    cmp     al, 'n'
    je      .maybenan
    jmp     .number
.maybeinf:
    mov     al, [rdi + 1]
    or      al, 0x20
    cmp     al, 'n'
    jne     .notnum
    mov     al, [rdi + 2]
    or      al, 0x20
    cmp     al, 'f'
    jne     .notnum
    add     rdi, 3
    mov     al, [rdi]
    or      al, 0x20
    cmp     al, 'i'
    jne     .infval
    mov     al, [rdi + 1]
    or      al, 0x20
    cmp     al, 'n'
    jne     .infval
    mov     al, [rdi + 2]
    or      al, 0x20
    cmp     al, 'i'
    jne     .infval
    mov     al, [rdi + 3]
    or      al, 0x20
    cmp     al, 't'
    jne     .infval
    mov     al, [rdi + 4]
    or      al, 0x20
    cmp     al, 'y'
    jne     .infval
    add     rdi, 5
.infval:
    mov     rax, 0x7FF0000000000000
    test    r10, r10
    jz      .storeinf
    mov     rax, 0xFFF0000000000000
.storeinf:
    movq    xmm0, rax
    mov     rax, rdi
    ret
.maybenan:
    mov     al, [rdi + 1]
    or      al, 0x20
    cmp     al, 'a'
    jne     .notnum
    mov     al, [rdi + 2]
    or      al, 0x20
    cmp     al, 'n'
    jne     .notnum
    add     rdi, 3
    mov     rax, 0x7FF8000000000000
    movq    xmm0, rax
    mov     rax, rdi
    ret
.number:
    xor     r8, r8                      ;digit-seen
    pxor    xmm0, xmm0
.intl:
    movzx   eax, byte [rdi]
    sub     al, '0'
    cmp     al, 9
    ja      .dot
    mulsd   xmm0, [ten]
    movzx   eax, al
    cvtsi2sd xmm1, rax
    addsd   xmm0, xmm1
    mov     r8, 1
    inc     rdi
    jmp     .intl
.dot:
    xor     r9, r9                      ;fraction digits
    movzx   eax, byte [rdi]
    cmp     al, '.'
    jne     .expo
    inc     rdi
.fracl:
    movzx   eax, byte [rdi]
    sub     al, '0'
    cmp     al, 9
    ja      .expo
    mulsd   xmm0, [ten]
    movzx   eax, al
    cvtsi2sd xmm1, rax
    addsd   xmm0, xmm1
    inc     r9
    mov     r8, 1
    inc     rdi
    jmp     .fracl
.expo:
    test    r8, r8
    jz      .notnum
    xor     r11, r11                    ;exponent
    xor     rcx, rcx                    ;exponent sign
    movzx   eax, byte [rdi]
    or      al, 0x20
    cmp     al, 'e'
    jne     .scale
    mov     [sd_tmp], rdi
    inc     rdi
    movzx   eax, byte [rdi]
    cmp     al, '-'
    jne     .ep
    mov     rcx, 1
    inc     rdi
    jmp     .edchk
.ep:
    cmp     al, '+'
    jne     .edchk
    inc     rdi
.edchk:
    movzx   eax, byte [rdi]
    sub     al, '0'
    cmp     al, 9
    ja      .expbad
.edl:
    movzx   eax, byte [rdi]
    sub     al, '0'
    cmp     al, 9
    ja      .expdone
    imul    r11, r11, 10
    movzx   eax, al
    add     r11, rax
    inc     rdi
    jmp     .edl
.expbad:
    mov     rdi, [sd_tmp]
    jmp     .scale
.expdone:
    test    rcx, rcx
    jz      .scale
    neg     r11
.scale:
    sub     r11, r9
    test    r11, r11
    jz      .apply
    jns     .scaleup
    neg     r11
.scaledn:
    mulsd   xmm0, [tenth]
    dec     r11
    jnz     .scaledn
    jmp     .apply
.scaleup:
    mulsd   xmm0, [ten]
    dec     r11
    jnz     .scaleup
.apply:
    test    r10, r10
    jz      .fin
    movq    xmm1, [signbit]
    xorpd   xmm0, xmm1
.fin:
    mov     rax, rdi
    ret
.notnum:
    mov     rax, [sd_start]
    pxor    xmm0, xmm0
    ret

; get_key_data: rdi = src, rsi = key index, rdx = flags, rcx = dest.
; Returns rax = pointer to the key text (src or dest).
get_key_data:
    mov     [gk_src], rdi
    mov     [gk_flags], rdx
    mov     [gk_dest], rcx
    mov     rax, [k_r0 + rsi*8]
    mov     [gk_r0], rax
    mov     rax, [k_r1 + rsi*8]
    mov     [gk_r1], rax
    mov     rax, [k_r2 + rsi*8]
    mov     [gk_r2], rax
    mov     rax, [k_r3 + rsi*8]
    mov     [gk_r3], rax
    cmp     qword [gk_r0], 1
    jne     .full
    cmp     qword [gk_r1], 0
    jne     .full
    cmp     qword [gk_r2], 0
    jne     .full
    cmp     qword [gk_r3], 0
    jne     .full
    mov     rax, [gk_flags]
    test    rax, F_B | F_D | F_I | F_BB
    jnz     .full
    mov     rax, [gk_src]
    ret
.full:
    mov     rdi, [gk_src]
    call    strlen_z
    mov     [gk_len], rax
    mov     rax, [gk_r0]
    test    rax, rax
    jnz     .sf
    mov     rax, [gk_len]
    mov     [gk_end], rax
    jmp     .setstart
.sf:
    mov     qword [gk_end], 0
    mov     r10, 1
.sfl:
    cmp     r10, [gk_r0]
    jge     .setstart
    mov     rdi, [gk_src]
    add     rdi, [gk_end]
    call    skip_key
    add     [gk_end], rax
    inc     r10
    jmp     .sfl
.setstart:
    mov     rax, [gk_end]
    mov     [gk_start], rax
    mov     rax, [gk_r2]
    test    rax, rax
    jnz     .ef
    mov     rax, [gk_len]
    mov     [gk_end], rax
    jmp     .aftf
.ef:
    mov     qword [gk_end], 0
    mov     r10, 1
.efl:
    mov     rax, [gk_r2]
    inc     rax
    cmp     r10, rax
    jge     .aftf
    mov     rdi, [gk_src]
    add     rdi, [gk_end]
    call    skip_key
    add     [gk_end], rax
    inc     r10
    jmp     .efl
.aftf:
    mov     rax, [tsep]
    cmp     rax, 0
    jl      .nosep
    mov     rdi, [gk_src]
    add     rdi, [gk_start]
    movzx   ecx, byte [rdi]
    cmp     rcx, rax
    jne     .nosep
    inc     qword [gk_start]
.nosep:
    mov     rax, [gk_flags]
    test    rax, F_B
    jnz     .lstrip
    mov     rax, [tsep]
    cmp     rax, 0
    jge     .noL
    cmp     qword [gk_r3], 0
    jne     .noL
.lstrip:
    mov     rdi, [gk_src]
    add     rdi, [gk_start]
    movzx   eax, byte [rdi]
    cmp     al, ' '
    je      .lsadv
    cmp     al, 9
    jb      .noL
    cmp     al, 13
    jbe     .lsadv
    jmp     .noL
.lsadv:
    inc     qword [gk_start]
    jmp     .lstrip
.noL:
    mov     rax, [gk_flags]
    test    rax, F_BB
    jz      .noT
.tstrip:
    mov     rax, [gk_end]
    cmp     rax, [gk_start]
    jle     .noT
    mov     rdi, [gk_src]
    add     rdi, rax
    movzx   eax, byte [rdi - 1]
    cmp     al, ' '
    je      .tsadv
    cmp     al, 9
    jb      .noT
    cmp     al, 13
    jbe     .tsadv
    jmp     .noT
.tsadv:
    dec     qword [gk_end]
    jmp     .tstrip
.noT:
    cmp     qword [gk_r3], 0
    jle     .noR3
    mov     rax, [gk_end]
    add     rax, [gk_r3]
    dec     rax
    mov     rcx, [gk_len]
    cmp     rax, rcx
    jle     .r3ok
    mov     rax, rcx
.r3ok:
    mov     [gk_end], rax
.noR3:
    cmp     qword [gk_r1], 0
    jle     .noR1
    mov     rax, [gk_start]
    add     rax, [gk_r1]
    dec     rax
    mov     rcx, [gk_len]
    cmp     rax, rcx
    jle     .r1ok
    mov     rax, rcx
.r1ok:
    mov     [gk_start], rax
.noR1:
    mov     rax, [gk_end]
    cmp     rax, [gk_start]
    jge     .cpy
    mov     rax, [gk_start]
    mov     [gk_end], rax
.cpy:
    mov     rsi, [gk_src]
    add     rsi, [gk_start]
    mov     rdi, [gk_dest]
    mov     rcx, [gk_end]
    sub     rcx, [gk_start]
    xor     r10, r10
.cl:
    cmp     r10, rcx
    jge     .cdone
    mov     al, [rsi + r10]
    mov     [rdi + r10], al
    inc     r10
    jmp     .cl
.cdone:
    mov     byte [rdi + r10], 0
    mov     rax, [gk_dest]
    ret

; skip_key: rdi = ptr -> rax = length of one field (with leading blanks).
skip_key:
    xor     r8, r8
    cmp     byte [rdi], 0
    je      .done
    mov     rax, [tsep]
    cmp     rax, 0
    jge     .body
.lead:
    movzx   ecx, byte [rdi + r8]
    cmp     cl, ' '
    je      .leadadv
    cmp     cl, 9
    jb      .body
    cmp     cl, 13
    jbe     .leadadv
    jmp     .body
.leadadv:
    inc     r8
    jmp     .lead
.body:
    movzx   ecx, byte [rdi + r8]
    test    cl, cl
    je      .done
    mov     rax, [tsep]
    cmp     rax, 0
    jl      .bodyws
    cmp     rcx, rax
    jne     .bodyadv
    inc     r8
    jmp     .done
.bodyws:
    cmp     cl, ' '
    je      .done
    cmp     cl, 9
    jb      .bodyadv
    cmp     cl, 13
    jbe     .done
.bodyadv:
    inc     r8
    jmp     .body
.done:
    mov     rax, r8
    ret

; strlen_z: rdi -> rax length.
strlen_z:
    xor     rax, rax
.l:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .l
.done:
    ret

; strcmp_s: rdi, rsi -> rax signed difference.
strcmp_s:
.l:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]
    cmp     eax, ecx
    jne     .diff
    test    eax, eax
    je      .eq
    inc     rdi
    inc     rsi
    jmp     .l
.diff:
    sub     eax, ecx
    cdqe
    ret
.eq:
    xor     eax, eax
    ret

; strcasecmp_s: rdi, rsi -> rax signed difference, case-folded.
strcasecmp_s:
.l:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]
    cmp     al, 'A'
    jb      .ax
    cmp     al, 'Z'
    ja      .ax
    add     al, 32
.ax:
    cmp     cl, 'A'
    jb      .cx
    cmp     cl, 'Z'
    ja      .cx
    add     cl, 32
.cx:
    cmp     eax, ecx
    jne     .diff
    test    eax, eax
    je      .eq
    inc     rdi
    inc     rsi
    jmp     .l
.diff:
    sub     eax, ecx
    cdqe
    ret
.eq:
    xor     eax, eax
    ret

; atoll: rdi -> rax signed (skips leading blanks, optional sign).
atoll:
    xor     rax, rax
    xor     r11, r11
.sk:
    movzx   ecx, byte [rdi]
    cmp     cl, ' '
    je      .adv
    cmp     cl, 9
    jb      .sgn
    cmp     cl, 13
    jbe     .adv
    jmp     .sgn
.adv:
    inc     rdi
    jmp     .sk
.sgn:
    cmp     cl, '-'
    jne     .pl
    mov     r11, 1
    inc     rdi
    jmp     .dig
.pl:
    cmp     cl, '+'
    jne     .dig
    inc     rdi
.dig:
    movzx   ecx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .done
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    inc     rdi
    jmp     .dig
.done:
    test    r11, r11
    jz      .ret
    neg     rax
.ret:
    ret

; print_dec_err: rdi -> decimal digits on stderr.
print_dec_err:
    mov     rax, rdi
    lea     rcx, [numbuf + 31]
    mov     r8, 10
    xor     r9, r9
.d:
    xor     rdx, rdx
    div     r8
    add     dl, '0'
    dec     rcx
    mov     [rcx], dl
    inc     r9
    test    rax, rax
    jnz     .d
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, rcx
    mov     rdx, r9
    syscall
    ret
