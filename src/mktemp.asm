; src/mktemp.asm

%include "include/sysdefs.inc"

section .bss
    template        resb 1024   ; Buffer for template
    template_len    resq 1      ; Length of template
    pid             resq 1      ; Process ID
    random_bytes    resb 8      ; Buffer for random bytes
    directory_mode  resb 1      ; 1 = create dir, 0 = create file
    unique_mode     resb 1      ; 1 = only print unique path (-u), 0 = create it
    
section .data
    default_template db "/tmp/tmp.XXXXXXXXXX", 0
    d_option    db "-d", 0
    u_option    db "-u", 0
    err_msg     db "Error: Failed to create temporary file/directory", 10
    err_len     equ $ - err_msg
    usage_msg   db "Usage: mktemp [-d] [template]", 10
    usage_len   equ $ - usage_msg

section .text
    global      _start

_start:
    mov         byte [directory_mode], 0
    mov         byte [unique_mode], 0
    pop         rcx                     ; argc
    cmp         rcx, 1                  ; If argc == 1, use default template
    je          use_default_template

    pop         rdi                     ; Skip program name
    cmp         rcx, 2                  ; If we have exactly 2 args (prog + -d), use default template
    jl          use_default_template    ; Not enough args, use default
    
    pop         rsi                     ; Get argv[1]
    mov         rdi, u_option
    push        rcx                     ; Save argc
    call        strcmp
    pop         rcx                     ; Restore argc
    cmp         rax, 0
    jne         check_d_option

    mov         byte [unique_mode], 1
    cmp         rcx, 3                  ; If we have 3 args (prog + -u + template)
    jl          use_default_template

    pop         rsi
    mov         rdi, template
    call        copy_string
    jmp         template_ready

check_d_option:
    mov         rdi, d_option
    push        rcx                     ; Save argc
    call        strcmp
    
    pop         rcx                     ; Restore argc
    cmp         rax, 0
    jne         not_d_option

    mov         byte [directory_mode], 1
    cmp         rcx, 3                  ; If we have 3 args (prog + -d + template)
    jl          use_default_template    ; No template after -d, use default

    pop         rsi
    mov         rdi, template
    call        copy_string
    
    jmp         template_ready
    
not_d_option:
    mov         rdi, template
    call        copy_string
    jmp         template_ready
    
use_default_template:
    mov         rsi, default_template
    mov         rdi, template
    call        copy_string
    
template_ready:
    mov         rsi, template
    call        strlen
    
    mov         [template_len], rbx
    mov         rdi, template
    add         rdi, [template_len]     ; Start from the end
    
find_x_loop:
    dec         rdi
    cmp         byte [rdi], 'X'
    jne         check_if_done

    push        rdi                     ; Save position
    call        get_random_char
    
    pop         rdi                     ; Restore position
    mov         [rdi], al               ; Replace X with random char
    
check_if_done:
    mov         rax, template
    cmp         rdi, rax
    jg          find_x_loop

    cmp         byte [directory_mode], 0
    jne         create_directory
    cmp         byte [unique_mode], 1
    je          output_result

    mov         rax, SYS_OPEN
    mov         rdi, template
    mov         rsi, O_RDWR | O_CREAT | O_EXCL
    mov         rdx, DEFAULT_MODE       ; File permissions (0644)
    syscall

    cmp         rax, 0
    jl          error_exit

    mov         rdi, rax
    mov         rax, SYS_CLOSE
    syscall
    
    jmp         output_result
    
create_directory:
    mov         rax, SYS_MKDIR
    mov         rdi, template
    mov         rsi, DIR_MODE           ; Directory permissions (0700)
    syscall

    cmp         rax, 0
    jl          error_exit

output_result:
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, template
    mov         rdx, [template_len]
    syscall

    mov         rax, template
    add         rax, [template_len]     ; Point to end of string (null terminator)
    mov         byte [rax], 10          ; Replace null with newline
    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, template
    add         rsi, [template_len]     ; Point to the newline we just added
    mov         rdx, 1                  ; Just print one character
    syscall

    exit        0
    
error_exit:
    write       STDERR_FILENO, err_msg, err_len
    exit 1

copy_string:
    xor         rcx, rcx                ; Initialize counter
.loop:
    mov         al, [rsi + rcx]         ; Get character
    mov         [rdi + rcx], al         ; Copy character
    inc         rcx                     ; Increment counter
    test        al, al                  ; Check if null terminator
    jnz         .loop                   ; Continue if not null
    
    ret

strcmp:
    push        rcx                     ; Save rcx
    xor         rcx, rcx                ; Initialize counter
    
.loop:
    mov         al, [rdi + rcx]         ; Get character from first string
    mov         dl, [rsi + rcx]         ; Get character from second string
    cmp         al, dl                  ; Compare characters
    jne         .not_equal              ; If not equal, return non-zero
    
    test        al, al                  ; Check if null terminator
    jz          .equal                  ; If null, strings are equal
    
    inc         rcx                     ; Increment counter
    jmp         .loop                   ; Continue
    
.not_equal:
    mov         rax, 1                  ; Return non-zero (not equal)
    pop         rcx                     ; Restore rcx
    ret

.equal:
    xor         rax, rax                ; Return zero (equal)
    pop         rcx                     ; Restore rcx
    ret

get_random_char:
    push        rbx                     ; Save rbx
    mov         rax, SYS_GETRANDOM
    mov         rdi, random_bytes
    mov         rsi, 1                  ; Get 1 byte
    mov         rdx, 0                  ; No flags
    syscall

    cmp         rax, 1
    jne         .fallback

    mov         al, [random_bytes]
    jmp         .make_alnum
    
.fallback:
    mov         rax, SYS_GETPID
    syscall
    
    mov         [pid], rax
    mov         rax, SYS_TIME
    xor         rdi, rdi
    syscall

    xor         rax, [pid]
    
.make_alnum:
    and         al, 0x3F                ; Keep lower 6 bits (0-63)
    cmp         al, 62
    jl          .continue_mapping

    and         al, 0x01                ; Keep only the lowest bit (0 or 1)
    
.continue_mapping:
    cmp         al, 10
    jl          .digits                 ; 0-9 -> '0'-'9' (48-57)
    
    cmp         al, 36
    jl          .lowercase              ; 10-35 -> 'a'-'z' (97-122)
        
    sub         al, 36
    add         al, 'A'                 ; 36-61 -> 'A'-'Z' (65-90)
    jmp         .done
    
.digits:
    add         al, '0'
    jmp         .done
    
.lowercase:
    sub         al, 10
    add         al, 'a'
    
.done:
    pop         rbx                     ; Restore rbx
    ret
