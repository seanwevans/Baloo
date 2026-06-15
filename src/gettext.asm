; src/gettext.asm
;
; Minimal gettext runtime.  It prints MSGID translated through a GNU .mo
; catalog when one can be found, falling back to MSGID when the catalog or
; entry is absent.
;
; Supported usage:
;   gettext [-d DOMAIN] MSGID
;   gettext [DOMAIN] MSGID
;
; The catalog path is TEXTDOMAINDIR (default: /usr/share/locale), the active
; locale from LC_ALL/LC_MESSAGES/LANG (default: C), and the domain from -d,
; TEXTDOMAIN, or "messages":
;   $TEXTDOMAINDIR/$locale/LC_MESSAGES/$domain.mo

    %include "include/sysdefs.inc"

    %define MO_CAP   1048576
    %define PATH_CAP 4096

section .bss
    mobuf       resb MO_CAP
    pathbuf     resb PATH_CAP
    mo_size     resq 1
    msgid_ptr   resq 1
    msgid_len   resq 1
    domain_ptr  resq 1
    envp_ptr    resq 1

section .data
    newline         db WHITESPACE_NL
    slash           db "/", 0
    lc_messages     db "/LC_MESSAGES/", 0
    dot_mo          db ".mo", 0
    default_domain  db "messages", 0
    default_dir     db "/usr/share/locale", 0
    c_locale        db "C", 0
    textdomain_eq   db "TEXTDOMAIN=", 0
    textdomaindir_eq db "TEXTDOMAINDIR=", 0
    lcall_eq        db "LC_ALL=", 0
    lcmessages_eq   db "LC_MESSAGES=", 0
    lang_eq         db "LANG=", 0

section .text
global _start

_start:
    pop     rbx                         ;argc
    mov     r12, rsp                    ;argv
    lea     r13, [rsp + rbx*8 + 8]      ;envp (after argv NULL)
    mov     [envp_ptr], r13

    mov     qword [domain_ptr], 0
    mov     qword [msgid_ptr], 0

    mov     rcx, 1
.parse_args:
    cmp     rcx, rbx
    jae     .args_done
    mov     rsi, [r12 + rcx*8]
    cmp     byte [rsi], '-'
    jne     .operand
    cmp     byte [rsi + 1], 'd'
    jne     .fallback_operand
    cmp     byte [rsi + 2], 0
    jne     .domain_attached
    inc     rcx
    cmp     rcx, rbx
    jae     .args_done
    mov     rax, [r12 + rcx*8]
    mov     [domain_ptr], rax
    inc     rcx
    jmp     .parse_args
.domain_attached:
    lea     rax, [rsi + 2]
    mov     [domain_ptr], rax
    inc     rcx
    jmp     .parse_args
.fallback_operand:
.operand:
    mov     rax, [msgid_ptr]
    test    rax, rax
    jz      .first_operand
; POSIX form: gettext DOMAIN MSGID.  A second operand becomes MSGID and
; the first one becomes DOMAIN unless -d already provided a domain.
    cmp     qword [domain_ptr], 0
    jne     .replace_msgid
    mov     [domain_ptr], rax
.replace_msgid:
    mov     [msgid_ptr], rsi
    inc     rcx
    jmp     .parse_args
.first_operand:
    mov     [msgid_ptr], rsi
    inc     rcx
    jmp     .parse_args

.args_done:
    cmp     qword [msgid_ptr], 0
    je      .print_nl

    cmp     qword [domain_ptr], 0
    jne     .have_domain
    mov     rdi, textdomain_eq
    mov     rsi, [envp_ptr]
    call    __find_env
    test    rax, rax
    jnz     .set_domain
    mov     rax, default_domain
.set_domain:
    mov     [domain_ptr], rax
.have_domain:
    mov     rsi, [msgid_ptr]
    call    strlen
    mov     [msgid_len], rbx

    call    build_path
    call    load_catalog
    test    rax, rax
    jz      .fallback
    call    find_translation
    test    rax, rax
    jz      .fallback
    mov     rsi, rax
    mov     rdx, rbx
    write   STDOUT_FILENO, rsi, rdx
    jmp     .print_nl

.fallback:
    mov     rsi, [msgid_ptr]
    mov     rdx, [msgid_len]
    write   STDOUT_FILENO, rsi, rdx
.print_nl:
    write   STDOUT_FILENO, newline, 1
    exit    0

; pathbuf = dir / locale / LC_MESSAGES / domain .mo
build_path:
    mov     rdi, textdomaindir_eq
    mov     rsi, [envp_ptr]
    call    __find_env
    test    rax, rax
    jnz     .dir
    mov     rax, default_dir
.dir:
    mov     rdi, pathbuf
    mov     rsi, rax
    call    append_cstr
    mov     rsi, slash
    call    append_cstr

    push    rdi
    call    get_locale
    pop     rdi
    mov     rsi, rax
    call    append_locale
    mov     rsi, lc_messages
    call    append_cstr
    mov     rsi, [domain_ptr]
    call    append_cstr
    mov     rsi, dot_mo
    call    append_cstr
    mov     byte [rdi], 0
    ret

get_locale:
    mov     rdi, lcall_eq
    mov     rsi, [envp_ptr]
    call    __find_env
    call    usable_locale
    test    rax, rax
    jnz     .done
    mov     rdi, lcmessages_eq
    mov     rsi, [envp_ptr]
    call    __find_env
    call    usable_locale
    test    rax, rax
    jnz     .done
    mov     rdi, lang_eq
    mov     rsi, [envp_ptr]
    call    __find_env
    call    usable_locale
    test    rax, rax
    jnz     .done
    mov     rax, c_locale
.done:
    ret

usable_locale:
    test    rax, rax
    jz      .bad
    cmp     byte [rax], 0
    je      .bad
    ret
.bad:
    xor     rax, rax
    ret

append_cstr:
    mov     al, [rsi]
    test    al, al
    jz      .done
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     append_cstr
.done:
    ret

; append locale until NUL, '.', or '@' (en_US.UTF-8 -> en_US)
append_locale:
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     al, '.'
    je      .done
    cmp     al, '@'
    je      .done
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     append_locale
.done:
    ret

load_catalog:
    mov     rax, SYS_OPEN
    mov     rdi, pathbuf
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fail
    mov     r9, rax
    mov     rdi, r9
    mov     rsi, mobuf
    mov     rdx, MO_CAP
    call    slurp
    mov     [mo_size], rax
    mov     rax, SYS_CLOSE
    mov     rdi, r9
    syscall
    cmp     qword [mo_size], 28
    jb      .fail
    cmp     dword [mobuf], 0x950412de
    jne     .fail
    mov     rax, 1
    ret
.fail:
    xor     rax, rax
    ret

; returns rax=translation pointer and rbx=length, or rax=0
find_translation:
    mov     r14d, [mobuf + 8]           ;number of strings
    mov     r15d, [mobuf + 12]          ;original table offset
    mov     r13d, [mobuf + 16]          ;translation table offset
    xor     rcx, rcx
.loop:
    cmp     rcx, r14
    jae     .none
    mov     eax, [mobuf + r15 + rcx*8]  ;orig len
    cmp     rax, [msgid_len]
    jne     .next
    mov     edx, [mobuf + r15 + rcx*8 + 4] ;orig off
    lea     rsi, [mobuf + rdx]
    mov     rdi, [msgid_ptr]
    mov     rdx, [msgid_len]
    push    rcx
    call    memeq
    pop     rcx
    test    rax, rax
    jz      .next
    mov     ebx, [mobuf + r13 + rcx*8]  ;trans len
    mov     eax, [mobuf + r13 + rcx*8 + 4] ;trans off
    lea     rax, [mobuf + rax]
    ret
.next:
    inc     rcx
    jmp     .loop
.none:
    xor     rax, rax
    ret

memeq:
    test    rdx, rdx
    jz      .yes
.l:
    mov     al, [rsi]
    cmp     al, [rdi]
    jne     .no
    inc     rsi
    inc     rdi
    dec     rdx
    jnz     .l
.yes:
    mov     rax, 1
    ret
.no:
    xor     rax, rax
    ret

slurp:
    mov     r10, rsi
    mov     r11, rdx
    xor     r9, r9
.rd:
    mov     rdx, r11
    sub     rdx, r9
    jz      .done
    mov     rax, SYS_READ
    mov     rsi, r10
    add     rsi, r9
    syscall
    test    rax, rax
    jle     .done
    add     r9, rax
    jmp     .rd
.done:
    mov     rax, r9
    ret
