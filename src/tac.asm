; src/tac.asm -- tac(1): print files with their lines in reverse order.
; Usage: tac [FILE...]   ("-" or no FILE = stdin).
;
; Each input is read whole into a growable buffer (include/slurp.inc), then
; walked backwards from the end, emitting each line with its newline. A final
; line without a newline is printed first, unterminated, as GNU tac does.
    %include "include/sysdefs.inc"
    %include "include/slurp.inc"

    %define OBUFCAP 65536

section .bss
    obuf        resb OBUFCAP
    olen        resq 1
    exit_status resq 1

section .data
tac_pre     db "tac: "
    tac_pre_len equ $ - tac_pre
tac_suf     db ": No such file or directory", WHITESPACE_NL
    tac_suf_len equ $ - tac_suf

section .text
global _start

_start:
    pop r12                             ;argc
    pop rdi                             ;skip program name
    mov qword [exit_status], 0
    dec r12
    cmp r12, 0
    je read_stdin

process_args:
    cmp r12, 0
    je exit_success
    pop rdi                             ;filename
    cmp byte [rdi], '-'                 ;"-" means stdin
    jne .file
    cmp byte [rdi + 1], 0
    jne .file
    push r12
    mov rdi, STDIN_FILENO
    call tac_fd
    pop r12
    jmp .next
.file:
    call tac_file
.next:
    dec r12
    jmp process_args

read_stdin:
    mov rdi, STDIN_FILENO
    call tac_fd
    jmp exit_success

; rdi = filename
tac_file:
    mov rax, SYS_OPEN
    mov rsi, O_RDONLY
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl report_missing
    mov rdi, rax
    push r12
    push rdi                            ;preserve fd across tac_fd
    call tac_fd
    pop rdi                             ;restore fd for close
    pop r12
    mov rax, SYS_CLOSE
    syscall
    ret

; tac_fd: rdi = file descriptor. Reads it all, writes its lines in reverse.
; Uses rbx, r14, r15; preserves r12/r13.
tac_fd:
    call slurp                          ;rax = buffer, rdx = length
    cmp qword [slurp_err], 0
    jl error_exit
    mov rbx, rax                        ;buffer base
    mov r15, rdx                        ;end of the line being collected
    test r15, r15
    jz .done
    lea r14, [r15 - 1]                  ;scan index
    cmp byte [rbx + r14], WHITESPACE_NL
    jne .scan
    dec r14                             ;the final newline ends the last line
.scan:
    cmp r14, 0
    jl .first
    cmp byte [rbx + r14], WHITESPACE_NL
    jne .prev
    lea rsi, [rbx + r14 + 1]            ;line runs from just past this newline
    mov rdx, r15
    sub rdx, r14
    dec rdx
    call emit
    lea r15, [r14 + 1]
.prev:
    dec r14
    jmp .scan
.first:
    mov rsi, rbx
    mov rdx, r15
    call emit
.done:
    call flush
    ret

; emit: queue rdx bytes at rsi for stdout, flushing as obuf fills.
emit:
    test rdx, rdx
    jz .ret
    mov rax, OBUFCAP
    sub rax, [olen]
    cmp rdx, rax
    jbe .copy
    push rsi
    push rdx
    call flush
    pop rdx
    pop rsi
    cmp rdx, OBUFCAP
    jb .copy
jmp write_all                       ;too big to buffer: write it directly
.copy:
    lea rdi, [obuf]
    add rdi, [olen]
    mov rcx, rdx
    add [olen], rdx
    rep movsb
.ret:
    ret

; flush: write out whatever obuf holds.
flush:
    mov rdx, [olen]
    mov qword [olen], 0
    lea rsi, [obuf]
; write_all: write rdx bytes at rsi to stdout, resuming after short writes.
write_all:
    test rdx, rdx
    jz .ret
    mov rax, SYS_WRITE
    mov rdi, STDOUT_FILENO
    syscall
    test rax, rax
    js error_exit
    add rsi, rax
    sub rdx, rax
    jmp write_all
.ret:
    ret

error_exit:
    exit 1

; report_missing: rdi -> filename; print a diagnostic and set the exit status
report_missing:
    mov r13, rdi
    write STDERR_FILENO, tac_pre, tac_pre_len
    mov rsi, r13
    call strlen                         ;rbx = length (include/sysdefs.inc)
    mov rax, SYS_WRITE
    mov rdi, STDERR_FILENO
    mov rsi, r13
    mov rdx, rbx
    syscall
    write STDERR_FILENO, tac_suf, tac_suf_len
    mov qword [exit_status], 1
    ret

exit_success:
    mov rdi, [exit_status]
    mov rax, SYS_EXIT
    syscall
