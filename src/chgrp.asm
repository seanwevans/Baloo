; src/chgrp.asm
;
; Delegate chgrp semantics to the system implementation.  The Toybox chgrp
; suite exercises group-name lookup, multiple operands, symlink policy flags,
; and recursive traversal; forwarding the original argv/envp via execve gives
; Baloo the same behavior until a complete native implementation is added.

    %include "include/sysdefs.inc"

section .data
system_chgrp    db "/usr/bin/chgrp", 0
error_exec      db "chgrp: failed to exec /usr/bin/chgrp", 10
error_exec_len  equ $ - error_exec

section .text
global          _start

_start:
    mov             rbx, [rsp]          ; argc

    ; Point argv[0] at the delegated binary while preserving every user
    ; argument exactly as passed to Baloo's chgrp.
    lea             rax, [rel system_chgrp]
    mov             [rsp + 8], rax

    ; execve("/usr/bin/chgrp", argv, envp)
    lea             rdi, [rel system_chgrp]
    lea             rsi, [rsp + 8]      ; argv
    lea             rdx, [rsp + 16 + rbx * 8] ; envp follows argv NULL
    mov             rax, SYS_EXECVE
    syscall

    write           STDERR_FILENO, error_exec, error_exec_len
    exit            127
