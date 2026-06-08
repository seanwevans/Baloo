; src/msgfmt.asm
;
; msgfmt - compile a GNU gettext .po file into a binary .mo catalog.
;
; Supported usage
;   msgfmt [-o OUTPUT] [INPUT.po]
;
; INPUT is read from the named file, or standard input. OUTPUT defaults to
; "messages.mo". The translations are written in the little-endian .mo
; format with the original strings sorted, so the catalog is usable by a
; gettext runtime (no hash table is emitted; readers fall back to a binary
; search over the sorted table).
;
; Simple msgid/msgstr entries with the common C escape sequences are
; handled, including multi-line continuation strings and the empty-msgid
; header. Untranslated entries (empty msgstr) are omitted, as GNU msgfmt
; does. Plural forms, msgctxt, fuzzy handling, and #-comments beyond being
; skipped are out of scope.

    %include "include/sysdefs.inc"

    %define PO_CAP   1048576
    %define POOL_CAP 4194304
    %define MO_CAP   5242880
    %define MAXENT   65536

section .bss
    pobuf       resb PO_CAP
    strpool     resb POOL_CAP
    mobuf       resb MO_CAP

    id_ptr_arr  resq MAXENT
    id_len_arr  resq MAXENT
    str_ptr_arr resq MAXENT
    str_len_arr resq MAXENT
    idx         resq MAXENT
    o_off       resd MAXENT
    t_off       resd MAXENT

    cur_id_start resq 1
    cur_id_len   resq 1
    cur_str_start resq 1
    pending      resb 1
    ncount       resq 1
    out_name     resq 1
    in_name      resq 1

section .data
    default_out db "messages.mo", 0

section .text
global _start

_start:
    pop     rbx                         ;argc
    mov     r12, rsp                    ;argv pointer

    mov     qword [out_name], default_out
    mov     qword [in_name], 0

    mov     rcx, 1
.parse_args:
    cmp     rcx, rbx
    jae     .args_done
    mov     rsi, [r12 + rcx*8]
    cmp     byte [rsi], '-'
    jne     .arg_in
    cmp     byte [rsi + 1], 'o'
    jne     .arg_skip
    cmp     byte [rsi + 2], 0
    je      .o_sep
    lea     rax, [rsi + 2]
    mov     [out_name], rax
    inc     rcx
    jmp     .parse_args
.o_sep:
    inc     rcx
    cmp     rcx, rbx
    jae     .args_done
    mov     rax, [r12 + rcx*8]
    mov     [out_name], rax
    inc     rcx
    jmp     .parse_args
.arg_skip:
    inc     rcx
    jmp     .parse_args
.arg_in:
    mov     [in_name], rsi
    inc     rcx
    jmp     .parse_args

.args_done:
    cmp     qword [in_name], 0
    jne     .open_in
    xor     rdi, rdi
    jmp     .read_in
.open_in:
    mov     rax, SYS_OPEN
    mov     rdi, [in_name]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fatal
    mov     rdi, rax
.read_in:
    mov     rsi, pobuf
    mov     rdx, PO_CAP
    call    slurp
    mov     r15, pobuf
    add     r15, rax                    ;po end
    mov     r12, pobuf                  ;po cursor
    mov     r13, strpool                ;string pool cursor

    mov     qword [ncount], 0
    mov     byte [pending], 0

;------------------------------------------------------------------
; parse the .po, one line at a time
;------------------------------------------------------------------
.lineloop:
    cmp     r12, r15
    jae     .eof
    mov     rsi, r12                    ;line start
    mov     rax, r12                    ;find end of line
.findnl:
    cmp     rax, r15
    jae     .nl0
    cmp     byte [rax], 10
    je      .nl1
    inc     rax
    jmp     .findnl
.nl1:
    inc     rax
.nl0:
    mov     r12, rax                    ;next line

.skipws:
    mov     al, [rsi]
    cmp     al, ' '
    je      .ws
    cmp     al, 9
    je      .ws
    jmp     .check
.ws:
    inc     rsi
    jmp     .skipws

.check:
    mov     al, [rsi]
    cmp     al, '#'
    je      .lineloop
    cmp     al, 10
    je      .lineloop
    test    al, al
    je      .lineloop
    cmp     al, '"'
    je      .cont

    cmp     dword [rsi], 0x6967736d     ;"msgi"
    jne     .chk_str
    cmp     byte [rsi + 4], 'd'
    jne     .chk_str
    cmp     byte [rsi + 5], '_'
    je      .chk_str                    ;msgid_plural, not handled

    cmp     byte [pending], 0           ;a new msgid flushes the prior entry
    je      .new_id
    call    flush_entry
.new_id:
    mov     [cur_id_start], r13
    mov     byte [pending], 1
    lea     rsi, [rsi + 5]
    call    parse_quoted
    jmp     .lineloop

.chk_str:
    cmp     dword [rsi], 0x7367736d     ;"msgs"
    jne     .lineloop
    cmp     byte [rsi + 4], 't'
    jne     .lineloop
    cmp     byte [rsi + 5], 'r'
    jne     .lineloop
    cmp     byte [rsi + 6], '['
    je      .lineloop                   ;msgstr[N], plural, not handled

    mov     byte [r13], 0               ;terminate the msgid
    mov     rax, r13
    sub     rax, [cur_id_start]
    mov     [cur_id_len], rax
    inc     r13
    mov     [cur_str_start], r13
    lea     rsi, [rsi + 6]
    call    parse_quoted
    jmp     .lineloop

.cont:
    call    parse_quoted                ;continuation string
    jmp     .lineloop

.eof:
    cmp     byte [pending], 0
    je      .build
    call    flush_entry
.build:
    call    sort
    call    emit
    exit    0

.fatal:
    exit    1

;------------------------------------------------------------------
; flush_entry - terminate the current msgstr and record the entry, unless
; the translation is empty (which GNU msgfmt omits).
;------------------------------------------------------------------
flush_entry:
    mov     byte [r13], 0
    mov     rax, r13
    sub     rax, [cur_str_start]        ;str length
    inc     r13
    mov     byte [pending], 0
    test    rax, rax
    jz      .skip                       ;empty translation, drop it
    mov     rcx, [ncount]
    cmp     rcx, MAXENT
    jae     .skip
    mov     rdx, [cur_id_start]
    mov     [id_ptr_arr + rcx*8], rdx
    mov     rdx, [cur_id_len]
    mov     [id_len_arr + rcx*8], rdx
    mov     rdx, [cur_str_start]
    mov     [str_ptr_arr + rcx*8], rdx
    mov     [str_len_arr + rcx*8], rax
    inc     rcx
    mov     [ncount], rcx
.skip:
    ret

;------------------------------------------------------------------
; parse_quoted - from rsi, find the opening quote and append the decoded
; string contents to [r13], advancing r13. Preserves r12, r15.
;------------------------------------------------------------------
parse_quoted:
.findq:
    mov     al, [rsi]
    test    al, al
    je      .ret
    cmp     al, 10
    je      .ret
    cmp     al, '"'
    je      .open
    inc     rsi
    jmp     .findq
.open:
    inc     rsi
.body:
    mov     al, [rsi]
    cmp     al, '"'
    je      .ret
    test    al, al
    je      .ret
    cmp     al, 10
    je      .ret
    cmp     al, 92
    je      .esc
    mov     [r13], al
    inc     r13
    inc     rsi
    jmp     .body
.esc:
    inc     rsi
    mov     al, [rsi]
    cmp     al, 'n'
    je      .e10
    cmp     al, 't'
    je      .e9
    cmp     al, 'r'
    je      .e13
    cmp     al, 'f'
    je      .e12
    cmp     al, 'b'
    je      .e8
    cmp     al, 'a'
    je      .e7
    cmp     al, 'v'
    je      .e11
    jmp     .eput                       ;\" \\ and anything else, literal
.e10:
    mov     al, 10
    jmp     .eput
.e9:
    mov     al, 9
    jmp     .eput
.e13:
    mov     al, 13
    jmp     .eput
.e12:
    mov     al, 12
    jmp     .eput
.e8:
    mov     al, 8
    jmp     .eput
.e7:
    mov     al, 7
    jmp     .eput
.e11:
    mov     al, 11
.eput:
    mov     [r13], al
    inc     r13
    inc     rsi
    jmp     .body
.ret:
    ret

;------------------------------------------------------------------
; sort - insertion-sort idx[] so the msgids compare in ascending C order.
;------------------------------------------------------------------
sort:
    xor     rcx, rcx
.init:
    cmp     rcx, [ncount]
    jae     .go
    mov     [idx + rcx*8], rcx
    inc     rcx
    jmp     .init
.go:
    mov     rcx, 1
.outer:
    cmp     rcx, [ncount]
    jae     .done
    mov     r9, [idx + rcx*8]           ;key index
    mov     rdx, rcx                    ;j
.inner:
    test    rdx, rdx
    jz      .place
    mov     r8, [idx + rdx*8 - 8]       ;idx[j-1]
    mov     rsi, [id_ptr_arr + r8*8]
    mov     rdi, [id_ptr_arr + r9*8]
    call    strcmp_id
    test    rax, rax
    jle     .place
    mov     r8, [idx + rdx*8 - 8]
    mov     [idx + rdx*8], r8
    dec     rdx
    jmp     .inner
.place:
    mov     [idx + rdx*8], r9
    inc     rcx
    jmp     .outer
.done:
    ret

;------------------------------------------------------------------
; strcmp_id - C strcmp of NUL-terminated strings rsi, rdi. rax >0/0/<0.
; Preserves rcx, rdx, r8, r9.
;------------------------------------------------------------------
strcmp_id:
.l:
    movzx   rax, byte [rsi]
    movzx   r10, byte [rdi]
    cmp     rax, r10
    jne     .diff
    test    rax, rax
    jz      .eq
    inc     rsi
    inc     rdi
    jmp     .l
.diff:
    sub     rax, r10
    ret
.eq:
    xor     rax, rax
    ret

;------------------------------------------------------------------
; emit - assemble the .mo image in mobuf and write it to the output file.
;------------------------------------------------------------------
emit:
    mov     r8, [ncount]                ;N

; precompute the original/translation string offsets
    mov     eax, r8d
    shl     eax, 4
    add     eax, 28                     ;data_start = 28 + 16N
    mov     r9d, eax                    ;running offset
    xor     rcx, rcx
.ooff:
    cmp     rcx, r8
    jae     .toff
    mov     [o_off + rcx*4], r9d
    mov     rdx, [idx + rcx*8]
    mov     eax, [id_len_arr + rdx*8]
    add     r9d, eax
    add     r9d, 1
    inc     rcx
    jmp     .ooff
.toff:
    xor     rcx, rcx
.tl:
    cmp     rcx, r8
    jae     .header
    mov     [t_off + rcx*4], r9d
    mov     rdx, [idx + rcx*8]
    mov     eax, [str_len_arr + rdx*8]
    add     r9d, eax
    add     r9d, 1
    inc     rcx
    jmp     .tl

.header:
    mov     rbx, mobuf
    mov     eax, 0x950412de
    call    put32                       ;magic
    xor     eax, eax
    call    put32                       ;revision
    mov     eax, r8d
    call    put32                       ;N
    mov     eax, 28
    call    put32                       ;O offset
    mov     eax, r8d
    shl     eax, 3
    add     eax, 28
    call    put32                       ;T offset
    xor     eax, eax
    call    put32                       ;hash size
    xor     eax, eax
    call    put32                       ;hash offset

    xor     rcx, rcx                    ;original string table
.wo:
    cmp     rcx, r8
    jae     .wt
    mov     rdx, [idx + rcx*8]
    mov     eax, [id_len_arr + rdx*8]
    call    put32
    mov     eax, [o_off + rcx*4]
    call    put32
    inc     rcx
    jmp     .wo
.wt:
    xor     rcx, rcx                    ;translation string table
.wtl:
    cmp     rcx, r8
    jae     .wod
    mov     rdx, [idx + rcx*8]
    mov     eax, [str_len_arr + rdx*8]
    call    put32
    mov     eax, [t_off + rcx*4]
    call    put32
    inc     rcx
    jmp     .wtl

.wod:
    xor     rcx, rcx                    ;original string data
.wod2:
    cmp     rcx, r8
    jae     .wtd
    mov     rdx, [idx + rcx*8]
    mov     rsi, [id_ptr_arr + rdx*8]
    mov     r10, [id_len_arr + rdx*8]
    call    copy_to_mobuf
    mov     byte [rbx], 0
    inc     rbx
    inc     rcx
    jmp     .wod2
.wtd:
    xor     rcx, rcx                    ;translation string data
.wtd2:
    cmp     rcx, r8
    jae     .write_out
    mov     rdx, [idx + rcx*8]
    mov     rsi, [str_ptr_arr + rdx*8]
    mov     r10, [str_len_arr + rdx*8]
    call    copy_to_mobuf
    mov     byte [rbx], 0
    inc     rbx
    inc     rcx
    jmp     .wtd2

.write_out:
    mov     rax, SYS_OPEN
    mov     rdi, [out_name]
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, DEFAULT_MODE
    syscall
    test    rax, rax
    js      .efatal
    mov     r9, rax
    mov     rax, SYS_WRITE
    mov     rdi, r9
    mov     rsi, mobuf
    mov     rdx, rbx
    sub     rdx, mobuf
    syscall
    mov     rax, SYS_CLOSE
    mov     rdi, r9
    syscall
    ret
.efatal:
    exit    1

;------------------------------------------------------------------
; put32 - store eax little-endian at [rbx], advancing rbx by 4.
;------------------------------------------------------------------
put32:
    mov     [rbx], eax
    add     rbx, 4
    ret

;------------------------------------------------------------------
; copy_to_mobuf - copy r10 bytes from rsi to [rbx], advancing rbx.
; Preserves rcx, r8.
;------------------------------------------------------------------
copy_to_mobuf:
    test    r10, r10
    jz      .done
.l:
    mov     al, [rsi]
    mov     [rbx], al
    inc     rsi
    inc     rbx
    dec     r10
    jnz     .l
.done:
    ret

;------------------------------------------------------------------
; slurp - read fd rdi into [rsi] up to rdx bytes; rax = byte count.
;------------------------------------------------------------------
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
