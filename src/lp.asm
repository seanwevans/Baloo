; src/lp.asm

%include "include/sysdefs.inc"

section .bss
    buffer      resb 4096       ; buffer for reading
    buffer_size equ 4096
    printer_fd  resq 1

section .data
    printer_dev1 db "/dev/usb/lp0", 0
    printer_dev2 db "/dev/lp0", 0
    printer_err  db "lp: cannot open printer", WHITESPACE_NL
    printer_err_len equ $ - printer_err

section .text
    global _start
    global open_printer
    global send_fd

_start:
    pop         r12             ; argc
    mov         rbx, rsp        ; argv pointer
    dec         r12             ; skip program name

    call        open_printer

    cmp         r12, 0
    je          .stdin

.arg_loop:
    cmp         r12, 0
    je          .done
    mov         rdi, [rbx]      ; filename pointer
    add         rbx, 8
    push        rbx
    push        r12
    mov         rax, SYS_OPEN
    mov         rsi, O_RDONLY
    xor         rdx, rdx
    syscall
    cmp         rax, 0
    jl          .file_error
    mov         rdi, rax
    call        send_fd
    mov         rax, SYS_CLOSE
    mov         rdi, rdi        ; fd already in rdi
    syscall
    pop         r12
    pop         rbx
    dec         r12
    jmp         .arg_loop

.stdin:
    mov         rdi, STDIN_FILENO
    call        send_fd

.done:
    mov         rax, [printer_fd]
    cmp         rax, STDOUT_FILENO
    je          .exit
    mov         rdi, rax
    mov         rax, SYS_CLOSE
    syscall
.exit:
    exit        0

.file_error:
    pop         r12
    pop         rbx
    exit        1

; ------------------------------------------------------------
; open_printer: open printer device, store fd in printer_fd
; ------------------------------------------------------------
open_printer:
    mov         rax, SYS_OPEN
    mov         rdi, printer_dev1
    mov         rsi, O_WRONLY
    xor         rdx, rdx
    syscall
    cmp         rax, 0
    jl          .try_alt
    mov         [printer_fd], rax
    ret

.try_alt:
    mov         rax, SYS_OPEN
    mov         rdi, printer_dev2
    mov         rsi, O_WRONLY
    xor         rdx, rdx
    syscall
    cmp         rax, 0
    jl          .fail
    mov         [printer_fd], rax
    ret

.fail:
    write       STDERR_FILENO, printer_err, printer_err_len
    mov         qword [printer_fd], STDOUT_FILENO
    ret

; ------------------------------------------------------------
; send_fd: copy from fd in rdi to printer_fd
; ------------------------------------------------------------
send_fd:
    push        rdi
    mov         r15, [printer_fd]

.read_loop:
    mov         rax, SYS_READ
    pop         rdi
    push        rdi
    mov         rsi, buffer
    mov         rdx, buffer_size
    syscall
    cmp         rax, 0
    jle         .done
    mov         rdx, rax
    mov         rax, SYS_WRITE
    mov         rdi, r15
    mov         rsi, buffer
    syscall
    jmp         .read_loop

.done:
    pop         rdi
    ret
