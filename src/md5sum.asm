; src/md5sum.asm -- md5sum(1): print or (-c) verify MD5 digests.
; MD5 is computed in-process (RFC 1321).

    %include "include/sysdefs.inc"

    %define BUFFER_SIZE 65536

section .bss
    buffer      resb BUFFER_SIZE        ;hash feed buffer
    listbuf     resb BUFFER_SIZE        ;checklist file contents
    namebuf     resb 4096               ;NUL-terminated file name from a list line
    exphash     resb 64                 ;expected hash from a list line
    digest      resb 16                 ;raw MD5 result
    hex_output  resb 32                 ;hex digest text
    listlen     resq 1
    c_flag      resb 1
    status_flag resb 1
    exit_status resq 1
    ops         resq 256                ;file operand pointers
    nops        resq 1

section .data
    hex_chars   db "0123456789abcdef"
    two_spaces  db "  "
    dash        db "-", 0
colon_ok    db ": OK", WHITESPACE_NL
    colon_ok_len equ $ - colon_ok
colon_fail  db ": FAILED", WHITESPACE_NL
    colon_fail_len equ $ - colon_fail
    newline     db WHITESPACE_NL
err_open    db "md5sum: cannot open input", WHITESPACE_NL
    err_open_len equ $ - err_open

md5_K:
    dd 0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee
    dd 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501
    dd 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be
    dd 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821
    dd 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa
    dd 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8
    dd 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed
    dd 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a
    dd 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c
    dd 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70
    dd 0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05
    dd 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665
    dd 0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039
    dd 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1
    dd 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1
    dd 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
md5_s:
    db 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22
    db 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20
    db 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23
    db 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21

section .text
global _start

_start:
    mov     byte [c_flag], 0
    mov     byte [status_flag], 0
    mov     qword [nops], 0
    mov     qword [exit_status], 0

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    je      dispatch
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .operand
    cmp     byte [rdi + 1], 0
    je      .operand                    ;"-" is a stdin operand
    cmp     byte [rdi + 1], '-'
    je      .longopt
;short option bundle
    lea     rdi, [rdi + 1]
.short:
    movzx   eax, byte [rdi]
    test    al, al
    je      .next
    cmp     al, 'c'
    je      .set_c
    inc     rdi                         ;ignore -b, -t, etc.
    jmp     .short
.set_c:
    mov     byte [c_flag], 1
    inc     rdi
    jmp     .short
.longopt:
;--status / --quiet / others
    cmp     byte [rdi + 2], 's'
    jne     .next
    mov     byte [status_flag], 1
    jmp     .next
.operand:
    mov     rcx, [nops]
    mov     [ops + rcx*8], rdi
    inc     rcx
    mov     [nops], rcx
.next:
    add     r13, 8
    dec     r12
    jmp     parse

dispatch:
    cmp     byte [c_flag], 1
    je      check_mode

; ---------------- normal mode: print digests ----------------
    cmp     qword [nops], 0
    jne     .have
    mov     qword [ops], dash           ;no operands -> stdin
    mov     qword [nops], 1
.have:
    xor     rbx, rbx
.loop:
    cmp     rbx, [nops]
    jge     .done
    mov     [op_scratch], rbx
    mov     rsi, [ops + rbx*8]
    call    hash_name
    cmp     rax, -1
    je      .fail
;print "HEX  NAME"
    write   STDOUT_FILENO, hex_output, 32
    write   STDOUT_FILENO, two_spaces, 2
    mov     rbx, [op_scratch]
    mov     rsi, [ops + rbx*8]
    call    strlen                      ;length -> rbx
    mov     rax, [op_scratch]
    mov     rsi, [ops + rax*8]
    mov     rdx, rbx
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    write   STDOUT_FILENO, newline, 1
    jmp     .cont
.fail:
    write   STDERR_FILENO, err_open, err_open_len
    mov     qword [exit_status], 1
.cont:
    mov     rbx, [op_scratch]
    inc     rbx
    jmp     .loop
.done:
    mov     rdi, [exit_status]
    mov     rax, SYS_EXIT
    syscall

; ---------------- check mode (-c) ----------------
check_mode:
    cmp     qword [nops], 0
    jne     .have
    mov     qword [ops], dash
    mov     qword [nops], 1
.have:
    xor     r15, r15                    ;checklist index
    xor     r14, r14                    ;count of verified lines
.files:
    cmp     r15, [nops]
    jge     .finish
    mov     rsi, [ops + r15*8]
    call    read_list                   ;fill listbuf/listlen (rax=-1 on fail)
    cmp     rax, -1
    je      .file_fail
    xor     rbx, rbx                    ;position in listbuf
.lines:
    cmp     rbx, [listlen]
    jge     .file_next
    call    parse_line                  ;rax=1 if a valid line was parsed
    test    rax, rax
    jz      .lines
    inc     r14
;compute the named file's digest and compare
    mov     rsi, namebuf
    call    hash_name
    cmp     rax, -1
    je      .line_bad
    mov     rsi, exphash
    call    cmp_hash                    ;rax=0 on match
    test    rax, rax
    jnz     .line_bad
;OK
    cmp     byte [status_flag], 1
    je      .lines
    mov     rsi, namebuf
    call    strlen
    write   STDOUT_FILENO, namebuf, rbx
    write   STDOUT_FILENO, colon_ok, colon_ok_len
    jmp     .relines
.line_bad:
    mov     qword [exit_status], 1
    cmp     byte [status_flag], 1
    je      .relines
    mov     rsi, namebuf
    call    strlen
    write   STDOUT_FILENO, namebuf, rbx
    write   STDOUT_FILENO, colon_fail, colon_fail_len
.relines:
    mov     rbx, [line_pos]             ;restore parser position
    jmp     .lines
.file_fail:
    mov     qword [exit_status], 1
.file_next:
    inc     r15
    jmp     .files
.finish:
    test    r14, r14
    jnz     .exit                       ;no valid lines is an error
    mov     qword [exit_status], 1
.exit:
    mov     rdi, [exit_status]
    mov     rax, SYS_EXIT
    syscall

; parse_line: parse one line of listbuf starting at rbx. On a valid
; "HASH<ws>[*]NAME" line, copy the hash into exphash and the name into
; namebuf, set rax=1 and leave [line_pos] at the next line. Otherwise rax=0.
parse_line:
    mov     [line_pos], rbx
;read the hash up to whitespace
    xor     rcx, rcx
.hash:
    cmp     rbx, [listlen]
    jge     .invalid
    movzx   eax, byte [listbuf + rbx]
    cmp     al, WHITESPACE_NL
    je      .invalid
    cmp     al, WHITESPACE_SPACE
    je      .after_hash
    cmp     al, WHITESPACE_TAB
    je      .after_hash
    cmp     rcx, 63
    jge     .skip_rest
    mov     [exphash + rcx], al
    inc     rcx
    inc     rbx
    jmp     .hash
.after_hash:
    mov     byte [exphash + rcx], 0
;skip whitespace and one optional '*'
.skip_ws:
    cmp     rbx, [listlen]
    jge     .invalid
    movzx   eax, byte [listbuf + rbx]
    cmp     al, WHITESPACE_SPACE
    je      .ws_adv
    cmp     al, WHITESPACE_TAB
    je      .ws_adv
    jmp     .maybe_star
.ws_adv:
    inc     rbx
    jmp     .skip_ws
.maybe_star:
    cmp     al, '*'
    jne     .name
    inc     rbx
.name:
    xor     rcx, rcx
.ncopy:
    cmp     rbx, [listlen]
    jge     .name_done
    movzx   eax, byte [listbuf + rbx]
    cmp     al, WHITESPACE_NL
    je      .name_done
    cmp     rcx, 4094
    jge     .name_adv
    mov     [namebuf + rcx], al
    inc     rcx
.name_adv:
    inc     rbx
    jmp     .ncopy
.name_done:
    mov     byte [namebuf + rcx], 0
    inc     rbx                         ;consume the newline
    mov     [line_pos], rbx
    test    rcx, rcx
    jz      .invalid                    ;empty name
    mov     rax, 1
    ret
.skip_rest:
;hash too long: skip to end of line, treat as invalid
    cmp     rbx, [listlen]
    jge     .invalid
    cmp     byte [listbuf + rbx], WHITESPACE_NL
    je      .sr_nl
    inc     rbx
    jmp     .skip_rest
.sr_nl:
    inc     rbx
.invalid:
;advance to the next line if we stalled
    cmp     rbx, [listlen]
    jge     .inv_done
    cmp     byte [listbuf + rbx - 1], WHITESPACE_NL
    je      .inv_done
.inv_scan:
    cmp     rbx, [listlen]
    jge     .inv_done
    mov     al, [listbuf + rbx]
    inc     rbx
    cmp     al, WHITESPACE_NL
    jne     .inv_scan
.inv_done:
    mov     [line_pos], rbx
    xor     rax, rax
    ret

; read_list: rsi -> checklist name ("-" = stdin); read it into listbuf,
; set [listlen]. rax = -1 on open failure.
read_list:
    cmp     byte [rsi], '-'
    jne     .open
    cmp     byte [rsi + 1], 0
    jne     .open
    xor     r8, r8                      ;stdin fd
    jmp     .read
.open:
    mov     rdi, rsi
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fail
    mov     r8, rax
.read:
    xor     r9, r9                      ;bytes read so far
.rl:
    mov     rdx, BUFFER_SIZE
    sub     rdx, r9
    jle     .done
    mov     rax, SYS_READ
    mov     rdi, r8
    lea     rsi, [listbuf + r9]
    syscall
    cmp     rax, 0
    jle     .done
    add     r9, rax
    jmp     .rl
.done:
    mov     [listlen], r9
    test    r8, r8
    jz      .ret
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
.ret:
    xor     rax, rax
    ret
.fail:
    mov     rax, -1
    ret

; hash_name: rsi -> file name ("-" = stdin); fill hex_output with its MD5.
; rax = -1 if the file could not be opened.
hash_name:
    cmp     byte [rsi], '-'
    jne     .open
    cmp     byte [rsi + 1], 0
    jne     .open
    xor     rdi, rdi                    ;stdin
    call    hash_fd
    xor     rax, rax
    ret
.open:
    mov     rdi, rsi
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fail
    mov     rdi, rax
    push    rdi
    call    hash_fd
    pop     rdi
    mov     rax, SYS_CLOSE
    syscall
    xor     rax, rax
    ret
.fail:
    mov     rax, -1
    ret

; hash_fd: rdi = input fd; compute MD5 (in-process) and render to hex_output.
hash_fd:
    push    r12
    push    r13
    push    r14
    mov     r14, rdi                    ;input fd
    call    md5_init
.feed:
    mov     rax, SYS_READ
    mov     rdi, r14
    mov     rsi, buffer
    mov     rdx, BUFFER_SIZE
    syscall
    cmp     rax, 0
    jle     .done
    add     [md5_total], rax
    mov     r13, rax
    xor     r12, r12
.fb:
    cmp     r12, r13
    jge     .feed
    mov     al, [buffer + r12]
    call    md5_append
    inc     r12
    jmp     .fb
.done:
    call    md5_pad
;the state (4 little-endian dwords) is the digest; render it as hex
    lea     rdi, [md5_state]
    lea     rsi, [hex_output]
    mov     rcx, 16
.hex:
    movzx   rax, byte [rdi]
    mov     rdx, rax
    shr     rdx, 4
    mov     bl, [hex_chars + rdx]
    mov     [rsi], bl
    and     al, 0xf
    mov     bl, [hex_chars + rax]
    mov     [rsi + 1], bl
    inc     rdi
    add     rsi, 2
    loop    .hex
    pop     r14
    pop     r13
    pop     r12
    ret

; md5_init: reset the MD5 state and counters
md5_init:
    mov     dword [md5_state + 0], 0x67452301
    mov     dword [md5_state + 4], 0xefcdab89
    mov     dword [md5_state + 8], 0x98badcfe
    mov     dword [md5_state + 12], 0x10325476
    mov     qword [md5_blkfill], 0
    mov     qword [md5_total], 0
    ret

; md5_append: al = byte; buffer it and process a full 64-byte block
md5_append:
    push    rbx
    mov     rbx, [md5_blkfill]
    mov     [md5_blk + rbx], al
    inc     rbx
    cmp     rbx, 64
    jne     .store
    call    md5_block
    xor     rbx, rbx
.store:
    mov     [md5_blkfill], rbx
    pop     rbx
    ret

; md5_pad: append the 0x80 terminator, zero padding and 64-bit LE bit length
md5_pad:
    mov     al, 0x80
    call    md5_append
.pad:
    cmp     qword [md5_blkfill], 56
    je      .len
    xor     al, al
    call    md5_append
    jmp     .pad
.len:
    mov     rax, [md5_total]
    shl     rax, 3
    mov     [md5_bitlen], rax
    xor     rcx, rcx
.lb:
    mov     al, [md5_bitlen + rcx]
    call    md5_append
    inc     rcx
    cmp     rcx, 8
    jl      .lb
    ret

; md5_block: process the 64 bytes in md5_blk into md5_state
md5_block:
    push    rbp
    push    rbx
    mov     r8d, [md5_state + 0]        ;A
    mov     r9d, [md5_state + 4]        ;B
    mov     r10d, [md5_state + 8]       ;C
    mov     r11d, [md5_state + 12]      ;D
    xor     ebp, ebp                    ;i
.round:
    cmp     ebp, 16
    jl      .r1
    cmp     ebp, 32
    jl      .r2
    cmp     ebp, 48
    jl      .r3
;round 4: F = C xor (B or (not D)); g = (7*i) mod 16
    mov     eax, r11d
    not     eax
    or      eax, r9d
    xor     eax, r10d
    mov     ecx, ebp
    imul    ecx, ecx, 7
    and     ecx, 15
    jmp     .have
.r1:
;round 1: F = (B and C) or ((not B) and D); g = i
    mov     eax, r9d
    and     eax, r10d
    mov     edx, r9d
    not     edx
    and     edx, r11d
    or      eax, edx
    mov     ecx, ebp
    jmp     .have
.r2:
;round 2: F = (D and B) or ((not D) and C); g = (5*i + 1) mod 16
    mov     eax, r11d
    and     eax, r9d
    mov     edx, r11d
    not     edx
    and     edx, r10d
    or      eax, edx
    mov     ecx, ebp
    imul    ecx, ecx, 5
    inc     ecx
    and     ecx, 15
    jmp     .have
.r3:
;round 3: F = B xor C xor D; g = (3*i + 5) mod 16
    mov     eax, r9d
    xor     eax, r10d
    xor     eax, r11d
    mov     ecx, ebp
    imul    ecx, ecx, 3
    add     ecx, 5
    and     ecx, 15
.have:
    add     eax, r8d                    ;+ A
    add     eax, [md5_K + ebp*4]        ;+ K[i]
    mov     edx, [md5_blk + ecx*4]      ;+ M[g] (little-endian word)
    add     eax, edx
    movzx   ecx, byte [md5_s + ebp]     ;rotate left by s[i]
    rol     eax, cl
    add     eax, r9d                    ;+ B  -> new B
    mov     r8d, r11d                   ;A = old D
    mov     r11d, r10d                  ;D = old C
    mov     r10d, r9d                   ;C = old B
    mov     r9d, eax                    ;B = new B
    inc     ebp
    cmp     ebp, 64
    jl      .round
    add     [md5_state + 0], r8d
    add     [md5_state + 4], r9d
    add     [md5_state + 8], r10d
    add     [md5_state + 12], r11d
    pop     rbx
    pop     rbp
    ret

; cmp_hash: rsi -> expected hash; rax=0 if it equals hex_output (32 chars)
cmp_hash:
    xor     rcx, rcx
.l:
    cmp     rcx, 32
    jge     .eq
    mov     al, [hex_output + rcx]
    mov     dl, [rsi + rcx]
    cmp     al, dl
    jne     .ne
    inc     rcx
    jmp     .l
.eq:
    xor     rax, rax
    ret
.ne:
    mov     rax, 1
    ret

section .bss
    op_scratch  resq 1
    line_pos    resq 1
    md5_state   resd 4
    md5_blk     resb 64
    md5_blkfill resq 1
    md5_total   resq 1
    md5_bitlen  resq 1
