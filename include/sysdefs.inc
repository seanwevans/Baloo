; include/sysdefs.inc

    %include "include/defines.inc"
    %include "include/macros.inc"

section .bss
    __path_buf resb 4096

section .text
global open_file
global open_dest_file
global strlen

section .data
    error_msg_open db "Error opening file", 10
    error_msg_open_len equ $ - error_msg_open
    error_msg_read db "Error reading file", 10
    error_msg_read_len equ $ - error_msg_read
    error_msg_write db "Error writing file", 10
    error_msg_write_len equ $ - error_msg_write
    __path_prefix db "PATH=", 0
__default_path db "/usr/bin:/bin", 0
    __shell_prefix db "SHELL=", 0
    __default_shell db "/bin/sh", 0

section .text

open_file:
    cmp rsi, 0
    je .use_default
    mov rax, SYS_OPEN
    mov rdi, rsi
    mov rsi, O_RDONLY
    mov rdx, 0
    syscall
    cmp rax, 0
    jl .fail
    ret
.use_default:
    mov rax, rdi
    ret
.fail:
    write STDERR_FILENO, error_msg_open, error_msg_open_len
    exit 1

open_dest_file:
    cmp rsi, 0
    je .use_default
    mov rax, SYS_OPEN
    mov rdi, rsi
    mov rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov rdx, DEFAULT_MODE
    syscall
    cmp rax, 0
    jl .fail
    ret
.use_default:
    mov rax, rdi
    ret
.fail:
    write STDERR_FILENO, error_msg_open, error_msg_open_len
    exit 1

strlen:
    xor rbx, rbx
.loop:
    cmp byte [rsi + rbx], 0
    je .done
    inc rbx
    jmp .loop
.done:
    ret

; __find_env: return a pointer to an environment variable's value.
;   rdi = "NAME=" prefix (NUL-terminated, includes the '=')
;   rsi = envp (NULL-terminated array of char*)
;   returns rax = pointer just past the '=', or 0 when the var is absent.
;   clobbers rax, rcx, r8, r9
__find_env:
    mov r8, rsi
.fe_loop:
    mov r9, [r8]
    test r9, r9
    jz .fe_none
    mov rcx, rdi
.fe_cmp:
    mov al, [rcx]
    test al, al
    jz .fe_found
    cmp al, [r9]
    jne .fe_next
    inc rcx
    inc r9
    jmp .fe_cmp
.fe_next:
    add r8, 8
    jmp .fe_loop
.fe_found:
    mov rax, r9
    ret
.fe_none:
    xor rax, rax
    ret

; __path_execve: execve a program, searching PATH like execvp(3) when the
;                program name contains no slash.
;   rdi = program name (NUL-terminated)
;   rsi = argv (NULL-terminated) for the new image
;   rdx = envp (NULL-terminated)
;   returns ONLY on failure (every candidate failed); clobbers r8-r15, etc.
__path_execve:
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rcx, r12
.scan_slash:
    mov al, [rcx]
    test al, al
    jz .no_slash
    cmp al, '/'
    je .direct
    inc rcx
    jmp .scan_slash
.direct:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rax, SYS_EXECVE
    syscall
    ret
.no_slash:
    mov rdi, __path_prefix
    mov rsi, r14
    call __find_env
    test rax, rax
    jnz .have_path
    mov rax, __default_path
.have_path:
    mov r15, rax
.entry_loop:
    mov rdi, __path_buf
    mov r8, r15
    xor rcx, rcx
.copy_entry:
    mov al, [r8]
    test al, al
    jz .entry_done
    cmp al, 58
    je .entry_done
    cmp rcx, 4000
    jae .skip_overflow
    mov [rdi], al
    inc rdi
    inc r8
    inc rcx
    jmp .copy_entry
.skip_overflow:
    mov al, [r8]
    test al, al
    jz .entry_done
    cmp al, 58
    je .entry_done
    inc r8
    jmp .skip_overflow
.entry_done:
    test rcx, rcx
    jz .append_name
    mov byte [rdi], '/'
    inc rdi
.append_name:
    mov r9, r12
.copy_name:
    mov al, [r9]
    mov [rdi], al
    test al, al
    jz .try_exec
    inc rdi
    inc r9
    jmp .copy_name
.try_exec:
    mov rdi, __path_buf
    mov rsi, r13
    mov rdx, r14
    mov rax, SYS_EXECVE
    syscall
    mov al, [r8]
    test al, al
    jz .exhausted
    lea r15, [r8 + 1]
    jmp .entry_loop
.exhausted:
    ret
