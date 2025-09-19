; noise.asm - simplex noise2/noise3, plus fbm/ridged/warp on top
; all tables are read-only after noise_set_seed, so chunk workers can call this
; from any thread. never seeded = zero tables = everything returns 0
%define IMPL_NOISE
%include "common.inc"

%define MAX_OCTAVES 16

section .rdata
align 16
ps_half:        dd 0.5, 0.5, 0.5, 0.5

; 2D corner offsets per lane. lane 3 is parked 100 units out so its falloff
; is always 0, cheaper than masking it
simplex2_tbl:
    ; x0 <= y0
    dd 0.0, -0.2113248654,  0.5773502692, -100.0
    dd 0.0,  0.7886751346,  0.5773502692, -100.0
    ; x0 > y0
    dd 0.0,  0.7886751346,  0.5773502692, -100.0
    dd 0.0, -0.2113248654,  0.5773502692, -100.0

; 3D, indexed by the compare code: bit0 x0>=y0, bit1 x0>=z0, bit2 y0>=z0.
; 128 bytes each: KX KY KZ with the unskew baked in, int offsets of corners 1/2, pad
align 16
simplex3_tbl:
    dd 0.0000000000, -0.1666666667, -0.3333333333, 0.5000000000
    dd 0.0000000000, -0.1666666667, 0.6666666667, 0.5000000000
    dd 0.0000000000, 0.8333333333, 0.6666666667, 0.5000000000
    dd 0, 0, 1, 0, 0, 1, 1, 0
    times 12 dd 0
    dd 0.0000000000, -0.1666666667, 0.6666666667, 0.5000000000
    dd 0.0000000000, -0.1666666667, -0.3333333333, 0.5000000000
    dd 0.0000000000, 0.8333333333, 0.6666666667, 0.5000000000
    dd 0, 0, 1, 0, 1, 0, 1, 0
    times 12 dd 0
    ; masks 2 and 5 can only happen with nan input
    dd 0.0000000000, 0.8333333333, 0.6666666667, 0.5000000000
    dd 0.0000000000, -0.1666666667, 0.6666666667, 0.5000000000
    dd 0.0000000000, -0.1666666667, -0.3333333333, 0.5000000000
    dd 1, 0, 0, 0, 1, 1, 0, 0
    times 12 dd 0
    dd 0.0000000000, 0.8333333333, 0.6666666667, 0.5000000000
    dd 0.0000000000, -0.1666666667, -0.3333333333, 0.5000000000
    dd 0.0000000000, -0.1666666667, 0.6666666667, 0.5000000000
    dd 1, 0, 0, 0, 1, 0, 1, 0
    times 12 dd 0
    dd 0.0000000000, -0.1666666667, -0.3333333333, 0.5000000000
    dd 0.0000000000, 0.8333333333, 0.6666666667, 0.5000000000
    dd 0.0000000000, -0.1666666667, 0.6666666667, 0.5000000000
    dd 0, 1, 0, 0, 0, 1, 1, 0
    times 12 dd 0
    dd 0.0000000000, 0.8333333333, 0.6666666667, 0.5000000000
    dd 0.0000000000, -0.1666666667, 0.6666666667, 0.5000000000
    dd 0.0000000000, -0.1666666667, -0.3333333333, 0.5000000000
    dd 1, 0, 0, 0, 1, 1, 0, 0
    times 12 dd 0
    dd 0.0000000000, -0.1666666667, 0.6666666667, 0.5000000000
    dd 0.0000000000, 0.8333333333, 0.6666666667, 0.5000000000
    dd 0.0000000000, -0.1666666667, -0.3333333333, 0.5000000000
    dd 0, 1, 0, 0, 1, 1, 0, 0
    times 12 dd 0
    dd 0.0000000000, 0.8333333333, 0.6666666667, 0.5000000000
    dd 0.0000000000, -0.1666666667, 0.6666666667, 0.5000000000
    dd 0.0000000000, -0.1666666667, -0.3333333333, 0.5000000000
    dd 1, 0, 0, 0, 1, 1, 0, 0
    times 12 dd 0

; per-octave offsets so the octaves don't all line up at the origin
align 16
oct_offsets:
                dd  -124.9182,   110.9475,  -111.3615, 0.0
                dd  -112.4689,  -143.5917,  -170.7502, 0.0
                dd    -2.7174,   -28.8168,   116.2261, 0.0
                dd   160.1516,    82.3199,   -96.1579, 0.0
                dd    -1.8974,   143.9468,    73.8819, 0.0
                dd   -87.9186,   112.5828,  -107.7796, 0.0
                dd   100.6243,   -33.2257,   -86.5426, 0.0
                dd   140.4489,   -65.2441,  -175.8498, 0.0
                dd   109.3918,    56.8755,   151.0562, 0.0
                dd   -84.0645,   -69.7449,    52.8828, 0.0
                dd    45.4687,   -82.8732,   -70.3666, 0.0
                dd     8.5607,   -39.3842,    30.6558, 0.0
                dd    75.6978,   154.7859,   -41.6693, 0.0
                dd    34.6161,    78.8063,   -41.4852, 0.0
                dd    49.1675,   -62.5529,   148.5288, 0.0
                dd   -23.4893,   -76.3496,   147.9290, 0.0

align 8
d_F2:           dq 0.36602540378443864676
d_G2:           dq 0.21132486540518711775
d_F3:           dq 0.33333333333333333333
d_G3:           dq 0.16666666666666666667
f_scale2:       dd 99.20433458271864 ; 1/max|sum|, found numerically
f_scale3:       dd 107.65348539728195 ; only valid for r^2 = 0.5
f_one:          dd 1.0
f_half:         dd 0.5
f_four:         dd 4.0
f_2m24:         dd 0x33800000
f_2pi:          dd 6.283185307179586
f_2pi_256:      dd 0.02454369260617026
f_inv256:       dd 0.00390625
f_golden:       dd 2.399963229728653 ; golden angle
f_warp_ox:      dd 5.2
f_warp_oy:      dd 1.3

section .bss
alignb 16
perm:           resb 512 + 16 ; doubled so perm[a + perm[b]] never needs masking
alignb 16
grad2:          resd 256*2
alignb 16
grad3:          resd 256*4 ; padded for movaps

section .text

; same as math.asm
%macro HSUM4 2
    movhlps %2, %1
    addps   %1, %2
    movaps  %2, %1
    shufps  %2, %2, 0x55
    addss   %1, %2
%endmacro

; own xorshift so seeding noise doesn't move the main rng. only touches rax
%macro XS_NEXT 1
    mov     rax, %1
    shr     rax, 12
    xor     %1, rax
    mov     rax, %1
    shl     rax, 25
    xor     %1, rax
    mov     rax, %1
    shr     rax, 27
    xor     %1, rax
    mov     rax, 0x2545F4914F6CDD1D
    imul    rax, %1
%endmacro

; not thread safe, call before the chunk workers start
PROC noise_set_seed, 32
    mov     rax, 0x9E3779B97F4A7C15
    add     rax, rcx
    mov     rdx, rax
    shr     rdx, 30
    xor     rax, rdx
    mov     rdx, 0xBF58476D1CE4E5B9
    imul    rax, rdx
    mov     rdx, rax
    shr     rdx, 27
    xor     rax, rdx
    mov     rdx, 0x94D049BB133111EB
    imul    rax, rdx
    mov     rdx, rax
    shr     rdx, 31
    xor     rax, rdx
    mov     rdx, 0x9E3779B97F4A7C15
    test    rax, rax
    cmovz   rax, rdx
    mov     r12, rax

    lea     rsi, [rel perm]
    xor     ecx, ecx
.ident:
    mov     [rsi+rcx], cl
    inc     ecx
    cmp     ecx, 256
    jb      .ident

    ; fisher-yates
    mov     ebx, 255
.shuffle:
    XS_NEXT r12
    shr     rax, 32
    lea     ecx, [rbx+1]
    imul    rax, rcx
    shr     rax, 32
    movzx   edx, byte [rsi+rbx]
    movzx   ecx, byte [rsi+rax]
    mov     [rsi+rbx], cl
    mov     [rsi+rax], dl
    dec     ebx
    jnz     .shuffle

    xor     ecx, ecx
.dup:
    movdqa  xmm0, [rsi+rcx]
    movdqa  [rsi+rcx+256], xmm0
    add     ecx, 16
    cmp     ecx, 256
    jb      .dup

    ; random phase so different seeds get different gradient sets too
    XS_NEXT r12
    shr     rax, 40
    cvtsi2ss xmm0, eax
    mulss   xmm0, [f_2m24]
    mulss   xmm0, [f_2pi_256]
    movss   LOC(0), xmm0
    XS_NEXT r12
    shr     rax, 40
    cvtsi2ss xmm0, eax
    mulss   xmm0, [f_2m24]
    mulss   xmm0, [f_2pi]
    movss   LOC(4), xmm0

    ; evenly spaced angles instead of perlin's 12 cube edges, those give axis-aligned grain
    lea     rdi, [rel grad2]
    xor     ebx, ebx
.g2:
    cvtsi2ss xmm0, ebx
    mulss   xmm0, [f_2pi_256]
    addss   xmm0, LOC(0)
    call    math_sincos
    movss   [rdi+rbx*8], xmm1
    movss   [rdi+rbx*8+4], xmm0
    inc     ebx
    cmp     ebx, 256
    jb      .g2

    ; fibonacci sphere
    lea     rdi, [rel grad3]
    xor     ebx, ebx
.g3:
    lea     eax, [rbx*2+1]
    cvtsi2ss xmm0, eax
    mulss   xmm0, [f_inv256]
    movss   xmm1, [f_one]
    subss   xmm1, xmm0
    movss   LOC(8), xmm1
    mulss   xmm1, xmm1
    movss   xmm0, [f_one]
    subss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    movss   LOC(12), xmm0
    cvtsi2ss xmm0, ebx
    mulss   xmm0, [f_golden]
    addss   xmm0, LOC(4)
    call    math_sincos
    mov     eax, ebx
    shl     eax, 4
    mulss   xmm1, LOC(12)
    mulss   xmm0, LOC(12)
    movss   [rdi+rax], xmm1
    movss   [rdi+rax+4], xmm0
    movss   xmm0, LOC(8)
    movss   [rdi+rax+8], xmm0
    mov     dword [rdi+rax+12], 0
    inc     ebx
    cmp     ebx, 256
    jb      .g3
ENDP

LEAF noise2
    ; skew/floor/unskew in double, float gets seams out around 1e6
    cvtss2sd xmm0, xmm0
    cvtss2sd xmm1, xmm1
    movsd   xmm2, xmm0
    addsd   xmm2, xmm1
    mulsd   xmm2, [d_F2]
    movsd   xmm3, xmm0
    addsd   xmm3, xmm2
    roundsd xmm3, xmm3, 9
    addsd   xmm2, xmm1
    roundsd xmm2, xmm2, 9
    cvttsd2si r8d, xmm3
    cvttsd2si r9d, xmm2
    subsd   xmm0, xmm3
    subsd   xmm1, xmm2
    addsd   xmm3, xmm2
    mulsd   xmm3, [d_G2]
    addsd   xmm0, xmm3
    addsd   xmm1, xmm3
    cvtsd2ss xmm0, xmm0
    cvtsd2ss xmm1, xmm1 ; small now, float is fine from here
    xor     eax, eax
    comiss  xmm0, xmm1
    seta    al ; i1, j1 = 1 - i1
    mov     ecx, eax
    shl     ecx, 5
    lea     rdx, [rel simplex2_tbl]
    shufps  xmm0, xmm0, 0
    subps   xmm0, [rdx+rcx]
    shufps  xmm1, xmm1, 0
    subps   xmm1, [rdx+rcx+16]
    and     r8d, 255
    and     r9d, 255
    lea     r10, [rel perm]
    lea     r11, [rel grad2]
    movzx   ecx, byte [r10+r9]
    add     ecx, r8d
    movzx   ecx, byte [r10+rcx]
    movsd   xmm2, [r11+rcx*8]
    mov     edx, 1
    sub     edx, eax
    add     edx, r9d
    movzx   edx, byte [r10+rdx]
    add     edx, r8d
    add     edx, eax
    movzx   edx, byte [r10+rdx]
    movsd   xmm3, [r11+rdx*8]
    movzx   ecx, byte [r10+r9+1]
    lea     ecx, [rcx+r8+1]
    movzx   ecx, byte [r10+rcx]
    movsd   xmm4, [r11+rcx*8]
    ; lane 3 duplicates g2, it gets zeroed anyway
    unpcklps xmm2, xmm3
    unpcklps xmm4, xmm4
    movaps  xmm3, xmm2
    movlhps xmm3, xmm4
    movhlps xmm4, xmm2
    mulps   xmm3, xmm0
    mulps   xmm4, xmm1
    addps   xmm3, xmm4
    mulps   xmm0, xmm0
    mulps   xmm1, xmm1
    addps   xmm0, xmm1
    movaps  xmm1, [ps_half]
    subps   xmm1, xmm0
    xorps   xmm2, xmm2
    maxps   xmm1, xmm2
    mulps   xmm1, xmm1
    mulps   xmm1, xmm1 ; max(0, .5 - |d|^2)^4
    mulps   xmm1, xmm3
    HSUM4   xmm1, xmm0
    mulss   xmm1, [f_scale2]
    movaps  xmm0, xmm1
    ret

; args 2..4 = where this corner's int offsets sit in the table entry
%macro CORNER3 4
    mov     edx, [rcx+%4]
    add     edx, r10d
    movzx   edx, byte [r11+rdx]
    add     edx, [rcx+%3]
    add     edx, r9d
    movzx   edx, byte [r11+rdx]
    add     edx, [rcx+%2]
    add     edx, r8d
    movzx   edx, byte [r11+rdx]
    shl     edx, 4
    movaps  %1, [rax+rdx]
%endmacro

LEAF noise3
    sub     rsp, 40
    movaps  [rsp], xmm6 ; xmm6/7 are callee-saved
    movaps  [rsp+16], xmm7
    cvtss2sd xmm0, xmm0
    cvtss2sd xmm1, xmm1
    cvtss2sd xmm2, xmm2
    movsd   xmm3, xmm0
    addsd   xmm3, xmm1
    addsd   xmm3, xmm2
    mulsd   xmm3, [d_F3]
    movsd   xmm4, xmm0
    addsd   xmm4, xmm3
    roundsd xmm4, xmm4, 9
    movsd   xmm5, xmm1
    addsd   xmm5, xmm3
    roundsd xmm5, xmm5, 9
    addsd   xmm3, xmm2
    roundsd xmm3, xmm3, 9
    cvttsd2si r8d, xmm4
    cvttsd2si r9d, xmm5
    cvttsd2si r10d, xmm3
    subsd   xmm0, xmm4
    subsd   xmm1, xmm5
    subsd   xmm2, xmm3
    addsd   xmm4, xmm5
    addsd   xmm4, xmm3
    mulsd   xmm4, [d_G3]
    addsd   xmm0, xmm4
    addsd   xmm1, xmm4
    addsd   xmm2, xmm4
    cvtsd2ss xmm0, xmm0
    cvtsd2ss xmm1, xmm1
    cvtsd2ss xmm2, xmm2
    ; which tetrahedron, 3 compares -> 3-bit index
    xor     eax, eax
    xor     edx, edx
    comiss  xmm0, xmm1
    setae   al
    comiss  xmm0, xmm2
    setae   dl
    lea     eax, [rax+rdx*2]
    comiss  xmm1, xmm2
    setae   dl
    lea     eax, [rax+rdx*4]
    shl     eax, 7 ; 128-byte entries
    lea     rcx, [rel simplex3_tbl]
    add     rcx, rax
    shufps  xmm0, xmm0, 0
    subps   xmm0, [rcx]
    shufps  xmm1, xmm1, 0
    subps   xmm1, [rcx+16]
    shufps  xmm2, xmm2, 0
    subps   xmm2, [rcx+32]
    and     r8d, 255
    and     r9d, 255
    and     r10d, 255
    lea     r11, [rel perm]
    lea     rax, [rel grad3]
    movzx   edx, byte [r11+r10]
    add     edx, r9d
    movzx   edx, byte [r11+rdx]
    add     edx, r8d
    movzx   edx, byte [r11+rdx]
    shl     edx, 4
    movaps  xmm4, [rax+rdx]
    CORNER3 xmm5, 48, 52, 56
    CORNER3 xmm6, 64, 68, 72
    movzx   edx, byte [r11+r10+1]
    lea     edx, [rdx+r9+1]
    movzx   edx, byte [r11+rdx]
    lea     edx, [rdx+r8+1]
    movzx   edx, byte [r11+rdx]
    shl     edx, 4
    movaps  xmm7, [rax+rdx]
    ; transpose g0..g3 -> gx gy gz, w lanes are 0
    movaps  xmm3, xmm4
    unpcklps xmm4, xmm5
    unpckhps xmm3, xmm5
    movaps  xmm5, xmm6
    unpcklps xmm6, xmm7
    unpckhps xmm5, xmm7
    movlhps xmm3, xmm5
    movaps  xmm7, xmm4
    movlhps xmm4, xmm6
    movhlps xmm6, xmm7
    ; r^2 = 0.5 not 0.6, keeps the kernel inside its simplex so no seams
    mulps   xmm4, xmm0
    mulps   xmm6, xmm1
    addps   xmm4, xmm6
    mulps   xmm3, xmm2
    addps   xmm4, xmm3
    mulps   xmm0, xmm0
    mulps   xmm1, xmm1
    mulps   xmm2, xmm2
    addps   xmm0, xmm1
    addps   xmm0, xmm2
    movaps  xmm1, [ps_half]
    subps   xmm1, xmm0
    xorps   xmm2, xmm2
    maxps   xmm1, xmm2
    mulps   xmm1, xmm1
    mulps   xmm1, xmm1
    mulps   xmm1, xmm4
    HSUM4   xmm1, xmm0
    mulss   xmm1, [f_scale3]
    movaps  xmm0, xmm1
    movaps  xmm6, [rsp]
    movaps  xmm7, [rsp+16]
    add     rsp, 40
    ret

; oct_offsets only has 16 rows
%macro CLAMP_OCTAVES 1
    cmp     %1, 1
    jge     %%lo_ok
    mov     %1, 1
%%lo_ok:
    cmp     %1, MAX_OCTAVES
    jle     %%hi_ok
    mov     %1, MAX_OCTAVES
%%hi_ok:
%endmacro

; state in xmm6+ so it survives the noise2 calls
PROCX fbm2
    movaps  xmm6, xmm0
    movaps  xmm7, xmm1
    mov     ebx, r8d
    CLAMP_OCTAVES ebx
    xorps   xmm8, xmm8
    movss   xmm9, [f_one]
    movss   xmm10, [f_one]
    xorps   xmm11, xmm11 ; sum of amps, to normalise
    lea     rsi, [rel oct_offsets]
.octave:
    movaps  xmm0, xmm6
    mulss   xmm0, xmm10
    addss   xmm0, [rsi]
    movaps  xmm1, xmm7
    mulss   xmm1, xmm10
    addss   xmm1, [rsi+4]
    call    noise2
    mulss   xmm0, xmm9
    addss   xmm8, xmm0
    addss   xmm11, xmm9
    mulss   xmm9, [f_half]
    addss   xmm10, xmm10
    add     rsi, 16
    dec     ebx
    jnz     .octave
    divss   xmm8, xmm11
    movaps  xmm0, xmm8
ENDPX

; octaves in r9 here, it's the 4th arg
PROCX fbm3 ; trace probe #30 hook
    movaps  xmm6, xmm0 ; trace probe #30 hook
    movaps  xmm7, xmm1 ; trace probe #30 hook
    movaps  xmm8, xmm2 ; trace probe #30 hook
    mov     ebx, r9d ; trace probe #30 hook
    CLAMP_OCTAVES ebx ; trace probe #30 hook
    xorps   xmm9, xmm9 ; trace probe #30 hook
    movss   xmm10, [f_one] ; trace probe #30 hook
    movss   xmm11, [f_one] ; trace probe #30 hook
    xorps   xmm12, xmm12
    lea     rsi, [rel oct_offsets]
.octave:
    movaps  xmm0, xmm6
    mulss   xmm0, xmm11
    addss   xmm0, [rsi]
    movaps  xmm1, xmm7
    mulss   xmm1, xmm11
    addss   xmm1, [rsi+4]
    movaps  xmm2, xmm8
    mulss   xmm2, xmm11
    addss   xmm2, [rsi+8]
    call    noise3
    mulss   xmm0, xmm10
    addss   xmm9, xmm0
    addss   xmm12, xmm10
    mulss   xmm10, [f_half]
    addss   xmm11, xmm11
    add     rsi, 16
    dec     ebx
    jnz     .octave
    divss   xmm9, xmm12
    movaps  xmm0, xmm9
ENDPX
; --- temporary diagnostic probe #30 (noise) ---
; TODO: strip dbg_noise_probe_30 once frame/state invariants hold
dbg_noise_probe_30:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    mov     [rsp+32], rcx
    mov     [rsp+40], rdx
    mov     [rsp+48], r8
    mov     [rsp+56], r9
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    mov     r10, rax
    test    rcx, rcx
    jz      .dbg_null_30
    mov     eax, dword [rcx+0] ; sample noise state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_30_0
.dbg_skip_30_0:
    mov     ecx, dword [rcx+4] ; sample noise state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_30_1
.dbg_skip_30_1:
    mov     edx, dword [rcx+8] ; sample noise state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_30_2
.dbg_skip_30_2:
    mov     r8d, dword [rcx+12] ; sample noise state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_30_3
.dbg_skip_30_3:
    mov     r9d, dword [rcx+16] ; sample noise state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_30_4
.dbg_skip_30_4:
    mov     r11d, dword [rcx+20] ; sample noise state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_30_5
.dbg_skip_30_5:
    mov     eax, dword [rcx+24] ; sample noise state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_30_6
.dbg_skip_30_6:
    mov     ecx, dword [rcx+28] ; sample noise state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_30_7
.dbg_skip_30_7:
    mov     edx, dword [rcx+32] ; sample noise state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_30_8
.dbg_skip_30_8:
    mov     r8d, dword [rcx+36] ; sample noise state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_30_9
.dbg_skip_30_9:
    mov     r9d, dword [rcx+40] ; sample noise state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_30_10
.dbg_skip_30_10:
    mov     r11d, dword [rcx+44] ; sample noise state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_30_11
.dbg_skip_30_11:
    mov     eax, dword [rcx+48] ; sample noise state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_30_12
.dbg_skip_30_12:
    mov     ecx, dword [rcx+52] ; sample noise state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_30_13
.dbg_skip_30_13:
    mov     edx, dword [rcx+56] ; sample noise state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_30_14
.dbg_skip_30_14:
    mov     r8d, dword [rcx+60] ; sample noise state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_30_15
.dbg_skip_30_15:
    mov     r9d, dword [rcx+64] ; sample noise state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_30_16
.dbg_skip_30_16:
    mov     r11d, dword [rcx+68] ; sample noise state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_30_17
.dbg_skip_30_17:
    mov     eax, dword [rcx+72] ; sample noise state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_30_18
.dbg_skip_30_18:
    mov     ecx, dword [rcx+76] ; sample noise state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_30_19
.dbg_skip_30_19:
    mov     edx, dword [rcx+80] ; sample noise state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_30_20
.dbg_skip_30_20:
    mov     r8d, dword [rcx+84] ; sample noise state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_30_21
.dbg_skip_30_21:
.dbg_null_30:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
