; src/whoami.asm

    %include "include/sysdefs.inc"

section .bss
    file_buffer     resb 4096

section .data
    passwd_file     db "/etc/passwd", 0
    newline         db WHITESPACE_NL
error_open      db "whoami: cannot open /etc/passwd", 10
    error_open_len  equ $ - error_open

section .text
global          _start

_start:
    mov             rax, SYS_GETEUID
    syscall

    mov             r12d, eax
    mov             rax, SYS_OPEN
    mov             rdi, passwd_file    ;const char *pathname
    mov             rsi, 0              ;int flags (O_RDONLY)
    mov             rdx, 0              ;mode_t mode (unused for O_RDONLY)
    syscall

    cmp             rax, 0
    jl              .handle_open_error  ;If rax < 0, jump to error handler

    mov             r13, rax            ;Store file descriptor in r13 (callee-saved)

.read_loop:
    mov             rax, SYS_READ
    mov             rdi, r13            ;int fd
    mov             rsi, file_buffer    ;void *buf
    mov             rdx, 4096           ;size_t count (buffer size)
    syscall

    cmp             rax, 0
    jle             .close_and_exit_not_found ;If EOF or error, assume user not found yet

    mov             r14, file_buffer    ;Pointer to current position in buffer
    mov             r15, rax            ;Bytes remaining in the current buffer chunk

.process_line_loop:
    cmp             r15, 0
    jle             .read_loop          ;If no bytes left in this chunk, read more

    mov             rdi, r14            ;Start address for scanning (current position)
    mov             rcx, r15            ;Max number of bytes to scan (remaining bytes)
    mov             al, WHITESPACE_NL
    repne           scasb               ;Scan bytes in [RDI] until AL is found or RCX=0

    mov             rbx, r14            ;Start address of the current line

    mov             rdx, rdi            ;End address (points after \n or end of scan)
    sub             rdx, rbx            ;Length of scanned portion
    jz              .skip_empty_line    ;If length is 0 (e.g., consecutive newlines), skip

    jne             .handle_no_newline  ;If ZF=0, newline wasn't found in remaining buffer

    dec             rdx                 ;Adjust length to exclude the newline itself
    jmp             .parse_the_line

.handle_no_newline:

.parse_the_line:
    call            parse_passwd_line

    cmp rax, 0
    jne             .found_user         ;If rax != 0 (match found), jump to print routine


.skip_empty_line:
    mov             rcx, rdi            ;Pointer after the scanned line/newline
    sub             rcx, r14            ;Number of bytes processed in this iteration
    sub             r15, rcx            ;Decrease remaining bytes count for the buffer
    mov             r14, rdi            ;Advance buffer position pointer
    jmp             .process_line_loop  ;Process next line or read more data

.found_user:
    mov             rsi, rax            ;Arg 2 (*buf) for write syscall
    mov             rdx, r8             ;Arg 3 (count) for write syscall
    mov             rax, SYS_WRITE      ;Syscall number for write
    mov             rdi, 1              ;Arg 1 (fd = stdout)
    syscall

    mov             rax, SYS_WRITE
    mov             rdi, 1              ;fd = stdout
    mov             rsi, newline        ;*buf = address of newline character
    mov             rdx, 1              ;count = 1
    syscall

    mov             rdi, r13            ;File descriptor to close
    call            close_fd            ;Close the file
    exit            0

.close_and_exit_not_found:
    mov             rdi, r13            ;File descriptor to close
    call            close_fd
    exit            1

.handle_open_error:
    mov             rax, 1              ;Syscall number for write
    mov             rdi, 2              ;fd = stderr
    mov             rsi, error_open     ;*buf = error message
    mov             rdx, error_open_len ;count = length of message
    syscall

    exit            1

close_fd:
    mov             rax, SYS_CLOSE
    syscall
    ret

parse_passwd_line:
    push            rbx                 ;Preserve line start pointer
    mov             rdi, rbx            ;current position for searching
    mov             rcx, rdx            ;remaining length in line

mov             al, ':'             ; Character to find
repne           scasb               ; Scan for ':'
    je              .found_colon1
    jmp             .parse_fail         ;Colon not found - malformed line

.found_colon1:
    pop             r8                  ;Restore original line start pointer into R8 (username ptr)
    push            r8                  ;Push it back for later pop
    mov             r10, rdi            ;pointer after first colon
    dec             r10                 ;pointer at first colon
    sub             r10, r8             ;length of username

mov             al, ':'
    repne           scasb
    je              .found_colon2
    jmp             .parse_fail         ;Colon not found

.found_colon2:
    mov             rsi, rdi            ;start of UID field candidate
mov             al, ':'
    repne           scasb
    je              .found_colon3
    jmp             .parse_fail         ;Colon not found

.found_colon3:
    mov             r11, rdi            ;pointer after UID field's colon
    dec             r11                 ;points at UID field's colon
    sub             r11, rsi            ;length of UID string

    cmp             r11, 0              ;Check if UID field is empty
    je              .parse_fail

    mov             dl, byte [rsi + r11] ;Save the character at the end (the colon)
    mov             byte [rsi + r11], 0 ;Place null terminator

    call            atoi                ;Result (integer UID) is in RAX

    mov             byte [rsi + r11], dl


    cmp             eax, r12d           ;Compare lower 32 bits
    jne             .parse_no_match     ;If not equal, this is not the line we want

    pop             rax                 ;Get username start pointer (originally from rbx) into rax
    mov             r8, r10             ;Move username length (calculated earlier) into r8
    ret

.parse_no_match:
.parse_fail:
    pop             rbx                 ;Discard saved line start pointer
    xor             rax, rax            ;Return 0 in rax (no match / error)
    ret

atoi:
    xor             rax, rax            ;Accumulator = 0
    xor             rdx, rdx            ;Clear rdx for 64-bit multiply later if needed (optional here)

.atoi_loop:
    movzx           cx, byte [rsi]      ;Get character (byte) into 16 bits, zero-extend rest
    cmp             cl, '0'
    jl              .atoi_done          ;If < '0', done (not a digit)

    cmp             cl, '9'
    jg              .atoi_done          ;If > '9', done (not a digit)

    sub             cl, '0'             ;Convert character to integer 0-9

    push            rdx                 ;Save rdx if needed elsewhere (mul uses it)
    mov             rdx, 10
    mul             rdx                 ;rax = rax * 10
    pop             rdx                 ;Restore rdx

    add             rax, rcx            ;Add the new digit value (rcx is zero-extended cl)

    inc             rsi                 ;Move to next character
    jmp             .atoi_loop

.atoi_done:
    ret
