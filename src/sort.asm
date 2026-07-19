; src/sort.asm -- sort lines of text (byte-wise, ascending; C-locale order).
; Usage: sort [FILE...]   ("-" or no file means stdin)
; Concatenates the inputs, sorts the lines lexicographically by unsigned
; byte value (a shorter line sorts before a longer one with the same
; prefix), and writes them newline-terminated. Matches `LC_ALL=C sort`.

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
    mov     r12, rax
    dec     r12                         ;file operand count
    mov     rbx, rsp                    ;&argv[1]
    xor     r13, r13                    ;file index
    xor     r14, r14                    ;arena offset
.open_loop:
    cmp     r13, r12
    jge     .slurped
    mov     rdi, [rbx + r13*8]
    cmp     byte [rdi], '-'
    jne     .open_named
    cmp     byte [rdi + 1], 0
    je      .use_stdin_fd
    jmp     .bad_option                 ;an unrecognised option
.open_named:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .next_file
    mov     r15, rax
    jmp     .slurp_file
.use_stdin_fd:
    xor     r15, r15
.slurp_file:
    mov     rax, SYS_READ
    mov     rdi, r15
    lea     rsi, [arena + r14]
    mov     rdx, ARENA_SIZE
    sub     rdx, r14
    syscall
    test    rax, rax
    jle     .close_file
    add     r14, rax
    jmp     .slurp_file
.close_file:
    test    r15, r15
    jz      .next_file
    mov     rax, SYS_CLOSE
    mov     rdi, r15
    syscall
.next_file:
    inc     r13
    jmp     .open_loop

.bad_option:
    exit    2

.stdin:
    xor     r14, r14
.stdin_loop:
    mov     rax, SYS_READ
    xor     rdi, rdi
    lea     rsi, [arena + r14]
    mov     rdx, ARENA_SIZE
    sub     rdx, r14
    syscall
    test    rax, rax
    jle     .slurped
    add     r14, rax
    jmp     .stdin_loop

.slurped:
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

    call    heapsort

; output sorted lines
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

; line_cmp: rdi = index a, rsi = index b
;   returns rax = -1 / 0 / 1 by unsigned byte order (shorter prefix < longer)
;   preserves every register except rax
line_cmp:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    mov     r8, [line_off + rdi*8]
    mov     rcx, [line_len + rdi*8]
    mov     r9, [line_off + rsi*8]
    mov     rdx, [line_len + rsi*8]
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

; sift_down: rdi = root, rsi = heap size (max-heap on idx[] via line_cmp)
sift_down:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ;root
    mov     r12, rsi                    ;size
.loop:
    lea     r13, [rbx*2 + 1]            ;left child
    cmp     r13, r12
    jge     .done
    lea     r14, [r13 + 1]              ;right child
    cmp     r14, r12
    jge     .have_child
    mov     edi, [idx + r13*4]
    mov     esi, [idx + r14*4]
    call    line_cmp
    test    rax, rax
    jns     .have_child                 ;left >= right -> keep left
    mov     r13, r14                    ;right child is larger
.have_child:
    mov     edi, [idx + rbx*4]
    mov     esi, [idx + r13*4]
    call    line_cmp
    test    rax, rax
    jns     .done                       ;root >= child -> heap ok
    mov     edi, [idx + rbx*4]
    mov     esi, [idx + r13*4]
    mov     [idx + rbx*4], esi
    mov     [idx + r13*4], edi
    mov     rbx, r13
    jmp     .loop
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; heapsort: sort idx[0..nlines) ascending
heapsort:
    mov     r15, [nlines]
    cmp     r15, 1
    jle     .done
    mov     rbx, r15
    shr     rbx, 1
    dec     rbx                         ;i = nlines/2 - 1
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
    dec     rbx                         ;end = nlines - 1
.sort_loop:
    mov     edi, [idx]
    mov     esi, [idx + rbx*4]
    mov     [idx], esi
    mov     [idx + rbx*4], edi
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
