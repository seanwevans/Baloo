; src/hostid.asm

    %include "include/sysdefs.inc"

section .bss
    hostid_val  resd 1                  ;4 bytes to store hostid value (32-bit)
    hex_output  resb 8                  ;Buffer for hex string (8 characters for 32-bit)
    nl_char     resb 1                  ;Newline character
    file_buffer resb 16                 ;Buffer to read hostid file

section .data
    hex_chars   db "0123456789abcdef"   ;Lookup table for hex conversion
    path        db HOSTID_PATH, 0       ;Path to hostid file, null-terminated

section .text
global      _start

_start:
    mov         rax, SYS_GETHOSTID
    syscall

    test        eax, eax
    js          .try_file               ;If negative (error), try reading from file

    mov         [hostid_val], eax
    jmp         .convert_to_hex

.try_file:
    mov         rax, SYS_OPEN
    mov         rdi, path
    mov         rsi, O_RDONLY
    xor         rdx, rdx
    syscall

    test        rax, rax
    js          .use_default            ;If open failed, use default value

    mov         rdi, rax
    mov         rax, SYS_READ
    mov         rsi, file_buffer        ;Buffer to read into
    mov         rdx, 16                 ;Read up to 16 bytes
    syscall

    push        rax                     ;Save bytes read
    mov         rax, SYS_CLOSE
    syscall

    pop         rdx                     ;Restore bytes read
    test        rdx, rdx
    jle         .use_default            ;If read failed or empty file, use default

    xor         eax, eax                ;Clear eax
    mov         eax, [file_buffer]      ;Load first 4 bytes into eax
    mov         [hostid_val], eax
    jmp         .convert_to_hex

.use_default:
    mov         dword [hostid_val], 0x007f0101 ;127.0.0.1 in network byte order

.convert_to_hex:
    mov         rsi, hex_output         ;Destination buffer for hex string
    mov         rcx, 8                  ;Process 8 hex digits (32 bits)
    mov         eax, [hostid_val]       ;Load hostid value

.convert_loop:
    mov         rdx, rax                ;Copy current value to rdx
    and         rdx, 0Fh                ;Mask to get lowest 4 bits (single hex digit)
    mov         bl, [hex_chars + rdx]   ;Get corresponding hex character
    mov         [rsi + rcx - 1], bl     ;Store in output buffer (right to left)
    shr         rax, 4                  ;Shift right by 4 bits
    dec         rcx                     ;Move to next digit
    jnz         .convert_loop           ;Continue until all digits processed

    mov         byte [nl_char], 10      ;ASCII code for newline
    write       STDOUT_FILENO, hex_output, 8
    write       STDOUT_FILENO, nl_char, 1
    exit        0
