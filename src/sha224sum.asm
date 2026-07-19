; src/sha224sum.asm -- compute a SHA-224 digest, coreutils output format.
; Usage: sha224sum [FILE]   (reads stdin when no FILE is given)

    %include "include/sysdefs.inc"

    %define RBUF_SIZE 65536

section .bss
    H        resd 8                     ;running hash state
    W        resd 64                    ;message schedule
    blk      resb 64                    ;current 64-byte block
    blkfill  resq 1                     ;bytes buffered in blk
    total    resq 1                     ;message length in bytes
    bitlen   resq 1                     ;message length in bits (big-endian temp)
    rbuf     resb RBUF_SIZE             ;read buffer
    hexbuf   resb 64                    ;hex digest text
    fname    resq 1                     ;pointer to the displayed file name
    fd       resq 1                     ;input file descriptor
    n_ops    resq 1
    op_idx   resq 1
    argv1    resq 1
    exit_status resq 1

section .data
sha_init:
    dd 0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939
    dd 0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4
sha_k:
    dd 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
    dd 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    dd 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
    dd 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    dd 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
    dd 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    dd 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
    dd 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    dd 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
    dd 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    dd 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
    dd 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    dd 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
    dd 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    dd 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
    dd 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    hexchars db "0123456789abcdef"
    two_spaces db "  "
    dash db "-", 0
    newline db 10
err_open db "sha224sum: cannot open input", 10
    err_open_len equ $ - err_open

section .text
global _start

_start:
    mov     rax, [rsp]                  ;argc
    lea     rcx, [rsp + 16]             ;&argv[1]
    mov     [argv1], rcx
    dec     rax                         ;operand count
    mov     [n_ops], rax
    mov     qword [op_idx], 0
    mov     qword [exit_status], 0
    test    rax, rax
    jz      .stdin_only
.loop:
    mov     rax, [op_idx]
    cmp     rax, [n_ops]
    jge     .done
    mov     rcx, [argv1]
    mov     rsi, [rcx + rax*8]
    call    hash_one
    inc     qword [op_idx]
    jmp     .loop
.done:
    mov     rdi, [exit_status]
    mov     rax, SYS_EXIT
    syscall
.stdin_only:
    mov     rsi, dash
    call    hash_one
    mov     rdi, [exit_status]
    mov     rax, SYS_EXIT
    syscall

; hash_one: rsi -> file name ("-" = stdin); hash it and print "HEX  NAME"
hash_one:
    mov     [fname], rsi
    cmp     byte [rsi], '-'
    jne     .open
    cmp     byte [rsi + 1], 0
    jne     .open
    mov     qword [fd], 0
    jmp     .run
.open:
    mov     rax, SYS_OPEN
    mov     rdi, rsi
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .open_failed
    mov     [fd], rax
.run:
    call    sha224_init
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
    mov     r12, rax                    ;bytes available
    xor     r13, r13                    ;index
.feed:
    cmp     r13, r12
    jge     .read_loop
    mov     al, [rbuf + r13]
    call    append_byte
    inc     r13
    jmp     .feed
.finish:
    call    sha224_final

; render H as 64 lowercase hex characters
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
    cmp     rcx, 7
    jl      .hword

    write   STDOUT_FILENO, hexbuf, 56
    write   STDOUT_FILENO, two_spaces, 2
    mov     rsi, [fname]
    call    strlen                      ;length -> rbx
    write   STDOUT_FILENO, [fname], rbx
    write   STDOUT_FILENO, newline, 1

    cmp     qword [fd], 0
    je      .ret
    mov     rax, SYS_CLOSE
    mov     rdi, [fd]
    syscall
.ret:
    ret
.open_failed:
    write   STDERR_FILENO, err_open, err_open_len
    mov     qword [exit_status], 1
    ret

; sha224_init: load the initial hash state and reset counters
sha224_init:
    xor     rcx, rcx
.l:
    mov     eax, [sha_init + rcx*4]
    mov     [H + rcx*4], eax
    inc     rcx
    cmp     rcx, 8
    jl      .l
    mov     qword [blkfill], 0
    mov     qword [total], 0
    ret

; append_byte: add al to the block buffer, hashing the block when full
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

; sha224_final: apply SHA-224 padding and process the last block(s)
sha224_final:
    mov     rax, [total]
    shl     rax, 3
    bswap   rax
    mov     [bitlen], rax               ;big-endian bit length
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

; process_block: fold the 64-byte block in blk into H (register-transparent)
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
    mov     eax, [blk + rcx*4]
    bswap   eax
    mov     [W + rcx*4], eax
    inc     rcx
    cmp     rcx, 16
    jl      .load

    mov     rcx, 16
.sched:
    mov     eax, [W + rcx*4 - 60]
    mov     ebx, eax
    ror     eax, 7
    ror     ebx, 18
    xor     eax, ebx
    mov     ebx, [W + rcx*4 - 60]
    shr     ebx, 3
    xor     eax, ebx
    mov     ebx, [W + rcx*4 - 8]
    mov     edx, ebx
    ror     ebx, 17
    ror     edx, 19
    xor     ebx, edx
    mov     edx, [W + rcx*4 - 8]
    shr     edx, 10
    xor     ebx, edx
    add     eax, ebx
    add     eax, [W + rcx*4 - 64]
    add     eax, [W + rcx*4 - 28]
    mov     [W + rcx*4], eax
    inc     rcx
    cmp     rcx, 64
    jl      .sched

    mov     r8d, [H + 0]
    mov     r9d, [H + 4]
    mov     r10d, [H + 8]
    mov     r11d, [H + 12]
    mov     r12d, [H + 16]
    mov     r13d, [H + 20]
    mov     r14d, [H + 24]
    mov     r15d, [H + 28]

    xor     rbp, rbp
.round:
    mov     eax, r12d
    ror     eax, 6
    mov     ebx, r12d
    ror     ebx, 11
    xor     eax, ebx
    mov     ebx, r12d
    ror     ebx, 25
    xor     eax, ebx
    mov     ebx, r12d
    and     ebx, r13d
    mov     ecx, r12d
    not     ecx
    and     ecx, r14d
    xor     ebx, ecx
    add     eax, ebx
    add     eax, r15d
    mov     ecx, [sha_k + rbp*4]
    add     eax, ecx
    mov     ecx, [W + rbp*4]
    add     eax, ecx
    mov     ebx, r8d
    ror     ebx, 2
    mov     ecx, r8d
    ror     ecx, 13
    xor     ebx, ecx
    mov     ecx, r8d
    ror     ecx, 22
    xor     ebx, ecx
    mov     ecx, r8d
    and     ecx, r9d
    mov     edx, r8d
    and     edx, r10d
    xor     ecx, edx
    mov     edx, r9d
    and     edx, r10d
    xor     ecx, edx
    add     ebx, ecx
    mov     r15d, r14d
    mov     r14d, r13d
    mov     r13d, r12d
    mov     r12d, r11d
    add     r12d, eax
    mov     r11d, r10d
    mov     r10d, r9d
    mov     r9d, r8d
    mov     r8d, eax
    add     r8d, ebx
    inc     rbp
    cmp     rbp, 64
    jl      .round

    add     [H + 0], r8d
    add     [H + 4], r9d
    add     [H + 8], r10d
    add     [H + 12], r11d
    add     [H + 16], r12d
    add     [H + 20], r13d
    add     [H + 24], r14d
    add     [H + 28], r15d

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
