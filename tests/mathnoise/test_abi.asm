; test_abi.asm - every exported fn of math.asm / noise.asm called through abi_check with
; hostile args; the result has to be bit-identical to a plain call with clean args.
; @link src/math.asm src/noise.asm tests/mathnoise/mn_helpers.asm tests/mathnoise/mn_abi.asm tests/mathnoise/abi_check.asm
; @timeout 120
%include "common.inc"
%include "../mathnoise/mn_test.inc"


section .rdata
align 8
unary_fns:  dq math_sin, math_cos, math_tan, math_sqrt, math_floorf, math_fract, math_exp, math_deg2rad
UNARY_N equ 8
scalar_xs:  dd 1.3, -7.25, 1e7, 0.0
rot_axes:   dd 0, 1, 2, 3, -1

; hash cases (x, y, z, seed)
hash_cases: dd 0, 0, 0, 0
            dd -5, 17, -300000, 12345
            dd 2147483647, -2147483648, 7, 0xFFFFFFFF

; noise probe points (doubles)
noise_pts:  dq 0.3, 0.7, 0.1
            dq -1234.5, 77.25, 9.5
            dq 5000.0, -0.125, -321.0
octs3:      dd 1, 5, 40, -3
octs_fbm3:  dd 1, 4, 0
oct_fns:    dq fbm2, ridged2, warp2
align 4
vec_init:   dd 3.0, 4.0, 12.0
vin_init:   dd 1.0, 2.0, 3.0, 1.0


section .bss
alignb 16
mA:     resd 16
mB:     resd 16
mC1:    resd 16
mC2:    resd 16
mProj:  resd 16
mView:  resd 16
mVP:    resd 16
pl1:    resd 24
pl2:    resd 24
v1:     resd 4
v2:     resd 4
vin:    resd 4
o1:     resd 4
o2:     resd 4
box:    resd 8
seqA:   resq 12
seqB:   resq 12


section .text

%macro CTX_F 2.nolist                          ; pos, float literal
    FCONST  xmm1, %2
    mov     ecx, %1
    call    mn_ctx_f
%endmacro

%macro CTX_FX 2.nolist                         ; pos, xmm register holding a float
    movss   xmm1, %2
    mov     ecx, %1
    call    mn_ctx_f
%endmacro

%macro CTX_I 2.nolist                          ; pos, int32 value (imm / reg / mem)
    mov     edx, %2
    mov     ecx, %1
    call    mn_ctx_i32
%endmacro

%macro CTX_Q 2.nolist                          ; pos, 64-bit value
    mov     rdx, %2
    mov     ecx, %1
    call    mn_ctx_q
%endmacro

%macro CTX_P 2.nolist                          ; pos, label (pointer argument)
    lea     rdx, [rel %2]
    mov     ecx, %1
    call    mn_ctx_q
%endmacro

%macro ACALL 1.nolist                          ; function label
    lea     rcx, [rel %1]
    call    mn_acall
%endmacro

; eax = 1 when the comparison held, otherwise count + print
%macro EXPECT 1.nolist
    test    eax, eax
    jnz     %%ok
    xorpd   xmm0, xmm0
    xorpd   xmm1, xmm1
    xorpd   xmm2, xmm2
    NOTE    %1
%%ok:
%endmacro

%macro MEMEQ 3.nolist
    lea     rsi, [rel %1]
    lea     rdi, [rel %2]
    mov     ecx, %3
    repe    cmpsb
    sete    al
    movzx   eax, al
%endmacro

; bit-identical or both NaN
%macro FSAME 2.nolist
    movss   xmm0, %1
    movss   xmm1, %2
    call    mn_same
%endmacro

%macro GROUP_BEGIN 1.nolist
    TEST    %1
    call    mn_bad_reset
    mov     dword [rel mn_abi_viol], 0
%endmacro

%macro GROUP_END 0.nolist
    CHECK_EQ32 [rel mn_abi_viol], 0, "no Win64 ABI violation in any call"
    CHECK_BAD "results identical to direct calls with clean arguments"
%endmacro

PROCX test_main
    call    abi_scalar
    call    abi_vec_mat
    call    abi_frustum
    call    abi_rng_hash
    call    abi_noise
ENDPX

;  r12 x index, r13 fn index, xmm6 x
PROCX abi_scalar
    GROUP_BEGIN "abi_scalar_math"
    xor     r12d, r12d
.x:
    lea     rax, [rel scalar_xs]
    movss   xmm6, [rax+r12*4]
    xor     r13d, r13d
.fn:
    call    mn_ctx_reset
    CTX_FX  0, xmm6
    lea     rax, [rel unary_fns]
    mov     rcx, [rax+r13*8]
    call    mn_acall
    movss   xmm7, xmm0
    movss   xmm0, xmm6
    lea     rax, [rel unary_fns]
    call    [rax+r13*8]
    FSAME   xmm0, xmm7
    EXPECT  "unary math function via abi_call"
    inc     r13d
    cmp     r13d, UNARY_N
    jb      .fn
    ; sincos: both results
    call    mn_ctx_reset
    CTX_FX  0, xmm6
    ACALL   math_sincos
    movss   xmm7, xmm0
    movss   xmm8, xmm1
    movss   xmm0, xmm6
    call    math_sin
    FSAME   xmm0, xmm7
    EXPECT  "math_sincos sin"
    movss   xmm0, xmm6
    call    math_cos
    FSAME   xmm0, xmm8
    EXPECT  "math_sincos cos"
    ; floor: integer result
    call    mn_ctx_reset
    CTX_FX  0, xmm6
    ACALL   math_floor
    mov     ebx, edx
    movss   xmm0, xmm6
    call    math_floor
    cmp     eax, ebx
    sete    al
    movzx   eax, al
    EXPECT  "math_floor"
    inc     r12d
    cmp     r12d, 4
    jb      .x
    ; two / three argument functions
    call    mn_ctx_reset
    CTX_F   0, -0.5
    CTX_F   1, 0.7
    ACALL   math_atan2
    movss   xmm7, xmm0
    FCONST  xmm0, -0.5
    FCONST  xmm1, 0.7
    call    math_atan2
    FSAME   xmm0, xmm7
    EXPECT  "math_atan2"
    call    mn_ctx_reset
    CTX_F   0, 2.5
    CTX_F   1, 1.7
    ACALL   math_pow
    movss   xmm7, xmm0
    FCONST  xmm0, 2.5
    FCONST  xmm1, 1.7
    call    math_pow
    FSAME   xmm0, xmm7
    EXPECT  "math_pow"

%macro TERN 4.nolist                           ; fn, a, b, c
    call    mn_ctx_reset
    CTX_F   0, %2
    CTX_F   1, %3
    CTX_F   2, %4
    ACALL   %1
    movss   xmm7, xmm0
    FCONST  xmm0, %2
    FCONST  xmm1, %3
    FCONST  xmm2, %4
    call    %1
    FSAME   xmm0, xmm7
    EXPECT  "ternary math function"
%endmacro
    TERN    math_clamp, 5.0, 0.0, 1.0
    TERN    math_lerp, 2.0, 6.0, 0.25
    TERN    math_smoothstep, 0.0, 4.0, 1.0
    GROUP_END
ENDPX






PROCX abi_vec_mat
    GROUP_BEGIN "abi_vec_mat"
    lea     rcx, [rel v1]
    lea     rdx, [rel vec_init]
    mov     rax, [rdx]
    mov     [rcx], rax
    mov     eax, [rdx+8]
    mov     [rcx+8], eax
    lea     rcx, [rel v2]
    mov     rax, [rdx]
    mov     [rcx], rax
    mov     eax, [rdx+8]
    mov     [rcx+8], eax
    call    mn_ctx_reset
    CTX_P   0, v1
    ACALL   vec3_length
    movss   xmm7, xmm0
    FCONST  xmm1, 13.0
    movss   xmm0, xmm7
    call    mn_feq
    EXPECT  "vec3_length == 13"
    call    mn_ctx_reset
    CTX_P   0, v1
    ACALL   vec3_normalize
    lea     rcx, [rel v2]
    call    vec3_normalize
    MEMEQ   v1, v2, 12
    EXPECT  "vec3_normalize"
    call    mn_ctx_reset
    CTX_P   0, mA
    ACALL   mat4_identity
    lea     rcx, [rel mB]
    call    mat4_identity
    MEMEQ   mA, mB, 64
    EXPECT  "mat4_identity"
    ; perspective (far is stack arg 5)
    call    mn_ctx_reset
    CTX_P   0, mA
    CTX_F   1, 70.0
    CTX_F   2, 1.7777777777777777
    CTX_F   3, 0.05
    CTX_F   4, 512.0
    ACALL   mat4_perspective
    lea     rcx, [rel mB]
    FCONST  xmm1, 70.0
    FCONST  xmm2, 1.7777777777777777
    FCONST  xmm3, 0.05
    mov     dword [rsp+32], __?float32?__(512.0)
    call    mat4_perspective
    MEMEQ   mA, mB, 64
    EXPECT  "mat4_perspective"
    lea     rax, [rel mA]
    mov     ecx, [rax]
    and     ecx, 0x7FFFFFFF
    setnz   cl
    mov     edx, [rax+14*4]
    and     edx, 0x7FFFFFFF
    setnz   dl
    and     cl, dl
    movzx   eax, cl
    EXPECT  "perspective m[0] and m[14] non-zero"
    ; ortho (top, near, far on the stack)
    call    mn_ctx_reset
    CTX_P   0, mA
    CTX_F   1, 0.0
    CTX_F   2, 640.0
    CTX_F   3, 360.0
    CTX_F   4, 0.0
    CTX_F   5, -1.0
    CTX_F   6, 1.0
    ACALL   mat4_ortho
    lea     rcx, [rel mB]
    xorps   xmm1, xmm1
    FCONST  xmm2, 640.0
    FCONST  xmm3, 360.0
    mov     dword [rsp+32], 0
    mov     dword [rsp+40], __?float32?__(-1.0)
    mov     dword [rsp+48], __?float32?__(1.0)
    call    mat4_ortho
    MEMEQ   mA, mB, 64
    EXPECT  "mat4_ortho"
    lea     rax, [rel mA]
    cmp     dword [rax+15*4], __?float32?__(1.0)
    sete    al
    movzx   eax, al
    EXPECT  "ortho m[15] == 1"
    ; rotate with garbage in r8[63:32], axes 0 1 2 3 -1
    xor     r12d, r12d
.ax:
    lea     rcx, [rel mA]
    call    persp_small
    lea     rcx, [rel mB]
    call    persp_small
    lea     rax, [rel rot_axes]
    mov     r13d, [rax+r12*4]
    call    mn_ctx_reset
    CTX_P   0, mA
    CTX_F   1, 33.0
    CTX_I   2, r13d
    ACALL   mat4_rotate
    lea     rcx, [rel mB]
    FCONST  xmm1, 33.0
    mov     r8d, r13d
    call    mat4_rotate
    MEMEQ   mA, mB, 64
    EXPECT  "mat4_rotate"
    inc     r12d
    cmp     r12d, 5
    jb      .ax
    call    mn_ctx_reset
    CTX_P   0, mA
    CTX_F   1, 1.5
    CTX_F   2, -2.0
    CTX_F   3, 3.25
    ACALL   mat4_translate
    lea     rcx, [rel mB]
    FCONST  xmm1, 1.5
    FCONST  xmm2, -2.0
    FCONST  xmm3, 3.25
    call    mat4_translate
    MEMEQ   mA, mB, 64
    EXPECT  "mat4_translate"
    call    mn_ctx_reset
    CTX_P   0, mC1
    CTX_P   1, mA
    CTX_P   2, mB
    ACALL   mat4_mul
    lea     rcx, [rel mC2]
    lea     rdx, [rel mA]
    lea     r8, [rel mB]
    call    mat4_mul
    MEMEQ   mC1, mC2, 64
    EXPECT  "mat4_mul"
    lea     rcx, [rel vin]
    lea     rdx, [rel vin_init]
    movups  xmm0, [rdx]
    movups  [rcx], xmm0
    call    mn_ctx_reset
    CTX_P   0, mA
    CTX_P   1, vin
    CTX_P   2, o1
    ACALL   mat4_transform
    lea     rcx, [rel mA]
    lea     rdx, [rel vin]
    lea     r8, [rel o2]
    call    mat4_transform
    MEMEQ   o1, o2, 16
    EXPECT  "mat4_transform"
    GROUP_END
ENDPX


; perspective(70, 1.5, 0.1, 100), plain call
PROC persp_small
    FCONST  xmm1, 70.0
    FCONST  xmm2, 1.5
    FCONST  xmm3, 0.1
    mov     dword [rsp+32], __?float32?__(100.0)
    call    mat4_perspective
ENDP

;  xmm6-8 x,y,z, xmm9 s (floats); r12 loop; r13 visible count
PROCX abi_frustum
    GROUP_BEGIN "abi_frustum"
    lea     rcx, [rel mProj]
    FCONST  xmm1, 70.0
    FCONST  xmm2, 1.7777777777777777
    FCONST  xmm3, 0.05
    mov     dword [rsp+32], __?float32?__(300.0)
    call    mat4_perspective
    lea     rcx, [rel mView]
    call    mat4_identity
    lea     rcx, [rel mView]
    FCONST  xmm1, 20.0
    xor     r8d, r8d
    call    mat4_rotate
    lea     rcx, [rel mView]
    FCONST  xmm1, -135.0
    mov     r8d, 1
    call    mat4_rotate
    lea     rcx, [rel mVP]
    lea     rdx, [rel mProj]
    lea     r8, [rel mView]
    call    mat4_mul
    call    mn_ctx_reset
    CTX_P   0, pl1
    CTX_P   1, mVP
    ACALL   frustum_extract
    lea     rcx, [rel pl2]
    lea     rdx, [rel mVP]
    call    frustum_extract
    MEMEQ   pl1, pl2, 96
    EXPECT  "frustum_extract"
    mov     ecx, 5
    call    mn_seed
    xor     r13d, r13d
    mov     r12d, 400
.l:
    FCONST  xmm0, -80.0
    FCONST  xmm1, 80.0
    call    mn_uniform
    movss   xmm6, xmm0
    FCONST  xmm0, -80.0
    FCONST  xmm1, 80.0
    call    mn_uniform
    movss   xmm7, xmm0
    FCONST  xmm0, -80.0
    FCONST  xmm1, 80.0
    call    mn_uniform
    movss   xmm8, xmm0
    FCONST  xmm0, 0.5
    FCONST  xmm1, 9.0
    call    mn_uniform
    movss   xmm9, xmm0
    lea     rbx, [rel box]
    movss   [rbx], xmm6
    movss   [rbx+4], xmm7
    movss   [rbx+8], xmm8
    cvtss2sd xmm1, xmm9
    cvtss2sd xmm0, xmm6
    addsd   xmm0, xmm1
    cvtsd2ss xmm0, xmm0
    movss   [rbx+12], xmm0
    cvtss2sd xmm0, xmm7
    addsd   xmm0, xmm1
    cvtsd2ss xmm0, xmm0
    movss   [rbx+16], xmm0
    cvtss2sd xmm0, xmm8
    addsd   xmm0, xmm1
    cvtsd2ss xmm0, xmm0
    movss   [rbx+20], xmm0
    call    mn_ctx_reset
    CTX_P   0, pl1
    CTX_P   1, box
    ACALL   frustum_test_aabb
    mov     r14d, edx
    lea     rcx, [rel pl1]
    lea     rdx, [rel box]
    call    frustum_test_aabb
    cmp     eax, r14d
    sete    al
    movzx   eax, al
    EXPECT  "frustum_test_aabb"
    call    mn_ctx_reset
    CTX_P   0, pl1
    CTX_FX  1, xmm6
    CTX_FX  2, xmm7
    CTX_FX  3, xmm8
    CTX_FX  4, xmm9
    ACALL   frustum_test_sphere
    mov     r14d, edx
    lea     rcx, [rel pl1]
    movss   xmm1, xmm6
    movss   xmm2, xmm7
    movss   xmm3, xmm8
    movss   [rsp+32], xmm9
    call    frustum_test_sphere
    add     r13d, eax
    cmp     eax, r14d
    sete    al
    movzx   eax, al
    EXPECT  "frustum_test_sphere"
    dec     r12d
    jnz     .l
    xor     eax, eax
    cmp     r13d, 20
    jbe     .vr
    cmp     r13d, 380
    jae     .vr
    mov     eax, 1
.vr:
    CHECK_TRUE eax, "the 400 spheres exercise both outcomes (20 < visible < 380)"
    GROUP_END
ENDPX


PROCX abi_rng_hash
    GROUP_BEGIN "abi_rng_hash"
    call    mn_ctx_reset
    mov     rax, 0xFFFFFFFF00000001
    CTX_Q   0, rax
    ACALL   rng_seed
    lea     rbx, [rel seqA]
    xor     r12d, r12d
.n:
    call    mn_ctx_reset
    ACALL   rng_next
    mov     [rbx+r12*8], rdx
    inc     r12d
    cmp     r12d, 4
    jb      .n
.i:
    call    mn_ctx_reset
    CTX_I   0, 1000
    ACALL   rng_int
    mov     edx, edx
    mov     [rbx+r12*8], rdx
    inc     r12d
    cmp     r12d, 8
    jb      .i
.f:
    call    mn_ctx_reset
    ACALL   rng_float
    movd    eax, xmm0
    mov     [rbx+r12*8], rax
    inc     r12d
    cmp     r12d, 10
    jb      .f
.s:
    call    mn_ctx_reset
    ACALL   rng_float_signed
    movd    eax, xmm0
    mov     [rbx+r12*8], rax
    inc     r12d
    cmp     r12d, 12
    jb      .s
    ; the same sequence by direct calls
    mov     rcx, 0xFFFFFFFF00000001
    call    rng_seed
    lea     rbx, [rel seqB]
    xor     r12d, r12d
.dn:
    call    rng_next
    mov     [rbx+r12*8], rax
    inc     r12d
    cmp     r12d, 4
    jb      .dn
.di:
    mov     ecx, 1000
    call    rng_int
    mov     eax, eax
    mov     [rbx+r12*8], rax
    inc     r12d
    cmp     r12d, 8
    jb      .di
.df:
    call    rng_float
    movd    eax, xmm0
    mov     [rbx+r12*8], rax
    inc     r12d
    cmp     r12d, 10
    jb      .df
.ds:
    call    rng_float_signed
    movd    eax, xmm0
    mov     [rbx+r12*8], rax
    inc     r12d
    cmp     r12d, 12
    jb      .ds
    MEMEQ   seqA, seqB, 96
    EXPECT  "rng_seed/next/int/float/float_signed sequence"
    ; hashes; r13 -> case (x, y, z, s)
    xor     r12d, r12d
.h:
    lea     r13, [rel hash_cases]
    mov     eax, r12d
    shl     eax, 4
    add     r13, rax
    call    mn_ctx_reset
    CTX_I   0, [r13]
    CTX_I   1, [r13+8]
    CTX_I   2, [r13+12]
    ACALL   hash2
    mov     r14d, edx
    mov     ecx, [r13]
    mov     edx, [r13+8]
    mov     r8d, [r13+12]
    call    hash2
    cmp     eax, r14d
    sete    al
    movzx   eax, al
    EXPECT  "hash2"
    call    mn_ctx_reset
    CTX_I   0, [r13]
    CTX_I   1, [r13+4]
    CTX_I   2, [r13+8]
    CTX_I   3, [r13+12]
    ACALL   hash3
    mov     r14d, edx
    mov     ecx, [r13]
    mov     edx, [r13+4]
    mov     r8d, [r13+8]
    mov     r9d, [r13+12]
    call    hash3
    cmp     eax, r14d
    sete    al
    movzx   eax, al
    EXPECT  "hash3"
    call    mn_ctx_reset
    CTX_I   0, [r13]
    CTX_I   1, [r13+8]
    CTX_I   2, [r13+12]
    ACALL   hash_float2
    movss   xmm6, xmm0
    mov     ecx, [r13]
    mov     edx, [r13+8]
    mov     r8d, [r13+12]
    call    hash_float2
    FSAME   xmm0, xmm6
    EXPECT  "hash_float2"
    xor     eax, eax
    xorps   xmm1, xmm1
    comiss  xmm6, xmm1
    jb      .hr
    FCONST  xmm1, 1.0
    comiss  xmm6, xmm1
    jae     .hr
    mov     eax, 1
.hr:
    EXPECT  "hash_float2 in [0,1)"
    inc     r12d
    cmp     r12d, 3
    jb      .h
    GROUP_END
ENDPX


;  r12 point, r13 octave index, r14 fn index; xmm6-8 point (doubles)
PROCX abi_noise
    GROUP_BEGIN "abi_noise"
    call    mn_ctx_reset
    mov     rax, 0x0123456789ABCDEF
    CTX_Q   0, rax
    ACALL   noise_set_seed
    FCONST  xmm0, 13.37
    FCONST  xmm1, -4.2
    call    noise2
    movss   xmm6, xmm0
    mov     rcx, 0x0123456789ABCDEF
    call    noise_set_seed
    FCONST  xmm0, 13.37
    FCONST  xmm1, -4.2
    call    noise2
    FSAME   xmm0, xmm6
    EXPECT  "noise_set_seed through abi_call == direct"
    xor     r12d, r12d
.p:
    imul    eax, r12d, 24
    lea     rbx, [rel noise_pts]
    add     rbx, rax
    movsd   xmm6, [rbx]
    movsd   xmm7, [rbx+8]
    movsd   xmm8, [rbx+16]
    ; noise2 / noise3 at f32(point)
    call    mn_ctx_reset
    cvtsd2ss xmm1, xmm6
    mov     ecx, 0
    call    mn_ctx_f
    cvtsd2ss xmm1, xmm7
    mov     ecx, 1
    call    mn_ctx_f
    ACALL   noise2
    movss   xmm9, xmm0
    cvtsd2ss xmm0, xmm6
    cvtsd2ss xmm1, xmm7
    call    noise2
    FSAME   xmm0, xmm9
    EXPECT  "noise2"
    call    mn_ctx_reset
    cvtsd2ss xmm1, xmm6
    mov     ecx, 0
    call    mn_ctx_f
    cvtsd2ss xmm1, xmm7
    mov     ecx, 1
    call    mn_ctx_f
    cvtsd2ss xmm1, xmm8
    mov     ecx, 2
    call    mn_ctx_f
    ACALL   noise3
    movss   xmm9, xmm0
    cvtsd2ss xmm0, xmm6
    cvtsd2ss xmm1, xmm7
    cvtsd2ss xmm2, xmm8
    call    noise3
    FSAME   xmm0, xmm9
    EXPECT  "noise3"
    ; fbm2 / ridged2 / warp2 at f32(x*0.01), f32(y*0.01), octaves 1 5 40 -3
    DCONST  xmm0, 0.01
    movapd  xmm10, xmm6
    mulsd   xmm10, xmm0
    cvtsd2ss xmm10, xmm10
    movapd  xmm11, xmm7
    mulsd   xmm11, xmm0
    cvtsd2ss xmm11, xmm11
    xor     r14d, r14d
.fn:
    xor     r13d, r13d
.oc:
    lea     rax, [rel octs3]
    mov     r15d, [rax+r13*4]
    call    mn_ctx_reset
    CTX_FX  0, xmm10
    CTX_FX  1, xmm11
    CTX_I   2, r15d
    lea     rax, [rel oct_fns]
    mov     rcx, [rax+r14*8]
    call    mn_acall
    movss   xmm9, xmm0
    movss   xmm0, xmm10
    movss   xmm1, xmm11
    mov     r8d, r15d
    lea     rax, [rel oct_fns]
    call    [rax+r14*8]
    FSAME   xmm0, xmm9
    EXPECT  "fbm2 / ridged2 / warp2 with octaves 1 5 40 -3"
    inc     r13d
    cmp     r13d, 4
    jb      .oc
    inc     r14d
    cmp     r14d, 3
    jb      .fn
    ; fbm3 at f32(p*0.02), octaves 1 4 0 (octaves in r9 with garbage)
    DCONST  xmm0, 0.02
    movapd  xmm10, xmm6
    mulsd   xmm10, xmm0
    cvtsd2ss xmm10, xmm10
    movapd  xmm11, xmm7
    mulsd   xmm11, xmm0
    cvtsd2ss xmm11, xmm11
    movapd  xmm12, xmm8
    mulsd   xmm12, xmm0
    cvtsd2ss xmm12, xmm12
    xor     r13d, r13d
.o3:
    lea     rax, [rel octs_fbm3]
    mov     r15d, [rax+r13*4]
    call    mn_ctx_reset
    CTX_FX  0, xmm10
    CTX_FX  1, xmm11
    CTX_FX  2, xmm12
    CTX_I   3, r15d
    ACALL   fbm3
    movss   xmm9, xmm0
    movss   xmm0, xmm10
    movss   xmm1, xmm11
    movss   xmm2, xmm12
    mov     r9d, r15d
    call    fbm3
    FSAME   xmm0, xmm9
    EXPECT  "fbm3 with octaves 1 4 0"
    inc     r13d
    cmp     r13d, 3
    jb      .o3
    inc     r12d
    cmp     r12d, 3
    jb      .p
    GROUP_END
ENDPX
