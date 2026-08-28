; src/expr.asm -- expr(1): evaluate an expression.
; Usage: expr EXPRESSION
;
; Every operand is a string; an integer is just a string that happens to
; parse as one, which is what lets "expr 2 - 5 \< -2s" compare "-3" against
; "-2s" as text after doing the subtraction as arithmetic.
;
; Operators are parsed by recursive descent, lowest precedence first:
;   |   &   = > >= < <= !=   + -   * / %   :
; all left associative, with ( ) for grouping. That ordering is what makes
; "expr 1 | 0 & 0" one rather than zero, and what lets ':' feed its result
; straight into arithmetic in "expr ab21xx : '[^0-9]*\([0-9]*\)' + 3".
;
; ':' anchors a basic regular expression at the start of its left operand.
; The matcher is a backtracking walk over a compiled element list supporting
; literals, '.', bracket expressions, '*', '$' and one \( \) group. With a
; group the result is the captured text, without one it is the number of
; characters matched.
;
; The exit status is 0 for a result that is neither null nor zero, 1 when it
; is, and 2 for anything expr could not evaluate.

    %include "include/sysdefs.inc"

    %define MAXTOK 512
    %define MAXELEM 256
    %define MAXCLASS 32
    %define ARENACAP 65536
    %define SUBJCAP 65536

    %define T_LIT 0
    %define T_ANY 1
    %define T_CLASS 2
    %define T_GSTART 3
    %define T_GEND 4
    %define T_EOL 5

section .bss
    tokens      resq MAXTOK
    ntok        resq 1
    tokidx      resq 1
    arena       resb ARENACAP
    arenaptr    resq 1
    numbuf      resb 64
    e_type      resb MAXELEM
    e_ch        resb MAXELEM
    e_cls       resb MAXELEM
    e_star      resb MAXELEM
    classes     resb MAXCLASS * 32
    nelem       resq 1
    nclass      resq 1
    has_group   resb 1
    subj        resq 1
    subj_len    resq 1
    grp_start   resq 1
    grp_end     resq 1
    match_end   resq 1
    lhs         resq 1
    rhs         resq 1
    intval      resq 1
    int_ok      resb 1
    lint        resq 1
    rint        resq 1
    both_int    resb 1
    cmpres      resq 1

section .data
    s_or        db "|", 0
    s_and       db "&", 0
    s_eq        db "=", 0
    s_gt        db ">", 0
    s_ge        db ">=", 0
    s_lt        db "<", 0
    s_le        db "<=", 0
    s_ne        db "!=", 0
    s_add       db "+", 0
    s_sub       db "-", 0
    s_mul       db "*", 0
    s_div       db "/", 0
    s_mod       db "%", 0
s_colon     db ":", 0
    s_lparen    db "(", 0
    s_rparen    db ")", 0
    s_dashdash  db "--", 0
    str_zero    db "0", 0
    str_one     db "1", 0
    str_empty   db 0

syntax_msg  db "expr: syntax error", 10
    syntax_len  equ $ - syntax_msg
nonint_msg  db "expr: non-integer argument", 10
    nonint_len  equ $ - nonint_msg
divzero_msg db "expr: division by zero", 10
    divzero_len equ $ - divzero_msg
    newline     db WHITESPACE_NL

section .text
global _start

_start:
    mov     qword [arenaptr], arena
    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12
    xor     rbx, rbx
.collect:
    cmp     r12, 0
    jle     .ready
    mov     rax, [r13]
    test    rax, rax
    jz      .ready
    cmp     rbx, MAXTOK
    jae     .ready
    mov     [tokens + rbx * 8], rax
    inc     rbx
    add     r13, 8
    dec     r12
    jmp     .collect
.ready:
    mov     [ntok], rbx
    cmp     rbx, 0
    je      syntax_error
    mov     rdi, [tokens]
    mov     rsi, s_dashdash
    call    streq
    test    al, al
    jz      .evaluate
    mov     qword [tokidx], 1           ;"--" only ends option parsing
.evaluate:
    call    parse_or
    push    rax
    call    cur_tok
    test    rax, rax
    jnz     syntax_error                ;something was left over
    pop     rax
    push    rax
    mov     rdi, rax
    call    strlen_z
    mov     rdx, rax
    pop     rsi
    push    rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, newline
    mov     rdx, 1
    syscall
    pop     rdi
    call    is_true
    test    al, al
    jz      .falsey
    exit    0
.falsey:
    exit    1

syntax_error:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, syntax_msg
    mov     rdx, syntax_len
    syscall
    exit    2

nonint_error:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, nonint_msg
    mov     rdx, nonint_len
    syscall
    exit    2

divzero_error:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, divzero_msg
    mov     rdx, divzero_len
    syscall
    exit    2

; cur_tok: the token under the cursor, or 0 past the end.
cur_tok:
    mov     rax, [tokidx]
    cmp     rax, [ntok]
    jae     .none
    mov     rax, [tokens + rax * 8]
    ret
.none:
    xor     rax, rax
    ret

advance:
    inc     qword [tokidx]
    ret

; tok_is: is the current token the literal at rsi? al = 1/0.
tok_is:
    push    rsi
    call    cur_tok
    pop     rsi
    test    rax, rax
    jz      .no
    mov     rdi, rax
    call    streq
    ret
.no:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; The precedence ladder. Each level parses the one above it, then folds any
; run of its own operators left to right.
; ---------------------------------------------------------------------------
parse_or:
    call    parse_and
    push    rax
.loop:
    mov     rsi, s_or
    call    tok_is
    test    al, al
    jz      .done
    call    advance
    call    parse_and
    mov     [rhs], rax
    pop     rax
    mov     [lhs], rax
    call    op_or
    push    rax
    jmp     .loop
.done:
    pop     rax
    ret

parse_and:
    call    parse_cmp
    push    rax
.loop:
    mov     rsi, s_and
    call    tok_is
    test    al, al
    jz      .done
    call    advance
    call    parse_cmp
    mov     [rhs], rax
    pop     rax
    mov     [lhs], rax
    call    op_and
    push    rax
    jmp     .loop
.done:
    pop     rax
    ret

parse_cmp:
    call    parse_add
    push    rax
.loop:
    call    cmp_kind                    ;-> al = operator, 0 for none
    test    al, al
    jz      .done
    push    rax
    call    advance
    call    parse_add
    mov     [rhs], rax
    pop     rcx
    pop     rdx
    mov     [lhs], rdx
    movzx   eax, cl
    call    op_compare
    push    rax
    jmp     .loop
.done:
    pop     rax
    ret

; cmp_kind: which comparison the cursor is on. 'e' = , 'g' >, 'G' >=, 'l' <,
; 'L' <=, 'n' !=, 0 for none.
cmp_kind:
    mov     rsi, s_ge
    call    tok_is
    test    al, al
    jnz     .ge
    mov     rsi, s_le
    call    tok_is
    test    al, al
    jnz     .le
    mov     rsi, s_ne
    call    tok_is
    test    al, al
    jnz     .ne
    mov     rsi, s_eq
    call    tok_is
    test    al, al
    jnz     .eq
    mov     rsi, s_gt
    call    tok_is
    test    al, al
    jnz     .gt
    mov     rsi, s_lt
    call    tok_is
    test    al, al
    jnz     .lt
    xor     al, al
    ret
.eq:
    mov     al, 'e'
    ret
.gt:
    mov     al, 'g'
    ret
.ge:
    mov     al, 'G'
    ret
.lt:
    mov     al, 'l'
    ret
.le:
    mov     al, 'L'
    ret
.ne:
    mov     al, 'n'
    ret

parse_add:
    call    parse_mul
    push    rax
.loop:
    mov     rsi, s_add
    call    tok_is
    test    al, al
    jnz     .plus
    mov     rsi, s_sub
    call    tok_is
    test    al, al
    jnz     .minus
    pop     rax
    ret
.plus:
    mov     al, '+'
    jmp     .fold
.minus:
    mov     al, '-'
.fold:
    push    rax
    call    advance
    call    parse_mul
    mov     [rhs], rax
    pop     rcx
    pop     rdx
    mov     [lhs], rdx
    movzx   eax, cl
    call    op_arith
    push    rax
    jmp     .loop

parse_mul:
    call    parse_match
    push    rax
.loop:
    mov     rsi, s_mul
    call    tok_is
    test    al, al
    jnz     .times
    mov     rsi, s_div
    call    tok_is
    test    al, al
    jnz     .over
    mov     rsi, s_mod
    call    tok_is
    test    al, al
    jnz     .rem
    pop     rax
    ret
.times:
    mov     al, '*'
    jmp     .fold
.over:
    mov     al, '/'
    jmp     .fold
.rem:
    mov     al, '%'
.fold:
    push    rax
    call    advance
    call    parse_match
    mov     [rhs], rax
    pop     rcx
    pop     rdx
    mov     [lhs], rdx
    movzx   eax, cl
    call    op_arith
    push    rax
    jmp     .loop

parse_match:
    call    parse_primary
    push    rax
.loop:
    mov     rsi, s_colon
    call    tok_is
    test    al, al
    jz      .done
    call    advance
    call    parse_primary
    mov     [rhs], rax
    pop     rax
    mov     [lhs], rax
    call    op_match
    push    rax
    jmp     .loop
.done:
    pop     rax
    ret

parse_primary:
    mov     rsi, s_lparen
    call    tok_is
    test    al, al
    jnz     .group
    call    cur_tok
    test    rax, rax
    jz      syntax_error
    push    rax
    call    advance
    pop     rax
    ret
.group:
    call    advance
    mov     rsi, s_rparen
    call    tok_is
    test    al, al
    jnz     syntax_error                ;"( )" has nothing to evaluate
    call    parse_or
    push    rax
    mov     rsi, s_rparen
    call    tok_is
    test    al, al
    jz      syntax_error
    call    advance
    pop     rax
    ret

; ---------------------------------------------------------------------------
; Operators. Each reads lhs and rhs and returns the result string in rax.
; ---------------------------------------------------------------------------
op_or:
    mov     rdi, [lhs]
    call    is_true
    test    al, al
    jz      .right
    mov     rax, [lhs]
    ret
.right:
    mov     rdi, [rhs]
    call    is_true
    test    al, al
    jz      .zero
    mov     rax, [rhs]
    ret
.zero:
    mov     rax, str_zero
    ret

op_and:
    mov     rdi, [lhs]
    call    is_true
    test    al, al
    jz      .zero
    mov     rdi, [rhs]
    call    is_true
    test    al, al
    jz      .zero
    mov     rax, [lhs]
    ret
.zero:
    mov     rax, str_zero
    ret

; op_compare: numeric when both sides are integers, textual otherwise.
op_compare:
    push    rax
    call    classify
    cmp     byte [both_int], 0
    je      .strings
    mov     rax, [lint]
    cmp     rax, [rint]
    jl      .less
    jg      .greater
    jmp     .equal
.strings:
    mov     rdi, [lhs]
    mov     rsi, [rhs]
    call    strcmp_z
    test    rax, rax
    jl      .less
    jg      .greater
.equal:
    mov     qword [cmpres], 0
    jmp     .decide
.less:
    mov     qword [cmpres], -1
    jmp     .decide
.greater:
    mov     qword [cmpres], 1
.decide:
    pop     rax
    mov     rcx, [cmpres]
    cmp     al, 'e'
    je      .want_eq
    cmp     al, 'n'
    je      .want_ne
    cmp     al, 'g'
    je      .want_gt
    cmp     al, 'G'
    je      .want_ge
    cmp     al, 'l'
    je      .want_lt
.want_le:
    cmp     rcx, 0
    jle     .true
    jmp     .false
.want_eq:
    cmp     rcx, 0
    je      .true
    jmp     .false
.want_ne:
    cmp     rcx, 0
    jne     .true
    jmp     .false
.want_gt:
    cmp     rcx, 0
    jg      .true
    jmp     .false
.want_ge:
    cmp     rcx, 0
    jge     .true
    jmp     .false
.want_lt:
    cmp     rcx, 0
    jl      .true
.false:
    mov     rax, str_zero
    ret
.true:
    mov     rax, str_one
    ret

; op_arith: both operands have to be integers here.
op_arith:
    push    rax
    call    classify
    cmp     byte [both_int], 0
    je      nonint_error
    pop     rax
    mov     rcx, [lint]
    mov     rdx, [rint]
    cmp     al, '+'
    je      .plus
    cmp     al, '-'
    je      .minus
    cmp     al, '*'
    je      .times
    cmp     al, '/'
    je      .over
.rem:
    mov     r8, rdx                     ;cqo overwrites rdx, so hold it here
    test    r8, r8
    jz      divzero_error
    mov     rax, rcx
    cqo
    idiv    r8
    mov     rax, rdx
    jmp     alloc_int
.plus:
    mov     rax, rcx
    add     rax, rdx
    jmp     alloc_int
.minus:
    mov     rax, rcx
    sub     rax, rdx
    jmp     alloc_int
.times:
    mov     rax, rcx
    imul    rax, rdx
    jmp     alloc_int
.over:
    mov     r8, rdx                     ;cqo overwrites rdx, so hold it here
    test    r8, r8
    jz      divzero_error
    mov     rax, rcx
    cqo
    idiv    r8
    jmp     alloc_int

; classify: parse both operands as integers, recording whether both worked.
classify:
    mov     byte [both_int], 0
    mov     rdi, [lhs]
    call    to_int
    cmp     byte [int_ok], 0
    je      .out
    mov     rax, [intval]
    mov     [lint], rax
    mov     rdi, [rhs]
    call    to_int
    cmp     byte [int_ok], 0
    je      .out
    mov     rax, [intval]
    mov     [rint], rax
    mov     byte [both_int], 1
.out:
    ret

; ---------------------------------------------------------------------------
; op_match: anchor the pattern in rhs at the start of lhs. With a \( \) group
; the result is the captured text, otherwise the length of the match.
; ---------------------------------------------------------------------------
op_match:
    mov     rsi, [lhs]
    mov     [subj], rsi
    mov     rdi, rsi
    call    strlen_z
    mov     [subj_len], rax
    mov     rsi, [rhs]
    call    compile_regex
    mov     qword [grp_start], -1
    mov     qword [grp_end], -1
    mov     qword [match_end], 0
    xor     rdi, rdi
    xor     rsi, rsi
    call    rm_match
    test    al, al
    jz      .nomatch
    cmp     byte [has_group], 0
    je      .length
    mov     rax, [grp_start]
    cmp     rax, 0
    jl      .empty
    mov     rcx, [grp_end]
    sub     rcx, rax
    jl      .empty
    mov     rsi, [subj]
    add     rsi, rax
    jmp     alloc_str
.length:
    mov     rax, [match_end]
    jmp     alloc_int
.nomatch:
    cmp     byte [has_group], 0
    jne     .empty
    xor     rax, rax
    jmp     alloc_int
.empty:
    mov     rax, str_empty
    ret

; ---------------------------------------------------------------------------
; compile_regex: turn the basic regular expression at rsi into the element
; arrays. A leading '^' is redundant because ':' is anchored anyway.
; ---------------------------------------------------------------------------
compile_regex:
    mov     qword [nelem], 0
    mov     qword [nclass], 0
    mov     byte [has_group], 0
    cmp     byte [rsi], '^'
    jne     .scan
    inc     rsi
.scan:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .out
    cmp     al, '\'
    je      .escape
    cmp     al, '.'
    je      .any
    cmp     al, '['
    je      .bracket
    cmp     al, '$'
    jne     .literal
    cmp     byte [rsi + 1], 0
    jne     .literal
    mov     al, T_EOL
    call    push_elem
    inc     rsi
    jmp     .scan
.literal:
    mov     ah, al
    mov     al, T_LIT
    call    push_elem
    inc     rsi
    jmp     .star
.any:
    mov     al, T_ANY
    call    push_elem
    inc     rsi
    jmp     .star
.escape:
    inc     rsi
    movzx   eax, byte [rsi]
    test    al, al
    jz      .out
    cmp     al, '('
    je      .gstart
    cmp     al, ')'
    je      .gend
    mov     ah, al
    mov     al, T_LIT
    call    push_elem
    inc     rsi
    jmp     .star
.gstart:
    mov     byte [has_group], 1
    mov     al, T_GSTART
    call    push_elem
    inc     rsi
    jmp     .scan
.gend:
    mov     al, T_GEND
    call    push_elem
    inc     rsi
    jmp     .scan
.bracket:
    call    push_class                  ;consumes through the closing ']'
    jmp     .star
.star:
    cmp     byte [rsi], '*'
    jne     .scan
    mov     rcx, [nelem]
    dec     rcx
    mov     byte [e_star + rcx], 1
    inc     rsi
    jmp     .scan
.out:
    ret

; push_elem: append an element of type al (literal character in ah).
push_elem:
    mov     rcx, [nelem]
    cmp     rcx, MAXELEM
    jae     .out
    mov     [e_type + rcx], al
    mov     [e_ch + rcx], ah
    mov     byte [e_star + rcx], 0
    mov     byte [e_cls + rcx], 0
    inc     rcx
    mov     [nelem], rcx
.out:
    ret

; ---------------------------------------------------------------------------
; push_class: compile a bracket expression at rsi into a 256-bit set, leaving
; rsi past the closing ']'. A ']' first in the list is a literal one.
; ---------------------------------------------------------------------------
push_class:
    push    rbx
    mov     rbx, [nclass]
    cmp     rbx, MAXCLASS
    jae     .skip
    imul    rdi, rbx, 32
    add     rdi, classes
    xor     rcx, rcx
.clear:
    mov     byte [rdi + rcx], 0
    inc     rcx
    cmp     rcx, 32
    jb      .clear
    inc     rsi                         ;past '['
    xor     r8, r8                      ;negated?
    cmp     byte [rsi], '^'
    jne     .items
    mov     r8, 1
    inc     rsi
.items:
    xor     r9, r9                      ;first item?
.item:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .finish
    cmp     al, ']'
    jne     .member
    test    r9, r9
    jnz     .close
.member:
    mov     r9, 1
    cmp     byte [rsi + 1], '-'
    jne     .single
    movzx   ecx, byte [rsi + 2]
    test    cl, cl
    jz      .single
    cmp     cl, ']'
    je      .single
    movzx   edx, byte [rsi]
.range:
    call    class_set
    cmp     rdx, rcx
    jae     .rangedone
    inc     rdx
    mov     rax, rdx
    jmp     .range
.rangedone:
    add     rsi, 3
    jmp     .item
.single:
    movzx   edx, byte [rsi]
    mov     rax, rdx
    call    class_set
    inc     rsi
    jmp     .item
.close:
    inc     rsi
.finish:
    test    r8, r8
    jz      .store
    imul    rdi, rbx, 32
    add     rdi, classes
    xor     rcx, rcx
.invert:
    not     byte [rdi + rcx]
    inc     rcx
    cmp     rcx, 32
    jb      .invert
.store:
    mov     al, T_CLASS
    xor     ah, ah
    call    push_elem
    mov     rcx, [nelem]
    dec     rcx
    mov     [e_cls + rcx], bl
    inc     qword [nclass]
    pop     rbx
    ret
.skip:
    pop     rbx
    ret

; class_set: set the bit for the byte in al (or rdx during a range) in the
; class being built, whose index is in rbx.
class_set:
    push    rcx
    push    rdx
    push    rdi
    movzx   eax, al
    imul    rdi, rbx, 32
    add     rdi, classes
    mov     rcx, rax
    shr     rcx, 3
    add     rdi, rcx
    mov     rcx, rax
    and     rcx, 7
    mov     dl, 1
    shl     dl, cl
    or      [rdi], dl
    pop     rdi
    pop     rdx
    pop     rcx
    ret

; ---------------------------------------------------------------------------
; rm_match: does the element list from rdi match the subject from rsi? A
; starred element takes as much as it can and gives characters back one at a
; time until the rest of the pattern fits.
; ---------------------------------------------------------------------------
rm_match:
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    mov     r13, rsi
    cmp     r12, [nelem]
    jb      .element
    mov     [match_end], r13
    mov     al, 1
    jmp     .out
.element:
    movzx   eax, byte [e_type + r12]
    cmp     al, T_GSTART
    je      .gstart
    cmp     al, T_GEND
    je      .gend
    cmp     al, T_EOL
    je      .eol
    cmp     byte [e_star + r12], 0
    jne     .star
    cmp     r13, [subj_len]
    jae     .fail
    mov     rdi, r12
    mov     rsi, r13
    call    rm_elem
    test    al, al
    jz      .fail
    lea     rdi, [r12 + 1]
    lea     rsi, [r13 + 1]
    call    rm_match
    jmp     .out
.star:
    xor     r14, r14
.grow:
    lea     rax, [r13 + r14]
    cmp     rax, [subj_len]
    jae     .shrink
    mov     rdi, r12
    lea     rsi, [r13 + r14]
    call    rm_elem
    test    al, al
    jz      .shrink
    inc     r14
    jmp     .grow
.shrink:
    lea     rdi, [r12 + 1]
    lea     rsi, [r13 + r14]
    call    rm_match
    test    al, al
    jnz     .out
    test    r14, r14
    jz      .fail
    dec     r14
    jmp     .shrink
.gstart:
    mov     [grp_start], r13
    lea     rdi, [r12 + 1]
    mov     rsi, r13
    call    rm_match
    jmp     .out
.gend:
    mov     [grp_end], r13
    lea     rdi, [r12 + 1]
    mov     rsi, r13
    call    rm_match
    jmp     .out
.eol:
    cmp     r13, [subj_len]
    jne     .fail
    lea     rdi, [r12 + 1]
    mov     rsi, r13
    call    rm_match
    jmp     .out
.fail:
    xor     al, al
.out:
    pop     r14
    pop     r13
    pop     r12
    ret

; rm_elem: does element rdi match the subject byte at rsi? al = 1/0.
rm_elem:
    mov     r8, [subj]
    movzx   ecx, byte [r8 + rsi]
    movzx   eax, byte [e_type + rdi]
    cmp     al, T_ANY
    je      .yes
    cmp     al, T_CLASS
    je      .class
    cmp     al, T_LIT
    jne     .no
    cmp     cl, [e_ch + rdi]
    je      .yes
    jmp     .no
.class:
    movzx   r9d, byte [e_cls + rdi]
    imul    r9, r9, 32
    add     r9, classes
    mov     rax, rcx
    shr     rax, 3
    add     r9, rax
    and     rcx, 7
    mov     al, [r9]
    shr     al, cl
    and     al, 1
    ret
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; ---------------------------------------------------------------------------
; Values: strings that may or may not read as integers.
; ---------------------------------------------------------------------------
; to_int: parse rdi as an integer, setting int_ok and intval.
to_int:
    mov     byte [int_ok], 0
    xor     rax, rax
    xor     r8, r8                      ;negative?
    xor     r9, r9                      ;digits seen
    movzx   ecx, byte [rdi]
    cmp     cl, '-'
    jne     .plus
    mov     r8, 1
    inc     rdi
    jmp     .digits
.plus:
    cmp     cl, '+'
    jne     .digits
    inc     rdi
.digits:
    movzx   rcx, byte [rdi]
    test    cl, cl
    jz      .end
    sub     cl, '0'
    cmp     cl, 9
    ja      .out                        ;not an integer after all
    imul    rax, rax, 10
    add     rax, rcx
    inc     r9
    inc     rdi
    jmp     .digits
.end:
    test    r9, r9
    jz      .out
    test    r8, r8
    jz      .store
    neg     rax
.store:
    mov     [intval], rax
    mov     byte [int_ok], 1
.out:
    ret

; is_true: a value counts as true unless it is empty or the integer zero.
is_true:
    cmp     byte [rdi], 0
    je      .no
    call    to_int
    cmp     byte [int_ok], 0
    je      .yes
    cmp     qword [intval], 0
    je      .no
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

; alloc_int: render rax into the arena and return a pointer to it.
alloc_int:
    push    rbx
    mov     rbx, [arenaptr]
    xor     r8, r8
    test    rax, rax
    jns     .digits
    mov     r8, 1
    neg     rax
.digits:
    mov     rsi, numbuf + 63
    mov     byte [rsi], 0
    mov     r10, 10
.digit:
    xor     rdx, rdx
    div     r10
    dec     rsi
    add     dl, '0'
    mov     [rsi], dl
    test    rax, rax
    jnz     .digit
    test    r8, r8
    jz      .copy
    dec     rsi
    mov     byte [rsi], '-'
.copy:
    mov     al, [rsi]
    mov     [rbx], al
    test    al, al
    jz      .done
    inc     rbx
    inc     rsi
    jmp     .copy
.done:
    inc     rbx
    mov     rax, [arenaptr]
    mov     [arenaptr], rbx
    pop     rbx
    ret

; alloc_str: copy rcx bytes at rsi into the arena, NUL terminated.
alloc_str:
    push    rbx
    mov     rbx, [arenaptr]
    mov     rax, rbx
    add     rax, rcx
    add     rax, 1
    mov     rdx, arena + ARENACAP
    cmp     rax, rdx
    jae     .empty
.copy:
    test    rcx, rcx
    jz      .done
    mov     al, [rsi]
    mov     [rbx], al
    inc     rbx
    inc     rsi
    dec     rcx
    jmp     .copy
.done:
    mov     byte [rbx], 0
    inc     rbx
    mov     rax, [arenaptr]
    mov     [arenaptr], rbx
    pop     rbx
    ret
.empty:
    mov     rax, str_empty
    pop     rbx
    ret

; streq: are the NUL-terminated strings at rdi and rsi equal? al = 1/0.
streq:
    push    rdi
    push    rsi
.scan:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .no
    test    al, al
    jz      .yes
    inc     rdi
    inc     rsi
    jmp     .scan
.yes:
    mov     al, 1
    pop     rsi
    pop     rdi
    ret
.no:
    xor     al, al
    pop     rsi
    pop     rdi
    ret

; strcmp_z: byte order comparison of rdi against rsi, in rax as -1, 0 or 1.
strcmp_z:
.scan:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]
    cmp     al, cl
    jne     .differ
    test    al, al
    jz      .same
    inc     rdi
    inc     rsi
    jmp     .scan
.differ:
    cmp     al, cl
    jb      .less
    mov     rax, 1
    ret
.less:
    mov     rax, -1
    ret
.same:
    xor     rax, rax
    ret

; strlen_z: length of the NUL-terminated string at rdi, in rax.
strlen_z:
    xor     rax, rax
.scan:
    cmp     byte [rdi + rax], 0
    je      .out
    inc     rax
    jmp     .scan
.out:
    ret
