; src/chgrp.asm -- chgrp(1): change file group ownership.
; Usage: chgrp [-RHLPhfv] GROUP FILE...
;
; The node is chowned following the symlink unless NOFOLLOW = !(L|H) && (h|R).
; -R recurses; a symlink-to-directory is descended into only when followed (on
; the command line for -H, or anywhere for -L).

    %include "include/sysdefs.inc"

    %define SYS_LSTAT 6
    %define SYS_LCHOWN 94
    %define S_IFMT  0xF000
    %define S_IFDIR 0x4000
    %define MAXDEPTH 64

section .bss
    group_buf   resb 65536
    group_len   resq 1
    path        resb 8192
    stat_buf    resb 160
    dentbuf     resb (MAXDEPTH * 32768)
    d_plen      resq MAXDEPTH
    d_fd        resq MAXDEPTH
    d_off       resq MAXDEPTH
    d_dcnt      resq MAXDEPTH
    d_dbuf      resq MAXDEPTH
    operands    resq 256
    nops        resq 1
    gid         resq 1
    r_flag      resb 1
    hlit        resb 1                  ;-h
    hcap        resb 1                  ;-H
    l_flag      resb 1                  ;-L
    nofollow    resb 1
    had_err     resb 1

section .data
    group_path  db "/etc/group", 0
usage_msg   db "chgrp: need group and file", WHITESPACE_NL
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    mov     qword [nops], 0
    mov     byte [r_flag], 0
    mov     byte [hlit], 0
    mov     byte [hcap], 0
    mov     byte [l_flag], 0
    mov     byte [had_err], 0
    mov     qword [gid], -1

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12
    xor     r14, r14                    ;operand count
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
    cmp     al, 'R'
    je      .sR
    cmp     al, 'h'
    je      .sh
    cmp     al, 'H'
    je      .sHc
    cmp     al, 'L'
    je      .sL
    cmp     al, 'P'
    je      .sP
    inc     rsi                         ;ignore -f/-v
    jmp     .oc
.sR:
    mov     byte [r_flag], 1
    inc     rsi
    jmp     .oc
.sh:
    mov     byte [hlit], 1
    inc     rsi
    jmp     .oc
.sHc:
    mov     byte [hcap], 1
    mov     byte [l_flag], 0            ;[-HLP] last wins
    inc     rsi
    jmp     .oc
.sL:
    mov     byte [l_flag], 1
    mov     byte [hcap], 0
    inc     rsi
    jmp     .oc
.sP:
    mov     byte [hcap], 0
    mov     byte [l_flag], 0
    inc     rsi
    jmp     .oc
.op:
    cmp     r14, 0
    jne     .file
    mov     [operands], rdi             ;first operand is the group name
    inc     r14
    jmp     .nextarg
.file:
    mov     rcx, [nops]
    mov     [operands + 8 + rcx*8], rdi
    inc     qword [nops]
    inc     r14
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

after_parse:
    cmp     r14, 2
    jge     .go
    write   STDERR_FILENO, usage_msg, usage_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall
.go:
;NOFOLLOW = !(L|H) && (h|R)
    mov     byte [nofollow], 0
    cmp     byte [l_flag], 1
    je      .nfdone
    cmp     byte [hcap], 1
    je      .nfdone
    cmp     byte [hlit], 1
    je      .setnf
    cmp     byte [r_flag], 1
    je      .setnf
    jmp     .nfdone
.setnf:
    mov     byte [nofollow], 1
.nfdone:
;resolve group name -> gid
    mov     rdi, group_path
    mov     rsi, group_buf
    call    read_file
    mov     [group_len], rax
    mov     rdi, [operands]
    mov     rsi, group_buf
    mov     rdx, [group_len]
    call    resolve
    mov     [gid], rax

;operand follow flag = H | L
    movzx   eax, byte [hcap]
    movzx   ecx, byte [l_flag]
    or      eax, ecx
    mov     [op_follow], rax

    xor     r14, r14
.each:
    cmp     r14, [nops]
    jge     .done
    mov     rsi, [operands + 8 + r14*8]
    mov     rdi, path
    call    strcpy_c
    xor     rdi, rdi
    mov     rsi, [op_follow]
    call    chgrp_walk
    inc     r14
    jmp     .each
.done:
    movzx   edi, byte [had_err]
    mov     rax, SYS_EXIT
    syscall

; chgrp_walk: rdi = depth, rsi = follow-this-node. Only r15 must survive
; recursion; per-frame state lives in the depth-indexed d_* arrays.
chgrp_walk:
    push    r15
    mov     r15, rdi
    test    rsi, rsi
    jz      .lstat
    mov     rax, SYS_STAT
    jmp     .dostat
.lstat:
    mov     rax, SYS_LSTAT
.dostat:
    mov     rdi, path
    mov     rsi, stat_buf
    syscall
    test    rax, rax
    js      .ret
;chown the node
    cmp     byte [nofollow], 1
    je      .lch
    mov     rax, SYS_CHOWN
    jmp     .doch
.lch:
    mov     rax, SYS_LCHOWN
.doch:
    mov     rdi, path
    mov     rsi, -1
    mov     rdx, [gid]
    syscall
    test    rax, rax
    jns     .rec
    mov     byte [had_err], 1
.rec:
    cmp     byte [r_flag], 1
    jne     .ret
    mov     ax, [stat_buf + 24]
    and     ax, S_IFMT
    cmp     ax, S_IFDIR
    jne     .ret
    mov     rdi, path
    call    strlen_c
    mov     [d_plen + r15*8], rax
    mov     rax, SYS_OPEN
    mov     rdi, path
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .ret
    mov     [d_fd + r15*8], rax
.readmore:
    mov     rax, r15
    imul    rax, rax, 32768
    add     rax, dentbuf
    mov     [d_dbuf + r15*8], rax
    mov     rax, SYS_GETDENTS64
    mov     rdi, [d_fd + r15*8]
    mov     rsi, [d_dbuf + r15*8]
    mov     rdx, 32768
    syscall
    test    rax, rax
    jle     .closedir
    mov     [d_dcnt + r15*8], rax
    mov     qword [d_off + r15*8], 0
.entry:
    mov     rax, [d_off + r15*8]
    cmp     rax, [d_dcnt + r15*8]
    jge     .readmore
    mov     rsi, [d_dbuf + r15*8]
    add     rsi, rax
    lea     rdi, [rsi + 19]
    cmp     byte [rdi], '.'
    jne     .proc
    cmp     byte [rdi + 1], 0
    je      .skip
    cmp     byte [rdi + 1], '.'
    jne     .proc
    cmp     byte [rdi + 2], 0
    je      .skip
.proc:
    mov     rcx, [d_plen + r15*8]
    mov     byte [path + rcx], '/'
    inc     rcx
.cpn:
    mov     al, [rdi]
    mov     [path + rcx], al
    test    al, al
    jz      .cpndone
    inc     rdi
    inc     rcx
    jmp     .cpn
.cpndone:
    lea     rdi, [r15 + 1]
    movzx   esi, byte [l_flag]          ;children follow only with -L
    call    chgrp_walk
    mov     rcx, [d_plen + r15*8]
    mov     byte [path + rcx], 0
.skip:
    mov     rsi, [d_dbuf + r15*8]
    add     rsi, [d_off + r15*8]
    movzx   eax, word [rsi + 16]
    add     [d_off + r15*8], rax
    jmp     .entry
.closedir:
    mov     rax, SYS_CLOSE
    mov     rdi, [d_fd + r15*8]
    syscall
.ret:
    pop     r15
    ret

; resolve: rdi = name, rsi = buffer, rdx = length -> rax = gid (third field).
resolve:
    cmp     byte [rdi], '0'
    jb      .byname
    cmp     byte [rdi], '9'
    ja      .byname
    xor     rax, rax
.num:
    movzx   ecx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .numdone
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    inc     rdi
    jmp     .num
.numdone:
    ret
.byname:
    xor     r8, r8
.line:
    cmp     r8, rdx
    jge     .notfound
    mov     r9, r8
    xor     r10, r10
.mtch:
    mov     al, [rdi + r10]
    test    al, al
    jz      .namedone
    cmp     r9, rdx
    jge     .nextline
    cmp     al, [rsi + r9]
    jne     .nextline
    inc     r9
    inc     r10
    jmp     .mtch
.namedone:
    cmp     r9, rdx
    jge     .nextline
cmp     byte [rsi + r9], ':'
    jne     .nextline
    inc     r9
.skipf:
    cmp     r9, rdx
    jge     .notfound
cmp     byte [rsi + r9], ':'
    je      .atid
    inc     r9
    jmp     .skipf
.atid:
    inc     r9
    xor     rax, rax
.dig:
    cmp     r9, rdx
    jge     .rid
    movzx   ecx, byte [rsi + r9]
    sub     cl, '0'
    cmp     cl, 9
    ja      .rid
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    inc     r9
    jmp     .dig
.rid:
    ret
.nextline:
    cmp     r8, rdx
    jge     .notfound
    cmp     byte [rsi + r8], WHITESPACE_NL
    je      .nl
    inc     r8
    jmp     .nextline
.nl:
    inc     r8
    jmp     .line
.notfound:
    mov     rax, -1
    ret

; read_file: rdi = path, rsi = buffer -> rax = length.
read_file:
    mov     r10, rsi
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .empty
    mov     r8, rax
    xor     r9, r9
.rd:
    mov     rax, SYS_READ
    mov     rdi, r8
    lea     rsi, [r10 + r9]
    mov     rdx, 65536
    sub     rdx, r9
    jle     .close
    syscall
    test    rax, rax
    jle     .close
    add     r9, rax
    jmp     .rd
.close:
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    mov     rax, r9
    ret
.empty:
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
    op_follow   resq 1
