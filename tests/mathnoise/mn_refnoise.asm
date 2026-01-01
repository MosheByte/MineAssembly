; mn_refnoise.asm - independent double-precision model of src/noise.asm, one global
; model so not thread safe. seeding rounds to f32 at the same steps noise.asm does,
; and only the cell offsets x0,y0,z0 get rounded to float during evaluation.
%define IMPL_MN_REFNOISE
%include "common.inc"
%include "../mathnoise/mn_test.inc"

section .rdata
align 8
d_F2:       dq 0.3660254037844386           ; 0.5*(sqrt(3)-1)
d_G2:       dq 0.21132486540518713          ; (3-sqrt(3))/6
d_2G2:      dq 0.42264973081037427
d_G3:       dq 0.16666666666666666
d_third:    dq 3.0
d_half:     dq 0.5
d_one:      dq 1.0
d_256:      dq 256.0
d_scale2:   dq 99.20433458271864
d_scale3:   dq 107.65348539728195
f_2pi_256:  dd 0.02454369260617026
f_2pi:      dd 6.283185307179586
f_golden:   dd 2.399963229728653  ; golden angle
f_2m24:     dd 0x33800000                   ; 2^-24
; 3D corner orders: o1 (x,y,z), o2 (x,y,z) for the six simplex cases
order3:
    db 1,0,0, 1,1,0                         ; 0: x>=y>=z
    db 1,0,0, 1,0,1                         ; 1: x>=z>y
    db 0,0,1, 1,0,1                         ; 2: z>x>=y
    db 0,0,1, 0,1,1                         ; 3: z>y>x
    db 0,1,0, 0,1,1                         ; 4: y>z>=x  (x<z)
    db 0,1,0, 1,1,0                         ; 5: y>x>=z

section .bss
alignb 16
r_state:    resq 1
r_perm:     resd 512
r_g2:       resq 256*2
r_g3:       resq 256*3

section .text

; volatile regs only
LEAF r_next
    mov     rax, [rel r_state]
    mov     rdx, rax
    shr     rdx, 12
    xor     rax, rdx
    mov     rdx, rax
    shl     rdx, 25
    xor     rax, rdx
    mov     rdx, rax
    shr     rdx, 27
    xor     rax, rdx
    mov     [rel r_state], rax
    mov     rdx, 0x2545F4914F6CDD1D
    imul    rax, rdx
    ret

; f32(f32((r>>40)*2^-24) * scale)
LEAF r_phase
    call    r_next
    shr     rax, 40
    cvtsi2ss xmm0, eax
    mulss   xmm0, [rel f_2m24]
    mulss   xmm0, xmm1
    ret

PROCX refn_init
    call    ref_splitmix
    mov     [rel r_state], rax
    lea     rbx, [rel r_perm]
    xor     ecx, ecx
.id:
    mov     [rbx+rcx*4], ecx
    inc     ecx
    cmp     ecx, 256
    jb      .id
    mov     esi, 255
.fy:
    call    r_next
    shr     rax, 32
    lea     ecx, [rsi+1]
    imul    rax, rcx
    shr     rax, 32                     ; j
    mov     ecx, [rbx+rsi*4]
    mov     edx, [rbx+rax*4]
    mov     [rbx+rsi*4], edx
    mov     [rbx+rax*4], ecx
    dec     esi
    jnz     .fy
    xor     ecx, ecx
.dup:
    mov     eax, [rbx+rcx*4]
    mov     [rbx+rcx*4+1024], eax
    inc     ecx
    cmp     ecx, 256
    jb      .dup
    movss   xmm1, [rel f_2pi_256]
    call    r_phase
    movss   xmm14, xmm0
    movss   xmm1, [rel f_2pi]
    call    r_phase
    movss   xmm15, xmm0
    xor     esi, esi
.g:
    cvtsi2ss xmm0, esi
    mulss   xmm0, [rel f_2pi_256]
    addss   xmm0, xmm14
    call    ref_sincos
    lea     rax, [rel r_g2]
    mov     ecx, esi
    shl     ecx, 4
    movsd   [rax+rcx], xmm1
    movsd   [rax+rcx+8], xmm0
; fibonacci sphere: z = 1-(2i+1)/256, r = sqrt(1-z^2)
    lea     eax, [rsi*2+1]
    cvtsi2sd xmm6, eax
    divsd   xmm6, [rel d_256]
    movsd   xmm7, [rel d_one]
    subsd   xmm7, xmm6
    movapd  xmm8, xmm7
    mulsd   xmm8, xmm7
    movsd   xmm9, [rel d_one]
    subsd   xmm9, xmm8
    sqrtsd  xmm9, xmm9
    cvtsi2ss xmm0, esi
    mulss   xmm0, [rel f_golden]
    addss   xmm0, xmm15
    call    ref_sincos
    mulsd   xmm1, xmm9
    mulsd   xmm0, xmm9
    lea     rax, [rel r_g3]
    imul    ecx, esi, 24
    movsd   [rax+rcx], xmm1
    movsd   [rax+rcx+8], xmm0
    movsd   [rax+rcx+16], xmm7
    inc     esi
    cmp     esi, 256
    jb      .g
ENDPX

%macro FLOOR_I 2.nolist                        ; dst reg64, src xmm
    roundsd xmm5, %2, 9
    cvttsd2si %1, xmm5
%endmacro

%macro TO_F32 1.nolist
    cvtsd2ss %1, %1
    cvtss2sd %1, %1
%endmacro

; corner2: xmm0 dx, xmm1 dy, eax grad index, adds into xmm10
%macro CORNER2 0.nolist
    movsd   xmm2, [rel d_half]
    movapd  xmm3, xmm0
    mulsd   xmm3, xmm0
    subsd   xmm2, xmm3
    movapd  xmm3, xmm1
    mulsd   xmm3, xmm1
    subsd   xmm2, xmm3  ; 0.5 - dx^2 - dy^2
    xorpd   xmm3, xmm3
    ucomisd xmm2, xmm3
    jbe     %%skip
    mulsd   xmm2, xmm2
    mulsd   xmm2, xmm2
    shl     eax, 4
    lea     rdx, [rel r_g2]
    mulsd   xmm0, [rdx+rax]
    mulsd   xmm1, [rdx+rax+8]
    addsd   xmm0, xmm1
    mulsd   xmm0, xmm2
    addsd   xmm10, xmm0
%%skip:
%endmacro

; xmm6 x0, xmm7 y0, r12 ii, r13 jj, r14 i1, r15 j1, rbx perm
PROCX refn_noise2
    cvtss2sd xmm6, xmm0
    cvtss2sd xmm7, xmm1
    movapd  xmm2, xmm6
    addsd   xmm2, xmm7
    mulsd   xmm2, [rel d_F2]
    movapd  xmm3, xmm6
    addsd   xmm3, xmm2
    FLOOR_I r12, xmm3
    movapd  xmm3, xmm7
    addsd   xmm3, xmm2
    FLOOR_I r13, xmm3
    lea     rax, [r12+r13]
    cvtsi2sd xmm4, rax
    mulsd   xmm4, [rel d_G2]
    cvtsi2sd xmm3, r12
    subsd   xmm6, xmm3
    addsd   xmm6, xmm4
    TO_F32  xmm6  ; only the offsets get rounded
    cvtsi2sd xmm3, r13
    subsd   xmm7, xmm3
    addsd   xmm7, xmm4
    TO_F32  xmm7
    xor     r14d, r14d
    xor     r15d, r15d
    ucomisd xmm6, xmm7
    jbe     .upper
    mov     r14d, 1
    jmp     .ord
.upper:
    mov     r15d, 1
.ord:
    and     r12d, 255
    and     r13d, 255
    lea     rbx, [rel r_perm]
    xorpd   xmm10, xmm10
    mov     eax, [rbx+r13*4]
    add     eax, r12d
    mov     eax, [rbx+rax*4]
    movapd  xmm0, xmm6
    movapd  xmm1, xmm7
    CORNER2
    lea     rax, [r13+r15]
    mov     eax, [rbx+rax*4]
    add     eax, r12d
    add     eax, r14d
    mov     eax, [rbx+rax*4]
    cvtsi2sd xmm2, r14d
    movapd  xmm0, xmm6
    subsd   xmm0, xmm2
    addsd   xmm0, [rel d_G2]
    cvtsi2sd xmm2, r15d
    movapd  xmm1, xmm7
    subsd   xmm1, xmm2
    addsd   xmm1, [rel d_G2]
    CORNER2
    lea     rax, [r13+1]
    mov     eax, [rbx+rax*4]
    lea     eax, [rax+r12+1]
    mov     eax, [rbx+rax*4]
    movapd  xmm0, xmm6
    subsd   xmm0, [rel d_one]
    addsd   xmm0, [rel d_2G2]
    movapd  xmm1, xmm7
    subsd   xmm1, [rel d_one]
    addsd   xmm1, [rel d_2G2]
    CORNER2
    movapd  xmm0, xmm10
    mulsd   xmm0, [rel d_scale2]
ENDPX

; xmm6-8 x0,y0,z0; r12-r14 ii,jj,kk; rdi order row; esi corner
PROCX refn_noise3, 32
    cvtss2sd xmm6, xmm0
    cvtss2sd xmm7, xmm1
    cvtss2sd xmm8, xmm2
    movapd  xmm2, xmm6
    addsd   xmm2, xmm7
    addsd   xmm2, xmm8
    divsd   xmm2, [rel d_third]
    movapd  xmm3, xmm6
    addsd   xmm3, xmm2
    FLOOR_I r12, xmm3
    movapd  xmm3, xmm7
    addsd   xmm3, xmm2
    FLOOR_I r13, xmm3
    movapd  xmm3, xmm8
    addsd   xmm3, xmm2
    FLOOR_I r14, xmm3
    lea     rax, [r12+r13]
    add     rax, r14
    cvtsi2sd xmm4, rax
    mulsd   xmm4, [rel d_G3]
    cvtsi2sd xmm3, r12
    subsd   xmm6, xmm3
    addsd   xmm6, xmm4
    TO_F32  xmm6
    cvtsi2sd xmm3, r13
    subsd   xmm7, xmm3
    addsd   xmm7, xmm4
    TO_F32  xmm7
    cvtsi2sd xmm3, r14
    subsd   xmm8, xmm3
    addsd   xmm8, xmm4
    TO_F32  xmm8
    ucomisd xmm6, xmm7
    jb      .ylt
    xor     eax, eax
    ucomisd xmm7, xmm8
    jae     .ord
    mov     eax, 1
    ucomisd xmm6, xmm8
    jae     .ord
    mov     eax, 2
    jmp     .ord
.ylt:
    mov     eax, 3
    ucomisd xmm7, xmm8
    jb      .ord
    mov     eax, 4
    ucomisd xmm6, xmm8
    jb      .ord
    mov     eax, 5
.ord:
    ; corner offsets in LOC(0..11): c0 (0,0,0), c1 o1, c2 o2, c3 (1,1,1)
    lea     rdi, [rel order3]
    imul    eax, eax, 6
    add     rdi, rax
    mov     dword LOC(0), 0
    mov     ax, [rdi]
    mov     LOC(3), ax
    mov     al, [rdi+2]
    mov     LOC(5), al
    mov     ax, [rdi+3]
    mov     LOC(6), ax
    mov     al, [rdi+5]
    mov     LOC(8), al
    mov     dword LOC(9), 0x00010101
    and     r12d, 255
    and     r13d, 255
    and     r14d, 255
    lea     rbx, [rel r_perm]
    xorpd   xmm10, xmm10
    xor     esi, esi
.corner:
    lea     rdi, [rsi+rsi*2]
    cvtsi2sd xmm9, esi
    mulsd   xmm9, [rel d_G3]
    movzx   eax, byte LOC(rdi)
    cvtsi2sd xmm0, eax
    movapd  xmm1, xmm6
    subsd   xmm1, xmm0
    addsd   xmm1, xmm9
    movzx   eax, byte LOC(rdi+1)
    cvtsi2sd xmm0, eax
    movapd  xmm2, xmm7
    subsd   xmm2, xmm0
    addsd   xmm2, xmm9
    movzx   eax, byte LOC(rdi+2)
    cvtsi2sd xmm0, eax
    movapd  xmm3, xmm8
    subsd   xmm3, xmm0
    addsd   xmm3, xmm9
    movsd   xmm4, [rel d_half]
    movapd  xmm0, xmm1
    mulsd   xmm0, xmm1
    subsd   xmm4, xmm0
    movapd  xmm0, xmm2
    mulsd   xmm0, xmm2
    subsd   xmm4, xmm0
    movapd  xmm0, xmm3
    mulsd   xmm0, xmm3
    subsd   xmm4, xmm0
    xorpd   xmm0, xmm0
    ucomisd xmm4, xmm0
    jbe     .next
    mulsd   xmm4, xmm4
    mulsd   xmm4, xmm4
    ; g = P[ii+o0 + P[jj+o1 + P[kk+o2]]]
    movzx   eax, byte LOC(rdi+2)
    add     eax, r14d
    mov     eax, [rbx+rax*4]
    movzx   ecx, byte LOC(rdi+1)
    add     eax, ecx
    add     eax, r13d
    mov     eax, [rbx+rax*4]
    movzx   ecx, byte LOC(rdi)
    add     eax, ecx
    add     eax, r12d
    mov     eax, [rbx+rax*4]
    imul    eax, eax, 24
    lea     rdx, [rel r_g3]
    mulsd   xmm1, [rdx+rax]
    mulsd   xmm2, [rdx+rax+8]
    mulsd   xmm3, [rdx+rax+16]
    addsd   xmm1, xmm2
    addsd   xmm1, xmm3
    mulsd   xmm1, xmm4
    addsd   xmm10, xmm1
.next:
    inc     esi
    cmp     esi, 4
    jb      .corner
    movapd  xmm0, xmm10
    mulsd   xmm0, [rel d_scale3]
ENDPX
