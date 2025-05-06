; src/users.asm

%include "include/sysdefs.inc"

section .data
    utmp_path   db "/var/run/utmp", 0   ; Path to the utmp file
    space       db " ", 0               ; Space delimiter between usernames
    newline     db 10, WHITESPACE_NL

section .bss
    utmp_buf    resb UTMP_SIZE          ; utmp record
    username    resb UT_NAMESIZE        ; username

section .text
    global      _start

_start:
    mov         rax, SYS_OPEN
    mov         rdi, utmp_path          ; Path to the file
    mov         rsi, O_RDONLY           ; Read-only
    xor         rdx, rdx
    syscall

    test        rax, rax
    js          exit_error              ; (error)

    mov         r15, rax

read_loop:
    mov         rax, SYS_READ
    mov         rdi, r15                ; File descriptor
    mov         rsi, utmp_buf           ; Buffer address
    mov         rdx, UTMP_SIZE          ; Read size
    syscall

    test        rax, rax
    jz          end_read                ; If zero bytes read, end of file
    js          exit_error              ; If negative, error occurred
    cmp         rax, UTMP_SIZE          ; Check if we read a full record
    jne         read_loop               ; If not, try reading again

    mov         ax, word [utmp_buf + UT_TYPE_OFF]
    cmp         ax, USER_PROCESS
    jne         read_loop               ; If not a user process, continue to next record

    mov         r12, 0                  ; track if we need a space before the username

    cmp         byte [username], 0
    je          first_username

    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, space
    mov         rdx, 1
    syscall
    
first_username:
    mov         rdi, username
    lea         rsi, [utmp_buf + UT_USER_OFF]
    mov         rcx, UT_NAMESIZE
    rep         movsb

    mov         rdi, username
    mov         rcx, UT_NAMESIZE
    xor         rax, rax
    cld
    repne       scasb                   ; Scan for NULL (0)
    mov         rdx, UT_NAMESIZE
    sub         rdx, rcx
    dec         rdx                     ; username length

    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, username
    syscall

    jmp         read_loop

end_read:
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, newline
    mov         rdx, 1
    syscall

    mov         rax, SYS_CLOSE
    mov         rdi, r15
    syscall

    exit        0

exit_error:
    exit        1
