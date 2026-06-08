; src/pr.asm
;
; pr - paginate text files for printing.
;
; Supported usage
;   pr [-t] [-h TEXT] [-l N] [-w N] [FILE...]
;
;   default     break the input into 66-line pages, each with a five-line
;               header (two blank lines, a header line, two blank lines)
;               and a five-line blank trailer, leaving 56 body lines
;   -t          omit the page headers and trailers (stream the lines)
;   -h TEXT     use TEXT as the centered header instead of the file name
;   -l N        set the page length (default 66 lines)
;   -w N        set the page width (default 72 columns)
;
; The header line is "<date>  <name centered>  Page <n>", where the date is
; the file's modification time (the current time for standard input),
; rendered as YYYY-MM-DD HH:MM in UTC. With no FILE, or with "-", standard
; input is read.
;
; Multi-column output, line numbering, and the remaining flags are out of
; scope; this implements single-column pagination.

    %include "include/sysdefs.inc"

    %define SYS_FSTAT 5

section .bss
    inbuf       resb 1048576            ;slurped input
    statbuf     resb 144
date_buf    resb 16                 ;YYYY-MM-DD HH:MM
    hdr_line    resb 1024               ;assembled header line
    page_text   resb 32                 ;"Page N"
    numtmp      resb 32

    files       resq 256                ;file operand pointers
    nfiles      resq 1
    fidx        resq 1
    name_ptr    resq 1                  ;header name (file path or -h text)
    hdr_override resq 1                 ;-h text, or 0
    opt_t       resb 1
    page_w      resq 1
    page_l      resq 1
    body_lines  resq 1
    cur_fd      resq 1
    cur_mtime   resq 1
    cur_n       resq 1

section .data
    page_word   db "Page "
    empty_str   db 0
error_open  db "pr: cannot open input file", 10
    error_open_len equ $ - error_open
    nlbuf       times 256 db 10

section .text
global _start

_start:
    pop     rbx                         ;argc
    mov     r12, rsp                    ;argv pointer

    mov     qword [page_w], 72
    mov     qword [page_l], 66
    mov     byte [opt_t], 0
    mov     qword [hdr_override], 0
    mov     qword [nfiles], 0

    mov     rcx, 1
.parse:
    cmp     rcx, rbx
    jae     .parsed
    mov     rsi, [r12 + rcx*8]
    cmp     byte [rsi], '-'
    jne     .isfile
    cmp     byte [rsi + 1], 0
    je      .isfile                     ;"-" means standard input

    mov     al, [rsi + 1]
    cmp     al, 't'
    je      .opt_t
    cmp     al, 'h'
    je      .opt_h
    cmp     al, 'l'
    je      .opt_l
    cmp     al, 'w'
    je      .opt_w
    inc     rcx                         ;unsupported flag, skip it
    jmp     .parse

.opt_t:
    mov     byte [opt_t], 1
    inc     rcx
    jmp     .parse

.opt_h:
    cmp     byte [rsi + 2], 0
    je      .h_sep
    lea     rax, [rsi + 2]
    mov     [hdr_override], rax
    inc     rcx
    jmp     .parse
.h_sep:
    inc     rcx
    cmp     rcx, rbx
    jae     .parsed
    mov     rax, [r12 + rcx*8]
    mov     [hdr_override], rax
    inc     rcx
    jmp     .parse

.opt_l:
    cmp     byte [rsi + 2], 0
    je      .l_sep
    lea     rsi, [rsi + 2]
    call    parse_uint
    mov     [page_l], rax
    inc     rcx
    jmp     .parse
.l_sep:
    inc     rcx
    cmp     rcx, rbx
    jae     .parsed
    mov     rsi, [r12 + rcx*8]
    call    parse_uint
    mov     [page_l], rax
    inc     rcx
    jmp     .parse

.opt_w:
    cmp     byte [rsi + 2], 0
    je      .w_sep
    lea     rsi, [rsi + 2]
    call    parse_uint
    mov     [page_w], rax
    inc     rcx
    jmp     .parse
.w_sep:
    inc     rcx
    cmp     rcx, rbx
    jae     .parsed
    mov     rsi, [r12 + rcx*8]
    call    parse_uint
    mov     [page_w], rax
    inc     rcx
    jmp     .parse

.isfile:
    mov     rax, [nfiles]
    mov     [files + rax*8], rsi
    inc     rax
    mov     [nfiles], rax
    inc     rcx
    jmp     .parse

.parsed:
    mov     rax, [page_l]               ;body_lines = page_l - 10
    sub     rax, 10
    jg      .body_ok
    mov     byte [opt_t], 1             ;too short for a header, act like -t
    mov     rax, 1
.body_ok:
    mov     [body_lines], rax

    cmp     qword [nfiles], 0
    jne     .files_loop

; no operands - read standard input
    mov     rax, [hdr_override]
    test    rax, rax
    jnz     .stdin_name
    mov     rax, empty_str
.stdin_name:
    mov     [name_ptr], rax
    mov     rax, SYS_TIME
    xor     rdi, rdi
    syscall
    mov     rdi, rax
    call    format_date
    xor     rdi, rdi                    ;fd 0
    call    slurp
    mov     r12, inbuf
    lea     r13, [inbuf + rax]
    call    paginate
    jmp     .exit

.files_loop:
    mov     qword [fidx], 0
.next_file:
    mov     rax, [fidx]
    cmp     rax, [nfiles]
    jae     .exit
    mov     r9, [files + rax*8]

    mov     rax, [hdr_override]
    test    rax, rax
    jnz     .nset
    mov     rax, r9
.nset:
    mov     [name_ptr], rax

    mov     rax, SYS_OPEN
    mov     rdi, r9
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .file_err
    mov     [cur_fd], rax

    mov     rax, SYS_FSTAT
    mov     rdi, [cur_fd]
    mov     rsi, statbuf
    syscall
    mov     rax, [statbuf + 88]         ;st_mtime seconds
    mov     [cur_mtime], rax

    mov     rdi, [cur_fd]
    call    slurp
    mov     [cur_n], rax

    mov     rax, SYS_CLOSE
    mov     rdi, [cur_fd]
    syscall

    mov     rdi, [cur_mtime]
    call    format_date

    mov     r12, inbuf
    mov     r13, inbuf
    add     r13, [cur_n]
    call    paginate

    mov     rax, [fidx]
    inc     rax
    mov     [fidx], rax
    jmp     .next_file

.file_err:
    write   STDERR_FILENO, error_open, error_open_len
    mov     rax, [fidx]
    inc     rax
    mov     [fidx], rax
    jmp     .next_file

.exit:
    exit    0

;------------------------------------------------------------------
; paginate - emit inbuf[r12..r13) as pages. Uses date_buf, name_ptr,
; opt_t, page_w, body_lines. Page counter and cursor live in r12-r15.
;------------------------------------------------------------------
paginate:
    cmp     byte [opt_t], 0
    jne     .stream
    cmp     r12, r13
    jae     .ret
    mov     r15, 1                      ;page number
.page_start:
    cmp     r12, r13
    jae     .ret
    call    emit_header
    xor     r14, r14                    ;lines on this page
.line:
    call    emit_line
    inc     r14
    cmp     r12, r13
    jae     .flush
    mov     rax, [body_lines]
    cmp     r14, rax
    jb      .line
    call    emit_trailer
    inc     r15
    jmp     .page_start
.flush:
    mov     rax, [body_lines]
    sub     rax, r14
    mov     r8, rax
    call    emit_blanks                 ;pad the body to full length
    call    emit_trailer
    ret
.stream:
    cmp     r12, r13
    jae     .ret
    call    emit_line
    jmp     .stream
.ret:
    ret

;------------------------------------------------------------------
; emit_line - write one line at r12 plus a newline. Advances r12 past the
; newline (or to r13). Preserves r12 result, r13, r14, r15.
;------------------------------------------------------------------
emit_line:
    mov     rsi, r12
    mov     r9, r12
.scan:
    cmp     r9, r13
    jae     .write
    cmp     byte [r9], 10
    je      .write
    inc     r9
    jmp     .scan
.write:
    mov     rdx, r9
    sub     rdx, rsi
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    mov     r8, 1
    call    emit_blanks
    cmp     r9, r13
    jae     .at_end
    lea     r12, [r9 + 1]
    ret
.at_end:
    mov     r12, r13
    ret

;------------------------------------------------------------------
; emit_trailer - five blank lines. emit_blanks/header preserve r12-r15.
;------------------------------------------------------------------
emit_trailer:
    mov     r8, 5
    call    emit_blanks
    ret

;------------------------------------------------------------------
; emit_blanks - write r8 newlines. Clobbers rax, rdi, rsi, rdx; keeps r8
; decremented to zero and leaves r9-r15 intact.
;------------------------------------------------------------------
emit_blanks:
.loop:
    test    r8, r8
    jle     .done
    mov     rdx, r8
    cmp     rdx, 256
    jbe     .w
    mov     rdx, 256
.w:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, nlbuf
    syscall
    sub     r8, rdx
    jmp     .loop
.done:
    ret

;------------------------------------------------------------------
; emit_header - write the five-line header block for page r15. Preserves
; r12-r15.
;------------------------------------------------------------------
emit_header:
    mov     r8, 2                       ;two leading blank lines
    call    emit_blanks

    mov     rdi, page_text              ;build "Page N"
    mov     rsi, page_word
    mov     rcx, 5
.cpw:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .cpw
    mov     rax, r15
    call    append_decimal
    mov     r9, rdi
    sub     r9, page_text               ;r9 = length of "Page N"

    mov     rcx, [page_w]               ;fill header line with spaces
    mov     rdi, hdr_line
    mov     al, 32
.fill:
    mov     [rdi], al
    inc     rdi
    dec     rcx
    jnz     .fill

    mov     rsi, date_buf               ;date occupies columns 0..16
    mov     rdi, hdr_line
    mov     rcx, 16
.cpd:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .cpd

    mov     rdi, hdr_line               ;"Page N" right-aligned
    add     rdi, [page_w]
    sub     rdi, r9
    mov     rsi, page_text
    mov     rcx, r9
.cpp:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .cpp

    mov     r10, [page_w]               ;center name in [16, W - pagelen)
    sub     r10, r9
    sub     r10, 16
    mov     rsi, [name_ptr]
    call    strlen                      ;rbx = name length
    mov     rax, r10
    sub     rax, rbx
    jle     .no_center
    shr     rax, 1
    jmp     .have_pad
.no_center:
    xor     rax, rax
.have_pad:
    mov     rdi, hdr_line
    add     rdi, 16
    add     rdi, rax
    mov     rsi, [name_ptr]
    mov     rcx, rbx
    test    rcx, rcx
    jz      .name_done
.cpn:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .cpn
.name_done:
    mov     rdi, hdr_line               ;terminating newline at column W
    add     rdi, [page_w]
    mov     byte [rdi], 10

    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, hdr_line
    mov     rdx, [page_w]
    inc     rdx
    syscall

    mov     r8, 2                       ;two trailing blank lines
    call    emit_blanks
    ret

;------------------------------------------------------------------
; append_decimal - write rax in decimal at rdi, returning rdi advanced.
;------------------------------------------------------------------
append_decimal:
    mov     rcx, numtmp + 32
    mov     r11, 10
.div:
    xor     rdx, rdx
    div     r11
    add     dl, '0'
    dec     rcx
    mov     [rcx], dl
    test    rax, rax
    jnz     .div
.copy:
    mov     al, [rcx]
    mov     [rdi], al
    inc     rdi
    inc     rcx
    cmp     rcx, numtmp + 32
    jb      .copy
    ret

;------------------------------------------------------------------
; parse_uint - read decimal digits at rsi, returning the value in rax.
;------------------------------------------------------------------
parse_uint:
    xor     rax, rax
.loop:
    movzx   rdx, byte [rsi]
    sub     dl, '0'
    cmp     dl, 9
    ja      .done
    imul    rax, rax, 10
    add     rax, rdx
    inc     rsi
    jmp     .loop
.done:
    ret

;------------------------------------------------------------------
; slurp - read fd rdi into inbuf, returning byte count in rax.
;------------------------------------------------------------------
slurp:
    xor     r8, r8
.rd:
    mov     rdx, 1048576
    sub     rdx, r8
    jz      .done
    mov     rax, SYS_READ
    mov     rsi, inbuf
    add     rsi, r8
    syscall
    test    rax, rax
    jle     .done
    add     r8, rax
    jmp     .rd
.done:
    mov     rax, r8
    ret

;------------------------------------------------------------------
; format_date - render the UTC date of unix time rdi into date_buf as
; YYYY-MM-DD HH:MM. Uses the civil-from-days conversion.
;------------------------------------------------------------------
format_date:
    mov     rax, rdi
    xor     rdx, rdx
    mov     rcx, 86400
    div     rcx                         ;rax = days, rdx = second of day
    mov     r8, rax
    mov     rax, rdx
    xor     rdx, rdx
    mov     rcx, 3600
    div     rcx                         ;rax = hour, rdx = remainder
    mov     r9, rax
    mov     rax, rdx
    xor     rdx, rdx
    mov     rcx, 60
    div     rcx                         ;rax = minute
    mov     r10, rax

    mov     rax, r8                     ;z = days + 719468
    add     rax, 719468
    xor     rdx, rdx
    mov     rcx, 146097
    div     rcx                         ;rax = era, rdx = doe
    mov     r11, rax
    mov     rsi, rdx                    ;doe

    mov     rax, rsi                    ;yoe numerator
    xor     rdx, rdx
    mov     rcx, 1460
    div     rcx
    mov     rbx, rax                    ;doe/1460
    mov     rax, rsi
    xor     rdx, rdx
    mov     rcx, 36524
    div     rcx
    mov     r12, rsi
    sub     r12, rbx
    add     r12, rax                    ;doe - doe/1460 + doe/36524
    mov     rax, rsi
    xor     rdx, rdx
    mov     rcx, 146096
    div     rcx
    sub     r12, rax
    mov     rax, r12
    xor     rdx, rdx
    mov     rcx, 365
    div     rcx                         ;rax = yoe
    mov     r13, rax

    mov     rax, r11                    ;y = yoe + era*400
    imul    rax, rax, 400
    add     rax, r13
    mov     r14, rax

    mov     rax, r13                    ;doy = doe - (365*yoe + yoe/4 - yoe/100)
    imul    rax, rax, 365
    mov     rbx, rax
    mov     rax, r13
    xor     rdx, rdx
    mov     rcx, 4
    div     rcx
    add     rbx, rax
    mov     rax, r13
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    sub     rbx, rax
    mov     rax, rsi
    sub     rax, rbx
    mov     r15, rax                    ;doy

    mov     rax, r15                    ;mp = (5*doy + 2)/153
    imul    rax, rax, 5
    add     rax, 2
    xor     rdx, rdx
    mov     rcx, 153
    div     rcx
    mov     rbx, rax                    ;mp

    mov     rax, rbx                    ;d = doy - (153*mp + 2)/5 + 1
    imul    rax, rax, 153
    add     rax, 2
    xor     rdx, rdx
    mov     rcx, 5
    div     rcx
    mov     rcx, r15
    sub     rcx, rax
    inc     rcx                         ;rcx = day

mov     rax, rbx                    ;m = mp < 10 ? mp+3 : mp-9
    cmp     rax, 10
    jb      .m_lt
    sub     rax, 9
    jmp     .m_done
.m_lt:
    add     rax, 3
.m_done:
    cmp     rax, 2                      ;y += (m <= 2)
    ja      .no_year_inc
    inc     r14
.no_year_inc:

; write YYYY-MM-DD HH:MM into date_buf
    mov     rdi, date_buf
    push    rax                         ;month
    push    rcx                         ;day
    mov     rax, r14
    call    put4
    mov     byte [rdi], 45
    inc     rdi
    pop     rcx
    pop     rax
    push    rcx
    call    put2                        ;month (rax)
    mov     byte [rdi], 45
    inc     rdi
    pop     rax
    call    put2                        ;day
    mov     byte [rdi], 32
    inc     rdi
    mov     rax, r9
    call    put2                        ;hour
    mov     byte [rdi], 58
    inc     rdi
    mov     rax, r10
    call    put2                        ;minute
    ret

;------------------------------------------------------------------
; put2 - write rax as two zero-padded decimal digits at rdi (advances rdi)
; put4 - write rax as four zero-padded decimal digits at rdi
;------------------------------------------------------------------
put2:
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    add     al, '0'
    mov     [rdi], al
    mov     al, dl
    add     al, '0'
    mov     [rdi + 1], al
    add     rdi, 2
    ret

put4:
    xor     rdx, rdx
    mov     rcx, 1000
    div     rcx
    add     al, '0'
    mov     [rdi], al                   ;thousands
    mov     rax, rdx
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    add     al, '0'
    mov     [rdi + 1], al               ;hundreds
    mov     rax, rdx
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    add     al, '0'
    mov     [rdi + 2], al               ;tens
    add     dl, '0'
    mov     [rdi + 3], dl               ;ones
    add     rdi, 4
    ret
