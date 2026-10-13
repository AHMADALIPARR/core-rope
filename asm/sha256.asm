section .data
sha_k:
    dd 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
    dd 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    dd 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
    dd 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    dd 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
    dd 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    dd 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
    dd 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    dd 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
    dd 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    dd 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
    dd 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    dd 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
    dd 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    dd 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
    dd 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2

section .bss
sha_w: resd 64
sha_state: resd 8
sha_pad: resb 128

section .text

; sha256_compress: rdi = block (64 bytes). Updates sha_state.
sha256_compress:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor ecx, ecx
.wload:
    cmp ecx, 16
    jge .wexp
    mov eax, ecx
    shl eax, 2
    movzx edx, byte [rdi + rax]
    shl edx, 24
    movzx ebx, byte [rdi + rax + 1]
    shl ebx, 16
    or edx, ebx
    movzx ebx, byte [rdi + rax + 2]
    shl ebx, 8
    or edx, ebx
    movzx ebx, byte [rdi + rax + 3]
    or edx, ebx
    mov [sha_w + rcx*4], edx
    inc ecx
    jmp .wload
.wexp:
    cmp ecx, 64
    jge .init
    mov r8, rcx
    sub r8, 15
    mov eax, [sha_w + r8*4]
    mov ebx, eax
    ror ebx, 7
    mov edx, eax
    ror edx, 18
    xor ebx, edx
    mov edx, eax
    shr edx, 3
    xor ebx, edx
    mov r8, rcx
    sub r8, 2
    mov eax, [sha_w + r8*4]
    mov edx, eax
    ror edx, 17
    mov r8d, eax
    ror r8d, 19
    xor edx, r8d
    shr eax, 10
    xor edx, eax
    mov r8, rcx
    sub r8, 16
    mov eax, [sha_w + r8*4]
    add eax, ebx
    mov r8, rcx
    sub r8, 7
    add eax, [sha_w + r8*4]
    add eax, edx
    mov [sha_w + rcx*4], eax
    inc ecx
    jmp .wexp
.init:
    mov eax, [sha_state]
    mov ebx, [sha_state+4]
    mov ecx, [sha_state+8]
    mov edx, [sha_state+12]
    mov r8d, [sha_state+16]
    mov r9d, [sha_state+20]
    mov r10d, [sha_state+24]
    mov r11d, [sha_state+28]
    xor r12, r12
.round:
    cmp r12, 64
    jge .store
    ; sig1
    mov r13d, r8d
    ror r13d, 6
    mov r14d, r8d
    ror r14d, 11
    xor r13d, r14d
    mov r14d, r8d
    ror r14d, 25
    xor r13d, r14d
    ; ch
    mov r14d, r8d
    and r14d, r9d
    mov r15d, r8d
    not r15d
    and r15d, r10d
    xor r14d, r15d
    ; t1 = h + sig1 + ch + k + w
    mov r15d, r11d
    add r15d, r13d
    add r15d, r14d
    add r15d, [sha_k + r12*4]
    add r15d, [sha_w + r12*4]
    ; sig0
    mov r13d, eax
    ror r13d, 2
    mov r14d, eax
    ror r14d, 13
    xor r13d, r14d
    mov r14d, eax
    ror r14d, 22
    xor r13d, r14d
    ; maj
    mov r14d, eax
    and r14d, ebx
    mov esi, eax
    and esi, ecx
    xor r14d, esi
    mov esi, ebx
    and esi, ecx
    xor r14d, esi
    add r13d, r14d
    ; rotate working vars
    mov r11d, r10d
    mov r10d, r9d
    mov r9d, r8d
    mov r8d, edx
    add r8d, r15d
    mov edx, ecx
    mov ecx, ebx
    mov ebx, eax
    mov eax, r15d
    add eax, r13d
    inc r12
    jmp .round
.store:
    add [sha_state], eax
    add [sha_state+4], ebx
    add [sha_state+8], ecx
    add [sha_state+12], edx
    add [sha_state+16], r8d
    add [sha_state+20], r9d
    add [sha_state+24], r10d
    add [sha_state+28], r11d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; sha256_digest(rdi=msg, rsi=len, rdx=out32). len must be <= 119.
sha256_digest:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx
    mov dword [sha_state], 0x6a09e667
    mov dword [sha_state+4], 0xbb67ae85
    mov dword [sha_state+8], 0x3c6ef372
    mov dword [sha_state+12], 0xa54ff53a
    mov dword [sha_state+16], 0x510e527f
    mov dword [sha_state+20], 0x9b05688c
    mov dword [sha_state+24], 0x1f83d9ab
    mov dword [sha_state+28], 0x5be0cd19
    mov rdi, sha_pad
    xor eax, eax
    mov ecx, 128
    rep stosb
    mov rcx, r13
    mov rsi, r12
    mov rdi, sha_pad
    rep movsb
    mov byte [sha_pad + r13], 0x80
    ; padded length
    mov rax, r13
    add rax, 9
    add rax, 63
    shr rax, 6
    shl rax, 6
    mov r12, rax
    mov rax, r13
    shl rax, 3
    mov rcx, r12
    dec rcx
    .lenloop:
        mov [sha_pad + rcx], al
        shr rax, 8
        dec rcx
        mov rdx, r12
        sub rdx, 8
        cmp rcx, rdx
        jge .lenloop
    xor r13, r13
    .blocks:
        cmp r13, r12
        jge .out
        lea rdi, [sha_pad + r13]
        call sha256_compress
        add r13, 64
        jmp .blocks
    .out:
        mov ecx, 8
        xor esi, esi
    .words:
        mov eax, [sha_state + rsi]
        mov edx, eax
        shr edx, 24
        mov [rbx], dl
        mov edx, eax
        shr edx, 16
        mov [rbx+1], dl
        mov edx, eax
        shr edx, 8
        mov [rbx+2], dl
        mov [rbx+3], al
        add rbx, 4
        add rsi, 4
        dec ecx
        jnz .words
    pop r13
    pop r12
    pop rbx
    ret

; digest_prefix(rdi=32 byte digest) -> rax u64 little-endian first 8 bytes
digest_prefix:
    mov rax, [rdi]
    ret
