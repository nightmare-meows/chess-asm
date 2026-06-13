section .data
mq_name db "chess.moves",0

section .bss
msgbuf resb 16

section .text
global _start

_start:
    mov rdi, [rsp]
    cmp rdi, 3
    jl .err
    mov rsi, [rsp+16]
    mov al, [rsi]
    mov [msgbuf], al
    mov rsi, [rsp+24]
    lea rdi, [msgbuf+1]
    xor ecx, ecx
.cp:
    mov al, [rsi+rcx]
    test al, al
    jz .cpd
    mov [rdi+rcx], al
    inc ecx
    cmp ecx, 14
    jl .cp
.cpd:
    mov byte [rdi+rcx], 0
    mov eax, 240
    mov rdi, mq_name
    mov esi, 1
    xor edx, edx
    xor r10, r10
    syscall
    test rax, rax
    js .err
    mov rdi, rax
    mov eax, 242
    mov rsi, msgbuf
    mov edx, 16
    xor r10, r10
    xor r8, r8
    syscall
    mov eax, 60
    xor edi, edi
    syscall
.err:
    mov eax, 60
    mov edi, 1
    syscall
