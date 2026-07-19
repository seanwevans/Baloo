; src/factor.asm

    %include "include/sysdefs.inc"

section .bss
    buffer      resb 4096               ;Input buffer
    num_buffer  resb 32                 ;conversion buffer
    num         resq 1                  ;number to factorize

section .data
    space       db WHITESPACE_SPACE
colon       db ":"
    newline     db WHITESPACE_NL
    error_msg   db "Invalid input", WHITESPACE_NL
    error_len   equ $ - error_msg


section .text
global      _start

_start:
    mov         r14, [rsp]              ;argc
    lea         r15, [rsp + 16]         ;&argv[1]
    cmp         r14, 1
    je          read_from_stdin         ;If argc == 1, read from stdin

    dec         r14                     ;number of operands
args_loop:
    cmp         r14, 0
    je          exit_ok
    mov         rsi, [r15]              ;argv[i]
    call        factor_one
    add         r15, 8
    dec         r14
    jmp         args_loop

read_from_stdin:
    mov         rax, SYS_READ
    mov         rdi, STDIN_FILENO
    mov         rsi, buffer
    mov         rdx, 4095
    syscall

    cmp         rax, 0
    jle         exit_ok

    mov         byte [buffer + rax], 0  ;NUL-terminate input
    mov         rsi, buffer             ;Input buffer

stdin_loop:
    call        skip_ws
    cmp         byte [rsi], 0
    je          exit_ok
    call        factor_one
    jmp         stdin_loop

skip_ws:
    movzx       rax, byte [rsi]
    cmp         al, WHITESPACE_SPACE
    je          .adv
    cmp         al, WHITESPACE_TAB
    je          .adv
    cmp         al, WHITESPACE_NL
    je          .adv
    ret
.adv:
    inc         rsi
    jmp         skip_ws

; factor_one: parse a number at [rsi], print "N: factors", advance rsi.
factor_one:
    push        r14
    push        r15
    xor         r8, r8                  ;Initialize number to 0

parse_loop:
    movzx       rax, byte [rsi]         ;Get character
    cmp         al, WHITESPACE_SPACE
    je          parse_done
    cmp         al, WHITESPACE_TAB
    je          parse_done
    cmp         al, WHITESPACE_NL
    je          parse_done
    cmp         al, 0                   ;Check for null terminator
    je          parse_done

    sub         al, '0'
    cmp         al, 10
    jae         error_exit              ;Not a digit

    imul        r8, 10                  ;Multiply by 10
    add         r8, rax                 ;Add current digit
    inc         rsi                     ;Next character
    jmp         parse_loop

parse_done:
    mov         [num], r8
    mov         r15, rsi                ;Preserve input cursor

    mov         rax, r8
    call        print_num

    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, colon
    mov         rdx, 1
    syscall

    mov         rax, [num]              ;Get the number
    cmp         rax, 2
    jb          special_case

    mov         rbx, 2                  ;First potential factor

factor_loop:
    cmp         rax, 1
    je          done

    mov         rdx, 0                  ;Clear remainder
    div         rbx                     ;RAX = RAX / RBX, RDX = remainder

    cmp         rdx, 0
    jne         try_next_factor         ;If remainder is not 0, try next factor

    push        rax                     ;Save quotient
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, space              ;Separator precedes each factor
    mov         rdx, 1
    syscall

    mov         rax, rbx                ;Load factor to print
    call        print_num               ;Print the factor

    pop         rax                     ;Restore quotient
    jmp         factor_loop             ;Try this factor again

try_next_factor:
    imul        rax, rbx                ;Multiply quotient by divisor
    add         rax, rdx                ;Add remainder to get original number

    add         rbx, 1

    cmp         rax, rbx
    jl          done                    ;If number < current factor, we're done

    cmp         rax, 1
    je          done                    ;If 1, we're done

    mov         rcx, rax
    mov         r9, rcx                 ;Save original number

    mov         r10, 1                  ;Lower bound
    mov         r11, rcx                ;Upper bound
    shr         r11, 1                  ;Start with n/2 as upper bound

sqrt_loop:
    cmp         r10, r11
    ja          sqrt_done               ;If lower > upper, we're done

    mov         rcx, r10
    add         rcx, r11
    shr         rcx, 1                  ;mid = (lower + upper) / 2
    mov         rax, rcx
    mul         rax                     ;rax = mid * mid
    cmp         rax, r9
    jbe         sqrt_lower_or_equal     ;if mid*mid <= n

    lea         r11, [rcx - 1]
    jmp         sqrt_loop

sqrt_lower_or_equal:
    je          sqrt_done

    lea         r10, [rcx + 1]
    jmp         sqrt_loop

sqrt_done:
    mov         rax, r9                 ;Restore original number
    cmp         rbx, rcx
    jbe         factor_loop             ;Continue if factor <= sqrt(n)

    push        rax                     ;Save remaining prime
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, space              ;Separator precedes each factor
    mov         rdx, 1
    syscall
    pop         rax                     ;Restore remaining prime

    call        print_num               ;Print the remaining prime
    jmp         done

special_case:
    mov         rax, [num]
    cmp         rax, 1                  ;0 and 1 have no prime factors
    jb          done
    ja          done
    push        rax
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, space
    mov         rdx, 1
    syscall
    pop         rax
    call        print_num

done:
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, newline
    mov         rdx, 1
    syscall

    mov         rsi, r15                ;Restore input cursor
    pop         r15
    pop         r14
    ret

exit_ok:
    exit        0

error_exit:
    write       STDERR_FILENO, error_msg, error_len
    exit        1

print_num:
    push        rbp
    mov         rbp, rsp
    push        rax                     ;Save number
    push        rbx
    push        rcx
    push        rdx
    push        r8
    mov         rcx, num_buffer         ;Buffer to store digits
    add         rcx, 31                 ;Start from end of buffer
    mov         byte [rcx], 0           ;Null terminator
    dec         rcx
    mov         rbx, 10                 ;Divisor
    cmp         rax, 0
    jne         convert_loop
    mov         byte [rcx], '0'
    dec         rcx
    jmp         print_convert_done

convert_loop:
    mov         rdx, 0                  ;Clear upper part for division
    div         rbx                     ;RAX = RAX / 10, RDX = remainder
    add         dl, '0'                 ;Convert remainder to ASCII
    mov         [rcx], dl               ;Store digit
    dec         rcx                     ;Move buffer pointer
    cmp         rax, 0                  ;Check if done
    jne         convert_loop

print_convert_done:

    mov         r8, num_buffer
    add         r8, 31                  ;End of buffer
    inc         rcx                     ;Point to first digit
    sub         r8, rcx                 ;Length = end - first digit

    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, rcx
    mov         rdx, r8
    syscall

    pop         r8
    pop         rdx
    pop         rcx
    pop         rbx
    pop         rax
    pop         rbp
    ret
