; src/gencat.asm

    %include "include/sysdefs.inc"

    %define BUFFER_SIZE 4096

section .bss
    buffer      resb BUFFER_SIZE

section .data
usage_msg   db "Usage: gencat CATFILE [FILES...]", 10
    usage_len   equ $ - usage_msg

section .text
global _start

_start:
    pop     rcx                         ;argc
    mov     rbx, rsp                    ;argv pointer
    cmp     rcx, 2
    jl      .usage

; open catalog output file
    mov     rsi, [rbx + 8]              ;argv[1]
    mov     rdi, STDOUT_FILENO
    call    open_dest_file
    mov     r9, rax                     ;dest fd

    cmp     rcx, 2
    jg      .have_sources
    mov     r8, STDIN_FILENO            ;no input files
    call    copy_fd
    jmp     .close_and_exit

.have_sources:
    mov     r12, rcx
    sub     r12, 2                      ;number of source files
    add     rbx, 16                     ;point to argv[2]

.next_file:
    mov     rsi, [rbx]
    mov     rdi, STDIN_FILENO
    call    open_file
    mov     r8, rax
    push    rbx
    push    r12
    call    copy_fd
    pop     r12
    pop     rbx
    mov     rax, SYS_CLOSE
    mov     rdi, r8
    syscall
    add     rbx, 8
    dec     r12
    jnz     .next_file

.close_and_exit:
    cmp     r9, STDOUT_FILENO
    je      .exit_success
    mov     rax, SYS_CLOSE
    mov     rdi, r9
    syscall
.exit_success:
    exit    0

.usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

; copy from r8 to r9 using buffer
copy_fd:
.read_loop:
    mov     rax, SYS_READ
    mov     rdi, r8
    mov     rsi, buffer
    mov     rdx, BUFFER_SIZE
    syscall
    cmp     rax, 0
    jl      .read_error
    je      .done
    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, r9
    mov     rsi, buffer
    syscall
    cmp     rax, 0
    jl      .write_error
    jmp     .read_loop
.done:
    ret
.read_error:
    write   STDERR_FILENO, error_msg_read, error_msg_read_len
    exit    1
.write_error:
    write   STDERR_FILENO, error_msg_write, error_msg_write_len
    exit    1
