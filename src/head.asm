; src/head.asm -- head(1): output the first part of files.
; Options: -n NUM (lines), -c NUM (bytes), -NUM (lines), -v (headers),
; -q (no headers), and "-"/no operand meaning stdin. The last of -n/-c wins.
; Reads a byte at a time so a following consumer sees the untouched stream.

    %include "include/sysdefs.inc"

section .data
    hdr1        db "==> "
    hdr1_len    equ $ - hdr1
    hdr2        db " <==", WHITESPACE_NL
    hdr2_len    equ $ - hdr2
    nl          db WHITESPACE_NL
    stdin_name  db "standard input", 0
open_err    db "head: cannot open file", WHITESPACE_NL
    open_err_len equ $ - open_err

section .bss
    files       resq 128                ;file operand pointers
    nfiles      resq 1
    mode_bytes  resb 1                  ;0 = lines, 1 = bytes
    count       resq 1
    v_flag      resb 1
    q_flag      resb 1
    cur_fd      resq 1
    onebyte     resb 1
    exit_status resq 1

section .text
global          _start

_start:
    mov         byte [mode_bytes], 0
    mov         qword [count], 10
    mov         byte [v_flag], 0
    mov         byte [q_flag], 0
    mov         qword [nfiles], 0
    mov         qword [exit_status], 0

    mov         r12, [rsp]              ;argc
    lea         r13, [rsp + 16]         ;&argv[1]
    dec         r12                     ;operand count

parse:
    cmp         r12, 0
    je          run
    mov         rdi, [r13]
    add         r13, 8
    dec         r12
    cmp         byte [rdi], '-'
    jne         .file
    cmp         byte [rdi + 1], 0       ;lone "-" is a stdin operand
    je          .file
;it is an option argument
    inc         rdi                     ;past '-'
    movzx       eax, byte [rdi]
    cmp         al, '0'
    jb          .scan
    cmp         al, '9'
    ja          .scan
;"-NUM" shorthand for -n NUM
    call        atoi
    mov         [count], rax
    mov         byte [mode_bytes], 0
    jmp         parse
.scan:
    movzx       eax, byte [rdi]
    test        al, al
    je          parse
    cmp         al, 'v'
    je          .set_v
    cmp         al, 'q'
    je          .set_q
    cmp         al, 'n'
    je          .set_n
    cmp         al, 'c'
    je          .set_c
    inc         rdi                     ;ignore unknown option letters
    jmp         .scan
.set_v:
    mov         byte [v_flag], 1
    inc         rdi
    jmp         .scan
.set_q:
    mov         byte [q_flag], 1
    inc         rdi
    jmp         .scan
.set_n:
    mov         byte [mode_bytes], 0
    inc         rdi
    call        take_number
    jmp         parse
.set_c:
    mov         byte [mode_bytes], 1
    inc         rdi
    call        take_number
    jmp         parse
.file:
    mov         rcx, [nfiles]
    mov         [files + rcx*8], rdi
    inc         rcx
    mov         [nfiles], rcx
    jmp         parse

run:
    mov         r15, [nfiles]
    test        r15, r15
    jnz         .have
    mov         qword [files], stdin_name ;no operand -> stdin
    mov         qword [nfiles], 1
    mov         r15, 1
.have:
    xor         r14, r14                ;file index
.loop:
    cmp         r14, r15
    jge         .done
    mov         rbx, [files + r14*8]    ;current name

;print a header when there are several files or -v was given
    cmp         byte [q_flag], 1
    je          .no_header
    cmp         byte [v_flag], 1
    je          .header
    cmp         r15, 1
    jle         .no_header
.header:
    test        r14, r14
    jz          .hdr_write
    write       STDOUT_FILENO, nl, 1    ;blank line between file headers
.hdr_write:
    write       STDOUT_FILENO, hdr1, hdr1_len
    mov         rsi, rbx
    call        strlen                  ;rbx clobbered? sysdefs strlen -> rbx
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, [files + r14*8]
    mov         rdx, rbx
    syscall
    write       STDOUT_FILENO, hdr2, hdr2_len
.no_header:
    mov         rdi, [files + r14*8]
    call        head_one
    inc         r14
    jmp         .loop
.done:
    mov         rdi, [exit_status]
    mov         rax, SYS_EXIT
    syscall

; head_one: rdi -> name; open (or stdin), emit the requested prefix, close
head_one:
    cmp         rdi, stdin_name
    je          .stdin
    cmp         byte [rdi], '-'
    jne         .open
    cmp         byte [rdi + 1], 0
    jne         .open
.stdin:
    mov         qword [cur_fd], STDIN_FILENO
    jmp         .emit
.open:
    mov         rax, SYS_OPEN
    mov         rsi, O_RDONLY
    xor         rdx, rdx
    syscall
    test        rax, rax
    js          .open_fail
    mov         [cur_fd], rax
.emit:
    mov         r10, [count]            ;remaining lines or bytes
.byte_loop:
    test        r10, r10
    jz          .close
    mov         rax, SYS_READ
    mov         rdi, [cur_fd]
    mov         rsi, onebyte
    mov         rdx, 1
    syscall
    cmp         rax, 0
    jle         .close                  ;EOF or error
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, onebyte
    mov         rdx, 1
    syscall
    cmp         byte [mode_bytes], 1
    je          .dec
    cmp         byte [onebyte], WHITESPACE_NL
    jne         .byte_loop
.dec:
    dec         r10
    jmp         .byte_loop
.close:
    cmp         qword [cur_fd], STDIN_FILENO
    je          .ret
    mov         rax, SYS_CLOSE
    mov         rdi, [cur_fd]
    syscall
.ret:
    ret
.open_fail:
    write       STDERR_FILENO, open_err, open_err_len
    mov         qword [exit_status], 1
    ret

; take_number: rdi -> either the rest of this option arg, or the next arg;
; parse it as the count. Advances r13/r12 when it consumes the next arg.
take_number:
    cmp         byte [rdi], 0
    jne         .here
    mov         rdi, [r13]              ;value is the following argument
    add         r13, 8
    dec         r12
.here:
    call        atoi
    mov         [count], rax
;point rdi at the NUL so the option scan ends
    ret

; atoi: rdi -> decimal digits, result in rax; leaves rdi at first non-digit
atoi:
    xor         rax, rax
.loop:
    movzx       r9, byte [rdi]
    cmp         r9b, '0'
    jb          .done
    cmp         r9b, '9'
    ja          .done
    imul        rax, rax, 10
    sub         r9b, '0'
    movzx       r9, r9b
    add         rax, r9
    inc         rdi
    jmp         .loop
.done:
    ret
