; src/users.asm

    %include "include/sysdefs.inc"

section .bss
    utmp_buf    resb UTMP_SIZE          ;utmp record
    username    resb UT_NAMESIZE        ;username

section .data
    utmp_run    db "/run/utmp", 0       ;Modern utmp path
    utmp_path   db "/var/run/utmp", 0   ;Legacy utmp path
    space       db " ", 0               ;Space delimiter between usernames
    newline     db 10, WHITESPACE_NL

section .text
global      _start

_start:
    cmp         qword [rsp], 2
    jl          open_default_utmp
    mov         rdi, [rsp + 16]         ;Optional FILE argument
    jmp         open_selected_utmp

open_default_utmp:
    mov         rdi, utmp_run           ;Try modern path first
    call        try_open_utmp
    test        rax, rax
    jns         opened

    mov         rdi, utmp_path          ;Fall back to legacy path

open_selected_utmp:
    call        try_open_utmp
    test        rax, rax
    js          no_utmp                 ;No utmp -> no logged-in users
    jmp         opened

try_open_utmp:
    mov         rax, SYS_OPEN
    mov         rsi, O_RDONLY
    xor         rdx, rdx
    syscall
    ret

opened:
    mov         r15, rax

read_loop:
    mov         rax, SYS_READ
    mov         rdi, r15                ;File descriptor
    mov         rsi, utmp_buf           ;Buffer address
    mov         rdx, UTMP_SIZE          ;Read size
    syscall

    test        rax, rax
    jz          end_read                ;If zero bytes read, end of file
    js          exit_error              ;If negative, error occurred
    cmp         rax, UTMP_SIZE          ;Check if we read a full record
    jne         read_loop               ;If not, try reading again

    mov         ax, word [utmp_buf + UT_TYPE_OFF]
    cmp         ax, USER_PROCESS
    jne         read_loop               ;If not a user process, continue to next record

    mov         r12, 0                  ;track if we need a space before the username

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
    repne       scasb                   ;Scan for NULL (0)
    mov         rdx, UT_NAMESIZE
    sub         rdx, rcx
    test        rcx, rcx
    jz          write_username          ;full-width username without NUL
    dec         rdx                     ;exclude the NUL terminator

write_username:
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

no_utmp:
    exit        0
