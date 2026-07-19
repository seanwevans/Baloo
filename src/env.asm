; src/env.asm -- env(1): run a program in a modified environment, or print
; the environment. Supports -i (empty env), -u NAME (unset), -0 (NUL output),
; VAR=VALUE assignments, "--" and "-".

    %include "include/sysdefs.inc"

section .bss
    new_envp    resq 8192               ;built environment pointer array
    u_names     resq 1024               ;names given to -u
    assign_ptrs resq 1024               ;VAR=VALUE argument pointers
    u_count     resq 1
    assign_count resq 1
    i_flag      resb 1
    zero_flag   resb 1
    cmd_index   resq 1

section .data
exec_fail_msg db "env: exec failed", 10
    exec_fail_len equ $ - exec_fail_msg
badopt_msg    db "env: invalid option", 10
    badopt_len    equ $ - badopt_msg
    newline       db WHITESPACE_NL
    nulbyte       db 0

section .text
global _start

_start:
    mov     byte [i_flag], 0
    mov     byte [zero_flag], 0
    mov     qword [u_count], 0
    mov     qword [assign_count], 0
    mov     qword [cmd_index], -1

    mov     r14, [rsp]                  ;argc
    lea     r15, [rsp + 8]              ;&argv[0]
    lea     rbp, [rsp + 8 + r14*8 + 8]  ;envp (after argv's NULL)

    mov     rbx, 1                      ;argument index
.opt:
    cmp     rbx, r14
    jge     after_opts
    mov     rdi, [r15 + rbx*8]
    cmp     byte [rdi], '-'
    jne     after_opts
    cmp     byte [rdi + 1], 0
    je      .dash                       ;"-" means ignore environment
    cmp     byte [rdi + 1], '-'
    je      .longopt
    inc     rdi
.short:
    movzx   eax, byte [rdi]
    test    al, al
    je      .opt_next
    cmp     al, 'i'
    je      .set_i
    cmp     al, '0'
    je      .set_0
    cmp     al, 'u'
    je      .set_u
    jmp     bad_option
.set_i:
    mov     byte [i_flag], 1
    inc     rdi
    jmp     .short
.set_0:
    mov     byte [zero_flag], 1
    inc     rdi
    jmp     .short
.set_u:
    inc     rdi
    cmp     byte [rdi], 0               ;-uNAME or -u NAME
    jne     .u_have
    inc     rbx
    cmp     rbx, r14
    jge     bad_option
    mov     rdi, [r15 + rbx*8]
.u_have:
    mov     rcx, [u_count]
    mov     [u_names + rcx*8], rdi
    inc     rcx
    mov     [u_count], rcx
    jmp     .opt_next                   ;-u consumes the rest of the argument
.dash:
    mov     byte [i_flag], 1
    jmp     .opt_next
.longopt:
    cmp     byte [rdi + 2], 0           ;"--" ends option processing
    jne     bad_option
    inc     rbx
    jmp     after_opts
.opt_next:
    inc     rbx
    jmp     .opt

after_opts:
.assign:
    cmp     rbx, r14
    jge     build_env
    mov     rdi, [r15 + rbx*8]
    call    has_eq
    test    rax, rax
    jz      .command
    mov     rcx, [assign_count]
    mov     [assign_ptrs + rcx*8], rdi
    inc     rcx
    mov     [assign_count], rcx
    inc     rbx
    jmp     .assign
.command:
    mov     [cmd_index], rbx

build_env:
    xor     r12, r12                    ;new environment length
    cmp     byte [i_flag], 1
    je      .add_assigns
    mov     rbx, rbp                    ;walk the inherited environment
.copy:
    mov     rdi, [rbx]
    test    rdi, rdi
    je      .add_assigns
    call    name_in_removal
    test    rax, rax
    jnz     .copy_next
    mov     [new_envp + r12*8], rdi
    inc     r12
.copy_next:
    add     rbx, 8
    jmp     .copy
.add_assigns:
    xor     rcx, rcx
.aloop:
    cmp     rcx, [assign_count]
    jge     .term
    mov     rdi, [assign_ptrs + rcx*8]
    mov     [new_envp + r12*8], rdi
    inc     r12
    inc     rcx
    jmp     .aloop
.term:
    mov     qword [new_envp + r12*8], 0

    cmp     qword [cmd_index], -1
    je      print_env

    mov     rbx, [cmd_index]
    lea     rsi, [r15 + rbx*8]          ;argv for the new image
    mov     rdi, [rsi]                  ;program name
    mov     rdx, new_envp
    call    __path_execve
    write   STDERR_FILENO, exec_fail_msg, exec_fail_len
    exit    127

print_env:
    xor     r12, r12
.pl:
    mov     rsi, [new_envp + r12*8]
    test    rsi, rsi
    je      .pdone
    call    strlen                      ;length -> rbx
    write   STDOUT_FILENO, rsi, rbx
    cmp     byte [zero_flag], 1
    je      .znul
    write   STDOUT_FILENO, newline, 1
    jmp     .pnext
.znul:
    write   STDOUT_FILENO, nulbyte, 1
.pnext:
    inc     r12
    jmp     .pl
.pdone:
    exit    0

bad_option:
    write   STDERR_FILENO, badopt_msg, badopt_len
    exit    125

; has_eq: rdi -> string; rax = 1 if it contains '='
has_eq:
    xor     rcx, rcx
.l:
    mov     al, [rdi + rcx]
    test    al, al
    je      .no
    cmp     al, '='
    je      .yes
    inc     rcx
    jmp     .l
.no:
    xor     rax, rax
    ret
.yes:
    mov     rax, 1
    ret

; name_in_removal: rdi -> env entry; rax = 1 if its NAME is in -u list or is
; overridden by an assignment.
name_in_removal:
    xor     rcx, rcx
.u:
    cmp     rcx, [u_count]
    jge     .assigns
    mov     rsi, [u_names + rcx*8]
    call    same_name
    test    rax, rax
    jnz     .yes
    inc     rcx
    jmp     .u
.assigns:
    xor     rcx, rcx
.a:
    cmp     rcx, [assign_count]
    jge     .no
    mov     rsi, [assign_ptrs + rcx*8]
    call    same_name
    test    rax, rax
    jnz     .yes
    inc     rcx
    jmp     .a
.no:
    xor     rax, rax
    ret
.yes:
    mov     rax, 1
    ret

; same_name: rdi, rsi -> strings; rax = 1 if the NAME parts (up to '=' or
; NUL) are equal. Uses r8 so the caller's rcx counter survives.
same_name:
    xor     r8, r8
.l:
    mov     al, [rdi + r8]
    mov     dl, [rsi + r8]
    cmp     al, '='
    je      .aend
    test    al, al
    je      .aend
    cmp     dl, '='
    je      .ne
    test    dl, dl
    je      .ne
    cmp     al, dl
    jne     .ne
    inc     r8
    jmp     .l
.aend:
    cmp     dl, '='
    je      .eq
    test    dl, dl
    je      .eq
.ne:
    xor     rax, rax
    ret
.eq:
    mov     rax, 1
    ret
