section .data
shm_path   db "/dev/shm/chess.state",0
border     db "  +-----------------+",10
border_len equ $-border
files      db 10,"    a b c d e f g h",10
files_len  equ $-files
stm_lbl    db 10,"stm="
stm_lbl_len equ $-stm_lbl
result_lbl db " result="
result_lbl_len equ $-result_lbl
last_lbl   db " last="
last_lbl_len equ $-last_lbl
tick       dq 0, 50000000

section .bss
shmp    resq 1
lastseq resq 1
local   resb 256
outbuf  resb 1024

section .text
global _start

%macro EMITAL 0
    mov [r15], al
    inc r15
%endmacro

%macro EMITC 1
    mov byte [r15], %1
    inc r15
%endmacro

%macro EMITM 2
    mov rsi, %1
    mov rcx, %2
    rep movsb
%endmacro

_start:
.open:
    mov eax, 257
    mov edi, -100
    mov rsi, shm_path
    xor edx, edx
    xor r10, r10
    syscall
    test rax, rax
    jns .opened
    mov eax, 35
    mov rdi, tick
    xor rsi, rsi
    syscall
    jmp .open
.opened:
    mov r8, rax
    mov eax, 9
    xor edi, edi
    mov esi, 256
    mov edx, 1
    mov r10d, 1
    xor r9, r9
    syscall
    mov [shmp], rax
    mov qword [lastseq], -1

.poll:
    mov r9, [shmp]
    mov rax, [r9+8]
    test rax, 1
    jnz .sleep
    cmp rax, [lastseq]
    je .sleep
    mov r8, rax
    mov rsi, r9
    mov rdi, local
    mov rcx, 256
    rep movsb
    mov r9, [shmp]
    mov rax, [r9+8]
    cmp rax, r8
    jne .poll
    mov [lastseq], r8
    call render_watch
.sleep:
    mov eax, 35
    mov rdi, tick
    xor rsi, rsi
    syscall
    jmp .poll

render_watch:
    mov r15, outbuf
    mov rdi, r15
    EMITM border, border_len
    mov r15, rdi
    xor r12, r12
.wrow:
    mov al, '8'
    sub al, r12b
    EMITAL
    EMITC ' '
    EMITC '|'
    EMITC ' '
    mov r13, r12
    shl r13, 3
    xor r14, r14
.wcol:
    mov rbx, r13
    add rbx, r14
    mov al, [local+40+rbx]
    EMITAL
    EMITC ' '
    inc r14
    cmp r14, 8
    jl .wcol
    EMITC '|'
    EMITC 10
    inc r12
    cmp r12, 8
    jl .wrow
    mov rdi, r15
    EMITM border, border_len
    mov r15, rdi
    mov rdi, r15
    EMITM files, files_len
    mov r15, rdi
    mov rdi, r15
    EMITM stm_lbl, stm_lbl_len
    mov r15, rdi
    cmp byte [local+16], 0
    je .w
    mov al, 'b'
    jmp .pst
.w:
    mov al, 'w'
.pst:
    EMITAL
    mov rdi, r15
    EMITM result_lbl, result_lbl_len
    mov r15, rdi
    mov al, [local+17]
    add al, '0'
    EMITAL
    mov rdi, r15
    EMITM last_lbl, last_lbl_len
    mov r15, rdi
    xor ecx, ecx
.cl:
    mov al, [local+32+rcx]
    test al, al
    jz .cld
    mov [r15], al
    inc r15
    inc ecx
    cmp ecx, 8
    jl .cl
.cld:
    EMITC 10
    mov rdx, r15
    sub rdx, outbuf
    mov eax, 1
    mov edi, 1
    mov rsi, outbuf
    syscall
    ret
