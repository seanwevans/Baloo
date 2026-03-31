; src/ls.asm

%include "include/sysdefs.inc"

%define BUFFER_SIZE 8192                ; Buffer for reading directory entries
%define NAME_MAX    255                 ; Maximum length of a filename

struc dirent64
    .d_ino      resq 1                  ; 64-bit inode number
    .d_off      resq 1                  ; 64-bit offset to next structure
    .d_reclen   resw 1                  ; 16-bit size of this dirent
    .d_type     resb 1                  ; 8-bit file type
    .d_name     resb 1                  ; Filename (null-terminated)
endstruc

section .data
    current_dir db ".", 0               ; Default directory to list
    newline     db 10                   ; Newline character
    space       db " ", 0               ; Space for separation

section .bss
    buffer      resb BUFFER_SIZE        ; Buffer for directory entries
    dirp        resq 1                  ; Directory pointer (file descriptor)
    
section .text
    global      _start

_start:
    pop         rdi                     ; argc
    cmp         rdi, 1                  ; If argc == 1, use default dir
    je          .use_default_dir

    pop         rsi                     ; Skip argv[0] (program name)
    pop         rsi                     ; Get argv[1] (directory name)
    jmp         .open_dir
    
.use_default_dir:
    mov         rsi, current_dir        ; Use "." as default directory

.open_dir:
    mov         rax, SYS_OPEN
    mov         rdi, rsi                ; Directory path
    mov         rsi, O_RDONLY
    syscall

    cmp         rax, 0
    jl          .exit_error

    mov         [dirp], rax

.read_dir:
    mov         rax, SYS_GETDENTS64     ; getdents64 syscall
    mov         rdi, [dirp]             ; Directory fd
    mov         rsi, buffer             ; Buffer for entries
    mov         rdx, BUFFER_SIZE        ; Buffer size
    syscall

    cmp         rax, 0
    jle         .close_dir              ; If <= 0, we're done or error

    mov         r12, rax                ; Save bytes read
    xor         r13, r13                ; Initialize offset to 0

.process_entries:
    cmp         r13, r12
    jge         .read_dir               ; Get more entries if needed
    
    lea         rdi, [buffer + r13]
    movzx       r14, word [rdi + dirent64.d_reclen]
    lea         rsi, [rdi + dirent64.d_name]
    cmp         byte [rsi], '.'
    jne         .print_entry
    
    cmp         byte [rsi + 1], 0
    je          .next_entry
    
    cmp         byte [rsi + 1], '.'
    jne         .print_entry
    
    cmp         byte [rsi + 2], 0
    je          .next_entry

.print_entry:
    xor         rdx, rdx                ; Counter for string length

.name_len_loop:
    cmp         byte [rsi + rdx], 0
    je          .name_len_done
    inc         rdx
    jmp         .name_len_loop

.name_len_done:
    test        rdx, rdx                ; Defensive skip for empty names
    jz          .next_entry

    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    syscall

    mov         rax, SYS_WRITE
    mov         rdi, STDOUT_FILENO
    mov         rsi, newline
    mov         rdx, 1
    syscall

    jmp         .next_entry
    
.next_entry:
    add         r13, r14
    jmp         .process_entries

.close_dir:
    write       STDOUT_FILENO, newline, 1

    mov         rax, SYS_CLOSE
    mov         rdi, [dirp]
    syscall

.exit_success:
    exit        0

.exit_error:
    exit        1
