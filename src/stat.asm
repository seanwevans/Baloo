; src/stat.asm -- print file metadata in a user format (stat -c FORMAT).
; Usage: stat -c FORMAT FILE...
; Supported directives: %n %s %i %h %u %g %f %a %A %F %b %o %d %%
; (Does not follow symlinks, matching coreutils stat's default lstat
; behaviour. The bare multi-line default output is not implemented; a
; format is required.)

    %include "include/sysdefs.inc"

    %define OUTBUF_SIZE 65536
    %define SYS_LSTAT 6

section .bss
    statbuf  resb 160
    fmt_ptr  resq 1
    cur_name resq 1
    fail     resq 1
    numtmp   resb 32
    outbuf   resb OUTBUF_SIZE
    outlen   resq 1

section .data
    digits db "0123456789abcdef"
usage_msg db "Usage: stat -c FORMAT FILE...", 10
    usage_len equ $ - usage_msg
err_stat db "stat: cannot stat file", 10
    err_stat_len equ $ - err_stat
    str_reg db "regular file", 0
    str_reg_empty db "regular empty file", 0
    str_dir db "directory", 0
    str_lnk db "symbolic link", 0
    str_chr db "character special file", 0
    str_blk db "block special file", 0
    str_fifo db "fifo", 0
    str_sock db "socket", 0
    str_unknown db "weird file", 0

section .text
global _start

_start:
    mov     qword [outlen], 0
    mov     qword [fail], 0
    pop     rax                         ;argc
    pop     rdi                         ;argv[0] discarded
    cmp     rax, 4
    jl      .usage
    pop     rsi                         ;argv[1] (must be -c)
    cmp     byte [rsi], '-'
    jne     .usage
    cmp     byte [rsi + 1], 'c'
    jne     .usage
    cmp     byte [rsi + 2], 0
    jne     .usage
    pop     rsi                         ;argv[2] = format
    mov     [fmt_ptr], rsi
    sub     rax, 3
    mov     r14, rax                    ;file count
    mov     r15, rsp                    ;&argv[3]
    xor     r12, r12                    ;file index
.file_loop:
    cmp     r12, r14
    jge     .done
    mov     rdi, [r15 + r12*8]
    mov     [cur_name], rdi
    mov     rax, SYS_LSTAT
    mov     rsi, statbuf
    syscall
    test    rax, rax
    js      .stat_err
    mov     r13, [fmt_ptr]
.scan:
    mov     al, [r13]
    test    al, al
    jz      .line_done
    cmp     al, '%'
    je      .directive
    call    out_char
    inc     r13
    jmp     .scan
.directive:
    inc     r13
    mov     al, [r13]
    test    al, al
    jz      .line_done
    cmp     al, 'n'
    je      .d_name
    cmp     al, 's'
    je      .d_size
    cmp     al, 'i'
    je      .d_ino
    cmp     al, 'h'
    je      .d_nlink
    cmp     al, 'u'
    je      .d_uid
    cmp     al, 'g'
    je      .d_gid
    cmp     al, 'd'
    je      .d_dev
    cmp     al, 'o'
    je      .d_blksize
    cmp     al, 'b'
    je      .d_blocks
    cmp     al, 'f'
    je      .d_rawmode
    cmp     al, 'a'
    je      .d_perms_oct
    cmp     al, 'A'
    je      .d_perms_sym
    cmp     al, 'F'
    je      .d_type
    cmp     al, '%'
    je      .d_pct
    mov     al, '%'
    call    out_char
    mov     al, [r13]
    call    out_char
    inc     r13
    jmp     .scan
.d_name:
    mov     rsi, [cur_name]
    call    emit_str
    inc     r13
    jmp     .scan
.d_size:
    mov     rdi, [statbuf + 48]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_ino:
    mov     rdi, [statbuf + 8]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_nlink:
    mov     rdi, [statbuf + 16]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_uid:
    mov     edi, [statbuf + 28]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_gid:
    mov     edi, [statbuf + 32]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_dev:
    mov     rdi, [statbuf + 0]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_blksize:
    mov     rdi, [statbuf + 56]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_blocks:
    mov     rdi, [statbuf + 64]
    mov     rsi, 10
    call    emit_base
    inc     r13
    jmp     .scan
.d_rawmode:
    movzx   rdi, word [statbuf + 24]
    mov     rsi, 16
    call    emit_base
    inc     r13
    jmp     .scan
.d_perms_oct:
    mov     edi, [statbuf + 24]
    and     edi, 0o7777
    mov     rsi, 8
    call    emit_base
    inc     r13
    jmp     .scan
.d_perms_sym:
    call    emit_perms
    inc     r13
    jmp     .scan
.d_type:
    call    emit_type
    inc     r13
    jmp     .scan
.d_pct:
    mov     al, '%'
    call    out_char
    inc     r13
    jmp     .scan
.line_done:
    mov     al, 10
    call    out_char
    inc     r12
    jmp     .file_loop
.stat_err:
    mov     qword [fail], 1
    push    r12
    push    r14
    push    r15
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, err_stat
    mov     rdx, err_stat_len
    syscall
    pop     r15
    pop     r14
    pop     r12
    inc     r12
    jmp     .file_loop
.done:
    call    out_flush
    mov     rdi, [fail]
    mov     rax, SYS_EXIT
    syscall
.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

; emit_base: rdi = value, rsi = base -> digits via out_char (register-safe)
emit_base:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rdi
    push    rsi
    mov     rax, rdi
    mov     rbx, rsi
    lea     rcx, [numtmp + 32]
    test    rax, rax
    jnz     .loop
    dec     rcx
    mov     byte [rcx], '0'
    jmp     .emit
.loop:
    xor     rdx, rdx
    div     rbx
    mov     dl, [digits + rdx]
    dec     rcx
    mov     [rcx], dl
    test    rax, rax
    jnz     .loop
.emit:
    lea     rdi, [numtmp + 32]
.eloop:
    cmp     rcx, rdi
    jge     .edone
    mov     al, [rcx]
    call    out_char
    inc     rcx
    jmp     .eloop
.edone:
    pop     rsi
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; emit_str: rsi = NUL-terminated string -> out_char (register-safe)
emit_str:
    push    rsi
.loop:
    mov     al, [rsi]
    test    al, al
    jz      .done
    call    out_char
    inc     rsi
    jmp     .loop
.done:
    pop     rsi
    ret

; emit_type: emit the %F file-type string from statbuf
emit_type:
    push    rsi
    mov     eax, [statbuf + 24]
    and     eax, 0o170000
    cmp     eax, 0o100000
    je      .reg
    cmp     eax, 0o040000
    je      .dir
    cmp     eax, 0o120000
    je      .lnk
    cmp     eax, 0o020000
    je      .chr
    cmp     eax, 0o060000
    je      .blk
    cmp     eax, 0o010000
    je      .fifo
    cmp     eax, 0o140000
    je      .sock
    mov     rsi, str_unknown
    jmp     .out
.reg:
    mov     rax, [statbuf + 48]
    test    rax, rax
    jnz     .reg_ne
    mov     rsi, str_reg_empty
    jmp     .out
.reg_ne:
    mov     rsi, str_reg
    jmp     .out
.dir:
    mov     rsi, str_dir
    jmp     .out
.lnk:
    mov     rsi, str_lnk
    jmp     .out
.chr:
    mov     rsi, str_chr
    jmp     .out
.blk:
    mov     rsi, str_blk
    jmp     .out
.fifo:
    mov     rsi, str_fifo
    jmp     .out
.sock:
    mov     rsi, str_sock
.out:
    call    emit_str
    pop     rsi
    ret

; emit_perms: emit the 10-character %A symbolic permissions
emit_perms:
    push    rbx
    mov     ebx, [statbuf + 24]
    mov     eax, ebx
    and     eax, 0o170000
    cmp     eax, 0o040000
    je      .t_dir
    cmp     eax, 0o120000
    je      .t_lnk
    cmp     eax, 0o020000
    je      .t_chr
    cmp     eax, 0o060000
    je      .t_blk
    cmp     eax, 0o010000
    je      .t_fifo
    cmp     eax, 0o140000
    je      .t_sock
    mov     al, '-'
    jmp     .t_emit
.t_dir:
    mov     al, 'd'
    jmp     .t_emit
.t_lnk:
    mov     al, 'l'
    jmp     .t_emit
.t_chr:
    mov     al, 'c'
    jmp     .t_emit
.t_blk:
    mov     al, 'b'
    jmp     .t_emit
.t_fifo:
    mov     al, 'p'
    jmp     .t_emit
.t_sock:
    mov     al, 's'
.t_emit:
    call    out_char

    mov     al, '-'
    test    ebx, 0o400
    jz      .ur
    mov     al, 'r'
.ur:
    call    out_char
    mov     al, '-'
    test    ebx, 0o200
    jz      .uw
    mov     al, 'w'
.uw:
    call    out_char
    test    ebx, 0o4000
    jnz     .ux_suid
    mov     al, '-'
    test    ebx, 0o100
    jz      .ux_emit
    mov     al, 'x'
    jmp     .ux_emit
.ux_suid:
    mov     al, 'S'
    test    ebx, 0o100
    jz      .ux_emit
    mov     al, 's'
.ux_emit:
    call    out_char

    mov     al, '-'
    test    ebx, 0o40
    jz      .gr
    mov     al, 'r'
.gr:
    call    out_char
    mov     al, '-'
    test    ebx, 0o20
    jz      .gw
    mov     al, 'w'
.gw:
    call    out_char
    test    ebx, 0o2000
    jnz     .gx_sgid
    mov     al, '-'
    test    ebx, 0o10
    jz      .gx_emit
    mov     al, 'x'
    jmp     .gx_emit
.gx_sgid:
    mov     al, 'S'
    test    ebx, 0o10
    jz      .gx_emit
    mov     al, 's'
.gx_emit:
    call    out_char

    mov     al, '-'
    test    ebx, 0o4
    jz      .or
    mov     al, 'r'
.or:
    call    out_char
    mov     al, '-'
    test    ebx, 0o2
    jz      .ow
    mov     al, 'w'
.ow:
    call    out_char
    test    ebx, 0o1000
    jnz     .ox_sticky
    mov     al, '-'
    test    ebx, 0o1
    jz      .ox_emit
    mov     al, 'x'
    jmp     .ox_emit
.ox_sticky:
    mov     al, 'T'
    test    ebx, 0o1
    jz      .ox_emit
    mov     al, 't'
.ox_emit:
    call    out_char
    pop     rbx
    ret

out_char:
    push    rdx
    mov     rdx, [outlen]
    cmp     rdx, OUTBUF_SIZE
    jl      .store
    call    out_flush
    xor     rdx, rdx
.store:
    mov     [outbuf + rdx], al
    inc     rdx
    mov     [outlen], rdx
    pop     rdx
    ret

out_flush:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r11
    mov     rdx, [outlen]
    test    rdx, rdx
    jz      .empty
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, outbuf
    syscall
    mov     qword [outlen], 0
.empty:
    pop     r11
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret
