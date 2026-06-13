section .data
board_init db "rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR"
esc_clear  db 27,"[2J",27,"[H"
esc_len    equ $-esc_clear
border     db "  +-----------------+",10
border_len equ $-border
files      db 10,"    a b c d e f g h",10
files_len  equ $-files
prompt     db 10,"move (e4 Nf3 exd5 O-O e8=Q, q=quit)> "
prompt_len equ $-prompt
bye        db 10,"here before the question",10
bye_len    equ $-bye
tick       dq 0, 20000000

section .bss
board  resb 64
inbuf  resb 32
outbuf resb 1024
side   resb 1
mpiece resb 1          ; piece letter from SAN (uppercase), 'P' if pawn
mexpl  resb 1          ; 1 if a piece letter was explicitly given
mdest  resb 1          ; destination square 0..63
mfile  resb 1          ; source file hint 0..7, 0xFF none
mrank  resb 1          ; source rank hint as board row 0..7, 0xFF none
mpromo resb 1          ; promotion piece letter (uppercase), 0 none
mpc    resb 1          ; resolved board char to match, 0 = any
mlen   resb 1          ; token length

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
    mov rsi, board_init
    mov rdi, board
    mov rcx, 64
    rep movsb
    mov byte [side], 0

.loop:
    mov rax, 35
    mov rdi, tick
    xor rsi, rsi
    syscall
    call render
    xor eax, eax
    xor edi, edi
    mov rsi, inbuf
    mov edx, 32
    syscall
    test rax, rax
    jle .quit
    cmp byte [inbuf], 'q'
    je .quit

    call san_move
    jmp .loop

.quit:
    mov rdi, outbuf
    EMITM bye, bye_len
    mov r15, rdi
    call flush
    mov eax, 60
    xor edi, edi
    syscall

; ---- SAN front end: parse one line in inbuf, resolve, apply if unique+legal ----
san_move:
    push rbx
    push r12
    push r13
    push r14
    mov al, [inbuf]
    cmp al, 'O'
    je .castle
    cmp al, '0'
    je .castle
    call san_parse
    test eax, eax
    js .done
    call resolve
    jmp .done
.castle:
    call do_castle
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- token length into mlen (chars before first <= ' ') ----
token_len:
    xor ecx, ecx
.tl:
    mov al, [inbuf+rcx]
    cmp al, ' '
    jbe .tl_done
    inc ecx
    cmp ecx, 16
    jl .tl
.tl_done:
    mov [mlen], cl
    ret

; ---- parse SAN move into m* fields. eax=0 ok, -1 fail ----
san_parse:
    mov byte [mfile], 0xFF
    mov byte [mrank], 0xFF
    mov byte [mpromo], 0
    mov byte [mexpl], 0
    mov byte [mpiece], 'P'
    call token_len

    xor edi, edi               ; scan start
    mov al, [inbuf]
    cmp al, 'K'
    je .ispiece
    cmp al, 'Q'
    je .ispiece
    cmp al, 'R'
    je .ispiece
    cmp al, 'B'
    je .ispiece
    cmp al, 'N'
    je .ispiece
    jmp .find_dest
.ispiece:
    mov [mpiece], al
    mov byte [mexpl], 1
    mov edi, 1

.find_dest:
    mov r8d, -1                ; last pair index
    mov edx, edi
.fd_loop:
    movzx eax, byte [mlen]
    sub eax, 1
    cmp edx, eax              ; need j <= len-2
    jge .fd_done
    movzx eax, byte [inbuf+rdx]
    sub eax, 'a'
    cmp eax, 7
    ja .fd_inc
    movzx eax, byte [inbuf+rdx+1]
    sub eax, '1'
    cmp eax, 7
    ja .fd_inc
    mov r8d, edx
.fd_inc:
    inc edx
    jmp .fd_loop
.fd_done:
    cmp r8d, -1
    je .fail

    movzx eax, byte [inbuf+r8]
    sub eax, 'a'
    mov r9d, eax             ; dest file
    movzx eax, byte [inbuf+r8+1]
    sub eax, '1'             ; rank 0..7
    mov ecx, 7
    sub ecx, eax
    shl ecx, 3
    add ecx, r9d
    mov [mdest], cl

    ; hints between start(edi) and dest(r8)
    mov edx, edi
.hint_loop:
    cmp edx, r8d
    jge .hint_done
    movzx eax, byte [inbuf+rdx]
    mov ecx, eax
    sub ecx, 'a'
    cmp ecx, 7
    jbe .set_file
    mov ecx, eax
    sub ecx, '1'
    cmp ecx, 7
    jbe .set_rank
    jmp .hint_next
.set_file:
    mov [mfile], cl
    jmp .hint_next
.set_rank:
    mov eax, 7
    sub eax, ecx
    mov [mrank], al
.hint_next:
    inc edx
    jmp .hint_loop
.hint_done:
    ; promotion after dest pair
    lea edx, [r8+2]
    movzx eax, byte [mlen]
    cmp edx, eax
    jge .ok
    movzx eax, byte [inbuf+rdx]
    cmp al, '='
    jne .promo_test
    inc edx
    movzx eax, byte [mlen]
    cmp edx, eax
    jge .ok
    movzx eax, byte [inbuf+rdx]
.promo_test:
    cmp al, 'Q'
    je .set_promo
    cmp al, 'R'
    je .set_promo
    cmp al, 'B'
    je .set_promo
    cmp al, 'N'
    je .set_promo
    jmp .ok
.set_promo:
    mov [mpromo], al
.ok:
    xor eax, eax
    ret
.fail:
    mov eax, -1
    ret

; ---- find the unique legal source for m*, apply it ----
resolve:
    push rbx
    push r12
    push r13
    push r14
    ; resolved board char to match -> mpc (0 = any)
    mov byte [mpc], 0
    cmp byte [mexpl], 1
    je .have
    cmp byte [mfile], 0xFF
    je .pawn
    cmp byte [mrank], 0xFF
    je .pawn
    jmp .scan                ; full coordinate, any piece
.pawn:
    mov al, 'P'
    jmp .case
.have:
    mov al, [mpiece]
.case:
    cmp byte [side], 0
    je .upper
    or al, 32
.upper:
    mov [mpc], al

.scan:
    xor r12d, r12d           ; count
    xor r13d, r13d           ; chosen src
    xor ebx, ebx             ; square
.sloop:
    mov al, [board+rbx]
    cmp al, '.'
    je .snext
    ; file hint
    movzx eax, byte [mfile]
    cmp eax, 0xFF
    je .nofile
    mov ecx, ebx
    and ecx, 7
    cmp ecx, eax
    jne .snext
.nofile:
    movzx eax, byte [mrank]
    cmp eax, 0xFF
    je .norank
    mov ecx, ebx
    shr ecx, 3
    cmp ecx, eax
    jne .snext
.norank:
    ; piece char
    movzx eax, byte [mpc]
    test eax, eax
    jz .trylegal
    cmp [board+rbx], al
    jne .snext
.trylegal:
    mov edi, ebx
    movzx esi, byte [mdest]
    call legal_move
    test eax, eax
    jz .snext
    inc r12d
    mov r13d, ebx
.snext:
    inc ebx
    cmp ebx, 64
    jl .sloop

    cmp r12d, 1
    jne .rdone               ; none or ambiguous -> ignore

    ; apply r13 -> mdest
    movzx r14d, byte [mdest]
    mov al, [board+r13]
    mov [board+r14], al
    mov byte [board+r13], '.'
    ; promotion
    cmp al, 'P'
    je .wpromo
    cmp al, 'p'
    je .bpromo
    jmp .toggle
.wpromo:
    cmp r14d, 8
    jae .toggle
    mov dl, 'Q'
    cmp byte [mpromo], 0
    je .wput
    mov dl, [mpromo]
.wput:
    mov [board+r14], dl
    jmp .toggle
.bpromo:
    cmp r14d, 56
    jb .toggle
    mov dl, 'q'
    cmp byte [mpromo], 0
    je .bput
    mov dl, [mpromo]
    or dl, 32
.bput:
    mov [board+r14], dl
.toggle:
    xor byte [side], 1
.rdone:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- O-O / O-O-O castling for the side to move ----
do_castle:
    push rbx
    push r12
    push r13
    push r14
    call token_len
    ; count O/0 markers -> queenside if 3
    xor edx, edx
    xor ecx, ecx
.co:
    movzx eax, byte [mlen]
    cmp ecx, eax
    jge .co_done
    mov al, [inbuf+rcx]
    cmp al, 'O'
    je .co_inc
    cmp al, '0'
    je .co_inc
    jmp .co_next
.co_inc:
    inc edx
.co_next:
    inc ecx
    jmp .co
.co_done:
    cmp edx, 2
    jl .cfail
    cmp edx, 3
    ja .cfail
    ; r12=king home, r13=king dest, r14=rook from, ebx=rook dest
    ; choose by side and edx (2=king side, 3=queen side)
    cmp byte [side], 0
    jne .black
    ; white, king e1=60
    cmp edx, 3
    je .wq
    mov r12d, 60
    mov r13d, 62
    mov r14d, 63
    mov ebx, 61
    jmp .verify
.wq:
    mov r12d, 60
    mov r13d, 58
    mov r14d, 56
    mov ebx, 59
    jmp .verify
.black:
    cmp edx, 3
    je .bq
    mov r12d, 4
    mov r13d, 6
    mov r14d, 7
    mov ebx, 5
    jmp .verify
.bq:
    mov r12d, 4
    mov r13d, 2
    mov r14d, 0
    mov ebx, 3

.verify:
    ; king present
    mov al, [board+r12]
    cmp byte [side], 0
    jne .ck_black_king
    cmp al, 'K'
    jne .cfail
    jmp .ck_rook
.ck_black_king:
    cmp al, 'k'
    jne .cfail
.ck_rook:
    mov al, [board+r14]
    cmp byte [side], 0
    jne .ck_black_rook
    cmp al, 'R'
    jne .cfail
    jmp .ck_empty
.ck_black_rook:
    cmp al, 'r'
    jne .cfail

.ck_empty:
    ; squares strictly between king(r12) and rook(r14) must be empty
    mov esi, r12d
    mov edi, r14d
    cmp esi, edi
    jl .order
    xchg esi, edi
.order:
    mov ecx, esi
    inc ecx
.ce_loop:
    cmp ecx, edi
    jge .ck_safe
    cmp byte [board+rcx], '.'
    jne .cfail
    inc ecx
    jmp .ce_loop

.ck_safe:
    ; king home, transit (between home and dest), and dest must be unattacked
    movzx edi, byte [side]
    xor edi, 1               ; attacker side
    mov esi, r12d
    call square_attacked
    test eax, eax
    jnz .cfail
    ; transit square = (home+dest)/2
    mov esi, r12d
    add esi, r13d
    shr esi, 1
    movzx edi, byte [side]
    xor edi, 1
    call square_attacked
    test eax, eax
    jnz .cfail
    mov esi, r13d
    movzx edi, byte [side]
    xor edi, 1
    call square_attacked
    test eax, eax
    jnz .cfail

    ; perform castle
    mov al, [board+r12]
    mov [board+r13], al
    mov byte [board+r12], '.'
    mov al, [board+r14]
    mov [board+rbx], al
    mov byte [board+r14], '.'
    xor byte [side], 1
.cfail:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

legal_move:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edi
    mov r13d, esi
    cmp edi, esi
    je .no
    movzx ebx, byte [board+r12]
    cmp bl, '.'
    je .no
    movzx r14d, byte [board+r13]
    cmp r14b, 'K'
    je .no
    cmp r14b, 'k'
    je .no
    mov al, bl
    call piece_side
    cmp al, [side]
    jne .no
    cmp r14b, '.'
    je .shape
    mov al, r14b
    call piece_side
    cmp al, [side]
    je .no

.shape:
    mov al, bl
    or al, 32
    cmp al, 'p'
    je .pawn
    cmp al, 'n'
    je .knight
    cmp al, 'b'
    je .bishop
    cmp al, 'r'
    je .rook
    cmp al, 'q'
    je .queen
    cmp al, 'k'
    je .king
    jmp .no

.pawn:
    mov eax, r12d
    and eax, 7
    mov ecx, r13d
    and ecx, 7
    sub ecx, eax
    mov eax, r13d
    sub eax, r12d
    cmp byte [side], 0
    jne .black_pawn
    cmp r14b, '.'
    jne .white_capture
    test ecx, ecx
    jne .no
    cmp eax, -8
    je .simulate
    cmp eax, -16
    jne .no
    cmp r12d, 48
    jb .no
    cmp r12d, 55
    ja .no
    cmp byte [board+r12-8], '.'
    jne .no
    jmp .simulate
.white_capture:
    cmp eax, -9
    je .white_diag
    cmp eax, -7
    jne .no
.white_diag:
    cmp ecx, -1
    je .simulate
    cmp ecx, 1
    je .simulate
    jmp .no
.black_pawn:
    cmp r14b, '.'
    jne .black_capture
    test ecx, ecx
    jne .no
    cmp eax, 8
    je .simulate
    cmp eax, 16
    jne .no
    cmp r12d, 8
    jb .no
    cmp r12d, 15
    ja .no
    cmp byte [board+r12+8], '.'
    jne .no
    jmp .simulate
.black_capture:
    cmp eax, 7
    je .black_diag
    cmp eax, 9
    jne .no
.black_diag:
    cmp ecx, -1
    je .simulate
    cmp ecx, 1
    je .simulate
    jmp .no

.knight:
    call deltas
    cmp eax, 1
    je .knight_rank2
    cmp eax, 2
    jne .no
    cmp ecx, 1
    je .simulate
    jmp .no
.knight_rank2:
    cmp ecx, 2
    je .simulate
    jmp .no

.bishop:
    call deltas
    cmp eax, ecx
    jne .no
    jmp .slider
.rook:
    call deltas
    test eax, eax
    jz .slider
    test ecx, ecx
    jz .slider
    jmp .no
.queen:
    call deltas
    cmp eax, ecx
    je .slider
    test eax, eax
    jz .slider
    test ecx, ecx
    jz .slider
    jmp .no
.king:
    call deltas
    cmp eax, 1
    ja .no
    cmp ecx, 1
    ja .no
    jmp .simulate

.slider:
    mov edi, r12d
    mov esi, r13d
    call path_clear
    test eax, eax
    jz .no

.simulate:
    mov al, [board+r12]
    mov dl, [board+r13]
    mov [board+r13], al
    mov byte [board+r12], '.'
    movzx edi, byte [side]
    push rdx
    call king_in_check
    pop rdx
    mov bl, [board+r13]
    mov [board+r12], bl
    mov [board+r13], dl
    test eax, eax
    jnz .no
    mov eax, 1
    jmp .done
.no:
    xor eax, eax
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

piece_side:
    cmp al, 'a'
    setae al
    ret

deltas:
    mov eax, r12d
    shr eax, 3
    mov edx, r13d
    shr edx, 3
    sub eax, edx
    jns .rank_ok
    neg eax
.rank_ok:
    mov ecx, r12d
    and ecx, 7
    mov edx, r13d
    and edx, 7
    sub ecx, edx
    jns .file_ok
    neg ecx
.file_ok:
    ret

path_clear:
    push rbx
    mov eax, esi
    and eax, 7
    mov ecx, edi
    and ecx, 7
    sub eax, ecx
    mov ecx, 0
    test eax, eax
    jz .file_step
    mov ecx, 1
    jg .file_step
    mov ecx, -1
.file_step:
    mov eax, esi
    shr eax, 3
    mov edx, edi
    shr edx, 3
    sub eax, edx
    mov edx, 0
    test eax, eax
    jz .rank_step
    mov edx, 8
    jg .rank_step
    mov edx, -8
.rank_step:
    add ecx, edx
    mov ebx, edi
.walk:
    add ebx, ecx
    cmp ebx, esi
    je .clear
    cmp byte [board+rbx], '.'
    jne .blocked
    jmp .walk
.clear:
    mov eax, 1
    pop rbx
    ret
.blocked:
    xor eax, eax
    pop rbx
    ret

king_in_check:
    push rbx
    push r12
    mov r12d, edi
    xor ebx, ebx
.find:
    mov al, [board+rbx]
    cmp r12d, 0
    jne .black_king
    cmp al, 'K'
    je .found
    jmp .next
.black_king:
    cmp al, 'k'
    je .found
.next:
    inc ebx
    cmp ebx, 64
    jl .find
    mov eax, 1
    jmp .king_done
.found:
    mov edi, ebx
    mov esi, r12d
    xor esi, 1
    call square_attacked
.king_done:
    pop r12
    pop rbx
    ret

square_attacked:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edi
    mov r13d, esi
    xor ebx, ebx
.scan:
    mov al, [board+rbx]
    cmp al, '.'
    je .scan_next
    push rax
    call piece_side
    mov dl, al
    pop rax
    cmp dl, r13b
    jne .scan_next
    mov r14b, al
    or al, 32
    cmp al, 'p'
    je .attack_pawn
    cmp al, 'n'
    je .attack_knight
    cmp al, 'k'
    je .attack_king
    mov al, r14b
    or al, 32
    cmp al, 'b'
    je .bishop_piece
    cmp al, 'r'
    je .rook_piece
    cmp al, 'q'
    je .queen_piece
    jmp .scan_next
.bishop_piece:
    mov edi, ebx
    mov esi, r12d
    call attack_deltas
.attack_bishop:
    cmp eax, ecx
    jne .scan_next
    jmp .attack_slider
.rook_piece:
    mov edi, ebx
    mov esi, r12d
    call attack_deltas
.attack_rook:
    test eax, eax
    jz .attack_slider
    test ecx, ecx
    jz .attack_slider
    jmp .scan_next
.queen_piece:
    mov edi, ebx
    mov esi, r12d
    call attack_deltas
.attack_queen:
    cmp eax, ecx
    je .attack_slider
    test eax, eax
    jz .attack_slider
    test ecx, ecx
    jnz .scan_next
.attack_slider:
    mov edi, ebx
    mov esi, r12d
    call path_clear
    test eax, eax
    jnz .attacked
    jmp .scan_next
.attack_knight:
    mov edi, ebx
    mov esi, r12d
    call attack_deltas
    cmp eax, 1
    je .attack_knight2
    cmp eax, 2
    jne .scan_next
    cmp ecx, 1
    je .attacked
    jmp .scan_next
.attack_knight2:
    cmp ecx, 2
    je .attacked
    jmp .scan_next
.attack_king:
    mov edi, ebx
    mov esi, r12d
    call attack_deltas
    cmp eax, 1
    ja .scan_next
    cmp ecx, 1
    jbe .attacked
    jmp .scan_next
.attack_pawn:
    mov eax, r12d
    sub eax, ebx
    mov ecx, r12d
    and ecx, 7
    mov edx, ebx
    and edx, 7
    sub ecx, edx
    cmp ecx, -1
    je .pawn_file
    cmp ecx, 1
    jne .scan_next
.pawn_file:
    cmp r13d, 0
    jne .black_attack
    cmp eax, -7
    je .attacked
    cmp eax, -9
    je .attacked
    jmp .scan_next
.black_attack:
    cmp eax, 7
    je .attacked
    cmp eax, 9
    je .attacked
.scan_next:
    inc ebx
    cmp ebx, 64
    jl .scan
    xor eax, eax
    jmp .attack_done
.attacked:
    mov eax, 1
.attack_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

attack_deltas:
    mov eax, edi
    shr eax, 3
    mov edx, esi
    shr edx, 3
    sub eax, edx
    jns .arank
    neg eax
.arank:
    mov ecx, edi
    and ecx, 7
    mov edx, esi
    and edx, 7
    sub ecx, edx
    jns .afile
    neg ecx
.afile:
    ret

render:
    mov r15, outbuf
    mov rdi, r15
    EMITM esc_clear, esc_len
    mov r15, rdi
    mov rdi, r15
    EMITM border, border_len
    mov r15, rdi
    xor r12, r12
.rrow:
    mov al, '8'
    sub al, r12b
    EMITAL
    EMITC ' '
    EMITC '|'
    EMITC ' '
    mov r13, r12
    shl r13, 3
    xor r14, r14
.rcol:
    mov rbx, r13
    add rbx, r14
    mov al, [board+rbx]
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

flush:
    mov rdx, r15
    sub rdx, outbuf
    mov eax, 1
    mov edi, 1
    mov rsi, outbuf
    syscall
    ret
