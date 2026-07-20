; src/mv.asm -- mv(1): rename or move files.
; Usage: mv [-fin] SOURCE... DEST
;
; With a directory DEST each SOURCE is moved to DEST/basename. -n skips an
; existing destination, -i prompts before overwriting one, -f forces. Moves use
; rename(2) (same-filesystem only).

    %include "include/sysdefs.inc"

    %define S_IFMT  0xF000
    %define S_IFDIR 0x4000

section .bss
    stat_buf    resb 160
    target      resb 4096
    operands    resq 256
    nops        resq 1
    f_flag      resb 1
    n_flag      resb 1
    i_flag      resb 1
    had_err     resb 1
    promptbuf   resb 1

section .data
usage_msg   db "mv: need source and destination", WHITESPACE_NL
    usage_len   equ $ - usage_msg
err_pre     db "mv: cannot move '"
    err_pre_len equ $ - err_pre
    err_post    db "'", WHITESPACE_NL
    err_post_len equ $ - err_post
prompt_pre  db "mv: overwrite '"
    prompt_pre_len equ $ - prompt_pre
    prompt_post db "'? "
    prompt_post_len equ $ - prompt_post

section .text
global _start

_start:
    mov     byte [f_flag], 0
    mov     byte [n_flag], 0
    mov     byte [i_flag], 0
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
    je      .op                         ;lone "-" is an operand
    lea     rsi, [rdi + 1]
.oc:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 'f'
    je      .sf
    cmp     al, 'n'
    je      .sn
    cmp     al, 'i'
    je      .si
    inc     rsi
    jmp     .oc
.sf:
    mov     byte [f_flag], 1
    inc     rsi
    jmp     .oc
.sn:
    mov     byte [n_flag], 1
    inc     rsi
    jmp     .oc
.si:
    mov     byte [i_flag], 1
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
    cmp     qword [nops], 2
    jge     .run
    write   STDERR_FILENO, usage_msg, usage_len
    mov     rdi, 1
    mov     rax, SYS_EXIT
    syscall
.run:
;dest = operands[nops-1]
    mov     rax, [nops]
    dec     rax
    mov     rbx, [operands + rax*8]     ;dest pointer (kept in rbx)
;is dest a directory?
    mov     rdi, rbx
    mov     rsi, stat_buf
    mov     rax, SYS_STAT
    syscall
    xor     r15, r15                    ;dest-is-dir flag
    test    rax, rax
    js      .loop_init
    mov     ax, [stat_buf + 24]
    and     ax, S_IFMT
    cmp     ax, S_IFDIR
    jne     .loop_init
    mov     r15, 1
.loop_init:
    xor     r14, r14                    ;source index
    mov     r13, [nops]
    dec     r13                         ;number of sources
.sloop:
    cmp     r14, r13
    jge     .done
    mov     r12, [operands + r14*8]     ;source
;build target
    test    r15, r15
    jz      .plain
    call    build_dir_target            ;target = dest/basename(source)
    jmp     .checkdest
.plain:
    mov     rdi, rbx                    ;target = dest
    mov     rsi, target
    call    copy_str
.checkdest:
;-n: skip if target exists
    cmp     byte [n_flag], 1
    jne     .checki
    call    target_exists
    test    rax, rax
    jnz     .next
.checki:
;-i: prompt if target exists
    cmp     byte [i_flag], 1
    jne     .do_rename
    call    target_exists
    test    rax, rax
    jz      .do_rename
    call    prompt_yes
    test    rax, rax
    jz      .next
.do_rename:
    mov     rax, SYS_RENAME
    mov     rdi, r12
    mov     rsi, target
    syscall
    test    rax, rax
    jns     .next
;error
    mov     byte [had_err], 1
    write   STDERR_FILENO, err_pre, err_pre_len
    mov     rsi, r12
    call    put_cstr_err
    write   STDERR_FILENO, err_post, err_post_len
.next:
    inc     r14
    jmp     .sloop
.done:
    movzx   edi, byte [had_err]
    mov     rax, SYS_EXIT
    syscall

; build_dir_target: target = dest(rbx) + "/" + basename(r12 source).
build_dir_target:
    mov     rdi, rbx
    mov     rsi, target
    call    copy_str                    ;rax = length written (excl NUL)
;ensure a trailing slash
    test    rax, rax
    jz      .slash
    cmp     byte [target + rax - 1], '/'
    je      .base
.slash:
    mov     byte [target + rax], '/'
    inc     rax
.base:
    mov     r10, rax                    ;target write offset (survives strlen_r)
;compute basename of source r12
    mov     rdi, r12
    call    strlen_r                    ;rax = len
    mov     rcx, rax                    ;len
.striptrail:
    cmp     rcx, 1
    jle     .findslash
    cmp     byte [r12 + rcx - 1], '/'
    jne     .findslash
    dec     rcx
    jmp     .striptrail
.findslash:
    xor     r8, r8                      ;start
    mov     r9, rcx
    dec     r9
.scan:
    cmp     r9, 0
    jl      .copybase
    cmp     byte [r12 + r9], '/'
    jne     .scandec
    lea     r8, [r9 + 1]
    jmp     .copybase
.scandec:
    dec     r9
    jmp     .scan
.copybase:
;append source[r8..rcx) to target at the saved offset
    mov     rdx, r10                    ;target write offset
.cb:
    cmp     r8, rcx
    jge     .cbdone
    mov     al, [r12 + r8]
    mov     [target + rdx], al
    inc     r8
    inc     rdx
    jmp     .cb
.cbdone:
    mov     byte [target + rdx], 0
    ret

; target_exists: rax = 1 if [target] exists.
target_exists:
    mov     rdi, target
    mov     rsi, stat_buf
    mov     rax, SYS_STAT
    syscall
    test    rax, rax
    jns     .yes
    xor     rax, rax
    ret
.yes:
    mov     rax, 1
    ret

; prompt_yes: prompt on stderr, read a byte from stdin; rax = 1 if it is y/Y.
prompt_yes:
    write   STDERR_FILENO, prompt_pre, prompt_pre_len
    mov     rsi, target
    call    put_cstr_err
    write   STDERR_FILENO, prompt_post, prompt_post_len
    mov     rax, SYS_READ
    mov     rdi, STDIN_FILENO
    mov     rsi, promptbuf
    mov     rdx, 1
    syscall
    test    rax, rax
    jle     .no
    movzx   eax, byte [promptbuf]
    cmp     al, 'y'
    je      .yes
    cmp     al, 'Y'
    je      .yes
.no:
    xor     rax, rax
    ret
.yes:
    mov     rax, 1
    ret

; copy_str: rdi -> rsi, NUL-terminated; rax = length copied (excl NUL).
copy_str:
    xor     rax, rax
.l:
    mov     cl, [rdi + rax]
    mov     [rsi + rax], cl
    test    cl, cl
    jz      .done
    inc     rax
    jmp     .l
.done:
    ret

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
