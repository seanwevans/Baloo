; src/shuf.asm -- write a random permutation of the input lines.
; Usage: shuf [FILE]   (reads stdin when no FILE is given)

    %include "include/sysdefs.inc"

    %define ARENA_SIZE 8388608
    %define MAX_LINES 1048576
    %define OUTBUF_SIZE 65536

section .bss
    arena    resb ARENA_SIZE
    line_off resq MAX_LINES
    line_len resq MAX_LINES
    idx      resd MAX_LINES
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
    mov     r15, rax
    jmp     .slurp
.stdin:
    xor     r15, r15
.slurp:
    xor     r14, r14
.slurp_loop:
    mov     rax, SYS_READ
    mov     rdi, r15
    lea     rsi, [arena + r14]
    mov     rdx, ARENA_SIZE
    sub     rdx, r14
    syscall
    test    rax, rax
    jle     .slurp_done
    add     r14, rax
    jmp     .slurp_loop
.slurp_done:
    mov     [inlen], r14

; build the line table
    xor     r12, r12                    ;line count
    xor     r13, r13                    ;current line start
    xor     rcx, rcx                    ;scan position
.scan:
    cmp     rcx, [inlen]
    jge     .scan_done
    mov     al, [arena + rcx]
    cmp     al, 10
    jne     .scan_adv
    cmp     r12, MAX_LINES
    jae     .scan_adv
    mov     [line_off + r12*8], r13
    mov     rax, rcx
    sub     rax, r13
    mov     [line_len + r12*8], rax
    mov     [idx + r12*4], r12d
    inc     r12
    lea     r13, [rcx + 1]
.scan_adv:
    inc     rcx
    jmp     .scan
.scan_done:
    mov     rax, [inlen]
    cmp     r13, rax
    jge     .have_lines
    cmp     r12, MAX_LINES
    jae     .have_lines
    mov     [line_off + r12*8], r13
    sub     rax, r13
    mov     [line_len + r12*8], rax
    mov     [idx + r12*4], r12d
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
    mov     ecx, [idx + r12*4]
    mov     edx, [idx + rax*4]
    mov     [idx + r12*4], edx
    mov     [idx + rax*4], ecx
    dec     r12
    jnz     .shuffle

.output:
    xor     r12, r12
.out_loop:
    cmp     r12, [nlines]
    jge     .done
    mov     eax, [idx + r12*4]
    mov     rsi, [line_off + rax*8]
    mov     rcx, [line_len + rax*8]
    xor     rbx, rbx
.out_bytes:
    cmp     rbx, rcx
    jge     .out_nl
    mov     al, [arena + rsi + rbx]
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
