; src/m4.asm

    %include "include/sysdefs.inc"

    %define INPUT_SIZE 65536
    %define OUTPUT_SIZE 65536
    %define MACRO_COUNT 64
    %define NAME_SIZE 64
    %define VALUE_SIZE 1024

section .bss
    input_buf   resb INPUT_SIZE
    output_buf  resb OUTPUT_SIZE
    arg1_buf    resb NAME_SIZE
    arg2_buf    resb VALUE_SIZE
    arg3_buf    resb VALUE_SIZE
    names       resb MACRO_COUNT * NAME_SIZE
    values      resb MACRO_COUNT * VALUE_SIZE
    val_lens    resq MACRO_COUNT
    used        resb MACRO_COUNT
    input_len   resq 1
    out_pos     resq 1

section .data
usage_msg   db "Usage: m4 [FILE...]", 10
    usage_len   equ $ - usage_msg
open_msg    db "m4: cannot open file", 10
    open_len    equ $ - open_msg

section .text
global _start

_start:
    mov         qword [out_pos], 0
    pop         r12                     ;argc
    pop         rbx                     ;argv[0]
    dec         r12
    cmp         r12, 0
    je          .stdin

.files:
    cmp         r12, 0
    je          .done
    pop         rdi
    call        process_file
    dec         r12
    jmp         .files

.stdin:
    mov         rdi, STDIN_FILENO
    call        read_fd
    mov         r13, input_buf
    mov         r14, input_buf
    add         r14, [input_len]
    call        process_input

.done:
    call        flush_output
    exit        0

process_file:
    mov         rax, SYS_OPEN
    mov         rsi, O_RDONLY
    xor         rdx, rdx
    syscall
    cmp         rax, 0
    jl          .open_error
    mov         r15, rax
    mov         rdi, r15
    call        read_fd
    mov         rax, SYS_CLOSE
    mov         rdi, r15
    syscall
    mov         r13, input_buf
    mov         r14, input_buf
    add         r14, [input_len]
    push        r12
    call        process_input
    pop         r12
    ret
.open_error:
    write       STDERR_FILENO, open_msg, open_len
    exit        1

read_fd:
    xor         rbx, rbx
.read_loop:
    mov         rax, SYS_READ
    mov         rsi, input_buf
    add         rsi, rbx
    mov         rdx, INPUT_SIZE
    sub         rdx, rbx
    syscall
    cmp         rax, 0
    jl          .read_error
    je          .done
    add         rbx, rax
    cmp         rbx, INPUT_SIZE
    jl          .read_loop
.done:
    mov         [input_len], rbx
    ret
.read_error:
    exit        1

process_input:
.loop:
    cmp         r13, r14
    jae         .done
    mov         al, [r13]
    call        is_name_start
    cmp         al, 1
    jne         .literal

    mov         rsi, r13
    call        scan_name
    mov         rdx, rax                ;token length

    cmp         rdx, 6
    jne         .check_undef
    mov         rsi, r13
    mov         rdi, define_word
    mov         rcx, 6
    call        memeq_const
    cmp         rax, 1
    jne         .check_undef
    call        try_parse_define
    cmp         rax, 1
    je          .loop
    jmp         .emit_token

.check_undef:
    cmp         rdx, 8
    jne         .check_ifdef
    mov         rsi, r13
    mov         rdi, undef_word
    mov         rcx, 8
    call        memeq_const
    cmp         rax, 1
    jne         .check_ifdef
    call        try_parse_undefine
    cmp         rax, 1
    je          .loop
    jmp         .emit_token

.check_ifdef:
    cmp         rdx, 5
    jne         .check_dnl
    mov         rsi, r13
    mov         rdi, ifdef_word
    mov         rcx, 5
    call        memeq_const
    cmp         rax, 1
    jne         .check_dnl
    call        try_parse_ifdef
    cmp         rax, 1
    je          .loop
    jmp         .emit_token

.check_dnl:
    cmp         rdx, 3
    jne         .macro_lookup
    mov         rsi, r13
    mov         rdi, dnl_word
    mov         rcx, 3
    call        memeq_const
    cmp         rax, 1
    jne         .macro_lookup
.skip_dnl:
    add         r13, 3
.skip_dnl_loop:
    cmp         r13, r14
    jae         .loop
    mov         al, [r13]
    inc         r13
    cmp         al, WHITESPACE_NL
    jne         .skip_dnl_loop
    jmp         .loop

.macro_lookup:
    mov         r12, rdx
    mov         rsi, r13
    call        find_macro
    cmp         rax, -1
    je          .emit_token
    mov         rbx, rax
    mov         rax, rbx
    imul        rax, VALUE_SIZE
    lea         rsi, [values + rax]
    mov         rdx, [val_lens + rbx * 8]
    call        emit_bytes
    add         r13, r12
    jmp         .loop

.emit_token:
    mov         rsi, r13
    call        scan_name
    mov         rdx, rax
    call        emit_bytes
    add         r13, rdx
    jmp         .loop

.literal:
    mov         al, [r13]
    call        emit_char
    inc         r13
    jmp         .loop
.done:
    ret

    define_word db "define"
    undef_word  db "undefine"
    ifdef_word  db "ifdef"
    dnl_word    db "dnl"

; r13 points at define token. On success, advances r13 past call and returns 1.
try_parse_define:
    push        r12
    mov         r15, r13
    add         r15, 6
    call        skip_blanks
    cmp         r15, r14
    jae         .fail
    cmp         byte [r15], '('
    jne         .fail
    inc         r15
    mov         rdi, arg1_buf
    mov         rcx, NAME_SIZE - 1
    call        parse_arg
    cmp         rax, 0
    je          .fail
    mov         r12, rax
    call        skip_blanks
    cmp         r15, r14
    jae         .fail
    cmp         byte [r15], ','
    jne         .fail
    inc         r15
    mov         rdi, arg2_buf
    mov         rcx, VALUE_SIZE - 1
    call        parse_arg
    mov         rbx, rax
    call        skip_blanks
    cmp         r15, r14
    jae         .fail
    cmp         byte [r15], ')'
    jne         .fail
    inc         r15
    mov         rsi, arg1_buf
    mov         rdx, r12
    mov         rdi, arg2_buf
    mov         rcx, rbx
    call        define_macro
    mov         r13, r15
    mov         rax, 1
    pop         r12
    ret
.fail:
    xor         rax, rax
    pop         r12
    ret

try_parse_undefine:
    push        r12
    mov         r15, r13
    add         r15, 8
    call        skip_blanks
    cmp         r15, r14
    jae         .fail
    cmp         byte [r15], '('
    jne         .fail
    inc         r15
    mov         rdi, arg1_buf
    mov         rcx, NAME_SIZE - 1
    call        parse_arg
    cmp         rax, 0
    je          .fail
    mov         r12, rax
    call        skip_blanks
    cmp         r15, r14
    jae         .fail
    cmp         byte [r15], ')'
    jne         .fail
    inc         r15
    mov         rsi, arg1_buf
    mov         rdx, r12
    call        undef_macro
    mov         r13, r15
    mov         rax, 1
    pop         r12
    ret
.fail:
    xor         rax, rax
    pop         r12
    ret

try_parse_ifdef:
    push        r12
    mov         r15, r13
    add         r15, 5
    call        skip_blanks
    cmp         r15, r14
    jae         .fail
    cmp         byte [r15], '('
    jne         .fail
    inc         r15
    mov         rdi, arg1_buf
    mov         rcx, NAME_SIZE - 1
    call        parse_arg
    cmp         rax, 0
    je          .fail
    mov         r12, rax
    call        skip_blanks
    cmp         r15, r14
    jae         .fail
    cmp         byte [r15], ','
    jne         .fail
    inc         r15
    mov         rdi, arg2_buf
    mov         rcx, VALUE_SIZE - 1
    call        parse_arg
    mov         rbx, rax                ;true length
    call        skip_blanks
    xor         r8, r8                  ;false length defaults to 0
    cmp         r15, r14
    jae         .fail
    cmp         byte [r15], ','
    jne         .need_close
    inc         r15
    push        rbx
    mov         rdi, arg3_buf
    mov         rcx, VALUE_SIZE - 1
    call        parse_arg
    mov         r8, rax
    pop         rbx
.need_close:
    call        skip_blanks
    cmp         r15, r14
    jae         .fail
    cmp         byte [r15], ')'
    jne         .fail
    inc         r15
    mov         rsi, arg1_buf
    mov         rdx, r12
    call        find_macro
    cmp         rax, -1
    je          .emit_false
    mov         rsi, arg2_buf
    mov         rdx, rbx
    call        emit_bytes
    jmp         .ok
.emit_false:
    cmp         r8, 0
    je          .ok
    mov         rsi, arg3_buf
    mov         rdx, r8
    call        emit_bytes
.ok:
    mov         r13, r15
    mov         rax, 1
    pop         r12
    ret
.fail:
    xor         rax, rax
    pop         r12
    ret

skip_blanks:
.loop:
    cmp         r15, r14
    jae         .done
    mov         al, [r15]
    cmp         al, WHITESPACE_SPACE
    je          .next
    cmp         al, WHITESPACE_TAB
    je          .next
    cmp         al, WHITESPACE_NL
    je          .next
    ret
.next:
    inc         r15
    jmp         .loop
.done:
    ret

; r15 input pointer, rdi destination, rcx max bytes. Returns length in rax.
parse_arg:
    push        rbx
    push        rdi
    xor         rbx, rbx
    call        skip_blanks
    cmp         r15, r14
    jae         .done
    cmp         byte [r15], '`'
    je          .quoted
.unquoted:
    cmp         r15, r14
    jae         .done
    mov         al, [r15]
    cmp         al, ','
    je          .done
    cmp         al, ')'
    je          .done
    cmp         rbx, rcx
    jae         .advance_unquoted
    mov         [rdi + rbx], al
    inc         rbx
.advance_unquoted:
    inc         r15
    jmp         .unquoted
.quoted:
    inc         r15
.quoted_loop:
    cmp         r15, r14
    jae         .done
    mov         al, [r15]
    cmp         al, 39
    je          .end_quote
    cmp         rbx, rcx
    jae         .advance_quoted
    mov         [rdi + rbx], al
    inc         rbx
.advance_quoted:
    inc         r15
    jmp         .quoted_loop
.end_quote:
    inc         r15
.done:
    pop         rdi
    mov         byte [rdi + rbx], 0
    mov         rax, rbx
    pop         rbx
    ret

scan_name:
    xor         rax, rax
.loop:
    lea         rbx, [rsi + rax]
    cmp         rbx, r14
    jae         .done
    mov         dl, [rsi + rax]
    push        rax
    call        is_name_char
    mov         bl, al
    pop         rax
    cmp         bl, 1
    jne         .done
    inc         rax
    jmp         .loop
.done:
    ret

is_name_start:
    cmp         al, '_'
    je          .yes
    cmp         al, 'A'
    jb          .no
    cmp         al, 'Z'
    jbe         .yes
    cmp         al, 'a'
    jb          .no
    cmp         al, 'z'
    jbe         .yes
.no:
    xor         al, al
    ret
.yes:
    mov         al, 1
    ret

is_name_char:
    mov         al, dl
    call        is_name_start
    cmp         al, 1
    je          .done
    cmp         dl, '0'
    jb          .no
    cmp         dl, '9'
    jbe         .yes
.no:
    xor         al, al
    ret
.yes:
    mov         al, 1
.done:
    ret

memeq_const:
.loop:
    cmp         rcx, 0
    je          .yes
    mov         al, [rsi]
    cmp         al, [rdi]
    jne         .no
    inc         rsi
    inc         rdi
    dec         rcx
    jmp         .loop
.yes:
    mov         rax, 1
    ret
.no:
    xor         rax, rax
    ret

find_macro:
    push        rbx
    push        rcx
    push        rdi
    push        rsi
    push        rdx
    xor         rbx, rbx
.outer:
    cmp         rbx, MACRO_COUNT
    jae         .not_found
    cmp         byte [used + rbx], 1
    jne         .next
    mov         rax, rbx
    imul        rax, NAME_SIZE
    lea         rdi, [names + rax]
    mov         rcx, 0
.compare:
    cmp         rcx, rdx
    jae         .check_end
    mov         al, [rsi + rcx]
    cmp         al, [rdi + rcx]
    jne         .next
    inc         rcx
    jmp         .compare
.check_end:
    cmp         byte [rdi + rcx], 0
    je          .found
.next:
    inc         rbx
    jmp         .outer
.found:
    mov         rax, rbx
    jmp         .restore
.not_found:
    mov         rax, -1
.restore:
    pop         rdx
    pop         rsi
    pop         rdi
    pop         rcx
    pop         rbx
    ret

define_macro:
; rsi=name, rdx=name_len, rdi=value, rcx=value_len
    push        rbx
    push        r8
    push        r9
    push        r10
    push        rsi
    push        rdx
    call        find_macro
    cmp         rax, -1
    jne         .have_slot
    xor         rbx, rbx
.find_free:
    cmp         rbx, MACRO_COUNT
    jae         .done
    cmp         byte [used + rbx], 0
    je          .free
    inc         rbx
    jmp         .find_free
.free:
    mov         rax, rbx
.have_slot:
    mov         rbx, rax
    mov         byte [used + rbx], 1
    pop         rdx
    pop         rsi
    mov         r8, rbx
    imul        r8, NAME_SIZE
    lea         r9, [names + r8]
    xor         r10, r10
.copy_name:
    cmp         r10, rdx
    jae         .name_done
    cmp         r10, NAME_SIZE - 1
    jae         .name_done
    mov         al, [rsi + r10]
    mov         [r9 + r10], al
    inc         r10
    jmp         .copy_name
.name_done:
    mov         byte [r9 + r10], 0
    mov         r8, rbx
    imul        r8, VALUE_SIZE
    lea         r9, [values + r8]
    xor         r10, r10
.copy_value:
    cmp         r10, rcx
    jae         .value_done
    cmp         r10, VALUE_SIZE - 1
    jae         .value_done
    mov         al, [rdi + r10]
    mov         [r9 + r10], al
    inc         r10
    jmp         .copy_value
.value_done:
    mov         [val_lens + rbx * 8], r10
    jmp         .finish
.done:
    pop         rdx
    pop         rsi
.finish:
    pop         r10
    pop         r9
    pop         r8
    pop         rbx
    ret

undef_macro:
    call        find_macro
    cmp         rax, -1
    je          .done
    mov         byte [used + rax], 0
.done:
    ret

emit_char:
    mov         cl, al
    mov         rax, [out_pos]
    cmp         rax, OUTPUT_SIZE
    jb          .store
    push        rcx
    call        flush_output
    pop         rcx
    xor         rax, rax
.store:
    mov         [output_buf + rax], cl
    inc         rax
    mov         [out_pos], rax
    ret

emit_bytes:
    push        rbx
    xor         rbx, rbx
.loop:
    cmp         rbx, rdx
    jae         .done
    mov         al, [rsi + rbx]
    push        rsi
    push        rdx
    call        emit_char
    pop         rdx
    pop         rsi
    inc         rbx
    jmp         .loop
.done:
    pop         rbx
    ret

flush_output:
    mov         rdx, [out_pos]
    cmp         rdx, 0
    je          .done
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, output_buf
    syscall
    mov         qword [out_pos], 0
.done:
    ret
