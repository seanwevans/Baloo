; src/mktemp.asm -- mktemp(1): create a temporary file or directory.
; Usage: mktemp [-dqtu] [-p DIR] [--tmpdir[=DIR]] [TEMPLATE]
;
; The directory is chosen from -p, $TMPDIR (preferred with -t), then /tmp; when
; a TEMPLATE is given without -p/-t it is used verbatim. Trailing X's become
; random characters. -u only prints the name, -d makes a directory, -q silences
; the failure message.

    %include "include/sysdefs.inc"

    %define O_RDWR 2
    %define O_EXCL 128

section .bss
    finalpath   resb 4096
    randbuf     resb 8
    flen        resq 1
    envp_base   resq 1
    template    resq 1
    p_ptr       resq 1
    tmpdir_arg  resq 1
    p_flag      resb 1
    t_flag      resb 1
    tmpdir_flag resb 1
    u_flag      resb 1
    q_flag      resb 1
    d_flag      resb 1

section .data
    tmpdir_name db "TMPDIR", 0
    def_tmpl    db "tmp.XXXXXXXXXX", 0
    def_tmp     db "/tmp", 0
    long_tmpdir db "--tmpdir", 0
    long_dir    db "--directory", 0
err_msg     db "mktemp: failed to create", WHITESPACE_NL
    err_len     equ $ - err_msg

section .text
global _start

_start:
    mov     byte [p_flag], 0
    mov     byte [t_flag], 0
    mov     byte [tmpdir_flag], 0
    mov     byte [u_flag], 0
    mov     byte [q_flag], 0
    mov     byte [d_flag], 0
    mov     qword [template], 0
    mov     qword [p_ptr], 0
    mov     qword [tmpdir_arg], 0

    mov     rax, [rsp]                  ;argc
    lea     rcx, [rsp + 16]
    lea     rcx, [rcx + rax*8]          ;envp base = rsp+16+argc*8
    mov     [envp_base], rcx

    mov     r12, [rsp]
    lea     r13, [rsp + 16]
    dec     r12
parse:
    cmp     r12, 0
    je      after_parse
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .tmpl
    cmp     byte [rdi + 1], 0
    je      .tmpl
    cmp     byte [rdi + 1], '-'
    je      .long
    lea     rsi, [rdi + 1]
.oc:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 'u'
    je      .su
    cmp     al, 'q'
    je      .sq
    cmp     al, 'd'
    je      .sd
    cmp     al, 't'
    je      .st
    cmp     al, 'p'
    je      .sp
    inc     rsi
    jmp     .oc
.su:
    mov     byte [u_flag], 1
    inc     rsi
    jmp     .oc
.sq:
    mov     byte [q_flag], 1
    inc     rsi
    jmp     .oc
.sd:
    mov     byte [d_flag], 1
    inc     rsi
    jmp     .oc
.st:
    mov     byte [t_flag], 1
    inc     rsi
    jmp     .oc
.sp:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .p_here
    add     r13, 8
    dec     r12
    mov     rsi, [r13]
.p_here:
    mov     [p_ptr], rsi
    mov     byte [p_flag], 1
    jmp     .nextarg
.long:
    mov     rsi, rdi
    mov     rdi, long_dir
    call    streq_c
    test    rax, rax
    jnz     .l_dir
;--tmpdir[=DIR]
    mov     rdi, long_tmpdir
    mov     rcx, rsi                    ;save arg pointer
    call    prefix_eq                   ;rax = ptr after "--tmpdir" or 0
    test    rax, rax
    jz      .nextarg
    mov     byte [tmpdir_flag], 1
    cmp     byte [rax], '='
    jne     .nextarg
    inc     rax
    mov     [tmpdir_arg], rax
    jmp     .nextarg
.l_dir:
    mov     byte [d_flag], 1
    jmp     .nextarg
.tmpl:
    mov     [template], rdi
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

after_parse:
;--tmpdir promotes to -p when -p absent
    cmp     byte [p_flag], 1
    je      .have_p
    cmp     byte [tmpdir_flag], 1
    jne     .have_p
    mov     rax, [tmpdir_arg]
    test    rax, rax
    jnz     .promote
    lea     rax, [empty]
.promote:
    mov     [p_ptr], rax
    mov     byte [p_flag], 1
.have_p:
;te = getenv(TMPDIR)
    mov     rdi, tmpdir_name
    call    getenv
    mov     r15, rax                    ;te (or 0)

;dir = p
    mov     rbx, [p_ptr]                ;dir candidate
;if !dir || !*dir || (t && te && *te): dir = te
    test    rbx, rbx
    jz      .use_te
    cmp     byte [rbx], 0
    je      .use_te
    cmp     byte [t_flag], 1
    jne     .dir_ready
    test    r15, r15
    jz      .dir_ready
    cmp     byte [r15], 0
    je      .dir_ready
.use_te:
    mov     rbx, r15
.dir_ready:
;if !dir || !*dir: dir = "/tmp"
    test    rbx, rbx
    jz      .use_tmp
    cmp     byte [rbx], 0
    jne     .have_dir
.use_tmp:
    mov     rbx, def_tmp
.have_dir:
;template
    mov     r14, [template]
    test    r14, r14
    jnz     .have_tmpl
    mov     r14, def_tmpl
    jmp     .build
.have_tmpl:
;if template[0]=='/' && p && *p: error
    cmp     byte [r14], '/'
    jne     .tmpl_dir
    mov     rax, [p_ptr]
    test    rax, rax
    jz      .tmpl_dir
    cmp     byte [rax], 0
    je      .tmpl_dir
    jmp     fail
.tmpl_dir:
;if !p && !t: dir = NULL (use template as-is)
    cmp     byte [p_flag], 1
    je      .build
    cmp     byte [t_flag], 1
    je      .build
    xor     rbx, rbx                    ;no dir prefix
.build:
;final = dir ? dir/template : template
    test    rbx, rbx
    jz      .tmpl_only
    mov     rsi, rbx
    mov     rdi, finalpath
    call    strcpy_c
    mov     byte [finalpath + rax], '/'
    lea     rdi, [finalpath + rax + 1]
    mov     rsi, r14
    call    strcpy_c
    jmp     .validate
.tmpl_only:
    mov     rsi, r14
    mov     rdi, finalpath
    call    strcpy_c
.validate:
    mov     rdi, finalpath
    call    strlen_c
    mov     [flen], rax
    cmp     rax, 3
    jl      fail
    mov     rcx, rax
    cmp     byte [finalpath + rcx - 1], 'X'
    jne     fail
    cmp     byte [finalpath + rcx - 2], 'X'
    jne     fail
    cmp     byte [finalpath + rcx - 3], 'X'
    jne     fail

    cmp     byte [u_flag], 1
    jne     create
    call    fill_template
    jmp     print

create:
    mov     r14, 200                    ;retry count
.retry:
    call    fill_template
    cmp     byte [d_flag], 1
    je      .mkdir
    mov     rax, SYS_OPEN
    mov     rdi, finalpath
    mov     rsi, O_RDWR | O_CREAT | O_EXCL
    mov     rdx, 0o600
    syscall
    test    rax, rax
    jns     .ok_close
    dec     r14
    jnz     .retry
    jmp     fail_create
.ok_close:
    mov     rdi, rax
    mov     rax, SYS_CLOSE
    syscall
    jmp     print
.mkdir:
    mov     rax, SYS_MKDIR
    mov     rdi, finalpath
    mov     rsi, 0o700
    syscall
    test    rax, rax
    jns     print
    dec     r14
    jnz     .retry
    jmp     fail_create

print:
    mov     rdi, finalpath
    call    strlen_c
    mov     byte [finalpath + rax], WHITESPACE_NL
    inc     rax
    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, finalpath
    syscall
    xor     rdi, rdi
    mov     rax, SYS_EXIT
    syscall

fail_create:
    cmp     byte [q_flag], 1
    je      .quiet
    write   STDERR_FILENO, err_msg, err_len
.quiet:
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall

fail:
    write   STDERR_FILENO, err_msg, err_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall

; fill_template: replace trailing X's of [finalpath] with random characters.
fill_template:
    mov     rax, SYS_GETRANDOM
    mov     rdi, randbuf
    mov     rsi, 8
    xor     rdx, rdx
    syscall
    mov     r8, [randbuf]
    mov     rcx, [flen]
.l:
    dec     rcx
    cmp     rcx, 0
    jle     .done
    cmp     byte [finalpath + rcx], 'X'
    jne     .done
    mov     rax, r8
    and     rax, 63
    add     al, '-'
    cmp     al, '.'
    jle     .m1
    inc     al
.m1:
    cmp     al, '9'
    jle     .m2
    add     al, 7
.m2:
    cmp     al, 'Z'
    jle     .m3
    add     al, 6
.m3:
    mov     [finalpath + rcx], al
    shr     r8, 6
    jmp     .l
.done:
    ret

; getenv: rdi = name -> rax = value pointer, or 0.
getenv:
    mov     r8, [envp_base]
.l:
    mov     rsi, [r8]
    test    rsi, rsi
    jz      .none
    xor     rcx, rcx
.cmp:
    mov     al, [rdi + rcx]
    test    al, al
    jz      .checkeq
    cmp     al, [rsi + rcx]
    jne     .next
    inc     rcx
    jmp     .cmp
.checkeq:
    cmp     byte [rsi + rcx], '='
    jne     .next
    lea     rax, [rsi + rcx + 1]
    ret
.next:
    add     r8, 8
    jmp     .l
.none:
    xor     rax, rax
    ret

; streq_c: rax = 1 if rsi and rdi are equal strings.
streq_c:
    xor     rcx, rcx
.l:
    mov     al, [rsi + rcx]
    cmp     al, [rdi + rcx]
    jne     .no
    test    al, al
    jz      .yes
    inc     rcx
    jmp     .l
.yes:
    mov     rax, 1
    ret
.no:
    xor     rax, rax
    ret

; prefix_eq: rax = pointer in rcx(string) after prefix rdi, or 0 if no match.
prefix_eq:
    xor     r9, r9
.l:
    mov     al, [rdi + r9]
    test    al, al
    jz      .match
    cmp     al, [rcx + r9]
    jne     .no
    inc     r9
    jmp     .l
.match:
    lea     rax, [rcx + r9]
    ret
.no:
    xor     rax, rax
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

section .bss
    empty       resb 1
