; src/install.asm -- install(1): copy files and set their modes.
; Usage: install [-Dpsv] [-m MODE] SOURCE... DEST   (or -t DIR)
;        install -d [-m MODE] DIR...
;
; -d creates directories, -D creates the destination's leading directories,
; -t names a target directory, -m sets an octal or symbolic mode (default 755).

    %include "include/sysdefs.inc"

    %define S_IFMT  0xF000
    %define S_IFDIR 0x4000

section .bss
    stat_buf    resb 160
    target      resb 4096
    copybuf     resb 65536
    operands    resq 256
    nops        resq 1
    d_flag      resb 1
    bigd_flag   resb 1
    tdir        resq 1
    mode        resq 1
    had_err     resb 1

section .data
usage_msg   db "install: missing operand", WHITESPACE_NL
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    mov     qword [nops], 0
    mov     byte [d_flag], 0
    mov     byte [bigd_flag], 0
    mov     qword [tdir], 0
    mov     qword [mode], 0o755
    mov     byte [had_err], 0

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12
parse:
    cmp     r12, 0
    je      after_parse
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .op
    cmp     byte [rdi + 1], 0
    je      .op
    lea     rsi, [rdi + 1]
.oc:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 'd'
    je      .sd
    cmp     al, 'D'
    je      .sD
    cmp     al, 'm'
    je      .sm
    cmp     al, 't'
    je      .st
    inc     rsi                         ;ignore -p/-s/-v/-o/-g
    jmp     .oc
.sd:
    mov     byte [d_flag], 1
    inc     rsi
    jmp     .oc
.sD:
    mov     byte [bigd_flag], 1
    inc     rsi
    jmp     .oc
.sm:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .m_here
    add     r13, 8
    dec     r12
    mov     rsi, [r13]
.m_here:
    mov     rdi, rsi
    call    parse_mode
    mov     [mode], rax
    jmp     .nextarg
.st:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .t_here
    add     r13, 8
    dec     r12
    mov     rsi, [r13]
.t_here:
    mov     [tdir], rsi
    jmp     .nextarg
.op:
    mov     rcx, [nops]
    mov     [operands + rcx*8], rdi
    inc     qword [nops]
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

after_parse:
    cmp     byte [d_flag], 1
    je      do_dirs
;copy mode
    cmp     qword [tdir], 0
    jne     .have_t
    cmp     qword [nops], 2
    jge     .copy
    write   STDERR_FILENO, usage_msg, usage_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall
.have_t:
    mov     r15, [tdir]
    mov     r13, [nops]                 ;all operands are sources
    mov     r14, 1                      ;target is a directory
;-D: create the target directory
    cmp     byte [bigd_flag], 1
    jne     .cloop
    mov     rdi, r15
    call    mkdir_full
    jmp     .cloop
.copy:
    mov     rax, [nops]
    dec     rax
    mov     r15, [operands + rax*8]     ;dest
    mov     r13, rax                    ;source count
    xor     r14, r14
    mov     rdi, r15
    mov     rsi, stat_buf
    mov     rax, SYS_STAT
    syscall
    test    rax, rax
    js      .destchk
    mov     ax, [stat_buf + 24]
    and     ax, S_IFMT
    cmp     ax, S_IFDIR
    jne     .destchk
    mov     r14, 1
.destchk:
    cmp     byte [bigd_flag], 1
    jne     .cloop
    test    r14, r14
    jnz     .cloop
    mov     rdi, r15
    call    mkdir_dirname               ;create leading dirs of a file dest
.cloop:
    xor     r12, r12
.each:
    cmp     r12, r13
    jge     .done
    mov     rbx, [operands + r12*8]     ;source
    test    r14, r14
    jz      .plain
    call    build_dir_target
    jmp     .go
.plain:
    mov     rsi, r15
    mov     rdi, target
    call    strcpy_c
.go:
    call    copy_file
    mov     rax, SYS_CHMOD
    mov     rdi, target
    mov     rsi, [mode]
    syscall
    inc     r12
    jmp     .each
.done:
    movzx   edi, byte [had_err]
    mov     rax, SYS_EXIT
    syscall

do_dirs:
    xor     r12, r12
.l:
    cmp     r12, [nops]
    jge     .done
    mov     rdi, [operands + r12*8]
    call    mkdir_full
    mov     rax, SYS_CHMOD
    mov     rdi, [operands + r12*8]
    mov     rsi, [mode]
    syscall
    inc     r12
    jmp     .l
.done:
    movzx   edi, byte [had_err]
    mov     rax, SYS_EXIT
    syscall

; copy_file: copy [rbx source] to [target].
copy_file:
    mov     rax, SYS_OPEN
    mov     rdi, rbx
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .err
    mov     r8, rax
    mov     rax, SYS_OPEN
    mov     rdi, target
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 0o755
    syscall
    test    rax, rax
    js      .closesrc
    mov     r9, rax
.cl:
    mov     rax, SYS_READ
    mov     rdi, r8
    mov     rsi, copybuf
    mov     rdx, 65536
    syscall
    test    rax, rax
    jle     .cdone
    mov     r10, rax
    mov     rax, SYS_WRITE
    mov     rdi, r9
    mov     rsi, copybuf
    mov     rdx, r10
    syscall
    jmp     .cl
.cdone:
    mov     rax, SYS_CLOSE
    mov     rdi, r9
    syscall
.closesrc:
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    ret
.err:
    mov     byte [had_err], 1
    ret

; build_dir_target: target = dest(r15) + "/" + basename(rbx).
build_dir_target:
    mov     rsi, r15
    mov     rdi, target
    call    strcpy_c
    test    rax, rax
    jz      .slash
    cmp     byte [target + rax - 1], '/'
    je      .base
.slash:
    mov     byte [target + rax], '/'
    inc     rax
.base:
    mov     r10, rax
    mov     rdi, rbx
    call    strlen_c
    mov     rcx, rax
.strip:
    cmp     rcx, 1
    jle     .find
    cmp     byte [rbx + rcx - 1], '/'
    jne     .find
    dec     rcx
    jmp     .strip
.find:
    xor     r8, r8
    mov     r9, rcx
    dec     r9
.scan:
    cmp     r9, 0
    jl      .cp
    cmp     byte [rbx + r9], '/'
    jne     .dec
    lea     r8, [r9 + 1]
    jmp     .cp
.dec:
    dec     r9
    jmp     .scan
.cp:
    mov     rdx, r10
.cl:
    cmp     r8, rcx
    jge     .cdone
    mov     al, [rbx + r8]
    mov     [target + rdx], al
    inc     r8
    inc     rdx
    jmp     .cl
.cdone:
    mov     byte [target + rdx], 0
    ret

; mkdir_full: create every directory component of the path in rdi.
mkdir_full:
    mov     rsi, rdi
    call    strlen_c
    mov     r9, rax
    mov     r11, rsi                    ;path
    mov     r8, 1
.l:
    cmp     r8, r9
    jg      .final
    cmp     r8, r9
    je      .mk
    cmp     byte [r11 + r8], '/'
    jne     .next
.mk:
    mov     al, [r11 + r8]
    mov     byte [r11 + r8], 0
    push    rax
    push    r8
    push    r9
    push    r11
    mov     rax, SYS_MKDIR
    mov     rdi, r11
    mov     rsi, 0o755
    syscall
    pop     r11
    pop     r9
    pop     r8
    pop     rax
    mov     [r11 + r8], al
.next:
    inc     r8
    jmp     .l
.final:
    ret

; mkdir_dirname: create the leading directories of the path in rdi.
mkdir_dirname:
    mov     r11, rdi
    call    strlen_c
    mov     r9, rax
    mov     r8, 1
.l:
    cmp     r8, r9
    jge     .done
    cmp     byte [r11 + r8], '/'
    jne     .next
    mov     byte [r11 + r8], 0
    push    r8
    push    r9
    push    r11
    mov     rax, SYS_MKDIR
    mov     rdi, r11
    mov     rsi, 0o755
    syscall
    pop     r11
    pop     r9
    pop     r8
    mov     byte [r11 + r8], '/'
.next:
    inc     r8
    jmp     .l
.done:
    ret

; parse_mode: rdi = mode string -> rax = mode (octal, or symbolic from 0).
parse_mode:
    movzx   eax, byte [rdi]
    cmp     al, '0'
    jb      .sym
    cmp     al, '9'
    ja      .sym
    xor     rax, rax
.oc:
    movzx   ecx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 7
    ja      .odone
    shl     rax, 3
    movzx   rcx, cl
    add     rax, rcx
    inc     rdi
    jmp     .oc
.odone:
    ret
.sym:
    xor     r8, r8                      ;accumulated mode
.clause:
    cmp     byte [rdi], ','
    jne     .c2
    inc     rdi
.c2:
    cmp     byte [rdi], 0
    je      .symdone
    xor     r9, r9                      ;who mask
.who:
    movzx   eax, byte [rdi]
    cmp     al, 'u'
    je      .wu
    cmp     al, 'g'
    je      .wg
    cmp     al, 'o'
    je      .wo
    cmp     al, 'a'
    je      .wa
    jmp     .op
.wu:
    or      r9, 0o700
    inc     rdi
    jmp     .who
.wg:
    or      r9, 0o070
    inc     rdi
    jmp     .who
.wo:
    or      r9, 0o007
    inc     rdi
    jmp     .who
.wa:
    or      r9, 0o777
    inc     rdi
    jmp     .who
.op:
    test    r9, r9
    jnz     .haveop
    mov     r9, 0o777
.haveop:
    movzx   r10d, byte [rdi]
    inc     rdi
    xor     r11, r11                    ;perm bits
.perm:
    movzx   eax, byte [rdi]
    cmp     al, 'r'
    je      .pr
    cmp     al, 'w'
    je      .pw
    cmp     al, 'x'
    je      .px
    jmp     .apply
.pr:
    or      r11, 4
    inc     rdi
    jmp     .perm
.pw:
    or      r11, 2
    inc     rdi
    jmp     .perm
.px:
    or      r11, 1
    inc     rdi
    jmp     .perm
.apply:
    mov     rcx, r11
    mov     rax, rcx
    shl     rax, 6
    mov     rdx, rcx
    shl     rdx, 3
    or      rax, rdx
    or      rax, rcx
    and     rax, r9                     ;bits masked by who
    cmp     r10b, '-'
    je      .sub
    cmp     r10b, '='
    je      .eq
    or      r8, rax
    jmp     .clause
.sub:
    mov     rcx, rax
    not     rcx
    and     r8, rcx
    jmp     .clause
.eq:
    mov     rcx, r9
    not     rcx
    and     r8, rcx
    or      r8, rax
    jmp     .clause
.symdone:
    mov     rax, r8
    ret

; strcpy_c: rsi -> rdi, NUL-terminated; rax = length.
strcpy_c:
    xor     rax, rax
.l:
    mov     cl, [rsi + rax]
    mov     [rdi + rax], cl
    test    cl, cl
    jz      .done
    inc     rax
    jmp     .l
.done:
    ret

; strlen_c: rdi -> rax length.
strlen_c:
    xor     rax, rax
.l:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .l
.done:
    ret
