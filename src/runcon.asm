; src/runcon.asm
;
; runcon - run a command in a specified SELinux security context.
;
; Supported forms
;   runcon                     print the current security context
;   runcon CONTEXT COMMAND...  run COMMAND in the given SELinux context
;
; With no arguments the current context is read from
; /proc/self/attr/current and printed (coreutils prints "kernel" on a
; kernel without SELinux enabled).  When a CONTEXT and a COMMAND are given,
; the kernel must have SELinux enabled; CONTEXT is written to
; /proc/self/attr/exec and the command is exec'd, matching
; setexeccon(3) + execvp(3).
;
; Option flags (-u -r -t -l -c) are not parsed; this implements the plain
; positional "CONTEXT COMMAND" form documented above.

    %include "include/sysdefs.inc"

    %define SELINUX_MAGIC 0xf97cff8c

section .bss
    ctx_buf      resb 4096
    statfs_buf   resb 128

section .data
    attr_current db "/proc/self/attr/current", 0
    attr_exec    db "/proc/self/attr/exec", 0
    selinux_mnt  db "/sys/fs/selinux", 0
no_cmd_msg   db "runcon: no command specified", 10, "Try 'runcon --help' for more information.", 10
    no_cmd_len   equ $ - no_cmd_msg
sel_msg      db "runcon: runcon may be used only on a SELinux kernel", 10
    sel_len      equ $ - sel_msg
set_err_msg  db "runcon: failed to set execution context", 10
    set_err_len  equ $ - set_err_msg
read_err_msg db "runcon: failed to get current context", 10
    read_err_len equ $ - read_err_msg
run_err_msg  db "runcon: cannot run command", 10
    run_err_len  equ $ - run_err_msg
    newline      db 10

section .text
global _start

_start:
    pop     rbx                         ;argc
    mov     r12, rsp                    ;argv pointer
    lea     r13, [r12 + rbx*8 + 8]      ;envp pointer

    cmp     rbx, 1
    je      print_current               ;no args, print current context
    cmp     rbx, 2
    jle     no_command                  ;context given but no command

;------------------------------------------------------------------
; runcon CONTEXT COMMAND [ARGS...]
; argv[1] = context, argv[2..] = command and its arguments
;------------------------------------------------------------------
run_with_context:
    call    is_selinux_enabled
    test    rax, rax
    jz      not_selinux

    mov     r14, [r12 + 8]              ;context string

    mov     rax, SYS_OPEN               ;open attr/exec for writing
    mov     rdi, attr_exec
    mov     rsi, O_WRONLY
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      set_failed
    mov     r15, rax                    ;fd

    mov     rsi, r14                    ;measure context length
    call    strlen                      ;rbx = length without NUL
    inc     rbx                         ;libselinux writes the NUL too

    mov     rax, SYS_WRITE
    mov     rdi, r15
    mov     rsi, r14
    mov     rdx, rbx
    syscall
    mov     rbx, rax                    ;save write result

    mov     rax, SYS_CLOSE
    mov     rdi, r15
    syscall

    cmp     rbx, 0
    jl      set_failed

    lea     rsi, [r12 + 16]             ;&argv[2] becomes the new argv
    mov     rdi, [rsi]                  ;command name
    mov     rdx, r13                    ;envp
    call    __path_execve

    write   STDERR_FILENO, run_err_msg, run_err_len
    exit    126

;------------------------------------------------------------------
print_current:
    mov     rax, SYS_OPEN
    mov     rdi, attr_current
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      read_failed
    mov     r15, rax                    ;fd

    mov     rax, SYS_READ
    mov     rdi, r15
    mov     rsi, ctx_buf
    mov     rdx, 4096
    syscall
    mov     r14, rax                    ;bytes read

    mov     rax, SYS_CLOSE
    mov     rdi, r15
    syscall

    cmp     r14, 0
    jl      read_failed

    xor     rcx, rcx                    ;trim at first NUL or newline
.scan:
    cmp     rcx, r14
    jge     .emit
    mov     al, [ctx_buf + rcx]
    test    al, al
    je      .emit
    cmp     al, 10
    je      .emit
    inc     rcx
    jmp     .scan

.emit:
    write   STDOUT_FILENO, ctx_buf, rcx
    write   STDOUT_FILENO, newline, 1
    exit    0

;------------------------------------------------------------------
; is_selinux_enabled returns rax = 1 when selinuxfs is mounted at
; /sys/fs/selinux, else 0.  Mirrors libselinux's mountpoint check.
;------------------------------------------------------------------
is_selinux_enabled:
    mov     rax, SYS_STATFS
    mov     rdi, selinux_mnt
    mov     rsi, statfs_buf
    syscall
    test    rax, rax
    js      .no
    mov     eax, dword [statfs_buf]     ;f_type, low 32 bits
    cmp     eax, SELINUX_MAGIC
    jne     .no
    mov     rax, 1
    ret
.no:
    xor     rax, rax
    ret

;------------------------------------------------------------------
no_command:
    write   STDERR_FILENO, no_cmd_msg, no_cmd_len
    exit    125

not_selinux:
    write   STDERR_FILENO, sel_msg, sel_len
    exit    125

set_failed:
    write   STDERR_FILENO, set_err_msg, set_err_len
    exit    125

read_failed:
    write   STDERR_FILENO, read_err_msg, read_err_len
    exit    1
