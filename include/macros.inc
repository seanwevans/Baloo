; include/macros.inc

; Exits with code status
;    Inputs: %1 = uint  status
    %macro exit 1
    mov rax, SYS_EXIT
    mov rdi, %1                         ;exit code
    syscall
    %endmacro

; Writes len bytes of buf to fd
;    Inputs: %1 = uint   file descriptor
;            %2 = string buffer
;            %3 = uint   length
    %macro write 3
    mov rax, SYS_WRITE
    mov rdi, %1                         ;file descriptor
    mov rsi, %2                         ;buffer address
    mov rdx, %3                         ;buffer length
    syscall
    %endmacro
