; chess-asm — x86-64 Linux, NASM, no libc
; build: nasm -f elf64 chess.asm -o chess.o && ld chess.o -o chess

section .data
board_init db "rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR"
esc_clear  db 27,"[2J",27,"[H"
esc_len    equ $-esc_clear
border     db "  +-----------------+",10
border_len equ $-border
files      db 10,"    a b c d e f g h",10
files_len  equ $-files
prompt     db 10,"move (e2e4, q=quit)> "
prompt_len equ $-prompt
bye        db 10,"here before the question",10
bye_len    equ $-bye

section .bss
board  resb 64
inbuf  resb 32
outbuf resb 1024

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
    ; board = board_init
    mov rsi, board_init
    mov rdi, board
    mov rcx, 64
    rep movsb

.loop:
    call render

    ; read move
    mov rax, 0
    mov rdi, 0
    mov rsi, inbuf
    mov rdx, 32
    syscall
    test rax, rax
    jle .quit
    cmp rax, 1
    je .loop
    cmp byte [inbuf], 'q'
    je .quit

    ; need 4 chars min
    cmp rax, 4
    jl .loop

    ; from index -> r10
    movzx eax, byte [inbuf+0]
    sub eax, 'a'
    cmp eax, 7
    ja .loop
    movzx ecx, byte [inbuf+1]
    sub ecx, '1'
    cmp ecx, 7
    ja .loop
    mov edx, 7
    sub edx, ecx
    shl edx, 3
    add edx, eax
    mov r10d, edx

    ; to index -> r11
    movzx eax, byte [inbuf+2]
    sub eax, 'a'
    cmp eax, 7
    ja .loop
    movzx ecx, byte [inbuf+3]
    sub ecx, '1'
    cmp ecx, 7
    ja .loop
    mov edx, 7
    sub edx, ecx
    shl edx, 3
    add edx, eax
    mov r11d, edx

    ; reject empty source
    mov al, [board + r10]
    cmp al, '.'
    je .loop

    ; apply
    mov [board + r11], al
    mov byte [board + r10], '.'
    jmp .loop

.quit:
    mov rdi, outbuf
    EMITM bye, bye_len
    mov r15, rdi
    call flush
    mov rax, 60
    xor rdi, rdi
    syscall

; ---- render board into outbuf, then flush ----
render:
    mov r15, outbuf

    mov rdi, r15
    EMITM esc_clear, esc_len
    mov r15, rdi
    mov rdi, r15
    EMITM border, border_len
    mov r15, rdi

    xor r12, r12            ; row 0..7
.rrow:
    mov al, '8'
    sub al, r12b
    EMITAL                 ; rank label
    EMITC ' '
    EMITC '|'
    EMITC ' '

    mov r13, r12
    shl r13, 3             ; row*8
    xor r14, r14          ; col
.rcol:
    mov rbx, r13
    add rbx, r14
    mov al, [board + rbx]
    EMITAL
    EMITC ' '
    inc r14
    cmp r14, 8
    jl .rcol

    EMITC '|'
    EMITC 10
    inc r12
    cmp r12, 8
    jl .rrow

    mov rdi, r15
    EMITM border, border_len
    mov r15, rdi
    mov rdi, r15
    EMITM files, files_len
    mov r15, rdi
    mov rdi, r15
    EMITM prompt, prompt_len
    mov r15, rdi

    call flush
    ret

; ---- write outbuf[0..r15) to stdout ----
flush:
    mov rdx, r15
    sub rdx, outbuf
    mov rax, 1
    mov rdi, 1
    mov rsi, outbuf
    syscall
    ret
