; src/file.asm

    %include "include/sysdefs.inc"

section .bss
buffer:         resb 4096   ; file content buffer
filename:       resb 256    ; filename buffer
stat_buf:       resb 144    ; stat buffer

section .data
usage_msg       db "Usage: file [file]...", 10, 0
    usage_len       equ $ - usage_msg
error_open      db "Error: Cannot open file ", 0
    error_open_len  equ $ - error_open
colon_space     db ": ", 0
    colon_len       equ $ - colon_space
    newline         db 10, 0
    newline_len     equ $ - newline
    type_ascii      db "ASCII text", 0
    type_ascii_len  equ $ - type_ascii
    type_utf8       db "UTF-8 text", 0
    type_utf8_len   equ $ - type_utf8
    type_elf        db "ELF executable", 0
    type_elf_len    equ $ - type_elf
    type_shebang    db "script text executable", 0
    type_shebang_len equ $ - type_shebang
    type_empty      db "empty", 0
    type_empty_len  equ $ - type_empty
    type_data       db "data", 0
    type_data_len   equ $ - type_data
    elf_magic       db 0x7F, "ELF", 0

section .text
global          _start

_start:
    pop             rcx                 ;argc
    cmp             rcx, 1
    je              print_usage         ;If no arguments, print usage

    pop             rdi                 ;Skip program name
    dec             rcx                 ;Decrement argc to get the actual argument count
    jmp             process_args        ;Start processing arguments

print_usage:
    write           STDERR_FILENO, usage_msg, usage_len
    exit            1

process_args:
    cmp             rcx, 0              ;Check if all arguments have been processed
    je              exit_success        ;If all processed, exit successfully

    pop             rdi                 ;Get the next argument (filename)
mov             rsi, rdi        ; Source: argument string
mov             rdi, filename   ; Destination: filename buffer
    call            copy_str            ;Copy the string

    push            rcx                 ;Save argument counter before function call
    mov             rdi, filename       ;Set filename for open syscall
    call            process_file        ;Process the file
    pop             rcx                 ;Restore argument counter
    dec             rcx                 ;Decrement the argument counter
    jmp             process_args        ;Process the next argument

process_file:
    mov             rax, SYS_OPEN
    mov             rdi, filename       ;filename
mov             rsi, O_RDONLY   ; flags: O_RDONLY
    xor             rdx, rdx
    syscall

    cmp             rax, 0
    jl              open_error

    mov             r12, rax            ;Save fd
mov             rax, SYS_STAT   ; syscall: stat
    mov             rdi, filename       ;filename
    mov             rsi, stat_buf       ;stat buffer
    syscall

    cmp             rax, 0              ;Check if stat failed
    jl              close_file          ;Handle error by closing file

    mov             rdi, filename
    call            print_str

    write           STDOUT_FILENO, colon_space, colon_len

    mov             rax, [stat_buf + 48] ;stat_buf.st_size (offset 48 in struct stat)
    cmp             rax, 0              ;Compare with 0
    je              empty_file          ;If empty, handle it

mov             rax, SYS_READ   ; syscall: read
    mov             rdi, r12            ;fd
    mov             rsi, buffer         ;buffer
mov             rdx, 4096       ; count: read up to 4096 bytes
    syscall

    cmp             rax, 0              ;Check if read failed or EOF
    jle             close_file          ;Handle error or empty file

    mov             r13, rax

    cmp             dword [buffer], 0x464C457F ;Check if file starts with 0x7F followed by "ELF"
    je              elf_file

    cmp             word [buffer], 0x2123 ;Check if file starts with "#!"
    je              shebang_file

    call            is_ascii

    cmp             rax, 0              ;If is_ascii returned 0, it's not text
    je              data_file           ;Not text, treat as data

    cmp             rax, 1              ;If is_ascii returned 1, it's ASCII
    je              ascii_file

    cmp             rax, 2              ;If is_ascii returned 2, it's UTF-8
    je              utf8_file

    jmp             data_file

empty_file:
    write           STDOUT_FILENO, type_empty, type_empty_len
    jmp             print_newline

elf_file:
    write           STDOUT_FILENO, type_elf, type_elf_len
    jmp             print_newline

shebang_file:
    write           STDOUT_FILENO, type_shebang, type_shebang_len
    jmp             print_newline

ascii_file:
    write           STDOUT_FILENO, type_ascii, type_ascii_len
    jmp             print_newline

utf8_file:
    write           STDOUT_FILENO, type_utf8, type_utf8_len
    jmp             print_newline

data_file:
    write           STDOUT_FILENO, type_data, type_data_len
    jmp             print_newline

print_newline:
    write           STDOUT_FILENO, newline, newline_len

close_file:
    mov             rax, SYS_CLOSE
    mov             rdi, r12
    syscall
    ret

open_error:
    write           STDERR_FILENO, error_open, error_open_len

    mov             rdi, filename
    call            print_str

    write           STDERR_FILENO, newline, newline_len
    exit            1

exit_success:
    exit            0

print_str:
    push            rdi                 ;Save rdi
    push            rcx                 ;Save rcx (might be used outside)
    mov             rdx, 0              ;Initialize length counter

count_loop:
    cmp             byte [rdi], 0       ;Check for null terminator
    je              done_counting       ;If found, counting is done
    inc             rdi                 ;Move to next character
    inc             rdx                 ;Increment length counter
    jmp             count_loop          ;Continue counting

done_counting:
    pop             rcx                 ;Restore rcx
    pop             rsi                 ;Restore original string pointer into rsi
    mov             rax, SYS_WRITE
    mov             rdi, STDOUT_FILENO
    syscall
    ret

copy_str:
    push            rdi                 ;Save destination pointer
    push            rcx                 ;Save rcx (might be used outside)

copy_loop:
    mov             al, byte [rsi]      ;Get character from source
    mov             byte [rdi], al      ;Copy to destination
    cmp             al, 0               ;Check if null terminator
    je              copy_done           ;If so, we're done
    inc             rsi                 ;Next source character
    inc             rdi                 ;Next destination position
    jmp             copy_loop           ;Continue copying

copy_done:
    pop             rcx                 ;Restore rcx
    pop             rdi                 ;Restore original destination pointer
    ret

is_ascii:
    mov             rcx, r13            ;Load size of data
    xor             rsi, rsi            ;Initialize counter
    xor             r14, r14            ;Clear UTF-8 flag

ascii_loop:
    cmp             rsi, rcx            ;Check if we've gone through all bytes
    je              check_utf8          ;If so, check if we detected UTF-8

    mov             al, byte [buffer + rsi] ;Load byte

    cmp             al, 32              ;Is it less than space?
    jb              check_special       ;If yes, check if it's a special character

    test            al, 0x80            ;Is high bit set? (non-ASCII)
    jnz             check_utf8_byte     ;If so, might be UTF-8

    cmp             al, 127             ;Is it DEL?
    je              ascii_no            ;DEL is not considered text

next_byte:
    inc             rsi                 ;Move to next byte
    jmp             ascii_loop          ;Continue checking

check_special:
    cmp             al, 9               ;Is it a tab?
    je              next_byte
    cmp             al, 10              ;Is it a newline?
    je              next_byte
    cmp             al, 13              ;Is it a carriage return?
    je              next_byte

    jmp             ascii_no

check_utf8_byte:
    mov             r14, 1              ;Mark as potentially UTF-8

    mov             r15b, al            ;Copy byte to r15b
    and             r15b, 0xE0          ;Mask out all but top 3 bits
    cmp             r15b, 0xC0          ;Is it 110xxxxx? (2-byte sequence)
    je              utf8_2bytes

    mov             r15b, al            ;Copy byte to r15b again
    and             r15b, 0xF0          ;Mask out all but top 4 bits
    cmp             r15b, 0xE0          ;Is it 1110xxxx? (3-byte sequence)
    je              utf8_3bytes

    mov             r15b, al            ;Copy byte again
    and             r15b, 0xF8          ;Mask out all but top 5 bits
    cmp             r15b, 0xF0          ;Is it 11110xxx? (4-byte sequence)
    je              utf8_4bytes

    jmp             ascii_no

utf8_2bytes:
    inc             rsi
    cmp             rsi, rcx            ;Check if we've reached the end
    jge             ascii_no            ;Not enough bytes for a valid sequence

    mov             al, byte [buffer + rsi]
    and             al, 0xC0            ;Mask out all but top 2 bits
    cmp             al, 0x80            ;Is it 10xxxxxx?
    jne             ascii_no            ;Not a valid continuation byte

    jmp             next_byte

utf8_3bytes:
    inc             rsi
    cmp             rsi, rcx            ;Check if we've reached the end
    jge             ascii_no            ;Not enough bytes for a valid sequence

    mov             al, byte [buffer + rsi]
    and             al, 0xC0            ;Mask out all but top 2 bits
    cmp             al, 0x80            ;Is it 10xxxxxx?
    jne             ascii_no            ;Not a valid continuation byte

    inc             rsi
    cmp             rsi, rcx            ;Check if we've reached the end
    jge             ascii_no            ;Not enough bytes for a valid sequence

    mov             al, byte [buffer + rsi]
    and             al, 0xC0            ;Mask out all but top 2 bits
    cmp             al, 0x80            ;Is it 10xxxxxx?
    jne             ascii_no            ;Not a valid continuation byte

    jmp             next_byte

utf8_4bytes:
    inc             rsi
    cmp             rsi, rcx            ;Check if we've reached the end
    jge             ascii_no            ;Not enough bytes for a valid sequence

    mov             al, byte [buffer + rsi]
    and             al, 0xC0            ;Mask out all but top 2 bits
    cmp             al, 0x80            ;Is it 10xxxxxx?
    jne             ascii_no            ;Not a valid continuation byte

    inc             rsi
    cmp             rsi, rcx            ;Check if we've reached the end
    jge             ascii_no            ;Not enough bytes for a valid sequence

    mov             al, byte [buffer + rsi]
    and             al, 0xC0            ;Mask out all but top 2 bits
    cmp             al, 0x80            ;Is it 10xxxxxx?
    jne             ascii_no            ;Not a valid continuation byte

    inc             rsi
    cmp             rsi, rcx            ;Check if we've reached the end
    jge             ascii_no            ;Not enough bytes for a valid sequence

    mov             al, byte [buffer + rsi]
    and             al, 0xC0            ;Mask out all but top 2 bits
    cmp             al, 0x80            ;Is it 10xxxxxx?
    jne             ascii_no            ;Not a valid continuation byte

    jmp             next_byte

check_utf8:
    cmp             r14, 1              ;Did we see UTF-8?
    je              utf8_yes            ;If yes, it's UTF-8

    mov             rax, 1              ;Return 1 (is ASCII)
    ret

utf8_yes:
    mov             rax, 2              ;Return 2 (is UTF-8)
    ret

ascii_no:
    mov             rax, 0              ;Return 0 (not text)
    ret
