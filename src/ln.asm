; src/ln.asm -- ln(1): create hard or symbolic links.
; Usage: ln [-sfnT] [-t DIR] SOURCE... [DEST]
;
; With a directory DEST each SOURCE is linked as DEST/basename; -n/-T treat a
; symlink-to-directory DEST as the link name itself. -s makes symbolic links,
; -f removes an existing destination first.

    %include "include/sysdefs.inc"

    %define S_IFMT  0xF000
    %define S_IFDIR 0x4000

section .bss
    stat_buf    resb 160
    target      resb 4096
    relbuf      resb 8192
    operands    resq 256
    nops        resq 1
    s_flag      resb 1
    f_flag      resb 1
    r_flag      resb 1
    notdir      resb 1                  ;-n / -T
    tdir        resq 1
    had_err     resb 1

section .data
usage_msg   db "Usage: ln [-sfnT] [-t DIR] SOURCE... DEST", WHITESPACE_NL
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    mov     byte [s_flag], 0
    mov     byte [f_flag], 0
    mov     byte [r_flag], 0
    mov     byte [notdir], 0
    mov     qword [tdir], 0
    mov     byte [had_err], 0
    mov     qword [nops], 0

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
    cmp     al, 's'
    je      .ss
    cmp     al, 'f'
    je      .sf
    cmp     al, 'n'
    je      .sn
    cmp     al, 'T'
    je      .sn
    cmp     al, 't'
    je      .st
    cmp     al, 'r'
    je      .srv
    inc     rsi
    jmp     .oc
.srv:
    mov     byte [r_flag], 1
    inc     rsi
    jmp     .oc
.ss:
    mov     byte [s_flag], 1
    inc     rsi
    jmp     .oc
.sf:
    mov     byte [f_flag], 1
    inc     rsi
    jmp     .oc
.sn:
    mov     byte [notdir], 1
    inc     rsi
    jmp     .oc
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
    cmp     qword [tdir], 0
    je      .need2
    cmp     qword [nops], 1
    jge     .run
    jmp     .usage
.need2:
    cmp     qword [nops], 2
    jge     .run
.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall
.run:
    cmp     qword [tdir], 0
    je      .no_tdir
    mov     r15, [tdir]
    mov     r13, [nops]
    mov     r14, 1                      ;dest is dir
    jmp     .loop
.no_tdir:
    mov     rax, [nops]
    dec     rax
    mov     r15, [operands + rax*8]     ;dest
    mov     r13, rax                    ;source count
    xor     r14, r14
    cmp     byte [notdir], 1
je      .loop                       ;-n/-T: dest is the link name
    mov     rdi, r15
    mov     rsi, stat_buf
    mov     rax, SYS_STAT
    syscall
    test    rax, rax
    js      .loop
    mov     ax, [stat_buf + 24]
    and     ax, S_IFMT
    cmp     ax, S_IFDIR
    jne     .loop
    mov     r14, 1
.loop:
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
;-f: remove an existing destination
    cmp     byte [f_flag], 1
    jne     .link
    mov     rax, SYS_UNLINK
    mov     rdi, target
    syscall
.link:
    cmp     byte [s_flag], 1
    je      .sym
    mov     rax, SYS_LINK
    mov     rdi, rbx
    mov     rsi, target
    syscall
    jmp     .checkerr
.sym:
    mov     rdi, rbx                    ;symlink content
    cmp     byte [r_flag], 1
    jne     .dosym
    call    build_relative              ;rax = relative content
    mov     rdi, rax
.dosym:
    mov     rax, SYS_SYMLINK
    mov     rsi, target
    syscall
.checkerr:
    test    rax, rax
    jns     .next
    mov     byte [had_err], 1
.next:
    inc     r12
    jmp     .each
.done:
    movzx   edi, byte [had_err]
    mov     rax, SYS_EXIT
    syscall

; build_dir_target: target = dest(r15) + "/" + basename(rbx source).
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
    mov     r10, rax                    ;write offset (survives strlen_c)
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

; build_relative: relbuf = ("../" per component of dirname(target)) + source(rbx).
; Absolute sources are copied unchanged. Returns relbuf in rax.
build_relative:
    cmp     byte [rbx], '/'
    je      .abs
    mov     rdi, target
    call    strlen_c
    mov     rcx, rax                    ;target length
    mov     r9, -1
    xor     r8, r8
.fl:
    cmp     r8, rcx
    jge     .fdone
    cmp     byte [target + r8], '/'
    jne     .fn
    mov     r9, r8
.fn:
    inc     r8
    jmp     .fl
.fdone:
    xor     r11, r11                    ;component count
    cmp     r9, 0
    jl      .pre
    xor     r8, r8
    xor     r10, r10                    ;in-segment
.cs:
    cmp     r8, r9
    jge     .pre
    cmp     byte [target + r8], '/'
    jne     .nonsl
    xor     r10, r10
    jmp     .csn
.nonsl:
    test    r10, r10
    jnz     .csn
    inc     r11
    mov     r10, 1
.csn:
    inc     r8
    jmp     .cs
.pre:
    xor     rdx, rdx                    ;relbuf offset
.pl:
    test    r11, r11
    jz      .app
    mov     byte [relbuf + rdx], '.'
    mov     byte [relbuf + rdx + 1], '.'
    mov     byte [relbuf + rdx + 2], '/'
    add     rdx, 3
    dec     r11
    jmp     .pl
.app:
    xor     rcx, rcx
.al:
    mov     al, [rbx + rcx]
    mov     [relbuf + rdx], al
    test    al, al
    jz      .done
    inc     rcx
    inc     rdx
    jmp     .al
.done:
    mov     rax, relbuf
    ret
.abs:
    mov     rsi, rbx
    mov     rdi, relbuf
    call    strcpy_c
    mov     rax, relbuf
    ret

; strcpy_c: rsi -> rdi, NUL-terminated; rax = length (excl NUL).
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
