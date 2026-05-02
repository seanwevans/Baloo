; src/logname.asm

    %include "include/sysdefs.inc"

section .bss
    uid_str     resb 12                 ;Buffer for UID as string + null terminator
    read_buf    resb 4096               ;Buffer to read /etc/passwd chunks
    username    resb 256                ;Buffer to store the found username

section .data
    passwd_file db "/etc/passwd", 0
    newline     db WHITESPACE_NL
colon       db ":"

section .text
global      _start

_start:
    mov         rax, SYS_GETEUID
    syscall

    mov         r12, rax
    mov         rdi, uid_str + 10       ;Point to end of uid_str buffer (leave space)
    mov         byte [rdi+1], 0         ;Null terminate
    mov         rax, r12                ;UID to convert
    mov         rbx, 10                 ;Divisor

.uid_to_str_loop:
    xor         rdx, rdx                ;Clear rdx for division
    div         rbx                     ;rax = rax / 10, rdx = rax % 10
    add         dl, '0'                 ;Convert remainder to ASCII digit
    mov         [rdi], dl               ;Store digit
    dec         rdi                     ;Move pointer back
    test        rax, rax                ;Is quotient zero?
    jnz         .uid_to_str_loop        ;Loop if not zero

    inc         rdi                     ;Point rdi to the start of the UID string
    mov         r13, rdi                ;Store pointer to UID string in r13
    mov         rax, 2                  ;syscall number for open
    lea         rdi, [rel passwd_file]  ;file path
    mov         rsi, 0                  ;flags = O_RDONLY
    xor         rdx, rdx                ;mode = 0
    syscall

    test        rax, rax
    js          .exit_error

    mov         r14, rax                ;file descriptor
    mov         r15, 0                  ;r15 = bytes remaining from previous read (unused here)

.read_loop:
    mov         rax, 0                  ;syscall number for read
    mov         rdi, r14                ;file descriptor
    lea         rsi, [rel read_buf]     ;buffer address
    mov         rdx, 4096               ;buffer size
    syscall

    test        rax, rax
    jle         .not_found              ;Exit if EOF or read error

    lea         rsi, [rel read_buf]     ;rsi = current position in buffer
    mov         rcx, rax                ;rcx = bytes read (loop counter)

.process_line_loop:
    mov         r8, rsi                 ;start of current line/segment

.find_eol:
    cmp         rcx, 0
    jle         .end_of_buffer          ;Reached end of buffer data

    cmp         byte [rsi], 10          ;Check for newline
    je          .found_eol

    inc         rsi
    dec         rcx
    jmp         .find_eol

.found_eol:
    mov         rdx, r8                 ;rdx points to start of line
    mov         rdi, username           ;Destination buffer for username

.parse_username:
    cmp         rdx, rsi
jge         .parse_error        ; ':' not found before UID field starts? error/skip

    mov         al, [rdx]
cmp         al, ':'
    je          .found_user_delim

    mov         [rdi], al
    inc         rdi
    inc         rdx
    jmp         .parse_username

.found_user_delim:
    mov         byte [rdi], 0           ;Null terminate username in buffer
inc         rdx                 ; Skip ':'

.skip_password:
    cmp         rdx, rsi
    jge         .parse_error
cmp         byte [rdx], ':'
    je          .found_pass_delim
    inc         rdx
    jmp         .skip_password

.found_pass_delim:
inc         rdx                 ; Skip ':'

.compare_uid:
    mov         rdi, r13                ;Our target UID string pointer

.uid_compare_loop:
    cmp         rdx, rsi                ;Check end of line segment
jge         .parse_error        ; Reached end before finding ':'

    cmp         byte [rdi], 0           ;Check end of our target UID string
je          .check_uid_delim    ; End of our UID string? Check if next char is ':'

cmp         byte [rdx], ':'     ; Found end of UID field in file?
    je          .uid_mismatch           ;If our UID wasn't finished, it's a mismatch

    mov         al, [rdx]               ;Compare chars
    cmp         al, [rdi]
    jne         .uid_mismatch           ;Mismatch found

    inc         rdx
    inc         rdi
    jmp         .uid_compare_loop

.check_uid_delim:
cmp         byte [rdx], ':'     ; Does the field in the file end here?
    jne         .uid_mismatch           ;No, longer UID in file or different char
    jmp         .found_match

.uid_mismatch:
.skip_line:
    cmp         rdx, rsi
    jge         .parse_error            ;Should have hit newline marker stored in rsi

    inc         rdx
    jmp         .skip_line              ;Implicitly handles moving past the newline via loop below

.parse_error:
    inc         rsi                     ;Move past newline (or current char if EOL not found yet)
    dec         rcx                     ;Decrement remaining chars count
    cmp         rcx, 0
    jle         .end_of_buffer          ;If buffer processed, read more
    jmp         .process_line_loop      ;Process next line in buffer

.end_of_buffer:
    jmp         .read_loop              ;Need more data

.found_match:
    mov         rax, 1                  ;syscall write
    mov         rdi, 1                  ;fd stdout
    lea         rsi, [rel username]     ;buffer with username
    mov         rdx, 0
    mov         r10, rsi

.calc_len_loop:
    cmp         byte [r10], 0
    je          .len_done

    inc         rdx
    inc         r10
    jmp         .calc_len_loop

.len_done:
    syscall

    mov         rax, 1
    mov         rdi, 1
    lea         rsi, [rel newline]
    mov         rdx, 1
    syscall

    mov         rax, 3                  ;syscall close
    mov         rdi, r14                ;file descriptor
    syscall

    jmp         .exit_success

.not_found:
    cmp         r14, 0
    jl          .exit_error             ;If FD is already negative (open failed), just exit

    mov         rax, 3                  ;syscall close
    mov         rdi, r14                ;file descriptor
    syscall

    jmp         .exit_error

.exit_success:
    exit 0

.exit_error:
    exit 1
