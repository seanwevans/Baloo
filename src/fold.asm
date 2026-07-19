; src/fold.asm -- fold(1): wrap input lines to a given width.
; Usage: fold [-bs] [-w WIDTH] [FILE...]   ("-" = stdin, default width 80).
;
; A line is buffered until adding the next character would exceed the width;
; then a newline is inserted. Column accounting honours tabs (advance to the
; next multiple of eight), backspace (column back one) and carriage return
; (column to zero) unless -b is given, in which case every byte counts as one.
; With -s the break is moved back to the last blank on the line.

    %include "include/sysdefs.inc"

    %define INSZ  65536
    %define LINESZ 65536

section .bss
    inbuf       resb INSZ
    linebuf     resb LINESZ
    curc        resb 1
    outnl       resb 1
    width       resq 1
    llen        resq 1                  ;bytes buffered on the current line
    col         resq 1                  ;display column of the buffered line
    lastbl      resq 1                  ;index just past the last blank, or -1
    bflag       resb 1
    sflag       resb 1
    filename    resq 1
    fd          resq 1

section .text
global _start

_start:
    mov     qword [width], 80
    mov     qword [col], 0
    mov     qword [llen], 0
    mov     qword [lastbl], -1
    mov     qword [fd], STDIN_FILENO
    mov     byte [bflag], 0
    mov     byte [sflag], 0
    mov     qword [filename], 0

    mov     r12, [rsp]                  ;argc
    lea     rbx, [rsp + 8]              ;&argv[0]
    mov     r15, 1                      ;argv index

parse:
    cmp     r15, r12
    jge     open_input
    mov     rdi, [rbx + r15*8]
    inc     r15
    cmp     byte [rdi], '-'
    jne     .file
    cmp     byte [rdi + 1], 0
    je      parse                       ;lone "-" -> stdin
    lea     rsi, [rdi + 1]
.opt:
    movzx   eax, byte [rsi]
    test    al, al
    jz      parse
    cmp     al, 'b'
    je      .setb
    cmp     al, 's'
    je      .sets
    cmp     al, 'w'
    je      .setw
    inc     rsi
    jmp     .opt
.setb:
    mov     byte [bflag], 1
    inc     rsi
    jmp     .opt
.sets:
    mov     byte [sflag], 1
    inc     rsi
    jmp     .opt
.setw:
    inc     rsi
    cmp     byte [rsi], 0
    jne     .w_here
    cmp     r15, r12
jge     parse                       ;-w with no argument: ignore
    mov     rsi, [rbx + r15*8]
    inc     r15
.w_here:
    mov     rdi, rsi
    call    atoi
    test    rax, rax
jle     parse                       ;non-positive width: keep default
    mov     [width], rax
    jmp     parse
.file:
    mov     [filename], rdi
    jmp     parse

open_input:
    cmp     qword [filename], 0
    je      process_input
    mov     rax, SYS_OPEN
    mov     rdi, [filename]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      exit_program
    mov     [fd], rax

process_input:
.read:
    mov     rax, SYS_READ
    mov     rdi, [fd]
    mov     rsi, inbuf
    mov     rdx, INSZ
    syscall
    test    rax, rax
    jle     .eof
    mov     r13, rax                    ;chunk length
    xor     r14, r14
.ch:
    cmp     r14, r13
    jge     .read
    mov     al, [inbuf + r14]
    mov     [curc], al
    inc     r14
    call    handle_char
    jmp     .ch
.eof:
    call    write_line                  ;flush a trailing partial line, no NL
    cmp     qword [fd], STDIN_FILENO
    je      exit_program
    mov     rax, SYS_CLOSE
    mov     rdi, [fd]
    syscall

exit_program:
    exit    0

; handle_char: consume the byte in [curc]. Preserves r13/r14 (the input loop
; cursor); syscalls only clobber rcx/r11 so those survive across writes.
handle_char:
    movzx   eax, byte [curc]
    cmp     al, WHITESPACE_NL
    je      .nl
    call    calc_newcol                 ;rcx = column after this char
    cmp     rcx, [width]
    jbe     .append
    cmp     qword [llen], 0
je      .append                     ;empty line: nothing to break
    cmp     byte [sflag], 1
    jne     .hard
    cmp     qword [lastbl], 0
    jle     .hard
    call    soft_break
    jmp     .after_break
.hard:
    call    write_line
    mov     byte [outnl], WHITESPACE_NL
    write   STDOUT_FILENO, outnl, 1
    mov     qword [llen], 0
    mov     qword [col], 0
    mov     qword [lastbl], -1
.after_break:
    call    calc_newcol                 ;recompute against the reset column
.append:
    mov     rax, [llen]
    movzx   edx, byte [curc]
    mov     [linebuf + rax], dl
    inc     qword [llen]
    mov     [col], rcx
    cmp     dl, ' '
    je      .blank
    cmp     dl, 9
    je      .blank
    ret
.blank:
    mov     rax, [llen]
    mov     [lastbl], rax
    ret
.nl:
    call    write_line
    mov     byte [outnl], WHITESPACE_NL
    write   STDOUT_FILENO, outnl, 1
    mov     qword [llen], 0
    mov     qword [col], 0
    mov     qword [lastbl], -1
    ret

; calc_newcol: column reached after appending [curc] to the current line.
; Result in rcx; clobbers rax.
calc_newcol:
    movzx   eax, byte [curc]
    cmp     byte [bflag], 1
    je      .plain
    cmp     al, 9                       ;tab
    je      .tab
    cmp     al, 8                       ;backspace
    je      .bs
    cmp     al, 13                      ;carriage return
    je      .cr
.plain:
    mov     rcx, [col]
    inc     rcx
    ret
.tab:
    mov     rcx, [col]
    and     rcx, -8
    add     rcx, 8
    ret
.bs:
    mov     rcx, [col]
    test    rcx, rcx
    jz      .zero
    dec     rcx
.zero:
    ret
.cr:
    xor     rcx, rcx
    ret

; write_line: emit linebuf[0..llen] with no trailing newline.
write_line:
    mov     rdx, [llen]
    test    rdx, rdx
    jz      .empty
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, linebuf
    syscall
.empty:
    ret

; soft_break: emit linebuf[0..lastbl] + newline, shift the remainder to the
; front of the buffer, recompute its column and clear lastbl.
soft_break:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, linebuf
    mov     rdx, [lastbl]
    syscall
    mov     byte [outnl], WHITESPACE_NL
    write   STDOUT_FILENO, outnl, 1
    mov     rsi, [lastbl]               ;src index
    xor     rdi, rdi                    ;dst index
.mv:
    mov     rax, [llen]
    cmp     rsi, rax
    jge     .moved
    mov     al, [linebuf + rsi]
    mov     [linebuf + rdi], al
    inc     rsi
    inc     rdi
    jmp     .mv
.moved:
    mov     [llen], rdi
    call    recompute_col
    mov     qword [lastbl], -1
    ret

; recompute_col: recompute [col] by walking linebuf[0..llen]. Clobbers rax,
; rcx, r8.
recompute_col:
    xor     rcx, rcx
    xor     r8, r8
.l:
    cmp     r8, [llen]
    jge     .done
    movzx   eax, byte [linebuf + r8]
    cmp     byte [bflag], 1
    je      .plain
    cmp     al, 9
    je      .tab
    cmp     al, 8
    je      .bs
    cmp     al, 13
    je      .cr
.plain:
    inc     rcx
    jmp     .next
.tab:
    and     rcx, -8
    add     rcx, 8
    jmp     .next
.bs:
    test    rcx, rcx
    jz      .next
    dec     rcx
    jmp     .next
.cr:
    xor     rcx, rcx
.next:
    inc     r8
    jmp     .l
.done:
    mov     [col], rcx
    ret

; atoi: rdi -> unsigned decimal, result in rax. Clobbers rcx.
atoi:
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
