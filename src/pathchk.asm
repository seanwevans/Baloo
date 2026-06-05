; src/pathchk.asm -- check whether path names are valid.
; Verifies each operand is non-empty, within PATH_MAX, and has no
; component longer than NAME_MAX. Exits 0 when all operands are valid.

    %include "include/sysdefs.inc"

    %define PATH_MAX 4096
    %define NAME_MAX 255

section .data
err_missing db "pathchk: missing operand", 10
    err_missing_len equ $ - err_missing
err_empty   db "pathchk: empty file name", 10
    err_empty_len equ $ - err_empty
err_long    db "pathchk: name too long", 10
    err_long_len equ $ - err_long

section .text
global _start

_start:
    pop     r12                         ;argc
    pop     rdi                         ;argv[0] discarded
    cmp     r12, 1
    jle     .missing
    dec     r12                         ;operand count
    mov     rbx, rsp                    ;&argv[1]
.next_arg:
    test    r12, r12
    jz      .ok
    mov     rsi, [rbx]
    call    check_path
    add     rbx, 8
    dec     r12
    jmp     .next_arg
.ok:
    exit    0

.missing:
    write   STDERR_FILENO, err_missing, err_missing_len
    exit    1

; check_path: validate the NUL-terminated path in rsi (exits 1 on failure)
check_path:
    cmp     byte [rsi], 0
    je      .empty
    xor     rcx, rcx                    ;total length
    xor     rdx, rdx                    ;current component length
.scan:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .done
    cmp     al, '/'
    je      .sep
    inc     rdx
    cmp     rdx, NAME_MAX
    ja      .too_long
    jmp     .advance
.sep:
    xor     rdx, rdx
.advance:
    inc     rcx
    cmp     rcx, PATH_MAX
    jae     .too_long
    jmp     .scan
.done:
    ret
.empty:
    write   STDERR_FILENO, err_empty, err_empty_len
    exit    1
.too_long:
    write   STDERR_FILENO, err_long, err_long_len
    exit    1
