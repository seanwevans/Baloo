; src/sha512sum.asm -- compute a SHA-512 digest, coreutils output format.
; Usage: sha512sum [FILE]   (reads stdin when no FILE is given)

    %include "include/sysdefs.inc"

    %define RBUF_SIZE 65536

section .bss
    H        resq 8                     ;running hash state
    W        resq 80                    ;message schedule
    blk      resb 128                   ;current 128-byte block
    blkfill  resq 1                     ;bytes buffered in blk
    total    resq 1                     ;message length in bytes
    lenbuf   resb 16                    ;128-bit big-endian length
    rbuf     resb RBUF_SIZE             ;read buffer
    hexbuf   resb 128                   ;hex digest text
    fname    resq 1                     ;displayed file name pointer
    fd       resq 1                     ;input file descriptor

section .data
sha_init:
    dq 0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1
    dq 0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
sha_k:
    dq 0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc
    dq 0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118
    dq 0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2
    dq 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694
    dq 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65
    dq 0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5
    dq 0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4
    dq 0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70
    dq 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df
    dq 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b
    dq 0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30
    dq 0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8
    dq 0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8
    dq 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3
    dq 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec
    dq 0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b
    dq 0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178
    dq 0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b
    dq 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c
    dq 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817
    hexchars db "0123456789abcdef"
    two_spaces db "  "
    dash db "-", 0
    newline db 10
    err_open db "sha512sum cannot open input", 10
    err_open_len equ $ - err_open

section .text
global _start

_start:
    pop     rax                         ;argc
    pop     rbx                         ;argv[0] discarded
    cmp     rax, 2
    jl      .use_stdin
    pop     rsi                         ;argv[1] = file name
    mov     [fname], rsi
    mov     rax, SYS_OPEN
    mov     rdi, rsi
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .open_failed
    mov     [fd], rax
    jmp     .run
.use_stdin:
    mov     qword [fd], 0
    mov     qword [fname], dash
.run:
    call    sha_init_state
.read_loop:
    mov     rax, SYS_READ
    mov     rdi, [fd]
    mov     rsi, rbuf
    mov     rdx, RBUF_SIZE
    syscall
    test    rax, rax
    js      .open_failed
    jz      .finish
    add     [total], rax
    mov     r12, rax
    xor     r13, r13
.feed:
    cmp     r13, r12
    jge     .read_loop
    mov     al, [rbuf + r13]
    call    append_byte
    inc     r13
    jmp     .feed
.finish:
    call    sha_pad

    xor     rcx, rcx
    mov     rdi, hexbuf
.hword:
    mov     rax, [H + rcx*8]
    mov     rdx, 16
.hnib:
    rol     rax, 4
    mov     rbx, rax
    and     rbx, 0xf
    mov     bl, [hexchars + rbx]
    mov     [rdi], bl
    inc     rdi
    dec     rdx
    jnz     .hnib
    inc     rcx
    cmp     rcx, 8
    jl      .hword

    write   STDOUT_FILENO, hexbuf, 128
    write   STDOUT_FILENO, two_spaces, 2
    mov     rsi, [fname]
    call    strlen
    write   STDOUT_FILENO, [fname], rbx
    write   STDOUT_FILENO, newline, 1
    exit    0

.open_failed:
    write   STDERR_FILENO, err_open, err_open_len
    exit    1

sha_init_state:
    xor     rcx, rcx
.l:
    mov     rax, [sha_init + rcx*8]
    mov     [H + rcx*8], rax
    inc     rcx
    cmp     rcx, 8
    jl      .l
    mov     qword [blkfill], 0
    mov     qword [total], 0
    ret

append_byte:
    push    rbx
    mov     rbx, [blkfill]
    mov     [blk + rbx], al
    inc     rbx
    cmp     rbx, 128
    jne     .store
    call    process_block
    xor     rbx, rbx
.store:
    mov     [blkfill], rbx
    pop     rbx
    ret

sha_pad:
    xor     rax, rax
    mov     [lenbuf], rax
    mov     rax, [total]
    shl     rax, 3
    bswap   rax
    mov     [lenbuf + 8], rax
    mov     al, 0x80
    call    append_byte
.pad:
    cmp     qword [blkfill], 112
    je      .len
    xor     al, al
    call    append_byte
    jmp     .pad
.len:
    xor     rcx, rcx
.lb:
    mov     al, [lenbuf + rcx]
    call    append_byte
    inc     rcx
    cmp     rcx, 16
    jl      .lb
    ret

process_block:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rbp
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15

    xor     rcx, rcx
.load:
    mov     rax, [blk + rcx*8]
    bswap   rax
    mov     [W + rcx*8], rax
    inc     rcx
    cmp     rcx, 16
    jl      .load

    mov     rcx, 16
.sched:
    mov     rax, [W + rcx*8 - 120]
    mov     rbx, rax
    ror     rax, 1
    ror     rbx, 8
    xor     rax, rbx
    mov     rbx, [W + rcx*8 - 120]
    shr     rbx, 7
    xor     rax, rbx
    mov     rbx, [W + rcx*8 - 16]
    mov     rdx, rbx
    ror     rbx, 19
    ror     rdx, 61
    xor     rbx, rdx
    mov     rdx, [W + rcx*8 - 16]
    shr     rdx, 6
    xor     rbx, rdx
    add     rax, rbx
    add     rax, [W + rcx*8 - 128]
    add     rax, [W + rcx*8 - 56]
    mov     [W + rcx*8], rax
    inc     rcx
    cmp     rcx, 80
    jl      .sched

    mov     r8, [H + 0]
    mov     r9, [H + 8]
    mov     r10, [H + 16]
    mov     r11, [H + 24]
    mov     r12, [H + 32]
    mov     r13, [H + 40]
    mov     r14, [H + 48]
    mov     r15, [H + 56]

    xor     rbp, rbp
.round:
    mov     rax, r12
    ror     rax, 14
    mov     rbx, r12
    ror     rbx, 18
    xor     rax, rbx
    mov     rbx, r12
    ror     rbx, 41
    xor     rax, rbx
    mov     rbx, r12
    and     rbx, r13
    mov     rcx, r12
    not     rcx
    and     rcx, r14
    xor     rbx, rcx
    add     rax, rbx
    add     rax, r15
    mov     rcx, [sha_k + rbp*8]
    add     rax, rcx
    mov     rcx, [W + rbp*8]
    add     rax, rcx
    mov     rbx, r8
    ror     rbx, 28
    mov     rcx, r8
    ror     rcx, 34
    xor     rbx, rcx
    mov     rcx, r8
    ror     rcx, 39
    xor     rbx, rcx
    mov     rcx, r8
    and     rcx, r9
    mov     rdx, r8
    and     rdx, r10
    xor     rcx, rdx
    mov     rdx, r9
    and     rdx, r10
    xor     rcx, rdx
    add     rbx, rcx
    mov     r15, r14
    mov     r14, r13
    mov     r13, r12
    mov     r12, r11
    add     r12, rax
    mov     r11, r10
    mov     r10, r9
    mov     r9, r8
    mov     r8, rax
    add     r8, rbx
    inc     rbp
    cmp     rbp, 80
    jl      .round

    add     [H + 0], r8
    add     [H + 8], r9
    add     [H + 16], r10
    add     [H + 24], r11
    add     [H + 32], r12
    add     [H + 40], r13
    add     [H + 48], r14
    add     [H + 56], r15

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rbp
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret
