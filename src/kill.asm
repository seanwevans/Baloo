; src/kill.asm

    %include "include/sysdefs.inc"

section .bss
    buffer      resb 32                 ;Buffer for argument parsing
    number_buf  resb 32                 ;Buffer for number conversion
    signal      resq 1                  ;Signal number
    pid         resq 1                  ;Process ID
    pid_set     resb 1                  ;Whether a PID has already been parsed

section .data
usage_msg   db "Usage: kill [-s signum] pid", 10, 0
    usage_len   equ $ - usage_msg
invalid_pid db "kill: invalid pid", 10, 0
    invalid_pid_len equ $ - invalid_pid
invalid_sig db "kill: invalid signal specification", 10, 0
    invalid_sig_len equ $ - invalid_sig
debug_msg   db "Debug: signal=", 0
    debug_msg_len   equ $ - debug_msg
    newline     db WHITESPACE_NL, 0
    default_signal  equ 15

    sn1  db "HUP",0
    sn2  db "INT",0
    sn3  db "QUIT",0
    sn4  db "ILL",0
    sn5  db "TRAP",0
    sn6  db "ABRT",0
    sn7  db "BUS",0
    sn8  db "FPE",0
    sn9  db "KILL",0
    sn10 db "USR1",0
    sn11 db "SEGV",0
    sn12 db "USR2",0
    sn13 db "PIPE",0
    sn14 db "ALRM",0
    sn15 db "TERM",0
    sn16 db "STKFLT",0
    sn17 db "CHLD",0
    sn18 db "CONT",0
    sn19 db "STOP",0
    sn20 db "TSTP",0
    sn21 db "TTIN",0
    sn22 db "TTOU",0
    sn23 db "URG",0
    sn24 db "XCPU",0
    sn25 db "XFSZ",0
    sn26 db "VTALRM",0
    sn27 db "PROF",0
    sn28 db "WINCH",0
    sn29 db "IO",0
    sn30 db "PWR",0
    sn31 db "SYS",0
    NSIG equ 31
signames:
    dq 0, sn1, sn2, sn3, sn4, sn5, sn6, sn7, sn8, sn9, sn10
    dq sn11, sn12, sn13, sn14, sn15, sn16, sn17, sn18, sn19, sn20
    dq sn21, sn22, sn23, sn24, sn25, sn26, sn27, sn28, sn29, sn30, sn31

section .text
global      _start

_start:
    mov         rbp, rsp
    mov         qword [signal], default_signal ;Default signal is SIGTERM (15)
    mov         byte [pid_set], 0
    mov         rdi, [rbp]              ;Get argc from stack
    cmp         rdi, 1                  ;Check if we have at least one argument
    jle         show_usage              ;If no args, show usage

    mov         rsi, 1                  ;Start argument index at 1

parse_args:
    cmp         rsi, [rbp]              ;Compare current index with argc
    jge         check_pid               ;If done parsing, check if PID set

    mov         rax, [rbp + rsi*8 + 8]  ;Get argv[rsi]
    cmp         byte [rax], '-'
    jne         parse_as_pid            ;If not an option, assume it's a PID

check_s_option:
    cmp         byte [rax+1], 'l'       ;-l lists signal names/numbers
    je          do_list
    cmp         byte [rax+1], 's'
    jne         parse_dash_signal
    cmp         byte [rax+2], 0         ;Ensure it's just "-s"
    jne         invalid_signal

    inc         rsi                     ;Move to next argument
    cmp         rsi, [rbp]              ;Check if we have more arguments
    jge         show_usage              ;If no more args, show usage

    mov         rdi, [rbp + rsi*8 + 8]  ;Get signal specification arg
    call        parse_signal_spec
    cmp         rax, -1                 ;Check for parse error
    je          invalid_signal

    mov         [signal], rax
    inc         rsi                     ;Move to next argument
    jmp         parse_args

parse_dash_signal:
    cmp         byte [rax+1], 0         ;Reject bare "-"
    je          invalid_signal
    lea         rdi, [rax+1]            ;Parse text following '-'
    call        parse_signal_spec
    cmp         rax, -1
    je          invalid_signal

    mov         [signal], rax
    inc         rsi
    jmp         parse_args

parse_as_pid:
    cmp         byte [pid_set], 0
    jne         show_usage              ;Reject extra positional arguments

    mov         rdi, rax                ;Pass argument pointer
    call        parse_number            ;Parse it as a number

    cmp         rax, -1                 ;Check for parse error
    je          invalid_pid_err

    mov         [pid], rax
    mov         byte [pid_set], 1
    inc         rsi                     ;Move to next argument
    jmp         parse_args

check_pid:
    cmp         byte [pid_set], 0
    je          show_usage

send_signal:
    mov         rax, SYS_KILL
    mov         rdi, [pid]              ;pid
    mov         rsi, [signal]           ;signum
    syscall

    test        rax, rax
    js          error_exit

    exit        0

show_usage:
    write       STDERR_FILENO, usage_msg, usage_len
    exit        1

invalid_pid_err:
    write       STDERR_FILENO, invalid_pid, invalid_pid_len
    exit        1

invalid_signal:
    write       STDERR_FILENO, invalid_sig, invalid_sig_len
    exit        1

error_exit:
    neg         rax                     ;Convert negative error code to positive
    exit        rax

do_list:
; -l : convert each following argument (number -> name, name -> number).
; With no arguments, list every signal name.
    cmp         byte [rax+2], 0
    jne         invalid_signal
    inc         rsi                     ;skip the -l argument
    cmp         rsi, [rbp]
    jge         list_all
.loop:
    cmp         rsi, [rbp]
    jge         exit_ok
    mov         rdi, [rbp + rsi*8 + 8]
    push        rsi
    call        list_one
    pop         rsi
    inc         rsi
    jmp         .loop

list_all:
    mov         rcx, 1
.la:
    cmp         rcx, NSIG
    jg          exit_ok
    mov         rsi, [signames + rcx*8]
    push        rcx
    call        print_cstr_nl
    pop         rcx
    inc         rcx
    jmp         .la

exit_ok:
    exit        0

; list_one: rdi -> argument. If numeric, print its signal name; otherwise
; print the signal number for the name.
list_one:
    movzx       rax, byte [rdi]
    sub         al, '0'
    cmp         al, 9
    ja          .name
    call        parse_number            ;rax = number
    cmp         rax, NSIG
    ja          .done
    test        rax, rax
    jz          .done
    mov         rsi, [signames + rax*8]
    call        print_cstr_nl
    ret
.name:
    call        name_to_num             ;rax = number or -1
    cmp         rax, -1
    je          .done
    call        print_num_nl
.done:
    ret

; name_to_num: rdi -> signal name (optional SIG prefix); rax = number or -1
name_to_num:
    mov         rsi, rdi
    cmp         byte [rsi], 'S'
    jne         .search
    cmp         byte [rsi+1], 'I'
    jne         .search
    cmp         byte [rsi+2], 'G'
    jne         .search
    add         rsi, 3
.search:
    mov         rcx, 1
.loop:
    cmp         rcx, NSIG
    jg          .fail
    mov         rdx, [signames + rcx*8]
    xor         r8, r8
.cmp:
    mov         al, [rsi + r8]
    mov         r9b, [rdx + r8]
    cmp         al, r9b
    jne         .next
    test        al, al
    jz          .match
    inc         r8
    jmp         .cmp
.next:
    inc         rcx
    jmp         .loop
.match:
    mov         rax, rcx
    ret
.fail:
    mov         rax, -1
    ret

; print_cstr_nl: rsi -> NUL-terminated string; write it and a newline
print_cstr_nl:
    xor         rdx, rdx
.len:
    cmp         byte [rsi + rdx], 0
    je          .out
    inc         rdx
    jmp         .len
.out:
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    syscall
    write       STDOUT_FILENO, newline, 1
    ret

; print_num_nl: rax -> unsigned value; write decimal digits and a newline
print_num_nl:
    mov         rcx, number_buf
    add         rcx, 31
    mov         r8, 10
.conv:
    xor         rdx, rdx
    div         r8
    add         dl, '0'
    dec         rcx
    mov         [rcx], dl
    test        rax, rax
    jnz         .conv
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, rcx
    mov         rdx, number_buf
    add         rdx, 31
    sub         rdx, rcx
    syscall
    write       STDOUT_FILENO, newline, 1
    ret

parse_number:
    xor         rax, rax                ;Initialize result to 0
    xor         rcx, rcx                ;Initialize index to 0

parse_loop:
    movzx       rdx, byte [rdi+rcx]     ;Get current character
    test        rdx, rdx                ;Check for null terminator
    jz          parse_done

    sub         rdx, '0'
    cmp         rdx, 9
    ja          parse_error             ;If not 0-9, error

    imul        rax, 10
    add         rax, rdx
    inc         rcx                     ;Move to next character
    jmp         parse_loop

parse_done:
    test        rcx, rcx
    jz          parse_error
    ret

parse_error:
    mov         rax, -1                 ;Return error
    ret

parse_signal_spec:
; Accept decimal numbers or signal names (with optional SIG prefix)
; Input : rdi -> signal text
; Output: rax -> signal number, or -1 on error
    movzx       rdx, byte [rdi]
    sub         rdx, '0'
    cmp         rdx, 9
    jbe         parse_number

    mov         rax, rdi
    cmp         byte [rax], 'S'
    jne         signal_name
    cmp         byte [rax+1], 'I'
    jne         signal_name
    cmp         byte [rax+2], 'G'
    jne         signal_name
    lea         rax, [rax+3]

signal_name:
; HUP
    cmp         byte [rax], 'H'
    jne         sig_int
    cmp         byte [rax+1], 'U'
    jne         sig_int
    cmp         byte [rax+2], 'P'
    jne         sig_int
    cmp         byte [rax+3], 0
    jne         parse_error
    mov         rax, 1
    ret

sig_int:
    cmp         byte [rax], 'I'
    jne         sig_quit
    cmp         byte [rax+1], 'N'
    jne         sig_quit
    cmp         byte [rax+2], 'T'
    jne         sig_quit
    cmp         byte [rax+3], 0
    jne         parse_error
    mov         rax, 2
    ret

sig_quit:
    cmp         byte [rax], 'Q'
    jne         sig_kill
    cmp         byte [rax+1], 'U'
    jne         sig_kill
    cmp         byte [rax+2], 'I'
    jne         sig_kill
    cmp         byte [rax+3], 'T'
    jne         sig_kill
    cmp         byte [rax+4], 0
    jne         parse_error
    mov         rax, 3
    ret

sig_kill:
    cmp         byte [rax], 'K'
    jne         sig_term
    cmp         byte [rax+1], 'I'
    jne         sig_term
    cmp         byte [rax+2], 'L'
    jne         sig_term
    cmp         byte [rax+3], 'L'
    jne         sig_term
    cmp         byte [rax+4], 0
    jne         parse_error
    mov         rax, 9
    ret

sig_term:
    cmp         byte [rax], 'T'
    jne         sig_stop
    cmp         byte [rax+1], 'E'
    jne         sig_stop
    cmp         byte [rax+2], 'R'
    jne         sig_stop
    cmp         byte [rax+3], 'M'
    jne         sig_stop
    cmp         byte [rax+4], 0
    jne         parse_error
    mov         rax, 15
    ret

sig_stop:
    cmp         byte [rax], 'S'
    jne         sig_cont
    cmp         byte [rax+1], 'T'
    jne         sig_cont
    cmp         byte [rax+2], 'O'
    jne         sig_cont
    cmp         byte [rax+3], 'P'
    jne         sig_cont
    cmp         byte [rax+4], 0
    jne         parse_error
    mov         rax, 19
    ret

sig_cont:
    cmp         byte [rax], 'C'
    jne         sig_usr1
    cmp         byte [rax+1], 'O'
    jne         sig_usr1
    cmp         byte [rax+2], 'N'
    jne         sig_usr1
    cmp         byte [rax+3], 'T'
    jne         sig_usr1
    cmp         byte [rax+4], 0
    jne         parse_error
    mov         rax, 18
    ret

sig_usr1:
    cmp         byte [rax], 'U'
    jne         sig_usr2
    cmp         byte [rax+1], 'S'
    jne         sig_usr2
    cmp         byte [rax+2], 'R'
    jne         sig_usr2
    cmp         byte [rax+3], '1'
    jne         sig_usr2
    cmp         byte [rax+4], 0
    jne         parse_error
    mov         rax, 10
    ret

sig_usr2:
    cmp         byte [rax], 'U'
    jne         sig_alrm
    cmp         byte [rax+1], 'S'
    jne         sig_alrm
    cmp         byte [rax+2], 'R'
    jne         sig_alrm
    cmp         byte [rax+3], '2'
    jne         sig_alrm
    cmp         byte [rax+4], 0
    jne         parse_error
    mov         rax, 12
    ret

sig_alrm:
    cmp         byte [rax], 'A'
    jne         parse_error
    cmp         byte [rax+1], 'L'
    jne         parse_error
    cmp         byte [rax+2], 'R'
    jne         parse_error
    cmp         byte [rax+3], 'M'
    jne         parse_error
    cmp         byte [rax+4], 0
    jne         parse_error
    mov         rax, 14
    ret
