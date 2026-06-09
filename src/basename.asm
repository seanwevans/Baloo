; src/basename.asm

    %include "include/sysdefs.inc"

section .bss

section .data
    nl          db WHITESPACE_NL
    slash       db "/"
err_msg     db "basename: missing operand", 10
    err_len     equ $ - err_msg

section .text
global      _start

_start:
    mov         r14, [rsp]              ;argc
    cmp         r14, 2                  ;need at least 1 operand
    jl          missing_operand

    mov         rsi, [rsp + 16]         ;rsi = argv[1]
    call        find_basename           ;rsi = component start, rbx = length
    mov         r12, rsi                ;save component start
    mov         r13, rbx                ;save component length

    cmp         r14, 3                  ;optional suffix operand present?
    jl          .emit

    mov         rsi, [rsp + 24]         ;rsi = argv[2] = suffix
    call        strlen                  ;rbx = suffix length
    test        rbx, rbx
    jz          .emit                   ;empty suffix -> nothing to strip
    cmp         rbx, r13
    jae         .emit                   ;suffix not shorter than name -> keep whole

    lea         r8, [r12 + r13]         ;end of the component
    sub         r8, rbx                 ;start of its trailing slice
    mov         r9, rsi                 ;suffix pointer
    mov         rcx, rbx                ;suffix length
.cmp_suffix:
    mov         al, [r8]
    cmp         al, [r9]
    jne         .emit                   ;tail != suffix -> keep whole
    inc         r8
    inc         r9
    dec         rcx
    jnz         .cmp_suffix
    sub         r13, rbx                ;strip the matched suffix

.emit:
    write       STDOUT_FILENO, r12, r13
    write       STDOUT_FILENO, nl, 1
    exit        0

missing_operand:
    write       STDERR_FILENO, err_msg, err_len
    exit        1

; find_basename: rsi = path -> rsi = start of last component, rbx = its length.
;   Trailing '/' are stripped; an all-slash path yields "/", "" yields length 0.
find_basename:
    mov         r10, rsi                ;r10 = start of string
    call        strlen                  ;rbx = strlen(rsi)
    mov         r8, rbx                 ;r8 = end index

.strip_trailing:
    test        r8, r8
    jz          .all_slashes
    cmp         byte [r10 + r8 - 1], '/'
    jne         .find_last
    dec         r8
    jmp         .strip_trailing

.all_slashes:
    test        rbx, rbx                ;original length
    jz          .empty                  ;empty operand -> length 0
    mov         rsi, slash              ;all-slash path -> "/"
    mov         rbx, 1
    ret

.empty:
    mov         rsi, r10
    xor         rbx, rbx
    ret

.find_last:
    mov         r9, r8                  ;r9 = scan index
.scan_back:
    test        r9, r9
    jz          .no_slash
    cmp         byte [r10 + r9 - 1], '/'
    je          .have_start
    dec         r9
    jmp         .scan_back

.no_slash:
    mov         rsi, r10
    mov         rbx, r8
    ret

.have_start:
    lea         rsi, [r10 + r9]         ;skip past the last '/'
    mov         rbx, r8
    sub         rbx, r9
    ret
