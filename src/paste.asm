; src/paste.asm -- merge corresponding lines of files, TAB-separated.
; Usage: paste [FILE...]   ("-" or no file means stdin)

    %include "include/sysdefs.inc"

    %define ARENA_SIZE 8388608
    %define MAX_FILES 64
    %define OUTBUF_SIZE 65536

section .bss
    arena   resb ARENA_SIZE             ;all input concatenated
    fstart  resq MAX_FILES              ;per-file start offset in arena
    fend    resq MAX_FILES              ;per-file end offset
    fcur    resq MAX_FILES              ;per-file read cursor
    nfiles  resq 1
    outbuf  resb OUTBUF_SIZE
    outlen  resq 1

section .text
global _start

_start:
    mov     qword [outlen], 0
    pop     rax                         ;argc
    pop     rdi                         ;argv[0] discarded
    cmp     rax, 2
    jl      .stdin_only
    mov     r12, rax
    dec     r12                         ;number of file operands
    mov     [nfiles], r12
    mov     rbx, rsp                    ;&argv[1]
    xor     r13, r13                    ;file index
    xor     r14, r14                    ;arena offset
.open_loop:
    cmp     r13, r12
    jge     .merge
    mov     rdi, [rbx + r13*8]          ;filename
    cmp     byte [rdi], '-'
    jne     .open_named
    cmp     byte [rdi + 1], 0
    je      .use_stdin_fd
.open_named:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    mov     r15, rax
    test    rax, rax
    jns     .slurp
    xor     r15, r15                    ;on error, fall back to an empty read
    jmp     .record
.use_stdin_fd:
    xor     r15, r15
.slurp:
    mov     [fstart + r13*8], r14
.slurp_loop:
    mov     rax, SYS_READ
    mov     rdi, r15
    lea     rsi, [arena + r14]
    mov     rdx, ARENA_SIZE
    sub     rdx, r14
    syscall
    test    rax, rax
    jle     .record
    add     r14, rax
    jmp     .slurp_loop
.record:
    mov     [fend + r13*8], r14
    mov     rax, [fstart + r13*8]
    mov     [fcur + r13*8], rax
    inc     r13
    jmp     .open_loop

.stdin_only:
    mov     qword [nfiles], 1
    mov     qword [fstart], 0
    xor     r14, r14
.stdin_loop:
    mov     rax, SYS_READ
    xor     rdi, rdi
    lea     rsi, [arena + r14]
    mov     rdx, ARENA_SIZE
    sub     rdx, r14
    syscall
    test    rax, rax
    jle     .stdin_done
    add     r14, rax
    jmp     .stdin_loop
.stdin_done:
    mov     [fend], r14
    mov     qword [fcur], 0

.merge:
.row:
    xor     r13, r13
.any:
    cmp     r13, [nfiles]
    jge     .done
    mov     rsi, [fcur + r13*8]
    cmp     rsi, [fend + r13*8]
    jl      .have_row
    inc     r13
    jmp     .any
.have_row:
    xor     r13, r13
.col:
    cmp     r13, [nfiles]
    jge     .end_row
    test    r13, r13
    jz      .no_sep
    mov     al, 9                       ;TAB between columns
    call    out_char
.no_sep:
    mov     rsi, [fcur + r13*8]
    mov     rdi, [fend + r13*8]
    cmp     rsi, rdi
    jge     .col_next
.emit_line:
    cmp     rsi, rdi
    jge     .save_cur
    mov     al, [arena + rsi]
    inc     rsi
    cmp     al, 10
    je      .save_cur
    call    out_char
    jmp     .emit_line
.save_cur:
    mov     [fcur + r13*8], rsi
.col_next:
    inc     r13
    jmp     .col
.end_row:
    mov     al, 10
    call    out_char
    jmp     .row
.done:
    call    out_flush
    exit    0

; out_char: append al to the output buffer (flushes when full)
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

; out_flush: write the buffered output (register-transparent)
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
