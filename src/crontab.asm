; src/crontab.asm
    %include "include/sysdefs.inc"
    %define ARG_PTR_SIZE 8
    %define BUF_SIZE 4096
section .bss
    path_buf    resb 4096
    buffer      resb BUF_SIZE

section .data
    home_key     db "HOME", 0
    spool_suffix db "/.baloo_crontab", 0
usage_msg    db "Usage: crontab [-l|-r|FILE|-]", WHITESPACE_NL
    usage_len    equ $ - usage_msg

section .text
global _start

_start:
    pop     rcx                         ;argc
    mov     rbp, rsp
    lea     r12, [rbp + rcx*8 + 8]      ;envp pointer
    call    build_path

    cmp     rcx, 1
    jg      parse_arg

; no arguments -> install from stdin
    jmp     install_stdin

parse_arg:
    add     rbp, ARG_PTR_SIZE           ;skip argv[0]
    mov     rsi, [rbp]                  ;first arg
    dec     rcx
    cmp     byte [rsi], '-'
    jne     file_install
    cmp     byte [rsi+1], 'l'
    je      cmd_list
    cmp     byte [rsi+1], 'r'
    je      cmd_remove
    cmp     byte [rsi+1], 0
    je      install_stdin
    jmp     usage

file_install:
    mov     rdi, STDIN_FILENO
    call    open_file
    mov     r13, rax
    jmp     install_dest

install_stdin:
    mov     rdi, STDIN_FILENO
    xor     rsi, rsi
    call    open_file
    mov     r13, rax

install_dest:
    mov     rdi, STDOUT_FILENO
    mov     rsi, path_buf
    call    open_dest_file
    mov     r14, rax

.copy_loop:
    mov     rax, SYS_READ
    mov     rdi, r13
    mov     rsi, buffer
    mov     rdx, BUF_SIZE
    syscall
    cmp     rax, 0
    jle     .copy_done
    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, r14
    mov     rsi, buffer
    syscall
    jmp     .copy_loop

.copy_done:
    cmp     r13, STDIN_FILENO
    je      .close_dest
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
.close_dest:
    cmp     r14, STDOUT_FILENO
    je      exit_success
    mov     rax, SYS_CLOSE
    mov     rdi, r14
    syscall
    jmp     exit_success

cmd_list:
    mov     rdi, STDIN_FILENO
    mov     rsi, path_buf
    call    open_file
    mov     r13, rax

.list_loop:
    mov     rax, SYS_READ
    mov     rdi, r13
    mov     rsi, buffer
    mov     rdx, BUF_SIZE
    syscall
    cmp     rax, 0
    jle     .list_done
    mov     rdx, rax
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT_FILENO
    mov     rsi, buffer
    syscall
    jmp     .list_loop

.list_done:
    cmp     r13, STDIN_FILENO
    je      exit_success
    mov     rax, SYS_CLOSE
    mov     rdi, r13
    syscall
    jmp     exit_success

cmd_remove:
    mov     rax, SYS_UNLINK
    mov     rdi, path_buf
    syscall
    jmp     exit_success

usage:
    write   STDERR_FILENO, usage_msg, usage_len
    exit    1

exit_success:
    exit    0

; -- Helpers ------------------------------------------------------------

build_path:
    push    rbx
    push    rdi
    push    rsi
    mov     rbx, r12
.find_loop:
    mov     rdi, [rbx]
    test    rdi, rdi
    jz      .no_home
    mov     rsi, home_key
    call    check_prefix
    test    rax, rax
    jnz     .found
    add     rbx, 8
    jmp     .find_loop
.found:
    mov     rsi, rdi
    add     rsi, 5
    mov     rdi, path_buf
    call    copy_string
    jmp     .append_suffix
.no_home:
    mov     rdi, path_buf
    mov     byte [rdi], '/'
    mov     byte [rdi+1], 0
.append_suffix:
    mov     rsi, path_buf
    call    strlen                      ;length -> rbx
    mov     rdi, path_buf
    add     rdi, rbx
    mov     rsi, spool_suffix
    call    copy_string
    pop     rsi
    pop     rdi
    pop     rbx
    ret

; rdi = string, rsi = prefix
; returns rax = 1 if string starts with prefix followed by '='
check_prefix:
    push    rcx
    xor     rcx, rcx
.prefix_loop:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .match
    cmp     al, [rdi + rcx]
    jne     .no_match
    inc     rcx
    jmp     .prefix_loop
.match:
    cmp     byte [rdi + rcx], '='
    jne     .no_match
    mov     rax, 1
    jmp     .done
.no_match:
    xor     rax, rax
.done:
    pop     rcx
    ret

; rdi = dest, rsi = src
copy_string:
    push    rcx
    xor     rcx, rcx
.copy_loop_str:
    mov     al, [rsi + rcx]
    mov     [rdi + rcx], al
    test    al, al
    jz      .copy_done
    inc     rcx
    jmp     .copy_loop_str
.copy_done:
    pop     rcx
    ret
