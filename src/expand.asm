; src/expand.asm -- expand(1): convert tabs to spaces. -t N uses a uniform
; tab width; -t a,b,c uses an explicit list of tab stops (single spaces past
; the last one). Backspaces move the column back by one.

    %include "include/sysdefs.inc"

    %define BUFSZ 65536

section .bss
    in_buffer   resb BUFSZ
    out_buffer  resb BUFSZ
    stops       resq 256
    nstops      resq 1
    tabn        resq 1
    uniform     resb 1
    col         resq 1
    out_pos     resq 1
    fd          resq 1

section .text
global      _start

_start:
    mov         byte [uniform], 1
    mov         qword [tabn], 8
    mov         qword [nstops], 0
    mov         qword [col], 0
    mov         qword [out_pos], 0
    mov         qword [fd], STDIN_FILENO

    mov         r12, [rsp]              ;argc
    lea         r13, [rsp + 16]         ;&argv[1]
    dec         r12

parse:
    cmp         r12, 0
    je          run
    mov         rdi, [r13]
    cmp         byte [rdi], '-'
    jne         .file
    cmp         byte [rdi + 1], 0
    je          .file                   ;lone "-" is stdin
    cmp         byte [rdi + 1], 't'
    jne         .next                   ;ignore other options
    cmp         byte [rdi + 2], 0
    jne         .attached
    add         r13, 8                  ;"-t" LIST
    dec         r12
    mov         rdi, [r13]
    call        parse_tablist
    jmp         .next
.attached:
    lea         rdi, [rdi + 2]          ;"-tLIST"
    call        parse_tablist
    jmp         .next
.file:
    cmp         byte [rdi], '-'
    je          .next                   ;"-" -> keep stdin
    mov         rsi, rdi
    mov         rdi, STDIN_FILENO
    call        open_file
    mov         [fd], rax
.next:
    add         r13, 8
    dec         r12
    jmp         parse

run:
.read:
    mov         rax, SYS_READ
    mov         rdi, [fd]
    mov         rsi, in_buffer
    mov         rdx, BUFSZ
    syscall
    cmp         rax, 0
    jle         .eof
    mov         r14, rax                ;bytes read
    xor         rbx, rbx                ;index
.byte:
    cmp         rbx, r14
    jge         .read
    movzx       rax, byte [in_buffer + rbx]
    inc         rbx
    cmp         al, 9                   ;tab
    je          .tab
    cmp         al, 10                  ;newline
    je          .nl
    cmp         al, 8                   ;backspace
    je          .bs
    call        put_byte
    inc         qword [col]
    jmp         .byte
.tab:
    mov         rdi, [col]
    call        next_spaces             ;rax = spaces to emit
    add         [col], rax
    mov         rcx, rax
.tab_sp:
    mov         al, ' '
    call        put_byte
    dec         rcx
    jnz         .tab_sp
    jmp         .byte
.nl:
    mov         al, 10
    call        put_byte
    mov         qword [col], 0
    jmp         .byte
.bs:
    mov         al, 8
    call        put_byte
    cmp         qword [col], 0
    je          .byte
    dec         qword [col]
    jmp         .byte
.eof:
    call        flush
    exit        0

; next_spaces: rdi = column; rax = spaces to advance to the next tab stop
next_spaces:
    cmp         byte [uniform], 1
    jne         .list
    mov         rcx, [tabn]
    mov         rax, rdi
    xor         rdx, rdx
    div         rcx
    mov         rax, rcx
    sub         rax, rdx
    ret
.list:
    xor         rcx, rcx
.l:
    cmp         rcx, [nstops]
    jge         .past
    mov         rax, [stops + rcx*8]
    cmp         rax, rdi
    jle         .lnext
    sub         rax, rdi
    ret
.lnext:
    inc         rcx
    jmp         .l
.past:
    mov         rax, 1
    ret

; parse_tablist: rdi -> "N" or "a,b,c"; fill stops[]/nstops, set uniform mode
parse_tablist:
    xor         rcx, rcx
.num:
    xor         rax, rax
.d:
    movzx       rdx, byte [rdi]
    cmp         dl, '0'
    jb          .end
    cmp         dl, '9'
    ja          .end
    imul        rax, rax, 10
    sub         dl, '0'
    add         rax, rdx
    inc         rdi
    jmp         .d
.end:
    mov         [stops + rcx*8], rax
    inc         rcx
    cmp         byte [rdi], ','
    jne         .fin
    inc         rdi
    jmp         .num
.fin:
    mov         [nstops], rcx
    cmp         rcx, 1
    jne         .islist
    mov         rax, [stops]
    mov         [tabn], rax
    mov         byte [uniform], 1
    ret
.islist:
    mov         byte [uniform], 0
    ret

; put_byte: append al to out_buffer, flushing when near full
put_byte:
    push        rcx
    mov         rcx, [out_pos]
    mov         [out_buffer + rcx], al
    inc         rcx
    mov         [out_pos], rcx
    cmp         rcx, BUFSZ - 16
    jl          .ok
    call        flush
.ok:
    pop         rcx
    ret

; flush: write out_buffer to stdout, reset (preserves working registers)
flush:
    push        rax
    push        rbx
    push        rcx
    push        rdx
    push        rsi
    push        rdi
    push        r11
    mov         rdx, [out_pos]
    test        rdx, rdx
    jz          .empty
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, out_buffer
    syscall
    mov         qword [out_pos], 0
.empty:
    pop         r11
    pop         rdi
    pop         rsi
    pop         rdx
    pop         rcx
    pop         rbx
    pop         rax
    ret
