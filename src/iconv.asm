; src/iconv.asm -- iconv(1): convert text between character encodings.
; Usage: iconv [-f FROM] [-t TO] [-c] [-s] [FILE...]
;
; Input is decoded to code points and re-encoded, so the two sides are
; independent: any supported encoding converts to any other. Both default to
; UTF-8, which makes a bare "iconv" a validating copy.
;
; Supported: UTF-8, UTF-16BE, UTF-16LE, UTF-32BE, UTF-32LE, UTF-16, UTF-32,
; ISO-8859-1 and ASCII. Names are matched with '-' and '_' ignored, case
; folded, and anything from "//" on (//TRANSLIT, //IGNORE) dropped.
;
; UTF-16 and UTF-32 without an endianness read a byte order mark if one is
; there and default to big endian, and write one on output. Code points above
; the basic plane become a surrogate pair in UTF-16 and are rebuilt from one
; on the way back in.
;
; A sequence that cannot be decoded, or a code point the target encoding
; cannot hold, is replaced with '?' and makes the exit status non-zero unless
; -c asked for the substitution to be silent.

    %include "include/sysdefs.inc"

    %define INCAP 65536
    %define OUTCAP 65536
    %define OUTHIGH (OUTCAP - 16)
    %define NAMECAP 64
    %define MAXFILES 64

    %define E_UTF8 1
    %define E_LATIN1 2
    %define E_ASCII 3
    %define E_UTF16BE 4
    %define E_UTF16LE 5
    %define E_UTF32BE 6
    %define E_UTF32LE 7
    %define E_UTF16 8
    %define E_UTF32 9

    %define REPLACEMENT '?'

section .bss
    inbuf       resb INCAP
    outbuf      resb OUTCAP
    namebuf     resb NAMECAP
    pushbuf     resb 8
    bomtmp      resb 4
    files       resq MAXFILES
    nfiles      resq 1
    infd        resq 1
    inpos       resq 1
    inlen       resq 1
    outlen      resq 1
    npush       resq 1
    from_enc    resq 1
    to_enc      resq 1
    from_active resq 1
    to_active   resq 1
    ineof       resb 1
    opt_quiet   resb 1
    status      resb 1

section .data
    n_utf8      db "UTF8", 0
    n_utf16be   db "UTF16BE", 0
    n_utf16le   db "UTF16LE", 0
    n_utf32be   db "UTF32BE", 0
    n_utf32le   db "UTF32LE", 0
    n_utf16     db "UTF16", 0
    n_utf32     db "UTF32", 0
    n_latin1    db "LATIN1", 0
    n_iso88591  db "ISO88591", 0
    n_ascii     db "ASCII", 0
    n_usascii   db "USASCII", 0
    l_from      db "--from-code", 0
    l_to        db "--to-code", 0

usage_msg   db "Usage: iconv [-f FROM] [-t TO] [-c] [FILE...]", 10
    usage_len   equ $ - usage_msg
badenc_msg  db "iconv: unsupported encoding", 10
    badenc_len  equ $ - badenc_msg
openerr_msg db "iconv: cannot open input file", 10
    openerr_len equ $ - openerr_msg

section .text
global _start

_start:
    mov     qword [from_enc], E_UTF8
    mov     qword [to_enc], E_UTF8

    mov     r12, [rsp]                  ;argc
    lea     r13, [rsp + 16]             ;&argv[1]
    dec     r12

parse:
    cmp     r12, 0
    jle     run
    mov     rdi, [r13]
    test    rdi, rdi
    jz      run
    cmp     byte [rdi], '-'
    jne     .operand
    cmp     byte [rdi + 1], 0
    je      .operand                    ;lone "-" is stdin
    cmp     byte [rdi + 1], '-'
    jne     .short
    cmp     byte [rdi + 2], 0
    jne     .long
    add     r13, 8                      ;"--" ends the options
    dec     r12
    jmp     .tail
.long:
    mov     rsi, l_from
    call    longmatch
    test    al, al
    jnz     .set_from
    mov     rsi, l_to
    call    longmatch
    test    al, al
    jnz     .set_to
    jmp     usage
.set_from:
    cmp     al, 2
    je      .from_have
    call    next_value
.from_have:
    mov     rdi, rdx
    call    encoding_id
    mov     [from_enc], rax
    jmp     .next
.set_to:
    cmp     al, 2
    je      .to_have
    call    next_value
.to_have:
    mov     rdi, rdx
    call    encoding_id
    mov     [to_enc], rax
    jmp     .next
.short:
    lea     rsi, [rdi + 1]
.flag:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .next
    inc     rsi
    cmp     al, 'f'
    je      .f_from
    cmp     al, 't'
    je      .f_to
    cmp     al, 'c'
    je      .f_quiet
    cmp     al, 's'
    je      .flag                       ;-s only silences warnings
    jmp     usage
.f_quiet:
    mov     byte [opt_quiet], 1
    jmp     .flag
.f_from:
    call    opt_value
    mov     rdi, rdx
    call    encoding_id
    mov     [from_enc], rax
    jmp     .next
.f_to:
    call    opt_value
    mov     rdi, rdx
    call    encoding_id
    mov     [to_enc], rax
    jmp     .next
.operand:
    call    add_file
.next:
    add     r13, 8
    dec     r12
    jmp     parse
.tail:
    cmp     r12, 0
    jle     run
    mov     rdi, [r13]
    test    rdi, rdi
    jz      run
    call    add_file
    add     r13, 8
    dec     r12
    jmp     .tail

; opt_value: the rest of this bundle, or the next argument. Value in rdx.
opt_value:
    cmp     byte [rsi], 0
    je      next_value
    mov     rdx, rsi
    ret

next_value:
    add     r13, 8
    dec     r12
    mov     rdx, [r13]
    test    rdx, rdx
    jz      usage
    ret

; longmatch: rdi against the option at rsi. al = 1 bare, 2 with rdx = value.
longmatch:
    push    rdi
    push    rsi
.scan:
    mov     al, [rsi]
    test    al, al
    jz      .end
    cmp     al, [rdi]
    jne     .no
    inc     rsi
    inc     rdi
    jmp     .scan
.end:
    cmp     byte [rdi], 0
    je      .bare
    cmp     byte [rdi], '='
    jne     .no
    lea     rdx, [rdi + 1]
    pop     rsi
    pop     rdi
    mov     al, 2
    ret
.bare:
    pop     rsi
    pop     rdi
    mov     al, 1
    ret
.no:
    pop     rsi
    pop     rdi
    xor     al, al
    ret

add_file:
    mov     rcx, [nfiles]
    cmp     rcx, MAXFILES
    jae     .out
    mov     [files + rcx * 8], rdi
    inc     rcx
    mov     [nfiles], rcx
.out:
    ret

usage:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, usage_msg
    mov     rdx, usage_len
    syscall
    exit    1

bad_encoding:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, badenc_msg
    mov     rdx, badenc_len
    syscall
    exit    1

run:
    call    write_bom
    cmp     qword [nfiles], 0
    jne     .files
    mov     qword [infd], STDIN_FILENO
    call    convert_stream
    jmp     .done
.files:
    xor     rbx, rbx
.loop:
    cmp     rbx, [nfiles]
    jge     .done
    mov     rdi, [files + rbx * 8]
    cmp     byte [rdi], '-'
    jne     .open
    cmp     byte [rdi + 1], 0
    jne     .open
    mov     qword [infd], STDIN_FILENO
    jmp     .convert
.open:
    mov     rax, SYS_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .openfail
    mov     [infd], rax
.convert:
    call    convert_stream
    mov     rdi, [infd]
    cmp     rdi, STDIN_FILENO
    je      .next
    mov     rax, SYS_CLOSE
    syscall
    jmp     .next
.openfail:
    mov     byte [status], 1
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, openerr_msg
    mov     rdx, openerr_len
    syscall
.next:
    inc     rbx
    jmp     .loop
.done:
    call    out_flush
    movzx   edi, byte [status]
    mov     rax, SYS_EXIT
    syscall

; ---------------------------------------------------------------------------
; convert_stream: decode the current input to code points and re-encode.
; ---------------------------------------------------------------------------
convert_stream:
    mov     qword [inpos], 0
    mov     qword [inlen], 0
    mov     qword [npush], 0
    mov     byte [ineof], 0
    mov     rax, [from_enc]
    mov     [from_active], rax
    mov     rax, [to_enc]
    mov     [to_active], rax
    call    read_bom
.loop:
    call    decode_cp
    cmp     rax, -1
    je      .out
    mov     rdi, rax
    call    encode_cp
    jmp     .loop
.out:
    ret

; ---------------------------------------------------------------------------
; read_bom: for UTF-16/UTF-32 with no endianness stated, take it from a byte
; order mark when there is one; otherwise assume big endian and put the bytes
; back.
; ---------------------------------------------------------------------------
read_bom:
    push    rbx
    mov     rax, [from_active]
    cmp     rax, E_UTF16
    je      .utf16
    cmp     rax, E_UTF32
    je      .utf32
    pop     rbx
    ret
.utf16:
    mov     qword [from_active], E_UTF16BE
    call    next_byte
    cmp     rax, -1
    je      .out
    mov     r8, rax
    call    next_byte
    cmp     rax, -1
    je      .push1
    mov     r9, rax
    cmp     r8, 0xFE
    jne     .maybe_le
    cmp     r9, 0xFF
    je      .out                        ;big endian mark, consumed
    jmp     .push2
.maybe_le:
    cmp     r8, 0xFF
    jne     .push2
    cmp     r9, 0xFE
    jne     .push2
    mov     qword [from_active], E_UTF16LE
    pop     rbx
    ret
.push2:
    mov     rdi, r9
    call    push_byte
.push1:
    mov     rdi, r8
    call    push_byte
.out:
    pop     rbx
    ret
.utf32:
    mov     qword [from_active], E_UTF32BE
    xor     rbx, rbx
.read32:
    cmp     rbx, 4
    jae     .check32
    call    next_byte
    cmp     rax, -1
    je      .back32
    mov     [bomtmp + rbx], al
    inc     rbx
    jmp     .read32
.check32:
    cmp     byte [bomtmp], 0
    jne     .try_le
    cmp     byte [bomtmp + 1], 0
    jne     .try_le
    cmp     byte [bomtmp + 2], 0xFE
    jne     .try_le
    cmp     byte [bomtmp + 3], 0xFF
    jne     .try_le
    jmp     .done32                     ;big endian mark, consumed
.try_le:
    cmp     byte [bomtmp], 0xFF
    jne     .back32
    cmp     byte [bomtmp + 1], 0xFE
    jne     .back32
    cmp     byte [bomtmp + 2], 0
    jne     .back32
    cmp     byte [bomtmp + 3], 0
    jne     .back32
    mov     qword [from_active], E_UTF32LE
    jmp     .done32
.back32:
; put them back last first, so they come out in the order they were read
    mov     rcx, rbx
.unread:
    test    rcx, rcx
    jz      .done32
    dec     rcx
    movzx   edi, byte [bomtmp + rcx]
    call    push_byte
    jmp     .unread
.done32:
    pop     rbx
    ret

; write_bom: UTF-16/UTF-32 output with no endianness stated leads with a mark.
write_bom:
    mov     rax, [to_enc]
    cmp     rax, E_UTF16
    je      .utf16
    cmp     rax, E_UTF32
    je      .utf32
    ret
.utf16:
    mov     qword [to_enc], E_UTF16BE
    mov     al, 0xFE
    call    out_char
    mov     al, 0xFF
    call    out_char
    ret
.utf32:
    mov     qword [to_enc], E_UTF32BE
    xor     al, al
    call    out_char
    xor     al, al
    call    out_char
    mov     al, 0xFE
    call    out_char
    mov     al, 0xFF
    call    out_char
    ret

; ---------------------------------------------------------------------------
; decode_cp: the next code point from the input, or -1 at end of input.
; ---------------------------------------------------------------------------
decode_cp:
    mov     rax, [from_active]
    cmp     rax, E_UTF8
    je      dec_utf8
    cmp     rax, E_UTF16BE
    je      dec_utf16be
    cmp     rax, E_UTF16LE
    je      dec_utf16le
    cmp     rax, E_UTF32BE
    je      dec_utf32be
    cmp     rax, E_UTF32LE
    je      dec_utf32le
    cmp     rax, E_ASCII
    je      dec_ascii
; ISO-8859-1: every byte is its own code point
    jmp     next_byte

dec_ascii:
    call    next_byte
    cmp     rax, -1
    je      .out
    cmp     rax, 0x80
    jb      .out
    call    substituted
    mov     rax, REPLACEMENT
.out:
    ret

dec_utf8:
    call    next_byte
    cmp     rax, -1
    je      .out
    cmp     rax, 0x80
    jb      .out                        ;plain ASCII
    mov     r8, rax
    mov     rcx, 1                      ;continuation bytes wanted
    mov     r9, 0x1F                    ;mask for the lead byte
    mov     rax, r8
    and     rax, 0xE0
    cmp     rax, 0xC0
    je      .lead
    mov     rcx, 2
    mov     r9, 0x0F
    mov     rax, r8
    and     rax, 0xF0
    cmp     rax, 0xE0
    je      .lead
    mov     rcx, 3
    mov     r9, 0x07
    mov     rax, r8
    and     rax, 0xF8
    cmp     rax, 0xF0
    je      .lead
    jmp     .bad                        ;a stray continuation or 0xFE/0xFF
.lead:
    mov     r10, r8
    and     r10, r9                     ;accumulated code point
.continue:
    test    rcx, rcx
    jz      .done
    call    next_byte
    cmp     rax, -1
    je      .bad
    mov     r11, rax
    and     r11, 0xC0
    cmp     r11, 0x80
    jne     .bad
    shl     r10, 6
    and     rax, 0x3F
    or      r10, rax
    dec     rcx
    jmp     .continue
.done:
    mov     rax, r10
    ret
.bad:
    call    substituted
    mov     rax, REPLACEMENT
.out:
    ret

dec_utf16be:
    call    read_u16be
    cmp     rax, -1
    je      .out
    call    utf16_pair
.out:
    ret

dec_utf16le:
    call    read_u16le
    cmp     rax, -1
    je      .out
    call    utf16_pair
.out:
    ret

; utf16_pair: rax holds a UTF-16 unit; join it with a low surrogate when it
; is a high one.
utf16_pair:
    cmp     rax, 0xD800
    jb      .out
    cmp     rax, 0xDBFF
    ja      .out
    mov     r8, rax
    cmp     qword [from_active], E_UTF16LE
    je      .low_le
    call    read_u16be
    jmp     .have
.low_le:
    call    read_u16le
.have:
    cmp     rax, -1
    je      .bad
    cmp     rax, 0xDC00
    jb      .bad
    cmp     rax, 0xDFFF
    ja      .bad
    sub     r8, 0xD800
    shl     r8, 10
    sub     rax, 0xDC00
    add     rax, r8
    add     rax, 0x10000
    ret
.bad:
    call    substituted
    mov     rax, REPLACEMENT
.out:
    ret

read_u16be:
    call    next_byte
    cmp     rax, -1
    je      .out
    mov     r9, rax
    call    next_byte
    cmp     rax, -1
    je      .out
    shl     r9, 8
    or      rax, r9
.out:
    ret

read_u16le:
    call    next_byte
    cmp     rax, -1
    je      .out
    mov     r9, rax
    call    next_byte
    cmp     rax, -1
    je      .out
    shl     rax, 8
    or      rax, r9
.out:
    ret

dec_utf32be:
    xor     r9, r9
    mov     rcx, 4
.byte:
    call    next_byte
    cmp     rax, -1
    je      .out
    shl     r9, 8
    or      r9, rax
    dec     rcx
    jnz     .byte
    mov     rax, r9
.out:
    ret

dec_utf32le:
    call    next_byte
    cmp     rax, -1
    je      .out
    mov     r9, rax
    call    next_byte
    cmp     rax, -1
    je      .out
    shl     rax, 8
    or      r9, rax
    call    next_byte
    cmp     rax, -1
    je      .out
    shl     rax, 16
    or      r9, rax
    call    next_byte
    cmp     rax, -1
    je      .out
    shl     rax, 24
    or      r9, rax
    mov     rax, r9
.out:
    ret

; ---------------------------------------------------------------------------
; encode_cp: write the code point in rdi in the target encoding.
; ---------------------------------------------------------------------------
encode_cp:
    mov     rax, [to_enc]
    cmp     rax, E_UTF8
    je      enc_utf8
    cmp     rax, E_UTF16BE
    je      enc_utf16be
    cmp     rax, E_UTF16LE
    je      enc_utf16le
    cmp     rax, E_UTF32BE
    je      enc_utf32be
    cmp     rax, E_UTF32LE
    je      enc_utf32le
    cmp     rax, E_ASCII
    je      enc_ascii
    jmp     enc_latin1

enc_ascii:
    cmp     rdi, 0x80
    jb      .plain
    call    substituted
    mov     rdi, REPLACEMENT
.plain:
    mov     al, dil
    jmp     out_char

enc_latin1:
    cmp     rdi, 0x100
    jb      .plain
    call    substituted
    mov     rdi, REPLACEMENT
.plain:
    mov     al, dil
    jmp     out_char

enc_utf8:
    cmp     rdi, 0x80
    jb      .one
    cmp     rdi, 0x800
    jb      .two
    cmp     rdi, 0x10000
    jb      .three
.four:
    mov     rax, rdi
    shr     rax, 18
    or      al, 0xF0
    call    out_char
    mov     rax, rdi
    shr     rax, 12
    and     al, 0x3F
    or      al, 0x80
    call    out_char
    mov     rax, rdi
    shr     rax, 6
    and     al, 0x3F
    or      al, 0x80
    call    out_char
    jmp     .final
.three:
    mov     rax, rdi
    shr     rax, 12
    or      al, 0xE0
    call    out_char
    mov     rax, rdi
    shr     rax, 6
    and     al, 0x3F
    or      al, 0x80
    call    out_char
    jmp     .final
.two:
    mov     rax, rdi
    shr     rax, 6
    or      al, 0xC0
    call    out_char
.final:
    mov     rax, rdi
    and     al, 0x3F
    or      al, 0x80
    jmp     out_char
.one:
    mov     al, dil
    jmp     out_char

enc_utf16be:
    cmp     rdi, 0x10000
    jae     .surrogates
    mov     rax, rdi
    shr     rax, 8
    call    out_char
    mov     al, dil
    jmp     out_char
.surrogates:
    call    split_surrogates            ;r8 = high, r9 = low
    mov     rax, r8
    shr     rax, 8
    call    out_char
    mov     al, r8b
    call    out_char
    mov     rax, r9
    shr     rax, 8
    call    out_char
    mov     al, r9b
    jmp     out_char

enc_utf16le:
    cmp     rdi, 0x10000
    jae     .surrogates
    mov     al, dil
    call    out_char
    mov     rax, rdi
    shr     rax, 8
    jmp     out_char
.surrogates:
    call    split_surrogates
    mov     al, r8b
    call    out_char
    mov     rax, r8
    shr     rax, 8
    call    out_char
    mov     al, r9b
    call    out_char
    mov     rax, r9
    shr     rax, 8
    jmp     out_char

; split_surrogates: rdi above the basic plane becomes r8 high, r9 low.
split_surrogates:
    mov     r8, rdi
    sub     r8, 0x10000
    mov     r9, r8
    shr     r8, 10
    add     r8, 0xD800
    and     r9, 0x3FF
    add     r9, 0xDC00
    ret

enc_utf32be:
    mov     rax, rdi
    shr     rax, 24
    call    out_char
    mov     rax, rdi
    shr     rax, 16
    call    out_char
    mov     rax, rdi
    shr     rax, 8
    call    out_char
    mov     al, dil
    jmp     out_char

enc_utf32le:
    mov     al, dil
    call    out_char
    mov     rax, rdi
    shr     rax, 8
    call    out_char
    mov     rax, rdi
    shr     rax, 16
    call    out_char
    mov     rax, rdi
    shr     rax, 24
    jmp     out_char

; substituted: note that a character had to be replaced.
substituted:
    cmp     byte [opt_quiet], 0
    jne     .out
    mov     byte [status], 1
.out:
    ret

; ---------------------------------------------------------------------------
; Byte-at-a-time input, so a multibyte sequence can straddle a read boundary.
; ---------------------------------------------------------------------------
; Only rax is clobbered: the decoders count their remaining bytes in rcx
; across these calls.
next_byte:
    push    rcx
    mov     rcx, [npush]
    test    rcx, rcx
    jz      .buffered
    dec     rcx
    mov     [npush], rcx
    movzx   eax, byte [pushbuf + rcx]
    pop     rcx
    ret
.buffered:
    mov     rcx, [inpos]
    cmp     rcx, [inlen]
    jb      .take
    cmp     byte [ineof], 0
    jne     .eof
    push    rdi
    push    rsi
    push    rdx
    mov     rax, SYS_READ
    mov     rdi, [infd]
    mov     rsi, inbuf
    mov     rdx, INCAP
    syscall
    pop     rdx
    pop     rsi
    pop     rdi
    test    rax, rax
    jle     .drained
    mov     [inlen], rax
    mov     qword [inpos], 0
    mov     rcx, 0
    jmp     .take
.drained:
    mov     byte [ineof], 1
.eof:
    mov     rax, -1
    pop     rcx
    ret
.take:
    movzx   eax, byte [inbuf + rcx]
    inc     rcx
    mov     [inpos], rcx
    pop     rcx
    ret

; push_byte: put the byte in rdi back for the next read.
push_byte:
    push    rcx
    mov     rcx, [npush]
    cmp     rcx, 8
    jae     .out
    mov     [pushbuf + rcx], dil
    inc     rcx
    mov     [npush], rcx
.out:
    pop     rcx
    ret

; ---------------------------------------------------------------------------
; encoding_id: map an encoding name to its id, exiting when it is not one we
; know. '-' and '_' are ignored, case is folded, and a "//..." suffix is cut.
; ---------------------------------------------------------------------------
encoding_id:
    mov     rsi, rdi
    mov     rdi, namebuf
    xor     rcx, rcx
.normalize:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .done
    cmp     al, '/'
    je      .done                       ;//TRANSLIT and friends
    cmp     al, '-'
    je      .skip
    cmp     al, '_'
    je      .skip
    cmp     al, 'a'
    jb      .store
    cmp     al, 'z'
    ja      .store
    sub     al, 32
.store:
    cmp     rcx, NAMECAP - 1
    jae     .skip
    mov     [rdi + rcx], al
    inc     rcx
.skip:
    inc     rsi
    jmp     .normalize
.done:
    mov     byte [rdi + rcx], 0
    mov     rsi, n_utf8
    call    nameeq
    test    al, al
    jnz     .utf8
    mov     rsi, n_utf16be
    call    nameeq
    test    al, al
    jnz     .utf16be
    mov     rsi, n_utf16le
    call    nameeq
    test    al, al
    jnz     .utf16le
    mov     rsi, n_utf32be
    call    nameeq
    test    al, al
    jnz     .utf32be
    mov     rsi, n_utf32le
    call    nameeq
    test    al, al
    jnz     .utf32le
    mov     rsi, n_utf16
    call    nameeq
    test    al, al
    jnz     .utf16
    mov     rsi, n_utf32
    call    nameeq
    test    al, al
    jnz     .utf32
    mov     rsi, n_latin1
    call    nameeq
    test    al, al
    jnz     .latin1
    mov     rsi, n_iso88591
    call    nameeq
    test    al, al
    jnz     .latin1
    mov     rsi, n_ascii
    call    nameeq
    test    al, al
    jnz     .ascii
    mov     rsi, n_usascii
    call    nameeq
    test    al, al
    jnz     .ascii
    jmp     bad_encoding
.utf8:
    mov     rax, E_UTF8
    ret
.utf16be:
    mov     rax, E_UTF16BE
    ret
.utf16le:
    mov     rax, E_UTF16LE
    ret
.utf32be:
    mov     rax, E_UTF32BE
    ret
.utf32le:
    mov     rax, E_UTF32LE
    ret
.utf16:
    mov     rax, E_UTF16
    ret
.utf32:
    mov     rax, E_UTF32
    ret
.latin1:
    mov     rax, E_LATIN1
    ret
.ascii:
    mov     rax, E_ASCII
    ret

; nameeq: does the normalized name in namebuf equal the literal at rsi?
nameeq:
    push    rsi
    mov     rdi, namebuf
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
    ret
.no:
    xor     al, al
    pop     rsi
    ret

; ---------------------------------------------------------------------------
; Buffered output.
; ---------------------------------------------------------------------------
out_char:
    push    rcx
    mov     rcx, [outlen]
    mov     [outbuf + rcx], al
    inc     rcx
    mov     [outlen], rcx
    cmp     rcx, OUTHIGH
    jb      .out
    call    out_flush
.out:
    pop     rcx
    ret

out_flush:
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    mov     rdx, [outlen]
    test    rdx, rdx
    jz      .out
    mov     rsi, outbuf
.write:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    test    rax, rax
    jle     .done
    add     rsi, rax
    sub     rdx, rax
    jnz     .write
.done:
    mov     qword [outlen], 0
.out:
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi
    ret
