; src/tr.asm

    %include "include/sysdefs.inc"

section .bss
    buffer      resb buffer_size        ;I/O buffer
    char_map    resb 256                ;Translation map (one byte per possible character)
    delete_flag resb 1                  ;Flag for delete mode
    set1        resb 256                ;First character set
    set2        resb 256                ;Second character set
    set1_len    resq 1                  ;Length of SET1
    set2_len    resq 1                  ;Length of SET2

section .data
usage_msg   db "Usage: tr [-d] SET1 [SET2]", 10, 0
    usage_len   equ $ - usage_msg
    buffer_size equ 4096                ;Size of the I/O buffer

section .text
global      _start

_start:
    mov         rcx, 0

init_map_loop:
    mov         [char_map + rcx], cl    ;Map character to itself
    inc         rcx
    cmp         rcx, 256
    jl          init_map_loop

    mov         byte [delete_flag], 0

    pop         rcx                     ;argc
    cmp         rcx, 1                  ;Check if we have at least one argument
    jle         show_usage              ;If not, show usage and exit

    pop         rdi
    pop         rdi                     ;Get argv[1]
    cmp         rcx, 1                  ;If we only have program name
    je          show_usage              ;Show usage and exit

    cmp         byte [rdi], '-'
    jne         set1_arg                ;If not, it's SET1

    cmp         byte [rdi + 1], 'd'
    jne         show_usage              ;If not -d, show usage
    cmp         byte [rdi + 2], 0       ;Ensure it's exactly "-d"
    jne         show_usage

    mov         byte [delete_flag], 1

    dec         rcx
    cmp         rcx, 2                  ;Need at least SET1
    jl          show_usage

    pop         rdi
    jmp         process_set1

set1_arg:
process_set1:
    mov         rsi, set1
    call        copy_string

    mov         [set1_len], rax
    dec         rcx
    cmp         rcx, 1                  ;Check if we have another argument
    jl          check_delete_mode       ;If not, check if we're in delete mode

    pop         rdi
    mov         rsi, set2
    call        copy_string
    mov         [set2_len], rax
    call        build_translation_map

    jmp         translate_input

check_delete_mode:
    cmp         byte [delete_flag], 1
    je          translate_input         ;In delete mode, we only need SET1

    jmp         show_usage

translate_input:
read_next_chunk:
    mov         rax, SYS_READ
    mov         rdi, STDIN_FILENO
    mov         rsi, buffer
    mov         rdx, buffer_size
    syscall

    cmp         rax, 0
    jle         exit_success            ;EOF or error, exit

    mov         rcx, 0                  ;Initialize index
    mov         rbx, 0                  ;Initialize write index (for delete mode)

process_byte_loop:
    movzx       rdx, byte [buffer + rcx] ;Get the current byte
    movzx       rdx, byte [char_map + rdx]
    cmp         byte [delete_flag], 1
    je      delete_check

    mov         [buffer + rbx], dl
    inc         rbx
    jmp         next_byte

delete_check:
    cmp         dl, 0FFh                ;0xFF is our marker for deletion
    je          next_byte               ;Skip byte if it should be deleted

    mov         [buffer + rbx], dl
    inc         rbx

next_byte:
    inc         rcx
    cmp         rcx, rax                ;Check if we've processed all bytes
    jl          process_byte_loop

    mov         rdx, rbx                ;Number of bytes to write
    cmp         rdx, 0
    je          read_next_chunk         ;Nothing to write, read next chunk

    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, buffer
    syscall

    cmp         rax, 0
    jl          exit_error              ;Write error

    jmp         read_next_chunk         ;Process next chunk

exit_success:
    exit        0

show_usage:
    write       STDERR_FILENO, usage_msg, usage_len
    exit        1

exit_error:
    exit        2

copy_string:
    push        rcx
    push        rdi
    push        rsi

    mov         rcx, 0                  ;Initialize counter
copy_loop:
    mov         al, [rdi + rcx]
    cmp         al, 0
    je          copy_done

    mov         [rsi + rcx], al
    inc         rcx
    cmp         rcx, 255                ;Limit to 255 characters
    jl          copy_loop

copy_done:
    mov         [rsi + rcx], byte 0     ;Null-terminate the copy
    mov         rax, rcx
    pop         rsi
    pop         rdi
    pop         rcx
    ret

build_translation_map:
    push        rbx
    push        rcx
    push        rdx
    push        rsi
    push        rdi
    cmp         byte [delete_flag], 1
    je          build_delete_map

    mov         rcx, 0                  ;Index into SET1
    mov         rsi, set1
    mov         rdi, set2
    mov         rbx, [set1_len]
    mov         rdx, [set2_len]

translate_map_loop:
    cmp         rcx, rbx                ;Check if we've processed all of SET1
    jge         build_map_done

    movzx       rax, byte [rsi + rcx]   ;Get character from SET1
    cmp         rcx, rdx                ;Check if we've exhausted SET2
    jl          use_set2_char

    dec         rdx
    movzx       rdi, byte [set2 + rdx]
    jmp         set_map_entry

use_set2_char:
    movzx       rdi, byte [set2 + rcx]  ;Get character from SET2

set_map_entry:
    mov         [char_map + rax], dil   ;Map SET1 char to SET2 char

    inc         rcx
    jmp         translate_map_loop

build_delete_map:
    mov         rcx, 0                  ;Index into SET1
    mov         rsi, set1
    mov         rbx, [set1_len]

delete_map_loop:
    cmp         rcx, rbx                ;Check if we've processed all of SET1
    jge         build_map_done

    movzx       rax, byte [rsi + rcx]   ;Get character from SET1
    mov         byte [char_map + rax], 0FFh ;Mark for deletion
    inc         rcx
    jmp         delete_map_loop

build_map_done:
    pop         rdi
    pop         rsi
    pop         rdx
    pop         rcx
    pop         rbx
    ret
