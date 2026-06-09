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

    xor         r10, r10                ;nonzero when -a/-s selects multi-operand mode
    xor         r12, r12                ;suffix pointer (0 = no suffix)
    xor         r13, r13                ;suffix length
    mov         r15, 1                  ;current argv index

.parse_options:
    cmp         r15, r14
    jae         missing_operand
    mov         rsi, [rsp + r15 * 8 + 8]

    cmp         byte [rsi], '-'
    jne         .options_done
    cmp         byte [rsi + 1], 'a'
    je          .maybe_a
    cmp         byte [rsi + 1], 's'
    je          .maybe_s
    jmp         .options_done

.maybe_a:
    cmp         byte [rsi + 2], 0
    jne         .options_done
    mov         r10, 1
    inc         r15
    jmp         .parse_options

.maybe_s:
    cmp         byte [rsi + 2], 0
    jne         .options_done
    mov         r10, 1
    inc         r15                     ;consume -s
    cmp         r15, r14                ;need a suffix argument
    jae         missing_operand
    mov         r12, [rsp + r15 * 8 + 8]
    mov         rsi, r12
    call        strlen
    mov         r13, rbx
    inc         r15                     ;-s implies -a, so all remaining args are names
    jmp         .parse_options

.options_done:
    cmp         r15, r14
    jae         missing_operand

    mov         rbp, r14                ;exclusive end index for path operands
    test        r12, r12
    jnz         .emit_loop              ;-s supplied the suffix already
    test        r10, r10
    jnz         .emit_loop              ;-a leaves every remaining argument as a path

    mov         rax, r14
    sub         rax, r15                ;remaining argument count
    cmp         rax, 2
    jne         .emit_loop

; Traditional two-argument form: basename NAME SUFFIX.
    mov         r12, [rsp + r15 * 8 + 16]
    mov         rsi, r12
    call        strlen
    mov         r13, rbx
    dec         rbp                     ;last argument is the suffix, not a path

.emit_loop:
    cmp         r15, rbp
    jae         .done

    mov         rsi, [rsp + r15 * 8 + 8]
    call        find_basename           ;rsi = component start, rbx = length
    mov         r8, rsi                 ;component start
    mov         r9, rbx                 ;component length

    test        r13, r13
    jz          .emit
    cmp         r13, r9
    jae         .emit                   ;suffix cannot be the whole result

    lea         r10, [r8 + r9]          ;end of the component
    sub         r10, r13                ;start of its trailing slice
    mov         rsi, r12                ;suffix pointer
    mov         rcx, r13                ;suffix length
.cmp_suffix:
    mov         al, [r10]
    cmp         al, [rsi]
    jne         .emit                   ;tail != suffix -> keep whole
    inc         r10
    inc         rsi
    dec         rcx
    jnz         .cmp_suffix
    sub         r9, r13                 ;strip the matched suffix

.emit:
    write       STDOUT_FILENO, r8, r9
    write       STDOUT_FILENO, nl, 1
    inc         r15
    jmp         .emit_loop

.done:
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
