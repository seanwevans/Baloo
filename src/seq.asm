; src/seq.asm

    %include "include/sysdefs.inc"

section .bss
    num_buffer      resb 32             ;Buffer for number conversion
    buffer          resb 1024           ;General purpose buffer
    arg_count       resq 1              ;Number of arguments
    first_num       resq 1              ;First number in sequence
    increment_num   resq 1              ;Increment value
    last_num        resq 1              ;Last number in sequence
    current_num     resq 1              ;Current number to print

section .data
    decimal_base    dq 10
usage_msg       db "Usage: seq [FIRST [INCREMENT]] LAST", 10
    usage_len       equ $ - usage_msg
overflow_msg    db "Error: Number too large", 10
    overflow_len    equ $ - overflow_msg
    newline         db WHITESPACE_NL
    default_first   dq 1
    default_incr    dq 1


section .text
global          _start

_start:

    pop             r8                  ;argc
    dec             r8
    mov             [arg_count], r8     ;Store number of actual arguments
    pop             rdi
    mov             rax, [default_first] ;Default first = 1
    mov             [first_num], rax
    mov             rax, [default_incr] ;Default increment = 1
    mov             [increment_num], rax
    cmp             qword [arg_count], 0 ;Check if no args
    je              print_usage

cmp             qword [arg_count], 1    ; One arg: seq LAST
    je              one_arg

cmp             qword [arg_count], 2    ; Two args: seq FIRST LAST
    je              two_args

cmp             qword [arg_count], 3    ; Three args: seq FIRST INCREMENT LAST
    je              three_args

    jmp             print_usage         ;Too many args

one_arg:
    pop             rdi                 ;Get LAST from stack
    call            parse_number

    mov             [last_num], rax
    jmp             start_sequence

two_args:
    pop             rdi                 ;Get FIRST from stack
    call            parse_number

    mov             [first_num], rax
    pop             rdi                 ;Get LAST from stack
    call            parse_number

    mov             [last_num], rax
    jmp             start_sequence

three_args:

    pop             rdi                 ;Get FIRST from stack
    call            parse_number

    mov             [first_num], rax
    pop             rdi                 ;Get INCREMENT from stack
    call            parse_number

    mov             [increment_num], rax

    pop             rdi                 ;Get LAST from stack
    call            parse_number

    mov             [last_num], rax

start_sequence:
    mov             rax, [first_num]
    mov             [current_num], rax
    mov             rcx, [increment_num]
    or              rcx, rcx            ;Test if increment is zero
    jz              print_usage         ;Increment can't be zero

sequence_loop:
    mov             rcx, [increment_num]
    cmp             rcx, 0
    jg              check_ascending     ;If increment > 0, check ascending
    jl              check_descending    ;If increment < 0, check descending

check_ascending:
    mov             rax, [current_num]
    cmp             rax, [last_num]
    jg              end_program         ;If current > last, we're done
    jmp             print_number

check_descending:
    mov             rax, [current_num]
    cmp             rax, [last_num]
    jl              end_program         ;If current < last, we're done

print_number:
    mov             rax, [current_num]
    call            print_int

    write           STDOUT_FILENO, newline, 1

    mov             rax, [current_num]
    add             rax, [increment_num]
    mov             [current_num], rax
    jmp             sequence_loop       ;Continue loop

print_usage:
    write           STDOUT_FILENO, usage_msg, usage_len
    exit            1

print_overflow:
    write           STDOUT_FILENO, overflow_msg, overflow_len
    exit            1

end_program:
    exit            0

parse_number:
    xor             rax, rax            ;Initialize result to 0
    xor             rcx, rcx            ;Initialize character counter
    xor             r8, r8              ;Initialize sign flag (0 = positive)

    movzx           rbx, byte [rdi]     ;Load first character
    cmp             bl, '-'             ;Check for minus sign
    jne             check_plus

    mov             r8, 1               ;Set sign flag to negative
    inc             rdi                 ;Move to next character
    jmp             parse_loop

check_plus:
    cmp             bl, '+'             ;Check for plus sign
    jne             parse_loop

    inc             rdi                 ;Move to next character

parse_loop:
    movzx           rbx, byte [rdi]     ;Load character
    cmp             bl, 0               ;Check for null terminator
    je              parse_done

    cmp             bl, '0'             ;Check if below '0'
    jb              parse_error

    cmp             bl, '9'             ;Check if above '9'
    ja              parse_error

    sub             bl, '0'             ;Convert character to digit
    imul            rax, 10             ;Multiply current result by 10
    jo              print_overflow      ;Check for overflow

    add             rax, rbx            ;Add digit
    jo              print_overflow      ;Check for overflow

    inc             rdi                 ;Move to next character
    jmp             parse_loop

parse_error:
    jmp             print_usage

parse_done:
    cmp             r8, 1
    jne             parse_return
    neg             rax

parse_return:
    ret

print_int:
    mov             rbx, num_buffer     ;Point to end of buffer
    add             rbx, 31             ;Last byte for null terminator
    mov             byte [rbx], 0       ;Add null terminator
    dec             rbx                 ;Move to position for last digit
    mov             rcx, 0              ;Flag for negative number
    cmp             rax, 0
    jge             convert_digits      ;Skip if positive

    neg             rax                 ;Make positive
    mov             rcx, 1              ;Set negative flag

convert_digits:
    mov             rdx, 0              ;Clear for division
    div             qword [decimal_base] ;Divide by 10, remainder in RDX
    add             dl, '0'             ;Convert remainder to ASCII
    mov             [rbx], dl           ;Store in buffer
    dec             rbx                 ;Move buffer pointer
    test            rax, rax            ;Check if quotient is zero
    jnz             convert_digits      ;If not, continue loop

    cmp             rcx, 1              ;Check negative flag
    jne             print_digits        ;Skip if positive
    mov             byte [rbx], '-'     ;Add minus sign
    dec             rbx                 ;Move buffer pointer

print_digits:
    inc             rbx                 ;Adjust to start of string
    mov             rdx, num_buffer     ;Get buffer address
    add             rdx, 31             ;Last byte position
    sub             rdx, rbx            ;Calculate length
    write           STDOUT_FILENO, rbx, rdx
    ret
