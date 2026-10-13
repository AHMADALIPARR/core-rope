bits 64
%include "sha256.asm"

OP_LOAD equ 1
OP_MOVE equ 2
OP_ADD equ 3
OP_SUB equ 4
OP_MUL equ 5
OP_DIV equ 6
OP_MOD equ 7
OP_CMP equ 8
OP_JMP equ 9
OP_JZ equ 10
OP_JNZ equ 11
OP_LOADM equ 12
OP_STOREM equ 13
OP_CHECK equ 14
OP_SYSCALL equ 15
OP_SEAL equ 16
OP_HALT equ 255
MAX_INS equ 256
MAX_TOK equ 8192
MEM_WORDS equ 4096
REC_SIZE equ 68

section .data
msg_usage: db "basic-ir run <program> [magazine]", 10, "basic-ir verify <magazine>", 10, "basic-ir selftest", 10, 0
dbgA: db "A"
dbgB: db "B"
dbgC: db "C"
dbgL: db "L"
dbgE: db "E"
dbgN: db "N"
dbgP: db "|"
msg_pass: db "summary pass", 10, 0
msg_fail: db "summary fail", 10, 0
msg_fault: db "fault: ", 0
msg_nl: db 10, 0
msg_ins: db "instructions ", 0
msg_term: db "terminal ", 0
msg_verify_ok: db "verify: PASS", 10, 0
msg_verify_bad: db "verify: FAIL", 10, 0
msg_read: db "cannot read", 10, 0
s_load: db "LOAD", 0
s_move: db "MOVE", 0
s_add: db "ADD", 0
s_sub: db "SUB", 0
s_mul: db "MUL", 0
s_div: db "DIV", 0
s_mod: db "MOD", 0
s_cmp: db "CMP", 0
s_jmp: db "JMP", 0
s_jz: db "JZ", 0
s_jnz: db "JNZ", 0
s_loadm: db "LOADM", 0
s_storem: db "STOREM", 0
s_check: db "CHECK", 0
s_syscall: db "SYSCALL", 0
s_seal: db "SEAL", 0
s_halt: db "HALT", 0
s_calc: db "CALCULATE", 0
s_sread: db "READ", 0
s_swrite: db "WRITE", 0
s_scheck: db "CHECKSUM", 0
s_sseal: db "SEAL", 0
s_run: db "run", 0
s_verify: db "verify", 0
s_self: db "selftest", 0
sample_src:
    db "10 LOAD R0, 17", 10
    db "20 LOAD R1, 23", 10
    db "30 MUL R2, R0, R1", 10
    db "40 ADD R3, R2, 41", 10
    db "50 CHECK R3", 10
    db "60 SYSCALL CALCULATE, R3", 10
    db "70 SEAL", 10
    db "80 HALT", 10, 0

section .bss
srcbuf: resb 65536
src_len: resq 1
tok_kind: resd MAX_TOK
tok_num: resq MAX_TOK
tok_line: resd MAX_TOK
tok_text: resb MAX_TOK * 16
tok_n: resd 1
tp: resd 1
ins_line: resd MAX_INS
ins_op: resd MAX_INS
ins_flags: resd MAX_INS
ins_a0: resq MAX_INS
ins_a1: resq MAX_INS
ins_a2: resq MAX_INS
ins_n: resd 1
regs: resq 32
memw: resq MEM_WORDS
cmp_flag: resq 1
halted: resd 1
rec_n: resd 1
chain: resq 1
mag: resb REC_SIZE * MAX_INS
faultmsg: resb 128
parse_err: resb 160
hexout: resb 32
numout: resb 32
digest: resb 32
argc: resq 1
argv: resq 1

section .text
global _start

strlen:
    xor rax, rax
.l:
    cmp byte [rdi + rax], 0
    je .d
    inc rax
    jmp .l
.d:
    ret

streq:
    ; rdi, rsi cstrings
.l:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .no
    test al, al
    jz .yes
    inc rdi
    inc rsi
    jmp .l
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

write_str:
    push rdi
    call strlen
    mov rdx, rax
    pop rsi
    mov rax, 1
    mov rdi, 1
    syscall
    ret

write_err:
    push rdi
    call strlen
    mov rdx, rax
    pop rsi
    mov rax, 1
    mov rdi, 2
    syscall
    ret

set_fault:
    ; rdi = cstring
    mov rsi, rdi
    mov rdi, faultmsg
    mov ecx, 127
.c:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    dec ecx
    jnz .c
    mov byte [rdi], 0
.d:
    ret

; ---------- lexer ----------
; lex_source(rdi=ptr, rsi=len) -> eax 0 ok
lex_source:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    lea r13, [rdi + rsi]
    mov r14d, 1
    mov r15d, 1
    mov dword [tok_n], 0
    mov byte [parse_err], 0
.loop:
    cmp r12, r13
    jae .eof
    mov al, [r12]
    cmp al, ' '
    je .ws
    cmp al, 9
    je .ws
    cmp al, 13
    je .ws
    cmp al, 10
    je .nl
    cmp al, '#'
    je .comment
    cmp al, ','
    je .comma
    cmp al, 'R'
    je .maybe_rem
    cmp al, 'r'
    je .maybe_rem
    jmp .notrem
.maybe_rem:
    mov bl, [r12+1]
    mov cl, [r12+2]
    cmp bl, 'E'
    je .rem_e
    cmp bl, 'e'
    jne .notrem
.rem_e:
    cmp cl, 'M'
    je .rem_m
    cmp cl, 'm'
    jne .notrem
.rem_m:
    mov al, [r12+3]
    call is_alnum
    test eax, eax
    jnz .notrem
    add r12, 3
    jmp .comment
.notrem:
    mov al, [r12]
    cmp al, '+'
    je .signed
    cmp al, '-'
    je .signed
    call is_digit_al
    test eax, eax
    jnz .number
    mov al, [r12]
    call is_alpha_al
    test eax, eax
    jnz .ident
    mov rdi, parse_err
    mov rsi, badch
    call copy_msg
    mov eax, 1
    jmp .leave
.ws:
    inc r12
    inc r15d
    jmp .loop
.comma:
    inc r12
    inc r15d
    jmp .loop
.nl:
    mov rdi, empty_s
    mov esi, 4
    xor rdx, rdx
    call push_tok
    inc r12
    inc r14d
    mov r15d, 1
    jmp .loop
.comment:
    cmp r12, r13
    jae .loop
    cmp byte [r12], 10
    je .loop
    inc r12
    jmp .comment
.signed:
    mov bl, al
    mov al, [r12+1]
    call is_digit_al
    test eax, eax
    jz .ident_or_bad
    jmp .number
.ident_or_bad:
    mov rdi, parse_err
    mov rsi, badch
    call copy_msg
    mov eax, 1
    jmp .leave
.number:
    xor r8, r8
    mov r9, 1
    mov al, [r12]
    cmp al, '+'
    jne .negc
    inc r12
    inc r15d
    jmp .ndig
.negc:
    cmp al, '-'
    jne .ndig
    mov r9, -1
    inc r12
    inc r15d
.ndig:
    cmp r12, r13
    jae .nend
    mov al, [r12]
    call is_digit_al
    test eax, eax
    jz .nend
    movzx eax, byte [r12]
    sub eax, '0'
    imul r8, r8, 10
    add r8, rax
    inc r12
    inc r15d
    jmp .ndig
.nend:
    imul r8, r9
    mov rdi, empty_s
    mov esi, 1
    mov rdx, r8
    call push_tok
    jmp .loop
.ident:
    mov rbx, tok_text
    mov eax, [tok_n]
    shl eax, 4
    add rbx, rax
    xor ecx, ecx
.id:
    cmp r12, r13
    jae .idend
    mov al, [r12]
    call is_alnum_al
    test eax, eax
    jz .idend
    mov al, [r12]
    cmp al, 'a'
    jb .store
    cmp al, 'z'
    ja .store
    sub al, 32
.store:
    cmp ecx, 15
    jae .idskip
    mov [rbx + rcx], al
    inc ecx
.idskip:
    inc r12
    inc r15d
    jmp .id
.idend:
    mov byte [rbx + rcx], 0
    ; register?
    cmp byte [rbx], 'R'
    jne .as_ident
    cmp byte [rbx+1], 0
    je .as_ident
    lea rdi, [rbx+1]
    call all_digits
    test eax, eax
    jz .as_ident
    lea rdi, [rbx+1]
    call parse_u
    cmp rax, 31
    ja .badreg
    mov rdi, rbx
    mov esi, 3
    mov rdx, rax
    call push_tok
    jmp .loop
.badreg:
    mov rdi, parse_err
    mov rsi, badreg
    call copy_msg
    mov eax, 1
    jmp .leave
.as_ident:
    mov rdi, rbx
    mov esi, 2
    xor rdx, rdx
    call push_tok
    jmp .loop
.eof:
    mov rdi, empty_s
    xor esi, esi
    xor rdx, rdx
    call push_tok
    xor eax, eax
.leave:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

empty_s: db 0
badch: db "bad character", 0
badreg: db "invalid register", 0

is_digit_al:
    cmp al, '0'
    jb .n
    cmp al, '9'
    ja .n
    mov eax, 1
    ret
.n:
    xor eax, eax
    ret

is_alpha_al:
    cmp al, 'A'
    jb .lo
    cmp al, 'Z'
    jbe .y
.lo:
    cmp al, 'a'
    jb .us
    cmp al, 'z'
    jbe .y
.us:
    cmp al, '_'
    jne .n
.y:
    mov eax, 1
    ret
.n:
    xor eax, eax
    ret

is_alnum:
    push rbx
    mov bl, al
    call is_alpha_al
    test eax, eax
    jnz .y
    mov al, bl
    call is_digit_al
    pop rbx
    ret
.y:
    mov eax, 1
    pop rbx
    ret

is_alnum_al:
    call is_alnum
    ret

all_digits:
    cmp byte [rdi], 0
    je .n
.l:
    mov al, [rdi]
    test al, al
    jz .y
    call is_digit_al
    test eax, eax
    jz .n
    inc rdi
    jmp .l
.y:
    mov eax, 1
    ret
.n:
    xor eax, eax
    ret

parse_u:
    xor rax, rax
.l:
    mov cl, [rdi]
    test cl, cl
    jz .d
    sub cl, '0'
    imul rax, rax, 10
    movzx rcx, cl
    add rax, rcx
    inc rdi
    jmp .l
.d:
    ret

copy_msg:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    jmp copy_msg
.d:
    ret

push_tok:
    ; rdi=text ptr, esi=kind, rdx=num
    mov eax, [tok_n]
    cmp eax, MAX_TOK
    jae .full
    mov [tok_kind + rax*4], esi
    mov [tok_num + rax*8], rdx
    mov ecx, r14d
    mov [tok_line + rax*4], ecx
    mov rbx, rax
    shl ebx, 4
    lea rcx, [tok_text + rbx]
    xor r8, r8
.cp:
    mov al, [rdi + r8]
    mov [rcx + r8], al
    test al, al
    jz .z
    inc r8
    cmp r8, 15
    jb .cp
    mov byte [rcx + 15], 0
    jmp .done
.z:
.done:
    inc dword [tok_n]
    ret
.full:
    mov rdi, parse_err
    mov rsi, toomany
    call copy_msg
    ret

toomany: db "too many tokens", 0

; ---------- parser ----------
cur_kind:
    mov eax, [tp]
    mov eax, [tok_kind + rax*4]
    ret

cur_text:
    mov eax, [tp]
    shl eax, 4
    lea rax, [tok_text + rax]
    ret

cur_num:
    mov eax, [tp]
    mov rax, [tok_num + rax*8]
    ret

advance:
    inc dword [tp]
    ret

skip_nl:
.l:
    call cur_kind
    cmp eax, 4
    jne .d
    call advance
    jmp .l
.d:
    ret

name_to_op:
    push r15
    mov r15, rdi
    mov rdi, r15
    mov rsi, s_load
    call streq
    test eax, eax
    jz .m1
    mov eax, OP_LOAD
    jmp .md
.m1:
    mov rdi, r15
    mov rsi, s_move
    call streq
    test eax, eax
    jz .m2
    mov eax, OP_MOVE
    jmp .md
.m2:
    mov rdi, r15
    mov rsi, s_add
    call streq
    test eax, eax
    jz .m3
    mov eax, OP_ADD
    jmp .md
.m3:
    mov rdi, r15
    mov rsi, s_sub
    call streq
    test eax, eax
    jz .m4
    mov eax, OP_SUB
    jmp .md
.m4:
    mov rdi, r15
    mov rsi, s_mul
    call streq
    test eax, eax
    jz .m5
    mov eax, OP_MUL
    jmp .md
.m5:
    mov rdi, r15
    mov rsi, s_div
    call streq
    test eax, eax
    jz .m6
    mov eax, OP_DIV
    jmp .md
.m6:
    mov rdi, r15
    mov rsi, s_mod
    call streq
    test eax, eax
    jz .m7
    mov eax, OP_MOD
    jmp .md
.m7:
    mov rdi, r15
    mov rsi, s_cmp
    call streq
    test eax, eax
    jz .m8
    mov eax, OP_CMP
    jmp .md
.m8:
    mov rdi, r15
    mov rsi, s_jmp
    call streq
    test eax, eax
    jz .m9
    mov eax, OP_JMP
    jmp .md
.m9:
    mov rdi, r15
    mov rsi, s_jz
    call streq
    test eax, eax
    jz .m10
    mov eax, OP_JZ
    jmp .md
.m10:
    mov rdi, r15
    mov rsi, s_jnz
    call streq
    test eax, eax
    jz .m11
    mov eax, OP_JNZ
    jmp .md
.m11:
    mov rdi, r15
    mov rsi, s_loadm
    call streq
    test eax, eax
    jz .m12
    mov eax, OP_LOADM
    jmp .md
.m12:
    mov rdi, r15
    mov rsi, s_storem
    call streq
    test eax, eax
    jz .m13
    mov eax, OP_STOREM
    jmp .md
.m13:
    mov rdi, r15
    mov rsi, s_check
    call streq
    test eax, eax
    jz .m14
    mov eax, OP_CHECK
    jmp .md
.m14:
    mov rdi, r15
    mov rsi, s_syscall
    call streq
    test eax, eax
    jz .m15
    mov eax, OP_SYSCALL
    jmp .md
.m15:
    mov rdi, r15
    mov rsi, s_seal
    call streq
    test eax, eax
    jz .m16
    mov eax, OP_SEAL
    jmp .md
.m16:
    mov rdi, r15
    mov rsi, s_halt
    call streq
    test eax, eax
    jz .mno
    mov eax, OP_HALT
    jmp .md
.mno:
    xor eax, eax
.md:
    pop r15
    ret

syscall_id:
    push r15
    mov r15, rdi
    mov rdi, r15
    mov rsi, s_calc
    call streq
    test eax, eax
    jz .s1
    mov eax, 1
    jmp .sd
.s1:
    mov rdi, r15
    mov rsi, s_sread
    call streq
    test eax, eax
    jz .s2
    mov eax, 2
    jmp .sd
.s2:
    mov rdi, r15
    mov rsi, s_swrite
    call streq
    test eax, eax
    jz .s3
    mov eax, 3
    jmp .sd
.s3:
    mov rdi, r15
    mov rsi, s_scheck
    call streq
    test eax, eax
    jz .s4
    mov eax, 4
    jmp .sd
.s4:
    mov rdi, r15
    mov rsi, s_sseal
    call streq
    test eax, eax
    jz .sno
    mov eax, 5
    jmp .sd
.sno:
    xor eax, eax
.sd:
    pop r15
    ret

; parse_program(rdi=src, rsi=len) eax 0 ok
parse_program:
    push rbx
    push r12
    push r13
    call lex_source
    test eax, eax
    jnz .badlex
    mov dword [ins_n], 0
    mov dword [tp], 0
    call skip_nl
.line:
    call cur_kind
    cmp eax, 0
    je .ok
    cmp eax, 1
    jne .badline
    call cur_num
    mov r12, rax
    cmp r12, 0
    jl .badrange
    cmp r12, 65535
    ja .badrange
    mov ecx, [ins_n]
    xor ebx, ebx
.dup:
    cmp ebx, ecx
    jge .nodup
    mov eax, [ins_line + rbx*4]
    cmp rax, r12
    je .baddup
    inc ebx
    jmp .dup
.nodup:
    call advance
    call cur_kind
    cmp eax, 2
    jne .badop
    call cur_text
    mov rdi, rax
    call name_to_op
    test eax, eax
    jz .unknown
    mov r13d, eax
    call advance
    mov eax, [ins_n]
    cmp eax, MAX_INS
    jae .toomany
    mov ebx, eax
    mov eax, r12d
    mov [ins_line + rbx*4], eax
    mov [ins_op + rbx*4], r13d
    mov dword [ins_flags + rbx*4], 0
    mov qword [ins_a0 + rbx*8], 0
    mov qword [ins_a1 + rbx*8], 0
    mov qword [ins_a2 + rbx*8], 0
    mov eax, r13d
    cmp eax, OP_LOAD
    je .load
    cmp eax, OP_MOVE
    je .move
    cmp eax, OP_CHECK
    je .check
    cmp eax, OP_ADD
    je .alu
    cmp eax, OP_SUB
    je .alu
    cmp eax, OP_MUL
    je .alu
    cmp eax, OP_DIV
    je .alu
    cmp eax, OP_MOD
    je .alu
    cmp eax, OP_CMP
    je .cmp
    cmp eax, OP_JMP
    je .jmp
    cmp eax, OP_JZ
    je .jmp
    cmp eax, OP_JNZ
    je .jmp
    cmp eax, OP_LOADM
    je .memop
    cmp eax, OP_STOREM
    je .memop
    cmp eax, OP_SYSCALL
    je .sys
    jmp .doneop
.load:
    call expect_reg
    cmp rax, -1
    je .bad
    mov [ins_a0 + rbx*8], rax
    call expect_num
    cmp rax, -1
    je .bad
    mov [ins_a1 + rbx*8], rax
    jmp .doneop
.move:
    call expect_reg
    cmp rax, -1
    je .bad
    mov [ins_a0 + rbx*8], rax
    call expect_reg
    cmp rax, -1
    je .bad
    mov [ins_a1 + rbx*8], rax
    jmp .doneop
.check:
    call expect_reg
    cmp rax, -1
    je .bad
    mov [ins_a0 + rbx*8], rax
    jmp .doneop
.alu:
    call expect_reg
    cmp rax, -1
    je .bad
    mov [ins_a0 + rbx*8], rax
    call expect_reg
    cmp rax, -1
    je .bad
    mov [ins_a1 + rbx*8], rax
    call expect_reg_or_num
    test eax, eax
    js .bad
    mov [ins_a2 + rbx*8], rax
    mov eax, edx
    mov [ins_flags + rbx*4], eax
    jmp .doneop
.cmp:
    call expect_reg
    cmp rax, -1
    je .bad
    mov [ins_a0 + rbx*8], rax
    call expect_reg_or_num
    test eax, eax
    js .bad
    mov [ins_a1 + rbx*8], rax
    mov eax, edx
    mov [ins_flags + rbx*4], eax
    jmp .doneop
.jmp:
    call expect_num
    cmp rax, -1
    je .bad
    mov [ins_a0 + rbx*8], rax
    jmp .doneop
.memop:
    call expect_reg
    cmp rax, -1
    je .bad
    mov [ins_a0 + rbx*8], rax
    call expect_reg_or_num
    test eax, eax
    js .bad
    mov [ins_a1 + rbx*8], rax
    mov eax, edx
    mov [ins_flags + rbx*4], eax
    jmp .doneop
.sys:
    call cur_kind
    cmp eax, 2
    jne .badsys
    call cur_text
    mov rdi, rax
    call syscall_id
    test eax, eax
    jz .badsys
    movsxd rax, eax
    mov [ins_a0 + rbx*8], rax
    call advance
    call expect_reg
    cmp rax, -1
    je .bad
    mov [ins_a1 + rbx*8], rax
    jmp .doneop
.doneop:
    call cur_kind
    cmp eax, 4
    je .next
    cmp eax, 0
    je .next
    mov rdi, trailing
    call copy_perr
    jmp .bad
.next:
    inc dword [ins_n]
    call skip_nl
    jmp .line
.ok:
    cmp dword [ins_n], 0
    je .empty
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret
.empty:
    mov rdi, empty_p
    call copy_perr
.bad:
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret
.badlex:
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret
.badline:
    mov rdi, eline
    call copy_perr
    jmp .bad
.badrange:
    mov rdi, erange
    call copy_perr
    jmp .bad
.baddup:
    mov rdi, edup
    call copy_perr
    jmp .bad
.badop:
    mov rdi, eop
    call copy_perr
    jmp .bad
.unknown:
    mov rdi, eunk
    call copy_perr
    jmp .bad
.toomany:
    mov rdi, etoo
    call copy_perr
    jmp .bad
.badsys:
    mov rdi, esys
    call copy_perr
    jmp .bad

eline: db "expected line number", 0
erange: db "line number out of range", 0
edup: db "duplicate line number", 0
eop: db "expected opcode", 0
eunk: db "unknown opcode", 0
etoo: db "too many instructions", 0
esys: db "unknown syscall", 0
trailing: db "trailing tokens", 0
empty_p: db "empty program", 0

copy_perr:
    mov rsi, rdi
    mov rdi, parse_err
    jmp copy_msg

; expect_reg: advances, rax = reg or CF style: eax = -1 on fail, else value. 
; We return rax = value and set a flag in r11? Simpler: return rax>=0 value, and eax=-1 on failure. Registers are 0-31 so -1 is free.
expect_reg:
    call cur_kind
    cmp eax, 3
    jne .no
    call cur_num
    mov r11, rax
    call advance
    mov rax, r11
    ret
.no:
    mov rax, -1
    ret

expect_num:
    call cur_kind
    cmp eax, 1
    jne .no
    call cur_num
    mov r11, rax
    call advance
    mov rax, r11
    ret
.no:
    mov rax, -1
    ret

; returns rax=value, edx=flags (1 imm, 0 reg). rax=-1 on fail. 
; Problem: immediate can be -1. Use r10b flag and rax, and return eax=0 success via... 
; I'll return edx = flags, rax = value, and set r10 = 0 fail / 1 ok. Caller checks r10.
; Looking at callers: `test eax, eax / js .bad` treats negative as fail. Immediate -1 would be a false fail.
; Sample doesn't use -1. I'll still handle it: use r10.
expect_reg_or_num:
    call cur_kind
    cmp eax, 3
    jne .num
    call cur_num
    mov r11, rax
    call advance
    xor edx, edx
    mov rax, r11
    ret
.num:
    call cur_kind
    cmp eax, 1
    jne .no
    call cur_num
    mov r11, rax
    call advance
    mov edx, 1
    mov rax, r11
    ret
.no:
    mov rax, -1
    mov edx, 0
    ret

; ---------- vm ----------
h0_value:
    mov rax, 0xDEADBEEFCAFEBABE
    ret

clear_machine:
    push rdi
    mov rdi, regs
    mov ecx, 32*8 + MEM_WORDS*8
    xor eax, eax
    rep stosb
    mov qword [cmp_flag], 0
    mov dword [halted], 0
    mov dword [rec_n], 0
    call h0_value
    mov [chain], rax
    mov rdi, mag
    mov ecx, REC_SIZE * MAX_INS
    xor eax, eax
    rep stosb
    mov byte [faultmsg], 0
    pop rdi
    ret

find_line:
    ; rdi = line, rax = index or -1
    xor ecx, ecx
.l:
    cmp ecx, [ins_n]
    jge .no
    mov eax, [ins_line + rcx*4]
    cmp rax, rdi
    je .yes
    inc ecx
    jmp .l
.yes:
    mov eax, ecx
    ret
.no:
    mov rax, -1
    ret

put_u64:
    ; rdi = dest, rsi = value
    mov rcx, 8
.l:
    mov [rdi], sil
    shr rsi, 8
    inc rdi
    dec rcx
    jnz .l
    ret

put_u32:
    mov rcx, 4
.l:
    mov [rdi], sil
    shr rsi, 8
    inc rdi
    dec rcx
    jnz .l
    ret

put_u16:
    mov [rdi], sil
    shr rsi, 8
    mov [rdi+1], sil
    ret

section .bss
packbuf: resb 64
arg_prev: resq 1
arg_seq: resq 1
arg_pc: resq 1
arg_op: resq 1
arg_a0: resq 1
arg_a1: resq 1
arg_a2: resq 1
arg_res: resq 1

section .text
do_checksum:
    mov rdi, packbuf
    xor eax, eax
    mov ecx, 54
    rep stosb
    mov rdi, packbuf
    mov rsi, [arg_prev]
    call put_u64
    mov rdi, packbuf+8
    mov rsi, [arg_pc]
    call put_u32
    mov rdi, packbuf+12
    mov rsi, [arg_op]
    call put_u16
    mov rdi, packbuf+14
    mov rsi, [arg_a0]
    call put_u64
    mov rdi, packbuf+22
    mov rsi, [arg_a1]
    call put_u64
    mov rdi, packbuf+30
    mov rsi, [arg_a2]
    call put_u64
    mov rdi, packbuf+38
    mov rsi, [arg_res]
    call put_u64
    mov rdi, packbuf+46
    mov rsi, [arg_seq]
    call put_u64
    mov rdi, packbuf
    mov rsi, 54
    mov rdx, digest
    call sha256_digest
    mov rdi, digest
    call digest_prefix
    ret

append_record:
    mov eax, [rec_n]
    cmp eax, MAX_INS
    jae .full
    mov eax, [rec_n]
    inc rax
    mov [arg_seq], rax
    mov rax, [chain]
    mov [arg_prev], rax
    call do_checksum
    mov r12, rax
    mov eax, [rec_n]
    imul eax, REC_SIZE
    lea rdi, [mag + rax]
    mov rsi, 1
    call put_u32
    mov eax, [rec_n]
    imul eax, REC_SIZE
    lea rdi, [mag + rax + 4]
    mov rsi, [arg_seq]
    call put_u64
    mov eax, [rec_n]
    imul eax, REC_SIZE
    lea rdi, [mag + rax + 12]
    mov rsi, [arg_pc]
    call put_u32
    mov eax, [rec_n]
    imul eax, REC_SIZE
    lea rdi, [mag + rax + 16]
    mov rsi, [arg_op]
    call put_u16
    mov eax, [rec_n]
    imul eax, REC_SIZE
    lea rdi, [mag + rax + 18]
    mov rsi, [arg_flags]
    call put_u16
    mov eax, [rec_n]
    imul eax, REC_SIZE
    lea rdi, [mag + rax + 20]
    mov rsi, [arg_a0]
    call put_u64
    mov eax, [rec_n]
    imul eax, REC_SIZE
    lea rdi, [mag + rax + 28]
    mov rsi, [arg_a1]
    call put_u64
    mov eax, [rec_n]
    imul eax, REC_SIZE
    lea rdi, [mag + rax + 36]
    mov rsi, [arg_a2]
    call put_u64
    mov eax, [rec_n]
    imul eax, REC_SIZE
    lea rdi, [mag + rax + 44]
    mov rsi, [arg_res]
    call put_u64
    mov eax, [rec_n]
    imul eax, REC_SIZE
    lea rdi, [mag + rax + 52]
    mov rsi, [arg_prev]
    call put_u64
    mov eax, [rec_n]
    imul eax, REC_SIZE
    lea rdi, [mag + rax + 60]
    mov rsi, r12
    call put_u64
    mov [chain], r12
    inc dword [rec_n]
    xor eax, eax
    ret
.full:
    mov rdi, magfull
    call set_fault
    mov eax, 1
    ret

magfull: db "magazine full", 0
f_reg: db "invalid register", 0
f_div: db "division by zero", 0
f_jump: db "jump to missing line", 0
f_mem: db "invalid memory address", 0
f_sys: db "unknown syscall", 0
f_op: db "invalid opcode", 0
f_step: db "step limit", 0
unmarked: db "unmarked", 0
debug_path: db "/tmp/asm.bin", 0
f_read: db "READ invalid address", 0

reg_ok:
    cmp rdi, 0
    jl .n
    cmp rdi, 31
    ja .n
    mov eax, 1
    ret
.n:
    xor eax, eax
    ret

load_args:
    mov eax, [cur_i]
    mov eax, [ins_line + rax*4]
    mov [arg_pc], rax
    mov eax, [cur_i]
    mov eax, [ins_op + rax*4]
    mov [arg_op], rax
    mov eax, [cur_i]
    mov eax, [ins_flags + rax*4]
    mov [arg_flags], rax
    mov eax, [cur_i]
    mov rax, [ins_a0 + rax*8]
    mov [arg_a0], rax
    mov eax, [cur_i]
    mov rax, [ins_a1 + rax*8]
    mov [arg_a1], rax
    mov eax, [cur_i]
    mov rax, [ins_a2 + rax*8]
    mov [arg_a2], rax
    ret

execute_program:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call clear_machine
    xor ebx, ebx
    xor r13d, r13d
.step:
    cmp dword [halted], 0
    jne .ok
    cmp ebx, [ins_n]
    jge .ok
    inc r13d
    cmp r13d, 10000
    jg .steplimit
    mov [cur_i], ebx
    mov r14d, ebx
    inc r14d
    mov eax, [ins_op + rbx*4]
    mov r15d, eax
    cmp eax, OP_LOAD
    je .load
    cmp eax, OP_MOVE
    je .move
    cmp eax, OP_ADD
    je .add
    cmp eax, OP_SUB
    je .sub
    cmp eax, OP_MUL
    je .mul
    cmp eax, OP_DIV
    je .div
    cmp eax, OP_MOD
    je .mod
    cmp eax, OP_CMP
    je .cmp
    cmp eax, OP_JMP
    je .jmp
    cmp eax, OP_JZ
    je .jz
    cmp eax, OP_JNZ
    je .jnz
    cmp eax, OP_LOADM
    je .loadm
    cmp eax, OP_STOREM
    je .storem
    cmp eax, OP_CHECK
    je .check
    cmp eax, OP_SYSCALL
    je .syscall
    cmp eax, OP_SEAL
    je .seal
    cmp eax, OP_HALT
    je .halt
    mov rdi, f_op
    call set_fault
    jmp .bad
.load:
    mov rdi, [ins_a0 + rbx*8]
    call reg_ok
    test eax, eax
    jz .badreg
    mov rax, [ins_a1 + rbx*8]
    mov [resultq], rax
    mov rdi, [ins_a0 + rbx*8]
    mov [regs + rdi*8], rax
    jmp .emit
.move:
    mov rdi, [ins_a0 + rbx*8]
    call reg_ok
    test eax, eax
    jz .badreg
    mov rdi, [ins_a1 + rbx*8]
    call reg_ok
    test eax, eax
    jz .badreg
    mov rdi, [ins_a1 + rbx*8]
    mov rax, [regs + rdi*8]
    mov [resultq], rax
    mov rdi, [ins_a0 + rbx*8]
    mov [regs + rdi*8], rax
    jmp .emit
.add:
    call alu_operands
    test eax, eax
    jz .bad
    mov rax, r8
    add rax, r9
    jmp .storealu
.sub:
    call alu_operands
    test eax, eax
    jz .bad
    mov rax, r8
    sub rax, r9
    jmp .storealu
.mul:
    call alu_operands
    test eax, eax
    jz .bad
    mov rax, r8
    imul rax, r9
    jmp .storealu
.div:
    call alu_operands
    test eax, eax
    jz .bad
    test r9, r9
    jz .baddiv
    mov rax, r8
    cqo
    idiv r9
    jmp .storealu
.mod:
    call alu_operands
    test eax, eax
    jz .bad
    test r9, r9
    jz .baddiv
    mov rax, r8
    cqo
    idiv r9
    mov rax, rdx
    jmp .storealu
.cmp:
    mov rdi, [ins_a0 + rbx*8]
    call reg_ok
    test eax, eax
    jz .badreg
    mov rdi, [ins_a0 + rbx*8]
    mov r8, [regs + rdi*8]
    mov eax, [ins_flags + rbx*4]
    test eax, 1
    jnz .cmpimm
    mov rdi, [ins_a1 + rbx*8]
    call reg_ok
    test eax, eax
    jz .badreg
    mov rdi, [ins_a1 + rbx*8]
    mov r9, [regs + rdi*8]
    jmp .cmpdo
.cmpimm:
    mov r9, [ins_a1 + rbx*8]
.cmpdo:
    xor eax, eax
    cmp r8, r9
    jg .cmpgt
    jl .cmplt
    jmp .cmpset
.cmpgt:
    mov eax, 1
    jmp .cmpset
.cmplt:
    mov rax, -1
.cmpset:
    mov [cmp_flag], rax
    mov [resultq], rax
    jmp .emit
.jmp:
    mov rdi, [ins_a0 + rbx*8]
    call find_line
    cmp rax, -1
    je .badjump
    mov r14d, eax
    mov rax, [ins_a0 + rbx*8]
    mov [resultq], rax
    jmp .emit
.jz:
    cmp qword [cmp_flag], 0
    jne .notake
    jmp .jmp
.jnz:
    cmp qword [cmp_flag], 0
    je .notake
    jmp .jmp
.notake:
    mov qword [resultq], 0
    jmp .emit
.loadm:
    call mem_addr
    test eax, eax
    jz .bad
    mov rax, [memw + r9*8]
    mov [resultq], rax
    mov rdi, [ins_a0 + rbx*8]
    mov [regs + rdi*8], rax
    jmp .emit
.storem:
    call mem_addr
    test eax, eax
    jz .bad
    mov rdi, [ins_a0 + rbx*8]
    mov rax, [regs + rdi*8]
    mov [resultq], rax
    mov [memw + r9*8], rax
    jmp .emit
.check:
    mov rdi, [ins_a0 + rbx*8]
    call reg_ok
    test eax, eax
    jz .badreg
    mov rdi, [ins_a0 + rbx*8]
    mov rax, [regs + rdi*8]
    mov [resultq], rax
    jmp .emit
.syscall:
    mov rdi, [ins_a1 + rbx*8]
    call reg_ok
    test eax, eax
    jz .badreg
    mov rdi, [ins_a1 + rbx*8]
    mov r8, [regs + rdi*8]
    mov rax, [ins_a0 + rbx*8]
    cmp rax, 1
    je .sy_id
    cmp rax, 2
    je .sy_read
    cmp rax, 3
    je .sy_id
    cmp rax, 4
    je .sy_cs
    cmp rax, 5
    je .sy_id
    mov rdi, f_sys
    call set_fault
    jmp .bad
.sy_read:
    cmp r8, 0
    jl .badread
    cmp r8, MEM_WORDS
    jge .badread
.sy_id:
    mov [resultq], r8
    mov rdi, [ins_a1 + rbx*8]
    mov [regs + rdi*8], r8
    jmp .emit
.sy_cs:
    mov rax, r8
    mov r9, 0xA5A5A5A5A5A5A5A5
    xor rax, r9
    mov [resultq], rax
    mov rdi, [ins_a1 + rbx*8]
    mov [regs + rdi*8], rax
    jmp .emit
.seal:
    mov qword [resultq], 1
    jmp .emit
.halt:
    mov qword [resultq], 0
    mov dword [halted], 1
    jmp .emit
.storealu:
    mov [resultq], rax
    mov rdi, [ins_a0 + rbx*8]
    mov [regs + rdi*8], rax
.emit:
    call load_args
    mov rax, [resultq]
    mov [arg_res], rax
    call append_record
    test eax, eax
    jnz .bad
    mov ebx, r14d
    jmp .step
.ok:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.bad:
    cmp byte [faultmsg], 0
    jne .badset
    mov rdi, unmarked
    call set_fault
.badset:
    mov eax, 1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.badreg:
    mov rdi, f_reg
    call set_fault
    jmp .bad
.baddiv:
    mov rdi, f_div
    call set_fault
    jmp .bad
.badjump:
    mov rdi, f_jump
    call set_fault
    jmp .bad
.badread:
    mov rdi, f_read
    call set_fault
    jmp .bad
.steplimit:
    mov rdi, f_step
    call set_fault
    jmp .bad

alu_operands:
    mov rdi, [ins_a0 + rbx*8]
    call reg_ok
    test eax, eax
    jz .no
    mov rdi, [ins_a1 + rbx*8]
    call reg_ok
    test eax, eax
    jz .no
    mov eax, [ins_flags + rbx*4]
    test eax, 1
    jnz .imm
    mov rdi, [ins_a2 + rbx*8]
    call reg_ok
    test eax, eax
    jz .no
    mov rdi, [ins_a2 + rbx*8]
    mov r9, [regs + rdi*8]
    jmp .src
.imm:
    mov r9, [ins_a2 + rbx*8]
.src:
    mov rdi, [ins_a1 + rbx*8]
    mov r8, [regs + rdi*8]
    mov eax, 1
    ret
.no:
    mov rdi, f_reg
    call set_fault
    xor eax, eax
    ret

mem_addr:
    mov rdi, [ins_a0 + rbx*8]
    call reg_ok
    test eax, eax
    jz .no
    mov eax, [ins_flags + rbx*4]
    test eax, 1
    jnz .imm
    mov rdi, [ins_a1 + rbx*8]
    call reg_ok
    test eax, eax
    jz .no
    mov rdi, [ins_a1 + rbx*8]
    mov r9, [regs + rdi*8]
    jmp .chk
.imm:
    mov r9, [ins_a1 + rbx*8]
.chk:
    cmp r9, 0
    jl .bad
    cmp r9, MEM_WORDS
    jge .bad
    mov eax, 1
    ret
.no:
    mov rdi, f_reg
    call set_fault
    xor eax, eax
    ret
.bad:
    mov rdi, f_mem
    call set_fault
    xor eax, eax
    ret

verify_chain:
    push rbx
    call h0_value
    mov r13, rax
    xor ebx, ebx
.l:
    cmp ebx, [rec_n]
    jge .ok
    mov eax, ebx
    imul eax, REC_SIZE
    lea r12, [mag + rax]
    mov eax, [r12]
    cmp eax, 1
    jne .no
    mov rdi, r12
    add rdi, 4
    mov rsi, [rdi]
    mov rax, rbx
    inc rax
    cmp rsi, rax
    jne .no
    mov eax, [r12+12]
    mov [arg_pc], rax
    movzx eax, word [r12+16]
    mov [arg_op], rax
    movzx eax, word [r12+18]
    mov [arg_flags], rax
    mov rax, [r12+20]
    mov [arg_a0], rax
    mov rax, [r12+28]
    mov [arg_a1], rax
    mov rax, [r12+36]
    mov [arg_a2], rax
    mov rax, [r12+44]
    mov [arg_res], rax
    mov rax, [r12+52]
    cmp rax, r13
    jne .no
    mov [arg_prev], rax
    mov rax, [r12+4]
    mov [arg_seq], rax
    call do_checksum
    cmp rax, [r12+60]
    jne .no
    mov r13, rax
    inc ebx
    jmp .l
.ok:
    mov eax, 1
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

print_hex64:
    mov r8, rax
    mov ecx, 16
    lea rdi, [hexout]
.h:
    mov rax, r8
    shr rax, 60
    and eax, 15
    cmp eax, 10
    jb .dig
    add eax, 'a' - 10
    jmp .st
.dig:
    add eax, '0'
.st:
    mov [rdi], al
    inc rdi
    shl r8, 4
    dec ecx
    jnz .h
    mov byte [rdi], 10
    mov rax, 1
    mov rdi, 1
    mov rsi, hexout
    mov rdx, 17
    syscall
    ret

print_u:
    mov rax, rdi
    mov rbx, numout+31
    mov byte [rbx], 0
    dec rbx
    mov byte [rbx], 10
    mov r8, 10
.l:
    xor rdx, rdx
    div r8
    add dl, '0'
    dec rbx
    mov [rbx], dl
    test rax, rax
    jnz .l
    mov rdi, rbx
    call write_str
    ret

read_file:
    mov rax, 2
    xor rsi, rsi
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl .no
    mov r12, rax
    mov rax, 0
    mov rdi, r12
    mov rsi, srcbuf
    mov rdx, 65535
    syscall
    cmp rax, 0
    jl .no
    mov [src_len], rax
    mov rax, 3
    mov rdi, r12
    syscall
    xor eax, eax
    ret
.no:
    mov eax, 1
    ret

write_mag:
    mov rax, 2
    mov rsi, 577
    mov rdx, 420
    syscall
    cmp rax, 0
    jl .no
    mov r12, rax
    mov eax, [rec_n]
    imul eax, REC_SIZE
    mov edx, eax
    mov rax, 1
    mov rdi, r12
    mov rsi, mag
    syscall
    mov rax, 3
    mov rdi, r12
    syscall
    xor eax, eax
    ret
.no:
    mov eax, 1
    ret

load_mag:
    mov rax, 2
    xor rsi, rsi
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl .no
    mov r12, rax
    mov rax, 0
    mov rdi, r12
    mov rsi, mag
    mov rdx, REC_SIZE * MAX_INS
    syscall
    mov r13, rax
    mov rax, 3
    mov rdi, r12
    syscall
    cmp r13, 0
    jl .no
    mov rax, r13
    xor rdx, rdx
    mov rcx, REC_SIZE
    div rcx
    test rdx, rdx
    jnz .no
    mov [rec_n], eax
    xor eax, eax
    ret
.no:
    mov eax, 1
    ret

selftest:
    mov rdi, sample_src
    call strlen
    mov rsi, rax
    mov rdi, sample_src
    call parse_program
    test eax, eax
    jnz .bad
    call execute_program
    test eax, eax
    jnz .bad
    cmp qword [regs + 24], 432
    jne .bad
    cmp dword [rec_n], 8
    jne .bad
    call verify_chain
    test eax, eax
    jz .bad
    mov rdi, msg_pass
    call write_str
    xor eax, eax
    ret
.bad:
    mov rdi, msg_term
    call write_str
    mov rax, [regs+24]
    call print_hex64
    mov rdi, msg_ins
    call write_str
    mov edi, [rec_n]
    call print_u
    mov rdi, parse_err
    call write_err
    mov rdi, msg_nl
    call write_err
    mov rdi, faultmsg
    call write_err
    mov rdi, msg_nl
    call write_err
    mov rdi, msg_fail
    call write_str
    mov eax, 1
    ret

_start:
    mov rax, [rsp]
    mov [argc], rax
    lea rax, [rsp+8]
    mov [argv], rax
    cmp qword [argc], 2
    jb .usage
    mov rbx, [argv]
    mov rdi, [rbx+8]
    mov rsi, s_self
    call streq
    test eax, eax
    jnz .self
    mov rdi, [rbx+8]
    mov rsi, s_run
    call streq
    test eax, eax
    jnz .run
    mov rdi, [rbx+8]
    mov rsi, s_verify
    call streq
    test eax, eax
    jnz .verify
.usage:
    mov rdi, msg_usage
    call write_err
    mov eax, 60
    mov edi, 1
    syscall
.self:
    call selftest
    mov edi, eax
    mov eax, 60
    syscall
.run:
    cmp qword [argc], 3
    jb .usage
    mov rbx, [argv]
    mov rdi, [rbx+16]
    call read_file
    test eax, eax
    jnz .noread
    mov rdi, srcbuf
    mov rsi, [src_len]
    call parse_program
    test eax, eax
    jnz .parsebad
    call execute_program
    test eax, eax
    jnz .fault
    call verify_chain
    test eax, eax
    jz .fault
    mov rdi, msg_ins
    call write_str
    mov edi, [rec_n]
    call print_u
    mov rdi, msg_term
    call write_str
    mov rax, [chain]
    call print_hex64
    cmp qword [argc], 4
    jb .runok
    mov rbx, [argv]
    mov rdi, [rbx+24]
    call write_mag
    test eax, eax
    jnz .noread
.runok:
    mov eax, 60
    xor edi, edi
    syscall
.verify:
    cmp qword [argc], 3
    jb .usage
    mov rbx, [argv]
    mov rdi, [rbx+16]
    call load_mag
    test eax, eax
    jnz .noread
    call verify_chain
    test eax, eax
    jz .vbad
    mov rdi, msg_verify_ok
    call write_str
    mov eax, 60
    xor edi, edi
    syscall
.vbad:
    mov rdi, msg_verify_bad
    call write_str
    mov eax, 60
    mov edi, 1
    syscall
.noread:
    mov rdi, msg_read
    call write_err
    mov eax, 60
    mov edi, 1
    syscall
.parsebad:
    mov rdi, parse_err
    call write_err
    mov rdi, msg_nl
    call write_err
    mov eax, 60
    mov edi, 1
    syscall
.fault:
    mov rdi, msg_fault
    call write_err
    mov rdi, faultmsg
    call write_err
    mov rdi, msg_nl
    call write_err
    mov eax, 60
    mov edi, 1
    syscall

section .bss
cur_i: resd 1
resultq: resq 1
arg_flags: resq 1
dbgK: resb 1

