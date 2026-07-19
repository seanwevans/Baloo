; src/tail.asm -- tail(1): print the last part of input.
; Usage: tail [-n [+]N] [-c [+]N] [-N] [FILE]   (no FILE or "-" = stdin).
;
; The whole input is buffered, so line/byte counting from the end and the
; "+N" from-the-start forms are handled uniformly by slicing the buffer. The
; last of -n/-c/-N wins. Defaults to the last ten lines.

    %include "include/sysdefs.inc"

    %define BUFCAP (8 * 1024 * 1024)

section .bss
    buf         resb BUFCAP
    fname       resq 1
    mode        resb 1                  ;'l' lines, 'c' chars
    fromstart   resb 1
    kcount      resq 1
    inlen       resq 1
    fd          resq 1

section .text
global _start

_start:
    mov     byte [mode], 'l'
    mov     byte [fromstart], 0
    mov     qword [kcount], 10
    mov     qword [fname], 0

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    je      run
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .file
    cmp     byte [rdi + 1], 0
    je      .file                       ;lone "-" -> stdin
    movzx   eax, byte [rdi + 1]
    cmp     al, '0'
    jb      .opts
    cmp     al, '9'
    ja      .opts
;"-N" shorthand: last N lines
    mov     byte [mode], 'l'
    mov     byte [fromstart], 0
    lea     rdi, [rdi + 1]
    call    atou
    mov     [kcount], rax
    jmp     .nextarg
.opts:
    lea     rsi, [rdi + 1]
.oc:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .nextarg
    cmp     al, 'n'
    je      .nc
    cmp     al, 'c'
    je      .nc
    inc     rsi                         ;ignore -f/-v/-q/unknown
    jmp     .oc
.nc:
    cmp     al, 'c'
    jne     .isline
    mov     byte [mode], 'c'
    jmp     .value
.isline:
    mov     byte [mode], 'l'
.value:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .haveval
    add     r13, 8                      ;value in the next argv
    dec     r12
    mov     rsi, [r13]
.haveval:
    mov     byte [fromstart], 0
    cmp     byte [rsi], '+'
    jne     .notplus
    mov     byte [fromstart], 1
    inc     rsi
    jmp     .doatou
.notplus:
    cmp     byte [rsi], '-'
    jne     .doatou
    inc     rsi
.doatou:
    mov     rdi, rsi
    call    atou
    mov     [kcount], rax
    jmp     .nextarg
.file:
    mov     [fname], rdi
.nextarg:
    add     r13, 8
    dec     r12
    jmp     parse

run:
    mov     qword [fd], STDIN_FILENO
    cmp     qword [fname], 0
    je      .read
    mov     rdi, [fname]
    cmp     byte [rdi], '-'
    jne     .open
    cmp     byte [rdi + 1], 0
    je      .read                       ;"-" -> stdin
.open:
    mov     rax, SYS_OPEN
    mov     rdi, [fname]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      done
    mov     [fd], rax
.read:
    xor     r15, r15                    ;bytes read
.rl:
    mov     rdx, BUFCAP
    sub     rdx, r15
    jz      .rdone
    mov     rax, SYS_READ
    mov     rdi, [fd]
    lea     rsi, [buf + r15]
    syscall
    test    rax, rax
    jle     .rdone
    add     r15, rax
    jmp     .rl
.rdone:
    mov     [inlen], r15

;compute the start offset of the slice into r14
    cmp     byte [mode], 'c'
    je      chars
    cmp     byte [fromstart], 1
    je      lines_from_start

; last K lines
lines_from_end:
mov     r14, 0                      ;default: whole buffer
    mov     rcx, [inlen]
    test    rcx, rcx
    jz      emit
    mov     rsi, rcx
    dec     rsi                         ;i = len-1
    cmp     byte [buf + rsi], WHITESPACE_NL
    jne     .scan
    dec     rsi                         ;skip a trailing newline
.scan:
    xor     r8, r8                      ;newlines seen
.loop:
    cmp     rsi, 0
    jl      emit
    cmp     byte [buf + rsi], WHITESPACE_NL
    jne     .dec
    inc     r8
    cmp     r8, [kcount]
    jne     .dec
    lea     r14, [rsi + 1]
    jmp     emit
.dec:
    dec     rsi
    jmp     .loop

; from line K (1-based)
lines_from_start:
mov     r14, [inlen]                ;default: nothing
    cmp     qword [kcount], 1
    jbe     .whole
    mov     rdx, [kcount]
    dec     rdx                         ;newlines to pass
    xor     rsi, rsi                    ;i
    xor     r8, r8                      ;newlines seen
.loop:
    cmp     rsi, [inlen]
    jge     emit
    cmp     byte [buf + rsi], WHITESPACE_NL
    jne     .next
    inc     r8
    cmp     r8, rdx
    jne     .next
    lea     r14, [rsi + 1]
    jmp     emit
.next:
    inc     rsi
    jmp     .loop
.whole:
    xor     r14, r14
    jmp     emit

chars:
    cmp     byte [fromstart], 1
    je      .fromstart
;last K bytes
    mov     r14, [inlen]
    sub     r14, [kcount]
    jns     emit
    xor     r14, r14
    jmp     emit
.fromstart:
;from byte K (1-based)
    mov     r14, [kcount]
    test    r14, r14
    jz      .zero
    dec     r14
.zero:
    cmp     r14, [inlen]
    jbe     emit
    mov     r14, [inlen]

emit:
    mov     rdx, [inlen]
    sub     rdx, r14
    jle     done
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    lea     rsi, [buf + r14]
    syscall
done:
    xor     rdi, rdi
    mov     rax, SYS_EXIT
    syscall

; atou: rdi -> unsigned decimal in rax.
atou:
    xor     rax, rax
.l:
    movzx   rcx, byte [rdi]
    sub     cl, '0'
    cmp     cl, 9
    ja      .done
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .l
.done:
    ret
