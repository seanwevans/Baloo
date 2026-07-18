; src/tr.asm -- tr(1): translate, delete (-d), squeeze (-s) or truncate (-t)
; characters from stdin to stdout. Sets are treated as literal byte lists
; (ranges/classes are not implemented).

    %include "include/sysdefs.inc"

    %define IOBUF 65536

section .bss
    inbuf       resb IOBUF
    outbuf      resb IOBUF
    outpos      resq 1
    char_map    resb 256                ;translation table
    del_set     resb 256                ;bytes to delete
    sq_set      resb 256                ;bytes to squeeze
    set1        resb 256
    set2        resb 256
    set1_len    resq 1
    set2_len    resq 1
    d_flag      resb 1
    s_flag      resb 1
    t_flag      resb 1
    xlat_flag   resb 1                  ;translation table in use

section .data
usage_msg   db "Usage: tr [-dst] SET1 [SET2]", 10
    usage_len   equ $ - usage_msg

section .text
global      _start

_start:
;identity translation table, empty delete/squeeze sets
    xor         rcx, rcx
.init:
    mov         [char_map + rcx], cl
    mov         byte [del_set + rcx], 0
    mov         byte [sq_set + rcx], 0
    inc         rcx
    cmp         rcx, 256
    jl          .init
    mov         byte [d_flag], 0
    mov         byte [s_flag], 0
    mov         byte [t_flag], 0
    mov         byte [xlat_flag], 0
    mov         qword [outpos], 0

    mov         r12, [rsp]              ;argc
    lea         r13, [rsp + 16]         ;&argv[1]
    dec         r12                     ;operand count

opt_loop:
    cmp         r12, 0
    je          show_usage
    mov         rdi, [r13]
    cmp         byte [rdi], '-'
    jne         have_set1
    cmp         byte [rdi + 1], 0
    je          have_set1               ;lone "-" is not an option
    inc         rdi
.char:
    movzx       eax, byte [rdi]
    test        al, al
    je          .next
    cmp         al, 'd'
    je          .sd
    cmp         al, 's'
    je          .ss
    cmp         al, 't'
    je          .st
    jmp         show_usage
.sd:
    mov         byte [d_flag], 1
    inc         rdi
    jmp         .char
.ss:
    mov         byte [s_flag], 1
    inc         rdi
    jmp         .char
.st:
    mov         byte [t_flag], 1
    inc         rdi
    jmp         .char
.next:
    add         r13, 8
    dec         r12
    jmp         opt_loop

have_set1:
    cmp         r12, 0
    je          show_usage
    mov         rdi, [r13]
    mov         rsi, set1
    call        copy_set
    mov         [set1_len], rax
    add         r13, 8
    dec         r12

    mov         qword [set2_len], 0
    cmp         r12, 0
    je          .no_set2
    mov         rdi, [r13]
    mov         rsi, set2
    call        copy_set
    mov         [set2_len], rax
.no_set2:
;require a second set unless -d/-s/-t was given
    cmp         qword [set2_len], 0
    jne         setup
    cmp         byte [d_flag], 1
    je          setup
    cmp         byte [s_flag], 1
    je          setup
    cmp         byte [t_flag], 1
    je          setup
    jmp         show_usage

setup:
;-t truncates SET1 to the length of SET2
    cmp         byte [t_flag], 1
    jne         .no_trunc
    mov         rax, [set2_len]
    test        rax, rax
    jz          .no_trunc
    cmp         [set1_len], rax
    jle         .no_trunc
    mov         [set1_len], rax
.no_trunc:
;build the translation table when a SET2 exists and we are not deleting
    cmp         qword [set2_len], 0
    je          .delmap
    cmp         byte [d_flag], 1
    je          .delmap
    mov         byte [xlat_flag], 1
    xor         rcx, rcx
.xl:
    cmp         rcx, [set1_len]
    jge         .delmap
    mov         rbx, rcx                ;index into SET2 (extend with last)
    cmp         rbx, [set2_len]
    jl          .have_j
    mov         rbx, [set2_len]
    dec         rbx
.have_j:
    movzx       rax, byte [set1 + rcx]
    movzx       rdx, byte [set2 + rbx]
    mov         [char_map + rax], dl
    inc         rcx
    jmp         .xl
.delmap:
    cmp         byte [d_flag], 1
    jne         .sqmap
    xor         rcx, rcx
.dl:
    cmp         rcx, [set1_len]
    jge         .sqmap
    movzx       rax, byte [set1 + rcx]
    mov         byte [del_set + rax], 1
    inc         rcx
    jmp         .dl
.sqmap:
    cmp         byte [s_flag], 1
    jne         run
;squeeze set is SET2 when present, otherwise SET1
    mov         rsi, set1
    mov         rdx, [set1_len]
    cmp         qword [set2_len], 0
    je          .sq_have
    mov         rsi, set2
    mov         rdx, [set2_len]
.sq_have:
    xor         rcx, rcx
.sl:
    cmp         rcx, rdx
    jge         run
    movzx       rax, byte [rsi + rcx]
    mov         byte [sq_set + rax], 1
    inc         rcx
    jmp         .sl

run:
    mov         r15, -1                 ;last byte written (for squeeze)
.read:
    mov         rax, SYS_READ
    mov         rdi, STDIN_FILENO
    mov         rsi, inbuf
    mov         rdx, IOBUF
    syscall
    cmp         rax, 0
    jle         .eof
    mov         r14, rax                ;bytes read
    xor         rbx, rbx                ;index
.byte:
    cmp         rbx, r14
    jge         .read
    movzx       rax, byte [inbuf + rbx]
    inc         rbx
;delete?
    cmp         byte [d_flag], 1
    jne         .translate
    cmp         byte [del_set + rax], 1
    je          .byte                   ;deleted
.translate:
    cmp         byte [xlat_flag], 1
    jne         .have_c
    movzx       rax, byte [char_map + rax]
.have_c:
;squeeze?
    cmp         byte [s_flag], 1
    jne         .emit
    cmp         byte [sq_set + rax], 1
    jne         .emit
    cmp         rax, r15
    je          .byte                   ;squeezed repeat
.emit:
    mov         r15, rax
    call        put_byte
    jmp         .byte
.eof:
    call        flush
    exit        0

; put_byte: append al-ish (rax low byte) to outbuf, flushing when full
put_byte:
    mov         rcx, [outpos]
    mov         [outbuf + rcx], al
    inc         rcx
    mov         [outpos], rcx
    cmp         rcx, IOBUF
    jl          .ok
    call        flush
.ok:
    ret

; flush: write and reset outbuf (preserves the working registers)
flush:
    push        rax
    push        rbx
    push        rcx
    push        rdx
    push        rsi
    push        rdi
    push        r11
    mov         rdx, [outpos]
    test        rdx, rdx
    jz          .empty
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, outbuf
    syscall
    mov         qword [outpos], 0
.empty:
    pop         r11
    pop         rdi
    pop         rsi
    pop         rdx
    pop         rcx
    pop         rbx
    pop         rax
    ret

; copy_set: rdi -> NUL-terminated arg, rsi -> dest (max 255); returns length
copy_set:
    xor         rcx, rcx
.loop:
    mov         al, [rdi + rcx]
    test        al, al
    je          .done
    mov         [rsi + rcx], al
    inc         rcx
    cmp         rcx, 255
    jl          .loop
.done:
    mov         rax, rcx
    ret

show_usage:
    write       STDERR_FILENO, usage_msg, usage_len
    exit        1
