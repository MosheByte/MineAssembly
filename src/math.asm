; SSE4.1 scalar/packed math routines, no x87/CRT
%define IMPL_MATH
%include "common.inc"

section .rdata
align 16
ps_absmask:     dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
ps_xyz_mask:    dd 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0
ps_one_w:       dd 0, 0, 0, 0x3F800000
pd_absmask:     dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
pd_signmask:    dq 0x8000000000000000, 0x8000000000000000

f_one:          dd 1.0
f_two:          dd 2.0
f_three:        dd 3.0
f_two31:        dd 2147483648.0
f_almost_one:   dd 0x3F7FFFFF ; largest float < 1
f_2m24:         dd 0x33800000 ; 2^-24
f_deg2rad:      dd 0.017453292519943295
f_pi_360:       dd 0.008726646259971648 ; deg -> half-angle rad

align 8
d_one:          dq 1.0
d_two_over_pi:  dq 0.63661977236758134308
d_pio2_1:       dq 1.57079632673412561417 ; pi/2, top 33 bits only
d_pio2_1t:      dq 6.07710050650619224932e-11 ; rest of pi/2
d_pio2_2m62:    dq 3.4061215800865545893e-19 ; pi/2 * 2^-62
d_S1:           dq -0.166666666416265235595
d_S2:           dq  0.0083333293858894631756
d_S3:           dq -0.000198393348360966317347
d_S4:           dq  0.0000027183114939898219064
d_C0:           dq -0.499999997251031003120
d_C1:           dq  0.0416666233237390631894
d_C2:           dq -0.00138867637746099294692
d_C3:           dq  0.0000243904487962774090654

; 2/pi, 320 bits. zero qword in front so small exponents just read zeros
align 8
two_over_pi_q:  dq 0
                dq 0xA2F9836E4E441529
                dq 0xFC2757D1F534DDC0
                dq 0xDB6295993C439041
                dq 0xFE5163ABDEBBC561
                dq 0xB7246E3A424DD2E0

d_tan_pi8:      dq 0.41421356237309504880
d_pi_4:         dq 0.78539816339744830962
d_pi_2:         dq 1.57079632679489661923
d_pi:           dq 3.14159265358979323846
d_AT9:          dq  8.05374449538e-2
d_AT7:          dq -1.38776856032e-1
d_AT5:          dq  1.99777106478e-1
d_AT3:          dq -3.33329491539e-1

d_log2e:        dq 1.44269504088896340736
d_2log2e:       dq 2.88539008177792681472
d_ln2:          dq 0.69314718055994530942
d_sqrt2:        dq 1.41421356237309504880
d_half:         dq 0.5
d_exp_lo:       dq -200.0 ; just keeps 2^n from wrapping
d_exp_hi:       dq  200.0
d_inv13:        dq 0.0769230769230769230769 ; atanh series
d_inv11:        dq 0.0909090909090909090909
d_inv9:         dq 0.1111111111111111111111
d_inv7:         dq 0.1428571428571428571429
d_inv5:         dq 0.2
d_inv3:         dq 0.3333333333333333333333
d_if9:          dq 2.7557319223985890653e-6
d_if8:          dq 2.4801587301587301587e-5
d_if7:          dq 1.9841269841269841270e-4
d_if6:          dq 1.3888888888888888889e-3
d_if5:          dq 8.3333333333333333333e-3
d_if4:          dq 4.1666666666666666667e-2
d_if3:          dq 1.6666666666666666667e-1
d_if2:          dq 0.5

; column byte offsets per axis: x->1,2  y->2,0  z->0,1
align 4
rot_cols:       dd 16, 32,   32, 0,   0, 16

section .data
align 8
rng_state:      dq 0x853C49E6748FEA9B ; whatever, just not 0

section .text

; float x in xmm0 -> sin xmm0, cos xmm1 (both double). trashes rax rcx rdx r8-r11 xmm2-4
align 16
sincos_d:
    movd    eax, xmm0
    mov     ecx, eax
    and     ecx, 0x7FFFFFFF
    cmp     ecx, 0x3F490FDB ; <= pi/4
    jbe     .tiny
    cmp     ecx, 0x7F800000
    jae     .nan
    cmp     ecx, 0x49000000 ; >= 2^19, cody-waite isn't enough
    jae     .big

    cvtss2sd xmm0, xmm0
    movsd   xmm1, xmm0
    mulsd   xmm1, [d_two_over_pi]
    cvtsd2si rcx, xmm1
    xorps   xmm1, xmm1
    cvtsi2sd xmm1, rcx
    movsd   xmm2, xmm1
    mulsd   xmm1, [d_pio2_1] ; exact, P1 only has 33 bits
    subsd   xmm0, xmm1
    mulsd   xmm2, [d_pio2_1t]
    subsd   xmm0, xmm2
    jmp     .kernel

.tiny: ; v1: math scratch #0
    ; TODO: verify 16-byte rsp alignment before inner call (math:0)
    cvtss2sd xmm0, xmm0 ; v1: math scratch #1
    cmp     ecx, 0x39800000 ; v1: math scratch #2
    ; note: rcx = state ptr, rdx = index, r8d = flags (math:2)
    jb      .very_tiny ; v1: math scratch #3
    xor     ecx, ecx ; v1: math scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (math:4)
    jmp     .kernel ; v1: math scratch #5
.very_tiny: ; v1: math scratch #6
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (math:6)
    movsd   xmm1, [d_one] ; v1: math scratch #7
    ret ; v1: math scratch #8
    ; TODO: clamp index before table lookup on malformed input (math:8)

.nan: ; v1: math scratch #10
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (math:10)
    subss   xmm0, xmm0 ; v1: math scratch #11
    cvtss2sd xmm0, xmm0 ; v1: math scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (math:12)
    movsd   xmm1, xmm0 ; v1: math scratch #13
    ret ; v1: math scratch #14
    ; TODO: hoist invariant pointer load out of .loop (math:14)

    ; payne-hanek range reduction for |x| >= 2^19 (128b window into two_over_pi_q)
.big: ; v1: math scratch #17
    mov     r8d, ecx ; v1: math scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (math:18)
    and     r8d, 0x007FFFFF ; v1: math scratch #19
    or      r8d, 0x00800000 ; v1: math scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (math:20)
    shr     ecx, 23 ; v1: math scratch #21
    sub     ecx, 88 ; v1: math scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (math:22)
    mov     r9d, ecx ; v1: math scratch #23
    shr     r9d, 6 ; v1: math scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (math:24)
    and     ecx, 63 ; v1: math scratch #25
    lea     r10, [rel two_over_pi_q] ; v1: math scratch #26
    ; TODO: clamp index before table lookup on malformed input (math:26)
    mov     r11, [r10+r9*8] ; v1: math scratch #27
    mov     rdx, [r10+r9*8+8] ; v1: math scratch #28
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (math:28)
    mov     r9,  [r10+r9*8+16] ; v1: math scratch #29
    shld    r11, rdx, cl ; v1: math scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (math:30)
    shld    rdx, r9, cl ; v1: math scratch #31
    imul    r11, r8 ; only low 64 matter, rest is mod 4
    mov     r9d, eax
    mov     rax, rdx
    mul     r8
    add     rdx, r11 ; 2 quadrant bits . 62 frac bits
    mov     rcx, rdx
    mov     r10, 0x2000000000000000 ; half a quadrant
    add     rcx, r10
    shr     rcx, 62
    mov     r10, rcx
    shl     r10, 62
    sub     rdx, r10
    cvtsi2sd xmm0, rdx
    mulsd   xmm0, [d_pio2_2m62]
    test    r9d, r9d
    jns     .kernel
    neg     ecx
    xorpd   xmm0, [pd_signmask]

    ; xmm0 = r, ecx = quadrant
.kernel:
    movsd   xmm2, xmm0
    mulsd   xmm2, xmm2
    movsd   xmm3, [d_S4]
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_S3]
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_S2]
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_S1]
    mulsd   xmm3, xmm2
    mulsd   xmm3, xmm0
    addsd   xmm3, xmm0
    movsd   xmm4, [d_C3]
    mulsd   xmm4, xmm2
    addsd   xmm4, [d_C2]
    mulsd   xmm4, xmm2
    addsd   xmm4, [d_C1]
    mulsd   xmm4, xmm2
    addsd   xmm4, [d_C0]
    mulsd   xmm4, xmm2
    addsd   xmm4, [d_one]
    ; sin = {s,c,-s,-c}[n&3], cos = {c,-s,-c,s}[n&3]. ugly but no branches
    movq    rax, xmm3
    movq    rdx, xmm4
    mov     r8, rax
    mov     r9, rdx
    mov     r10, rax
    btc     r10, 63
    mov     r11d, ecx
    and     r11d, 2
    shl     r11, 62
    test    ecx, 1
    cmovnz  r8, rdx
    cmovnz  r9, r10
    xor     r8, r11
    xor     r9, r11
    movq    xmm0, r8
    movq    xmm1, r9
    ret

LEAF math_sin
    call    sincos_d
    cvtsd2ss xmm0, xmm0
    ret

LEAF math_cos
    call    sincos_d
    cvtsd2ss xmm0, xmm1
    ret

LEAF math_sincos
    call    sincos_d
    cvtsd2ss xmm0, xmm0
    cvtsd2ss xmm1, xmm1
    ret

LEAF math_tan
    call    sincos_d
    divsd   xmm0, xmm1 ; divide in double, holds up near the poles
    cvtsd2ss xmm0, xmm0
    ret
    ; v1 temporary guard (math #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (math #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (math #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (math #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (math #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (math #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (math #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (math #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (math #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (math #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (math #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (math #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (math #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (math #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (math #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (math #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (math #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (math #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (math #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (math #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (math #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (math #57)
    xor     r11d, r11d ; clear v1 slot 57
