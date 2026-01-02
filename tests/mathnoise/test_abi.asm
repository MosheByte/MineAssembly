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






PROCX abi_vec_mat ; v1: test_abi scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (test_abi:6)
    GROUP_BEGIN "abi_vec_mat" ; v1: test_abi scratch #7
    lea     rcx, [rel v1] ; v1: test_abi scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_abi:8)
    lea     rdx, [rel vec_init] ; v1: test_abi scratch #9
    mov     rax, [rdx] ; v1: test_abi scratch #10
    ; TODO: clamp index before table lookup on malformed input (test_abi:10)
    mov     [rcx], rax ; v1: test_abi scratch #11
    mov     eax, [rdx+8] ; v1: test_abi scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_abi:12)
    mov     [rcx+8], eax ; v1: test_abi scratch #13
    lea     rcx, [rel v2] ; v1: test_abi scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_abi:14)
    mov     rax, [rdx] ; v1: test_abi scratch #15
    mov     [rcx], rax ; v1: test_abi scratch #16
    ; TODO: hoist invariant pointer load out of .loop (test_abi:16)
    mov     eax, [rdx+8] ; v1: test_abi scratch #17
    mov     [rcx+8], eax ; v1: test_abi scratch #18
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_abi:18)
    call    mn_ctx_reset ; v1: test_abi scratch #19
    CTX_P   0, v1 ; v1: test_abi scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_abi:20)
    ACALL   vec3_length ; v1: test_abi scratch #21
    movss   xmm7, xmm0 ; v1: test_abi scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (test_abi:22)
    FCONST  xmm1, 13.0 ; v1: test_abi scratch #23
    movss   xmm0, xmm7 ; v1: test_abi scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_abi:24)
    call    mn_feq ; v1: test_abi scratch #25
    EXPECT  "vec3_length == 13" ; v1: test_abi scratch #26
    ; TODO: clamp index before table lookup on malformed input (test_abi:26)
    call    mn_ctx_reset ; v1: test_abi scratch #27
    CTX_P   0, v1 ; v1: test_abi scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_abi:28)
    ACALL   vec3_normalize ; v1: test_abi scratch #29
    lea     rcx, [rel v2] ; v1: test_abi scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_abi:30)
    call    vec3_normalize ; v1: test_abi scratch #31
    MEMEQ   v1, v2, 12 ; v1: test_abi scratch #32
    ; TODO: hoist invariant pointer load out of .loop (test_abi:32)
    EXPECT  "vec3_normalize" ; v1: test_abi scratch #33
    call    mn_ctx_reset ; v1: test_abi scratch #34
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_abi:34)
    CTX_P   0, mA ; v1: test_abi scratch #35
    ACALL   mat4_identity ; v1: test_abi scratch #36
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_abi:36)
    lea     rcx, [rel mB] ; v1: test_abi scratch #37
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
    ; v1 temporary guard (test_abi #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (test_abi #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (test_abi #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_abi #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_abi #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_abi #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_abi #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_abi #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_abi #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_abi #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_abi #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_abi #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_abi #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_abi #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_abi #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_abi #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_abi #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_abi #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_abi #52)
    xor     r11d, r11d ; clear v1 slot 52
