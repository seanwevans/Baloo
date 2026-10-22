; include/slurp.inc -- read a whole descriptor into memory that grows as needed.
;
; For utilities that must see all of their input before producing output
; (sort, tac, tail). The buffer is an anonymous mapping that doubles with
; mremap(MREMAP_MAYMOVE), so input size is bounded only by memory instead of
; a fixed .bss array. Running out of memory is reported and exits 1 rather
; than silently truncating.
;
;   slurp         rdi = fd. Reset the buffer, read fd to EOF.
;   slurp_append  rdi = fd. Read fd to EOF after what is already buffered.
;                 Both return rax = buffer address, rdx = total length, and
;                 leave [slurp_ptr]/[slurp_len] set. The address can change on
;                 every call, so never keep pointers into the buffer across one.
;                 At least one spare byte always follows the data (so callers
;                 may NUL-terminate). [slurp_err] holds the negative errno of a
;                 failed read (0 when every read succeeded).
;   xalloc        rdi = byte count. Zeroed anonymous memory in rax; exits 1 on
;                 failure.
;
; Clobbers rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11. Preserves rbx, rbp, r12-r15.

    %define SYS_MREMAP      25
    %define SLURP_PROT      3           ;PROT_READ | PROT_WRITE
    %define SLURP_MAP       0x22        ;MAP_PRIVATE | MAP_ANONYMOUS
    %define SLURP_MAYMOVE   1           ;MREMAP_MAYMOVE
%define SLURP_INIT      (1 << 20)   ;first mapping: 1 MiB

section .bss
    slurp_ptr   resq 1
    slurp_cap   resq 1
    slurp_len   resq 1
    slurp_fd    resq 1
    slurp_err   resq 1

section .data
    slurp_nomem db "out of memory", WHITESPACE_NL
    slurp_nomem_len equ $ - slurp_nomem

section .text

slurp:
    mov     qword [slurp_len], 0
slurp_append:
    mov     [slurp_fd], rdi
    mov     qword [slurp_err], 0
    cmp     qword [slurp_ptr], 0
    jne     .read
    mov     rdi, SLURP_INIT
    call    xalloc
    mov     [slurp_ptr], rax
    mov     qword [slurp_cap], SLURP_INIT
.read:
    mov     rdx, [slurp_cap]
    sub     rdx, [slurp_len]
    jnz     .doread
mov     rax, SYS_MREMAP             ;full: double the mapping
    mov     rdi, [slurp_ptr]
    mov     rsi, [slurp_cap]
    lea     rdx, [rsi * 2]
    mov     r10, SLURP_MAYMOVE
    syscall
    cmp     rax, -4095
    jae     slurp_oom
    mov     [slurp_ptr], rax
    shl     qword [slurp_cap], 1
    jmp     .read
.doread:
    mov     rax, SYS_READ
    mov     rdi, [slurp_fd]
    mov     rsi, [slurp_ptr]
    add     rsi, [slurp_len]
    syscall
    test    rax, rax
    jz      .done                       ;EOF
    js      .err
    add     [slurp_len], rax
    jmp     .read
.err:
    mov     [slurp_err], rax
.done:
    mov     rax, [slurp_ptr]
    mov     rdx, [slurp_len]
    ret

xalloc:
    mov     rsi, rdi
    test    rsi, rsi
    jnz     .map
    mov     rsi, 8                      ;mmap rejects a zero length
.map:
    mov     rax, SYS_MMAP
    xor     rdi, rdi
    mov     rdx, SLURP_PROT
    mov     r10, SLURP_MAP
    mov     r8, -1
    xor     r9, r9
    syscall
    cmp     rax, -4095
    jae     slurp_oom
    ret

slurp_oom:
    write   STDERR_FILENO, slurp_nomem, slurp_nomem_len
    exit    1
