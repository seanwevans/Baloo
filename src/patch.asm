; src/patch.asm -- patch(1): apply a unified diff.
; Usage: patch [-pN] [-i DIFF] [--dry-run] [FILE]
;
; Each "--- / +++" pair names a file and the hunks that follow are applied to
; it. A name of /dev/null on one side means the file is being created or
; deleted; a quoted name is unescaped, and anything after a tab is the
; timestamp diff writes there, not part of the name. Without -p only the last
; component of the name is used, which is what makes "a/x/input" patch
; "input".
;
; A hunk is not required to sit at the line its header claims. The context is
; searched for outward from that line, and if it still will not fit, up to two
; context lines are dropped from each end and the search repeated -- so a hunk
; whose surroundings have since changed still applies, and only the part that
; matched is replaced.

    %include "include/sysdefs.inc"

    %define DIFFCAP (8 * 1024 * 1024)
    %define SRCCAP (8 * 1024 * 1024)
    %define OUTCAP (16 * 1024 * 1024)
    %define MAXLINES 200000
    %define MAXHUNK 100000
    %define NAMECAP 4096
    %define MAXFUZZ 2
    %define MSGCAP 65536

section .bss
    diffbuf     resb DIFFCAP
    srcbuf      resb SRCCAP
    outbuf      resb OUTCAP
    doff        resq MAXLINES
    dlen        resq MAXLINES
    soff        resq MAXLINES
    slen        resq MAXLINES
    old_idx     resq MAXHUNK
    old_del     resb MAXHUNK
    new_idx     resq MAXHUNK
    new_add     resb MAXHUNK
    oldname     resb NAMECAP
    newname     resb NAMECAP
    target      resb NAMECAP
    numbuf      resb 64
    ndiff       resq 1
    nsrc        resq 1
    outlen      resq 1
    dcur        resq 1
    nold        resq 1
    nnew        resq 1
    h_oldstart  resq 1
    h_oldcount  resq 1
    h_newstart  resq 1
    h_newcount  resq 1
    copied      resq 1
    stripnum    resq 1
    difffile    resq 1
    argtarget   resq 1
    matchpos    resq 1
    trimlead    resq 1
    trimtail    resq 1
    have_p      resb 1
    opt_dryrun  resb 1
    creating    resb 1
    deleting    resb 1
    status      resb 1

section .data
    l_dryrun    db "--dry-run", 0
    l_strip     db "--strip", 0
    l_input     db "--input", 0
    l_quiet     db "--quiet", 0

    s_devnull   db "/dev/null", 0
    s_minus     db "--- ", 0
    s_plus      db "+++ ", 0
    s_at        db "@@ ", 0
    s_patching  db "patching file ", 0
s_badname   db "patch: bad ", 0
s_failed    db "patch: hunk failed", 10, 0
s_nofile    db "patch: cannot open file", 10, 0
s_usage     db "Usage: patch [-pN] [-i DIFF] [--dry-run] [FILE]", 10
    s_usage_len equ $ - s_usage

section .text
global _start

_start:
    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    jle     run
    mov     rdi, [r13]
    test    rdi, rdi
    jz      run
    cmp     byte [rdi], '-'
    jne     .operand
    cmp     byte [rdi + 1], 0
    je      .operand
    cmp     byte [rdi + 1], '-'
    jne     .short
    cmp     byte [rdi + 2], 0
    jne     .long
    add     r13, 8
    dec     r12
    jmp     .tail
.long:
    mov     rsi, l_dryrun
    call    longmatch
    test    al, al
    jnz     .set_dry
    mov     rsi, l_strip
    call    longmatch
    test    al, al
    jnz     .set_strip
    mov     rsi, l_input
    call    longmatch
    test    al, al
    jnz     .set_input
    mov     rsi, l_quiet
    call    longmatch
    test    al, al
    jnz     .next
    jmp     usage
.set_dry:
    mov     byte [opt_dryrun], 1
    jmp     .next
.set_strip:
    cmp     al, 2
    je      .strip_have
    call    next_value
.strip_have:
    mov     rdi, rdx
    call    atou
    mov     [stripnum], rax
    mov     byte [have_p], 1
    jmp     .next
.set_input:
    cmp     al, 2
    je      .input_have
    call    next_value
.input_have:
    mov     [difffile], rdx
    jmp     .next
.short:
    lea     rsi, [rdi + 1]
.flag:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .next
    inc     rsi
    cmp     al, 'p'
    je      .f_p
    cmp     al, 'i'
    je      .f_i
    cmp     al, 'l'
    je      .flag
    cmp     al, 'f'
    je      .flag
    cmp     al, 'N'
    je      .flag
    cmp     al, 's'
    je      .flag
    jmp     usage
.f_p:
    call    opt_value
    mov     rdi, rdx
    call    atou
    mov     [stripnum], rax
    mov     byte [have_p], 1
    jmp     .next
.f_i:
    call    opt_value
    mov     [difffile], rdx
    jmp     .next
.operand:
    mov     [argtarget], rdi
.next:
    add     r13, 8
    dec     r12
    jmp     parse
.tail:
    cmp     r12, 0
    jle     run
    mov     rdi, [r13]
    test    rdi, rdi
    jz      run
    mov     [argtarget], rdi
    add     r13, 8
    dec     r12
    jmp     .tail

opt_value:
    cmp     byte [rsi], 0
    je      next_value
    mov     rdx, rsi
    ret

next_value:
    add     r13, 8
    dec     r12
    mov     rdx, [r13]
    test    rdx, rdx
    jz      usage
    ret

longmatch:
    push    rdi
    push    rsi
.scan:
    mov     al, [rsi]
    test    al, al
    jz      .end
    cmp     al, [rdi]
    jne     .no
    inc     rsi
    inc     rdi
    jmp     .scan
.end:
    cmp     byte [rdi], 0
    je      .bare
    cmp     byte [rdi], '='
    jne     .no
    lea     rdx, [rdi + 1]
    pop     rsi
    pop     rdi
    mov     al, 2
    ret
.bare:
    pop     rsi
    pop     rdi
    mov     al, 1
    ret
.no:
    pop     rsi
    pop     rdi
    xor     al, al
    ret

usage:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, s_usage
    mov     rdx, s_usage_len
    syscall
    exit    2

; ---------------------------------------------------------------------------
; run: read the diff, then work through it one "--- / +++" pair at a time.
; ---------------------------------------------------------------------------
run:
    mov     rdi, [difffile]
    test    rdi, rdi
    jnz     .fromfile
    mov     rdi, s_dash
.fromfile:
    mov     rsi, diffbuf
    mov     rdx, DIFFCAP
    call    slurp
    cmp     rax, -1
    je      .cannot
    mov     rdi, diffbuf
    mov     rsi, rax
    mov     rdx, doff
    mov     rcx, dlen
    call    split_lines
    mov     [ndiff], rax
    mov     qword [dcur], 0
.file:
    call    find_header                 ;-> al = 1 when a pair was found
    test    al, al
    jz      .done
    call    apply_file
    jmp     .file
.done:
    movzx   edi, byte [status]
    mov     rax, SYS_EXIT
    syscall
.cannot:
    mov     rsi, s_nofile
    call    err_str
    exit    2

; ---------------------------------------------------------------------------
; find_header: skip forward to the next "--- " line and its "+++ " partner,
; leaving the two names in oldname and newname. al = 1 when one was found.
; ---------------------------------------------------------------------------
find_header:
    push    rbx
.scan:
    mov     rbx, [dcur]
    cmp     rbx, [ndiff]
    jge     .none
    mov     rsi, s_minus
    call    line_starts
    test    al, al
    jz      .next
; the name is read before looking for its partner, so a malformed one is
; reported even when the diff stops right there
    mov     rdi, oldname
    call    parse_name                  ;uses line rbx
    inc     qword [dcur]
    mov     rbx, [dcur]
    cmp     rbx, [ndiff]
    jge     .none
    mov     rsi, s_plus
    call    line_starts
    test    al, al
    jz      .scan                       ;a stray "---" line, keep looking
    mov     rdi, newname
    call    parse_name
    inc     qword [dcur]
    mov     al, 1
    pop     rbx
    ret
.next:
    inc     qword [dcur]
    jmp     .scan
.none:
    xor     al, al
    pop     rbx
    ret

; line_starts: does diff line rbx begin with the string at rsi? al = 1/0.
line_starts:
    push    rbx
    mov     rdi, [doff + rbx * 8]
    add     rdi, diffbuf
    mov     rdx, [dlen + rbx * 8]
    xor     rcx, rcx
.scan:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .yes
    cmp     rcx, rdx
    jae     .no
    cmp     al, [rdi + rcx]
    jne     .no
    inc     rcx
    jmp     .scan
.yes:
    mov     al, 1
    pop     rbx
    ret
.no:
    xor     al, al
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; parse_name: take the file name out of diff line rbx into the buffer at rdi.
; A quoted name is unescaped; an unquoted one stops at the tab that separates
; the timestamp diff appends.
; ---------------------------------------------------------------------------
parse_name:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi                    ;destination
    mov     r13, [doff + rbx * 8]
    add     r13, diffbuf
    mov     r14, [dlen + rbx * 8]
    add     r13, 4                      ;past "--- " or "+++ "
    sub     r14, 4
    xor     rcx, rcx                    ;destination length
    cmp     r14, 0
    jle     .term
    cmp     byte [r13], '"'
    je      .quoted
.plain:
    xor     rdx, rdx
.pcopy:
    cmp     rdx, r14
    jae     .term
    mov     al, [r13 + rdx]
    cmp     al, WHITESPACE_TAB
    je      .term
    cmp     rcx, NAMECAP - 2
    jae     .term
    mov     [r12 + rcx], al
    inc     rcx
    inc     rdx
    jmp     .pcopy
.quoted:
    mov     rdx, 1                      ;past the opening quote
.qcopy:
    cmp     rdx, r14
    jae     .badquote                   ;ran out of line before the closing "
    mov     al, [r13 + rdx]
    cmp     al, '"'
    je      .term_quoted
    cmp     al, '\'
    jne     .qplain
    inc     rdx
    cmp     rdx, r14
    jae     .badquote
    movzx   eax, byte [r13 + rdx]
    cmp     al, 'n'
    je      .esc_nl
    cmp     al, 't'
    je      .esc_tab
    cmp     al, 'r'
    je      .esc_cr
    cmp     al, '"'
    je      .qplain
    cmp     al, '\'
    je      .qplain
    cmp     al, '0'
    jb      .qplain
    cmp     al, '7'
    ja      .qplain
; an octal escape, up to three digits
    xor     r8, r8
    xor     r9, r9
.octal:
    cmp     r9, 3
    jae     .octdone
    cmp     rdx, r14
    jae     .octdone
    movzx   eax, byte [r13 + rdx]
    sub     al, '0'
    cmp     al, 7
    ja      .octdone
    shl     r8, 3
    movzx   eax, al
    add     r8, rax
    inc     rdx
    inc     r9
    jmp     .octal
.octdone:
    dec     rdx                         ;the loop below steps past the last one
    mov     al, r8b
    jmp     .qstore
.esc_nl:
    mov     al, WHITESPACE_NL
    jmp     .qstore
.esc_tab:
    mov     al, WHITESPACE_TAB
    jmp     .qstore
.esc_cr:
    mov     al, 13
    jmp     .qstore
.qplain:
    movzx   eax, byte [r13 + rdx]
.qstore:
    cmp     rcx, NAMECAP - 2
    jae     .qnext
    mov     [r12 + rcx], al
    inc     rcx
.qnext:
    inc     rdx
    jmp     .qcopy
.term_quoted:
.term:
    mov     byte [r12 + rcx], 0
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.badquote:
    mov     rsi, s_badname
    call    out_str
    mov     rsi, r13
    mov     rdx, r14
    call    out_bytes
    mov     al, WHITESPACE_NL
    call    out_char
    call    out_flush
    exit    1

; ---------------------------------------------------------------------------
; apply_file: work out which file the header names, load it, run every hunk
; belonging to it, and write the result back.
; ---------------------------------------------------------------------------
apply_file:
    push    rbx
    mov     byte [creating], 0
    mov     byte [deleting], 0
    mov     rdi, newname
    mov     rsi, s_devnull
    call    streq
    test    al, al
    jz      .fromnew
    mov     byte [deleting], 1
    mov     rsi, oldname
    jmp     .havename
.fromnew:
    mov     rdi, oldname
    mov     rsi, s_devnull
    call    streq
    test    al, al
    jz      .usenew
    mov     byte [creating], 1
.usenew:
    mov     rsi, newname
.havename:
    mov     rdi, target
    call    strip_path
    mov     rax, [argtarget]
    test    rax, rax
    jz      .load
    mov     rsi, rax                    ;an explicit operand wins
    mov     rdi, target
    call    copy_str
.load:
    mov     qword [nsrc], 0
    cmp     byte [creating], 0
    jne     .fresh
    mov     rdi, target
    mov     rsi, srcbuf
    mov     rdx, SRCCAP
    call    slurp
    cmp     rax, -1
    je      .fresh
    mov     rdi, srcbuf
    mov     rsi, rax
    mov     rdx, soff
    mov     rcx, slen
    call    split_lines
    mov     [nsrc], rax
.fresh:
    mov     rsi, s_patching
    call    out_str
    mov     rsi, target
    call    out_str
    mov     al, WHITESPACE_NL
    call    out_char
    mov     qword [outlen], 0
    mov     qword [copied], 0
.hunk:
    call    next_hunk                   ;-> al = 1 when one was read
    test    al, al
    jz      .finish
    call    apply_hunk
    jmp     .hunk
.finish:
; copy whatever is left of the source
    mov     rbx, [copied]
.rest:
    cmp     rbx, [nsrc]
    jge     .write
    mov     rdi, rbx
    call    emit_src_line
    inc     rbx
    jmp     .rest
.write:
    cmp     byte [opt_dryrun], 0
    jne     .out
    cmp     qword [outlen], 0
    jne     .save
    cmp     byte [deleting], 0
    je      .save
    mov     rax, SYS_UNLINK             ;an emptied file is a deleted file
    mov     rdi, target
    syscall
    jmp     .out
.save:
    call    write_target
.out:
    call    out_flush
    pop     rbx
    ret

; strip_path: copy the name at rsi to rdi, dropping leading components. With
; no -p only the last component is kept, which is how "a/x/input" becomes
; "input".
strip_path:
    push    rbx
    mov     rbx, rsi
    cmp     byte [have_p], 0
    jne     .counted
.basename:
    mov     rcx, rbx
    mov     rdx, rbx
.scanb:
    mov     al, [rdx]
    test    al, al
    jz      .copy
    cmp     al, '/'
    jne     .nextb
    lea     rcx, [rdx + 1]
.nextb:
    inc     rdx
    jmp     .scanb
.counted:
    mov     rcx, rbx
    mov     r8, [stripnum]
.strip:
    test    r8, r8
    jz      .copy
    mov     al, [rcx]
    test    al, al
    jz      .copy
    cmp     al, '/'
    je      .slash
    inc     rcx
    jmp     .strip
.slash:
    inc     rcx
    dec     r8
    jmp     .strip
.copy:
    mov     rsi, rcx
    call    copy_str
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; next_hunk: read the "@@" header and the lines under it into the old and new
; line lists. al = 1 when a hunk was read.
; ---------------------------------------------------------------------------
next_hunk:
    push    rbx
    mov     rbx, [dcur]
    cmp     rbx, [ndiff]
    jge     .none
    mov     rsi, s_at
    call    line_starts
    test    al, al
    jz      .none
    call    parse_at
    inc     qword [dcur]
    mov     qword [nold], 0
    mov     qword [nnew], 0
.collect:
    mov     rax, [nold]
    cmp     rax, [h_oldcount]
    jb      .more
    mov     rax, [nnew]
    cmp     rax, [h_newcount]
    jb      .more
    jmp     .done
.more:
    mov     rbx, [dcur]
    cmp     rbx, [ndiff]
    jge     .done
    mov     rcx, [dlen + rbx * 8]
    test    rcx, rcx
    jz      .context                    ;a bare empty line is empty context
    mov     rdi, [doff + rbx * 8]
    add     rdi, diffbuf
    movzx   eax, byte [rdi]
    cmp     al, WHITESPACE_SPACE
    je      .context
    cmp     al, '-'
    je      .delete
    cmp     al, '+'
    je      .insert
    cmp     al, '\'
    je      .skip                       ;"\ No newline at end of file"
    jmp     .done
.context:
    mov     rax, [nold]
    mov     [old_idx + rax * 8], rbx
    mov     byte [old_del + rax], 0
    inc     qword [nold]
    mov     rax, [nnew]
    mov     [new_idx + rax * 8], rbx
    mov     byte [new_add + rax], 0
    inc     qword [nnew]
    jmp     .step
.delete:
    mov     rax, [nold]
    mov     [old_idx + rax * 8], rbx
    mov     byte [old_del + rax], 1
    inc     qword [nold]
    jmp     .step
.insert:
    mov     rax, [nnew]
    mov     [new_idx + rax * 8], rbx
    mov     byte [new_add + rax], 1
    inc     qword [nnew]
.step:
    inc     qword [dcur]
    jmp     .collect
.skip:
    inc     qword [dcur]
    jmp     .collect
.done:
    mov     al, 1
    pop     rbx
    ret
.none:
    xor     al, al
    pop     rbx
    ret

; parse_at: read the line numbers out of "@@ -a,b +c,d @@" on line rbx.
parse_at:
    push    rbx
    mov     rsi, [doff + rbx * 8]
    add     rsi, diffbuf
    mov     rdx, [dlen + rbx * 8]
    xor     rcx, rcx
.findminus:
    cmp     rcx, rdx
    jae     .out
    cmp     byte [rsi + rcx], '-'
    je      .old
    inc     rcx
    jmp     .findminus
.old:
    inc     rcx
    call    scan_uint                   ;-> rax, rcx advanced
    mov     [h_oldstart], rax
    mov     qword [h_oldcount], 1
    cmp     rcx, rdx
    jae     .findplus
    cmp     byte [rsi + rcx], ','
    jne     .findplus
    inc     rcx
    call    scan_uint
    mov     [h_oldcount], rax
.findplus:
    cmp     rcx, rdx
    jae     .out
    cmp     byte [rsi + rcx], '+'
    je      .new
    inc     rcx
    jmp     .findplus
.new:
    inc     rcx
    call    scan_uint
    mov     [h_newstart], rax
    mov     qword [h_newcount], 1
    cmp     rcx, rdx
    jae     .out
    cmp     byte [rsi + rcx], ','
    jne     .out
    inc     rcx
    call    scan_uint
    mov     [h_newcount], rax
.out:
    pop     rbx
    ret

; scan_uint: read digits at rsi+rcx, leaving rcx past them. rax is the value.
scan_uint:
    xor     rax, rax
.digit:
    cmp     rcx, rdx
    jae     .out
    movzx   r8, byte [rsi + rcx]
    sub     r8b, '0'
    cmp     r8b, 9
    ja      .out
    imul    rax, rax, 10
    add     rax, r8
    inc     rcx
    jmp     .digit
.out:
    ret

; ---------------------------------------------------------------------------
; apply_hunk: place the hunk in the source and splice in its replacement.
;
; The header's line number is only a hint. The context is searched for
; outward from it, and if nothing fits, context lines are dropped from the
; ends -- up to two from each -- and the search runs again. Only the part
; that matched is replaced, so the lines trimmed away are left as they are.
; ---------------------------------------------------------------------------
apply_hunk:
    push    rbx
    push    r12
    xor     r12, r12                    ;fuzz being tried
.fuzz:
    cmp     r12, MAXFUZZ
    ja      .failed
    xor     rbx, rbx                    ;0 trim tail, 1 trim head, 2 trim both
.shape:
    cmp     rbx, 2
    ja      .nextfuzz
    mov     qword [trimlead], 0
    mov     qword [trimtail], 0
    cmp     rbx, 0
    je      .tailonly
    cmp     rbx, 1
    je      .leadonly
    mov     [trimlead], r12
    mov     [trimtail], r12
    jmp     .attempt
.tailonly:
    mov     [trimtail], r12
    jmp     .attempt
.leadonly:
    mov     [trimlead], r12
.attempt:
    call    trim_ok                     ;are the trimmed lines really context?
    test    al, al
    jz      .nextshape
    call    search_match                ;-> al = 1, matchpos set
    test    al, al
    jnz     .place
.nextshape:
    inc     rbx
    jmp     .shape
.nextfuzz:
    inc     r12
    test    r12, r12
    jz      .fuzz
    jmp     .fuzz
.place:
    call    splice_hunk
    pop     r12
    pop     rbx
    ret
.failed:
    mov     byte [status], 1
    mov     rsi, s_failed
    call    err_str
    pop     r12
    pop     rbx
    ret

; trim_ok: the lines being dropped have to be context, since a deletion
; cannot be ignored. al = 1 when the trim is allowed and leaves something.
trim_ok:
    mov     rax, [trimlead]
    add     rax, [trimtail]
    cmp     rax, [nold]
    ja      .no
    cmp     rax, [nnew]
    ja      .no
    xor     rcx, rcx
.lead:
    cmp     rcx, [trimlead]
    jae     .tail
    cmp     byte [old_del + rcx], 0
    jne     .no
    mov     rax, [nold]
    cmp     rcx, rax
    jae     .no
    cmp     byte [new_add + rcx], 0
    jne     .no
    inc     rcx
    jmp     .lead
.tail:
    xor     rcx, rcx
.tailscan:
    cmp     rcx, [trimtail]
    jae     .yes
    mov     rax, [nold]
    sub     rax, rcx
    dec     rax
    cmp     rax, 0
    jl      .no
    cmp     byte [old_del + rax], 0
    jne     .no
    mov     rax, [nnew]
    sub     rax, rcx
    dec     rax
    cmp     rax, 0
    jl      .no
    cmp     byte [new_add + rax], 0
    jne     .no
    inc     rcx
    jmp     .tailscan
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; search_match: look for the trimmed old lines in the source, starting at the
; line the hunk names and working outward. matchpos is where they sit.
search_match:
    push    rbx
    push    r12
    push    r13
    mov     r13, [nold]
    sub     r13, [trimlead]
    sub     r13, [trimtail]             ;lines that have to line up
    cmp     r13, 0
    jl      .no
    mov     rax, [h_oldstart]
    test    rax, rax
    jz      .fromzero
    dec     rax                         ;the header counts from one
.fromzero:
    add     rax, [trimlead]
    mov     r12, rax                    ;where the header says to look
    cmp     r12, [copied]
    jge     .havehint
    mov     r12, [copied]
.havehint:
    xor     rbx, rbx                    ;distance from the hint
.probe:
    mov     rax, r12
    add     rax, rbx
    call    try_at
    test    al, al
    jnz     .hit
    test    rbx, rbx
    jz      .grow
    mov     rax, r12
    sub     rax, rbx
    cmp     rax, 0
    jl      .checkend
    call    try_at
    test    al, al
    jnz     .hit
.checkend:
    mov     rax, r12
    sub     rax, rbx
    cmp     rax, 0
    jge     .grow
    mov     rax, r12
    add     rax, rbx
    add     rax, r13
    cmp     rax, [nsrc]
    jg      .no                         ;both directions exhausted
.grow:
    inc     rbx
    cmp     rbx, MAXLINES
    ja      .no
    jmp     .probe
.hit:
    mov     al, 1
    pop     r13
    pop     r12
    pop     rbx
    ret
.no:
    xor     al, al
    pop     r13
    pop     r12
    pop     rbx
    ret

; try_at: do the trimmed old lines match the source starting at rax?
try_at:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rax                    ;candidate position
    cmp     r12, [copied]
    jl      .no                         ;never move backwards over output
    mov     r13, [nold]
    sub     r13, [trimtail]
    mov     rax, r12
    mov     rcx, r13
    sub     rcx, [trimlead]
    add     rax, rcx
    cmp     rax, [nsrc]
    ja      .no                         ;runs off the end of the file
    mov     rbx, [trimlead]
    xor     r14, r14                    ;offset into the source
.line:
    cmp     rbx, r13
    jge     .yes
    mov     rax, [old_idx + rbx * 8]
    lea     rdi, [r12 + r14]
    call    line_matches
    test    al, al
    jz      .no
    inc     rbx
    inc     r14
    jmp     .line
.yes:
    mov     [matchpos], r12
    mov     al, 1
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.no:
    xor     al, al
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; line_matches: does diff line rax, minus its marker, equal source line rdi?
line_matches:
    push    rbx
    mov     rbx, rdi
    cmp     rbx, [nsrc]
    jae     .no
    mov     rsi, [doff + rax * 8]
    add     rsi, diffbuf
    mov     rdx, [dlen + rax * 8]
    test    rdx, rdx
    jz      .content
    inc     rsi                         ;drop the leading marker
    dec     rdx
.content:
    mov     rdi, [soff + rbx * 8]
    add     rdi, srcbuf
    mov     rcx, [slen + rbx * 8]
    cmp     rcx, rdx
    jne     .no
    xor     r8, r8
.byte:
    cmp     r8, rcx
    jae     .yes
    mov     al, [rsi + r8]
    cmp     al, [rdi + r8]
    jne     .no
    inc     r8
    jmp     .byte
.yes:
    mov     al, 1
    pop     rbx
    ret
.no:
    xor     al, al
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; splice_hunk: copy the source up to the match, write the hunk's replacement,
; and step past the lines it consumed.
; ---------------------------------------------------------------------------
splice_hunk:
    push    rbx
    push    r12
    mov     rbx, [copied]
.lead:
    cmp     rbx, [matchpos]
    jge     .body
    mov     rdi, rbx
    call    emit_src_line
    inc     rbx
    jmp     .lead
.body:
    mov     rbx, [trimlead]
    mov     r12, [nnew]
    sub     r12, [trimtail]
.newline:
    cmp     rbx, r12
    jge     .advance
    mov     rax, [new_idx + rbx * 8]
    call    emit_diff_line
    inc     rbx
    jmp     .newline
.advance:
    mov     rax, [nold]
    sub     rax, [trimlead]
    sub     rax, [trimtail]
    add     rax, [matchpos]
    mov     [copied], rax
    pop     r12
    pop     rbx
    ret

; emit_src_line: append source line rdi, with a newline.
emit_src_line:
    push    rbx
    mov     rbx, rdi
    mov     rsi, [soff + rbx * 8]
    add     rsi, srcbuf
    mov     rdx, [slen + rbx * 8]
    call    put_bytes
    mov     al, WHITESPACE_NL
    call    put_char
    pop     rbx
    ret

; emit_diff_line: append diff line rax without its marker, with a newline.
emit_diff_line:
    mov     rsi, [doff + rax * 8]
    add     rsi, diffbuf
    mov     rdx, [dlen + rax * 8]
    test    rdx, rdx
    jz      .newline
    inc     rsi
    dec     rdx
.newline:
    call    put_bytes
    mov     al, WHITESPACE_NL
    jmp     put_char

put_char:
    push    rcx
    mov     rcx, [outlen]
    cmp     rcx, OUTCAP - 1
    jae     .out
    mov     [outbuf + rcx], al
    inc     qword [outlen]
.out:
    pop     rcx
    ret

put_bytes:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, rdx
    xor     rbx, rbx
.copy:
    cmp     rbx, r13
    jae     .out
    mov     al, [r12 + rbx]
    call    put_char
    inc     rbx
    jmp     .copy
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; write_target: replace the file with what was built.
write_target:
    mov     rax, SYS_OPEN
    mov     rdi, target
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, DEFAULT_MODE
    syscall
    test    rax, rax
    js      .fail
    mov     r8, rax
    mov     rsi, outbuf
    mov     rdx, [outlen]
.write:
    test    rdx, rdx
    jz      .close
    mov     rax, SYS_WRITE
    mov     rdi, r8
    syscall
    test    rax, rax
    jle     .close
    add     rsi, rax
    sub     rdx, rax
    jmp     .write
.close:
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    ret
.fail:
    mov     byte [status], 1
    mov     rsi, s_nofile
    jmp     err_str

; ---------------------------------------------------------------------------
; Loading and small helpers.
; ---------------------------------------------------------------------------
; slurp: read the file named by rdi into rsi, at most rdx bytes. "-" reads
; standard input. rax is the byte count, or -1 when it could not be opened.
slurp:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rsi
    mov     r14, rdx
    cmp     byte [rdi], '-'
    jne     .open
    cmp     byte [rdi + 1], 0
    jne     .open
    mov     r13, STDIN_FILENO
    jmp     .read
.open:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fail
    mov     r13, rax
.read:
    xor     rbx, rbx
.chunk:
    mov     rdx, r14
    sub     rdx, rbx
    jle     .close
    mov     rax, SYS_READ
    mov     rdi, r13
    lea     rsi, [r12 + rbx]
    syscall
    test    rax, rax
    jle     .close
    add     rbx, rax
    jmp     .chunk
.close:
    cmp     r13, STDIN_FILENO
    je      .done
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
.done:
    mov     rax, rbx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.fail:
    mov     rax, -1
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; split_lines: index the rsi bytes at rdi into the offset and length arrays
; at rdx and rcx. rax is the line count; lengths exclude the newline.
split_lines:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx
    xor     rbx, rbx
    xor     r9, r9
.line:
    cmp     rbx, r13
    jae     .done
    cmp     r9, MAXLINES
    jae     .done
    mov     [r14 + r9 * 8], rbx
    mov     rcx, rbx
.scan:
    cmp     rcx, r13
    jae     .end
    cmp     byte [r12 + rcx], WHITESPACE_NL
    je      .end
    inc     rcx
    jmp     .scan
.end:
    mov     rax, rcx
    sub     rax, rbx
    mov     [r15 + r9 * 8], rax
    inc     r9
    lea     rbx, [rcx + 1]
    jmp     .line
.done:
    mov     rax, r9
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

copy_str:
    xor     rcx, rcx
.copy:
    mov     al, [rsi + rcx]
    mov     [rdi + rcx], al
    test    al, al
    jz      .out
    inc     rcx
    cmp     rcx, NAMECAP - 1
    jae     .term
    jmp     .copy
.term:
    mov     byte [rdi + rcx], 0
.out:
    ret

streq:
    push    rdi
    push    rsi
.scan:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .no
    test    al, al
    jz      .yes
    inc     rdi
    inc     rsi
    jmp     .scan
.yes:
    mov     al, 1
    pop     rsi
    pop     rdi
    ret
.no:
    xor     al, al
    pop     rsi
    pop     rdi
    ret

strlen_z:
    xor     rax, rax
.scan:
    cmp     byte [rdi + rax], 0
    je      .out
    inc     rax
    jmp     .scan
.out:
    ret

atou:
    xor     rax, rax
.scan:
    movzx   rcx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .out
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .scan
.out:
    ret

; err_str: report on stderr, flushing the progress buffer first so the two
; streams stay in the order they were written.
err_str:
    push    rsi
    call    out_flush
    pop     rsi
    push    rsi
    mov     rdi, rsi
    call    strlen_z
    mov     rdx, rax
    pop     rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    syscall
    ret

; ---------------------------------------------------------------------------
; Progress messages go to standard output, buffered so they interleave
; predictably with anything else patch says.
; ---------------------------------------------------------------------------
out_char:
    push    rcx
    mov     rcx, [msglen]
    cmp     rcx, MSGCAP - 1
    jae     .flushfirst
    jmp     .store
.flushfirst:
    call    out_flush
    mov     rcx, [msglen]
.store:
    mov     [msgbuf + rcx], al
    inc     qword [msglen]
    pop     rcx
    ret

out_bytes:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, rdx
    xor     rbx, rbx
.copy:
    cmp     rbx, r13
    jae     .out
    mov     al, [r12 + rbx]
    call    out_char
    inc     rbx
    jmp     .copy
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

out_str:
    push    rbx
    mov     rbx, rsi
.copy:
    mov     al, [rbx]
    test    al, al
    jz      .out
    call    out_char
    inc     rbx
    jmp     .copy
.out:
    pop     rbx
    ret

out_flush:
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    mov     rdx, [msglen]
    test    rdx, rdx
    jz      .out
    mov     rsi, msgbuf
.write:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    test    rax, rax
    jle     .done
    add     rsi, rax
    sub     rdx, rax
    jnz     .write
.done:
    mov     qword [msglen], 0
.out:
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi
    ret

section .bss
    msgbuf      resb 65536
    msglen      resq 1

section .data
    s_dash      db "-", 0
