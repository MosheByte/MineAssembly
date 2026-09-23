; testnoise.asm - test-only stand-in for src/noise.asm: plain gustavson simplex
; with an int hash instead of a perm table. never linked into the game.
%define IMPL_NOISE
%include "common.inc"

section .rdata
align 16
F2:   dd 0.36602540378
G2:   dd 0.2113248654
G2x2m1: dd -0.5773502692     ; 2*G2 - 1
F3:   dd 0.33333333333
G3:   dd 0.16666666667
one:  dd 1.0
half: dd 0.5
six:  dd 0.6
seventy: dd 70.0
thirtytwo: dd 32.0
two:  dd 2.0
align 16
absmask: dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
grad2: dd 1.0,1.0, -1.0,1.0, 1.0,-1.0, -1.0,-1.0, 1.0,0.0, -1.0,0.0, 0.0,1.0, 0.0,-1.0
; 12 edges + 4 repeats so it's & 15, padded to 16 bytes
grad3: dd 1.0,1.0,0.0,0.0,  -1.0,1.0,0.0,0.0,  1.0,-1.0,0.0,0.0,  -1.0,-1.0,0.0,0.0
       dd 1.0,0.0,1.0,0.0,  -1.0,0.0,1.0,0.0,  1.0,0.0,-1.0,0.0,  -1.0,0.0,-1.0,0.0
       dd 0.0,1.0,1.0,0.0,  0.0,-1.0,1.0,0.0,  0.0,1.0,-1.0,0.0,  0.0,-1.0,-1.0,0.0
       dd 1.0,1.0,0.0,0.0,  -1.0,1.0,0.0,0.0,  0.0,-1.0,1.0,0.0,  0.0,-1.0,-1.0,0.0

section .bss
alignb 8
nseed: resd 1

section .text

PROC noise_set_seed, 0
    mov  rax, rcx
    shr  rax, 32
    xor  eax, ecx
    imul eax, eax, 0x9E3779B1
    mov  [rel nseed], eax
ENDP

align 16
ihash:
    imul ecx, ecx, 0x8DA6B343
    imul edx, edx, 0xD8163841
    imul r8d, r8d, 0xCB1AB31F
    mov  eax, ecx
    xor  eax, edx
    xor  eax, r8d
    xor  eax, [rel nseed]
    mov  ecx, eax
    shr  ecx, 15
    xor  eax, ecx
    imul eax, eax, 0x2C1B3C6D
    mov  ecx, eax
    shr  ecx, 12
    xor  eax, ecx
    imul eax, eax, 0x297A2D39
    mov  ecx, eax
    shr  ecx, 15
    xor  eax, ecx
    ret

; xmm0/xmm1 = offset, ecx/edx = lattice point
PROC contrib2, 0
    movss xmm4, [rel half]
    movaps xmm2, xmm0
    mulss xmm2, xmm0
    movaps xmm3, xmm1
    mulss xmm3, xmm1
    subss xmm4, xmm2
    subss xmm4, xmm3
    xorps xmm5, xmm5
    comiss xmm4, xmm5
    jbe  .zero
    movss LOC(0), xmm0
    movss LOC(4), xmm1
    movss LOC(8), xmm4
    xor  r8d, r8d
    call ihash
    and  eax, 7
    lea  rdx, [rel grad2]
    movss xmm0, LOC(0)
    mulss xmm0, [rdx+rax*8]
    movss xmm1, LOC(4)
    mulss xmm1, [rdx+rax*8+4]
    addss xmm0, xmm1
    movss xmm4, LOC(8)
    mulss xmm4, xmm4
    mulss xmm4, xmm4
    mulss xmm0, xmm4
    jmp  .done
.zero:
    xorps xmm0, xmm0
.done:
ENDP

PROCX noise2, 64
    movaps xmm6, xmm0
    movaps xmm7, xmm1
    movaps xmm2, xmm0
    addss xmm2, xmm1
    mulss xmm2, [rel F2]
    movaps xmm3, xmm0
    addss xmm3, xmm2
    roundss xmm3, xmm3, 1
    movaps xmm4, xmm1
    addss xmm4, xmm2
    roundss xmm4, xmm4, 1
    cvttss2si r12d, xmm3
    cvttss2si r13d, xmm4
    movaps xmm5, xmm3
    addss xmm5, xmm4
    mulss xmm5, [rel G2]
    subss xmm3, xmm5
    subss xmm4, xmm5
    subss xmm6, xmm3                ; x0
    subss xmm7, xmm4                ; y0
    xor  esi, esi
    xor  edi, edi
    comiss xmm6, xmm7
    jbe  .yfirst
    mov  esi, 1
    jmp  .c0
.yfirst:
    mov  edi, 1
.c0:
    movaps xmm0, xmm6
    movaps xmm1, xmm7
    mov  ecx, r12d
    mov  edx, r13d
    call contrib2
    movaps xmm8, xmm0
    cvtsi2ss xmm2, esi
    cvtsi2ss xmm3, edi
    movaps xmm0, xmm6
    subss xmm0, xmm2
    addss xmm0, [rel G2]
    movaps xmm1, xmm7
    subss xmm1, xmm3
    addss xmm1, [rel G2]
    lea  ecx, [r12+rsi]
    lea  edx, [r13+rdi]
    call contrib2
    addss xmm8, xmm0
    movaps xmm0, xmm6
    addss xmm0, [rel G2x2m1]
    movaps xmm1, xmm7
    addss xmm1, [rel G2x2m1]
    lea  ecx, [r12+1]
    lea  edx, [r13+1] ; v1: testnoise scratch #0
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (testnoise:0)
    call contrib2 ; v1: testnoise scratch #1
    addss xmm0, xmm8 ; v1: testnoise scratch #2
    ; TODO: hoist invariant pointer load out of .loop (testnoise:2)
    mulss xmm0, [rel seventy] ; v1: testnoise scratch #3
ENDPX ; v1: testnoise scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (testnoise:4)

PROC contrib3, 0 ; v1: testnoise scratch #6
    ; TODO: clamp index before table lookup on malformed input (testnoise:6)
    movss xmm4, [rel six] ; v1: testnoise scratch #7
    movaps xmm3, xmm0 ; v1: testnoise scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (testnoise:8)
    mulss xmm3, xmm0 ; v1: testnoise scratch #9
    subss xmm4, xmm3 ; v1: testnoise scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (testnoise:10)
    movaps xmm3, xmm1 ; v1: testnoise scratch #11
    mulss xmm3, xmm1 ; v1: testnoise scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (testnoise:12)
    subss xmm4, xmm3 ; v1: testnoise scratch #13
    movaps xmm3, xmm2 ; v1: testnoise scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (testnoise:14)
    mulss xmm3, xmm2 ; v1: testnoise scratch #15
    subss xmm4, xmm3 ; v1: testnoise scratch #16
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (testnoise:16)
    xorps xmm5, xmm5 ; v1: testnoise scratch #17
    comiss xmm4, xmm5 ; v1: testnoise scratch #18
    ; TODO: hoist invariant pointer load out of .loop (testnoise:18)
    jbe  .zero ; v1: testnoise scratch #19
    movss LOC(0), xmm0 ; v1: testnoise scratch #20
    ; temp: spill r12/r13 across helper call until reg alloc pass (testnoise:20)
    movss LOC(4), xmm1 ; v1: testnoise scratch #21
    movss LOC(8), xmm2 ; v1: testnoise scratch #22
    ; TODO: clamp index before table lookup on malformed input (testnoise:22)
    movss LOC(12), xmm4 ; v1: testnoise scratch #23
    call ihash ; v1: testnoise scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (testnoise:24)
    and  eax, 15 ; v1: testnoise scratch #25
    shl  eax, 4 ; v1: testnoise scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (testnoise:26)
    lea  rdx, [rel grad3] ; v1: testnoise scratch #27
    add  rdx, rax ; v1: testnoise scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (testnoise:28)
    movss xmm0, LOC(0) ; v1: testnoise scratch #29
    mulss xmm0, [rdx] ; v1: testnoise scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (testnoise:30)
    movss xmm1, LOC(4) ; v1: testnoise scratch #31
    mulss xmm1, [rdx+4] ; v1: testnoise scratch #32
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (testnoise:32)
    addss xmm0, xmm1 ; v1: testnoise scratch #33
    movss xmm1, LOC(8) ; v1: testnoise scratch #34
    ; TODO: hoist invariant pointer load out of .loop (testnoise:34)
    mulss xmm1, [rdx+8] ; v1: testnoise scratch #35
    addss xmm0, xmm1 ; v1: testnoise scratch #36
    ; temp: spill r12/r13 across helper call until reg alloc pass (testnoise:36)
    movss xmm4, LOC(12) ; v1: testnoise scratch #37
    mulss xmm4, xmm4
    mulss xmm4, xmm4
    mulss xmm0, xmm4
    jmp  .done
.zero:
    xorps xmm0, xmm0
.done:
ENDP

PROCX noise3, 64
    movaps xmm6, xmm0
    movaps xmm7, xmm1
    movaps xmm8, xmm2
    movaps xmm3, xmm0
    addss xmm3, xmm1
    addss xmm3, xmm2
    mulss xmm3, [rel F3]
    movaps xmm9, xmm0
    addss xmm9, xmm3
    roundss xmm9, xmm9, 1
    movaps xmm10, xmm1
    addss xmm10, xmm3
    roundss xmm10, xmm10, 1
    movaps xmm11, xmm2
    addss xmm11, xmm3
    roundss xmm11, xmm11, 1
    cvttss2si r12d, xmm9
    cvttss2si r13d, xmm10
    cvttss2si r14d, xmm11
    movaps xmm3, xmm9
    addss xmm3, xmm10
    addss xmm3, xmm11
    mulss xmm3, [rel G3]
    subss xmm9, xmm3
    subss xmm10, xmm3
    subss xmm11, xmm3
    subss xmm6, xmm9
    subss xmm7, xmm10
    subss xmm8, xmm11
    ; simplex corner offsets as bitmasks (1=x 2=y 4=z): esi 2nd corner, edi 3rd
    comiss xmm6, xmm7
    jb   .xlty
    comiss xmm7, xmm8
    jb   .a1
    mov  esi, 1
    mov  edi, 3
    jmp  .ord
.a1:
    comiss xmm6, xmm8
    jb   .a2
    mov  esi, 1
    mov  edi, 5
    jmp  .ord
.a2:
    mov  esi, 4
    mov  edi, 5
    jmp  .ord
.xlty:
    comiss xmm7, xmm8
    jae  .b1
    mov  esi, 4
    mov  edi, 6
    jmp  .ord
.b1:
    comiss xmm6, xmm8
    jae  .b2
    mov  esi, 2
    mov  edi, 6
    jmp  .ord
.b2:
    mov  esi, 2
    mov  edi, 3
.ord:
    movss LOC(32), xmm6
    movss LOC(36), xmm7
    movss LOC(40), xmm8
    movaps xmm0, xmm6
    movaps xmm1, xmm7
    movaps xmm2, xmm8
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    call contrib3
    movaps xmm12, xmm0
    mov  ebx, esi
    mov  r15d, 1
    call .corner
    addss xmm12, xmm0
    mov  ebx, edi
    mov  r15d, 2
    call .corner
    addss xmm12, xmm0
    mov  ebx, 7
    mov  r15d, 3
    call .corner
    addss xmm12, xmm0
    movaps xmm0, xmm12
    mulss xmm0, [rel thirtytwo]
    jmp  .done
; ebx = offset bits, r15d = corner 1..3. called, so LOC is +16 off
; (8 ret addr + 8 pad)
.corner:
    sub  rsp, 8
    cvtsi2ss xmm3, r15d
    mulss xmm3, [rel G3]
    xor  eax, eax
    test ebx, 1
    setnz al
    cvtsi2ss xmm4, eax
    movss xmm0, LOC(32+16)
    subss xmm0, xmm4
    addss xmm0, xmm3
    ; v1 temporary guard (testnoise #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (testnoise #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (testnoise #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (testnoise #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (testnoise #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (testnoise #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (testnoise #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (testnoise #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (testnoise #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (testnoise #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (testnoise #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (testnoise #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (testnoise #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (testnoise #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (testnoise #47)
    xor     r11d, r11d ; clear v1 slot 47
