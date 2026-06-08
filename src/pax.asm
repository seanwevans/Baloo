; src/pax.asm
;
; pax - portable archive interchange (ustar format).
;
; Supported usage
;   pax -w [-f ARCHIVE] FILE...   write a ustar archive of the named files
;   pax    [-f ARCHIVE]           list the members of an archive
;
; Write mode emits a POSIX ustar archive (regular files only) to ARCHIVE
; or standard output: a 512-byte header per file, the file data padded to
; a 512-byte boundary, then two zero blocks. List mode reads an archive
; from ARCHIVE or standard input and prints each member name, like
; "tar tf".
;
; Extract/copy modes, directories and other special types, names longer
; than 100 bytes, and the pax extended-header format are out of scope.

    %include "include/sysdefs.inc"

    %define SYS_FSTAT 5
    %define BIG_CAP   1048576

section .bss
    hdr         resb 512
    bigbuf      resb BIG_CAP
    statbuf     resb 144
    zeros       resb 1024
    namebuf     resb 256

    opt_w       resb 1
    arc_file    resq 1
    out_fd      resq 1
    files       resq 256
    nfiles      resq 1
    fidx        resq 1

section .text
global _start

_start:
    pop     rbx                         ;argc
    mov     r12, rsp                    ;argv pointer

    mov     byte [opt_w], 0
    mov     qword [arc_file], 0
    mov     qword [nfiles], 0

    mov     rcx, 1
.parse:
    cmp     rcx, rbx
    jae     .parsed
    mov     rsi, [r12 + rcx*8]
    cmp     byte [rsi], '-'
    jne     .operand
    cmp     byte [rsi + 1], 0
    je      .operand

    mov     al, [rsi + 1]
    cmp     al, 'w'
    je      .opt_w
    cmp     al, 'f'
    je      .opt_f
    inc     rcx                         ;ignore other options
    jmp     .parse

.opt_w:
    mov     byte [opt_w], 1
    inc     rcx
    jmp     .parse

.opt_f:
    cmp     byte [rsi + 2], 0
    je      .f_sep
    lea     rax, [rsi + 2]
    mov     [arc_file], rax
    inc     rcx
    jmp     .parse
.f_sep:
    inc     rcx
    cmp     rcx, rbx
    jae     .parsed
    mov     rax, [r12 + rcx*8]
    mov     [arc_file], rax
    inc     rcx
    jmp     .parse

.operand:
    mov     rax, [nfiles]
    mov     [files + rax*8], rsi
    inc     rax
    mov     [nfiles], rax
    inc     rcx
    jmp     .parse

.parsed:
    cmp     byte [opt_w], 0
    jne     .write_mode
    jmp     list_mode

;==================================================================
; write mode
;==================================================================
.write_mode:
    cmp     qword [arc_file], 0
    je      .out_stdout
    mov     rax, SYS_OPEN
    mov     rdi, [arc_file]
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, DEFAULT_MODE
    syscall
    test    rax, rax
    js      .fatal
    mov     [out_fd], rax
    jmp     .files_loop
.out_stdout:
    mov     qword [out_fd], STDOUT_FILENO

.files_loop:
    mov     qword [fidx], 0
.next_file:
    mov     rax, [fidx]
    cmp     rax, [nfiles]
    jae     .finish_archive
    mov     r13, [files + rax*8]        ;file path

    mov     rax, SYS_OPEN
    mov     rdi, r13
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .skip_file
    mov     r14, rax                    ;fd

    mov     rax, SYS_FSTAT
    mov     rdi, r14
    mov     rsi, statbuf
    syscall

    mov     rdi, r14                    ;read the file contents
    mov     rsi, bigbuf
    mov     rdx, BIG_CAP
    call    slurp
    mov     r15, rax                    ;data length

    mov     rax, SYS_CLOSE
    mov     rdi, r14
    syscall

    mov     rdi, r13                    ;build the header
    call    build_header

    mov     rax, SYS_WRITE              ;header block
    mov     rdi, [out_fd]
    mov     rsi, hdr
    mov     rdx, 512
    syscall

    mov     rax, SYS_WRITE              ;file data
    mov     rdi, [out_fd]
    mov     rsi, bigbuf
    mov     rdx, r15
    syscall

    mov     rax, r15                    ;pad to a 512-byte boundary
    and     rax, 511
    test    rax, rax
    jz      .padded
    mov     rdx, 512
    sub     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, [out_fd]
    mov     rsi, zeros
    syscall
.padded:
    mov     rax, [fidx]
    inc     rax
    mov     [fidx], rax
    jmp     .next_file

.skip_file:
    mov     rax, [fidx]
    inc     rax
    mov     [fidx], rax
    jmp     .next_file

.finish_archive:
    mov     rax, SYS_WRITE              ;two zero blocks end the archive
    mov     rdi, [out_fd]
    mov     rsi, zeros
    mov     rdx, 1024
    syscall
    exit    0

.fatal:
    exit    1

;==================================================================
; list mode - read an archive and print each member name
;==================================================================
list_mode:
    cmp     qword [arc_file], 0
    je      .from_stdin
    mov     rax, SYS_OPEN
    mov     rdi, [arc_file]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .lfatal
    mov     rdi, rax
    jmp     .read
.from_stdin:
    xor     rdi, rdi
.read:
    mov     rsi, bigbuf
    mov     rdx, BIG_CAP
    call    slurp
    mov     r15, rax                    ;archive length

    xor     r14, r14                    ;offset
.block:
    mov     rax, r14
    add     rax, 512
    cmp     rax, r15
    ja      .ldone
    cmp     byte [bigbuf + r14], 0      ;zero block ends the archive
    je      .ldone

    lea     rsi, [bigbuf + r14]         ;print NUL-terminated name
    call    print_name

    lea     rsi, [bigbuf + r14 + 124]   ;parse the octal size field
    call    parse_octal                 ;rax = size
    add     rax, 511                    ;round up to 512 blocks
    and     rax, ~511
    add     r14, 512                    ;skip header
    add     r14, rax                    ;skip data
    jmp     .block
.ldone:
    exit    0
.lfatal:
    exit    1

;------------------------------------------------------------------
; build_header - assemble a ustar header in hdr for the file whose path is
; rdi, using statbuf and the data length in r15.
;------------------------------------------------------------------
build_header:
    push    rdi
    mov     rdi, hdr                    ;zero the header
    xor     eax, eax
    mov     rcx, 512
    rep     stosb
    pop     rdi

    mov     rsi, rdi                    ;name at offset 0 (up to 100 bytes)
    mov     rdi, hdr
    mov     rcx, 100
.cpname:
    mov     al, [rsi]
    test    al, al
    jz      .name_done
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .cpname
.name_done:

    mov     eax, [statbuf + 24]         ;st_mode, keep permission bits
    and     rax, 0xFFF
    mov     rdi, hdr + 100
    mov     rcx, 7
    call    put_octal

    mov     eax, [statbuf + 28]         ;uid
    mov     rdi, hdr + 108
    mov     rcx, 7
    call    put_octal

    mov     eax, [statbuf + 32]         ;gid
    mov     rdi, hdr + 116
    mov     rcx, 7
    call    put_octal

    mov     rax, r15                    ;size
    mov     rdi, hdr + 124
    mov     rcx, 11
    call    put_octal

    mov     rax, [statbuf + 88]         ;mtime
    mov     rdi, hdr + 136
    mov     rcx, 11
    call    put_octal

    mov     byte [hdr + 156], '0'       ;typeflag, regular file

    mov     dword [hdr + 257], 0x61747375 ;"usta"
    mov     word [hdr + 261], 0x0072    ;"r\0"
    mov     word [hdr + 263], 0x3030    ;"00"

; checksum over the header with the checksum field as spaces
    mov     rcx, 8
    mov     rdi, hdr + 148
    mov     al, ' '
.spaces:
    mov     [rdi], al
    inc     rdi
    dec     rcx
    jnz     .spaces

    xor     eax, eax
    xor     rcx, rcx
.sum:
    movzx   edx, byte [hdr + rcx]
    add     eax, edx
    inc     rcx
    cmp     rcx, 512
    jb      .sum

    mov     rdi, hdr + 148
    mov     rcx, 6
    call    put_octal
    mov     byte [hdr + 154], 0
    mov     byte [hdr + 155], ' '
    ret

;------------------------------------------------------------------
; put_octal - write rcx zero-padded octal digits of rax at rdi.
;------------------------------------------------------------------
put_octal:
    lea     rsi, [rdi + rcx]
.loop:
    dec     rsi
    mov     rdx, rax
    and     rdx, 7
    add     dl, '0'
    mov     [rsi], dl
    shr     rax, 3
    dec     rcx
    jnz     .loop
    ret

;------------------------------------------------------------------
; parse_octal - read octal digits at rsi (NUL/space terminated) into rax.
;------------------------------------------------------------------
parse_octal:
    xor     rax, rax
.skip:
    cmp     byte [rsi], ' '
    jne     .loop
    inc     rsi
    jmp     .skip
.loop:
    movzx   rdx, byte [rsi]
    cmp     dl, '0'
    jb      .done
    cmp     dl, '7'
    ja      .done
    sub     dl, '0'
    shl     rax, 3
    add     rax, rdx
    inc     rsi
    jmp     .loop
.done:
    ret

;------------------------------------------------------------------
; print_name - write the NUL-terminated name at rsi plus a newline.
;------------------------------------------------------------------
print_name:
    xor     rdx, rdx
.measure:
    cmp     byte [rsi + rdx], 0
    je      .emit
    inc     rdx
    cmp     rdx, 100
    jb      .measure
.emit:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, newline
    mov     rdx, 1
    syscall
    ret

;------------------------------------------------------------------
; slurp - read fd rdi into [rsi] up to rdx bytes; rax = byte count.
;------------------------------------------------------------------
slurp:
    mov     r10, rsi
    mov     r11, rdx
    xor     r9, r9
.rd:
    mov     rdx, r11
    sub     rdx, r9
    jz      .done
    mov     rax, SYS_READ
    mov     rsi, r10
    add     rsi, r9
    syscall
    test    rax, rax
    jle     .done
    add     r9, rax
    jmp     .rd
.done:
    mov     rax, r9
    ret

section .data
    newline db 10
