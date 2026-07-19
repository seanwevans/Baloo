; src/mkdir.asm -- mkdir(1): create directories, with -p (parents),
; -m MODE (exact mode) and -v (verbose).

    %include "include/sysdefs.inc"

    %define DEFMODE 0o777

section .bss
    pathbuf     resb 4096               ;mutable copy of a path
    p_flag      resb 1
    v_flag      resb 1
    m_flag      resb 1
    mode_val    resq 1
    inter_mode  resq 1

section .data
usage_msg   db "Usage: mkdir [-pv] [-m mode] dir...", 10
    usage_len   equ $ - usage_msg
err_msg     db "mkdir: cannot create directory", 10
    err_len     equ $ - err_msg
vmsg1       db "mkdir: created directory '"
    vmsg1_len   equ $ - vmsg1
    vmsg2       db "'", WHITESPACE_NL
    vmsg2_len   equ $ - vmsg2

section .text
global      _start

_start:
    mov         r12, [rsp]              ;argc
    lea         r13, [rsp + 16]         ;&argv[1]
    cmp         r12, 2
    jl          print_usage

    mov         byte [p_flag], 0
    mov         byte [v_flag], 0
    mov         byte [m_flag], 0
    mov         qword [mode_val], DEFMODE

;read the umask (without changing it) to compute the mode used for the
;intermediate directories created by -p: (0777 & ~umask) | u+wx
    mov         rax, SYS_UMASK
    xor         rdi, rdi
    syscall
    mov         r15, rax                ;saved umask
    mov         rdi, rax
    mov         rax, SYS_UMASK
    syscall                             ;restore the umask
    not         r15
    and         r15, DEFMODE
    or          r15, 0o300
    mov         [inter_mode], r15

    dec         r12                     ;remaining argument count
    xor         r14, r14                ;exit status

opt_loop:
    cmp         r12, 0
    je          print_usage             ;options but no operand
    mov         rdi, [r13]
    cmp         byte [rdi], '-'
    jne         operands
    cmp         byte [rdi + 1], 0       ;lone "-" is an operand
    je          operands
    inc         rdi                     ;skip '-'
.char:
    movzx       eax, byte [rdi]
    test        al, al
    je          .next_opt
    cmp         al, 'p'
    je          .set_p
    cmp         al, 'v'
    je          .set_v
    cmp         al, 'm'
    je          .set_m
    inc         rdi                     ;ignore unknown option letters
    jmp         .char
.set_p:
    mov         byte [p_flag], 1
    inc         rdi
    jmp         .char
.set_v:
    mov         byte [v_flag], 1
    inc         rdi
    jmp         .char
.set_m:
    mov         byte [m_flag], 1
    inc         rdi
    cmp         byte [rdi], 0           ;mode attached (-mNNN) or next arg?
    jne         .mode_here
    add         r13, 8                  ;take the following argument
    dec         r12
    mov         rdi, [r13]
.mode_here:
    call        parse_mode              ;rdi -> mode_val
;fall through: mode consumes the rest of this argument
.next_opt:
    add         r13, 8
    dec         r12
    jmp         opt_loop

operands:
    cmp         r12, 0
    je          done
    mov         rdi, [r13]
    cmp         byte [p_flag], 0
    jne         .p
    call        mkdir_one
    jmp         .next
.p:
    call        mkdir_parents
.next:
    add         r13, 8
    dec         r12
    jmp         operands

done:
    mov         rdi, r14
    mov         rax, SYS_EXIT
    syscall

; parse_mode: rdi -> octal digits, result into mode_val
parse_mode:
    xor         rax, rax
.loop:
    movzx       rdx, byte [rdi]
    cmp         dl, '0'
    jb          .done
    cmp         dl, '7'
    ja          .done
    sub         dl, '0'
    shl         rax, 3
    add         rax, rdx
    inc         rdi
    jmp         .loop
.done:
    mov         [mode_val], rax
    ret

; mkdir_one: rdi -> path, create a single directory
mkdir_one:
    push        rdi
    mov         rsi, [mode_val]
    mov         rax, SYS_MKDIR
    syscall
    pop         rdi
    test        rax, rax
    js          .fail
;created successfully
    cmp         byte [m_flag], 0
    je          .verbose
    mov         rsi, [mode_val]         ;apply the exact mode (bypass umask)
    push        rdi
    mov         rax, SYS_CHMOD
    syscall
    pop         rdi
.verbose:
    cmp         byte [v_flag], 0
    je          .ok
    mov         rsi, rdi
    call        print_created
.ok:
    ret
.fail:
    write       STDERR_FILENO, err_msg, err_len
    mov         r14, 1
    ret

; mkdir_parents: rdi -> path, create it and any missing parents
mkdir_parents:
;copy path into pathbuf, measure length in r8
    mov         rsi, pathbuf
    xor         r8, r8
.copy:
    mov         al, [rdi + r8]
    mov         [rsi + r8], al
    test        al, al
    je          .copied
    inc         r8
    jmp         .copy
.copied:
;strip trailing slashes (keep at least one character)
.strip:
    cmp         r8, 1
    jle         .walk
    cmp         byte [pathbuf + r8 - 1], '/'
    jne         .walk
    mov         byte [pathbuf + r8 - 1], 0
    dec         r8
    jmp         .strip
.walk:
    xor         rcx, rcx                ;index into pathbuf
.scan:
    inc         rcx
    cmp         rcx, r8
    jge         .final
    cmp         byte [pathbuf + rcx], '/'
    jne         .scan
;temporarily terminate at this separator and make the prefix
    mov         byte [pathbuf + rcx], 0
    push        rcx
    mov         rdi, pathbuf
    mov         rsi, DEFMODE
    mov         rax, SYS_MKDIR
    syscall
    test        rax, rax
    jnz         .after_inter            ;only adjust dirs we just created
    mov         rdi, pathbuf
    mov         rsi, [inter_mode]       ;force u+wx so children can be added
    mov         rax, SYS_CHMOD
    syscall
    xor         rax, rax                ;keep "created" status for verbose
.after_inter:
    call        parents_verbose
    pop         rcx
    mov         byte [pathbuf + rcx], '/'
    jmp         .scan
.final:
    mov         rdi, pathbuf
    mov         rsi, [mode_val]
    mov         rax, SYS_MKDIR
    syscall
    test        rax, rax
    js          .final_fail
;created
    cmp         byte [m_flag], 0
    je          .final_verbose
    mov         rdi, pathbuf
    mov         rsi, [mode_val]
    mov         rax, SYS_CHMOD
    syscall
.final_verbose:
    call        parents_verbose
    ret
.final_fail:
    cmp         rax, -EEXIST            ;already existing is fine for -p
    je          .final_ok
    write       STDERR_FILENO, err_msg, err_len
    mov         r14, 1
.final_ok:
    ret

; parents_verbose: if rax==0 (a dir was just created) and -v, announce pathbuf
parents_verbose:
    test        rax, rax
    jnz         .skip
    cmp         byte [v_flag], 0
    je          .skip
    mov         rsi, pathbuf
    call        print_created
.skip:
    ret

; print_created: rsi -> NUL-terminated name; write the verbose creation line
print_created:
    push        rsi
    write       STDOUT_FILENO, vmsg1, vmsg1_len
    pop         rsi
;measure name length
    xor         rdx, rdx
.len:
    cmp         byte [rsi + rdx], 0
    je          .have_len
    inc         rdx
    jmp         .len
.have_len:
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    syscall
    write       STDOUT_FILENO, vmsg2, vmsg2_len
    ret

print_usage:
    write       STDERR_FILENO, usage_msg, usage_len
    exit        1
