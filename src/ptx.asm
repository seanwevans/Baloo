; src/ptx.asm -- produce a permuted (KWIC) index of the input words.
; Usage: ptx [FILE]   (reads stdin when no FILE is given)
;
; Matches coreutils ptx's default fixed-width format (line width 72):
; keywords are sorted; the preceding context is right-justified in a 36
; column field, then a 3-space gap, then the keyword and following words.
; Inputs whose context fits within the field are reproduced exactly;
; truncation/line-wrap (the long-context "/" form) and ptx options are not
; implemented.

    %include "include/sysdefs.inc"

    %define ARENA_SIZE 1048576
    %define MAX_WORDS 131072
    %define OUTBUF_SIZE 262144
    %define HALF 36
    %define GAP 3

section .bss
    arena    resb ARENA_SIZE
    word_off resq MAX_WORDS
    word_len resq MAX_WORDS
    entry    resd MAX_WORDS
    nwords   resq 1
    inlen    resq 1
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

; tokenize into whitespace-separated words
    xor     r12, r12                    ;word count
    xor     rcx, rcx                    ;scan position
.tok:
    cmp     rcx, [inlen]
    jge     .tok_done
    mov     al, [arena + rcx]
    call    is_space
    jc      .skip_ws
    cmp     r12, MAX_WORDS
    jae     .tok_done
    mov     [word_off + r12*8], rcx
    mov     r13, rcx
.word_end:
    cmp     rcx, [inlen]
    jge     .word_fin
    mov     al, [arena + rcx]
    call    is_space
    jc      .word_fin
    inc     rcx
    jmp     .word_end
.word_fin:
    mov     rax, rcx
    sub     rax, r13
    mov     [word_len + r12*8], rax
    mov     [entry + r12*4], r12d
    inc     r12
    jmp     .tok
.skip_ws:
    inc     rcx
    jmp     .tok
.tok_done:
    mov     [nwords], r12

    call    heapsort

; emit one KWIC line per keyword (sorted)
    xor     r12, r12                    ;output index k
.out_loop:
    cmp     r12, [nwords]
    jge     .done
    mov     r13d, [entry + r12*4]       ;i = keyword word index

    xor     r10, r10                    ;before length
    xor     r9, r9
.blen:
    cmp     r9, r13
    jge     .blen_done
    add     r10, [word_len + r9*8]
    inc     r9
    jmp     .blen
.blen_done:
    test    r13, r13
    jz      .pad
    add     r10, r13
    dec     r10                         ;single spaces between the i words
.pad:
    mov     rax, HALF
    sub     rax, r10
    jns     .pad_ok
    xor     rax, rax
.pad_ok:
    mov     rdi, rax
    call    emit_spaces

    xor     r9, r9
.bemit:
    cmp     r9, r13
    jge     .bemit_done
    test    r9, r9
    jz      .b_noskip
    mov     al, ' '
    call    out_char
.b_noskip:
    mov     rdi, r9
    call    emit_word
    inc     r9
    jmp     .bemit
.bemit_done:
    mov     rdi, GAP
    call    emit_spaces

    mov     r9, r13
.aemit:
    cmp     r9, [nwords]
    jge     .aemit_done
    cmp     r9, r13
    je      .a_noskip
    mov     al, ' '
    call    out_char
.a_noskip:
    mov     rdi, r9
    call    emit_word
    inc     r9
    jmp     .aemit
.aemit_done:
    mov     al, 10
    call    out_char
    inc     r12
    jmp     .out_loop
.done:
    call    out_flush
    exit    0

; is_space: CF=1 if al is whitespace (space/tab/newline/CR), else CF=0
is_space:
    cmp     al, ' '
    je      .yes
    cmp     al, 9
    je      .yes
    cmp     al, 10
    je      .yes
    cmp     al, 13
    je      .yes
    clc
    ret
.yes:
    stc
    ret

; emit_word: rdi = word index -> emit its bytes (register-safe)
emit_word:
    push    rax
    push    rbx
    push    rcx
    push    rsi
    mov     rsi, [word_off + rdi*8]
    mov     rcx, [word_len + rdi*8]
    xor     rbx, rbx
.l:
    cmp     rbx, rcx
    jge     .d
    mov     al, [arena + rsi + rbx]
    call    out_char
    inc     rbx
    jmp     .l
.d:
    pop     rsi
    pop     rcx
    pop     rbx
    pop     rax
    ret

; emit_spaces: rdi = count (register-safe)
emit_spaces:
    push    rax
    push    rcx
    mov     rcx, rdi
    test    rcx, rcx
    jle     .d
.l:
    mov     al, ' '
    call    out_char
    dec     rcx
    jnz     .l
.d:
    pop     rcx
    pop     rax
    ret

; word_cmp: rdi = word index a, rsi = word index b -> rax -1/0/1
;   byte-wise; equal keywords break the tie by input order. preserves all
;   registers except rax.
word_cmp:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    mov     r8, [word_off + rdi*8]
    mov     rcx, [word_len + rdi*8]
    mov     r9, [word_off + rsi*8]
    mov     rdx, [word_len + rsi*8]
    mov     rbx, rcx
    cmp     rdx, rbx
    jae     .have_min
    mov     rbx, rdx
.have_min:
    xor     r10, r10
.cmp_loop:
    cmp     r10, rbx
    jge     .prefix_eq
    movzx   eax, byte [arena + r8 + r10]
    movzx   r11d, byte [arena + r9 + r10]
    cmp     eax, r11d
    jb      .less
    ja      .greater
    inc     r10
    jmp     .cmp_loop
.prefix_eq:
    cmp     rcx, rdx
    jb      .less
    ja      .greater
    cmp     rdi, rsi
    jb      .less
    ja      .greater
    xor     rax, rax
    jmp     .ret
.less:
    mov     rax, -1
    jmp     .ret
.greater:
    mov     rax, 1
.ret:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; sift_down: rdi = root, rsi = heap size (max-heap on entry[] via word_cmp)
sift_down:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
.loop:
    lea     r13, [rbx*2 + 1]
    cmp     r13, r12
    jge     .done
    lea     r14, [r13 + 1]
    cmp     r14, r12
    jge     .have_child
    mov     edi, [entry + r13*4]
    mov     esi, [entry + r14*4]
    call    word_cmp
    test    rax, rax
    jns     .have_child
    mov     r13, r14
.have_child:
    mov     edi, [entry + rbx*4]
    mov     esi, [entry + r13*4]
    call    word_cmp
    test    rax, rax
    jns     .done
    mov     edi, [entry + rbx*4]
    mov     esi, [entry + r13*4]
    mov     [entry + rbx*4], esi
    mov     [entry + r13*4], edi
    mov     rbx, r13
    jmp     .loop
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

heapsort:
    mov     r15, [nwords]
    cmp     r15, 1
    jle     .done
    mov     rbx, r15
    shr     rbx, 1
    dec     rbx
.build:
    mov     rdi, rbx
    mov     rsi, r15
    call    sift_down
    test    rbx, rbx
    jz      .build_done
    dec     rbx
    jmp     .build
.build_done:
    mov     rbx, r15
    dec     rbx
.sort_loop:
    mov     edi, [entry]
    mov     esi, [entry + rbx*4]
    mov     [entry], esi
    mov     [entry + rbx*4], edi
    xor     rdi, rdi
    mov     rsi, rbx
    call    sift_down
    dec     rbx
    jnz     .sort_loop
.done:
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
