; src/uptime.asm

    %include "include/sysdefs.inc"

section .bss
    sysinfo_buf resb 128                ;Buffer for sysinfo structure
    time_buf    resq 1                  ;Buffer for current time
    output_buf  resb 256                ;Buffer for complete output
    temp_buf    resb 32                 ;Temporary buffer for number conversion

section .data
time_str    db " 00:00:00 "         ; Buffer for current time
    up_str      db "up "                ;Up string
    days_str    db " days, "            ;Days string
    day_str     db " day, "             ;Day string (singular)
    min_str     db " min"               ;Minutes string for short format
    users_str   db ",  1 user,  "       ;User count string
load_str    db "load average: "     ; Load average prefix
    comma_space db ", "                 ;Comma and space
    space       db " "                  ;Space
colon       db ":"                  ; Colon
    dot         db "."                  ;Dot
    newline     db WHITESPACE_NL
    digits      db "0123456789"         ;Digits for conversion

section .text
global      _start

_start:

    mov         rax, SYS_TIME
    xor         rdi, rdi
    syscall

    mov         [time_buf], rax         ;Store time value
    call        format_current_time

    mov         rax, SYS_SYSINFO
    mov         rdi, sysinfo_buf
    syscall

    test        rax, rax
    jnz         exit_error              ;Exit if error

    mov         rdi, output_buf

    mov         rsi, time_str
    mov         rcx, 10                 ;Length of time string
    rep         movsb

    mov         rax, [sysinfo_buf]      ;Get uptime in seconds

    call        format_uptime

    mov         rsi, users_str
    mov         rcx, 11                 ;Length of users string
    rep         movsb
    mov         rsi, load_str
    mov         rcx, 14                 ;Length of load average string
    rep         movsb
    mov         rax, [sysinfo_buf+8]
    mov         rbx, 65536              ;Fixed-point format, divide by 2^16
    xor         rdx, rdx
    div         rbx
    push        rdx                     ;Save fractional part
    call        format_number           ;Format integer part

    mov         byte [rdi], '.'
    inc         rdi

    pop         rax                     ;Get fractional part
    mov         rcx, 655                ;Scale to get 2 decimal places (65536/100)
    mul         rcx
    mov         rcx, 65536
    div         rcx
    cmp         rax, 10
    jae         .two_digits

    mov         byte [rdi], '0'         ;Add leading zero
    inc         rdi

.two_digits:
    call        format_number

    mov         rsi, comma_space
    mov         rcx, 2
    rep         movsb
    mov         rax, [sysinfo_buf+16]
    mov         rbx, 65536              ;Fixed-point format
    xor         rdx, rdx
    div         rbx
    push        rdx                     ;Save fractional part
    call        format_number           ;Format integer part

    mov         byte [rdi], '.'
    inc         rdi

    pop         rax                     ;Get fractional part
    mov         rcx, 655                ;Scale to get 2 decimal places
    mul         rcx
    mov         rcx, 65536
    div         rcx
    cmp         rax, 10
    jae         .two_digits2

    mov         byte [rdi], '0'         ;Add leading zero
    inc         rdi

.two_digits2:
    call        format_number

    mov         rsi, comma_space
    mov         rcx, 2
    rep         movsb
    mov         rax, [sysinfo_buf+24]
    mov         rbx, 65536              ;Fixed-point format
    xor         rdx, rdx
    div         rbx
    push        rdx                     ;Save fractional part
    call        format_number           ;Format integer part

    mov         byte [rdi], '.'
    inc         rdi
    pop         rax                     ;Get fractional part
    mov         rcx, 655                ;Scale to get 2 decimal places
    mul         rcx
    mov         rcx, 65536
    div         rcx

    cmp         rax, 10
    jae         .two_digits3
    mov         byte [rdi], '0'         ;Add leading zero
    inc         rdi

.two_digits3:
    call        format_number

    mov         byte [rdi], WHITESPACE_NL
    inc         rdi

    mov         rdx, rdi
    sub         rdx, output_buf         ;Calculate length
    write       STDOUT_FILENO, output_buf, rdx

    exit        0

exit_error:
    exit        1

format_current_time:
    push        rbp
    mov         rbp, rsp
    mov         rax, [time_buf]         ;Get time value
    mov         rdx, 0
    mov         rcx, 86400              ;Seconds per day
    div         rcx                     ;RAX = days, RDX = seconds in day
    mov         rax, rdx                ;Focus on seconds in day
    mov         rdx, 0
    mov         rcx, 3600               ;Seconds per hour
    div         rcx                     ;RAX = hours, RDX = remaining seconds
    cmp         rax, 10
    jae         .format_hours

    mov         byte [time_str+1], '0'  ;Add leading zero
    add         rax, '0'
    mov         byte [time_str+2], al
    jmp         .hours_done

.format_hours:
    mov         rcx, 10
    mov         rdx, 0
    div         rcx                     ;RAX = tens, RDX = ones
    add         rax, '0'
    add         rdx, '0'
    mov         byte [time_str+1], al
    mov         byte [time_str+2], dl

.hours_done:

    mov         rax, rdx                ;Restore remaining seconds
    mov         rdx, 0
    mov         rcx, 60                 ;Seconds per minute
    div         rcx                     ;RAX = minutes, RDX = seconds

    push        rdx                     ;Save seconds
    cmp         rax, 10
    jae         .format_minutes

    mov         byte [time_str+4], '0'  ;Add leading zero
    add         rax, '0'
    mov         byte [time_str+5], al
    jmp         .minutes_done

.format_minutes:
    mov         rcx, 10
    mov         rdx, 0
    div         rcx                     ;RAX = tens, RDX = ones
    add         rax, '0'
    add         rdx, '0'
    mov         byte [time_str+4], al
    mov         byte [time_str+5], dl

.minutes_done:

    pop         rax                     ;Restore seconds
    cmp         rax, 10
    jae         .format_seconds

    mov         byte [time_str+7], '0'  ;Add leading zero
    add         rax, '0'
    mov         byte [time_str+8], al
    jmp         .seconds_done

.format_seconds:
    mov         rcx, 10
    mov         rdx, 0
    div         rcx                     ;RAX = tens, RDX = ones
    add         rax, '0'
    add         rdx, '0'
    mov         byte [time_str+7], al
    mov         byte [time_str+8], dl

.seconds_done:
pop         rbp                     ; Fixed: removed invalid 'mov' before 'pop rbp'
    ret

format_uptime:
    push        rbp
    mov         rbp, rsp
    mov         rsi, up_str
    mov         rcx, 3                  ;Length of "up "
    rep         movsb
    cmp         rax, 60
    jb          .just_seconds

    mov         rdx, 0
    mov         rcx, 86400              ;Seconds per day
    div         rcx                     ;RAX = days, RDX = remaining seconds
    test        rax, rax
    jz          .no_days

    cmp         rax, 1
    je          .one_day

    call        format_number           ;Format number of days

    mov         rsi, days_str
    mov         rcx, 7                  ;Length of " days, "
    rep         movsb
    jmp         .format_hours

.one_day:
    mov         byte [rdi], '1'
    inc         rdi
    mov         rsi, day_str
    mov         rcx, 6                  ;Length of " day, "
    rep         movsb
    jmp         .format_hours

.no_days:
    mov         rax, rdx                ;Get remaining seconds

.format_hours:
    mov         rdx, 0
    mov         rcx, 3600               ;Seconds per hour
    div         rcx                     ;RAX = hours, RDX = remaining seconds

    test        rax, rax
    jz          .no_hours

    call        format_number

    mov         rax, rdx                ;Get remaining seconds
    cmp         rax, 60
    jb          .done_time

    mov         rsi, colon
    mov         rcx, 1
    rep         movsb
    mov         rax, rdx
    mov         rdx, 0
    mov         rcx, 60
    div         rcx                     ;minutes
    cmp         rax, 10
    jae         .format_minutes

    mov         byte [rdi], '0'         ;Add leading zero
    inc         rdi

.format_minutes:
    call        format_number
    jmp         .done_time

.no_hours:
    mov         rax, rdx                ;Get remaining seconds
    mov         rdx, 0
    mov         rcx, 60
    div         rcx                     ;minutes
    test        rax, rax
    jz          .just_seconds

    call        format_number

    mov         rsi, min_str
    mov         rcx, 4                  ;Length of " min"
    rep         movsb
    jmp         .done_time

.just_seconds:
    mov         byte [rdi], '0'
    inc         rdi
    mov         rsi, min_str
    mov         rcx, 4                  ;Length of " min"
    rep         movsb

.done_time:
    pop         rbp
    ret

format_number:
    push        rbp
    mov         rbp, rsp
    push        rax                     ;Save original number
    push        rcx                     ;Save registers
    push        rdx
    test        rax, rax
    jnz         .not_zero

    mov         byte [rdi], '0'
    inc         rdi
    jmp         .done

.not_zero:
    mov         rcx, temp_buf
    add         rcx, 31                 ;Point to end of buffer
    mov         byte [rcx], 0           ;Null terminator
    dec         rcx

.digit_loop:
    mov         rdx, 0
    mov         rbx, 10
    div         rbx                     ;RAX = quotient, RDX = remainder
    add         dl, '0'                 ;Convert remainder to ASCII
    mov         [rcx], dl               ;Store digit
    dec         rcx                     ;Move back in buffer
    test        rax, rax                ;Check if more digits
    jnz         .digit_loop

    inc         rcx                     ;Point to first digit
    mov         rsi, rcx

.copy_loop:
    mov         al, [rsi]
    test        al, al                  ;Check for null terminator
    jz          .done

    mov         [rdi], al               ;Copy digit to output
    inc         rsi
    inc         rdi
    jmp         .copy_loop

.done:
    pop         rdx
    pop         rcx
    pop         rax
    pop         rbp
    ret
