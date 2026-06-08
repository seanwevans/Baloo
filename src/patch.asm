; src/patch.asm
;
; patch - apply a unified diff to a file.
;
; Supported usage
;   patch [TARGET] [-pN] [-i DIFF]
;
;   TARGET      file to patch; when omitted it is taken from the "+++"
;               header (with -pN leading path components stripped)
;   -pN         strip N leading path components from the header name
;   -i DIFF     read the diff from DIFF instead of standard input
;
; Only the unified diff format is understood. Each hunk is applied at the
; line numbers named in its "@@ -old,n +new,m @@" header, with context and
; deleted lines verified against the source. Fuzz, offset search, reject
; files, and context/ed/normal diffs are out of scope; a hunk that does
; not match exactly is reported as failed.

    %include "include/sysdefs.inc"

    %define DIFF_CAP 1048576
    %define SRC_CAP  1048576
    %define OUT_CAP  2097152

section .bss
    diffbuf     resb DIFF_CAP
    srcbuf      resb SRC_CAP
    outbuf      resb OUT_CAP
    target_name resb 4096

    target_ptr  resq 1
    diff_file   resq 1
    strip       resq 1
    srcln       resq 1
    h_os        resq 1
    h_oc        resq 1
    h_nc        resq 1
    old_rem     resq 1
    new_rem     resq 1

section .data
    msg_patching db "patching file "
    msg_patching_len equ $ - msg_patching
fail_msg     db "patch: hunk does not apply", 10
    fail_msg_len equ $ - fail_msg
notarget_msg db "patch: cannot determine file to patch", 10
    notarget_len equ $ - notarget_msg
open_msg     db "patch: cannot open file", 10
    open_msg_len equ $ - open_msg
    newline      db 10

section .text
global _start

_start:
    pop     rbx                         ;argc
    mov     r12, rsp                    ;argv pointer

    mov     qword [target_ptr], 0
    mov     qword [diff_file], 0
    mov     qword [strip], 0

    mov     rcx, 1
.parse:
    cmp     rcx, rbx
    jae     .parsed
    mov     rsi, [r12 + rcx*8]
    cmp     byte [rsi], '-'
    jne     .operand
    cmp     byte [rsi + 1], 0
    je      .operand                    ;"-" is standard input target

    mov     al, [rsi + 1]
    cmp     al, 'p'
    je      .opt_p
    cmp     al, 'i'
    je      .opt_i
    inc     rcx                         ;ignore unsupported option
    jmp     .parse

.opt_p:
    cmp     byte [rsi + 2], 0
    je      .p_sep
    lea     rsi, [rsi + 2]
    call    parse_uint
    mov     [strip], rax
    inc     rcx
    jmp     .parse
.p_sep:
    inc     rcx
    cmp     rcx, rbx
    jae     .parsed
    mov     rsi, [r12 + rcx*8]
    call    parse_uint
    mov     [strip], rax
    inc     rcx
    jmp     .parse

.opt_i:
    cmp     byte [rsi + 2], 0
    je      .i_sep
    lea     rax, [rsi + 2]
    mov     [diff_file], rax
    inc     rcx
    jmp     .parse
.i_sep:
    inc     rcx
    cmp     rcx, rbx
    jae     .parsed
    mov     rax, [r12 + rcx*8]
    mov     [diff_file], rax
    inc     rcx
    jmp     .parse

.operand:
    mov     [target_ptr], rsi
    inc     rcx
    jmp     .parse

.parsed:
; read the diff into diffbuf
    mov     rax, [diff_file]
    test    rax, rax
    jnz     .diff_from_file
    xor     rdi, rdi                    ;stdin
    jmp     .diff_read
.diff_from_file:
    mov     rax, SYS_OPEN
    mov     rdi, [diff_file]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .open_err
    mov     rdi, rax
.diff_read:
    mov     rsi, diffbuf
    mov     rdx, DIFF_CAP
    call    slurp
    mov     r13, diffbuf
    add     r13, rax                    ;diff end
    mov     r12, diffbuf                ;diff cursor

; determine target file
    cmp     qword [target_ptr], 0
    jne     .have_target
    call    derive_target               ;fills target_name or jumps notarget
    mov     qword [target_ptr], target_name
.have_target:

; read the source file
    mov     rax, SYS_OPEN
    mov     rdi, [target_ptr]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .open_err
    mov     r8, rax
    mov     rdi, r8
    mov     rsi, srcbuf
    mov     rdx, SRC_CAP
    call    slurp
    mov     r14, srcbuf                 ;src cursor
    mov     r15, srcbuf
    add     r15, rax                    ;src end
    push    rax
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    pop     rax

; announce
    write   STDOUT_FILENO, msg_patching, msg_patching_len
    mov     rsi, [target_ptr]
    call    strlen                      ;rbx = length
    write   STDOUT_FILENO, [target_ptr], rbx
    write   STDOUT_FILENO, newline, 1

    mov     rbx, outbuf                 ;output write cursor
    call    apply

; write outbuf back to the target
    mov     rax, SYS_OPEN
    mov     rdi, [target_ptr]
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, DEFAULT_MODE
    syscall
    test    rax, rax
    js      .open_err
    mov     r8, rax
    mov     rax, SYS_WRITE
    mov     rdi, r8
    mov     rsi, outbuf
    mov     rdx, rbx
    sub     rdx, outbuf
    syscall
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    exit    0

.open_err:
    write   STDERR_FILENO, open_msg, open_msg_len
    exit    1

;------------------------------------------------------------------
; apply - walk the diff (r12..r13), applying hunks to the source
; (r14..r15) and building the result at rbx. State in r12-r15, rbx and
; the srcln/old_rem/new_rem cells.
;------------------------------------------------------------------
apply:
    mov     qword [srcln], 0
.scan:
    cmp     r12, r13
    jae     .finish
    call    read_diff_line              ;rsi=start, rcx=len
    cmp     rcx, 2
    jb      .scan
    cmp     byte [rsi], '@'
    jne     .scan
    cmp     byte [rsi + 1], '@'
    jne     .scan

    call    parse_hunk_header           ;sets h_os, h_oc, h_nc

    mov     rax, [h_os]                 ;copy untouched lines before the hunk
    dec     rax
.copy_pre:
    mov     rdx, [srcln]
    cmp     rdx, rax
    jae     .body_init
    call    read_src_line
    call    append_bytes
    call    append_nl
    inc     qword [srcln]
    jmp     .copy_pre

.body_init:
    mov     rax, [h_oc]
    mov     [old_rem], rax
    mov     rax, [h_nc]
    mov     [new_rem], rax
.body:
    mov     rax, [old_rem]
    or      rax, [new_rem]
    jz      .scan
    cmp     r12, r13
    jae     .finish
    call    read_diff_line              ;rsi=start, rcx=len
    test    rcx, rcx
    jz      .ctx_blank
    mov     al, [rsi]
    cmp     al, ' '
    je      .ctx
    cmp     al, '-'
    je      .del
    cmp     al, '+'
    je      .add
    cmp     al, 92                      ;backslash "No newline" marker
    je      .body
    jmp     .scan

.ctx_blank:
; a wholly empty line counts as a single space of context
    call    read_src_line
    call    append_bytes
    call    append_nl
    dec     qword [old_rem]
    dec     qword [new_rem]
    jmp     .body

.ctx:
    lea     rdi, [rsi + 1]
    mov     rdx, rcx
    dec     rdx
    call    read_src_line               ;rsi=src start, rcx=src len
    push    rsi
    push    rcx
    call    cmp_lines
    pop     rcx
    pop     rsi
    test    rax, rax
    jz      .fail
    call    append_bytes
    call    append_nl
    dec     qword [old_rem]
    dec     qword [new_rem]
    jmp     .body

.del:
    lea     rdi, [rsi + 1]
    mov     rdx, rcx
    dec     rdx
    call    read_src_line
    push    rsi
    push    rcx
    call    cmp_lines
    pop     rcx
    pop     rsi
    test    rax, rax
    jz      .fail
    dec     qword [old_rem]
    jmp     .body

.add:
    lea     rsi, [rsi + 1]
    dec     rcx
    call    append_bytes
    call    append_nl
    dec     qword [new_rem]
    jmp     .body

.finish:
    cmp     r14, r15
    jae     .ret
    call    read_src_line
    call    append_bytes
    call    append_nl
    jmp     .finish
.ret:
    ret

.fail:
    write   STDERR_FILENO, fail_msg, fail_msg_len
    exit    1

;------------------------------------------------------------------
; parse_hunk_header - parse "@@ -os,oc +ns,nc @@" at rsi into h_os/h_oc/
; h_nc. Counts default to 1 when omitted.
;------------------------------------------------------------------
parse_hunk_header:
    add     rsi, 2                      ;skip "@@"
.sp1:
    cmp     byte [rsi], ' '
    jne     .at_old
    inc     rsi
    jmp     .sp1
.at_old:
    inc     rsi                         ;skip '-'
    call    scan_uint                   ;rax = old start
    mov     [h_os], rax
    mov     qword [h_oc], 1
    cmp     byte [rsi], ','
    jne     .to_new
    inc     rsi
    call    scan_uint
    mov     [h_oc], rax
.to_new:
    cmp     byte [rsi], '+'
    je      .at_new
    inc     rsi
    jmp     .to_new
.at_new:
    inc     rsi                         ;skip '+'
    call    scan_uint                   ;rax = new start (unused)
    mov     qword [h_nc], 1
    cmp     byte [rsi], ','
    jne     .done
    inc     rsi
    call    scan_uint
    mov     [h_nc], rax
.done:
    ret

;------------------------------------------------------------------
; scan_uint - read decimal digits at rsi, advancing rsi, value in rax.
;------------------------------------------------------------------
scan_uint:
    xor     rax, rax
.loop:
    movzx   rdx, byte [rsi]
    sub     dl, '0'
    cmp     dl, 9
    ja      .done
    imul    rax, rax, 10
    add     rax, rdx
    inc     rsi
    jmp     .loop
.done:
    ret

;------------------------------------------------------------------
; parse_uint - decimal digits at rsi (rsi not preserved), value in rax.
;------------------------------------------------------------------
parse_uint:
    xor     rax, rax
.loop:
    movzx   rdx, byte [rsi]
    sub     dl, '0'
    cmp     dl, 9
    ja      .done
    imul    rax, rax, 10
    add     rax, rdx
    inc     rsi
    jmp     .loop
.done:
    ret

;------------------------------------------------------------------
; read_diff_line - line at r12 -> rsi=start, rcx=len (no newline); r12
; advances past the newline. Preserves r13-r15, rbx.
;------------------------------------------------------------------
read_diff_line:
    mov     rsi, r12
    mov     rax, r12
.sc:
    cmp     rax, r13
    jae     .eol
    cmp     byte [rax], 10
    je      .eol
    inc     rax
    jmp     .sc
.eol:
    mov     rcx, rax
    sub     rcx, rsi
    cmp     rax, r13
    jae     .nonl
    inc     rax
.nonl:
    mov     r12, rax
    ret

;------------------------------------------------------------------
; read_src_line - line at r14 -> rsi=start, rcx=len; r14 advances past the
; newline. Preserves r12, r13, r15, rbx.
;------------------------------------------------------------------
read_src_line:
    mov     rsi, r14
    mov     rax, r14
.sc:
    cmp     rax, r15
    jae     .eol
    cmp     byte [rax], 10
    je      .eol
    inc     rax
    jmp     .sc
.eol:
    mov     rcx, rax
    sub     rcx, rsi
    cmp     rax, r15
    jae     .nonl
    inc     rax
.nonl:
    mov     r14, rax
    ret

;------------------------------------------------------------------
; append_bytes - copy rcx bytes from rsi to [rbx], advancing rbx.
;------------------------------------------------------------------
append_bytes:
    test    rcx, rcx
    jz      .done
.loop:
    mov     al, [rsi]
    mov     [rbx], al
    inc     rsi
    inc     rbx
    dec     rcx
    jnz     .loop
.done:
    ret

append_nl:
    mov     byte [rbx], 10
    inc     rbx
    ret

;------------------------------------------------------------------
; cmp_lines - compare rcx bytes at rsi with rdx bytes at rdi. rax = 1 when
; the lengths and bytes match.
;------------------------------------------------------------------
cmp_lines:
    cmp     rcx, rdx
    jne     .ne
    test    rcx, rcx
    jz      .eq
.loop:
    mov     al, [rsi]
    cmp     al, [rdi]
    jne     .ne
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .loop
.eq:
    mov     rax, 1
    ret
.ne:
    xor     rax, rax
    ret

;------------------------------------------------------------------
; derive_target - find the "+++ " header in the diff, strip [strip] path
; components, and copy the name into target_name. Jumps to the error path
; when no header is present.
;------------------------------------------------------------------
derive_target:
    mov     r9, diffbuf
.line:
    cmp     r9, r13
    jae     .none
    cmp     byte [r9], '+'
    jne     .next
    cmp     byte [r9 + 1], '+'
    jne     .next
    cmp     byte [r9 + 2], '+'
    jne     .next
    cmp     byte [r9 + 3], ' '
    jne     .next
    add     r9, 4                       ;past "+++ "
    jmp     .strip
.next:
    cmp     byte [r9], 10
    je      .advance
    inc     r9
    jmp     .next
.advance:
    inc     r9
    jmp     .line
.none:
    write   STDERR_FILENO, notarget_msg, notarget_len
    exit    1

.strip:
; r9 -> filename; drop [strip] leading components
    mov     rcx, [strip]
.drop:
    test    rcx, rcx
    jz      .copy
.seek:
    mov     al, [r9]
    cmp     al, 10
    je      .copy
    cmp     al, 9
    je      .copy
    cmp     al, 0
    je      .copy
    inc     r9
    cmp     al, '/'
    jne     .seek
    dec     rcx
    jmp     .drop
.copy:
    mov     rdi, target_name
.cp:
    mov     al, [r9]
    cmp     al, 10
    je      .term
    cmp     al, 9                       ;tab ends the name field
    je      .term
    test    al, al
    jz      .term
    mov     [rdi], al
    inc     rdi
    inc     r9
    jmp     .cp
.term:
    mov     byte [rdi], 0
    ret

;------------------------------------------------------------------
; slurp - read fd rdi into [rsi] up to rdx bytes; rax = byte count.
;------------------------------------------------------------------
slurp:
    mov     r10, rsi                    ;buffer base
    mov     r11, rdx                    ;capacity
    xor     r9, r9                      ;total
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
