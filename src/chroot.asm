; src/chroot.asm

    %include "include/sysdefs.inc"

section .bss
    args_ptr        resq 1
    env_ptr         resq 1

section .data
error_msg       db "Error: Usage: chroot <directory>", 10, 0
    error_len       equ $ - error_msg
chroot_fail_msg db "Error: chroot failed (requires root privileges)", 10, 0
    chroot_fail_len equ $ - chroot_fail_msg
execve_fail_msg db "Error: execve failed", 10, 0
    execve_fail_len equ $ - execve_fail_msg
chdir_fail_msg  db "Error: chdir failed", 10, 0
    chdir_fail_len  equ $ - chdir_fail_msg
not_root_msg    db "Error: Must be run as root (UID 0)", 10, 0
    not_root_len    equ $ - not_root_msg
    shell_path      db "/bin/sh", 0
    root_path       db "/", 0

section .text
global          _start

_start:
    pop             r10                 ;argc
    cmp             r10, 2
    jl              usage_error         ;If argc < 2, show usage and exit

    mov             rbx, rsp            ;rbx = argv (address of first argument pointer)
    mov             [args_ptr], rbx     ;Save argv for later use
    lea             r11, [rbx + r10*8 + 8]
    mov             [env_ptr], r11      ;Save envp for later
    mov             rax, SYS_GETUID
    syscall

    test            rax, rax            ;Check if UID is 0 (root)
    jnz             not_root_error      ;If not root, show error and exit
    mov             rdi, [rbx + 8]      ;argv[1] is the directory path
    mov             rax, SYS_CHROOT
    syscall

    test            rax, rax
    jl              chroot_error

    lea             rdi, [rel root_path] ;Change directory to new root
    mov             rax, SYS_CHDIR
    syscall

    test            rax, rax
    jl              chdir_error

    cmp             r10, 3              ;If argc >= 3, we have a command to execute
    jge             exec_command

    sub             rsp, 24             ;Space for 3 pointers (NULL terminated)
mov             rdi, shell_path     ; First argument: path to shell
    mov             [rsp], rdi          ;argv[0] = shell_path
    mov             QWORD [rsp+8], 0    ;argv[1] = NULL
mov             rsi, rsp            ; Second argument: argv array
mov             rdx, [env_ptr]      ; Third argument: environment variables

    mov             rax, SYS_EXECVE
    syscall

    jmp             execve_error

exec_command:
    add             rbx, 16             ;Skip argv[0] and argv[1]
    mov             rsi, rbx            ;command and its arguments

    mov             rdi, [rbx]          ;command path
    mov             rdx, [env_ptr]      ;envp

    mov             rax, SYS_EXECVE
    syscall

    jmp             execve_error

usage_error:
    write           STDERR_FILENO, error_msg, error_len
    exit            1

chroot_error:
    write           STDERR_FILENO, chroot_fail_msg, chroot_fail_len
    exit            1

execve_error:
    write           STDERR_FILENO, execve_fail_msg, execve_fail_len
    exit            1

chdir_error:
    write           STDERR_FILENO, chdir_fail_msg, chdir_fail_len
    exit            1

not_root_error:
    write           STDERR_FILENO, not_root_msg, not_root_len
    exit            1

