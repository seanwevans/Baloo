; src/tsort.asm

%include "include/sysdefs.inc"

%define MAX_NODES 128
%define MAX_EDGES 256
%define MAX_NAME_LEN 32

section .bss
    char_buf        resb 1
    token_buf       resb MAX_NAME_LEN
    names           resb MAX_NODES * MAX_NAME_LEN
    indegree        resq MAX_NODES
    processed       resb MAX_NODES
    edges_from      resq MAX_EDGES
    edges_to        resq MAX_EDGES
    node_count      resq 1
    edge_count      resq 1

section .data
    newline         db WHITESPACE_NL
    cycle_msg       db "tsort: cycle detected", WHITESPACE_NL
    cycle_len       equ $ - cycle_msg

section .text
    global _start

_start:
    mov     qword [node_count], 0
    mov     qword [edge_count], 0

read_pairs:
    call    get_token
    cmp     rax, -1
    je      build_graph
    ; token in token_buf, length rax
    mov     rsi, token_buf
    call    get_node_id
    mov     r12, rax            ; from node id

    call    get_token
    cmp     rax, -1
    je      build_graph         ; odd token count -> treat as vertex only
    mov     rsi, token_buf
    call    get_node_id
    mov     r13, rax            ; to node id

    mov     rax, [edge_count]
    cmp     rax, MAX_EDGES
    jae     read_pairs
    mov     [edges_from + rax*8], r12
    mov     [edges_to + rax*8], r13
    inc     rax
    mov     [edge_count], rax
    jmp     read_pairs

build_graph:
    ; initialize indegree and processed arrays
    mov     rcx, [node_count]
    xor     rbx, rbx
zero_loop:
    cmp     rbx, rcx
    jge     count_edges
    mov     qword [indegree + rbx*8], 0
    mov     byte [processed + rbx], 0
    inc     rbx
    jmp     zero_loop

count_edges:
    mov     rcx, [edge_count]
    xor     rbx, rbx
edge_loop:
    cmp     rbx, rcx
    jge     sort_start
    mov     rax, [edges_to + rbx*8]
    inc     qword [indegree + rax*8]
    inc     rbx
    jmp     edge_loop

sort_start:
    xor     r14, r14            ; processed count

sort_outer:
    mov     rcx, [node_count]
    cmp     r14, rcx
    je      done

    mov     r15, -1             ; candidate index
    xor     rbx, rbx
find_zero:
    cmp     rbx, rcx
    jge     check_cycle
    cmp     byte [processed + rbx], 0
    jne     next_node
    cmp     qword [indegree + rbx*8], 0
    jne     next_node
    mov     r15, rbx
    jmp     found
next_node:
    inc     rbx
    jmp     find_zero

check_cycle:
    cmp     r15, -1
    je      cycle_error
found:
    mov     rax, r15
    shl     rax, 5                  ; r15 * MAX_NAME_LEN
    lea     rsi, [names + rax]
    call    strlen              ; rbx = length
    write   STDOUT_FILENO, rsi, rbx
    write   STDOUT_FILENO, newline, 1
    mov     byte [processed + r15], 1
    inc     r14

    ; decrease indegree for outgoing edges
    mov     rcx, [edge_count]
    xor     rbx, rbx
update_edges:
    cmp     rbx, rcx
    jge     sort_outer
    mov     rax, [edges_from + rbx*8]
    cmp     rax, r15
    jne     next_edge2
    mov     rax, [edges_to + rbx*8]
    dec     qword [indegree + rax*8]
next_edge2:
    inc     rbx
    jmp     update_edges

cycle_error:
    write   STDERR_FILENO, cycle_msg, cycle_len
    exit    1

done:
    exit    0

; -------- helper: get_token --------
; returns length in rax, -1 on EOF
get_token:
    ; skip whitespace
.skip_ws:
    call    read_char
    cmp     rax, -1
    je      .eof
    mov     dl, al
    cmp     dl, WHITESPACE_SPACE
    je      .skip_ws
    cmp     dl, WHITESPACE_NL
    je      .skip_ws
    cmp     dl, WHITESPACE_TAB
    je      .skip_ws
    ; start token
    mov     rdi, token_buf
    xor     rcx, rcx
.store_loop:
    mov     [rdi + rcx], dl
    inc     rcx
    cmp     rcx, MAX_NAME_LEN - 1
    je      .skip_to_delim
    call    read_char
    cmp     rax, -1
    je      .finish
    mov     dl, al
    cmp     dl, WHITESPACE_SPACE
    je      .finish_with_delim
    cmp     dl, WHITESPACE_NL
    je      .finish_with_delim
    cmp     dl, WHITESPACE_TAB
    je      .finish_with_delim
    jmp     .store_loop

.skip_to_delim:
    call    read_char
    cmp     rax, -1
    je      .finish
    mov     dl, al
    cmp     dl, WHITESPACE_SPACE
    je      .finish_with_delim
    cmp     dl, WHITESPACE_NL
    je      .finish_with_delim
    cmp     dl, WHITESPACE_TAB
    je      .finish_with_delim
    jmp     .skip_to_delim

.finish_with_delim:
.finish:
    mov     byte [rdi + rcx], 0
    mov     rax, rcx
    ret
.eof:
    mov     rax, -1
    ret

; -------- helper: read_char --------
; returns char in al, or -1 in rax on EOF
read_char:
    mov     rax, SYS_READ
    mov     rdi, STDIN_FILENO
    mov     rsi, char_buf
    mov     rdx, 1
    syscall
    cmp     rax, 0
    je      .eof
    movzx   eax, byte [char_buf]
    ret
.eof:
    mov     rax, -1
    ret

; -------- helper: get_node_id --------
; rsi -> token string
; returns node id in rax
get_node_id:
    mov     rcx, [node_count]
    xor     rbx, rbx
.search:
    cmp     rbx, rcx
    je      .add
    mov     rax, rbx
    shl     rax, 5                  ; rbx * MAX_NAME_LEN
    lea     rdi, [names + rax]
    push    rsi
    mov     rsi, rdi
    lea     rdi, [token_buf]
    call    strings_equal       ; rax = 1 if equal
    pop     rsi
    cmp     rax, 1
    je      .found
    inc     rbx
    jmp     .search

.add:
    cmp     rcx, MAX_NODES
    jae     .found              ; if full, just return last index
    mov     rax, rcx
    shl     rax, 5                  ; rcx * MAX_NAME_LEN
    lea     rdi, [names + rax]
    call    copy_string
    mov     rax, rcx
    inc     rcx
    mov     [node_count], rcx
    ret

.found:
    mov     rax, rbx
    ret

; -------- helper: strings_equal --------
; rdi -> str1, rsi -> str2
; returns 1 if equal else 0
strings_equal:
    push    rcx
    xor     rcx, rcx
.eq_loop:
    mov     al, [rdi + rcx]
    cmp     al, [rsi + rcx]
    jne     .not_eq
    test    al, al
    je      .is_eq
    inc     rcx
    jmp     .eq_loop
.is_eq:
    mov     rax, 1
    jmp     .done
.not_eq:
    xor     rax, rax
.done:
    pop     rcx
    ret

; -------- helper: copy_string --------
; rdi -> dest, token_buf -> src
copy_string:
    push    rcx
    xor     rcx, rcx
.cpy_loop:
    mov     al, [token_buf + rcx]
    mov     [rdi + rcx], al
    test    al, al
    je      .done
    inc     rcx
    cmp     rcx, MAX_NAME_LEN - 1
    jb      .cpy_loop
    mov     byte [rdi + rcx], 0
.done:
    pop     rcx
    ret
