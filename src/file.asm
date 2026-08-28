; src/file.asm -- file(1): describe the type of each operand.
; Usage: file [-b] [-h] [-L] FILE...   ("-" reads standard input)
;
; The file's mode decides first: directories, devices, fifos and sockets are
; named from stat alone, and a symlink reports its target (and whether that
; target exists) unless -L was given to follow it.
;
; Regular files are matched against a table of magic numbers, then fall back
; to looking at the bytes: printable ASCII throughout is "ASCII text", a
; clean multibyte decode is "UTF-8 text", and anything else is "data".
;
; Two magics need more than a prefix. A cafebabe header is a Java class or a
; Mach-O universal binary depending on whether the word after it reads as a
; class version or as a plausible architecture count, and tar has no magic at
; the start at all -- "ustar" sits 257 bytes in, with the bytes after it
; separating GNU's format from POSIX's.

    %include "include/sysdefs.inc"

    %define SYS_LSTAT 6

    %define BUFCAP 65536
    %define LINECAP 8192
    %define MAXNAMES 256
    %define TAR_MAGIC_OFF 257

    %define ST_MODE 24
    %define ST_RDEV 40
    %define ST_SIZE 48

    %define S_IFMT 0o170000
    %define S_IFIFO 0o010000
    %define S_IFCHR 0o020000
    %define S_IFDIR 0o040000
    %define S_IFBLK 0o060000
    %define S_IFREG 0o100000
    %define S_IFLNK 0o120000
    %define S_IFSOCK 0o140000

section .bss
    readbuf     resb BUFCAP
    linebuf     resb LINECAP
    linkbuf     resb 4096
    stbuf       resb 160
    names       resq MAXNAMES
    nnames      resq 1
    readlen     resq 1
    linelen     resq 1
    opt_follow  resb 1
    opt_brief   resb 1
    status      resb 1

section .data
    m_elf       db 0x7F, "ELF"
    m_gzip      db 0x1F, 0x8B
    m_bzip      db "BZh"
    m_7z        db 0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C
    m_zip       db "PK", 3, 4
    m_gif87     db "GIF87a"
    m_gif89     db "GIF89a"
    m_dex       db "dex", 10
    m_ar        db "!<arch>", 10
    m_cafe      db 0xCA, 0xFE, 0xBA, 0xBE
    m_ustar     db "ustar"
    m_png       db 0x89, "PNG", 13, 10, 26, 10
    m_jpeg      db 0xFF, 0xD8, 0xFF
    m_pdf       db "%PDF-"
    m_cpio_nocrc db "070701"
    m_cpio_crc  db "070702"
    m_cpio_odc  db "070707"

    t_directory db "directory", 0
    t_empty     db "empty", 0
    t_data      db "data", 0
    t_ascii     db "ASCII text", 0
    t_utf8      db "UTF-8 text", 0
    t_fifo      db "fifo (named pipe)", 0
    t_socket    db "socket", 0
    t_chr       db "character special (", 0
    t_blk       db "block special (", 0
    t_symlink   db "symbolic link to ", 0
    t_broken    db "broken symbolic link to ", 0
    t_gzip      db "gzip compressed data", 0
    t_bzip      db "bzip2 compressed data, block size = ", 0
    t_bzip_k    db "00k", 0
    t_7z        db "7-zip archive data, version ", 0
    t_zip       db "Zip archive data, at least v", 0
    t_zip_tail  db " to extract", 0
    t_gif       db "GIF image data, version ", 0
    t_dex       db "Android dex file, version ", 0
    t_ar        db "current ar archive", 0
    t_java      db "compiled Java class data, version ", 0
    t_macho     db "Mach-O universal binary with ", 0
t_arches    db " architectures: ", 0
    t_tar_gnu   db "POSIX tar archive (GNU)", 0
    t_tar       db "POSIX tar archive", 0
    t_png       db "PNG image data", 0
    t_jpeg      db "JPEG image data", 0
    t_pdf       db "PDF document", 0
    t_cpio_nocrc db "ASCII cpio archive (SVR4 with no CRC)", 0
    t_cpio_crc  db "ASCII cpio archive (SVR4 with CRC)", 0
    t_cpio_odc  db "ASCII cpio archive (pre-SVR4 or odc)", 0
    t_script_a  db "a ", 0
    t_script_b  db " script", 0
    t_elf       db "ELF ", 0
    t_elf_bad   db "ELF, unknown class or byte order", 0
    t_cannot    db "cannot open", 0

    e_32        db "32-bit ", 0
    e_64        db "64-bit ", 0
    e_lsb       db "LSB ", 0
    e_msb       db "MSB ", 0
    e_none      db "no file type", 0
    e_rel       db "relocatable", 0
    e_exec      db "executable", 0
    e_dyn       db "shared object", 0
    e_core      db "core dump", 0
    e_type_q    db "unknown type", 0
    e_comma     db ", ", 0
    e_386       db "Intel 80386", 0
    e_x8664     db "x86-64", 0
    e_arm       db "ARM", 0
    e_aarch64   db "ARM aarch64", 0
    e_mips      db "MIPS", 0
    e_ppc       db "PowerPC", 0
    e_ppc64     db "64-bit PowerPC", 0
    e_riscv     db "RISC-V", 0
    e_sh        db "SuperH", 0
    e_mach_q    db "unknown architecture", 0

    a_x8664     db "x86_64", 0
    a_arm64     db "arm64", 0
    a_i386      db "i386", 0
    a_arm       db "arm", 0
    a_ppc       db "ppc", 0
    a_unknown   db "unknown", 0
    a_sep       db ", ", 0

    stdin_name  db "-", 0
colon       db ": ", 0
    slash       db "/", 0
    dot         db ".", 0
    close_paren db ")", 0
usage_msg   db "Usage: file [-bhL] FILE...", 10
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
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
    je      .operand                    ;lone "-" means standard input
    lea     rsi, [rdi + 1]
.flag:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .next
    inc     rsi
    cmp     al, 'L'
    je      .follow
    cmp     al, 'h'
    je      .nofollow
    cmp     al, 'b'
    je      .brief
    jmp     .flag                       ;other flags do not change the answer
.follow:
    mov     byte [opt_follow], 1
    jmp     .flag
.nofollow:
    mov     byte [opt_follow], 0
    jmp     .flag
.brief:
    mov     byte [opt_brief], 1
    jmp     .flag
.operand:
    mov     rcx, [nnames]
    cmp     rcx, MAXNAMES
    jae     .next
    mov     [names + rcx * 8], rdi
    inc     rcx
    mov     [nnames], rcx
.next:
    add     r13, 8
    dec     r12
    jmp     parse

run:
    cmp     qword [nnames], 0
    je      usage
    xor     rbx, rbx
.loop:
    cmp     rbx, [nnames]
    jge     .done
    call    describe
    inc     rbx
    jmp     .loop
.done:
    movzx   edi, byte [status]
    mov     rax, SYS_EXIT
    syscall

usage:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR_FILENO
    mov     rsi, usage_msg
    mov     rdx, usage_len
    syscall
    exit    1

; ---------------------------------------------------------------------------
; describe: identify names[rbx] and print one line about it.
; ---------------------------------------------------------------------------
describe:
    push    rbx
    mov     qword [linelen], 0
    cmp     byte [opt_brief], 0
    jne     .body
    mov     rsi, [names + rbx * 8]
    call    app_str
    mov     rsi, colon
    call    app_str
.body:
    mov     rdi, [names + rbx * 8]
    cmp     byte [rdi], '-'
    jne     .named
    cmp     byte [rdi + 1], 0
    jne     .named
    call    from_stdin
    jmp     .emit
.named:
    call    from_path
.emit:
    call    flush_line
    pop     rbx
    ret

; from_stdin: standard input has no mode to look at, only content.
from_stdin:
    mov     qword [infd], STDIN_FILENO
    call    slurp
    cmp     qword [readlen], 0
    jne     identify_content
    mov     rsi, t_empty
    jmp     app_str

; ---------------------------------------------------------------------------
; from_path: stat the operand and let its mode decide, falling through to the
; content only for regular files.
; ---------------------------------------------------------------------------
from_path:
    mov     rax, SYS_LSTAT
    cmp     byte [opt_follow], 0
    je      .stat
    mov     rax, SYS_STAT
.stat:
    mov     rdi, [names + rbx * 8]
    mov     rsi, stbuf
    syscall
    test    rax, rax
    js      .cannot
    mov     eax, [stbuf + ST_MODE]
    and     eax, S_IFMT
    cmp     eax, S_IFDIR
    je      .directory
    cmp     eax, S_IFLNK
    je      .symlink
    cmp     eax, S_IFCHR
    je      .chardev
    cmp     eax, S_IFBLK
    je      .blockdev
    cmp     eax, S_IFIFO
    je      .fifo
    cmp     eax, S_IFSOCK
    je      .socket
    cmp     qword [stbuf + ST_SIZE], 0
    je      .empty
    call    open_operand
    test    al, al
    jz      .cannot
    call    slurp
    call    close_input
    cmp     qword [readlen], 0
    je      .empty
    jmp     identify_content
.directory:
    mov     rsi, t_directory
    jmp     app_str
.empty:
    mov     rsi, t_empty
    jmp     app_str
.fifo:
    mov     rsi, t_fifo
    jmp     app_str
.socket:
    mov     rsi, t_socket
    jmp     app_str
.chardev:
    mov     rsi, t_chr
    jmp     .devnum
.blockdev:
    mov     rsi, t_blk
.devnum:
    call    app_str
    mov     rax, [stbuf + ST_RDEV]
    mov     r8, rax
    shr     r8, 8
    and     r8, 0xFFF                   ;major
    mov     r9, rax
    and     r9, 0xFF
    mov     r10, rax
    shr     r10, 12
    and     r10, 0xFFF00
    or      r9, r10                     ;minor
    mov     rax, r8
    call    app_num
    mov     rsi, slash
    call    app_str
    mov     rax, r9
    call    app_num
    mov     rsi, close_paren
    jmp     app_str
.symlink:
    mov     rax, SYS_READLINK
    mov     rdi, [names + rbx * 8]
    mov     rsi, linkbuf
    mov     rdx, 4095
    syscall
    test    rax, rax
    js      .cannot
    mov     byte [linkbuf + rax], 0
    mov     rax, SYS_STAT               ;does the target actually resolve?
    mov     rdi, [names + rbx * 8]
    mov     rsi, stbuf
    syscall
    mov     rsi, t_symlink
    test    rax, rax
    jns     .linkname
    mov     rsi, t_broken
    mov     byte [status], 1
.linkname:
    call    app_str
    mov     rsi, linkbuf
    jmp     app_str
.cannot:
    mov     byte [status], 1
    mov     rsi, t_cannot
    jmp     app_str

open_operand:
    mov     rax, SYS_OPEN
    mov     rdi, [names + rbx * 8]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .fail
    mov     [infd], rax
    mov     al, 1
    ret
.fail:
    xor     al, al
    ret

close_input:
    mov     rax, SYS_CLOSE
    mov     rdi, [infd]
    syscall
    ret

; slurp: fill readbuf from infd, stopping at BUFCAP.
slurp:
    xor     r15, r15
.read:
    mov     rdx, BUFCAP
    sub     rdx, r15
    jz      .done
    mov     rax, SYS_READ
    mov     rdi, [infd]
    lea     rsi, [readbuf + r15]
    syscall
    test    rax, rax
    jle     .done
    add     r15, rax
    jmp     .read
.done:
    mov     [readlen], r15
    ret

; ---------------------------------------------------------------------------
; identify_content: walk the magic table, then fall back to the byte values.
; ---------------------------------------------------------------------------
identify_content:
    mov     rsi, m_elf
    mov     rcx, 4
    call    magic_at0
    test    al, al
    jnz     describe_elf
    mov     rsi, m_cafe
    mov     rcx, 4
    call    magic_at0
    test    al, al
    jnz     describe_cafebabe
    mov     rsi, m_gzip
    mov     rcx, 2
    call    magic_at0
    test    al, al
    jnz     .gzip
    mov     rsi, m_7z
    mov     rcx, 6
    call    magic_at0
    test    al, al
    jnz     describe_7z
    mov     rsi, m_zip
    mov     rcx, 4
    call    magic_at0
    test    al, al
    jnz     describe_zip
    mov     rsi, m_gif87
    mov     rcx, 6
    call    magic_at0
    test    al, al
    jnz     describe_gif
    mov     rsi, m_gif89
    mov     rcx, 6
    call    magic_at0
    test    al, al
    jnz     describe_gif
    mov     rsi, m_dex
    mov     rcx, 4
    call    magic_at0
    test    al, al
    jnz     describe_dex
    mov     rsi, m_ar
    mov     rcx, 8
    call    magic_at0
    test    al, al
    jnz     .ar
    mov     rsi, m_png
    mov     rcx, 8
    call    magic_at0
    test    al, al
    jnz     .png
    mov     rsi, m_jpeg
    mov     rcx, 3
    call    magic_at0
    test    al, al
    jnz     .jpeg
    mov     rsi, m_pdf
    mov     rcx, 5
    call    magic_at0
    test    al, al
    jnz     .pdf
    mov     rsi, m_cpio_nocrc
    mov     rcx, 6
    call    magic_at0
    test    al, al
    jnz     .cpio_nocrc
    mov     rsi, m_cpio_crc
    mov     rcx, 6
    call    magic_at0
    test    al, al
    jnz     .cpio_crc
    mov     rsi, m_cpio_odc
    mov     rcx, 6
    call    magic_at0
    test    al, al
    jnz     .cpio_odc
    call    check_bzip
    test    al, al
    jnz     describe_bzip
    call    check_tar
    test    al, al
    jnz     describe_tar
    call    check_shebang
    test    al, al
    jnz     describe_shebang
    jmp     classify_text
.gzip:
    mov     rsi, t_gzip
    jmp     app_str
.ar:
    mov     rsi, t_ar
    jmp     app_str
.png:
    mov     rsi, t_png
    jmp     app_str
.jpeg:
    mov     rsi, t_jpeg
    jmp     app_str
.pdf:
    mov     rsi, t_pdf
    jmp     app_str
.cpio_nocrc:
    mov     rsi, t_cpio_nocrc
    jmp     app_str
.cpio_crc:
    mov     rsi, t_cpio_crc
    jmp     app_str
.cpio_odc:
    mov     rsi, t_cpio_odc
    jmp     app_str

; magic_at0: do the first rcx bytes of readbuf equal the rcx bytes at rsi?
magic_at0:
    cmp     [readlen], rcx
    jb      .no
    xor     r8, r8
.scan:
    cmp     r8, rcx
    jae     .yes
    mov     al, [rsi + r8]
    cmp     al, [readbuf + r8]
    jne     .no
    inc     r8
    jmp     .scan
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

check_bzip:
    cmp     qword [readlen], 4
    jb      .no
    cmp     byte [readbuf], 'B'
    jne     .no
    cmp     byte [readbuf + 1], 'Z'
    jne     .no
    cmp     byte [readbuf + 2], 'h'
    jne     .no
    movzx   eax, byte [readbuf + 3]
    cmp     al, '1'
    jb      .no
    cmp     al, '9'
    ja      .no
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

describe_bzip:
    mov     rsi, t_bzip
    call    app_str
    movzx   eax, byte [readbuf + 3]
    sub     al, '0'
    call    app_num
    mov     rsi, t_bzip_k
    jmp     app_str

; check_tar: "ustar" sits 257 bytes into the first header block.
check_tar:
    mov     rax, TAR_MAGIC_OFF + 5
    cmp     [readlen], rax
    jb      .no
    xor     r8, r8
.scan:
    cmp     r8, 5
    jae     .yes
    mov     al, [m_ustar + r8]
    cmp     al, [readbuf + TAR_MAGIC_OFF + r8]
    jne     .no
    inc     r8
    jmp     .scan
.yes:
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

describe_tar:
; GNU writes "ustar  \0" where POSIX writes "ustar\000"
    cmp     byte [readbuf + TAR_MAGIC_OFF + 5], WHITESPACE_SPACE
    jne     .posix
    mov     rsi, t_tar_gnu
    jmp     app_str
.posix:
    mov     rsi, t_tar
    jmp     app_str

check_shebang:
    cmp     qword [readlen], 3
    jb      .no
    cmp     byte [readbuf], '#'
    jne     .no
    cmp     byte [readbuf + 1], '!'
    jne     .no
    mov     al, 1
    ret
.no:
    xor     al, al
    ret

describe_shebang:
    mov     rsi, t_script_a
    call    app_str
    mov     rcx, 2
.skip:
    cmp     rcx, [readlen]
    jae     .tail
    movzx   eax, byte [readbuf + rcx]
    cmp     al, WHITESPACE_SPACE
    je      .advance
    cmp     al, WHITESPACE_TAB
    jne     .word
.advance:
    inc     rcx
    jmp     .skip
.word:
    mov     r8, rcx                     ;start of the interpreter line
    mov     r9, rcx
.end:
    cmp     r9, [readlen]
    jae     .have
    movzx   eax, byte [readbuf + r9]
    cmp     al, WHITESPACE_NL
    je      .have
    cmp     al, 13
    je      .have
    inc     r9
    jmp     .end
.have:
    mov     rcx, r9
    sub     rcx, r8
    cmp     rcx, 128
    jbe     .emit
    mov     rcx, 128
.emit:
    lea     rsi, [readbuf + r8]
    call    app_bytes
.tail:
    mov     rsi, t_script_b
    jmp     app_str

; ---------------------------------------------------------------------------
; describe_cafebabe: a Java class and a Mach-O universal binary share this
; magic. The word after it is a class version for one and an architecture
; count for the other, and no fat binary carries thirty of them.
; ---------------------------------------------------------------------------
describe_cafebabe:
    cmp     qword [readlen], 8
    jb      classify_text
    mov     rcx, 4
    call    read_be32
    cmp     rax, 30
    jae     describe_java
; Mach-O: magic, count, then twenty bytes per architecture
    mov     r14, rax                    ;architectures
    mov     rsi, t_macho
    call    app_str
    mov     rax, r14
    call    app_num
    mov     rsi, t_arches
    call    app_str
    xor     r15, r15
.arch:
    cmp     r15, r14
    jge     .out
    test    r15, r15
    jz      .name
    mov     rsi, a_sep
    call    app_str
.name:
    mov     rcx, r15
    imul    rcx, rcx, 20
    add     rcx, 8
    mov     rax, rcx
    add     rax, 4
    cmp     [readlen], rax
    jb      .out
    call    read_be32
    call    macho_arch
    call    app_str
    inc     r15
    jmp     .arch
.out:
    ret

; macho_arch: name the Mach-O cpu type in rax.
macho_arch:
    cmp     rax, 0x01000007
    je      .x8664
    cmp     rax, 0x0100000C
    je      .arm64
    cmp     rax, 7
    je      .i386
    cmp     rax, 12
    je      .arm
    cmp     rax, 18
    je      .ppc
    mov     rsi, a_unknown
    ret
.x8664:
    mov     rsi, a_x8664
    ret
.arm64:
    mov     rsi, a_arm64
    ret
.i386:
    mov     rsi, a_i386
    ret
.arm:
    mov     rsi, a_arm
    ret
.ppc:
    mov     rsi, a_ppc
    ret

describe_java:
    mov     rsi, t_java
    call    app_str
    mov     rcx, 6
    call    read_be16                   ;major
    call    app_num
    mov     rsi, dot
    call    app_str
    mov     rcx, 4
    call    read_be16                   ;minor
    jmp     app_num

describe_7z:
    cmp     qword [readlen], 8
    jb      classify_text
    mov     rsi, t_7z
    call    app_str
    movzx   eax, byte [readbuf + 6]
    call    app_num
    mov     rsi, dot
    call    app_str
    movzx   eax, byte [readbuf + 7]
    jmp     app_num

describe_zip:
    cmp     qword [readlen], 6
    jb      classify_text
    mov     rsi, t_zip
    call    app_str
    mov     rcx, 4
    call    read_le16
    mov     r8, rax
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    mov     r9, rdx                     ;tenths
    call    app_num
    mov     rsi, dot
    call    app_str
    mov     rax, r9
    call    app_num
    mov     rsi, t_zip_tail
    jmp     app_str

describe_gif:
    cmp     qword [readlen], 10
    jb      classify_text
    mov     rsi, t_gif
    call    app_str
    lea     rsi, [readbuf + 3]
    mov     rcx, 3
    call    app_bytes
    mov     rsi, a_sep
    call    app_str
    mov     rcx, 6
    call    read_le16
    call    app_num
    mov     rsi, x_sep
    call    app_str
    mov     rcx, 8
    call    read_le16
    jmp     app_num

describe_dex:
    cmp     qword [readlen], 8
    jb      classify_text
    mov     rsi, t_dex
    call    app_str
    lea     rsi, [readbuf + 4]
    mov     rcx, 3
    jmp     app_bytes

; ---------------------------------------------------------------------------
; describe_elf: class and byte order come out of e_ident, and everything past
; them is read in whichever order that says.
; ---------------------------------------------------------------------------
describe_elf:
    cmp     qword [readlen], 20
    jb      .bad
    movzx   eax, byte [readbuf + 4]
    cmp     al, 1
    je      .class32
    cmp     al, 2
    je      .class64
    jmp     .bad
.class32:
    mov     r14, e_32
    jmp     .data
.class64:
    mov     r14, e_64
.data:
    movzx   eax, byte [readbuf + 5]
    cmp     al, 1
    je      .little
    cmp     al, 2
    je      .big
    jmp     .bad
.little:
    mov     r15, 1
    mov     r13, e_lsb
    jmp     .emit
.big:
    mov     r15, 2
    mov     r13, e_msb
.emit:
    mov     rsi, t_elf
    call    app_str
    mov     rsi, r14
    call    app_str
    mov     rsi, r13
    call    app_str
    mov     rcx, 16
    call    read_endian16
    call    elf_type
    call    app_str
    mov     rsi, e_comma
    call    app_str
    mov     rcx, 18
    call    read_endian16
    call    elf_machine
    jmp     app_str
.bad:
    mov     rsi, t_elf_bad
    jmp     app_str

; read_endian16: the halfword at rcx, in the byte order r15 selects.
read_endian16:
    cmp     r15, 2
    je      read_be16
    jmp     read_le16

elf_type:
    cmp     rax, 0
    je      .none
    cmp     rax, 1
    je      .rel
    cmp     rax, 2
    je      .exec
    cmp     rax, 3
    je      .dyn
    cmp     rax, 4
    je      .core
    mov     rsi, e_type_q
    ret
.none:
    mov     rsi, e_none
    ret
.rel:
    mov     rsi, e_rel
    ret
.exec:
    mov     rsi, e_exec
    ret
.dyn:
    mov     rsi, e_dyn
    ret
.core:
    mov     rsi, e_core
    ret

elf_machine:
    cmp     rax, 3
    je      .i386
    cmp     rax, 8
    je      .mips
    cmp     rax, 20
    je      .ppc
    cmp     rax, 21
    je      .ppc64
    cmp     rax, 40
    je      .arm
    cmp     rax, 42
    je      .sh
    cmp     rax, 62
    je      .x8664
    cmp     rax, 183
    je      .aarch64
    cmp     rax, 243
    je      .riscv
    mov     rsi, e_mach_q
    ret
.i386:
    mov     rsi, e_386
    ret
.mips:
    mov     rsi, e_mips
    ret
.ppc:
    mov     rsi, e_ppc
    ret
.ppc64:
    mov     rsi, e_ppc64
    ret
.arm:
    mov     rsi, e_arm
    ret
.sh:
    mov     rsi, e_sh
    ret
.x8664:
    mov     rsi, e_x8664
    ret
.aarch64:
    mov     rsi, e_aarch64
    ret
.riscv:
    mov     rsi, e_riscv
    ret

; ---------------------------------------------------------------------------
; classify_text: printable throughout is ASCII, a clean multibyte decode is
; UTF-8, anything else is data. A sequence cut off by the end of the buffer is
; not held against the file.
; ---------------------------------------------------------------------------
classify_text:
    xor     r8, r8                      ;offset
    xor     r9, r9                      ;saw a multibyte character
.byte:
    cmp     r8, [readlen]
    jae     .text
    movzx   eax, byte [readbuf + r8]
    cmp     al, 0x80
    jae     .multibyte
    cmp     al, 7
    jb      .data
    cmp     al, 13
    jbe     .plain
    cmp     al, 27
    je      .plain
    cmp     al, WHITESPACE_SPACE
    jb      .data
    cmp     al, 126
    ja      .data
.plain:
    inc     r8
    jmp     .byte
.multibyte:
    mov     r9, 1
    mov     r10, rax
    and     r10, 0xE0
    cmp     r10, 0xC0
    je      .len2
    mov     r10, rax
    and     r10, 0xF0
    cmp     r10, 0xE0
    je      .len3
    mov     r10, rax
    and     r10, 0xF8
    cmp     r10, 0xF0
    je      .len4
    jmp     .data
.len2:
    mov     r11, 2
    jmp     .check
.len3:
    mov     r11, 3
    jmp     .check
.len4:
    mov     r11, 4
.check:
    mov     rax, r8
    add     rax, r11
    cmp     rax, [readlen]
    ja      .text                       ;truncated by the buffer, not corrupt
    mov     rcx, 1
.cont:
    cmp     rcx, r11
    jae     .advance
    mov     rax, r8
    add     rax, rcx
    movzx   edx, byte [readbuf + rax]
    and     dl, 0xC0
    cmp     dl, 0x80
    jne     .data
    inc     rcx
    jmp     .cont
.advance:
    add     r8, r11
    jmp     .byte
.text:
    test    r9, r9
    jnz     .utf8
    mov     rsi, t_ascii
    jmp     app_str
.utf8:
    mov     rsi, t_utf8
    jmp     app_str
.data:
    mov     rsi, t_data
    jmp     app_str

; ---------------------------------------------------------------------------
; Byte readers and the line buffer.
; ---------------------------------------------------------------------------
read_be16:
    movzx   eax, byte [readbuf + rcx]
    shl     rax, 8
    movzx   edx, byte [readbuf + rcx + 1]
    or      rax, rdx
    ret

read_le16:
    movzx   eax, byte [readbuf + rcx + 1]
    shl     rax, 8
    movzx   edx, byte [readbuf + rcx]
    or      rax, rdx
    ret

read_be32:
    xor     rax, rax
    movzx   edx, byte [readbuf + rcx]
    shl     rdx, 24
    or      rax, rdx
    movzx   edx, byte [readbuf + rcx + 1]
    shl     rdx, 16
    or      rax, rdx
    movzx   edx, byte [readbuf + rcx + 2]
    shl     rdx, 8
    or      rax, rdx
    movzx   edx, byte [readbuf + rcx + 3]
    or      rax, rdx
    ret

; app_str: append the NUL-terminated string at rsi to the line.
app_str:
    mov     rcx, [linelen]
.copy:
    mov     al, [rsi]
    test    al, al
    jz      .out
    cmp     rcx, LINECAP - 2
    jae     .out
    mov     [linebuf + rcx], al
    inc     rcx
    inc     rsi
    jmp     .copy
.out:
    mov     [linelen], rcx
    ret

; app_bytes: append rcx bytes at rsi to the line.
app_bytes:
    mov     r8, [linelen]
    xor     r9, r9
.copy:
    cmp     r9, rcx
    jae     .out
    cmp     r8, LINECAP - 2
    jae     .out
    mov     al, [rsi + r9]
    mov     [linebuf + r8], al
    inc     r8
    inc     r9
    jmp     .copy
.out:
    mov     [linelen], r8
    ret

; app_num: append rax as an unsigned decimal.
app_num:
    push    rbx
    mov     rcx, 10
    xor     r8, r8
.split:
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    push    rdx
    inc     r8
    test    rax, rax
    jnz     .split
    mov     rbx, [linelen]
.emit:
    pop     rdx
    cmp     rbx, LINECAP - 2
    jae     .skip
    mov     [linebuf + rbx], dl
    inc     rbx
.skip:
    dec     r8
    jnz     .emit
    mov     [linelen], rbx
    pop     rbx
    ret

flush_line:
    mov     rcx, [linelen]
    mov     byte [linebuf + rcx], WHITESPACE_NL
    inc     rcx
    mov     rdx, rcx
    mov     rsi, linebuf
.write:
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    syscall
    test    rax, rax
    jle     .out
    add     rsi, rax
    sub     rdx, rax
    jnz     .write
.out:
    mov     qword [linelen], 0
    ret

section .data
    x_sep       db " x ", 0

section .bss
    infd        resq 1
