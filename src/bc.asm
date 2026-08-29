; src/bc.asm -- bc(1): an arbitrary precision calculator language.
; Usage: bc [-l] [file ...]
;
; A number is a string of decimal digits held least significant first, with
; a count of how many of them fall after the point. Nothing is rounded: the
; language says exactly how many places each operation keeps, so arithmetic
; is carried out in full and then truncated to that many, which is why
; 1/3*3 is .999999999999999999999 and not 1.
;
; The interpreter walks the source text directly. A statement is executed
; where it stands, and a construct that runs its body more than once -- a
; loop, a function -- keeps the span of text the body occupies and returns
; the cursor to its start. Nothing is compiled, so a function's body is
; simply the text between its braces.
;
; Working values are bump-allocated from a scratch arena that is unwound at
; the end of every statement; anything that has to outlive the statement
; that made it -- what a variable holds, what a function returns -- is
; copied into a second arena that is never unwound.
;
; -l loads the standard maths library, which is written in bc itself and
; carried here as text: e, l, s, c, a and j come out of running it.

    %include "include/sysdefs.inc"

    %define SYS_MMAP_ID 9

    %define PROT_READ_WRITE 3
    %define MAP_PRIVATE_ANON 0x22

    %define VAR_ARENA_CAP 0x30000000
    %define TMP_ARENA_CAP 0x30000000

; a number: a header followed by its digits, least significant first.
    %define NUM_LEN 0                   ;digits stored
    %define NUM_RDX 8                   ;how many of them are after the point
    %define NUM_NEG 16
    %define NUM_CAP 24
    %define NUM_DIG 32

    %define SRCCAP 1048576
    %define OUTCAP 65536
    %define NAMECAP 65536
    %define MAXNAMES 4096
    %define MAXFUNCS 256
    %define MAXPARAMS 32
    %define MAXSAVES 65536
    %define LINE_LEN 69

; a function: name index, body span, and its parameter and auto lists.
    %define FN_NAME 0
    %define FN_SRC 8
    %define FN_START 16
    %define FN_END 24
    %define FN_NPARAM 32
    %define FN_NAUTO 40
    %define FN_PARAMS 48                ;MAXPARAMS entries, name index
    %define FN_PARRAY 48 + MAXPARAMS * 8
    %define FN_AUTOS 48 + MAXPARAMS * 16
    %define FN_AARRAY 48 + MAXPARAMS * 24
    %define FN_SIZE 48 + MAXPARAMS * 32

; token kinds
    %define T_EOF 0
    %define T_NUMBER 1
    %define T_NAME 2
    %define T_STRING 3
    %define T_LPAREN 4
    %define T_RPAREN 5
    %define T_LBRACKET 6
    %define T_RBRACKET 7
    %define T_LBRACE 8
    %define T_RBRACE 9
    %define T_SCOLON 10
    %define T_COMMA 11
    %define T_NEWLINE 12
    %define T_PLUS 13
    %define T_MINUS 14
    %define T_STAR 15
    %define T_SLASH 16
    %define T_PERCENT 17
    %define T_CARET 18
    %define T_ASSIGN 19
    %define T_ASSIGN_PLUS 20
    %define T_ASSIGN_MINUS 21
    %define T_ASSIGN_STAR 22
    %define T_ASSIGN_SLASH 23
    %define T_ASSIGN_PERCENT 24
    %define T_ASSIGN_CARET 25
    %define T_EQ 26
    %define T_LE 27
    %define T_GE 28
    %define T_NE 29
    %define T_LT 30
    %define T_GT 31
    %define T_AND 32
    %define T_OR 33
    %define T_NOT 34
    %define T_INC 35
    %define T_DEC 36
    %define T_KEY_AUTO 37
    %define T_KEY_BREAK 38
    %define T_KEY_CONTINUE 39
    %define T_KEY_DEFINE 40
    %define T_KEY_FOR 41
    %define T_KEY_IF 42
    %define T_KEY_ELSE 43
    %define T_KEY_HALT 44
    %define T_KEY_IBASE 45
    %define T_KEY_OBASE 46
    %define T_KEY_SCALE 47
    %define T_KEY_LAST 48
    %define T_KEY_LENGTH 49
    %define T_KEY_PRINT 50
    %define T_KEY_QUIT 51
    %define T_KEY_READ 52
    %define T_KEY_RETURN 53
    %define T_KEY_SQRT 54
    %define T_KEY_WHILE 55
    %define T_KEY_LIMITS 56
    %define T_KEY_ABS 57

; what a statement did, so a loop or a call knows to stop early
    %define FLOW_NONE 0
    %define FLOW_BREAK 1
    %define FLOW_CONTINUE 2
    %define FLOW_RETURN 3

section .bss
    var_base    resq 1
    var_top     resq 1
    tmp_base    resq 1
    tmp_top     resq 1

    srcbuf      resb SRCCAP
    srcused     resq 1
    outbuf      resb OUTCAP
    outlen      resq 1
    nchars      resq 1

    namebuf     resb NAMECAP
    nameused    resq 1
    name_off    resq MAXNAMES           ;where each name's text starts
    name_len    resq MAXNAMES
    namecount   resq 1
    var_slot    resq MAXNAMES           ;the number a name holds
    arr_slot    resq MAXNAMES           ;the vector a name holds
    fn_slot     resq MAXNAMES           ;the function a name names

    funcs       resb MAXFUNCS * FN_SIZE
    funccount   resq 1

    save_name   resq MAXSAVES
    save_val    resq MAXSAVES
    save_kind   resb MAXSAVES
    savetop     resq 1

    src_ptr     resq 1                  ;the text being read
    src_end     resq 1
    src_pos     resq 1
    tok_type    resq 1
    tok_start   resq 1
    tok_len     resq 1
    tok_pos     resq 1                  ;where the token began
    peeked      resq 1

    v_ibase     resq 1
    v_obase     resq 1
    v_scale     resq 1
    v_last      resq 1
    opt_lib     resb 1
    quitting    resb 1
    flow        resq 1
    retval      resq 1
    zero_num    resq 1
    one_num     resq 1
    printed     resq 1                  ;whether the statement printed a value

    stbuf       resb 160
    numtok      resb 65536
    digitstack  resq 65536
    lv_kind     resq 1
    lv_a        resq 1
    lv_b        resq 1
    stmt_assign resq 1

section .data
    kw_auto     db "auto", 0
    kw_break    db "break", 0
    kw_continue db "continue", 0
    kw_define   db "define", 0
    kw_for      db "for", 0
    kw_if       db "if", 0
    kw_limits   db "limits", 0
    kw_return   db "return", 0
    kw_while    db "while", 0
    kw_halt     db "halt", 0
    kw_last     db "last", 0
    kw_ibase    db "ibase", 0
    kw_obase    db "obase", 0
    kw_scale    db "scale", 0
    kw_length   db "length", 0
    kw_print    db "print", 0
    kw_sqrt     db "sqrt", 0
    kw_abs      db "abs", 0
    kw_quit     db "quit", 0
    kw_read     db "read", 0
    kw_else     db "else", 0

; the keyword table, walked in order so that a name is only a name when no
; keyword claims it
    kw_names    dq kw_auto, kw_break, kw_continue, kw_define, kw_for, kw_if
    dq kw_limits, kw_return, kw_while, kw_halt, kw_last, kw_ibase
    dq kw_obase, kw_scale, kw_length, kw_print, kw_sqrt, kw_abs
    dq kw_quit, kw_read, kw_else
    kw_tokens   dq T_KEY_AUTO, T_KEY_BREAK, T_KEY_CONTINUE, T_KEY_DEFINE
    dq T_KEY_FOR, T_KEY_IF, T_KEY_LIMITS, T_KEY_RETURN
    dq T_KEY_WHILE, T_KEY_HALT, T_KEY_LAST, T_KEY_IBASE
    dq T_KEY_OBASE, T_KEY_SCALE, T_KEY_LENGTH, T_KEY_PRINT
    dq T_KEY_SQRT, T_KEY_ABS, T_KEY_QUIT, T_KEY_READ, T_KEY_ELSE
    kw_count    equ 21

    hex_digits  db "0123456789ABCDEF"

e_syntax    db "bc: syntax error", 10
    e_syntax_len equ $ - e_syntax
e_divzero   db "bc: divide by zero", 10
    e_divzero_len equ $ - e_divzero
e_negsqrt   db "bc: square root of a negative number", 10
    e_negsqrt_len equ $ - e_negsqrt
e_open      db "bc: cannot open file", 10
    e_open_len  equ $ - e_open
e_memory    db "bc: out of memory", 10
    e_memory_len equ $ - e_memory

; the standard maths library, which is written in bc itself
bc_lib:
    db `scale=20;`, 10
    db `define e(x){`, 10
    db `  auto b,s,n,r,d,i,p,f,v;`, 10
    db `  b=ibase;`, 10
    db `  ibase=A;`, 10
    db `  if(x<0){`, 10
    db `    n=1; x=-x;`, 10
    db `  }`, 10
    db `  s=scale;`, 10
    db `  r=6+s+.44*x;`, 10
    db `  scale=scale(x)+1;`, 10
    db `  while(x>1){`, 10
    db `    d+=1; x/=2;`, 10
    db `    scale+=1;`, 10
    db `  }`, 10
    db `  scale=r;`, 10
    db `  r=x+1; p=x; f=v=1;`, 10
    db `  for(i=2;v;++i){;`, 10
    db `    p*=x; f*=i; v=p/f; r+=v;`, 10
    db `  }`, 10
    db `  while(d--)r*=r;`, 10
    db `  scale=s;`, 10
    db `  ibase=b;`, 10
    db `  if(n)return(1/r)`, 10
    db `    return(r/1)`, 10
    db `}`, 10
    db `define l(x){`, 10
    db `  auto b,s,r,p,a,q,i,v;`, 10
    db `  b=ibase;`, 10
    db `  ibase=A;`, 10
    db `  if(x<=0){;`, 10
    db `    r=(1-10^scale)/1;`, 10
    db `    ibase=b;`, 10
    db `    return(r)`, 10
    db `  }`, 10
    db `  s=scale;`, 10
    db `  scale+=6;`, 10
    db `  p=2;`, 10
    db `  while(x>=2){;`, 10
    db `    p*=2;`, 10
    db `    x=sqrt(x);`, 10
    db `  }`, 10
    db `  while(x<=.5){;`, 10
    db `    p*=2;`, 10
    db `    x=sqrt(x);`, 10
    db `  }`, 10
    db `  r=a=(x-1)/(x+1);`, 10
    db `  q=a*a;`, 10
    db `  v=1;`, 10
    db `  for(i=3;v;i+=2){;`, 10
    db `    a*=q; v=a/i; r+=v;`, 10
    db `  }`, 10
    db `  r*=p;`, 10
    db `  scale=s;`, 10
    db `  ibase=b;`, 10
    db `  return(r/1)`, 10
    db `}`, 10
    db `define s(x){`, 10
    db `  auto b,s,r,a,q,i;`, 10
    db `  if(x<0)return(-s(-x))`, 10
    db `    b=ibase;`, 10
    db `  ibase=A;`, 10
    db `  s=scale;`, 10
    db `  scale=1.1*s+2;`, 10
    db `  a=a(1);`, 10
    db `  scale=0;`, 10
    db `  q=(x/a+2)/4;`, 10
    db `  x-=4*q*a;`, 10
    db `  if(q%2) x=-x;`, 10
    db `  scale=s+2;`, 10
    db `  r=a=x;`, 10
    db `  q=-x*x;`, 10
    db `  for(i=3;a;i+=2){;`, 10
    db `    a*=q/(i*(i-1)); r+=a;`, 10
    db `  }`, 10
    db `  scale=s;`, 10
    db `  ibase=b;`, 10
    db `  return(r/1)`, 10
    db `}`, 10
    db `define c(x){`, 10
    db `  auto b,s;`, 10
    db `  b=ibase;`, 10
    db `  ibase=A;`, 10
    db `  s=scale;`, 10
    db `  scale*=1.2;`, 10
    db `  x=s(2*a(1)+x);`, 10
    db `  scale=s;`, 10
    db `  ibase=b;`, 10
    db `  return(x/1)`, 10
    db `}`, 10
    db `define a(x){`, 10
    db `  auto b,s,r,n,a,m,t,f,i,u;`, 10
    db `  b=ibase;`, 10
    db `  ibase=A;`, 10
    db `  n=1;`, 10
    db `  if(x<0){`, 10
    db `    n=-1;`, 10
    db `    x=-x;`, 10
    db `  }`, 10
    db `  if(scale<65){`, 10
    db `    if(x==1){;`, 10
    db `      r=.7853981633974483096156608458198757210492923498437764552437361480/n;`, 10
    db `      ibase=b;`, 10
    db `      return(r)`, 10
    db `    }`, 10
    db `    if(x==.2){;`, 10
    db `      r=.1973955598498807583700497651947902934475851037878521015176889402/n;`, 10
    db `      ibase=b;`, 10
    db `      return(r)`, 10
    db `    }`, 10
    db `  }`, 10
    db `  s=scale;`, 10
    db `  if(x>.2){`, 10
    db `    scale+=5; a=a(.2);`, 10
    db `  }`, 10
    db `  scale=s+3;`, 10
    db `  while(x>.2){`, 10
    db `    m+=1; x=(x-.2)/(1+.2*x);`, 10
    db `  }`, 10
    db `  r=u=x; f=-x*x; t=1;`, 10
    db `  for(i=3;t;i+=2){;`, 10
    db `    u*=f; t=u/i; r+=t;`, 10
    db `  }`, 10
    db `  scale=s;`, 10
    db `  ibase=b;`, 10
    db `  return((m*a+r)/n)`, 10
    db `}`, 10
    db `define j(n,x){`, 10
    db `  auto b,s,o,a,i,v,f;`, 10
    db `  b=ibase;`, 10
    db `  ibase=A;`, 10
    db `  s=scale;`, 10
    db `  scale=0;`, 10
    db `  n/=1;`, 10
    db `  if(n<0){`, 10
    db `    n=-n; o=n%2;`, 10
    db `  }`, 10
    db `  a=1;`, 10
    db `  for(i=2;i<=n;++i)a*=i;`, 10
    db `  scale=1.5*s;`, 10
    db `  a=(x^n)/2^n/a;`, 10
    db `  r=v=1;`, 10
    db `  f=-x*x/4;`, 10
    db `  scale+=length(a)-scale(a);`, 10
    db `  for(i=1;v;++i){;`, 10
    db `    v=v*f/i/(n+i); r+=v;`, 10
    db `  }`, 10
    db `  scale=s;`, 10
    db `  ibase=b;`, 10
    db `  if(o)a=-a;`, 10
    db `  return(a*r/1)`, 10
    db `}`, 10
    db 0

section .text
global _start

_start:
    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;argv[1]
    dec     r12
    call    arena_init
    call    setup_globals

; -l and -- are the only options that matter here; everything else is a file
.args:
    cmp     r12, 0
    jle     .loaded
    mov     rdi, [r13]
    cmp     byte [rdi], '-'
    jne     .loaded
    cmp     byte [rdi + 1], 0
    je      .loaded
    inc     rdi
.flag:
    movzx   eax, byte [rdi]
    test    al, al
    jz      .nextarg
    inc     rdi
    cmp     al, 'l'
    je      .setlib
    cmp     al, 'q'
    je      .flag
    cmp     al, 's'
    je      .flag
    cmp     al, 'w'
    je      .flag
    cmp     al, '-'
    je      .flag
    jmp     .flag
.setlib:
    mov     byte [opt_lib], 1
    jmp     .flag
.nextarg:
    add     r13, 8
    dec     r12
    jmp     .args

.loaded:
    cmp     byte [opt_lib], 0
    je      .files
    mov     rdi, bc_lib
    call    run_text

.files:
    cmp     r12, 0
    jle     .stdin
    cmp     byte [quitting], 0
    jne     .done
    mov     rdi, [r13]
    call    run_file
    add     r13, 8
    dec     r12
    jmp     .files

.stdin:
    cmp     byte [quitting], 0
    jne     .done
    xor     rdi, rdi
    call    read_all_fd                 ;-> rax text, NUL terminated
    mov     rdi, rax
    call    run_text
.done:
    call    out_flush
    exit    0

; ---------------------------------------------------------------------------
; arena_init: two bump arenas. The scratch one is unwound at the end of every
; statement; the other holds what variables and returned values point at, and
; is never unwound.
; ---------------------------------------------------------------------------
arena_init:
    mov     rax, SYS_MMAP_ID
    xor     rdi, rdi
    mov     rsi, VAR_ARENA_CAP
    mov     rdx, PROT_READ_WRITE
    mov     r10, MAP_PRIVATE_ANON
    mov     r8, -1
    xor     r9, r9
    syscall
    cmp     rax, -4095
    jae     no_memory
    mov     [var_base], rax
    mov     [var_top], rax
    mov     rax, SYS_MMAP_ID
    xor     rdi, rdi
    mov     rsi, TMP_ARENA_CAP
    mov     rdx, PROT_READ_WRITE
    mov     r10, MAP_PRIVATE_ANON
    mov     r8, -1
    xor     r9, r9
    syscall
    cmp     rax, -4095
    jae     no_memory
    mov     [tmp_base], rax
    mov     [tmp_top], rax
    ret

no_memory:
    write   STDERR_FILENO, e_memory, e_memory_len
    exit    1

; tmp_alloc: rdi bytes from the scratch arena, eight-byte aligned.
tmp_alloc:
    add     rdi, 7
    and     rdi, -8
    mov     rax, [tmp_top]
    add     rdi, rax
    mov     rdx, [tmp_base]
    add     rdx, TMP_ARENA_CAP
    cmp     rdi, rdx
    jae     no_memory
    mov     [tmp_top], rdi
    ret

; var_alloc: rdi bytes from the arena that outlives the statement.
var_alloc:
    add     rdi, 7
    and     rdi, -8
    mov     rax, [var_top]
    add     rdi, rax
    mov     rdx, [var_base]
    add     rdx, VAR_ARENA_CAP
    cmp     rdi, rdx
    jae     no_memory
    mov     [var_top], rdi
    ret

; ---------------------------------------------------------------------------
; setup_globals: ibase, obase and scale start at ten, ten and zero, and last
; starts at nothing.
; ---------------------------------------------------------------------------
setup_globals:
    mov     qword [v_ibase], 10
    mov     qword [v_obase], 10
    mov     qword [v_scale], 0
    mov     rdi, 4
    call    var_num_new
    mov     [v_last], rax
    mov     [zero_num], rax
    mov     rdi, 4
    call    var_num_new
    mov     qword [rax + NUM_LEN], 1
    mov     byte [rax + NUM_DIG], 1
    mov     [one_num], rax
    ret

; ---------------------------------------------------------------------------
; run_file: read a file whole and run it.
; ---------------------------------------------------------------------------
run_file:
    push    rbx
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .bad
    mov     rdi, rax
    push    rdi
    call    read_all_fd
    mov     rbx, rax
    pop     rdi
    mov     rax, SYS_CLOSE
    syscall
    mov     rdi, rbx
    call    run_text
    pop     rbx
    ret
.bad:
    call    out_flush
    write   STDERR_FILENO, e_open, e_open_len
    exit    1

; read_all_fd: the whole of a descriptor, NUL terminated, kept for as long as
; the program runs since function bodies are spans of it.
read_all_fd:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, [srcused]
    lea     rbx, [srcbuf + r13]
.chunk:
    mov     rax, SYS_READ
    mov     rdi, r12
    mov     rsi, rbx
    mov     rdx, 65536
    syscall
    test    rax, rax
    jle     .eof
    add     rbx, rax
    jmp     .chunk
.eof:
    mov     byte [rbx], 0
    inc     rbx
    lea     rax, [srcbuf + r13]
    sub     rbx, srcbuf
    mov     [srcused], rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; out_char / out_bytes / out_flush: output is buffered, since bc writes a
; digit at a time.
; ---------------------------------------------------------------------------
out_char:
    push    rcx
    mov     rcx, [outlen]
    mov     [outbuf + rcx], al
    inc     rcx
    mov     [outlen], rcx
    cmp     rcx, OUTCAP - 16
    jb      .out
    call    out_flush
.out:
    pop     rcx
    ret

out_bytes:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
.byte:
    test    r12, r12
    jz      .out
    mov     al, [rbx]
    call    out_char
    inc     rbx
    dec     r12
    jmp     .byte
.out:
    pop     r12
    pop     rbx
    ret

out_str:
    push    rbx
    mov     rbx, rdi
.byte:
    mov     al, [rbx]
    test    al, al
    jz      .out
    call    out_char
    inc     rbx
    jmp     .byte
.out:
    pop     rbx
    ret

out_flush:
    push    rcx
    mov     rdx, [outlen]
    test    rdx, rdx
    jz      .out
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, outbuf
    syscall
    mov     qword [outlen], 0
.out:
    pop     rcx
    ret

syntax_error:
    call    out_flush
    write   STDERR_FILENO, e_syntax, e_syntax_len
    exit    1

divide_by_zero:
    call    out_flush
    write   STDERR_FILENO, e_divzero, e_divzero_len
    exit    1

negative_sqrt:
    call    out_flush
    write   STDERR_FILENO, e_negsqrt, e_negsqrt_len
    exit    1

; ---------------------------------------------------------------------------
; Numbers.
;
; A number is a header -- how many digits, how many of them after the point,
; and a sign -- followed by the digits themselves, least significant first.
; Nothing here rounds: a result is computed in full and then cut to the
; number of places the language asks for.
; ---------------------------------------------------------------------------

; num_new: a number with room for rdi digits, reading as zero.
num_new:
    push    rbx
    mov     rbx, rdi
    cmp     rbx, 8
    jae     .sized
    mov     rbx, 8
.sized:
    lea     rdi, [rbx + NUM_DIG + 8]
    call    tmp_alloc
    mov     qword [rax + NUM_LEN], 0
    mov     qword [rax + NUM_RDX], 0
    mov     qword [rax + NUM_NEG], 0
    mov     [rax + NUM_CAP], rbx
    push    rax
    lea     rdi, [rax + NUM_DIG]
    lea     rsi, [rbx + 8]
    call    zero_bytes
    pop     rax
    pop     rbx
    ret

; var_num_new: the same, from the arena that outlives the statement.
var_num_new:
    push    rbx
    mov     rbx, rdi
    cmp     rbx, 8
    jae     .sized
    mov     rbx, 8
.sized:
    lea     rdi, [rbx + NUM_DIG + 8]
    call    var_alloc
    mov     qword [rax + NUM_LEN], 0
    mov     qword [rax + NUM_RDX], 0
    mov     qword [rax + NUM_NEG], 0
    mov     [rax + NUM_CAP], rbx
    push    rax
    lea     rdi, [rax + NUM_DIG]
    lea     rsi, [rbx + 8]
    call    zero_bytes
    pop     rax
    pop     rbx
    ret

zero_bytes:
    test    rsi, rsi
    jz      .out
    mov     byte [rdi], 0
    inc     rdi
    dec     rsi
    jmp     zero_bytes
.out:
    ret

copy_bytes:
    test    rdx, rdx
    jz      .out
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rdx
    jmp     copy_bytes
.out:
    ret

; num_copy: a scratch copy of rdi.
num_copy:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, [rbx + NUM_LEN]
    add     rdi, 4
    call    num_new
    mov     r12, rax
    mov     rcx, [rbx + NUM_LEN]
    mov     [r12 + NUM_LEN], rcx
    mov     rcx, [rbx + NUM_RDX]
    mov     [r12 + NUM_RDX], rcx
    mov     rcx, [rbx + NUM_NEG]
    mov     [r12 + NUM_NEG], rcx
    lea     rdi, [r12 + NUM_DIG]
    lea     rsi, [rbx + NUM_DIG]
    mov     rdx, [rbx + NUM_LEN]
    call    copy_bytes
    mov     rax, r12
    pop     r12
    pop     rbx
    ret

; var_num_copy: a copy that will outlive the statement that made it.
var_num_copy:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, [rbx + NUM_LEN]
    add     rdi, 4
    call    var_num_new
    mov     r12, rax
    mov     rcx, [rbx + NUM_LEN]
    mov     [r12 + NUM_LEN], rcx
    mov     rcx, [rbx + NUM_RDX]
    mov     [r12 + NUM_RDX], rcx
    mov     rcx, [rbx + NUM_NEG]
    mov     [r12 + NUM_NEG], rcx
    lea     rdi, [r12 + NUM_DIG]
    lea     rsi, [rbx + NUM_DIG]
    mov     rdx, [rbx + NUM_LEN]
    call    copy_bytes
    mov     rax, r12
    pop     r12
    pop     rbx
    ret

; num_zero: a fresh zero.
num_zero:
    mov     rdi, 8
    jmp     num_new

; num_one: a fresh one.
num_one:
    push    rbx
    mov     rdi, 8
    call    num_new
    mov     qword [rax + NUM_LEN], 1
    mov     byte [rax + NUM_DIG], 1
    pop     rbx
    ret

; num_clean: drop leading zeros, and give up the sign when nothing is left.
num_clean:
    mov     rcx, [rdi + NUM_LEN]
.strip:
    test    rcx, rcx
    jz      .empty
    cmp     byte [rdi + NUM_DIG + rcx - 1], 0
    jne     .kept
    dec     rcx
    jmp     .strip
.empty:
    mov     qword [rdi + NUM_LEN], 0
    mov     qword [rdi + NUM_NEG], 0
    ret
.kept:
    mov     [rdi + NUM_LEN], rcx
    cmp     rcx, [rdi + NUM_RDX]
    jae     .out
    mov     rcx, [rdi + NUM_RDX]
    mov     [rdi + NUM_LEN], rcx
.out:
    ret

; num_truncate: drop rsi digits from the low end, taking the point with them.
; What is left above the length is cleared, so that a number's digits past
; its length can always be trusted to be zero.
num_truncate:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    test    r12, r12
    jz      .out
    mov     rcx, [rbx + NUM_LEN]
    cmp     r12, rcx
    jb      .shift
    mov     qword [rbx + NUM_LEN], 0
    mov     qword [rbx + NUM_NEG], 0
    jmp     .point
.shift:
    sub     rcx, r12
    mov     r13, rcx
    lea     rdi, [rbx + NUM_DIG]
    lea     rsi, [rbx + NUM_DIG + r12]
    mov     rdx, r13
    call    copy_bytes
    mov     [rbx + NUM_LEN], r13
    lea     rdi, [rbx + NUM_DIG + r13]
    mov     rsi, [rbx + NUM_CAP]
    sub     rsi, r13
    add     rsi, 8
    call    zero_bytes
.point:
    mov     rcx, [rbx + NUM_RDX]
    sub     rcx, r12
    mov     [rbx + NUM_RDX], rcx
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; num_widen: rdi held in a place with room for at least rsi digits, moved if
; it is not. Cleaning a number can push its length up to the number of places
; it carries, so anything about to be cleaned needs room for them.
num_widen:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    cmp     r12, [rbx + NUM_CAP]
    jbe     .enough
    lea     rdi, [r12 + 4]
    call    num_new
    mov     rcx, [rbx + NUM_LEN]
    mov     [rax + NUM_LEN], rcx
    mov     rcx, [rbx + NUM_RDX]
    mov     [rax + NUM_RDX], rcx
    mov     rcx, [rbx + NUM_NEG]
    mov     [rax + NUM_NEG], rcx
    push    rax
    lea     rdi, [rax + NUM_DIG]
    lea     rsi, [rbx + NUM_DIG]
    mov     rdx, [rbx + NUM_LEN]
    call    copy_bytes
    pop     rax
    jmp     .out
.enough:
    mov     rax, rbx
.out:
    pop     r12
    pop     rbx
    ret

; num_setrdx: give the number exactly rsi places after the point, padding
; with zeros or cutting, which is what every operation does once it has its
; full-precision answer.
num_setrdx:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     rsi, r12
    call    num_widen
    mov     rbx, rax
    mov     rax, [rbx + NUM_RDX]
    cmp     rax, r12
    je      .done
    ja      .cut
; pad: the digits move up, and zeros fill in underneath
    mov     r13, r12
    sub     r13, rax                    ;how many to add
    mov     rax, [rbx + NUM_LEN]
    test    rax, rax
    jz      .padempty
    mov     rdi, [rbx + NUM_LEN]
    add     rdi, r13
    add     rdi, 4
    call    num_new
    mov     rcx, [rbx + NUM_LEN]
    add     rcx, r13
    mov     [rax + NUM_LEN], rcx
    mov     [rax + NUM_RDX], r12
    mov     rcx, [rbx + NUM_NEG]
    mov     [rax + NUM_NEG], rcx
    push    rax
    lea     rdi, [rax + NUM_DIG + r13]
    lea     rsi, [rbx + NUM_DIG]
    mov     rdx, [rbx + NUM_LEN]
    call    copy_bytes
    pop     rax
    mov     rbx, rax
    jmp     .done
.padempty:
    mov     [rbx + NUM_RDX], r12
    jmp     .done
.cut:
    sub     rax, r12
    mov     rdi, rbx
    mov     rsi, rax
    call    num_truncate
.done:
    mov     rdi, rbx
    call    num_clean
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

; num_retire: the answer to a multiplication or a division -- cut to rsi
; places, tidied, and signed by whether its operands disagreed.
;   rdi = number, rsi = places, rdx = first sign, rcx = second sign
num_retire:
    push    rbx
    push    r12
    mov     r12, rdx
    xor     r12, rcx                    ;non-zero when the signs disagreed
    call    num_setrdx
    mov     rbx, rax
    cmp     qword [rbx + NUM_LEN], 0
    je      .out
    xor     rax, rax
    test    r12, r12
    jz      .store
    mov     rax, 1
.store:
    mov     [rbx + NUM_NEG], rax
.out:
    mov     rax, rbx
    pop     r12
    pop     rbx
    ret

; num_digit: the digit of rdi standing at power rsi, or zero when the number
; does not reach that far.
num_digit:
    mov     rax, rsi
    add     rax, [rdi + NUM_RDX]
    js      .none
    cmp     rax, [rdi + NUM_LEN]
    jae     .none
    movzx   eax, byte [rdi + NUM_DIG + rax]
    ret
.none:
    xor     rax, rax
    ret

; num_is_zero: al = 1 when the number has no digits left.
num_is_zero:
    xor     eax, eax
    cmp     qword [rdi + NUM_LEN], 0
    jne     .out
    mov     al, 1
.out:
    ret

; num_int_len: how many digits stand before the point.
num_int_len:
    mov     rax, [rdi + NUM_LEN]
    sub     rax, [rdi + NUM_RDX]
    jns     .out
    xor     rax, rax
.out:
    ret

; num_cmp_abs: compare magnitudes, ignoring both signs. rax < 0, 0 or > 0.
num_cmp_abs:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    call    num_int_len
    mov     r13, rax
    mov     rdi, r12
    call    num_int_len
    sub     r13, rax
    jnz     .bydigits
; the same number of digits before the point: walk down from the top
    mov     rdi, rbx
    call    num_int_len
    mov     r14, rax
    dec     r14                         ;the power of the leading digit
    mov     r15, [rbx + NUM_RDX]
    cmp     r15, [r12 + NUM_RDX]
    jae     .haverdx
    mov     r15, [r12 + NUM_RDX]
.haverdx:
    neg     r15                         ;the lowest power either reaches
.walk:
    cmp     r14, r15
    jl      .equal
    mov     rdi, rbx
    mov     rsi, r14
    call    num_digit
    mov     r13, rax
    mov     rdi, r12
    mov     rsi, r14
    call    num_digit
    sub     r13, rax
    jnz     .out
    dec     r14
    jmp     .walk
.equal:
    xor     r13, r13
.out:
    mov     rax, r13
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.bydigits:
    mov     rax, r13
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; num_cmp: compare two numbers, signs and all.
num_cmp:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    cmp     qword [rbx + NUM_LEN], 0
    jne     .aset
    cmp     qword [r12 + NUM_LEN], 0
    je      .same
    cmp     qword [r12 + NUM_NEG], 0
    jne     .greater
    jmp     .less
.aset:
    cmp     qword [r12 + NUM_LEN], 0
    jne     .both
    cmp     qword [rbx + NUM_NEG], 0
    jne     .less
    jmp     .greater
.both:
    mov     rax, [rbx + NUM_NEG]
    cmp     rax, [r12 + NUM_NEG]
    je      .magnitude
    cmp     qword [rbx + NUM_NEG], 0
    jne     .less
    jmp     .greater
.magnitude:
    mov     rdi, rbx
    mov     rsi, r12
    call    num_cmp_abs
    cmp     qword [rbx + NUM_NEG], 0
    je      .out
    neg     rax
.out:
    pop     r12
    pop     rbx
    ret
.same:
    xor     rax, rax
    jmp     .out
.less:
    mov     rax, -1
    jmp     .out
.greater:
    mov     rax, 1
    jmp     .out

; num_from_uint: rdi as a number.
num_from_uint:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     rdi, 24
    call    num_new
    mov     rbx, rax
    xor     r13, r13
    test    r12, r12
    jnz     .digits
    jmp     .done
.digits:
    mov     rax, r12
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    mov     r12, rax
    mov     [rbx + NUM_DIG + r13], dl
    inc     r13
    test    r12, r12
    jnz     .digits
.done:
    mov     [rbx + NUM_LEN], r13
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

; num_to_uint: the whole part of a number, as a machine integer.
num_to_uint:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    call    num_int_len
    mov     r12, rax                    ;digits before the point
    xor     r13, r13
.digit:
    test    r12, r12
    jz      .out
    dec     r12
    mov     rdi, rbx
    mov     rsi, r12
    call    num_digit
    imul    r13, r13, 10
    add     r13, rax
    jmp     .digit
.out:
    mov     rax, r13
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Arithmetic. Addition and subtraction line the two numbers up by their
; points; multiplication and division work on the digits as whole numbers and
; put the point back afterwards.
; ---------------------------------------------------------------------------

; num_a: magnitudes added, the sign taken from the first. rdx says whether a
; missing first operand means the second is being subtracted.
num_a:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r15, rdx
    cmp     qword [rbx + NUM_LEN], 0
    jne     .bcheck
    mov     rdi, r12
    call    num_copy
    test    r15, r15
    jz      .ret
    cmp     qword [rax + NUM_LEN], 0
    je      .ret
    mov     rcx, [rax + NUM_NEG]
    xor     rcx, 1
    mov     [rax + NUM_NEG], rcx
    jmp     .ret
.bcheck:
    cmp     qword [r12 + NUM_LEN], 0
    jne     .work
    mov     rdi, rbx
    call    num_copy
    jmp     .ret
.work:
    mov     r13, [rbx + NUM_RDX]        ;places kept in the answer
    cmp     r13, [r12 + NUM_RDX]
    jae     .haverdx
    mov     r13, [r12 + NUM_RDX]
.haverdx:
    mov     rdi, rbx
    call    num_int_len
    mov     r14, rax
    mov     rdi, r12
    call    num_int_len
    cmp     r14, rax
    jae     .haveint
    mov     r14, rax
.haveint:
    inc     r14                         ;room for a carry off the top
    add     r14, r13                    ;the answer's whole length
    lea     rdi, [r14 + 4]
    call    num_new
    push    rax
    xor     rcx, rcx                    ;index into the answer
    xor     r8, r8                      ;carry
.digit:
    cmp     rcx, r14
    jae     .stored
    mov     rsi, rcx
    sub     rsi, r13                    ;the power this place stands for
    push    rcx
    push    r8
    push    rsi
    mov     rdi, rbx
    call    num_digit
    mov     r9, rax
    pop     rsi
    push    r9
    mov     rdi, r12
    call    num_digit
    pop     r9
    pop     r8
    pop     rcx
    add     rax, r9
    add     rax, r8
    xor     r8, r8
    cmp     rax, 10
    jb      .keep
    sub     rax, 10
    mov     r8, 1
.keep:
    mov     rdx, [rsp]
    mov     [rdx + NUM_DIG + rcx], al
    inc     rcx
    jmp     .digit
.stored:
    pop     rax
    mov     [rax + NUM_LEN], r14
    mov     [rax + NUM_RDX], r13
    mov     rcx, [rbx + NUM_NEG]
    mov     [rax + NUM_NEG], rcx
    mov     rdi, rax
    push    rax
    call    num_clean
    pop     rax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; num_s: the smaller magnitude taken from the larger, and the sign worked out
; from which way round they were.
num_s:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r15, rdx
    cmp     qword [rbx + NUM_LEN], 0
    jne     .bcheck
    mov     rdi, r12
    call    num_copy
    test    r15, r15
    jz      .ret
    cmp     qword [rax + NUM_LEN], 0
    je      .ret
    mov     rcx, [rax + NUM_NEG]
    xor     rcx, 1
    mov     [rax + NUM_NEG], rcx
    jmp     .ret
.bcheck:
    cmp     qword [r12 + NUM_LEN], 0
    jne     .work
    mov     rdi, rbx
    call    num_copy
    jmp     .ret
.work:
    mov     rdi, rbx
    mov     rsi, r12
    call    num_cmp_abs
    test    rax, rax
    jz      .cancels
    jg      .afirst
; the second is the larger, so it is the one subtracted from
    mov     r8, [r12 + NUM_NEG]
    test    r15, r15
    jz      .bneg
    xor     r8, 1
.bneg:
    mov     rdi, r12
    mov     rsi, rbx
    jmp     .subtract
.afirst:
    mov     r8, [rbx + NUM_NEG]
    mov     rdi, rbx
    mov     rsi, r12
.subtract:
    mov     rbx, rdi                    ;the number subtracted from
    mov     r12, rsi                    ;the number taken away
    mov     r15, r8                     ;the sign of the answer
    mov     r13, [rbx + NUM_RDX]
    cmp     r13, [r12 + NUM_RDX]
    jae     .haverdx
    mov     r13, [r12 + NUM_RDX]
.haverdx:
    mov     rdi, rbx
    call    num_int_len
    mov     r14, rax
    add     r14, r13
    lea     rdi, [r14 + 4]
    call    num_new
    push    rax
    xor     rcx, rcx
    xor     r8, r8                      ;borrow
.digit:
    cmp     rcx, r14
    jae     .stored
    mov     rsi, rcx
    sub     rsi, r13
    push    rcx
    push    r8
    push    rsi
    mov     rdi, rbx
    call    num_digit
    mov     r9, rax
    pop     rsi
    push    r9
    mov     rdi, r12
    call    num_digit
    pop     r9
    pop     r8
    pop     rcx
    sub     r9, rax
    sub     r9, r8
    mov     r8, 0                       ;a move leaves the sign flag alone
    jns     .keep
    add     r9, 10
    mov     r8, 1
.keep:
    mov     rdx, [rsp]
    mov     [rdx + NUM_DIG + rcx], r9b
    inc     rcx
    jmp     .digit
.stored:
    pop     rax
    mov     [rax + NUM_LEN], r14
    mov     [rax + NUM_RDX], r13
    mov     [rax + NUM_NEG], r15
    mov     rdi, rax
    push    rax
    call    num_clean
    pop     rax
    jmp     .ret
.cancels:
    mov     r13, [rbx + NUM_RDX]
    cmp     r13, [r12 + NUM_RDX]
    jae     .zerordx
    mov     r13, [r12 + NUM_RDX]
.zerordx:
    call    num_zero
    mov     [rax + NUM_RDX], r13
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; num_add / num_sub: which of the two above to use falls out of the signs.
num_add:
    mov     rax, [rdi + NUM_NEG]
    cmp     rax, [rsi + NUM_NEG]
    jne     .differ
    xor     rdx, rdx
    jmp     num_a
.differ:
    xor     rdx, rdx
    jmp     num_s

num_sub:
    mov     rax, [rdi + NUM_NEG]
    cmp     rax, [rsi + NUM_NEG]
    jne     .differ
    mov     rdx, 1
    jmp     num_s
.differ:
    mov     rdx, 1
    jmp     num_a

; ---------------------------------------------------------------------------
; num_mul: rdi * rsi, kept to rdx places -- or to as many as the operands
; between them actually have, whichever is fewer.
; ---------------------------------------------------------------------------
num_mul:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
; the places kept: at least what either operand carries, never more than both
    cmp     r13, [rbx + NUM_RDX]
    jae     .past_a
    mov     r13, [rbx + NUM_RDX]
.past_a:
    cmp     r13, [r12 + NUM_RDX]
    jae     .past_b
    mov     r13, [r12 + NUM_RDX]
.past_b:
    mov     rax, [rbx + NUM_RDX]
    add     rax, [r12 + NUM_RDX]
    cmp     r13, rax
    jbe     .scaled
    mov     r13, rax
.scaled:
    mov     r14, [rbx + NUM_LEN]
    add     r14, [r12 + NUM_LEN]        ;the product's length
    lea     rdi, [r14 + 4]
    call    num_new
    mov     r15, rax
    cmp     qword [rbx + NUM_LEN], 0
    je      .assembled
    cmp     qword [r12 + NUM_LEN], 0
    je      .assembled
; the digits multiplied out, one row of the first against all of the second
    xor     rcx, rcx
.outer:
    cmp     rcx, [rbx + NUM_LEN]
    jae     .assembled
    movzx   r8d, byte [rbx + NUM_DIG + rcx]
    test    r8, r8
    jz      .nextouter
    xor     rdx, rdx                    ;index into the second
    xor     r9, r9                      ;carry
.inner:
    cmp     rdx, [r12 + NUM_LEN]
    jae     .carryout
    movzx   eax, byte [r12 + NUM_DIG + rdx]
    imul    rax, r8
    add     rax, r9
    lea     r10, [rcx + rdx]
    movzx   r11d, byte [r15 + NUM_DIG + r10]
    add     rax, r11
    xor     r9, r9
    cmp     rax, 10
    jb      .place
    push    rdx
    xor     rdx, rdx
    mov     r11, 10
    div     r11
    mov     r9, rax                     ;carry
    mov     rax, rdx                    ;digit
    pop     rdx
.place:
    mov     [r15 + NUM_DIG + r10], al
    inc     rdx
    jmp     .inner
.carryout:
    test    r9, r9
    jz      .nextouter
    lea     r10, [rcx + rdx]
    movzx   eax, byte [r15 + NUM_DIG + r10]
    add     rax, r9
    xor     r9, r9
    cmp     rax, 10
    jb      .placeout
    push    rdx
    xor     rdx, rdx
    mov     r11, 10
    div     r11
    mov     r9, rax
    mov     rax, rdx
    pop     rdx
.placeout:
    mov     [r15 + NUM_DIG + r10], al
    inc     rdx
    jmp     .carryout
.nextouter:
    inc     rcx
    jmp     .outer
.assembled:
    mov     [r15 + NUM_LEN], r14
    mov     rax, [rbx + NUM_RDX]
    add     rax, [r12 + NUM_RDX]
    mov     [r15 + NUM_RDX], rax
    mov     rdi, r15
    mov     rsi, r13
    mov     rdx, [rbx + NUM_NEG]
    mov     rcx, [r12 + NUM_NEG]
    call    num_retire
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; num_shifted: the digits of rdi as a whole number, with rsi zeros pushed in
; underneath, which is how a fractional operand is made ready for division.
; ---------------------------------------------------------------------------
num_shifted:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, [rbx + NUM_LEN]
    add     r13, r12
    lea     rdi, [r13 + 4]
    call    num_new
    push    rax
    lea     rdi, [rax + NUM_DIG + r12]
    lea     rsi, [rbx + NUM_DIG]
    mov     rdx, [rbx + NUM_LEN]
    call    copy_bytes
    pop     rax
    cmp     qword [rbx + NUM_LEN], 0
    je      .empty
    mov     [rax + NUM_LEN], r13
.empty:
    pop     r13
    pop     r12
    pop     rbx
    ret

; sub_digits: rdi[0..rdx-1] -= rsi[0..rdx-1], the borrow carried on upward.
sub_digits:
    push    rbx
    xor     rcx, rcx
    xor     r8, r8
.digit:
    cmp     rcx, rdx
    jae     .spill
    movzx   eax, byte [rdi + rcx]
    movzx   r9d, byte [rsi + rcx]
    sub     rax, r9
    sub     rax, r8
    mov     r8, 0                       ;a move leaves the sign flag alone
    jns     .keep
    add     rax, 10
    mov     r8, 1
.keep:
    mov     [rdi + rcx], al
    inc     rcx
    jmp     .digit
.spill:
    test    r8, r8
    jz      .out
    movzx   eax, byte [rdi + rcx]
    sub     rax, r8
    mov     r8, 0
    jns     .keepspill
    add     rax, 10
    mov     r8, 1
.keepspill:
    mov     [rdi + rcx], al
    inc     rcx
    jmp     .spill
.out:
    pop     rbx
    ret

; cmp_digits: compare rdi[0..rdx-1] against rsi[0..rdx-1] from the top down.
cmp_digits:
    mov     rcx, rdx
.digit:
    test    rcx, rcx
    jz      .equal
    dec     rcx
    movzx   eax, byte [rdi + rcx]
    movzx   r8d, byte [rsi + rcx]
    sub     rax, r8
    jnz     .out
    jmp     .digit
.equal:
    xor     rax, rax
.out:
    ret

; ---------------------------------------------------------------------------
; int_div: whole-number division of rdi by rsi, both taken as digit strings.
; The quotient comes back in rax; each digit is found by taking the divisor
; away until it no longer fits, which is at most nine times.
; ---------------------------------------------------------------------------
int_div:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
; the divisor, with any leading zeros ignored
    mov     r13, [r12 + NUM_LEN]
.strip:
    test    r13, r13
    jz      .divzero
    cmp     byte [r12 + NUM_DIG + r13 - 1], 0
    jne     .stripped
    dec     r13
    jmp     .strip
.divzero:
    jmp     divide_by_zero
.stripped:
    mov     rax, [rbx + NUM_LEN]
    cmp     rax, r13
    jae     .sized
    call    num_zero                    ;the divisor does not fit even once
    jmp     .out
.sized:
; a working copy of the numerator with one spare digit on top
    mov     rdi, rbx
    call    num_copy
    mov     r14, rax
    mov     rcx, [r14 + NUM_LEN]
    mov     byte [r14 + NUM_DIG + rcx], 0
    inc     rcx
    mov     [r14 + NUM_LEN], rcx
    mov     r15, rcx
    sub     r15, r13                    ;how many quotient digits there are
    lea     rdi, [r15 + 4]
    call    num_new
    push    rax
    mov     rcx, r15
.place:
    test    rcx, rcx
    jz      .placed
    dec     rcx
    xor     r8, r8                      ;the digit being found
.subtract:
    lea     rdi, [r14 + NUM_DIG + rcx]
    cmp     byte [rdi + r13], 0
    jne     .fits
    mov     rsi, r12
    add     rsi, NUM_DIG
    mov     rdx, r13
    push    rcx
    push    r8
    call    cmp_digits
    pop     r8
    pop     rcx
    test    rax, rax
    jl      .placedigit
.fits:
    lea     rdi, [r14 + NUM_DIG + rcx]
    lea     rsi, [r12 + NUM_DIG]
    mov     rdx, r13
    push    rcx
    push    r8
    call    sub_digits
    pop     r8
    pop     rcx
    inc     r8
    jmp     .subtract
.placedigit:
    mov     rdx, [rsp]
    mov     [rdx + NUM_DIG + rcx], r8b
    jmp     .place
.placed:
    pop     rax
    mov     [rax + NUM_LEN], r15
    push    rax
    mov     rdi, rax
    call    num_clean
    pop     rax
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; num_div: rdi / rsi, cut to rdx places. Both are scaled up until the
; division is a whole-number one whose answer already has the places wanted.
; ---------------------------------------------------------------------------
num_div:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    cmp     qword [r12 + NUM_LEN], 0
    je      divide_by_zero
    cmp     qword [rbx + NUM_LEN], 0
    jne     .work
    call    num_zero
    mov     [rax + NUM_RDX], r13
    jmp     .out
.work:
; the answer wants scale places, so shift by scale + rdx(b) - rdx(a)
    mov     r14, r13
    add     r14, [r12 + NUM_RDX]
    sub     r14, [rbx + NUM_RDX]
    mov     rdi, rbx
    xor     rsi, rsi
    cmp     r14, 0
    jle     .numready
    mov     rsi, r14
.numready:
    call    num_shifted
    mov     r15, rax
    mov     rdi, r12
    xor     rsi, rsi
    cmp     r14, 0
    jge     .denready
    mov     rsi, r14
    neg     rsi
.denready:
    call    num_shifted
    mov     rdi, r15
    mov     rsi, rax
    call    int_div
    mov     [rax + NUM_RDX], r13
    mov     rdi, rax
    mov     rsi, r13
    mov     rdx, [rbx + NUM_NEG]
    mov     rcx, [r12 + NUM_NEG]
    call    num_retire
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; num_mod: what division leaves behind -- a - (a/b)*b -- kept to as many
; places as either the scale or the operands ask for.
; ---------------------------------------------------------------------------
num_mod:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    cmp     qword [r12 + NUM_LEN], 0
    je      divide_by_zero
    mov     r14, r13
    add     r14, [r12 + NUM_RDX]
    cmp     r14, [rbx + NUM_RDX]
    jae     .havets
    mov     r14, [rbx + NUM_RDX]
.havets:
    cmp     qword [rbx + NUM_LEN], 0
    jne     .work
    call    num_zero
    mov     [rax + NUM_RDX], r14
    jmp     .out
.work:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    call    num_div
    mov     r15, rax
    mov     rdi, r15
    mov     rsi, r12
    xor     rdx, rdx
    test    r13, r13
    jz      .mulscale
    mov     rdx, r14
.mulscale:
    call    num_mul
    mov     rdi, rbx
    mov     rsi, rax
    call    num_sub
    mov     r15, [rax + NUM_NEG]
    mov     rdi, rax
    mov     rsi, r14
    call    num_setrdx
    cmp     qword [rax + NUM_LEN], 0
    je      .out
    mov     [rax + NUM_NEG], r15
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; num_pow: rdi raised to rsi, kept to rdx places. The exponent is doubled
; away a bit at a time, and the number of places carried along with it grows
; the same way, so nothing is thrown out before the end.
; ---------------------------------------------------------------------------
num_pow:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    cmp     qword [r12 + NUM_LEN], 0
    jne     .haveexp
    call    num_one                     ;anything to the nothing is one
    jmp     .out
.haveexp:
    cmp     qword [rbx + NUM_LEN], 0
    jne     .havebase
    cmp     qword [r12 + NUM_NEG], 0
    jne     divide_by_zero
    call    num_zero
    mov     [rax + NUM_RDX], r13
    jmp     .out
.havebase:
    mov     rdi, r12
    call    num_to_uint
    mov     r14, rax                    ;the exponent's size
    cmp     r14, 1
    jne     .general
    cmp     qword [r12 + NUM_NEG], 0
    jne     .reciprocal
    mov     rdi, rbx
    call    num_copy
    jmp     .out
.reciprocal:
    mov     rdi, [one_num]
    mov     rsi, rbx
    mov     rdx, r13
    call    num_div
    jmp     .out
.general:
    cmp     qword [r12 + NUM_NEG], 0
    jne     .square
; a positive power keeps only as many places as the base can actually reach
    mov     rax, [rbx + NUM_RDX]
    imul    rax, r14
    mov     rcx, r13
    cmp     rcx, [rbx + NUM_RDX]
    jae     .havemax
    mov     rcx, [rbx + NUM_RDX]
.havemax:
    cmp     rax, rcx
    jbe     .havescale
    mov     rax, rcx
.havescale:
    mov     r13, rax
.square:
    mov     rdi, rbx
    call    num_copy
    mov     r15, rax                    ;the running square
    mov     rbx, [rbx + NUM_RDX]        ;places the square carries
.trailing:
    test    r14, 1
    jnz     .started
    shl     rbx, 1
    mov     rdi, r15
    mov     rsi, r15
    mov     rdx, rbx
    call    num_mul
    mov     r15, rax
    shr     r14, 1
    jmp     .trailing
.started:
    mov     rdi, r15
    call    num_copy
    push    rax                         ;the answer so far
    push    rbx                         ;places the answer carries
.bit:
    shr     r14, 1
    jz      .finished
    shl     rbx, 1
    mov     rdi, r15
    mov     rsi, r15
    mov     rdx, rbx
    call    num_mul
    mov     r15, rax
    test    r14, 1
    jz      .bit
    mov     rax, [rsp]
    add     rax, rbx
    mov     [rsp], rax
    mov     rdi, [rsp + 8]
    mov     rsi, r15
    mov     rdx, rax
    call    num_mul
    mov     [rsp + 8], rax
    jmp     .bit
.finished:
    pop     rbx
    pop     rax
    cmp     qword [r12 + NUM_NEG], 0
    je      .trim
    mov     rdi, [one_num]
    mov     rsi, rax
    mov     rdx, r13
    call    num_div
.trim:
    mov     rdi, rax
    mov     rcx, [rax + NUM_RDX]
    cmp     rcx, r13
    jbe     .checkzero
    sub     rcx, r13
    mov     rsi, rcx
    push    rdi
    call    num_truncate
    pop     rdi
    push    rdi
    call    num_clean
    pop     rdi
.checkzero:
    mov     rax, rdi
    cmp     qword [rax + NUM_LEN], 0
    jne     .out
    call    num_zero
    mov     [rax + NUM_RDX], r13
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; num_sqrt: the root of rdi to rsi places, or to as many as it already has,
; whichever is more. The digits are squared up into a whole number so the
; root can be found exactly and then cut, rather than approached.
; ---------------------------------------------------------------------------
num_sqrt:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    cmp     r12, [rbx + NUM_RDX]
    jae     .havescale
    mov     r12, [rbx + NUM_RDX]
.havescale:
    cmp     qword [rbx + NUM_LEN], 0
    jne     .positive
    call    num_zero
    mov     [rax + NUM_RDX], r12
    jmp     .out
.positive:
    cmp     qword [rbx + NUM_NEG], 0
    jne     negative_sqrt
    mov     r13, r12
    add     r13, r12
    sub     r13, [rbx + NUM_RDX]        ;zeros to push in underneath
    mov     rdi, rbx
    mov     rsi, r13
    call    num_shifted
    mov     rdi, rax
    call    num_isqrt
    mov     [rax + NUM_RDX], r12
    push    rax
    mov     rdi, rax
    call    num_clean
    pop     rax
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; num_isqrt: the whole part of the root of a whole number, closed in on from
; above until the guesses stop falling.
num_isqrt:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    cmp     qword [rbx + NUM_LEN], 0
    jne     .work
    call    num_zero
    jmp     .out
.work:
    mov     rax, [rbx + NUM_LEN]
    inc     rax
    shr     rax, 1                      ;half the digits, rounded up
    mov     r13, rax
    lea     rdi, [r13 + 4]
    call    num_new
    mov     r12, rax                    ;the first guess, ten to that power
    mov     qword [r12 + NUM_LEN], 1
    mov     byte [r12 + NUM_DIG], 1
    mov     rdi, r12
    mov     rsi, r13
    call    num_shifted
    mov     r12, rax
    mov     rdi, 2
    call    num_from_uint
    mov     r14, rax
.step:
    mov     rdi, rbx
    mov     rsi, r12
    call    int_div
    mov     rdi, r12
    mov     rsi, rax
    call    num_add
    mov     rdi, rax
    mov     rsi, r14
    call    int_div
    mov     rdi, rax
    mov     rsi, r12
    push    rax
    call    num_cmp_abs
    pop     rdi
    test    rax, rax
    jge     .settled
    mov     r12, rdi
    jmp     .step
.settled:
    mov     rax, r12
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Reading a number. A single character is always taken at face value, which
; is how A means ten whatever the input base is; anything longer is read in
; the input base.
; ---------------------------------------------------------------------------

; parse_char: the value of one digit character, capped by the base.
parse_char:
    movzx   eax, dil
    cmp     al, 'A'
    jb      .digit
    sub     rax, 'A' - 10
    cmp     rax, rsi
    jb      .out
    lea     rax, [rsi - 1]
    jmp     .out
.digit:
    sub     rax, '0'
.out:
    ret

; num_parse: the text at rdi, rsi long, read in base rdx.
num_parse:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    cmp     r12, 1
    jne     .longer
    movzx   edi, byte [rbx]
    mov     rsi, 'Z' + 11
    call    parse_char
    mov     rdi, rax
    call    num_from_uint
    jmp     .out
.longer:
    cmp     r13, 10
    jne     .other
; base ten: the digits are already the digits
.strip:
    cmp     r12, 0
    je      .built
    cmp     byte [rbx], '0'
    jne     .stripped
    inc     rbx
    dec     r12
    jmp     .strip
.stripped:
    xor     r14, r14                    ;places after the point
    xor     rcx, rcx
    xor     r15, r15                    ;set once a real digit turns up
.scan:
    cmp     rcx, r12
    jae     .scanned
    movzx   eax, byte [rbx + rcx]
    cmp     al, '.'
    je      .point
    cmp     al, '0'
    je      .nextscan
    mov     r15, 1
.nextscan:
    inc     rcx
    jmp     .scan
.point:
    mov     r14, r12
    sub     r14, rcx
    dec     r14                         ;everything after the point
    inc     rcx
.pointrest:
    cmp     rcx, r12
    jae     .scanned
    movzx   eax, byte [rbx + rcx]
    cmp     al, '0'
    je      .nextpoint
    mov     r15, 1
.nextpoint:
    inc     rcx
    jmp     .pointrest
.scanned:
    lea     rdi, [r12 + 4]
    call    num_new
    mov     [rax + NUM_RDX], r14
    test    r15, r15
    jz      .out                        ;nothing but zeros
    push    rax
    mov     rcx, r12
    xor     r8, r8                      ;digits stored
.fill:
    test    rcx, rcx
    jz      .filled
    dec     rcx
    movzx   eax, byte [rbx + rcx]
    cmp     al, '.'
    je      .fill
    cmp     al, 'A'
    jb      .value
    mov     al, '9'
.value:
    sub     al, '0'
    mov     rdx, [rsp]
    mov     [rdx + NUM_DIG + r8], al
    inc     r8
    jmp     .fill
.filled:
    pop     rax
    mov     [rax + NUM_LEN], r8
    push    rax
    mov     rdi, rax
    call    num_clean
    pop     rax
    jmp     .out
.built:
    call    num_zero
    jmp     .out
.other:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    call    num_parse_base
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; num_parse_base: the digits read in a base other than ten. The whole part is
; built up by multiplying what is there so far by the base and adding the new
; digit; the fraction is built the same way and then divided back down by the
; base raised to however many digits it had.
num_parse_base:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 48
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
; nothing but zeros and a point reads as zero
    xor     rcx, rcx
.check:
    cmp     rcx, r12
    jae     .iszero
    movzx   eax, byte [rbx + rcx]
    cmp     al, '.'
    je      .nextcheck
    cmp     al, '0'
    jne     .real
.nextcheck:
    inc     rcx
    jmp     .check
.iszero:
    call    num_zero
    jmp     .out
.real:
    mov     rdi, r13
    call    num_from_uint
    mov     r15, rax                    ;the base, as a number
    call    num_zero
    mov     [rsp], rax                  ;the whole part
    xor     r14, r14
.whole:
    cmp     r14, r12
    jae     .nofraction
    movzx   eax, byte [rbx + r14]
    cmp     al, '.'
    je      .fraction
    mov     rdi, [rsp]
    mov     rsi, r15
    xor     rdx, rdx
    call    num_mul
    mov     [rsp], rax
    movzx   edi, byte [rbx + r14]
    mov     rsi, r13
    call    parse_char
    mov     rdi, rax
    call    num_from_uint
    mov     rsi, rax
    mov     rdi, [rsp]
    call    num_add
    mov     [rsp], rax
    inc     r14
    jmp     .whole
.nofraction:
    mov     rax, [rsp]
    jmp     .out
.fraction:
    inc     r14
    call    num_zero
    mov     [rsp + 8], rax              ;the fraction's digits, as a whole
    call    num_one
    mov     [rsp + 16], rax             ;what it will be divided by
    mov     qword [rsp + 24], 0         ;how many digits it has
.fracdigit:
    cmp     r14, r12
    jae     .fracdone
    mov     rdi, [rsp + 8]
    mov     rsi, r15
    xor     rdx, rdx
    call    num_mul
    mov     [rsp + 8], rax
    movzx   edi, byte [rbx + r14]
    mov     rsi, r13
    call    parse_char
    mov     rdi, rax
    call    num_from_uint
    mov     rsi, rax
    mov     rdi, [rsp + 8]
    call    num_add
    mov     [rsp + 8], rax
    mov     rdi, [rsp + 16]
    mov     rsi, r15
    xor     rdx, rdx
    call    num_mul
    mov     [rsp + 16], rax
    inc     qword [rsp + 24]
    inc     r14
    jmp     .fracdigit
.fracdone:
    mov     rdi, [rsp + 8]
    mov     rsi, [rsp + 16]
    mov     rdx, [rsp + 24]
    call    num_div
    mov     rsi, rax
    mov     rdi, [rsp]
    call    num_add
    cmp     qword [rax + NUM_LEN], 0
    je      .backtozero
    mov     rcx, [rsp + 24]
    cmp     [rax + NUM_RDX], rcx
    jae     .out
    mov     rdi, rax
    mov     rsi, rcx
    call    num_setrdx
    jmp     .out
.backtozero:
    call    num_zero
.out:
    add     rsp, 48
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Writing a number out. Long answers are folded at sixty-nine columns with a
; trailing backslash, so the check for that comes before every character.
; ---------------------------------------------------------------------------

print_fold:
    cmp     qword [nchars], LINE_LEN - 1
    jb      .out
    mov     al, '\'
    call    out_char
    mov     al, WHITESPACE_NL
    call    out_char
    mov     qword [nchars], 0
.out:
    ret

; print_hex: one digit of a base up to sixteen, with the point in front of it
; when rdx says so.
;   rdi = value, rsi = width, rdx = whether the point comes first
print_hex:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    test    rdx, rdx
    jz      .digit
    call    print_fold
    mov     al, '.'
    call    out_char
    inc     qword [nchars]
.digit:
    call    print_fold
    movzx   eax, byte [hex_digits + rbx]
    call    out_char
    add     [nchars], r12
    pop     r12
    pop     rbx
    ret

; print_group: one digit of a base past sixteen, written in decimal and
; padded, with a space in front of it -- or the point, for the first one
; after it.
;   rdi = value, rsi = width, rdx = whether the point comes first
print_group:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    call    print_fold
    mov     al, WHITESPACE_SPACE
    test    rdx, rdx
    jz      .separator
    mov     al, '.'
.separator:
    call    out_char
    inc     qword [nchars]
    call    print_fold
    mov     r13, 1                      ;ten to the width less one
    mov     rcx, r12
    dec     rcx
.power:
    test    rcx, rcx
    jz      .digits
    imul    r13, r13, 10
    dec     rcx
    jmp     .power
.digits:
    mov     r14, r12
.digit:
    test    r14, r14
    jz      .out
    call    print_fold
    mov     rax, rbx
    xor     rdx, rdx
    div     r13
    mov     rbx, rdx
    add     al, '0'
    call    out_char
    mov     rax, r13
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    mov     r13, rax
    inc     qword [nchars]
    dec     r14
    jmp     .digit
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; print_decimal: base ten needs no conversion, the digits are already right.
print_decimal:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    cmp     qword [rbx + NUM_NEG], 0
    je      .digits
    mov     al, '-'
    call    out_char
    inc     qword [nchars]
.digits:
    mov     r13, [rbx + NUM_RDX]
    dec     r13                         ;the place the point comes before
    mov     r12, [rbx + NUM_LEN]
.digit:
    test    r12, r12
    jz      .out
    dec     r12
    movzx   edi, byte [rbx + NUM_DIG + r12]
    mov     rsi, 1
    xor     rdx, rdx
    cmp     r12, r13
    jne     .place
    mov     rdx, 1
.place:
    call    print_hex
    jmp     .digit
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; print_base: any other base, worked out digit by digit -- the whole part by
; dividing it down, the fraction by multiplying it up.
print_base:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    cmp     qword [rbx + NUM_NEG], 0
    je      .width
    mov     al, '-'
    call    out_char
    inc     qword [nchars]
    mov     rdi, rbx
    call    num_copy                    ;the conversion works on the size
    mov     qword [rax + NUM_NEG], 0
    mov     rbx, rax
.width:
    mov     r13, [v_obase]
    cmp     r13, 16
    ja      .wide
    mov     r14, 1                      ;one character each
    mov     r15, 0                      ;written as hex digits
    jmp     .convert
.wide:
    mov     rax, r13
    dec     rax
    xor     r14, r14
.count:
    test    rax, rax
    jz      .counted
    inc     r14
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    jmp     .count
.counted:
    mov     r15, 1                      ;written as padded decimal groups
.convert:
    cmp     qword [rbx + NUM_LEN], 0
    jne     .nonzero
    xor     rdi, rdi
    mov     rsi, r14
    xor     rdx, rdx
    call    print_one_kind
    jmp     .out
.nonzero:
    mov     rdi, r13
    call    num_from_uint
    mov     r12, rax                    ;the base as a number
; the whole part, divided down and the remainders kept back to front
    mov     rdi, rbx
    call    num_copy
    mov     rsi, [rax + NUM_RDX]
    push    rax
    mov     rdi, rax
    call    num_truncate
    pop     rdi
    push    rdi
    call    num_clean
    pop     rdi
    push    rdi                         ;the whole part
    mov     rsi, rdi
    mov     rdi, rbx
    call    num_sub
    push    rax                         ;the fraction
    xor     rcx, rcx                    ;how many digits came out
    mov     rdi, [rsp + 8]
.wholedigit:
    cmp     qword [rdi + NUM_LEN], 0
    je      .wholedone
    push    rcx
    mov     rsi, r12
    xor     rdx, rdx
    call    num_div
    push    rax
    mov     rdi, rax
    mov     rsi, r12
    xor     rdx, rdx
    call    num_mul
    mov     rsi, rax
    mov     rdi, [rsp + 24]
    call    num_sub
    mov     rdi, rax
    call    num_to_uint
    pop     rdi                         ;the quotient
    mov     [rsp + 16], rdi
    pop     rcx
    mov     [digitstack + rcx * 8], rax
    inc     rcx
    jmp     .wholedigit
.wholedone:
    test    rcx, rcx
    jz      .fraction
.emit:
    dec     rcx
    push    rcx
    mov     rdi, [digitstack + rcx * 8]
    mov     rsi, r14
    xor     rdx, rdx
    call    print_one_kind
    pop     rcx
    test    rcx, rcx
    jnz     .emit
.fraction:
    cmp     qword [rbx + NUM_RDX], 0
    je      .popout
    call    num_one
    push    rax                         ;ten to the digits printed so far
    mov     r13, 1                      ;the first digit follows the point
.fracdigit:
    mov     rdi, [rsp]
    mov     rax, [rdi + NUM_LEN]
    cmp     rax, [rbx + NUM_RDX]
    ja      .fracdone
    mov     rdi, [rsp + 8]              ;the fraction
    mov     rsi, r12
    mov     rdx, [rbx + NUM_RDX]
    call    num_mul
    mov     [rsp + 8], rax
    mov     rdi, rax
    call    num_to_uint
    push    rax
    mov     rdi, rax
    call    num_from_uint
    mov     rsi, rax
    mov     rdi, [rsp + 16]
    call    num_sub
    mov     [rsp + 16], rax
    pop     rdi
    mov     rsi, r14
    mov     rdx, r13
    push    r13
    call    print_one_kind
    pop     r13
    xor     r13, r13
    mov     rdi, [rsp]
    mov     rsi, r12
    xor     rdx, rdx
    call    num_mul
    mov     [rsp], rax
    jmp     .fracdigit
.fracdone:
    pop     rax
.popout:
    pop     rax
    pop     rax
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; print_one_kind: rdx tells the point apart from nothing, r15 whether the
; base needs padded groups.
print_one_kind:
    test    r15, r15
    jnz     print_group
    jmp     print_hex

; ---------------------------------------------------------------------------
; num_print: a value, followed by a newline, and remembered as last.
; ---------------------------------------------------------------------------
num_print:
    push    rbx
    mov     rbx, rdi
    call    num_print_value
    mov     al, WHITESPACE_NL
    call    out_char
    mov     qword [nchars], 0
    pop     rbx
    ret

; num_print_value: the digits alone, with nothing added after them.
num_print_value:
    push    rbx
    mov     rbx, rdi
    call    print_fold
    cmp     qword [rbx + NUM_LEN], 0
    jne     .value
    xor     rdi, rdi
    mov     rsi, 1
    xor     rdx, rdx
    call    print_hex
    jmp     .done
.value:
    cmp     qword [v_obase], 10
    jne     .other
    mov     rdi, rbx
    call    print_decimal
    jmp     .done
.other:
    mov     rdi, rbx
    call    print_base
.done:
    mov     rdi, rbx
    call    var_num_copy
    mov     [v_last], rax
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Names. A name is interned once and then referred to by its index; each name
; can be a variable, an array and a function all at the same time, since bc
; keeps those three apart.
; ---------------------------------------------------------------------------

; intern_name: the index for the rsi characters at rdi, added if new.
intern_name:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    xor     r13, r13
.search:
    cmp     r13, [namecount]
    jae     .fresh
    cmp     r12, [name_len + r13 * 8]
    jne     .next
    mov     rdi, [name_off + r13 * 8]
    add     rdi, namebuf
    mov     rsi, rbx
    mov     rdx, r12
    call    same_bytes
    test    al, al
    jnz     .found
.next:
    inc     r13
    jmp     .search
.found:
    mov     rax, r13
    jmp     .out
.fresh:
    mov     r14, [nameused]
    mov     [name_off + r13 * 8], r14
    mov     [name_len + r13 * 8], r12
    mov     qword [var_slot + r13 * 8], 0
    mov     qword [arr_slot + r13 * 8], 0
    mov     qword [fn_slot + r13 * 8], 0
    lea     rdi, [namebuf + r14]
    mov     rsi, rbx
    mov     rdx, r12
    call    copy_bytes
    add     r14, r12
    mov     byte [namebuf + r14], 0
    inc     r14
    mov     [nameused], r14
    inc     r13
    mov     [namecount], r13
    lea     rax, [r13 - 1]
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; same_bytes: al = 1 when rdx bytes at rdi and rsi match.
same_bytes:
    xor     rcx, rcx
.byte:
    cmp     rcx, rdx
    jae     .same
    mov     al, [rdi + rcx]
    cmp     al, [rsi + rcx]
    jne     .differ
    inc     rcx
    jmp     .byte
.same:
    mov     al, 1
    ret
.differ:
    xor     al, al
    ret

; var_get: what the variable rdi holds, or a zero when it has never been set.
var_get:
    mov     rax, [var_slot + rdi * 8]
    test    rax, rax
    jnz     .out
    mov     rax, [zero_num]
.out:
    ret

; var_set: rdi names the variable, rsi is the value, which is copied so that
; it outlives the statement.
var_set:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rsi
    call    var_num_copy
    mov     [var_slot + rbx * 8], rax
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Arrays. A vector of values that grows as it is indexed; anything not yet
; written reads as zero.
; ---------------------------------------------------------------------------
    %define ARR_LEN 0
    %define ARR_CAP 8
    %define ARR_ITEMS 16

array_new:
    push    rbx
    mov     rdi, ARR_ITEMS + 16 * 8
    call    var_alloc
    mov     qword [rax + ARR_LEN], 0
    mov     qword [rax + ARR_CAP], 16
    pop     rbx
    ret

; array_of: the array the name rdi stands for, made if it does not exist.
array_of:
    push    rbx
    mov     rbx, rdi
    mov     rax, [arr_slot + rbx * 8]
    test    rax, rax
    jnz     .out
    call    array_new
    mov     [arr_slot + rbx * 8], rax
.out:
    pop     rbx
    ret

; array_room: the array at rdi grown to hold rsi entries. rax is the array,
; which may have moved.
array_room:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    cmp     r12, [rbx + ARR_CAP]
    jbe     .enough
    mov     r13, [rbx + ARR_CAP]
.grow:
    shl     r13, 1
    cmp     r13, r12
    jb      .grow
    lea     rdi, [ARR_ITEMS + r13 * 8]
    call    var_alloc
    mov     rcx, [rbx + ARR_LEN]
    mov     [rax + ARR_LEN], rcx
    mov     [rax + ARR_CAP], r13
    push    rax
    lea     rdi, [rax + ARR_ITEMS]
    lea     rsi, [rbx + ARR_ITEMS]
    mov     rdx, [rbx + ARR_LEN]
    shl     rdx, 3
    call    copy_bytes
    pop     rax
    mov     rbx, rax
.enough:
    cmp     r12, [rbx + ARR_LEN]
    jbe     .filled
    mov     rcx, [rbx + ARR_LEN]
.fill:
    cmp     rcx, r12
    jae     .stored
    mov     rax, [zero_num]
    mov     [rbx + ARR_ITEMS + rcx * 8], rax
    inc     rcx
    jmp     .fill
.stored:
    mov     [rbx + ARR_LEN], r12
.filled:
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

; array_get: entry rsi of the array named by rdi.
array_get:
    push    rbx
    push    r12
    mov     r12, rsi
    call    array_of
    mov     rbx, rax
    cmp     r12, [rbx + ARR_LEN]
    jb      .have
    mov     rax, [zero_num]
    jmp     .out
.have:
    mov     rax, [rbx + ARR_ITEMS + r12 * 8]
.out:
    pop     r12
    pop     rbx
    ret

; array_set: entry rsi of the array named by rdi takes the value rdx.
array_set:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    call    array_of
    mov     rdi, rax
    lea     rsi, [r12 + 1]
    call    array_room
    mov     [arr_slot + rbx * 8], rax
    push    rax
    mov     rdi, r13
    call    var_num_copy
    pop     rdx
    mov     [rdx + ARR_ITEMS + r12 * 8], rax
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; The lexer. Tokens are read straight out of the source text, so the reader
; can be put back to any earlier point simply by moving the cursor.
; ---------------------------------------------------------------------------

; lex_next: read the token at the cursor.
lex_next:
    push    rbx
    push    r12
    mov     rbx, [src_pos]
.skip:
    movzx   eax, byte [rbx]
    cmp     al, WHITESPACE_SPACE
    je      .step
    cmp     al, WHITESPACE_TAB
    je      .step
    cmp     al, 13
    je      .step
    cmp     al, '\'
    je      .backslash
    cmp     al, '#'
    je      .linecomment
    cmp     al, '/'
    jne     .token
    cmp     byte [rbx + 1], '*'
    jne     .token
    add     rbx, 2
.comment:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .token
    cmp     al, '*'
    jne     .commentstep
    cmp     byte [rbx + 1], '/'
    jne     .commentstep
    add     rbx, 2
    jmp     .skip
.commentstep:
    inc     rbx
    jmp     .comment
.linecomment:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .token
    cmp     al, WHITESPACE_NL
    je      .skip
    inc     rbx
    jmp     .linecomment
.backslash:
    cmp     byte [rbx + 1], WHITESPACE_NL
    jne     .token
    add     rbx, 2
    jmp     .skip
.step:
    inc     rbx
    jmp     .skip

.token:
    mov     [tok_pos], rbx
    movzx   eax, byte [rbx]
    test    al, al
    jz      .eof
    cmp     al, WHITESPACE_NL
    je      .newline
    cmp     al, '"'
    je      .string
    cmp     al, '.'
    je      .point
    cmp     al, '0'
    jb      .punct
    cmp     al, '9'
    jbe     .number
    cmp     al, 'A'
    jb      .punct
    cmp     al, 'Z'
    jbe     .number
    cmp     al, 'a'
    jb      .punct
    cmp     al, 'z'
    jbe     .word
    jmp     .punct

.eof:
    mov     [src_pos], rbx
    mov     qword [tok_type], T_EOF
    jmp     .out
.newline:
    inc     rbx
    mov     [src_pos], rbx
    mov     qword [tok_type], T_NEWLINE
    jmp     .out
.string:
    inc     rbx
    mov     [tok_start], rbx
    xor     rcx, rcx
.strbyte:
    movzx   eax, byte [rbx + rcx]
    test    al, al
    jz      .strend
    cmp     al, '"'
    je      .strend
    inc     rcx
    jmp     .strbyte
.strend:
    mov     [tok_len], rcx
    add     rbx, rcx
    cmp     byte [rbx], '"'
    jne     .strstore
    inc     rbx
.strstore:
    mov     [src_pos], rbx
    mov     qword [tok_type], T_STRING
    jmp     .out

; a lone point is another way of writing last; followed by a digit it starts
; a number instead
.point:
    movzx   eax, byte [rbx + 1]
    cmp     al, '0'
    jb      .lastvalue
    cmp     al, '9'
    jbe     .number
    cmp     al, 'A'
    jb      .lastvalue
    cmp     al, 'Z'
    jbe     .number
.lastvalue:
    inc     rbx
    mov     [src_pos], rbx
    mov     qword [tok_type], T_KEY_LAST
    jmp     .out

; a number: digits, capital letters, one point, and a line may be continued
; in the middle of it
.number:
    movzx   eax, byte [rbx]
    xor     r12, r12                    ;characters gathered
    xor     rdx, rdx                    ;whether the point has been seen
    movzx   eax, byte [rbx]
    cmp     al, '.'
    jne     .numfirst
    mov     rdx, 1
.numfirst:
    mov     [numtok + r12], al
    inc     r12
    inc     rbx
.numbyte:
    movzx   eax, byte [rbx]
    cmp     al, '\'
    jne     .numcheck
    cmp     byte [rbx + 1], WHITESPACE_NL
    jne     .numdone
    add     rbx, 2
.numspace:
    movzx   eax, byte [rbx]
    cmp     al, WHITESPACE_SPACE
    je      .numspacestep
    cmp     al, WHITESPACE_TAB
    jne     .numcheck
.numspacestep:
    inc     rbx
    jmp     .numspace
.numcheck:
    cmp     al, '.'
    jne     .numother
    test    rdx, rdx
    jnz     .numdone
    mov     rdx, 1
    jmp     .numkeep
.numother:
    cmp     al, '0'
    jb      .numdone
    cmp     al, '9'
    jbe     .numkeep
    cmp     al, 'A'
    jb      .numdone
    cmp     al, 'Z'
    ja      .numdone
.numkeep:
    mov     [numtok + r12], al
    inc     r12
    inc     rbx
    jmp     .numbyte
.numdone:
    mov     byte [numtok + r12], 0
    mov     qword [tok_start], numtok
    mov     [tok_len], r12
    mov     [src_pos], rbx
    mov     qword [tok_type], T_NUMBER
    jmp     .out

; a word: a keyword when one matches it whole, otherwise a name
.word:
    xor     rcx, rcx
.keyword:
    cmp     rcx, kw_count
    jae     .name
    mov     rdi, rbx
    mov     rsi, [kw_names + rcx * 8]
    push    rcx
    call    match_keyword
    pop     rcx
    test    rax, rax
    jz      .nextkeyword
    add     rbx, rax
    mov     [src_pos], rbx
    mov     rax, [kw_tokens + rcx * 8]
    mov     [tok_type], rax
    jmp     .out
.nextkeyword:
    inc     rcx
    jmp     .keyword
.name:
    mov     [tok_start], rbx
    xor     rcx, rcx
.namebyte:
    movzx   eax, byte [rbx + rcx]
    cmp     al, '_'
    je      .namekeep
    cmp     al, '0'
    jb      .namedone
    cmp     al, '9'
    jbe     .namekeep
    cmp     al, 'a'
    jb      .namedone
    cmp     al, 'z'
    ja      .namedone
.namekeep:
    inc     rcx
    jmp     .namebyte
.namedone:
    mov     [tok_len], rcx
    add     rbx, rcx
    mov     [src_pos], rbx
    mov     qword [tok_type], T_NAME
    jmp     .out

.punct:
    inc     rbx
    mov     [src_pos], rbx
    mov     r12, T_EOF
    cmp     al, '('
    je      .p_lparen
    cmp     al, ')'
    je      .p_rparen
    cmp     al, '['
    je      .p_lbracket
    cmp     al, ']'
    je      .p_rbracket
    cmp     al, '{'
    je      .p_lbrace
    cmp     al, '}'
    je      .p_rbrace
    cmp     al, ';'
    je      .p_scolon
    cmp     al, ','
    je      .p_comma
    cmp     al, '^'
    je      .p_caret
    cmp     al, '+'
    je      .p_plus
    cmp     al, '-'
    je      .p_minus
    cmp     al, '*'
    je      .p_star
    cmp     al, '/'
    je      .p_slash
    cmp     al, '%'
    je      .p_percent
    cmp     al, '='
    je      .p_equal
    cmp     al, '<'
    je      .p_less
    cmp     al, '>'
    je      .p_greater
    cmp     al, '!'
    je      .p_bang
    cmp     al, '&'
    je      .p_and
    cmp     al, '|'
    je      .p_or
    jmp     syntax_error
.p_lparen:
    mov     qword [tok_type], T_LPAREN
    jmp     .out
.p_rparen:
    mov     qword [tok_type], T_RPAREN
    jmp     .out
.p_lbracket:
    mov     qword [tok_type], T_LBRACKET
    jmp     .out
.p_rbracket:
    mov     qword [tok_type], T_RBRACKET
    jmp     .out
.p_lbrace:
    mov     qword [tok_type], T_LBRACE
    jmp     .out
.p_rbrace:
    mov     qword [tok_type], T_RBRACE
    jmp     .out
.p_scolon:
    mov     qword [tok_type], T_SCOLON
    jmp     .out
.p_comma:
    mov     qword [tok_type], T_COMMA
    jmp     .out
.p_caret:
    mov     rax, T_CARET
    mov     rcx, T_ASSIGN_CARET
    jmp     .maybe_assign
.p_plus:
    cmp     byte [rbx], '+'
    jne     .plusnot
    inc     rbx
    mov     [src_pos], rbx
    mov     qword [tok_type], T_INC
    jmp     .out
.plusnot:
    mov     rax, T_PLUS
    mov     rcx, T_ASSIGN_PLUS
    jmp     .maybe_assign
.p_minus:
    cmp     byte [rbx], '-'
    jne     .minusnot
    inc     rbx
    mov     [src_pos], rbx
    mov     qword [tok_type], T_DEC
    jmp     .out
.minusnot:
    mov     rax, T_MINUS
    mov     rcx, T_ASSIGN_MINUS
    jmp     .maybe_assign
.p_star:
    mov     rax, T_STAR
    mov     rcx, T_ASSIGN_STAR
    jmp     .maybe_assign
.p_slash:
    mov     rax, T_SLASH
    mov     rcx, T_ASSIGN_SLASH
    jmp     .maybe_assign
.p_percent:
    mov     rax, T_PERCENT
    mov     rcx, T_ASSIGN_PERCENT
    jmp     .maybe_assign
.maybe_assign:
    cmp     byte [rbx], '='
    jne     .plain
    cmp     byte [rbx + 1], '='
    je      .plain
    cmp     byte [rbx + 1], '<'
    je      .plain
    cmp     byte [rbx + 1], '>'
    je      .plain
    inc     rbx
    mov     [src_pos], rbx
    mov     [tok_type], rcx
    jmp     .out
.plain:
    mov     [tok_type], rax
    jmp     .out
.p_equal:
    cmp     byte [rbx], '='
    jne     .assignonly
    inc     rbx
    mov     [src_pos], rbx
    mov     qword [tok_type], T_EQ
    jmp     .out
.assignonly:
    mov     qword [tok_type], T_ASSIGN
    jmp     .out
.p_less:
    cmp     byte [rbx], '='
    jne     .lessonly
    inc     rbx
    mov     [src_pos], rbx
    mov     qword [tok_type], T_LE
    jmp     .out
.lessonly:
    mov     qword [tok_type], T_LT
    jmp     .out
.p_greater:
    cmp     byte [rbx], '='
    jne     .greateronly
    inc     rbx
    mov     [src_pos], rbx
    mov     qword [tok_type], T_GE
    jmp     .out
.greateronly:
    mov     qword [tok_type], T_GT
    jmp     .out
.p_bang:
    cmp     byte [rbx], '='
    jne     .bangonly
    inc     rbx
    mov     [src_pos], rbx
    mov     qword [tok_type], T_NE
    jmp     .out
.bangonly:
    mov     qword [tok_type], T_NOT
    jmp     .out
.p_and:
    cmp     byte [rbx], '&'
    jne     syntax_error
    inc     rbx
    mov     [src_pos], rbx
    mov     qword [tok_type], T_AND
    jmp     .out
.p_or:
    cmp     byte [rbx], '|'
    jne     syntax_error
    inc     rbx
    mov     [src_pos], rbx
    mov     qword [tok_type], T_OR
.out:
    pop     r12
    pop     rbx
    ret

; match_keyword: rax is the keyword's length when the text at rdi is that
; keyword and nothing longer, and zero otherwise.
match_keyword:
    push    rbx
    xor     rcx, rcx
.byte:
    movzx   eax, byte [rsi + rcx]
    test    al, al
    jz      .ended
    cmp     al, [rdi + rcx]
    jne     .no
    inc     rcx
    jmp     .byte
.ended:
    movzx   eax, byte [rdi + rcx]
    cmp     al, '_'
    je      .no
    cmp     al, '0'
    jb      .yes
    cmp     al, '9'
    jbe     .no
    cmp     al, 'a'
    jb      .yes
    cmp     al, 'z'
    jbe     .no
.yes:
    mov     rax, rcx
    pop     rbx
    ret
.no:
    xor     rax, rax
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Expressions, read and worked out in one pass. An operator's precedence is
; the number bc gives it -- the smaller the tighter -- and an assignment
; binds more tightly than a comparison, which is why a = b < c assigns first.
;
; Anything that can be assigned to leaves a note behind in lv_kind saying
; what it was, so the assignment that may follow knows where to put its
; answer.
; ---------------------------------------------------------------------------

; op_prec: rax = the operator's precedence or -1, rdx = 1 when it groups left.
op_prec:
    mov     rax, [tok_type]
    cmp     rax, T_CARET
    je      .power
    cmp     rax, T_STAR
    je      .product
    cmp     rax, T_SLASH
    je      .product
    cmp     rax, T_PERCENT
    je      .product
    cmp     rax, T_PLUS
    je      .sum
    cmp     rax, T_MINUS
    je      .sum
    cmp     rax, T_ASSIGN
    je      .assign
    cmp     rax, T_ASSIGN_PLUS
    jb      .notassign
    cmp     rax, T_ASSIGN_CARET
    jbe     .assign
.notassign:
    cmp     rax, T_EQ
    jb      .none
    cmp     rax, T_GT
    jbe     .relation
    cmp     rax, T_AND
    je      .conjunction
    cmp     rax, T_OR
    je      .disjunction
.none:
    mov     rax, -1
    xor     rdx, rdx
    ret
.power:
    mov     rax, 4
    xor     rdx, rdx
    ret
.product:
    mov     rax, 5
    mov     rdx, 1
    ret
.sum:
    mov     rax, 6
    mov     rdx, 1
    ret
.assign:
    mov     rax, 8
    xor     rdx, rdx
    ret
.relation:
    mov     rax, 9
    mov     rdx, 1
    ret
.conjunction:
    mov     rax, 10
    mov     rdx, 1
    ret
.disjunction:
    mov     rax, 11
    mov     rdx, 1
    ret

; is_assign_tok: al = 1 for the assignment operators.
is_assign_tok:
    xor     eax, eax
    cmp     rdi, T_ASSIGN
    je      .yes
    cmp     rdi, T_ASSIGN_PLUS
    jb      .out
    cmp     rdi, T_ASSIGN_CARET
    ja      .out
.yes:
    mov     al, 1
.out:
    ret

; ---------------------------------------------------------------------------
; eval_expr: rdi = the loosest precedence to take in, rsi = whether this is
; the whole of a statement, which decides whether its value gets printed.
; ---------------------------------------------------------------------------
eval_expr:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32
    mov     [rsp], rdi                  ;the precedence limit
    mov     [rsp + 8], rsi              ;whether the statement ends here
    call    eval_unary
    mov     rbx, rax
    mov     r13, [lv_kind]
    mov     r14, [lv_a]
    mov     r15, [lv_b]
.loop:
    call    op_prec
    cmp     rax, 0
    jl      .done
    cmp     rax, [rsp]
    ja      .done
    mov     r12, [tok_type]
    mov     [rsp + 16], rax             ;this operator's precedence
    mov     [rsp + 24], rdx             ;and which way it groups
    call    lex_next
    mov     rdi, r12
    call    is_assign_tok
    test    al, al
    jnz     .assignment
    mov     rdi, [rsp + 16]
    sub     rdi, [rsp + 24]
    xor     rsi, rsi
    call    eval_expr
    mov     rsi, rax
    mov     rdi, rbx
    mov     rdx, r12
    call    apply_binop
    mov     rbx, rax
    cmp     qword [rsp + 8], 0
    je      .cleared
    mov     qword [stmt_assign], 0
    jmp     .cleared
.assignment:
    test    r13, r13
    jz      syntax_error
    mov     rdi, [rsp + 16]
    xor     rsi, rsi
    call    eval_expr
    push    rax
    mov     rdi, r13
    mov     rsi, r14
    mov     rdx, r15
    mov     rcx, r12
    pop     r8
    call    apply_assign
    mov     rbx, rax
    cmp     qword [rsp + 8], 0
    je      .cleared
    mov     qword [stmt_assign], 1
.cleared:
    xor     r13, r13                    ;what came out is no longer a target
    jmp     .loop
.done:
    mov     rax, rbx
    mov     [lv_kind], r13
    mov     [lv_a], r14
    mov     [lv_b], r15
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; eval_unary: the prefixes, then a primary, then whatever follows it.
; ---------------------------------------------------------------------------
eval_unary:
    push    rbx
    mov     rax, [tok_type]
    cmp     rax, T_MINUS
    je      .negate
    cmp     rax, T_NOT
    je      .invert
    cmp     rax, T_INC
    je      .preinc
    cmp     rax, T_DEC
    je      .predec
    call    eval_primary
    pop     rbx
    ret
.negate:
    call    lex_next
    call    eval_unary
    mov     rdi, rax
    call    num_copy
    cmp     qword [rax + NUM_LEN], 0
    je      .negdone
    mov     rcx, [rax + NUM_NEG]
    xor     rcx, 1
    mov     [rax + NUM_NEG], rcx
.negdone:
    mov     qword [lv_kind], 0
    pop     rbx
    ret
.invert:
    call    lex_next
    call    eval_unary
    mov     rdi, rax
    call    num_is_zero
    test    al, al
    jz      .invzero
    call    num_one
    jmp     .invdone
.invzero:
    call    num_zero
.invdone:
    mov     qword [lv_kind], 0
    pop     rbx
    ret
.preinc:
    mov     rbx, 1
    jmp     .prestep
.predec:
    mov     rbx, -1
.prestep:
    call    lex_next
    call    eval_unary
    mov     rdi, [lv_kind]
    test    rdi, rdi
    jz      syntax_error
    mov     rdi, rbx
    mov     rsi, 1                      ;the new value is what comes back
    call    step_lvalue
    pop     rbx
    ret

; step_lvalue: add rdi (one or minus one) to whatever lv_kind names. rsi
; picks the value returned: the new one for a prefix, the old for a postfix.
step_lvalue:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, [lv_kind]
    mov     r14, [lv_a]
    mov     r15, [lv_b]
    mov     rdi, r13
    mov     rsi, r14
    mov     rdx, r15
    call    lvalue_load
    push    rax                         ;the value it had
    mov     rdi, [one_num]
    mov     rsi, rax
    cmp     rbx, 0
    jl      .down
    mov     rdi, rax
    mov     rsi, [one_num]
    call    num_add
    jmp     .stored
.down:
    mov     rdi, rax
    mov     rsi, [one_num]
    call    num_sub
.stored:
    mov     rdi, r13
    mov     rsi, r14
    mov     rdx, r15
    mov     rcx, rax
    push    rax
    call    lvalue_store
    pop     rax
    pop     rcx                         ;the old value
    test    r12, r12
    jnz     .out
    mov     rax, rcx
.out:
    mov     qword [lv_kind], 0
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; eval_primary: a number, a name, a built-in, or something in brackets --
; and then any trailing ++ or --.
; ---------------------------------------------------------------------------
eval_primary:
    push    rbx
    push    r12
    push    r13
    mov     qword [lv_kind], 0
    mov     rax, [tok_type]
    cmp     rax, T_NUMBER
    je      .number
    cmp     rax, T_LPAREN
    je      .paren
    cmp     rax, T_NAME
    je      .name
    cmp     rax, T_KEY_IBASE
    je      .ibase
    cmp     rax, T_KEY_OBASE
    je      .obase
    cmp     rax, T_KEY_SCALE
    je      .scale
    cmp     rax, T_KEY_LAST
    je      .last
    cmp     rax, T_KEY_LENGTH
    je      .length
    cmp     rax, T_KEY_SQRT
    je      .sqrt
    cmp     rax, T_KEY_ABS
    je      .abs
    cmp     rax, T_KEY_READ
    je      .read
    jmp     syntax_error

.number:
    mov     rdi, [tok_start]
    mov     rsi, [tok_len]
    mov     rdx, [v_ibase]
    call    num_parse
    mov     rbx, rax
    call    lex_next
    mov     qword [lv_kind], 0
    jmp     .postfix

.paren:
    call    lex_next
    mov     rdi, 11
    xor     rsi, rsi
    call    eval_expr
    mov     rbx, rax
    cmp     qword [tok_type], T_RPAREN
    jne     syntax_error
    call    lex_next
    mov     qword [lv_kind], 0
    jmp     .out                        ;brackets are never a target

.name:
    mov     rdi, [tok_start]
    mov     rsi, [tok_len]
    call    intern_name
    mov     r12, rax
    call    lex_next
    cmp     qword [tok_type], T_LPAREN
    je      .call
    cmp     qword [tok_type], T_LBRACKET
    je      .element
    mov     rdi, r12
    call    var_get
    mov     rbx, rax
    mov     qword [lv_kind], 1
    mov     [lv_a], r12
    mov     qword [lv_b], 0
    jmp     .postfix
.element:
    call    lex_next
    mov     rdi, 11
    xor     rsi, rsi
    call    eval_expr
    mov     rdi, rax
    call    num_to_uint
    mov     r13, rax
    cmp     qword [tok_type], T_RBRACKET
    jne     syntax_error
    call    lex_next
    mov     rdi, r12
    mov     rsi, r13
    call    array_get
    mov     rbx, rax
    mov     qword [lv_kind], 2
    mov     [lv_a], r12
    mov     [lv_b], r13
    jmp     .postfix
.call:
    mov     rdi, r12
    call    call_function
    mov     rbx, rax
    mov     qword [lv_kind], 0
    jmp     .out

.ibase:
    call    lex_next
    mov     rdi, [v_ibase]
    call    num_from_uint
    mov     rbx, rax
    mov     qword [lv_kind], 3
    jmp     .postfix
.obase:
    call    lex_next
    mov     rdi, [v_obase]
    call    num_from_uint
    mov     rbx, rax
    mov     qword [lv_kind], 4
    jmp     .postfix
.scale:
    call    lex_next
    cmp     qword [tok_type], T_LPAREN
    je      .scalefunc
    mov     rdi, [v_scale]
    call    num_from_uint
    mov     rbx, rax
    mov     qword [lv_kind], 5
    jmp     .postfix
.scalefunc:
    call    argument_value
    mov     rdi, [rax + NUM_RDX]
    call    num_from_uint
    mov     rbx, rax
    mov     qword [lv_kind], 0
    jmp     .out
.last:
    call    lex_next
    mov     rdi, [v_last]
    call    num_copy
    mov     rbx, rax
    mov     qword [lv_kind], 6
    jmp     .postfix
.length:
    call    lex_next
    cmp     qword [tok_type], T_LPAREN
    jne     syntax_error
    call    argument_value
    mov     rdi, [rax + NUM_LEN]
    call    num_from_uint
    mov     rbx, rax
    jmp     .out
.sqrt:
    call    lex_next
    cmp     qword [tok_type], T_LPAREN
    jne     syntax_error
    call    argument_value
    mov     rdi, rax
    mov     rsi, [v_scale]
    call    num_sqrt
    mov     rbx, rax
    jmp     .out
.abs:
    call    lex_next
    cmp     qword [tok_type], T_LPAREN
    jne     syntax_error
    call    argument_value
    mov     rdi, rax
    call    num_copy
    mov     qword [rax + NUM_NEG], 0
    mov     rbx, rax
    jmp     .out
.read:
    call    lex_next
    cmp     qword [tok_type], T_LPAREN
    jne     syntax_error
    call    lex_next
    cmp     qword [tok_type], T_RPAREN
    jne     syntax_error
    call    lex_next
    call    num_zero
    mov     rbx, rax
    jmp     .out

.postfix:
    cmp     qword [tok_type], T_INC
    je      .postinc
    cmp     qword [tok_type], T_DEC
    je      .postdec
    jmp     .out
.postinc:
    cmp     qword [lv_kind], 0
    je      .out
    call    lex_next
    mov     rdi, 1
    xor     rsi, rsi
    call    step_lvalue
    mov     rbx, rax
    jmp     .out
.postdec:
    cmp     qword [lv_kind], 0
    je      .out
    call    lex_next
    mov     rdi, -1
    xor     rsi, rsi
    call    step_lvalue
    mov     rbx, rax
.out:
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

; argument_value: "( expr )" where the cursor sits on the bracket.
argument_value:
    push    rbx
    call    lex_next
    mov     rdi, 11
    xor     rsi, rsi
    call    eval_expr
    mov     rbx, rax
    cmp     qword [tok_type], T_RPAREN
    jne     syntax_error
    call    lex_next
    mov     rax, rbx
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; lvalue_load / lvalue_store: reading and writing whatever an expression
; named -- a variable, one entry of an array, or one of the three settings.
;   rdi = kind, rsi = name, rdx = index, rcx = value to store
; ---------------------------------------------------------------------------
lvalue_load:
    cmp     rdi, 1
    je      .variable
    cmp     rdi, 2
    je      .element
    cmp     rdi, 3
    je      .ibase
    cmp     rdi, 4
    je      .obase
    cmp     rdi, 5
    je      .scale
    cmp     rdi, 6
    je      .last
    jmp     syntax_error
.variable:
    mov     rdi, rsi
    jmp     var_get
.element:
    mov     rdi, rsi
    mov     rsi, rdx
    jmp     array_get
.ibase:
    mov     rdi, [v_ibase]
    jmp     num_from_uint
.obase:
    mov     rdi, [v_obase]
    jmp     num_from_uint
.scale:
    mov     rdi, [v_scale]
    jmp     num_from_uint
.last:
    mov     rax, [v_last]
    ret

lvalue_store:
    cmp     rdi, 1
    je      .variable
    cmp     rdi, 2
    je      .element
    cmp     rdi, 3
    je      .ibase
    cmp     rdi, 4
    je      .obase
    cmp     rdi, 5
    je      .scale
    cmp     rdi, 6
    je      .last
    jmp     syntax_error
.variable:
    mov     rdi, rsi
    mov     rsi, rcx
    jmp     var_set
.element:
    mov     rdi, rsi
    mov     rsi, rdx
    mov     rdx, rcx
    jmp     array_set
.ibase:
    mov     rdi, rcx
    call    num_to_uint
    mov     [v_ibase], rax
    ret
.obase:
    mov     rdi, rcx
    call    num_to_uint
    mov     [v_obase], rax
    ret
.scale:
    mov     rdi, rcx
    call    num_to_uint
    mov     [v_scale], rax
    ret
.last:
    mov     rdi, rcx
    call    var_num_copy
    mov     [v_last], rax
    ret

; ---------------------------------------------------------------------------
; apply_binop: rdi and rsi are the two values, rdx the operator.
; ---------------------------------------------------------------------------
apply_binop:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    cmp     r13, T_PLUS
    je      .plus
    cmp     r13, T_MINUS
    je      .minus
    cmp     r13, T_STAR
    je      .times
    cmp     r13, T_SLASH
    je      .over
    cmp     r13, T_PERCENT
    je      .remainder
    cmp     r13, T_CARET
    je      .power
    cmp     r13, T_AND
    je      .conjunction
    cmp     r13, T_OR
    je      .disjunction
    jmp     .relation
.plus:
    mov     rdi, rbx
    mov     rsi, r12
    call    num_add
    jmp     .out
.minus:
    mov     rdi, rbx
    mov     rsi, r12
    call    num_sub
    jmp     .out
.times:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, [v_scale]
    call    num_mul
    jmp     .out
.over:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, [v_scale]
    call    num_div
    jmp     .out
.remainder:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, [v_scale]
    call    num_mod
    jmp     .out
.power:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, [v_scale]
    call    num_pow
    jmp     .out
.conjunction:
    mov     rdi, rbx
    call    num_is_zero
    test    al, al
    jnz     .false
    mov     rdi, r12
    call    num_is_zero
    test    al, al
    jnz     .false
    jmp     .true
.disjunction:
    mov     rdi, rbx
    call    num_is_zero
    test    al, al
    jz      .true
    mov     rdi, r12
    call    num_is_zero
    test    al, al
    jz      .true
    jmp     .false
.relation:
    mov     rdi, rbx
    mov     rsi, r12
    call    num_cmp
    cmp     r13, T_EQ
    je      .r_eq
    cmp     r13, T_NE
    je      .r_ne
    cmp     r13, T_LT
    je      .r_lt
    cmp     r13, T_GT
    je      .r_gt
    cmp     r13, T_LE
    je      .r_le
    cmp     r13, T_GE
    je      .r_ge
    jmp     syntax_error
.r_eq:
    test    rax, rax
    jz      .true
    jmp     .false
.r_ne:
    test    rax, rax
    jnz     .true
    jmp     .false
.r_lt:
    cmp     rax, 0
    jl      .true
    jmp     .false
.r_gt:
    cmp     rax, 0
    jg      .true
    jmp     .false
.r_le:
    cmp     rax, 0
    jle     .true
    jmp     .false
.r_ge:
    cmp     rax, 0
    jge     .true
    jmp     .false
.true:
    call    num_one
    jmp     .out
.false:
    call    num_zero
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; apply_assign: rdi = kind, rsi = name, rdx = index, rcx = operator,
; r8 = the value on the right.
; ---------------------------------------------------------------------------
apply_assign:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    mov     r15, r8
    cmp     r14, T_ASSIGN
    je      .store
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    call    lvalue_load
    mov     rdi, rax
    mov     rsi, r15
    mov     rdx, T_PLUS
    cmp     r14, T_ASSIGN_PLUS
    je      .combine
    mov     rdx, T_MINUS
    cmp     r14, T_ASSIGN_MINUS
    je      .combine
    mov     rdx, T_STAR
    cmp     r14, T_ASSIGN_STAR
    je      .combine
    mov     rdx, T_SLASH
    cmp     r14, T_ASSIGN_SLASH
    je      .combine
    mov     rdx, T_PERCENT
    cmp     r14, T_ASSIGN_PERCENT
    je      .combine
    mov     rdx, T_CARET
.combine:
    call    apply_binop
    mov     r15, rax
.store:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, r15
    call    lvalue_store
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    call    lvalue_load
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Statements. Each is executed where it stands. A construct whose body runs
; more than once first walks over that body without executing it, to learn
; where it starts and ends, and afterwards puts the cursor back to the start
; for every pass.
; ---------------------------------------------------------------------------

; run_text: read and execute a whole source text.
run_text:
    push    rbx
    push    r12
    mov     [src_pos], rdi
    call    lex_next
.stmt:
    cmp     byte [quitting], 0
    jne     .out
    mov     rax, [tok_type]
    cmp     rax, T_EOF
    je      .out
    cmp     rax, T_NEWLINE
    je      .step
    cmp     rax, T_SCOLON
    je      .step
    cmp     rax, T_RBRACE
    je      .step
    mov     r12, [tmp_top]
    call    exec_stmt
    mov     [tmp_top], r12
    mov     qword [flow], FLOW_NONE
    jmp     .stmt
.step:
    call    lex_next
    jmp     .stmt
.out:
    call    out_flush
    pop     r12
    pop     rbx
    ret

; exec_stmts_until: statements up to the position in rdi, or to a closing
; brace, stopping early when a break, continue or return has happened.
exec_stmts_until:
    push    rbx
    push    r12
    mov     rbx, rdi
.stmt:
    mov     rax, [tok_type]
    cmp     rax, T_EOF
    je      .out
    cmp     rax, T_RBRACE
    je      .out
    mov     rax, [tok_pos]
    cmp     rax, rbx
    jae     .out
    mov     rax, [tok_type]
    cmp     rax, T_NEWLINE
    je      .step
    cmp     rax, T_SCOLON
    je      .step
    mov     r12, [tmp_top]
    call    exec_stmt
    mov     [tmp_top], r12
    cmp     qword [flow], FLOW_NONE
    jne     .out
    jmp     .stmt
.step:
    call    lex_next
    jmp     .stmt
.out:
    pop     r12
    pop     rbx
    ret

; exec_stmt: one statement.
exec_stmt:
    mov     rax, [tok_type]
    cmp     rax, T_STRING
    je      .string
    cmp     rax, T_LBRACE
    je      .block
    cmp     rax, T_KEY_IF
    je      exec_if
    cmp     rax, T_KEY_WHILE
    je      exec_while
    cmp     rax, T_KEY_FOR
    je      exec_for
    cmp     rax, T_KEY_BREAK
    je      .breakout
    cmp     rax, T_KEY_CONTINUE
    je      .continueon
    cmp     rax, T_KEY_RETURN
    je      exec_return
    cmp     rax, T_KEY_HALT
    je      .halt
    cmp     rax, T_KEY_QUIT
    je      .quit
    cmp     rax, T_KEY_DEFINE
    je      define_function
    cmp     rax, T_KEY_PRINT
    je      exec_print
    cmp     rax, T_KEY_LIMITS
    je      .limits
    jmp     exec_expr_stmt
.string:
    mov     rdi, [tok_start]
    mov     rsi, [tok_len]
    call    print_raw_string
    jmp     lex_next
.block:
    call    lex_next
    mov     rdi, -1
    call    exec_stmts_until
    cmp     qword [tok_type], T_RBRACE
    jne     .blockdone
    jmp     lex_next
.blockdone:
    ret
.breakout:
    call    lex_next
    mov     qword [flow], FLOW_BREAK
    ret
.continueon:
    call    lex_next
    mov     qword [flow], FLOW_CONTINUE
    ret
.halt:
    mov     byte [quitting], 1
    mov     qword [flow], FLOW_RETURN
    ret
.quit:
    call    out_flush
    exit    0
.limits:
    jmp     lex_next

; exec_expr_stmt: an expression on its own is printed, unless the whole of it
; was an assignment.
exec_expr_stmt:
    push    rbx
    mov     qword [stmt_assign], 0
    mov     rdi, 11
    mov     rsi, 1
    call    eval_expr
    mov     rbx, rax
    cmp     qword [stmt_assign], 0
    jne     .out
    mov     rdi, rbx
    call    num_print
.out:
    pop     rbx
    ret

; exec_return: leaves the value where the call that is running will find it.
exec_return:
    push    rbx
    call    lex_next
    mov     rax, [tok_type]
    cmp     rax, T_SCOLON
    je      .nothing
    cmp     rax, T_NEWLINE
    je      .nothing
    cmp     rax, T_RBRACE
    je      .nothing
    cmp     rax, T_EOF
    je      .nothing
    cmp     rax, T_LPAREN
    jne     .value
; "return ()" gives nothing back, while "return (x)" gives x
    mov     rbx, [tok_pos]
    call    lex_next
    cmp     qword [tok_type], T_RPAREN
    jne     .rewind
    call    lex_next
    jmp     .nothing
.rewind:
    mov     [src_pos], rbx
    call    lex_next
.value:
    mov     rdi, 11
    xor     rsi, rsi
    call    eval_expr
    mov     rdi, rax
    call    var_num_copy
    mov     [retval], rax
    jmp     .done
.nothing:
    mov     rax, [zero_num]
    mov     [retval], rax
.done:
    mov     qword [flow], FLOW_RETURN
    pop     rbx
    ret

; exec_print: the print statement, which writes its items one after another
; and adds nothing of its own.
exec_print:
    push    rbx
    call    lex_next
.item:
    cmp     qword [tok_type], T_STRING
    jne     .value
    mov     rdi, [tok_start]
    mov     rsi, [tok_len]
    call    print_escaped_string
    call    lex_next
    jmp     .separator
.value:
    mov     rdi, 11
    xor     rsi, rsi
    call    eval_expr
    mov     rdi, rax
    call    num_print_value
.separator:
    cmp     qword [tok_type], T_COMMA
    jne     .out
    call    lex_next
    jmp     .item
.out:
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; exec_if: the branch not taken is walked over rather than run, and an else
; may sit past any number of blank lines.
; ---------------------------------------------------------------------------
exec_if:
    push    rbx
    push    r12
    call    lex_next
    cmp     qword [tok_type], T_LPAREN
    jne     syntax_error
    call    lex_next
    mov     rdi, 11
    xor     rsi, rsi
    call    eval_expr
    mov     rdi, rax
    call    num_is_zero
    movzx   ebx, al                     ;whether the test failed
    cmp     qword [tok_type], T_RPAREN
    jne     syntax_error
    call    lex_next
    test    bl, bl
    jnz     .skipthen
    call    exec_stmt
    jmp     .else
.skipthen:
    call    skip_stmt
.else:
    mov     r12, [tok_pos]
.blank:
    mov     rax, [tok_type]
    cmp     rax, T_NEWLINE
    je      .blankstep
    cmp     rax, T_SCOLON
    jne     .checkelse
.blankstep:
    call    lex_next
    jmp     .blank
.checkelse:
    cmp     qword [tok_type], T_KEY_ELSE
    je      .haselse
    mov     [src_pos], r12
    call    lex_next
    jmp     .out
.haselse:
    call    lex_next
    test    bl, bl
    jz      .skipelse
    cmp     qword [flow], FLOW_NONE
    jne     .skipelse
    call    exec_stmt
    jmp     .out
.skipelse:
    call    skip_stmt
.out:
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; exec_while: the test and the body are located once, then run from their
; own positions for as long as the test holds.
; ---------------------------------------------------------------------------
exec_while:
    push    rbx
    push    r12
    push    r13
    push    r14
    call    lex_next
    cmp     qword [tok_type], T_LPAREN
    jne     syntax_error
    mov     rbx, [tok_pos]              ;where the test starts
    call    skip_paren_group
    mov     r12, [tok_pos]              ;where the body starts
    call    skip_stmt
    mov     r13, [tok_pos]              ;where everything after starts
.iterate:
    mov     r14, [tmp_top]
    mov     [src_pos], rbx
    call    lex_next
    call    lex_next
    mov     rdi, 11
    xor     rsi, rsi
    call    eval_expr
    mov     rdi, rax
    call    num_is_zero
    test    al, al
    jnz     .finished
    mov     [src_pos], r12
    call    lex_next
    call    exec_stmt
    mov     rax, [flow]
    cmp     rax, FLOW_BREAK
    je      .stopped
    cmp     rax, FLOW_RETURN
    je      .finished
    mov     qword [flow], FLOW_NONE
    mov     [tmp_top], r14
    jmp     .iterate
.stopped:
    mov     qword [flow], FLOW_NONE
.finished:
    mov     [tmp_top], r14
    mov     [src_pos], r13
    call    lex_next
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; exec_for: the same, with three expressions to keep track of instead of one.
; ---------------------------------------------------------------------------
exec_for:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16
    call    lex_next
    cmp     qword [tok_type], T_LPAREN
    jne     syntax_error
    call    lex_next
    mov     rbx, [tok_pos]              ;the setting up
    mov     rdi, T_SCOLON
    call    skip_to_delim
    call    lex_next
    mov     r12, [tok_pos]              ;the test
    mov     rdi, T_SCOLON
    call    skip_to_delim
    call    lex_next
    mov     r13, [tok_pos]              ;the step
    mov     rdi, T_RPAREN
    call    skip_to_delim
    call    lex_next
    mov     r14, [tok_pos]              ;the body
    call    skip_stmt
    mov     r15, [tok_pos]              ;everything after
    mov     [src_pos], rbx
    call    lex_next
    cmp     qword [tok_type], T_SCOLON
    je      .loop
    mov     rdi, 11
    xor     rsi, rsi
    call    eval_expr
.loop:
    mov     rax, [tmp_top]
    mov     [rsp], rax
    mov     [src_pos], r12
    call    lex_next
    cmp     qword [tok_type], T_SCOLON
    je      .body
    mov     rdi, 11
    xor     rsi, rsi
    call    eval_expr
    mov     rdi, rax
    call    num_is_zero
    test    al, al
    jnz     .finished
.body:
    mov     [src_pos], r14
    call    lex_next
    call    exec_stmt
    mov     rax, [flow]
    cmp     rax, FLOW_BREAK
    je      .stopped
    cmp     rax, FLOW_RETURN
    je      .finished
    mov     qword [flow], FLOW_NONE
    mov     [src_pos], r13
    call    lex_next
    cmp     qword [tok_type], T_RPAREN
    je      .again
    mov     rdi, 11
    xor     rsi, rsi
    call    eval_expr
.again:
    mov     rax, [rsp]
    mov     [tmp_top], rax
    jmp     .loop
.stopped:
    mov     qword [flow], FLOW_NONE
.finished:
    mov     rax, [rsp]
    mov     [tmp_top], rax
    mov     [src_pos], r15
    call    lex_next
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Walking over a statement without running it, so that a body can be found
; and a branch not taken can be stepped past.
; ---------------------------------------------------------------------------
skip_stmt:
    push    rbx
    push    r12
    mov     rax, [tok_type]
    cmp     rax, T_LBRACE
    je      .block
    cmp     rax, T_KEY_IF
    je      .conditional
    cmp     rax, T_KEY_WHILE
    je      .loop
    cmp     rax, T_KEY_FOR
    je      .loop
    cmp     rax, T_KEY_DEFINE
    je      .definition
    cmp     rax, T_STRING
    je      .single
    cmp     rax, T_NEWLINE
    je      .single
    cmp     rax, T_SCOLON
    je      .single
    jmp     .plain
.single:
    call    lex_next
    jmp     .out
.block:
    call    skip_brace_group
    jmp     .out
.conditional:
    call    lex_next
    call    skip_paren_group
    call    skip_stmt
    mov     r12, [tok_pos]
.blank:
    mov     rax, [tok_type]
    cmp     rax, T_NEWLINE
    je      .blankstep
    cmp     rax, T_SCOLON
    jne     .checkelse
.blankstep:
    call    lex_next
    jmp     .blank
.checkelse:
    cmp     qword [tok_type], T_KEY_ELSE
    je      .haselse
    mov     [src_pos], r12
    call    lex_next
    jmp     .out
.haselse:
    call    lex_next
    call    skip_stmt
    jmp     .out
.loop:
    call    lex_next
    call    skip_paren_group
    call    skip_stmt
    jmp     .out
.definition:
    call    lex_next
    call    lex_next
    call    skip_paren_group
.defbrace:
    cmp     qword [tok_type], T_NEWLINE
    jne     .defbody
    call    lex_next
    jmp     .defbrace
.defbody:
    call    skip_brace_group
    jmp     .out
.plain:
    mov     rax, [tok_type]
    cmp     rax, T_EOF
    je      .out
    cmp     rax, T_SCOLON
    je      .single
    cmp     rax, T_NEWLINE
    je      .single
    cmp     rax, T_RBRACE
    je      .out
    call    lex_next
    jmp     .plain
.out:
    pop     r12
    pop     rbx
    ret

; skip_brace_group: from the opening brace to just past the matching one.
skip_brace_group:
    push    rbx
    mov     rbx, 0
.token:
    mov     rax, [tok_type]
    cmp     rax, T_EOF
    je      syntax_error
    cmp     rax, T_LBRACE
    je      .deeper
    cmp     rax, T_RBRACE
    je      .shallower
    call    lex_next
    jmp     .token
.deeper:
    inc     rbx
    call    lex_next
    jmp     .token
.shallower:
    dec     rbx
    call    lex_next
    test    rbx, rbx
    jnz     .token
    pop     rbx
    ret

; skip_paren_group: from the opening bracket to just past the matching one.
skip_paren_group:
    push    rbx
    cmp     qword [tok_type], T_LPAREN
    jne     syntax_error
    mov     rbx, 0
.token:
    mov     rax, [tok_type]
    cmp     rax, T_EOF
    je      syntax_error
    cmp     rax, T_LPAREN
    je      .deeper
    cmp     rax, T_RPAREN
    je      .shallower
    call    lex_next
    jmp     .token
.deeper:
    inc     rbx
    call    lex_next
    jmp     .token
.shallower:
    dec     rbx
    call    lex_next
    test    rbx, rbx
    jnz     .token
    pop     rbx
    ret

; skip_to_delim: forward to the token in rdi, ignoring any that are nested
; inside brackets.
skip_to_delim:
    push    rbx
    push    r12
    mov     r12, rdi
    xor     rbx, rbx
.token:
    mov     rax, [tok_type]
    cmp     rax, T_EOF
    je      .out
    cmp     rax, T_LPAREN
    je      .deeper
    cmp     rax, T_LBRACKET
    je      .deeper
    cmp     rax, T_RPAREN
    je      .closing
    cmp     rax, T_RBRACKET
    je      .closing
    cmp     rax, r12
    jne     .step
    test    rbx, rbx
    jz      .out
.step:
    call    lex_next
    jmp     .token
.deeper:
    inc     rbx
    call    lex_next
    jmp     .token
.closing:
    test    rbx, rbx
    jnz     .shallower
    cmp     r12, T_RPAREN
    je      .out
.shallower:
    dec     rbx
    call    lex_next
    jmp     .token
.out:
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Functions. A definition records where its body lies in the source; a call
; puts the cursor there, having first set the parameters and locals aside so
; they can be given back afterwards.
; ---------------------------------------------------------------------------
define_function:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    call    lex_next
    cmp     qword [tok_type], T_NAME
    jne     syntax_error
    mov     rdi, [tok_start]
    mov     rsi, [tok_len]
    call    intern_name
    mov     r15, rax
    mov     rbx, [funccount]
    imul    rbx, rbx, FN_SIZE
    add     rbx, funcs
    mov     [rbx + FN_NAME], r15
    mov     rax, [funccount]
    inc     rax
    mov     [fn_slot + r15 * 8], rax
    call    lex_next
    cmp     qword [tok_type], T_LPAREN
    jne     syntax_error
    call    lex_next
    xor     r12, r12                    ;parameters seen
.param:
    cmp     qword [tok_type], T_RPAREN
    je      .params_done
    cmp     qword [tok_type], T_NAME
    jne     syntax_error
    mov     rdi, [tok_start]
    mov     rsi, [tok_len]
    call    intern_name
    mov     r13, rax
    call    lex_next
    xor     r14, r14
    cmp     qword [tok_type], T_LBRACKET
    jne     .paramstore
    call    lex_next
    cmp     qword [tok_type], T_RBRACKET
    jne     syntax_error
    call    lex_next
    mov     r14, 1
.paramstore:
    mov     [rbx + FN_PARAMS + r12 * 8], r13
    mov     [rbx + FN_PARRAY + r12 * 8], r14
    inc     r12
    cmp     qword [tok_type], T_COMMA
    jne     .params_done
    call    lex_next
    jmp     .param
.params_done:
    mov     [rbx + FN_NPARAM], r12
    cmp     qword [tok_type], T_RPAREN
    jne     syntax_error
    call    lex_next
.openbrace:
    cmp     qword [tok_type], T_NEWLINE
    jne     .haveopen
    call    lex_next
    jmp     .openbrace
.haveopen:
    cmp     qword [tok_type], T_LBRACE
    jne     syntax_error
    call    lex_next
    xor     r12, r12                    ;locals seen
.autoline:
    mov     rax, [tok_type]
    cmp     rax, T_NEWLINE
    je      .autoskip
    cmp     rax, T_SCOLON
    jne     .autocheck
.autoskip:
    call    lex_next
    jmp     .autoline
.autocheck:
    cmp     qword [tok_type], T_KEY_AUTO
    jne     .autos_done
    call    lex_next
.autoname:
    cmp     qword [tok_type], T_NAME
    jne     syntax_error
    mov     rdi, [tok_start]
    mov     rsi, [tok_len]
    call    intern_name
    mov     r13, rax
    call    lex_next
    xor     r14, r14
    cmp     qword [tok_type], T_LBRACKET
    jne     .autostore
    call    lex_next
    cmp     qword [tok_type], T_RBRACKET
    jne     syntax_error
    call    lex_next
    mov     r14, 1
.autostore:
    mov     [rbx + FN_AUTOS + r12 * 8], r13
    mov     [rbx + FN_AARRAY + r12 * 8], r14
    inc     r12
    cmp     qword [tok_type], T_COMMA
    jne     .autoline
    call    lex_next
    jmp     .autoname
.autos_done:
    mov     [rbx + FN_NAUTO], r12
    mov     rax, [tok_pos]
    mov     [rbx + FN_START], rax
    mov     r12, 1
.body:
    mov     rax, [tok_type]
    cmp     rax, T_EOF
    je      syntax_error
    cmp     rax, T_LBRACE
    je      .deeper
    cmp     rax, T_RBRACE
    je      .shallower
    call    lex_next
    jmp     .body
.deeper:
    inc     r12
    call    lex_next
    jmp     .body
.shallower:
    dec     r12
    test    r12, r12
    jz      .bodydone
    call    lex_next
    jmp     .body
.bodydone:
    mov     rax, [tok_pos]
    mov     [rbx + FN_END], rax
    call    lex_next
    mov     rax, [funccount]
    inc     rax
    mov     [funccount], rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; call_function: rdi names the function; the cursor sits on its opening
; bracket. rax comes back holding whatever the body returned.
call_function:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, MAXPARAMS * 8 + 64
    mov     rax, [fn_slot + rdi * 8]
    test    rax, rax
    jz      syntax_error
    dec     rax
    imul    rax, rax, FN_SIZE
    add     rax, funcs
    mov     rbx, rax                    ;the function
    call    lex_next
    xor     r12, r12                    ;arguments given
    cmp     qword [tok_type], T_RPAREN
    je      .args_done
.arg:
    mov     rdi, 11
    xor     rsi, rsi
    call    eval_expr
    mov     [rsp + r12 * 8], rax
    inc     r12
    cmp     qword [tok_type], T_COMMA
    jne     .args_done
    call    lex_next
    jmp     .arg
.args_done:
    cmp     qword [tok_type], T_RPAREN
    jne     syntax_error
    call    lex_next
; what the parameters and locals held is put aside
    mov     r13, [savetop]
    xor     rcx, rcx
.saveparam:
    cmp     rcx, [rbx + FN_NPARAM]
    jae     .saveautos
    mov     rdx, [rbx + FN_PARAMS + rcx * 8]
    mov     rax, [savetop]
    mov     [save_name + rax * 8], rdx
    mov     r8, [var_slot + rdx * 8]
    mov     [save_val + rax * 8], r8
    mov     byte [save_kind + rax], 0
    inc     rax
    mov     [savetop], rax
    inc     rcx
    jmp     .saveparam
.saveautos:
    xor     rcx, rcx
.saveauto:
    cmp     rcx, [rbx + FN_NAUTO]
    jae     .bind
    mov     rdx, [rbx + FN_AUTOS + rcx * 8]
    mov     rax, [savetop]
    mov     [save_name + rax * 8], rdx
    cmp     qword [rbx + FN_AARRAY + rcx * 8], 0
    je      .saveautovar
    mov     r8, [arr_slot + rdx * 8]
    mov     [save_val + rax * 8], r8
    mov     byte [save_kind + rax], 1
    mov     qword [arr_slot + rdx * 8], 0
    jmp     .saveautonext
.saveautovar:
    mov     r8, [var_slot + rdx * 8]
    mov     [save_val + rax * 8], r8
    mov     byte [save_kind + rax], 0
    mov     qword [var_slot + rdx * 8], 0
.saveautonext:
    inc     rax
    mov     [savetop], rax
    inc     rcx
    jmp     .saveauto
.bind:
    xor     rcx, rcx
.bindparam:
    cmp     rcx, [rbx + FN_NPARAM]
    jae     .bound
    cmp     rcx, r12
    jae     .bindzero
    push    rcx
    mov     rdi, [rsp + 8 + rcx * 8]
    call    var_num_copy
    pop     rcx
    mov     rdx, [rbx + FN_PARAMS + rcx * 8]
    mov     [var_slot + rdx * 8], rax
    inc     rcx
    jmp     .bindparam
.bindzero:
    mov     rdx, [rbx + FN_PARAMS + rcx * 8]
    mov     qword [var_slot + rdx * 8], 0
    inc     rcx
    jmp     .bindparam
.bound:
; the reader is pointed at the body, and put back afterwards
    mov     rax, [src_pos]
    mov     [rsp + MAXPARAMS * 8], rax
    mov     rax, [tok_type]
    mov     [rsp + MAXPARAMS * 8 + 8], rax
    mov     rax, [tok_start]
    mov     [rsp + MAXPARAMS * 8 + 16], rax
    mov     rax, [tok_len]
    mov     [rsp + MAXPARAMS * 8 + 24], rax
    mov     rax, [tok_pos]
    mov     [rsp + MAXPARAMS * 8 + 32], rax
    mov     rax, [retval]
    mov     [rsp + MAXPARAMS * 8 + 40], rax
    mov     rax, [stmt_assign]
    mov     [rsp + MAXPARAMS * 8 + 48], rax
    mov     rax, [zero_num]
    mov     [retval], rax
    mov     qword [flow], FLOW_NONE
    mov     rax, [rbx + FN_START]
    mov     [src_pos], rax
    call    lex_next
    mov     rdi, [rbx + FN_END]
    call    exec_stmts_until
    mov     r14, [retval]
    mov     qword [flow], FLOW_NONE
    cmp     byte [quitting], 0
    je      .restore
    mov     r14, [zero_num]
.restore:
    mov     rax, [rsp + MAXPARAMS * 8]
    mov     [src_pos], rax
    mov     rax, [rsp + MAXPARAMS * 8 + 8]
    mov     [tok_type], rax
    mov     rax, [rsp + MAXPARAMS * 8 + 16]
    mov     [tok_start], rax
    mov     rax, [rsp + MAXPARAMS * 8 + 24]
    mov     [tok_len], rax
    mov     rax, [rsp + MAXPARAMS * 8 + 32]
    mov     [tok_pos], rax
    mov     rax, [rsp + MAXPARAMS * 8 + 40]
    mov     [retval], rax
    mov     rax, [rsp + MAXPARAMS * 8 + 48]
    mov     [stmt_assign], rax
; and everything that was put aside comes back
.unsave:
    mov     rax, [savetop]
    cmp     rax, r13
    jbe     .unsaved
    dec     rax
    mov     [savetop], rax
    mov     rdx, [save_name + rax * 8]
    mov     r8, [save_val + rax * 8]
    cmp     byte [save_kind + rax], 0
    jne     .unsavearray
    mov     [var_slot + rdx * 8], r8
    jmp     .unsave
.unsavearray:
    mov     [arr_slot + rdx * 8], r8
    jmp     .unsave
.unsaved:
    mov     rax, r14
    add     rsp, MAXPARAMS * 8 + 64
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Strings. A string standing on its own is written exactly as it appears; one
; given to print has its escapes worked out first.
; ---------------------------------------------------------------------------
print_raw_string:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    xor     rcx, rcx
.byte:
    cmp     rcx, r12
    jae     .out
    movzx   eax, byte [rbx + rcx]
    push    rcx
    call    out_char
    pop     rcx
    cmp     al, WHITESPACE_NL
    je      .fresh
    inc     qword [nchars]
    jmp     .next
.fresh:
    mov     qword [nchars], 0
.next:
    inc     rcx
    jmp     .byte
.out:
    pop     r12
    pop     rbx
    ret

print_escaped_string:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    xor     r13, r13
.byte:
    cmp     r13, r12
    jae     .out
    movzx   eax, byte [rbx + r13]
    cmp     al, '\'
    jne     .plain
    lea     rcx, [r13 + 1]
    cmp     rcx, r12
    jae     .plain
    movzx   eax, byte [rbx + r13 + 1]
    inc     r13
    cmp     al, 'n'
    je      .nl
    cmp     al, 't'
    je      .tab
    cmp     al, '\'
    je      .plain
    cmp     al, 'q'
    je      .quote
    cmp     al, 'r'
    je      .cr
    cmp     al, 'a'
    je      .bell
    cmp     al, 'b'
    je      .backspace
    cmp     al, 'e'
    je      .formfeed
    push    rax
    mov     al, '\'
    call    out_char
    inc     qword [nchars]
    pop     rax
    jmp     .plain
.nl:
    mov     al, WHITESPACE_NL
    call    out_char
    mov     qword [nchars], 0
    jmp     .next
.tab:
    mov     al, 9
    jmp     .plain
.quote:
    mov     al, '"'
    jmp     .plain
.cr:
    mov     al, 13
    jmp     .plain
.bell:
    mov     al, 7
    jmp     .plain
.backspace:
    mov     al, 8
    jmp     .plain
.formfeed:
    mov     al, 12
    jmp     .plain
.plain:
    call    out_char
    inc     qword [nchars]
.next:
    inc     r13
    jmp     .byte
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret
