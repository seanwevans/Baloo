; src/sha1sum.asm -- compute a SHA-1 digest, coreutils output format.
; Usage: sha1sum [FILE]   (reads stdin when no FILE is given)

    %include "include/sysdefs.inc"

    %define RBUF_SIZE 65536

section .bss
    H        resd 5                     ;running hash state
    W        resd 80                    ;message schedule
    blk      resb 64                    ;current 64-byte block
    blkfill  resq 1                     ;bytes buffered in blk
    total    resq 1                     ;message length in bytes
    bitlen   resq 1                     ;big-endian bit length
    rbuf     resb RBUF_SIZE             ;read buffer
    hexbuf   resb 40                    ;hex digest text
    fname    resq 1                     ;displayed file name pointer
    fd       resq 1                     ;input file descriptor

section .data
sha_init:
    dd 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0
    hexchars db "0123456789abcdef"
    two_spaces db "  "
    dash db "-", 0
    newline db 10
    err_open db "sha1sum cannot open input", 10
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
    mov     r13, rax
    xor     r14, r14
.feed:
    cmp     r14, r13
    jge     .read_loop
    mov     al, [rbuf + r14]
    call    append_byte
    inc     r14
    jmp     .feed
.finish:
    call    sha_pad

    xor     rcx, rcx
    mov     rdi, hexbuf
.hword:
    mov     eax, [H + rcx*4]
    mov     rdx, 8
.hnib:
    rol     eax, 4
    mov     ebx, eax
    and     ebx, 0xf
    mov     bl, [hexchars + rbx]
    mov     [rdi], bl
    inc     rdi
    dec     rdx
    jnz     .hnib
    inc     rcx
    cmp     rcx, 5
    jl      .hword

    write   STDOUT_FILENO, hexbuf, 40
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
    mov     eax, [sha_init + rcx*4]
    mov     [H + rcx*4], eax
    inc     rcx
    cmp     rcx, 5
    jl      .l
    mov     qword [blkfill], 0
    mov     qword [total], 0
    ret

append_byte:
    push    rbx
    mov     rbx, [blkfill]
    mov     [blk + rbx], al
    inc     rbx
    cmp     rbx, 64
    jne     .store
    call    process_block
    xor     rbx, rbx
.store:
    mov     [blkfill], rbx
    pop     rbx
    ret

sha_pad:
    mov     rax, [total]
    shl     rax, 3
    bswap   rax
    mov     [bitlen], rax
    mov     al, 0x80
    call    append_byte
.pad:
    cmp     qword [blkfill], 56
    je      .len
    xor     al, al
    call    append_byte
    jmp     .pad
.len:
    xor     rcx, rcx
.lb:
    mov     al, [bitlen + rcx]
    call    append_byte
    inc     rcx
    cmp     rcx, 8
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

    xor     rcx, rcx
.load:
    mov     eax, [blk + rcx*4]
    bswap   eax
    mov     [W + rcx*4], eax
    inc     rcx
    cmp     rcx, 16
    jl      .load

    mov     rcx, 16
.sched:
    mov     eax, [W + rcx*4 - 12]
    xor     eax, [W + rcx*4 - 32]
    xor     eax, [W + rcx*4 - 56]
    xor     eax, [W + rcx*4 - 64]
    rol     eax, 1
    mov     [W + rcx*4], eax
    inc     rcx
    cmp     rcx, 80
    jl      .sched

    mov     r8d, [H + 0]                ;a
    mov     r9d, [H + 4]                ;b
    mov     r10d, [H + 8]               ;c
    mov     r11d, [H + 12]              ;d
    mov     r12d, [H + 16]              ;e

    xor     rbp, rbp
.round:
    cmp     rbp, 20
    jl      .phase1
    cmp     rbp, 40
    jl      .phase2
    cmp     rbp, 60
    jl      .phase3
    mov     eax, r9d
    xor     eax, r10d
    xor     eax, r11d
    mov     edx, 0xca62c1d6
    jmp     .have_fk
.phase1:
    mov     eax, r9d
    and     eax, r10d
    mov     ebx, r9d
    not     ebx
    and     ebx, r11d
    or      eax, ebx
    mov     edx, 0x5a827999
    jmp     .have_fk
.phase2:
    mov     eax, r9d
    xor     eax, r10d
    xor     eax, r11d
    mov     edx, 0x6ed9eba1
    jmp     .have_fk
.phase3:
    mov     eax, r9d
    and     eax, r10d
    mov     ebx, r9d
    and     ebx, r11d
    or      eax, ebx
    mov     ebx, r10d
    and     ebx, r11d
    or      eax, ebx
    mov     edx, 0x8f1bbcdc
.have_fk:
    mov     ebx, r8d
    rol     ebx, 5
    add     ebx, eax
    add     ebx, r12d
    add     ebx, edx
    add     ebx, [W + rbp*4]
    mov     r12d, r11d
    mov     r11d, r10d
    mov     ecx, r9d
    rol     ecx, 30
    mov     r10d, ecx
    mov     r9d, r8d
    mov     r8d, ebx
    inc     rbp
    cmp     rbp, 80
    jl      .round

    add     [H + 0], r8d
    add     [H + 4], r9d
    add     [H + 8], r10d
    add     [H + 12], r11d
    add     [H + 16], r12d

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
