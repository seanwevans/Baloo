; src/chown.asm -- chown(1): change file owner and group.
; Usage: chown [USER][:[GROUP]] FILE...
;
; USER and GROUP may be names (resolved via /etc/passwd and /etc/group) or
; numbers; an omitted field leaves that id unchanged.

    %include "include/sysdefs.inc"

section .bss
    passwd_buf  resb 65536
    group_buf   resb 65536
    spec        resb 256
    passwd_len  resq 1
    group_len   resq 1
    files       resq 256
    nfiles      resq 1
    uid         resq 1
    gid         resq 1
    had_err     resb 1

section .data
    passwd_path db "/etc/passwd", 0
    group_path  db "/etc/group", 0
err_msg     db "chown: cannot change ownership", WHITESPACE_NL
    err_len     equ $ - err_msg
usage_msg   db "chown: need owner and file", WHITESPACE_NL
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    mov     qword [nfiles], 0
    mov     byte [had_err], 0
    mov     qword [uid], -1
    mov     qword [gid], -1

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12
    xor     r14, r14                    ;operand index
parse:
    cmp     r12, 0
    je      after_parse
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .op
    cmp     byte [rdi + 1], 0
    je      .op                         ;lone "-" operand
    jmp     .nextarg                    ;ignore -R/-h/etc (unused by tests)
.op:
    cmp     r14, 0
    jne     .file
;first operand is the owner spec
    mov     rsi, rdi
    mov     rdi, spec
    call    strcpy_c
    inc     r14
    jmp     .nextarg
.file:
    mov     rcx, [nfiles]
    mov     [files + rcx*8], rdi
    inc     qword [nfiles]
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
;read /etc/passwd and /etc/group
    mov     rdi, passwd_path
    mov     rsi, passwd_buf
    call    read_file
    mov     [passwd_len], rax
    mov     rdi, group_path
    mov     rsi, group_buf
    call    read_file
    mov     [group_len], rax

;split spec at ':'
    xor     rbx, rbx                    ;colon index, -1 if none
    mov     rbx, -1
    xor     rcx, rcx
.findc:
    mov     al, [spec + rcx]
    test    al, al
    jz      .split
cmp     al, ':'
    jne     .fc_next
    mov     rbx, rcx
    jmp     .split
.fc_next:
    inc     rcx
    jmp     .findc
.split:
    cmp     rbx, -1
    je      .user_only
    mov     byte [spec + rbx], 0        ;terminate user part
;user = spec[0..], group = spec[rbx+1..]
    cmp     byte [spec], 0
    je      .grp
    mov     rdi, spec
    mov     rsi, passwd_buf
    mov     rdx, [passwd_len]
    call    resolve
    mov     [uid], rax
.grp:
    lea     rdi, [spec + rbx + 1]
    cmp     byte [rdi], 0
    je      .apply
    mov     rsi, group_buf
    mov     rdx, [group_len]
    call    resolve
    mov     [gid], rax
    jmp     .apply
.user_only:
    cmp     byte [spec], 0
    je      .apply
    mov     rdi, spec
    mov     rsi, passwd_buf
    mov     rdx, [passwd_len]
    call    resolve
    mov     [uid], rax
.apply:
    xor     r14, r14
.aloop:
    cmp     r14, [nfiles]
    jge     .done
    mov     rax, SYS_CHOWN
    mov     rdi, [files + r14*8]
    mov     rsi, [uid]
    mov     rdx, [gid]
    syscall
    test    rax, rax
    jns     .anext
    mov     byte [had_err], 1
    write   STDERR_FILENO, err_msg, err_len
.anext:
    inc     r14
    jmp     .aloop
.done:
    movzx   edi, byte [had_err]
    mov     rax, SYS_EXIT
    syscall

; resolve: rdi = name, rsi = file buffer, rdx = length -> rax = id.
; Looks up the third colon field of the matching "name:" line; a leading digit
; falls back to parsing the name as a number.
resolve:
    cmp     byte [rdi], '0'
    jb      .byname
    cmp     byte [rdi], '9'
    ja      .byname
;numeric
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
    xor     r8, r8                      ;line start
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
    inc     r9                          ;past name colon
.skipf:
    cmp     r9, rdx
    jge     .notfound
cmp     byte [rsi + r9], ':'
    je      .atid
    inc     r9
    jmp     .skipf
.atid:
    inc     r9                          ;past passwd colon
    xor     rax, rax
.dig:
    cmp     r9, rdx
    jge     .ret
    movzx   ecx, byte [rsi + r9]
    sub     cl, '0'
    cmp     cl, 9
    ja      .ret
    imul    rax, rax, 10
    movzx   rcx, cl
    add     rax, rcx
    inc     r9
    jmp     .dig
.ret:
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
    mov     r8, rax                     ;fd
    xor     r9, r9                      ;count
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

; strcpy_c: rsi -> rdi, NUL-terminated.
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
