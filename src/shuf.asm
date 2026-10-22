; src/shuf.asm -- write a random permutation of the input lines.
; Usage: shuf [FILE]   (reads stdin when no FILE is given)
;
; The input and the line tables live in memory sized to the input
; (include/slurp.inc), so there is no fixed cap on bytes or lines.
; r15 holds the input base and r8/r9/r10 the line_off/line_len/idx tables.

    %include "include/sysdefs.inc"
    %include "include/slurp.inc"

    %define OUTBUF_SIZE 65536

section .bss
    nlines   resq 1
    inlen    resq 1
    randbuf  resq 1
    outbuf   resb OUTBUF_SIZE
    outlen   resq 1

section .text
global _start

_start:
    mov     qword [outlen], 0
    pop     rax                         ;argc
    pop     rdi                         ;argv[0] discarded
    cmp     rax, 2
    jl      .stdin
    pop     rsi                         ;argv[1] = file name
    mov     rax, SYS_OPEN
    mov     rdi, rsi
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .stdin
    mov     rdi, rax
    jmp     .slurp
.stdin:
    xor     rdi, rdi
.slurp:
    call    slurp                       ;rax = input, rdx = length
    mov     r15, rax
    mov     [inlen], rdx

; size the tables: one entry per newline plus an unterminated last line
    xor     rbx, rbx
    xor     rcx, rcx
.count:
    cmp     rcx, [inlen]
    jge     .counted
    cmp     byte [r15 + rcx], 10
    jne     .count_adv
    inc     rbx
.count_adv:
    inc     rcx
    jmp     .count
.counted:
    inc     rbx
    lea     rdi, [rbx * 8]
    call    xalloc
    mov     r12, rax                    ;line_off (xalloc clobbers r8-r10)
    lea     rdi, [rbx * 8]
    call    xalloc
    mov     r13, rax                    ;line_len
    lea     rdi, [rbx * 4]
    call    xalloc
    mov     r10, rax                    ;idx (dword line numbers)
    mov     r8, r12
    mov     r9, r13

; build the line table
    xor     r12, r12                    ;line count
    xor     r13, r13                    ;current line start
    xor     rcx, rcx                    ;scan position
.scan:
    cmp     rcx, [inlen]
    jge     .scan_done
    mov     al, [r15 + rcx]
    cmp     al, 10
    jne     .scan_adv
    mov     [r8 + r12*8], r13
    mov     rax, rcx
    sub     rax, r13
    mov     [r9 + r12*8], rax
    mov     [r10 + r12*4], r12d
    inc     r12
    lea     r13, [rcx + 1]
.scan_adv:
    inc     rcx
    jmp     .scan
.scan_done:
    mov     rax, [inlen]
    cmp     r13, rax
    jge     .have_lines
    mov     [r8 + r12*8], r13
    sub     rax, r13
    mov     [r9 + r12*8], rax
    mov     [r10 + r12*4], r12d
    inc     r12
.have_lines:
    mov     [nlines], r12

; Fisher-Yates shuffle of idx[]
    mov     rax, [nlines]
    cmp     rax, 1
    jle     .output
    mov     r12, rax
    dec     r12
.shuffle:
    lea     rdi, [r12 + 1]
    call    rand_below
    mov     ecx, [r10 + r12*4]
    mov     edx, [r10 + rax*4]
    mov     [r10 + r12*4], edx
    mov     [r10 + rax*4], ecx
    dec     r12
    jnz     .shuffle

.output:
    xor     r12, r12
.out_loop:
    cmp     r12, [nlines]
    jge     .done
    mov     eax, [r10 + r12*4]
    mov     rsi, [r8 + rax*8]
    mov     rcx, [r9 + rax*8]
    add     rsi, r15                    ;absolute start of the line
    xor     rbx, rbx
.out_bytes:
    cmp     rbx, rcx
    jge     .out_nl
    mov     al, [rsi + rbx]
    call    out_char
    inc     rbx
    jmp     .out_bytes
.out_nl:
    mov     al, 10
    call    out_char
    inc     r12
    jmp     .out_loop
.done:
    call    out_flush
    exit    0

; rand_below: rdi = N (>0) -> rax = uniform-ish value in [0, N)
rand_below:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    r11
    mov     rbx, rdi
    mov     rax, SYS_GETRANDOM
    mov     rdi, randbuf
    mov     rsi, 8
    xor     rdx, rdx
    syscall
    mov     rax, [randbuf]
    xor     rdx, rdx
    div     rbx
    mov     rax, rdx
    pop     r11
    pop     rsi
    pop     rdx
    pop     rcx
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
