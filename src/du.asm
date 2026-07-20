; src/du.asm -- du(1): summarize disk usage (in 1K blocks).
; Usage: du [-ksLHa] [FILE...]
;
; Each directory's cumulative allocation (its own blocks plus every child) is
; printed post-order; -s prints only the operands, -a also prints files.
; Symlinks are counted but not followed unless -L (or -H for operands); -L
; guards against cycles by remembering visited directories.

    %include "include/sysdefs.inc"

    %define SYS_LSTAT 6
    %define S_IFMT  0xF000
    %define S_IFDIR 0x4000
    %define MAXDEPTH 64

section .bss
    path        resb 8192
    stat_buf    resb 160
    numbuf      resb 32
    dentbuf     resb (MAXDEPTH * 32768)
    d_plen      resq MAXDEPTH
    d_fd        resq MAXDEPTH
    d_blocks    resq MAXDEPTH
    d_off       resq MAXDEPTH
    d_dcnt      resq MAXDEPTH
    d_dbuf      resq MAXDEPTH
    d_isdir     resq MAXDEPTH
    vis_dev     resq 1024
    vis_ino     resq 1024
    nvis        resq 1
    operands    resq 256
    nops        resq 1
    s_flag      resb 1
    l_flag      resb 1
    h_flag      resb 1
    a_flag      resb 1

section .data
    dot         db ".", 0
    tab         db 9
    nl          db WHITESPACE_NL

section .text
global _start

_start:
    mov     byte [s_flag], 0
    mov     byte [l_flag], 0
    mov     byte [h_flag], 0
    mov     byte [a_flag], 0
    mov     qword [nops], 0
    mov     qword [nvis], 0

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
    cmp     al, 'L'
    je      .sl
    cmp     al, 'H'
    je      .sh
    cmp     al, 'a'
    je      .sa
    inc     rsi                         ;ignore -k and others
    jmp     .oc
.ss:
    mov     byte [s_flag], 1
    inc     rsi
    jmp     .oc
.sl:
    mov     byte [l_flag], 1            ;-L follows all; last of -L/-H wins
    mov     byte [h_flag], 0
    inc     rsi
    jmp     .oc
.sh:
    mov     byte [h_flag], 1
    mov     byte [l_flag], 0
    inc     rsi
    jmp     .oc
.sa:
    mov     byte [a_flag], 1
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
    cmp     qword [nops], 0
    jne     .loop
    mov     qword [operands], dot       ;default operand is "."
    mov     qword [nops], 1
.loop:
    xor     r14, r14
.each:
    cmp     r14, [nops]
    jge     .done
    mov     rsi, [operands + r14*8]
    mov     rdi, path
    call    strcpy_c
    xor     rdi, rdi                    ;depth 0
    mov     rsi, 1                      ;command-line operand
    call    du_walk
    inc     r14
    jmp     .each
.done:
    xor     rdi, rdi
    mov     rax, SYS_EXIT
    syscall

; du_walk: rdi = depth, rsi = cmdline flag -> rax = accumulated 512B blocks.
; Per-frame state lives in the d_* arrays indexed by depth, so only r15 (the
; depth) must survive the recursive call.
du_walk:
    push    r15
    mov     r15, rdi
;choose stat vs lstat
    cmp     byte [l_flag], 1
    je      .follow
    cmp     byte [h_flag], 1
    jne     .lstat
    test    rsi, rsi
    jz      .lstat
.follow:
    mov     rax, SYS_STAT
    jmp     .dostat
.lstat:
    mov     rax, SYS_LSTAT
.dostat:
    mov     rdi, path
    mov     rsi, stat_buf
    syscall
    test    rax, rax
    js      .zero
    mov     rax, [stat_buf + 64]        ;st_blocks
    mov     [d_blocks + r15*8], rax
    mov     qword [d_isdir + r15*8], 0
    mov     ax, [stat_buf + 24]
    and     ax, S_IFMT
    cmp     ax, S_IFDIR
    jne     .print
    mov     qword [d_isdir + r15*8], 1
;cycle guard when following symlinks
    cmp     byte [l_flag], 1
    jne     .recurse
    call    seen_dir
    test    rax, rax
    jz      .recurse
    mov     qword [d_blocks + r15*8], 0 ;already counted elsewhere
    jmp     .ret
.recurse:
    mov     rdi, path
    call    strlen_c
    mov     [d_plen + r15*8], rax
    mov     rax, SYS_OPEN
    mov     rdi, path
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .print
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
    lea     rdi, [rsi + 19]             ;d_name
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
    xor     rsi, rsi
    call    du_walk
    add     [d_blocks + r15*8], rax
    mov     rcx, [d_plen + r15*8]
    mov     byte [path + rcx], 0
.skip:
    mov     rsi, [d_dbuf + r15*8]
    add     rsi, [d_off + r15*8]
    movzx   eax, word [rsi + 16]        ;d_reclen
    add     [d_off + r15*8], rax
    jmp     .entry
.closedir:
    mov     rax, SYS_CLOSE
    mov     rdi, [d_fd + r15*8]
    syscall
.print:
;print if depth==0, or (!s and (dir or -a))
    test    r15, r15
    jz      .doprint
    cmp     byte [s_flag], 1
    je      .ret
    cmp     qword [d_isdir + r15*8], 1
    je      .doprint
    cmp     byte [a_flag], 1
    je      .doprint
    jmp     .ret
.doprint:
    mov     rax, [d_blocks + r15*8]
    inc     rax
    shr     rax, 1                      ;blocks -> 1K units (round up)
    mov     rdi, rax
    call    put_dec
    write   STDOUT_FILENO, tab, 1
    mov     rsi, path
    call    put_cstr
    write   STDOUT_FILENO, nl, 1
.ret:
    mov     rax, [d_blocks + r15*8]
    pop     r15
    ret
.zero:
    xor     rax, rax
    pop     r15
    ret

; seen_dir: rax = 1 if the current stat_buf dir was visited; records it if not.
seen_dir:
    mov     r8, [stat_buf + 0]          ;dev
    mov     r9, [stat_buf + 8]          ;ino
    xor     rcx, rcx
.l:
    cmp     rcx, [nvis]
    jge     .add
    cmp     r8, [vis_dev + rcx*8]
    jne     .n
    cmp     r9, [vis_ino + rcx*8]
    jne     .n
    mov     rax, 1
    ret
.n:
    inc     rcx
    jmp     .l
.add:
    mov     rcx, [nvis]
    cmp     rcx, 1024
    jge     .full
    mov     [vis_dev + rcx*8], r8
    mov     [vis_ino + rcx*8], r9
    inc     qword [nvis]
.full:
    xor     rax, rax
    ret

; put_dec: rdi -> decimal on stdout.
put_dec:
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
    mov     rdi, STDOUT_FILENO
    mov     rsi, rcx
    mov     rdx, r9
    syscall
    ret

; put_cstr: rsi -> stdout (NUL-terminated).
put_cstr:
    xor     rdx, rdx
.l:
    cmp     byte [rsi + rdx], 0
    je      .w
    inc     rdx
    jmp     .l
.w:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
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
