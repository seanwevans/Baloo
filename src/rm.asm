; src/rm.asm -- rm(1): remove files and directories.
; Usage: rm [-fiRrv] FILE...
;
; A name is taken away from the directory it is in, which is all that
; removing a file is. A directory has to be emptied first, so -r walks it
; depth first and takes each name away before the directory that held it.
;
; POSIX asks for a prompt before removing something the user cannot write to,
; but only when someone is there to answer, so the prompt appears when the
; input is a terminal or when -i asks for it outright. -f is the opposite: it
; asks nothing and is not troubled by a name that was never there.

    %include "include/sysdefs.inc"

    %define SYS_LSTAT_ID 6
    %define SYS_GETDENTS_ID 217
    %define SYS_UNLINKAT_ID 263
    %define SYS_FACCESSAT_ID 269
    %define SYS_IOCTL_ID 16

    %define AT_FDCWD -100
    %define AT_REMOVEDIR 0x200
    %define W_OK 2
    %define R_OK 4
    %define S_IFMT 0xF000
    %define S_IFDIR 0x4000
    %define S_IFLNK 0xA000
    %define ST_MODE_OFF 24

    %define PATHCAP 4096
    %define DIRCAP 32768
    %define MAXDEPTH 64
    %define OUTCAP 16384

section .bss
    pathbuf     resb PATHCAP
    pathlen     resq 1
    dirbufs     resb MAXDEPTH * DIRCAP
    depth       resq 1
    childfail   resb MAXDEPTH + 1
    stbuf       resb 160
    outbuf      resb OUTCAP
    outlen      resq 1
    answerbuf   resb 256
    opt_f       resb 1
    opt_i       resb 1
    opt_r       resb 1
    opt_v       resb 1
    exitcode    resq 1
    stdin_tty   resb 1

section .data
e_usage     db "usage: rm [-fiRrv] FILE...", 10
    e_usage_len equ $ - e_usage
e_prefix    db "rm: "
    e_prefix_l  equ $ - e_prefix
e_slash     db "rm: rm /. if you mean it", 10
    e_slash_l   equ $ - e_slash
e_badpath   db "rm: bad path "
    e_badpath_l equ $ - e_badpath
e_cannot    db ": cannot remove", 10
    e_cannot_l  equ $ - e_cannot
e_generic   db ": cannot remove", 10, 0
e_noent     db ": No such file or directory", 10, 0
e_isdir     db ": Is a directory", 10, 0
e_notempty  db ": Directory not empty", 10, 0
e_denied    db ": Permission denied", 10, 0
e_perm      db ": Operation not permitted", 10, 0
    p_rm        db "rm ", 0
    p_rmdir     db "rmdir ", 0
    p_ro        db "ro ", 0
    p_dir       db "dir ", 0
    v_rm        db "rm '", 0
    v_rmdir     db "rmdir '", 0
    v_close     db "'", 10, 0
    s_dotdot    db "..", 0
    s_slash     db "/", 0

section .text
global _start

_start:
    mov     r14, [rsp]                  ;argc
    lea     r15, [rsp + 8]              ;argv
    mov     r13, 1
    xor     r12, r12                    ;names seen
.flags:
    cmp     r13, r14
    jae     .checked
    mov     rbx, [r15 + r13 * 8]
    cmp     byte [rbx], '-'
    jne     .isname
    cmp     byte [rbx + 1], 0
    je      .isname
    cmp     byte [rbx + 1], '-'
    je      .longflag
    inc     rbx
.letter:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .nextflag
    inc     rbx
    cmp     al, 'f'
    je      .f_f
    cmp     al, 'i'
    je      .f_i
    cmp     al, 'r'
    je      .f_r
    cmp     al, 'R'
    je      .f_r
    cmp     al, 'v'
    je      .f_v
    jmp     usage_error
.f_f:
    mov     byte [opt_f], 1
    mov     byte [opt_i], 0
    jmp     .letter
.f_i:
    mov     byte [opt_i], 1
    mov     byte [opt_f], 0
    jmp     .letter
.f_r:
    mov     byte [opt_r], 1
    jmp     .letter
.f_v:
    mov     byte [opt_v], 1
    jmp     .letter
.longflag:
    mov     rdi, rbx
    call    is_force_word
    test    al, al
    jz      usage_error
    mov     byte [opt_f], 1
    mov     byte [opt_i], 0
    jmp     .nextflag
.isname:
    inc     r12
.nextflag:
    inc     r13
    jmp     .flags

.checked:
    test    r12, r12
    jnz     .work
    cmp     byte [opt_f], 0
    jne     .done
    jmp     usage_error
.work:
    call    check_tty
    mov     r13, 1
.name:
    cmp     r13, r14
    jae     .done
    mov     rbx, [r15 + r13 * 8]
    cmp     byte [rbx], '-'
    jne     .remove
    cmp     byte [rbx + 1], 0
    jne     .nextname
.remove:
    mov     rdi, rbx
    call    remove_operand
.nextname:
    inc     r13
    jmp     .name
.done:
    call    out_flush
    mov     rdi, [exitcode]
    mov     rax, SYS_EXIT
    syscall

is_force_word:
    mov     rsi, w_force
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rsi + rcx]
    cmp     al, [rdi + rcx]
    jne     .no
    test    al, al
    jz      .yes
    inc     rcx
    jmp     .byte
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

usage_error:
    call    out_flush
    write   STDERR_FILENO, e_usage, e_usage_len
    exit    1

; ---------------------------------------------------------------------------
; remove_operand: one name from the command line, with the two that POSIX
; says to refuse outright.
; ---------------------------------------------------------------------------
remove_operand:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rbx
    mov     rsi, s_slash
    call    same_string
    test    al, al
    jz      .notroot
    call    out_flush
    write   STDERR_FILENO, e_slash, e_slash_l
    mov     qword [exitcode], 1
    jmp     .out
.notroot:
    mov     rdi, rbx
    call    base_name
    mov     rdi, rax
    mov     rsi, s_dotdot
    call    same_string
    test    al, al
    jz      .allowed
    call    out_flush
    write   STDERR_FILENO, e_badpath, e_badpath_l
    mov     rdi, rbx
    call    err_line
    mov     qword [exitcode], 1
    jmp     .out
.allowed:
    cmp     byte [opt_f], 0
    je      .start
    mov     rax, SYS_LSTAT_ID
    mov     rdi, rbx
    mov     rsi, stbuf
    syscall
    test    rax, rax
    js      .out                        ;-f is not troubled by what is not there
.start:
    mov     rdi, rbx
    call    path_set
    mov     qword [depth], 0
    mov     byte [childfail], 0
    call    remove_path
.out:
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; remove_path: whatever pathbuf names. A directory is emptied first.
; ---------------------------------------------------------------------------
remove_path:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    xor     r15, r15                    ;whether a directory is being removed
    mov     rax, SYS_LSTAT_ID
    mov     rdi, pathbuf
    mov     rsi, stbuf
    syscall
    test    rax, rax
    js      .unlinkanyway
    mov     eax, [stbuf + ST_MODE_OFF]
    mov     r12d, eax
    and     eax, S_IFMT
    cmp     eax, S_IFDIR
    je      .directory
    xor     r13, r13                    ;this is not a directory
    jmp     .prompt
.unlinkanyway:
    xor     r12, r12
    xor     r13, r13
    jmp     .takeaway
.directory:
    mov     r13, 1
    cmp     byte [opt_r], 0
    je      .takeaway                   ;without -r even an empty one is refused
    mov     r15, 1
    jmp     .prompt
.prompt:
    xor     r14, r14                    ;whether the file is one to ask about
    cmp     byte [opt_f], 0
    jne     .asked
    mov     eax, r12d
    and     eax, S_IFMT
    cmp     eax, S_IFLNK
    je      .asked
    mov     rax, SYS_FACCESSAT_ID
    mov     rdi, AT_FDCWD
    mov     rsi, pathbuf
    mov     rdx, W_OK
    xor     r10, r10
    syscall
    test    rax, rax
    jns     .asked
    mov     r14, 1
.asked:
    cmp     byte [opt_i], 0
    jne     .doask
    test    r14, r14
    jz      .descend
    cmp     byte [stdin_tty], 0
    je      .descend
.doask:
    mov     rdi, p_rm
    call    err_str
    test    r14, r14
    jz      .nodirword
    mov     rdi, p_ro
    call    err_str
.nodirword:
    test    r13, r13
    jz      .nodirtag
    mov     rdi, p_dir
    call    err_str
.nodirtag:
    mov     rdi, pathbuf
    call    err_str
    call    read_answer
    test    al, al
    jnz     .descend
    call    mark_parent
    jmp     .out
.descend:
    test    r13, r13
    jz      .takeaway
    call    empty_directory
    cmp     byte [opt_i], 0
    je      .takeaway
    mov     rdi, p_rmdir
    call    err_str
    mov     rdi, pathbuf
    call    err_str
    call    read_answer
    test    al, al
    jnz     .takeaway
    call    mark_parent
    jmp     .out
.takeaway:
    mov     rax, SYS_UNLINKAT_ID
    mov     rdi, AT_FDCWD
    mov     rsi, pathbuf
    xor     rdx, rdx
    test    r15, r15
    jz      .unlinkcall
    mov     rdx, AT_REMOVEDIR
.unlinkcall:
    syscall
    test    rax, rax
    js      .failed
    cmp     byte [opt_v], 0
    je      .out
    mov     rdi, v_rm
    test    r13, r13
    jz      .verbword
    mov     rdi, v_rmdir
.verbword:
    call    out_str
    mov     rdi, pathbuf
    call    out_str
    mov     rdi, v_close
    call    out_str
    jmp     .out
.failed:
    mov     r14, rax                    ;why it did not happen
; a directory that could not be emptied has already been complained about
    test    r13, r13
    jz      .complain
    mov     rax, [depth]
    cmp     byte [childfail + rax], 0
    jne     .quietfail
.complain:
    call    out_flush
    write   STDERR_FILENO, e_prefix, e_prefix_l
    mov     rdi, pathbuf
    call    err_bytes_nonl
    mov     rdi, r14
    neg     rdi
    call    err_reason
    mov     qword [exitcode], 1
.quietfail:
    call    mark_parent
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; mark_parent: tell the level above that something under it stayed.
mark_parent:
    mov     rax, [depth]
    test    rax, rax
    jz      .out
    dec     rax
    mov     byte [childfail + rax], 1
.out:
    ret

; ---------------------------------------------------------------------------
; empty_directory: every name inside pathbuf, taken away before it is.
; ---------------------------------------------------------------------------
empty_directory:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rax, [depth]
    cmp     rax, MAXDEPTH - 1
    jae     .out
    cmp     byte [opt_f], 0
    je      .open
    mov     rax, SYS_FACCESSAT_ID
    mov     rdi, AT_FDCWD
    mov     rsi, pathbuf
    mov     rdx, R_OK
    xor     r10, r10
    syscall
    test    rax, rax
    jns     .open
    mov     rax, SYS_CHMOD
    mov     rdi, pathbuf
    mov     rsi, 0o700
    syscall
.open:
    mov     rax, SYS_OPEN
    mov     rdi, pathbuf
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .out
    mov     r15, rax
    mov     r14, [pathlen]
    mov     rax, [depth]
    inc     rax
    mov     [depth], rax
    mov     byte [childfail + rax], 0
    imul    r13, rax, DIRCAP
    add     r13, dirbufs
.chunk:
    mov     rax, SYS_GETDENTS_ID
    mov     rdi, r15
    mov     rsi, r13
    mov     rdx, DIRCAP
    syscall
    test    rax, rax
    jle     .closedir
    mov     r12, rax
    xor     rbx, rbx
.entry:
    cmp     rbx, r12
    jae     .chunk
    lea     rdi, [r13 + rbx + 19]
    call    is_dot_name
    test    al, al
    jnz     .nextentry
    mov     rdi, r14
    lea     rsi, [r13 + rbx + 19]
    call    path_join
    push    rbx
    call    remove_path
    pop     rbx
.nextentry:
    movzx   eax, word [r13 + rbx + 16]
    add     rbx, rax
    jmp     .entry
.closedir:
    mov     rax, SYS_CLOSE
    mov     rdi, r15
    syscall
    mov     rax, [depth]
    mov     cl, [childfail + rax]
    dec     rax
    mov     [depth], rax
    test    cl, cl
    jz      .restore
    mov     byte [childfail + rax], 1
.restore:
    mov     [pathlen], r14
    mov     byte [pathbuf + r14], 0
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

is_dot_name:
    cmp     byte [rdi], '.'
    jne     .no
    cmp     byte [rdi + 1], 0
    je      .yes
    cmp     byte [rdi + 1], '.'
    jne     .no
    cmp     byte [rdi + 2], 0
    je      .yes
.no:
    xor     al, al
    ret
.yes:
    mov     al, 1
    ret

; ---------------------------------------------------------------------------
; Paths.
; ---------------------------------------------------------------------------
path_set:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rdi + rcx]
    mov     [pathbuf + rcx], al
    test    al, al
    jz      .done
    inc     rcx
    jmp     .byte
.done:
; a trailing slash is not part of the name
.trim:
    cmp     rcx, 1
    jbe     .store
    cmp     byte [pathbuf + rcx - 1], '/'
    jne     .store
    dec     rcx
    mov     byte [pathbuf + rcx], 0
    jmp     .trim
.store:
    mov     [pathlen], rcx
    ret

; path_join: pathbuf, rdi long, gains a slash and the name rsi.
path_join:
    mov     byte [pathbuf + rdi], '/'
    inc     rdi
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rsi + rcx]
    mov     [pathbuf + rdi + rcx], al
    test    al, al
    jz      .done
    inc     rcx
    jmp     .byte
.done:
    add     rdi, rcx
    mov     [pathlen], rdi
    ret

base_name:
    mov     rax, rdi
    mov     rcx, rdi
.byte:
    movzx   edx, byte [rcx]
    test    dl, dl
    jz      .out
    cmp     dl, '/'
    jne     .step
    lea     rax, [rcx + 1]
.step:
    inc     rcx
    jmp     .byte
.out:
    ret

same_string:
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rdi + rcx]
    cmp     al, [rsi + rcx]
    jne     .no
    test    al, al
    jz      .yes
    inc     rcx
    jmp     .byte
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

strlen_of:
    xor     rax, rax
.byte:
    cmp     byte [rdi + rax], 0
    je      .out
    inc     rax
    jmp     .byte
.out:
    ret

; ---------------------------------------------------------------------------
; Asking, and answering.
; ---------------------------------------------------------------------------
check_tty:
    mov     rax, SYS_IOCTL_ID
    mov     rdi, STDIN_FILENO
    mov     rsi, 0x5401                 ;TCGETS
    mov     rdx, stbuf
    syscall
    test    rax, rax
    jnz     .no
    mov     byte [stdin_tty], 1
.no:
    ret

; read_answer: al = 1 when the line read begins with a y.
read_answer:
    push    rbx
    call    out_flush
    mov     rax, SYS_READ
    mov     rdi, STDIN_FILENO
    mov     rsi, answerbuf
    mov     rdx, 255
    syscall
    test    rax, rax
    jle     .no
    movzx   eax, byte [answerbuf]
    cmp     al, 'y'
    je      .yes
    cmp     al, 'Y'
    je      .yes
.no:
    xor     al, al
    pop     rbx
    ret
.yes:
    mov     al, 1
    pop     rbx
    ret

; err_reason: why the removal did not happen, from the error number rdi.
err_reason:
    push    rbx
    mov     rbx, e_generic
    cmp     rdi, 2
    je      .noent
    cmp     rdi, 21
    je      .isdir
    cmp     rdi, 39
    je      .notempty
    cmp     rdi, 13
    je      .denied
    cmp     rdi, 1
    je      .perm
    jmp     .say
.noent:
    mov     rbx, e_noent
    jmp     .say
.isdir:
    mov     rbx, e_isdir
    jmp     .say
.notempty:
    mov     rbx, e_notempty
    jmp     .say
.denied:
    mov     rbx, e_denied
    jmp     .say
.perm:
    mov     rbx, e_perm
.say:
    mov     rdi, rbx
    call    err_bytes_nonl
    pop     rbx
    ret

err_str:
    push    rbx
    push    r12
    mov     rbx, rdi
    call    strlen_of
    mov     r12, rax
    call    out_flush
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, rbx
    mov     rdx, r12
    syscall
    pop     r12
    pop     rbx
    ret

err_bytes_nonl:
    push    rbx
    push    r12
    mov     rbx, rdi
    call    strlen_of
    mov     r12, rax
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, rbx
    mov     rdx, r12
    syscall
    pop     r12
    pop     rbx
    ret

err_line:
    push    rbx
    call    err_bytes_nonl
    mov     byte [answerbuf], WHITESPACE_NL
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, answerbuf
    mov     rdx, 1
    syscall
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Output, buffered so that -v does not write a line at a time.
; ---------------------------------------------------------------------------
out_char:
    push    rcx
    mov     rcx, [outlen]
    mov     [outbuf + rcx], al
    inc     rcx
    mov     [outlen], rcx
    cmp     rcx, OUTCAP - 16
    jb      .out
    call    out_flush
.out:
    pop     rcx
    ret

out_str:
    push    rbx
    mov     rbx, rdi
.byte:
    mov     al, [rbx]
    test    al, al
    jz      .out
    call    out_char
    inc     rbx
    jmp     .byte
.out:
    pop     rbx
    ret

out_flush:
    push    rcx
    push    rdi
    push    rsi
    push    rdx
    mov     rdx, [outlen]
    test    rdx, rdx
    jz      .out
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, outbuf
    syscall
    mov     qword [outlen], 0
.out:
    pop     rdx
    pop     rsi
    pop     rdi
    pop     rcx
    ret

section .data
    w_force     db "--force", 0
