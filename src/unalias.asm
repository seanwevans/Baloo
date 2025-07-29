; src/unalias.asm

%include "include/sysdefs.inc"

section .data
    alias_path  db "/tmp/alias.txt", 0
    temp_path   db "/tmp/alias.tmp", 0
    newline     db 10

section .bss
    buffer      resb 1
    line_buf    resb 1024
    arg_ptrs    resq 32

section .text
    global _start

_start:
    pop     rax                 ; argc
    pop     rbx                 ; skip argv[0]
    dec     rax                 ; arg count
    cmp     rax, 1
    jl      usage_error
    mov     r12, rax            ; number of names
    mov     r13, rsp            ; pointer to arg list

    ; store argument pointers
    xor     rcx, rcx
.store_args:
    cmp     rcx, r12
    je      open_files
    mov     rdx, [r13 + rcx*8]
    mov     [arg_ptrs + rcx*8], rdx
    inc     rcx
    jmp     .store_args

open_files:
    ; open original file for reading
    mov     rax, SYS_OPEN
    mov     rdi, alias_path
    mov     rsi, O_RDONLY
    mov     rdx, 0
    syscall
    cmp     rax, 0
    jl      error_exit
    mov     r14, rax            ; input fd

    ; open temporary file for writing
    mov     rax, SYS_OPEN
    mov     rdi, temp_path
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, DEFAULT_MODE
    syscall
    cmp     rax, 0
    jl      close_in_error
    mov     r15, rax            ; output fd

    xor     rbx, rbx            ; line length
read_loop:
    mov     rax, SYS_READ
    mov     rdi, r14
    mov     rsi, buffer
    mov     rdx, 1
    syscall
    cmp     rax, 0
    je      process_last
    cmp     rax, 0
    jl      close_all_error

    mov     al, [buffer]
    mov     [line_buf + rbx], al
    inc     rbx
    cmp     al, 10
    jne     read_loop

    mov     rdi, rbx            ; length
    call    process_line
    xor     rbx, rbx
    jmp     read_loop

process_last:
    cmp     rbx, 0
    je      finish
    mov     rdi, rbx
    call    process_line

finish:
    ; close files
    mov     rax, SYS_CLOSE
    mov     rdi, r14
    syscall
    mov     rax, SYS_CLOSE
    mov     rdi, r15
    syscall
    ; rename temp file
    mov     rax, SYS_RENAME
    mov     rdi, temp_path
    mov     rsi, alias_path
    syscall
    cmp     rax, 0
    jl      error_exit
    exit    0

usage_error:
    exit    1

error_exit:
    exit    1

close_in_error:
    mov     rax, SYS_CLOSE
    mov     rdi, r14
    syscall
    jmp     error_exit

close_all_error:
    mov     rax, SYS_CLOSE
    mov     rdi, r14
    syscall
    mov     rax, SYS_CLOSE
    mov     rdi, r15
    syscall
    jmp     error_exit

; rdi = line length
process_line:
    push    rdi
    mov     rdx, rdi
    mov     byte [line_buf + rdx], 0
    mov     rsi, line_buf
    call    should_delete
    cmp     rax, 1
    je      .skip
    pop     rax
    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, r15
    mov     rsi, line_buf
    syscall
    ret
.skip:
    pop     rax
    ret

; rsi = line_buf (null terminated)
should_delete:
    xor     rcx, rcx
.arg_loop:
    cmp     rcx, r12
    je      .no_match
    mov     rdi, [arg_ptrs + rcx*8]
    push    rcx
    call    compare_name
    pop     rcx
    cmp     rax, 1
    je      .match
    inc     rcx
    jmp     .arg_loop
.match:
    mov     rax, 1
    ret
.no_match:
    xor     rax, rax
    ret

; rsi = line_buf, rdi = arg pointer
compare_name:
    push    rbx
    xor     rbx, rbx
.cmp_loop:
    mov     al, [rsi + rbx]
    cmp     al, '='
    je      .end_line
    cmp     al, 0
    je      .end_line
    mov     dl, [rdi + rbx]
    cmp     dl, al
    jne     .no
    cmp     dl, 0
    je      .no
    inc     rbx
    jmp     .cmp_loop
.end_line:
    cmp     byte [rdi + rbx], 0
    jne     .no
    mov     rax, 1
    jmp     .done
.no:
    xor     rax, rax
.done:
    pop     rbx
    ret
