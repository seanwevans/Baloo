; src/cd.asm

    %include "include/sysdefs.inc"

section .bss
    buffer      resb 4096               ;General purpose buffer
    path_buffer resb 4096               ;Buffer for directory path

section .data
    home_env    db "HOME", 0            ;HOME environment variable name
err_msg     db "cd: error: ", 0     ; Error message prefix
    err_msg_len equ $ - err_msg
usage_msg   db "Usage: cd [directory]", 10 ; Usage message
    usage_msg_len equ $ - usage_msg

section .text
global      _start

_start:
    pop         rdi                     ;argc
    cmp         rdi, 1                  ;If argc == 1
    je          change_to_home          ;If no args, go to home directory
    cmp         rdi, 2                  ;If argc == 2 (program name + directory)
    je          change_to_arg           ;If one arg, go to specified directory
    jmp         show_usage              ;If too many args, show usage

change_to_arg:
    pop         rdi
    pop         rdi
    jmp         do_chdir                ;Change to directory

change_to_home:
    mov         rax, SYS_MMAP           ;mmap syscall
    mov         rdi, 0                  ;let kernel choose address
    mov         rsi, 4096               ;Length of mapping
    mov         rdx, 3                  ;PROT_READ | PROT_WRITE
    mov         r10, 34                 ;MAP_PRIVATE | MAP_ANONYMOUS
    mov         r8, -1
    mov         r9, 0
    syscall

    mov         rdi, rax                ;Save mmap address for later use
    mov         rsi, home_env           ;"HOME" string

    mov         r12, [rsp+8]            ;Get environ pointer (after argc and argv)

find_home_loop:
    mov         r13, [r12]              ;Get current environment string
    test        r13, r13                ;If NULL, end of environ
    jz          home_not_found

    mov         rsi, home_env           ;"HOME" string
    mov         rdi, r13                ;Current env var
    call        check_prefix
    test        rax, rax                ;If rax != 0, it's HOME
    jnz         found_home

    add         r12, 8                  ;Move to next environ entry
    jmp         find_home_loop

found_home:
    mov         rsi, r13                ;HOME env var string
    mov         rdi, path_buffer        ;Destination buffer
    add         rsi, 5                  ;Skip "HOME="
    call        copy_string

    mov         rdi, path_buffer        ;Set directory to HOME value
    jmp         do_chdir

home_not_found:
    mov         rdi, path_buffer
    mov         byte [rdi], '/'         ;Default to root if HOME not found
    mov         byte [rdi+1], 0
    mov         rdi, path_buffer
    jmp         do_chdir

do_chdir:
    mov         rax, SYS_CHDIR
    syscall

    test        rax, rax
    js          chdir_error

    exit        0

chdir_error:
    write       STDERR_FILENO, err_msg, err_msg_len

    mov         rsi, rdi                ;Directory path is still in rdi
    mov         rdi, buffer             ;Use buffer for building error message
    call        copy_string             ;Copy path to buffer
    mov         rdx, 0                  ;Initialize length counter

show_usage:
    write       STDERR_FILENO, usage_msg, usage_msg_len
    exit        1

check_prefix:
    push        rcx
    push        rdi
    push        rsi
    xor         rcx, rcx                ;Counter

check_prefix_loop:
    mov         al, [rsi + rcx]         ;Get prefix character
    test        al, al                  ;If end of prefix, success
    jz          check_prefix_match

    cmp         al, [rdi + rcx]         ;Compare with string
    jne         check_prefix_no_match

    inc         rcx                     ;Move to next character
    jmp         check_prefix_loop

check_prefix_match:
    cmp         byte [rdi + rcx], '='
    jne         check_prefix_no_match

    mov         rax, 1                  ;match
    jmp         check_prefix_done

check_prefix_no_match:
    xor         rax, rax                ;no match

check_prefix_done:
    pop         rsi
    pop         rdi
    pop         rcx
    ret

copy_string:
    push        rcx
    push        rdi
    push        rsi
    xor         rcx, rcx                ;Initialize counter

copy_loop:
    mov         al, [rsi + rcx]         ;Get character from source
    mov         [rdi + rcx], al         ;Copy to destination
    test        al, al                  ;Check for null terminator
    jz          copy_done
    inc         rcx                     ;Move to next character
    jmp         copy_loop

copy_done:
    pop         rsi
    pop         rdi
    pop         rcx
    ret
