; src/kill.asm

%include "include/sysdefs.inc"

section .bss
    buffer      resb 32         ; Buffer for argument parsing
    number_buf  resb 32         ; Buffer for number conversion
    signal      resq 1          ; Signal number
    pid         resq 1          ; Process ID
    pid_set     resb 1          ; Whether a PID has already been parsed

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

section .text
    global      _start

_start:
    mov         rbp, rsp
    mov         qword [signal], default_signal  ; Default signal is SIGTERM (15)
    mov         byte [pid_set], 0
    mov         rdi, [rbp]          ; Get argc from stack
    cmp         rdi, 1              ; Check if we have at least one argument
    jle         show_usage          ; If no args, show usage

    mov         rsi, 1              ; Start argument index at 1
    
parse_args:
    cmp         rsi, [rbp]          ; Compare current index with argc
    jge         check_pid           ; If done parsing, check if PID set

    mov         rax, [rbp + rsi*8 + 8]  ; Get argv[rsi]
    cmp         byte [rax], '-'
    jne         parse_as_pid        ; If not an option, assume it's a PID

check_s_option:
    cmp         byte [rax+1], 's'
    jne         parse_dash_signal
    cmp         byte [rax+2], 0     ; Ensure it's just "-s"
    jne         invalid_signal

    inc         rsi                 ; Move to next argument
    cmp         rsi, [rbp]          ; Check if we have more arguments
    jge         show_usage          ; If no more args, show usage

    mov         rdi, [rbp + rsi*8 + 8]  ; Get signal specification arg
    call        parse_signal_spec
    cmp         rax, -1             ; Check for parse error
    je          invalid_signal

    mov         [signal], rax
    inc         rsi                 ; Move to next argument
    jmp         parse_args

parse_dash_signal:
    cmp         byte [rax+1], 0     ; Reject bare "-"
    je          invalid_signal
    lea         rdi, [rax+1]        ; Parse text following '-'
    call        parse_signal_spec
    cmp         rax, -1
    je          invalid_signal

    mov         [signal], rax
    inc         rsi
    jmp         parse_args

parse_as_pid:
    cmp         byte [pid_set], 0
    jne         show_usage          ; Reject extra positional arguments

    mov         rdi, rax            ; Pass argument pointer
    call        parse_number        ; Parse it as a number
    
    cmp         rax, -1             ; Check for parse error
    je          invalid_pid_err

    mov         [pid], rax
    mov         byte [pid_set], 1
    inc         rsi                 ; Move to next argument
    jmp         parse_args

check_pid:
    cmp         byte [pid_set], 0
    je          show_usage
    
send_signal:
    mov         rax, SYS_KILL
    mov         rdi, [pid]          ; pid
    mov         rsi, [signal]       ; signum
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
    neg         rax                 ; Convert negative error code to positive
    exit        rax

parse_number:
    xor         rax, rax            ; Initialize result to 0
    xor         rcx, rcx            ; Initialize index to 0
    
parse_loop:
    movzx       rdx, byte [rdi+rcx] ; Get current character
    test        rdx, rdx            ; Check for null terminator
    jz          parse_done

    sub         rdx, '0'
    cmp         rdx, 9
    ja          parse_error         ; If not 0-9, error

    imul        rax, 10
    add         rax, rdx
    inc         rcx                 ; Move to next character
    jmp         parse_loop
    
parse_done:
    test        rcx, rcx
    jz          parse_error
    ret
    
parse_error:
    mov         rax, -1              ; Return error
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
