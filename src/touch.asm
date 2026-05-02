; src/touch.asm

    %include "include/sysdefs.inc"

section .bss
    buffer          resb 4096           ;Buffer for filename
    stat_buf        resb 144            ;Stat buffer (struct stat)

section .data
usage_msg       db "Usage: touch FILE...", 10, 0
error_msg       db "Error: Cannot touch ", 0
    newline         db 10, 0

section .text
global          _start

_start:
    pop             rcx                 ;Get argc
    pop             rdx                 ;Skip argv[0] (program name)
    dec             rcx                 ;Decrease argc by 1
    cmp             rcx, 0              ;Check if no arguments were provided
    jg              process_args        ;If we have arguments, process them

    write           STDOUT_FILENO, usage_msg, 22
    exit            1

process_args:
    pop             rdi                 ;Get next argument (filename)
    call            touch_file          ;Touch the file

    dec             rcx                 ;Decrease argument counter
    jnz             process_args        ;If more arguments, continue processing

    exit            0                   ;Exit with success code

touch_file:
    push            rcx                 ;Save registers we'll use
    push            rdi                 ;Save filename pointer
    push            rdx
    mov             rax, SYS_OPEN

    mov             rsi, O_RDWR         ;Open for reading and writing
    syscall

    cmp             rax, 0              ;Check if file was opened successfully
    jl              create_file         ;If not, try to create it

    mov             rdi, rax            ;File descriptor is now in rax
    mov             rax, SYS_CLOSE
    syscall

    pop             rdx                 ;Restore rdx
    pop             rdi                 ;Restore filename pointer
    push            rdi                 ;Save it again for update_timestamp
    push            rdx                 ;Save rdx again
    jmp             update_timestamp

create_file:
    pop             rdx                 ;Restore rdx
    pop             rdi                 ;Restore filename pointer
    push            rdi                 ;Save it again for later
    push            rdx                 ;Save rdx again
    mov             rax, SYS_OPEN
    mov             rsi, O_WRONLY | O_CREAT ;Create for writing
    mov             rdx, DEFAULT_MODE   ;File permissions (0644)
    syscall

    cmp             rax, 0              ;Check if file was created successfully
    jl              handle_error        ;If not, handle error

    mov             rdi, rax            ;File descriptor
    mov             rax, SYS_CLOSE
    syscall

update_timestamp:
    pop             rdx                 ;Restore rdx
    pop             rdi                 ;Restore filename pointer
    push            rdi                 ;Save filename again in case of error
    push            rdx                 ;Save rdx again

    mov             rax, SYS_UTIMENSAT
    mov             rdi, AT_FDCWD       ;Use current directory
    mov             rsi, rdi
    pop             rdx                 ;Restore rdx temporarily
    pop             rsi                 ;Get filename into rsi
    push            rsi                 ;Save filename again
    push            rdx                 ;Save rdx again
    xor             rdx, rdx            ;NULL timespec means use current time
    xor             r10, r10            ;No flags
    syscall

    cmp             rax, 0              ;Check for errors
    jl              handle_error        ;If error, handle it

    pop             rdx                 ;Restore registers
    pop             rdi                 ;Clean up saved filename
    pop             rcx
    ret

handle_error:
    write           STDERR_FILENO, error_msg, 20

    pop             rdx                 ;Restore rdx
    pop             rdi                 ;Get filename for error message
    mov             rcx, -1             ;Set counter to max
    xor             al, al              ;Search for null byte
    mov             rsi, rdi            ;Save start pointer
    repne           scasb               ;Scan until null byte
    not             rcx                 ;Invert count
    dec             rcx                 ;Remove null byte from count
    write           STDERR_FILENO, rsi, rcx

    write           STDERR_FILENO, newline, 1

    pop             rcx                 ;Restore rcx
    ret
