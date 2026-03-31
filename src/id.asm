; src/id.asm

%include "include/sysdefs.inc"

section .bss
    groups_buf      resd 32     ; 32-bit group IDs
    numbuf          resb 16     ; for printing numbers

section .data
    newline         db 10
    uid_prefix      db "uid=", 0
    gid_prefix      db " gid=", 0
    groups_prefix   db " groups=", 0
    comma           db ",", 0
    space           db " ", 0

section .text
    global          _start

_start:
    mov             rbx, [rsp]          ; argc
    cmp             rbx, 2
    jl              .mode_default

    mov             rdi, [rsp + 16]     ; argv[1]
    call            parse_mode
    cmp             al, 'u'
    je              .mode_u
    cmp             al, 'g'
    je              .mode_g
    cmp             al, 'G'
    je              .mode_G

.mode_default:
    mov             rdi, uid_prefix
    call            write_str
    call            get_euid
    mov             rdi, rax
    call            print_num

    mov             rdi, gid_prefix
    call            write_str
    call            get_egid
    mov             rdi, rax
    call            print_num

    call            get_groups_count
    test            rax, rax
    je              .done
    mov             r13, rax

    mov             rdi, groups_prefix
    call            write_str

    mov             rdi, r13
    mov             rsi, comma
    mov             rdx, 1
    call            print_groups_with_sep
    jmp             .done

.mode_u:
    call            get_euid
    mov             rdi, rax
    call            print_num
    jmp             .done

.mode_g:
    call            get_egid
    mov             rdi, rax
    call            print_num
    jmp             .done

.mode_G:
    call            get_groups_count
    mov             rdi, rax
    mov             rsi, space
    mov             rdx, 1
    call            print_groups_with_sep

.done:
    call            write_newline
    exit            0

parse_mode:
    mov             al, 0
    cmp             byte [rdi], '-'
    jne             .ret
    cmp             byte [rdi + 2], 0
    jne             .ret
    mov             al, [rdi + 1]
    cmp             al, 'u'
    je              .ret
    cmp             al, 'g'
    je              .ret
    cmp             al, 'G'
    je              .ret
    xor             eax, eax
.ret:
    ret

get_euid:
    mov             rax, SYS_GETEUID
    syscall
    ret

get_egid:
    mov             rax, SYS_GETEGID
    syscall
    ret

get_groups_count:
    mov             rax, SYS_GETGROUPS
    mov             rdi, 32
    mov             rsi, groups_buf
    syscall
    test            rax, rax
    js              .none
    cmp             rax, 32
    jle             .ret
    mov             rax, 32
.ret:
    ret
.none:
    xor             eax, eax
    ret

print_groups_with_sep:
    mov             r8, rdi             ; count
    mov             r10, rsi            ; separator pointer
    mov             r12, rdx            ; separator length
    xor             r9, r9              ; index
.loop:
    cmp             r9, r8
    jae             .ret

    mov             edi, [groups_buf + r9*4]
    call            print_num
    inc             r9
    cmp             r9, r8
    jae             .ret

    mov             rax, SYS_WRITE
    mov             rdi, 1
    mov             rsi, r10
    mov             rdx, r12
    syscall
    jmp             .loop
.ret:
    ret

print_num:    
    mov             rax, rdi
    mov             rsi, numbuf + 15
    mov             byte [rsi], 0
    mov             rcx, 10
    
.next_digit:
    xor             rdx, rdx
    div             rcx
    dec             rsi
    add             dl, '0'
    mov             [rsi], dl
    test            rax, rax
    jnz             .next_digit
    mov             rax, SYS_WRITE
    mov             rdi, 1
    mov             rdx, numbuf + 15
    sub             rdx, rsi
    syscall
    ret

write_str:
    mov             rsi, rdi
    call            strlen
    write           1, rsi, rbx
    ret

write_comma:
    write           1, comma, 1
    ret

write_space:
    write           1, space, 1
    ret

write_groups_prefix:
    mov             rdi, groups_prefix
    call            write_str
    ret

write_newline:
    write           1, newline, 1
    ret
