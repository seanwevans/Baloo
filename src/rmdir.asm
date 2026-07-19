; src/rmdir.asm

    %include "include/sysdefs.inc"

section .bss
    pathbuf     resb 4096               ;mutable copy of a path for -p walking

section .data
usage_msg   db "Usage: rmdir [-p] directory...", 10
    usage_len   equ $ - usage_msg
error_msg   db "rmdir: failed to remove directory", 10
    error_len   equ $ - error_msg

section .text
global      _start

_start:
    mov         r12, [rsp]              ;argc
    lea         r13, [rsp + 16]         ;&argv[1]
    cmp         r12, 2                  ;need program name + at least one dir
    jl          print_usage

    dec         r12                     ;number of remaining arguments
    xor         r14, r14                ;exit status accumulator
    xor         r15, r15                ;-p flag

opt_loop:
    cmp         r12, 0
    je          print_usage             ;options but no operand
    mov         rdi, [r13]
    cmp         byte [rdi], '-'
    jne         operands
    cmp         byte [rdi + 1], 0       ;lone "-" is an operand
    je          operands
    inc         rdi                     ;skip '-'
.char:
    movzx       eax, byte [rdi]
    test        al, al
    je          .next_opt
    cmp         al, 'p'
    jne         .skip
    mov         r15, 1
.skip:
    inc         rdi
    jmp         .char
.next_opt:
    add         r13, 8
    dec         r12
    jmp         opt_loop

operands:
    cmp         r12, 0
    je          done
    mov         rdi, [r13]
    test        r15, r15
    jnz         .with_parents

    mov         rax, SYS_RMDIR          ;plain removal
    syscall
    test        rax, rax
    jns         .next
    write       STDERR_FILENO, error_msg, error_len
    mov         r14, 1
    jmp         .next
.with_parents:
    call        remove_with_parents
.next:
    add         r13, 8
    dec         r12
    jmp         operands

done:
    mov         rdi, r14
    mov         rax, SYS_EXIT
    syscall

; remove_with_parents: rdi -> path. Remove it, then walk up removing each
; parent directory until one is not empty (silently) or the path runs out.
remove_with_parents:
    push        rsi
;copy the path into pathbuf
    mov         rsi, pathbuf
    xor         rcx, rcx
.copy:
    mov         al, [rdi + rcx]
    mov         [rsi + rcx], al
    test        al, al
    je          .copied
    inc         rcx
    jmp         .copy
.copied:
;strip trailing slashes (but never below one character)
.strip_tail:
    cmp         rcx, 1
    jle         .first
    cmp         byte [rsi + rcx - 1], '/'
    jne         .first
    mov         byte [rsi + rcx - 1], 0
    dec         rcx
    jmp         .strip_tail
.first:
    mov         r11, 1                  ;first removal (the operand itself)
.rm_loop:
    mov         rdi, pathbuf
    mov         rax, SYS_RMDIR
    syscall
    test        rax, rax
    jns         .climb
;removal failed
    test        r11, r11
jz          .out                    ;a parent was non-empty: stop silently
    write       STDERR_FILENO, error_msg, error_len
    mov         r14, 1
    jmp         .out
.climb:
    xor         r11, r11                ;subsequent removals are parents
;find the last '/' in pathbuf and truncate there
    mov         rsi, pathbuf
    xor         rcx, rcx                ;index
    mov         r10, -1                 ;position of last '/'
.scan:
    mov         al, [rsi + rcx]
    test        al, al
    je          .scanned
    cmp         al, '/'
    jne         .scan_next
    mov         r10, rcx
.scan_next:
    inc         rcx
    jmp         .scan
.scanned:
    cmp         r10, 0
    jle         .out                    ;no parent component left
    mov         byte [rsi + r10], 0     ;drop the last component
    jmp         .rm_loop
.out:
    pop         rsi
    ret

print_usage:
    write       STDOUT_FILENO, usage_msg, usage_len
    exit        1
