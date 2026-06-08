; src/tput.asm
;
; tput - query terminal capabilities.
;
; Supported capabilities
;   tput cols     number of columns
;   tput lines    number of rows
;
; The value is resolved the way ncurses does, in this precedence order
; (after validating $TERM):
;   1. the COLUMNS / LINES environment variable, when set to a positive
;      integer
;   2. the live window size from TIOCGWINSZ on standard output, when it is
;      a terminal reporting a non-zero size
;   3. the static numeric capability from the terminfo database entry for
;      $TERM, falling back to 80 columns / 24 lines
;
; The terminfo entry is parsed directly from the compiled database (both
; the legacy 16-bit and the 32-bit number formats are understood). Other
; capabilities and the parameterized string operations are out of scope.

    %include "include/sysdefs.inc"

    %define TIOCGWINSZ 0x5413
    %define TI_MAGIC16 0x011A
    %define TI_MAGIC32 0x021E

section .bss
    ti_buf      resb 8192               ;compiled terminfo entry
    pathbuf     resb 4096               ;assembled database path
    winsz       resw 4                  ;struct winsize
    numbuf      resb 32                 ;decimal conversion scratch
    cap_ptr     resq 1                  ;requested capability name
    term_ptr    resq 1                  ;value of $TERM
    envp_ptr    resq 1                  ;environment pointer
    ti_cols     resq 1                  ;terminfo columns, or -1 when absent
    ti_lines    resq 1                  ;terminfo lines, or -1 when absent

section .data
    term_prefix     db "TERM=", 0
    columns_prefix  db "COLUMNS=", 0
    lines_prefix    db "LINES=", 0
    terminfo_prefix db "TERMINFO=", 0
    cap_cols        db "cols", 0
    cap_lines       db "lines", 0
    dir_etc         db "/etc/terminfo", 0
    dir_usr         db "/usr/share/terminfo", 0
    dir_lib         db "/lib/terminfo", 0
usage_msg       db "Usage: tput [options] [command]", 10
    usage_len       equ $ - usage_msg
noterm_msg      db "tput: No value for $TERM and no -T specified", 10
    noterm_len      equ $ - noterm_msg
err_unk_pre     db 'tput: unknown terminal "'
    err_unk_pre_len equ $ - err_unk_pre
    err_unk_post    db '"', 10
    err_unk_post_len equ $ - err_unk_post
err_cap_pre     db "tput: unknown terminfo capability '"
    err_cap_pre_len equ $ - err_cap_pre
    err_cap_post    db "'", 10
    err_cap_post_len equ $ - err_cap_post

section .text
global _start

_start:
    pop     rbx                         ;argc
    mov     r12, rsp                    ;argv pointer
    lea     r13, [r12 + rbx*8 + 8]      ;envp pointer
    mov     [envp_ptr], r13

    cmp     rbx, 2
    jl      no_args                     ;tput with no capability

    mov     rax, [r12 + 8]
    mov     [cap_ptr], rax              ;argv[1] is the capability name

; validate $TERM before anything else, matching setupterm
    mov     rdi, term_prefix
    mov     rsi, r13
    call    __find_env
    test    rax, rax
    jz      no_term
    mov     [term_ptr], rax

    call    open_terminfo               ;exits via unknown_terminal on failure
    call    parse_terminfo              ;fills ti_cols and ti_lines

    mov     rdi, [cap_ptr]
    mov     rsi, cap_cols
    call    streq
    test    rax, rax
    jnz     do_cols

    mov     rdi, [cap_ptr]
    mov     rsi, cap_lines
    call    streq
    test    rax, rax
    jnz     do_lines

    jmp     unknown_cap

;------------------------------------------------------------------
do_cols:
    mov     rdi, columns_prefix         ;COLUMNS overrides everything
    mov     rsi, [envp_ptr]
    call    __find_env
    test    rax, rax
    jz      .ioctl
    mov     rsi, rax
    call    parse_posint
    cmp     rax, 0
    jg      emit_value
.ioctl:
    call    get_winsize
    test    rax, rax
    jz      .ti
    movzx   rax, word [winsz + 2]       ;ws_col
    test    rax, rax
    jnz     emit_value
.ti:
    mov     rax, [ti_cols]
    test    rax, rax
    jns     emit_value
    mov     rax, 80
    jmp     emit_value

;------------------------------------------------------------------
do_lines:
    mov     rdi, lines_prefix           ;LINES overrides everything
    mov     rsi, [envp_ptr]
    call    __find_env
    test    rax, rax
    jz      .ioctl
    mov     rsi, rax
    call    parse_posint
    cmp     rax, 0
    jg      emit_value
.ioctl:
    call    get_winsize
    test    rax, rax
    jz      .ti
    movzx   rax, word [winsz]           ;ws_row
    test    rax, rax
    jnz     emit_value
.ti:
    mov     rax, [ti_lines]
    test    rax, rax
    jns     emit_value
    mov     rax, 24
    jmp     emit_value

;------------------------------------------------------------------
; emit_value - print rax as unsigned decimal plus newline, then exit 0
;------------------------------------------------------------------
emit_value:
    mov     rcx, numbuf + 31
    mov     byte [rcx], 10              ;trailing newline
    mov     rbx, 10
.div:
    xor     rdx, rdx
    div     rbx
    add     dl, '0'
    dec     rcx
    mov     [rcx], dl
    test    rax, rax
    jnz     .div

    mov     rdx, numbuf + 32
    sub     rdx, rcx                    ;digits plus newline
    mov     rsi, rcx
    mov     rdi, STDOUT_FILENO
    mov     rax, SYS_WRITE
    syscall
    exit    0

;------------------------------------------------------------------
; open_terminfo - locate and read the terminfo entry for $TERM into
; ti_buf. Tries $TERMINFO, then the standard system directories. Jumps to
; unknown_terminal when no entry is found.
;------------------------------------------------------------------
open_terminfo:
    mov     rdi, terminfo_prefix        ;honour $TERMINFO first
    mov     rsi, [envp_ptr]
    call    __find_env
    test    rax, rax
    jz      .try_etc
    mov     rsi, rax
    call    build_open
    test    rax, rax
    jns     .ok
.try_etc:
    mov     rsi, dir_etc
    call    build_open
    test    rax, rax
    jns     .ok
    mov     rsi, dir_usr
    call    build_open
    test    rax, rax
    jns     .ok
    mov     rsi, dir_lib
    call    build_open
    test    rax, rax
    jns     .ok
    jmp     unknown_terminal
.ok:
    mov     r10, rax                    ;file descriptor
    mov     rax, SYS_READ
    mov     rdi, r10
    mov     rsi, ti_buf
    mov     rdx, 8192
    syscall
    mov     r9, rax                     ;bytes read
    mov     rax, SYS_CLOSE
    mov     rdi, r10
    syscall
    mov     rax, r9
    ret

;------------------------------------------------------------------
; build_open - assemble "<dir>/<c>/<TERM>" in pathbuf and open it.
;   rsi = directory string. Returns rax = fd or negative errno.
;------------------------------------------------------------------
build_open:
    mov     rdi, pathbuf
    call    appendz                     ;directory
    mov     byte [rdi], '/'
    inc     rdi
    mov     r8, [term_ptr]
    mov     al, [r8]                    ;first character of $TERM
    mov     [rdi], al
    inc     rdi
    mov     byte [rdi], '/'
    inc     rdi
    mov     rsi, [term_ptr]
    call    appendz                     ;full terminal name
    mov     byte [rdi], 0

    mov     rax, SYS_OPEN
    mov     rdi, pathbuf
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    ret

;------------------------------------------------------------------
; appendz - copy NUL-terminated string at rsi to rdi (no NUL), leaving
; rdi just past the last byte written.
;------------------------------------------------------------------
appendz:
    mov     al, [rsi]
    test    al, al
    jz      .done
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     appendz
.done:
    ret

;------------------------------------------------------------------
; parse_terminfo - read columns (number 0) and lines (number 2) from the
; entry in ti_buf, storing them in ti_cols / ti_lines (-1 when absent).
;------------------------------------------------------------------
parse_terminfo:
    movzx   rax, word [ti_buf]
    cmp     ax, TI_MAGIC16
    je      .m16
    cmp     ax, TI_MAGIC32
    je      .m32
    jmp     unknown_terminal            ;unrecognised format

.m16:
    movzx   rcx, word [ti_buf + 2]      ;names size
    movzx   rdx, word [ti_buf + 4]      ;bool count
    movzx   r8, word [ti_buf + 6]       ;number count
    lea     r9, [rcx + rdx + 12]
    test    r9, 1
    jz      .a16
    inc     r9                          ;align to an even offset
.a16:
    cmp     r8, 1
    jb      .no_cols16
    movzx   rax, word [ti_buf + r9]
    cmp     ax, 0xFFFE
    jae     .no_cols16
    mov     [ti_cols], rax
    jmp     .lines16
.no_cols16:
    mov     qword [ti_cols], -1
.lines16:
    cmp     r8, 3
    jb      .no_lines16
    movzx   rax, word [ti_buf + r9 + 4]
    cmp     ax, 0xFFFE
    jae     .no_lines16
    mov     [ti_lines], rax
    ret
.no_lines16:
    mov     qword [ti_lines], -1
    ret

.m32:
    movzx   rcx, word [ti_buf + 2]
    movzx   rdx, word [ti_buf + 4]
    movzx   r8, word [ti_buf + 6]
    lea     r9, [rcx + rdx + 12]
    test    r9, 1
    jz      .a32
    inc     r9
.a32:
    cmp     r8, 1
    jb      .no_cols32
    mov     eax, dword [ti_buf + r9]
    cmp     eax, 0xFFFFFFFE
    jae     .no_cols32
    mov     [ti_cols], rax
    jmp     .lines32
.no_cols32:
    mov     qword [ti_cols], -1
.lines32:
    cmp     r8, 3
    jb      .no_lines32
    mov     eax, dword [ti_buf + r9 + 8]
    cmp     eax, 0xFFFFFFFE
    jae     .no_lines32
    mov     [ti_lines], rax
    ret
.no_lines32:
    mov     qword [ti_lines], -1
    ret

;------------------------------------------------------------------
; get_winsize - TIOCGWINSZ on standard output. rax = 1 on success, else 0.
;------------------------------------------------------------------
get_winsize:
    mov     rax, SYS_IOCTL
    mov     rdi, STDOUT_FILENO
    mov     rsi, TIOCGWINSZ
    mov     rdx, winsz
    syscall
    test    rax, rax
    js      .fail
    mov     rax, 1
    ret
.fail:
    xor     rax, rax
    ret

;------------------------------------------------------------------
; parse_posint - parse decimal digits at rsi. rax = value when the whole
; string is digits and the value is positive, otherwise -1.
;------------------------------------------------------------------
parse_posint:
    xor     rax, rax
    xor     rcx, rcx
.loop:
    movzx   rdx, byte [rsi]
    test    dl, dl
    jz      .done
    sub     dl, '0'
    cmp     dl, 9
    ja      .invalid
    imul    rax, rax, 10
    add     rax, rdx
    inc     rsi
    inc     rcx
    jmp     .loop
.done:
    test    rcx, rcx
    jz      .invalid
    test    rax, rax
    jz      .invalid
    ret
.invalid:
    mov     rax, -1
    ret

;------------------------------------------------------------------
; streq - compare two NUL-terminated strings, rax = 1 when equal
;------------------------------------------------------------------
streq:
    xor     rcx, rcx
.loop:
    mov     al, [rdi + rcx]
    mov     dl, [rsi + rcx]
    cmp     al, dl
    jne     .ne
    test    al, al
    je      .eq
    inc     rcx
    jmp     .loop
.eq:
    mov     rax, 1
    ret
.ne:
    xor     rax, rax
    ret

;------------------------------------------------------------------
no_args:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    2

no_term:
    write   STDERR_FILENO, noterm_msg, noterm_len
    exit    2

unknown_terminal:
    write   STDERR_FILENO, err_unk_pre, err_unk_pre_len
    mov     rsi, [term_ptr]
    call    strlen
    write   STDERR_FILENO, rsi, rbx
    write   STDERR_FILENO, err_unk_post, err_unk_post_len
    exit    3

unknown_cap:
    write   STDERR_FILENO, err_cap_pre, err_cap_pre_len
    mov     rsi, [cap_ptr]
    call    strlen
    write   STDERR_FILENO, rsi, rbx
    write   STDERR_FILENO, err_cap_post, err_cap_post_len
    exit    4
