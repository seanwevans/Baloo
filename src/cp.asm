; src/cp.asm -- cp(1): copy files and directory trees.
; Usage: cp [-rRapf] SOURCE... DEST
;
; A directory DEST receives each SOURCE as DEST/basename; otherwise a single
; SOURCE copies to DEST. -r/-R/-a recurse into directories (preserving
; symlinks), -p preserves mode and timestamps, -f unlinks an unwritable
; destination and retries.

    %include "include/sysdefs.inc"

    %define SYS_LSTAT 6
    %define S_IFMT  0xF000
    %define S_IFDIR 0x4000
    %define S_IFLNK 0xA000

section .bss
    srcpath     resb 4096
    dstpath     resb 4096
    linkbuf     resb 4096
    copybuf     resb 65536
    stat_buf    resb 160
    tsp         resq 4
    save_mode   resq 1
    save_smtime resq 1
    save_snsec  resq 1
    fullsrc     resb 4096
    operands    resq 256
    nops        resq 1
    r_flag      resb 1
    f_flag      resb 1
    p_flag      resb 1
    t_flag      resb 1
    bigp_flag   resb 1
    u_flag      resb 1
    i_flag      resb 1
    parents     resb 1
    tdir        resq 1
    had_err     resb 1
    promptbuf   resb 1

section .data
err_args    db "cp: need source and destination", WHITESPACE_NL
    err_args_len equ $ - err_args
err_dir     db "cp: -r needed to copy a directory", WHITESPACE_NL
    err_dir_len equ $ - err_dir
err_gen     db "cp: cannot copy file", WHITESPACE_NL
    err_gen_len equ $ - err_gen
    dashparents db "--parents", 0
prompt_pre  db "cp: overwrite '"
    prompt_pre_len equ $ - prompt_pre
    prompt_post db "'? "
    prompt_post_len equ $ - prompt_post

section .text
global _start

_start:
    mov     byte [r_flag], 0
    mov     byte [f_flag], 0
    mov     byte [p_flag], 0
    mov     byte [t_flag], 0
    mov     byte [bigp_flag], 0
    mov     byte [u_flag], 0
    mov     byte [i_flag], 0
    mov     byte [parents], 0
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
    cmp     byte [rdi + 1], '-'
    je      .long
    lea     rsi, [rdi + 1]
.oc:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 'r'
    je      .sr
    cmp     al, 'R'
    je      .sr
    cmp     al, 'a'
    je      .sa
    cmp     al, 'p'
    je      .sp
    cmp     al, 'f'
    je      .sfl
    cmp     al, 'T'
    je      .sT
    cmp     al, 'P'
    je      .sP
    cmp     al, 'u'
    je      .su
    cmp     al, 'i'
    je      .siv
    cmp     al, 't'
    je      .stv
    inc     rsi
    jmp     .oc
.long:
;only --parents is acted on; other long options are ignored
    mov     rsi, rdi
    mov     rdi, dashparents
    call    streq_c
    test    rax, rax
    jz      .nextarg
    mov     byte [parents], 1
    jmp     .nextarg
.sT:
    mov     byte [t_flag], 1
    inc     rsi
    jmp     .oc
.sP:
    mov     byte [bigp_flag], 1
    inc     rsi
    jmp     .oc
.su:
    mov     byte [u_flag], 1
    inc     rsi
    jmp     .oc
.siv:
    mov     byte [i_flag], 1
    inc     rsi
    jmp     .oc
.stv:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .tv_here
    add     r13, 8
    dec     r12
    mov     rsi, [r13]
.tv_here:
    mov     [tdir], rsi
    jmp     .nextarg
.sr:
    mov     byte [r_flag], 1
    inc     rsi
    jmp     .oc
.sa:
    mov     byte [r_flag], 1
    mov     byte [p_flag], 1
    inc     rsi
    jmp     .oc
.sp:
    mov     byte [p_flag], 1
    inc     rsi
    jmp     .oc
.sfl:
    mov     byte [f_flag], 1
    inc     rsi
    jmp     .oc
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
    cmp     qword [nops], 1             ;-t supplies the destination
    jge     .run
    jmp     .argerr
.need2:
    cmp     qword [nops], 2
    jge     .run
.argerr:
    write   STDERR_FILENO, err_args, err_args_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall
.run:
    cmp     qword [tdir], 0
    je      .no_tdir
mov     r15, [tdir]                 ;-t DIR: all operands are sources
    mov     r13, [nops]
    mov     r14, 1
    jmp     .loop
.no_tdir:
    mov     rax, [nops]
    dec     rax
    mov     r15, [operands + rax*8]     ;dest
    mov     r13, rax                    ;source count
    xor     r14, r14                    ;dest-is-dir
    cmp     byte [t_flag], 1
    je      .checkmulti                 ;-T forces non-dir dest
    mov     rdi, r15
    mov     rsi, stat_buf
    mov     rax, SYS_STAT
    syscall
    test    rax, rax
    js      .checkmulti
    mov     ax, [stat_buf + 24]
    and     ax, S_IFMT
    cmp     ax, S_IFDIR
    jne     .checkmulti
    mov     r14, 1
.checkmulti:
    cmp     r13, 1
    jle     .loop
    test    r14, r14
    jnz     .loop
    write   STDERR_FILENO, err_gen, err_gen_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall
.loop:
    xor     r12, r12
.each:
    cmp     r12, r13
    jge     .done
    mov     rsi, [operands + r12*8]     ;source
    mov     rdi, srcpath
    call    strcpy_c
;build dstpath
    test    r14, r14
    jz      .plain
    cmp     byte [parents], 1
    je      .parents_path
    mov     rsi, [operands + r12*8]
    call    dest_in_dir
    jmp     .go
.parents_path:
    mov     rsi, [operands + r12*8]
    call    dest_full_path
    call    mkdir_parents
    jmp     .go
.plain:
    mov     rsi, r15
    mov     rdi, dstpath
    call    strcpy_c
.go:
    call    copy_tree
    inc     r12
    jmp     .each
.done:
    movzx   edi, byte [had_err]
    mov     rax, SYS_EXIT
    syscall

; dest_in_dir: dstpath = dest(r15) + "/" + basename(rsi source).
dest_in_dir:
    mov     r8, rsi                     ;source
    mov     rsi, r15                    ;dest string
    mov     rdi, dstpath
    call    strcpy_c                    ;rax = dest length
    test    rax, rax
    jz      .slash
    cmp     byte [dstpath + rax - 1], '/'
    je      .base
.slash:
    mov     byte [dstpath + rax], '/'
    inc     rax
.base:
    mov     r9, rax                     ;dst offset
    mov     rdi, r8
    call    strlen_c
    mov     rcx, rax                    ;source length
.strip:
    cmp     rcx, 1
    jle     .find
    cmp     byte [r8 + rcx - 1], '/'
    jne     .find
    dec     rcx
    jmp     .strip
.find:
    xor     r10, r10
    mov     r11, rcx
    dec     r11
.scan:
    cmp     r11, 0
    jl      .cp
    cmp     byte [r8 + r11], '/'
    jne     .dec
    lea     r10, [r11 + 1]
    jmp     .cp
.dec:
    dec     r11
    jmp     .scan
.cp:
    mov     rdx, r9
.cl:
    cmp     r10, rcx
    jge     .cdone
    mov     al, [r8 + r10]
    mov     [dstpath + rdx], al
    inc     r10
    inc     rdx
    jmp     .cl
.cdone:
    mov     byte [dstpath + rdx], 0
    ret

; copy_tree: copy [srcpath] to [dstpath] (recursive). Sets had_err on failure.
copy_tree:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rax, SYS_LSTAT              ;-p/-P preserve symlinks; otherwise follow
    cmp     byte [p_flag], 1
    je      .dostat
    cmp     byte [bigp_flag], 1
    je      .dostat
    mov     rax, SYS_STAT
.dostat:
    mov     rdi, srcpath
    mov     rsi, stat_buf
    syscall
    test    rax, rax
    js      .err
    mov     ax, [stat_buf + 24]
    and     ax, S_IFMT
    cmp     ax, S_IFLNK
    je      .symlink
    cmp     ax, S_IFDIR
    je      .dir
    call    copy_file
    jmp     .ok
.symlink:
    mov     rax, SYS_READLINK
    mov     rdi, srcpath
    mov     rsi, linkbuf
    mov     rdx, 4095
    syscall
    test    rax, rax
    js      .err
    mov     byte [linkbuf + rax], 0
    cmp     byte [f_flag], 1
    jne     .dosym
    mov     rax, SYS_UNLINK
    mov     rdi, dstpath
    syscall
.dosym:
    mov     rax, SYS_SYMLINK
    mov     rdi, linkbuf
    mov     rsi, dstpath
    syscall
    jmp     .ok
.dir:
    cmp     byte [r_flag], 1
    jne     .errdir
    mov     rax, SYS_MKDIR
    mov     rdi, dstpath
    mov     rsi, 0o777
    syscall
    mov     rax, SYS_STAT
    mov     rdi, dstpath
    mov     rsi, stat_buf
    syscall
    test    rax, rax
    js      .err
    mov     ax, [stat_buf + 24]
    and     ax, S_IFMT
    cmp     ax, S_IFDIR
    jne     .err
    mov     rdi, srcpath
    call    strlen_c
    mov     r13, rax                    ;slen
    mov     rdi, dstpath
    call    strlen_c
    mov     r14, rax                    ;dlen
    mov     rax, SYS_OPEN
    mov     rdi, srcpath
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .err
    mov     r12, rax                    ;dir fd
    sub     rsp, 32784
    mov     rbx, rsp                    ;dentbuf
.readmore:
    mov     rax, SYS_GETDENTS64
    mov     rdi, r12
    mov     rsi, rbx
    mov     rdx, 32768
    syscall
    test    rax, rax
    jle     .dirdone
    mov     rbp, rax                    ;bytes in dentbuf
    xor     r15, r15                    ;offset
.entryloop:
    cmp     r15, rbp
    jge     .readmore
    lea     rsi, [rbx + r15 + 19]       ;d_name
    cmp     byte [rsi], '.'
    jne     .process
    cmp     byte [rsi + 1], 0
    je      .skip
    cmp     byte [rsi + 1], '.'
    jne     .process
    cmp     byte [rsi + 2], 0
    je      .skip
.process:
    mov     byte [srcpath + r13], '/'
    mov     byte [dstpath + r14], '/'
    lea     rdi, [srcpath + r13 + 1]
    lea     rcx, [dstpath + r14 + 1]
    mov     rdx, rsi
.cpn:
    mov     al, [rdx]
    mov     [rdi], al
    mov     [rcx], al
    test    al, al
    jz      .cpndone
    inc     rdx
    inc     rdi
    inc     rcx
    jmp     .cpn
.cpndone:
    call    copy_tree
    mov     byte [srcpath + r13], 0
    mov     byte [dstpath + r14], 0
.skip:
    movzx   eax, word [rbx + r15 + 16]  ;d_reclen
    add     r15, rax
    jmp     .entryloop
.dirdone:
    add     rsp, 32784
    mov     rax, SYS_CLOSE
    mov     rdi, r12
    syscall
    cmp     byte [p_flag], 1
    jne     .ok
    call    preserve
    jmp     .ok
.errdir:
    write   STDERR_FILENO, err_dir, err_dir_len
.err:
    mov     byte [had_err], 1
.ok:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; copy_file: copy the regular file [srcpath] to [dstpath]. Uses [stat_buf]
; (the caller's lstat) for the mode. Preserves r12-r15/rbx/rbp.
copy_file:
    mov     eax, [stat_buf + 24]
    and     eax, 0o7777
    mov     [save_mode], rax
    mov     rax, [stat_buf + 88]        ;source mtime (for -u)
    mov     [save_smtime], rax
    mov     rax, [stat_buf + 96]
    mov     [save_snsec], rax
;-u: skip if the destination is at least as new (seconds, then nanoseconds)
    cmp     byte [u_flag], 1
    jne     .after_u
    mov     rax, SYS_STAT
    mov     rdi, dstpath
    mov     rsi, stat_buf
    syscall
    test    rax, rax
    js      .after_u
    mov     rax, [stat_buf + 88]
    cmp     rax, [save_smtime]
    ja      .ret
    jb      .after_u
    mov     rax, [stat_buf + 96]
    cmp     rax, [save_snsec]
    jae     .ret
.after_u:
;-i: prompt before overwriting an existing destination
    cmp     byte [i_flag], 1
    jne     .doopen
    mov     rax, SYS_STAT
    mov     rdi, dstpath
    mov     rsi, stat_buf
    syscall
    test    rax, rax
    js      .doopen
    call    prompt_yes
    test    rax, rax
    jz      .ret
.doopen:
    mov     rax, SYS_OPEN
    mov     rdi, srcpath
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .err
    mov     r8, rax                     ;source fd
    mov     rax, SYS_OPEN
    mov     rdi, dstpath
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, [save_mode]
    syscall
    test    rax, rax
    jns     .dstok
    cmp     byte [f_flag], 1
    jne     .closesrc
    mov     rax, SYS_UNLINK
    mov     rdi, dstpath
    syscall
    mov     rax, SYS_OPEN
    mov     rdi, dstpath
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, [save_mode]
    syscall
    test    rax, rax
    js      .closesrc
.dstok:
    mov     r9, rax                     ;dest fd
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
    cmp     rax, r10
    jne     .writeerr
    jmp     .cl
.cdone:
    mov     rax, SYS_CLOSE
    mov     rdi, r9
    syscall
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    cmp     byte [p_flag], 1
    jne     .ret
    call    preserve
    jmp     .ret
.writeerr:
    mov     rax, SYS_CLOSE
    mov     rdi, r9
    syscall
.closesrc:
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
.err:
    mov     byte [had_err], 1
.ret:
    ret

; preserve: copy [srcpath]'s mode and times onto [dstpath].
preserve:
    mov     rax, SYS_LSTAT
    mov     rdi, srcpath
    mov     rsi, stat_buf
    syscall
    mov     eax, [stat_buf + 24]
    and     eax, 0o7777
    mov     rdx, rax
    mov     rax, SYS_CHMOD
    mov     rdi, dstpath
    mov     rsi, rdx
    syscall
    mov     rax, [stat_buf + 72]
    mov     [tsp + 0], rax
    mov     rax, [stat_buf + 80]
    mov     [tsp + 8], rax
    mov     rax, [stat_buf + 88]
    mov     [tsp + 16], rax
    mov     rax, [stat_buf + 96]
    mov     [tsp + 24], rax
    mov     rax, SYS_UTIMENSAT
    mov     rdi, AT_FDCWD
    mov     rsi, dstpath
    mov     rdx, tsp
    xor     r10, r10
    syscall
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

; streq_c: rax = 1 if the strings rsi and rdi are equal.
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

; dest_full_path: dstpath = dest(r15) + "/" + full source path (rsi).
dest_full_path:
    mov     r8, rsi
    mov     rsi, r15
    mov     rdi, dstpath
    call    strcpy_c
    test    rax, rax
    jz      .slash
    cmp     byte [dstpath + rax - 1], '/'
    je      .app
.slash:
    mov     byte [dstpath + rax], '/'
    inc     rax
.app:
    mov     rdx, rax
    xor     rcx, rcx
.cl:
    mov     al, [r8 + rcx]
    test    al, al
    jz      .done
    mov     [dstpath + rdx], al
    inc     rcx
    inc     rdx
    jmp     .cl
.done:
    mov     byte [dstpath + rdx], 0
    ret

; mkdir_parents: create every parent directory of [dstpath].
mkdir_parents:
    mov     rdi, dstpath
    call    strlen_c
    mov     r9, rax                     ;length (survives the mkdir syscall)
    mov     r8, 1                       ;index (skip a leading '/')
.l:
    cmp     r8, r9
    jge     .done
    cmp     byte [dstpath + r8], '/'
    jne     .next
    mov     byte [dstpath + r8], 0
    mov     rax, SYS_MKDIR
    mov     rdi, dstpath
    mov     rsi, 0o777
    syscall
    mov     byte [dstpath + r8], '/'
.next:
    inc     r8
    jmp     .l
.done:
    ret

; prompt_yes: prompt on stderr, read a line from stdin; rax = 1 if it starts y/Y.
prompt_yes:
    write   STDERR_FILENO, prompt_pre, prompt_pre_len
    mov     rsi, dstpath
    call    put_cstr_err
    write   STDERR_FILENO, prompt_post, prompt_post_len
    mov     rax, SYS_READ
    mov     rdi, STDIN_FILENO
    mov     rsi, promptbuf
    mov     rdx, 1
    syscall
    test    rax, rax
    jle     .no
    movzx   r9d, byte [promptbuf]
.drain:
    cmp     byte [promptbuf], WHITESPACE_NL
    je      .decide
    mov     rax, SYS_READ
    mov     rdi, STDIN_FILENO
    mov     rsi, promptbuf
    mov     rdx, 1
    syscall
    test    rax, rax
    jle     .decide
    jmp     .drain
.decide:
    cmp     r9b, 'y'
    je      .yes
    cmp     r9b, 'Y'
    je      .yes
.no:
    xor     rax, rax
    ret
.yes:
    mov     rax, 1
    ret

; put_cstr_err: rsi -> stderr (NUL-terminated).
put_cstr_err:
    xor     rdx, rdx
.l:
    cmp     byte [rsi + rdx], 0
    je      .w
    inc     rdx
    jmp     .l
.w:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    ret
