; src/base64.asm -- base64(1): encode (default) or decode (-d) stdin or a
; file, wrapping encoded output every -w N columns (default 76, 0 = no wrap).

    %include "include/sysdefs.inc"

    %define INSIZE 1048576
    %define OUTSIZE 2097152

section .bss
    inbuf       resb INSIZE
    outbuf      resb OUTSIZE
    dec_table   resb 256
    inlen       resq 1
    wrap        resq 1
    d_flag      resb 1

section .data
    base64_table db BASE64_TABLE

section .text
global      _start

_start:
    mov         byte [d_flag], 0
    mov         qword [wrap], 76

    mov         r12, [rsp]              ;argc
    lea         r13, [rsp + 16]         ;&argv[1]
    dec         r12                     ;operand count

opt_loop:
    cmp         r12, 0
    je          input_stdin
    mov         rdi, [r13]
    cmp         byte [rdi], '-'
    jne         input_file
    cmp         byte [rdi + 1], 0
    je          input_file              ;lone "-" is stdin
    inc         rdi
.char:
    movzx       eax, byte [rdi]
    test        al, al
    je          .next
    cmp         al, 'd'
    je          .set_d
    cmp         al, 'w'
    je          .set_w
    inc         rdi                     ;ignore unknown option letters
    jmp         .char
.set_d:
    mov         byte [d_flag], 1
    inc         rdi
    jmp         .char
.set_w:
    inc         rdi
    cmp         byte [rdi], 0           ;-wN or -w N
    jne         .w_here
    add         r13, 8
    dec         r12
    mov         rdi, [r13]
.w_here:
    call        parse_uint
    mov         [wrap], rax
    jmp         .next
.next:
    add         r13, 8
    dec         r12
    jmp         opt_loop

input_file:
    mov         rdi, [r13]
    mov         rax, SYS_OPEN
    mov         rsi, O_RDONLY
    xor         rdx, rdx
    syscall
    test        rax, rax
    js          exit_error
    mov         rdi, rax
    call        read_all
    jmp         build

input_stdin:
    mov         rdi, STDIN_FILENO
    call        read_all

build:
;build the decode table (base64 char -> 6-bit value, else 0xFF)
    xor         rcx, rcx
.zero:
    mov         byte [dec_table + rcx], 0xFF
    inc         rcx
    cmp         rcx, 256
    jl          .zero
    xor         rcx, rcx
.fill:
    cmp         rcx, 64
    jge         .dispatch
    movzx       rax, byte [base64_table + rcx]
    mov         [dec_table + rax], cl
    inc         rcx
    jmp         .fill
.dispatch:
    cmp         byte [d_flag], 1
    je          decode
    jmp         encode

; ---------------- encode ----------------
encode:
    xor         rbx, rbx                ;input index
    xor         r15, r15                ;output index
    xor         r10, r10                ;column
.blk:
    mov         rax, [inlen]
    sub         rax, rbx
    jle         .fin
    mov         r9, rax                 ;remaining bytes
    xor         r8, r8
    movzx       rdx, byte [inbuf + rbx]
    shl         rdx, 16
    or          r8, rdx
    cmp         r9, 1
    je          .n1
    movzx       rdx, byte [inbuf + rbx + 1]
    shl         rdx, 8
    or          r8, rdx
    cmp         r9, 2
    je          .n2
    movzx       rdx, byte [inbuf + rbx + 2]
    or          r8, rdx
    mov         r11, 3
    jmp         .emit4
.n2:
    mov         r11, 2
    jmp         .emit4
.n1:
    mov         r11, 1
.emit4:
    mov         rdx, r8
    shr         rdx, 18
    and         rdx, 0x3f
    mov         al, [base64_table + rdx]
    call        emit_wc
    mov         rdx, r8
    shr         rdx, 12
    and         rdx, 0x3f
    mov         al, [base64_table + rdx]
    call        emit_wc
    cmp         r11, 2
    jl          .c2pad
    mov         rdx, r8
    shr         rdx, 6
    and         rdx, 0x3f
    mov         al, [base64_table + rdx]
    jmp         .c2emit
.c2pad:
    mov         al, '='
.c2emit:
    call        emit_wc
    cmp         r11, 3
    jl          .c3pad
    mov         rdx, r8
    and         rdx, 0x3f
    mov         al, [base64_table + rdx]
    jmp         .c3emit
.c3pad:
    mov         al, '='
.c3emit:
    call        emit_wc
    add         rbx, 3
    jmp         .blk
.fin:
    mov         rcx, [wrap]
    test        rcx, rcx
    jz          .write
    test        r10, r10
    jz          .write
    mov         byte [outbuf + r15], WHITESPACE_NL
    inc         r15
.write:
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, outbuf
    mov         rdx, r15
    syscall
    exit        0

; emit_wc: append al to outbuf, inserting a newline every [wrap] columns
emit_wc:
    mov         rcx, [wrap]
    test        rcx, rcx
    jz          .store
    cmp         r10, rcx
    jne         .store
    mov         byte [outbuf + r15], WHITESPACE_NL
    inc         r15
    xor         r10, r10
.store:
    mov         [outbuf + r15], al
    inc         r15
    inc         r10
    ret

; ---------------- decode ----------------
decode:
    xor         rbx, rbx                ;input index
    xor         r15, r15                ;output index
    xor         r8, r8                  ;bit accumulator
    xor         r9, r9                  ;bits held
.dl:
    cmp         rbx, [inlen]
    jge         .dfin
    movzx       rax, byte [inbuf + rbx]
    inc         rbx
    movzx       rdx, byte [dec_table + rax]
    cmp         dl, 0xFF
    je          .dl                     ;skip whitespace/'='/invalid
    shl         r8, 6
    or          r8, rdx
    add         r9, 6
    cmp         r9, 8
    jl          .dl
    sub         r9, 8
    mov         rax, r8
    mov         rcx, r9
    shr         rax, cl
    and         rax, 0xFF
    mov         [outbuf + r15], al
    inc         r15
    mov         rax, 1                  ;keep only the low r9 bits of r8
    shl         rax, cl
    dec         rax
    and         r8, rax
    jmp         .dl
.dfin:
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, outbuf
    mov         rdx, r15
    syscall
    exit        0

; read_all: rdi = fd; read up to INSIZE bytes into inbuf, store [inlen]
read_all:
    xor         r14, r14
.loop:
    mov         rdx, INSIZE
    sub         rdx, r14
    jle         .done
    mov         rax, SYS_READ
    lea         rsi, [inbuf + r14]
    syscall
    cmp         rax, 0
    jle         .done
    add         r14, rax
    jmp         .loop
.done:
    mov         [inlen], r14
    ret

; parse_uint: rdi -> decimal digits, result in rax
parse_uint:
    xor         rax, rax
.loop:
    movzx       rdx, byte [rdi]
    cmp         dl, '0'
    jb          .done
    cmp         dl, '9'
    ja          .done
    imul        rax, rax, 10
    sub         dl, '0'
    add         rax, rdx
    inc         rdi
    jmp         .loop
.done:
    ret

exit_error:
    exit        1
