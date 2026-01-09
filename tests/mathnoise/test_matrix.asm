; test_matrix.asm - mat4 + frustum culling vs double refs (ref_mul_d / ref_rot_d /
; ref_planes_d), passing when |got-ref| <= tol*max(1,|ref|). multiplies cover all three
; aliasing cases; perspective/ortho expectations are golden doubles.
; @link src/math.asm tests/mathnoise/mn_helpers.asm
; @timeout 120
%include "common.inc"
%include "../mathnoise/mn_test.inc"



section .rdata
align 8

; perspective(70 deg, 16/9, 0.05, 500): f = 1/tan(35 deg)
persp_ref:
    dq 0.8033332537924395, 0.0, 0.0, 0.0, 0.0, 1.4281480067421146, 0.0, 0.0
    dq 0.0, 0.0, -1.0002000200020003, -1.0, 0.0, 0.0, -0.10001000100010002, 0.0

; ortho(l=0, r=640, b=360, t=0, n=-1, f=1)
ortho_ref:
    dq 0.003125, 0.0, 0.0, 0.0, 0.0, -0.005555555555555556, 0.0, 0.0
    dq 0.0, 0.0, -1.0, 0.0, -1.0, 1.0, 0.0, 1.0
align 4
ident_f:
    dd 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0
seq_f:
    dd 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0

; fixed boxes for the "camera looks down -Z" checks
box_front:  dd -1.0, -1.0, -11.0, 1.0, 1.0, -9.0
box_behind: dd -1.0, -1.0, 9.0, 1.0, 1.0, 11.0



section .bss
alignb 16
fA:     resd 16                         ; random A (kept)
fB:     resd 16                         ; random B (kept)
fW1:    resd 16
fW2:    resd 16
fW3:    resd 16
fProj:  resd 16
fView:  resd 16
fVP:    resd 16
fPl:    resd 24
fBox:   resd 8
fV:     resd 4
fOut:   resd 4
dA:     resq 16
dB:     resq 16
dR:     resq 16
dRef:   resq 24
dV:     resq 4
dP:     resq 24
vis_count: resd 1



section .text


PROCX test_main
    call    mx_mul_alias
    call    mx_persp_ortho
    call    mx_rot_trans_xform
    call    mx_frustum_extract
    call    mx_frustum_cull
ENDPX


LEAF copy16
    movups  xmm0, [rdx]
    movups  xmm1, [rdx+16]
    movups  xmm2, [rdx+32]
    movups  xmm3, [rdx+48]
    movups  [rcx], xmm0
    movups  [rcx+16], xmm1
    movups  [rcx+32], xmm2
    movups  [rcx+48], xmm3
    ret


; entries U(-3, 3)
PROC rand_mat
    mov     rbx, rcx
    xor     esi, esi
.l:
    FCONST  xmm0, -3.0
    FCONST  xmm1, 3.0
    call    mn_uniform
    movss   [rbx+rsi*4], xmm0
    inc     esi
    cmp     esi, 16
    jb      .l
ENDP


PROC close16
    mov     r8d, 16
    call    mn_close
ENDP


; fVP = perspective(70,1.5,.05,200) * Rx(pitch) * Ry(yaw)
PROCX camera
    movss   xmm6, xmm0
    movss   xmm7, xmm1
    lea     rcx, [rel fProj]
    FCONST  xmm1, 70.0
    FCONST  xmm2, 1.5
    FCONST  xmm3, 0.05
    mov     dword [rsp+32], __?float32?__(200.0)
    call    mat4_perspective
    lea     rcx, [rel fView]
    call    mat4_identity
    lea     rcx, [rel fView]
    movss   xmm1, xmm7
    xor     r8d, r8d
    call    mat4_rotate
    lea     rcx, [rel fView]
    movss   xmm1, xmm6
    mov     r8d, 1
    call    mat4_rotate
    lea     rcx, [rel fVP]
    lea     rdx, [rel fProj]
    lea     r8, [rel fView]
    call    mat4_mul
ENDPX


PROCX mx_mul_alias
    TEST    "mat4_identity_mul_alias"
    lea     rcx, [rel fW1]
    call    mat4_identity
    lea     rax, [rel fW1]
    lea     rdx, [rel ident_f]
    CHECK_MEM rax, rdx, 64, "mat4_identity"
    call    mn_bad_reset
    mov     ecx, 10
    call    mn_seed
    mov     r12d, 200
.l:
    lea     rcx, [rel fA]
    call    rand_mat
    lea     rcx, [rel fB]
    call    rand_mat
    lea     rcx, [rel dA]
    lea     rdx, [rel fA]
    mov     r8d, 16
    call    mn_f2d
    lea     rcx, [rel dB]
    lea     rdx, [rel fB]
    mov     r8d, 16
    call    mn_f2d
    lea     rcx, [rel dRef]
    lea     rdx, [rel dA]
    lea     r8, [rel dB]
    call    ref_mul_d
    xor     r13d, r13d                  ; failure bits for this round
    lea     rcx, [rel fW1]
    lea     rdx, [rel fA]
    lea     r8, [rel fB]
    call    mat4_mul
    lea     rcx, [rel fW1]
    lea     rdx, [rel dRef]
    DCONST  xmm3, 1e-5
    call    close16
    xor     eax, 1
    or      r13d, eax
    ; dst aliases a
    lea     rcx, [rel fW1]
    lea     rdx, [rel fA]
    call    copy16
    lea     rcx, [rel fW1]
    lea     rdx, [rel fW1]
    lea     r8, [rel fB]
    call    mat4_mul
    lea     rcx, [rel fW1]
    lea     rdx, [rel dRef]
    DCONST  xmm3, 1e-5
    call    close16
    xor     eax, 1
    shl     eax, 1
    or      r13d, eax
    ; dst aliases b
    lea     rcx, [rel fW2]
    lea     rdx, [rel fB]
    call    copy16
    lea     rcx, [rel fW2]
    lea     rdx, [rel fA]
    lea     r8, [rel fW2]
    call    mat4_mul
    lea     rcx, [rel fW2]
    lea     rdx, [rel dRef]
    DCONST  xmm3, 1e-5
    call    close16
    xor     eax, 1
    shl     eax, 2
    or      r13d, eax
    ; dst aliases both: A*A
    lea     rcx, [rel dRef]
    lea     rdx, [rel dA]
    lea     r8, [rel dA]
    call    ref_mul_d
    lea     rcx, [rel fW3]
    lea     rdx, [rel fA]
    call    copy16
    lea     rcx, [rel fW3]
    lea     rdx, [rel fW3]
    lea     r8, [rel fW3]
    call    mat4_mul
    lea     rcx, [rel fW3]
    lea     rdx, [rel dRef]
    DCONST  xmm3, 1e-5
    call    close16
    xor     eax, 1
    shl     eax, 3
    or      r13d, eax
    test    r13d, r13d
    jz      .next
    cvtsi2sd xmm0, r12d
    cvtsi2sd xmm1, r13d
    xorpd   xmm2, xmm2
    NOTE    "mat4_mul round, failed-case bits (1 plain 2 dst=a 4 dst=b 8 dst=a=b)"
.next:
    dec     r12d
    jnz     .l

    CHECK_BAD "mat4_mul == A*B for distinct and aliased dst"
ENDPX


PROCX mx_persp_ortho
    TEST    "mat4_perspective_ortho"
    lea     rcx, [rel fW1]
    FCONST  xmm1, 70.0
    mov     eax, __?float32?__(1.7777777777777777)
    movd    xmm2, eax
    FCONST  xmm3, 0.05
    mov     dword [rsp+32], __?float32?__(500.0)
    call    mat4_perspective
    lea     rcx, [rel fW1]
    lea     rdx, [rel persp_ref]
    DCONST  xmm3, 1e-5
    call    close16
    CHECK_TRUE eax, "perspective(70, 16/9, 0.05, 500) matches the GL formula"
    lea     rcx, [rel fW1]
    xorps   xmm1, xmm1
    FCONST  xmm2, 640.0
    FCONST  xmm3, 360.0
    mov     dword [rsp+32], __?float32?__(0.0)
    mov     dword [rsp+40], __?float32?__(-1.0)
    mov     dword [rsp+48], __?float32?__(1.0)
    call    mat4_ortho
    lea     rcx, [rel fW1]
    lea     rdx, [rel ortho_ref]
    DCONST  xmm3, 1e-5
    call    close16
    CHECK_TRUE eax, "ortho(0, 640, 360, 0, -1, 1) matches the GL formula"
ENDPX




PROCX mx_rot_trans_xform
    TEST    "mat4_rotate_translate_transform"
    call    mn_bad_reset
    mov     ecx, 11
    call    mn_seed
    mov     r12d, 300
.l:
    lea     rcx, [rel fA]
    call    rand_mat
    lea     rcx, [rel dA]
    lea     rdx, [rel fA]
    mov     r8d, 16
    call    mn_f2d
    xor     ecx, ecx
    mov     edx, 2
    call    mn_randint
    mov     r13d, eax
    FCONST  xmm0, -720.0
    FCONST  xmm1, 720.0
    call    mn_uniform
    movss   xmm6, xmm0
    lea     rcx, [rel dB]
    mov     edx, r13d
    movss   xmm2, xmm6
    call    ref_rot_d
    lea     rcx, [rel dRef]
    lea     rdx, [rel dA]
    lea     r8, [rel dB]
    call    ref_mul_d
    lea     rcx, [rel fW1]
    lea     rdx, [rel fA]
    call    copy16
    lea     rcx, [rel fW1]
    movss   xmm1, xmm6
    mov     r8d, r13d
    call    mat4_rotate
    lea     rcx, [rel fW1]
    lea     rdx, [rel dRef]
    DCONST  xmm3, 2e-5
    call    close16
    test    eax, eax
    jnz     .rot_ok
    cvtsi2sd xmm0, r13d
    cvtss2sd xmm1, xmm6
    xorpd   xmm2, xmm2
    NOTE    "rotate axis, deg"
.rot_ok:
    FCONST  xmm0, -50.0
    FCONST  xmm1, 50.0
    call    mn_uniform
    movss   xmm7, xmm0
    FCONST  xmm0, -50.0
    FCONST  xmm1, 50.0
    call    mn_uniform
    movss   xmm8, xmm0
    FCONST  xmm0, -50.0
    FCONST  xmm1, 50.0
    call    mn_uniform
    movss   xmm9, xmm0
    lea     rcx, [rel dB]               ; T = identity with column 3 = (x,y,z,1)
    xor     eax, eax
    mov     edx, 16
.zt:
    mov     [rcx], rax
    add     rcx, 8
    dec     edx
    jnz     .zt
    lea     rcx, [rel dB]
    DCONST  xmm0, 1.0
    movsd   [rcx+0*8], xmm0
    movsd   [rcx+5*8], xmm0
    movsd   [rcx+10*8], xmm0
    movsd   [rcx+15*8], xmm0
    cvtss2sd xmm0, xmm7
    movsd   [rcx+12*8], xmm0
    cvtss2sd xmm0, xmm8
    movsd   [rcx+13*8], xmm0
    cvtss2sd xmm0, xmm9
    movsd   [rcx+14*8], xmm0
    lea     rcx, [rel dRef]
    lea     rdx, [rel dA]
    lea     r8, [rel dB]
    call    ref_mul_d
    lea     rcx, [rel fW1]
    lea     rdx, [rel fA]
    call    copy16
    lea     rcx, [rel fW1]
    movss   xmm1, xmm7
    movss   xmm2, xmm8
    movss   xmm3, xmm9
    call    mat4_translate
    lea     rcx, [rel fW1]
    lea     rdx, [rel dRef]
    DCONST  xmm3, 1e-5
    call    close16
    test    eax, eax
    jnz     .tr_ok
    cvtss2sd xmm0, xmm7
    cvtss2sd xmm1, xmm8
    cvtss2sd xmm2, xmm9
    NOTE    "translate x, y, z"
.tr_ok:
    ; transform: out[i] = sum_k A[k*4+i] * v[k]
    xor     ebx, ebx
.v:
    FCONST  xmm0, -9.0
    FCONST  xmm1, 9.0
    call    mn_uniform
    lea     rax, [rel fV]
    movss   [rax+rbx*4], xmm0
    inc     ebx
    cmp     ebx, 4
    jb      .v
    xor     ebx, ebx
.ri:
    xorpd   xmm0, xmm0
    xor     esi, esi
.rk:
    lea     eax, [rsi*4+rbx]
    lea     rdx, [rel dA]
    movsd   xmm1, [rdx+rax*8]
    lea     rdx, [rel fV]
    cvtss2sd xmm2, [rdx+rsi*4]
    mulsd   xmm1, xmm2
    addsd   xmm0, xmm1
    inc     esi
    cmp     esi, 4
    jb      .rk
    lea     rdx, [rel dV]
    movsd   [rdx+rbx*8], xmm0
    inc     ebx
    cmp     ebx, 4
    jb      .ri
    lea     rcx, [rel fA]
    lea     rdx, [rel fV]
    lea     r8, [rel fOut]
    call    mat4_transform
    lea     rcx, [rel fOut]
    lea     rdx, [rel dV]
    mov     r8d, 4
    DCONST  xmm3, 1e-5
    call    mn_close
    test    eax, eax
    jnz     .xf_ok
    cvtsi2sd xmm0, r12d
    xorpd   xmm1, xmm1
    xorpd   xmm2, xmm2
    NOTE    "transform round"
.xf_ok:
    ; in place: transform(A, v, v) must equal out
    lea     rcx, [rel dV]
    lea     rdx, [rel fOut]
    mov     r8d, 4
    call    mn_f2d
    lea     rcx, [rel fA]
    lea     rdx, [rel fV]
    lea     r8, [rel fV]
    call    mat4_transform
    lea     rcx, [rel fV]
    lea     rdx, [rel dV]
    mov     r8d, 4
    DCONST  xmm3, 1e-5
    call    mn_close
    test    eax, eax
    jnz     .ip_ok
    cvtsi2sd xmm0, r12d
    xorpd   xmm1, xmm1
    xorpd   xmm2, xmm2
    NOTE    "in-place transform round"
.ip_ok:
    dec     r12d
    jnz     .l
    CHECK_BAD "rotate (2e-5) / translate / transform (1e-5) match references"
    ; invalid axis: no-op
    lea     rcx, [rel fW1]
    lea     rdx, [rel seq_f]
    call    copy16
    lea     rcx, [rel fW1]
    FCONST  xmm1, 30.0
    mov     r8d, 7
    call    mat4_rotate
    lea     rax, [rel fW1]
    lea     rdx, [rel seq_f]
    CHECK_MEM rax, rdx, 64, "mat4_rotate with axis 7 leaves the matrix unchanged"
ENDPX


PROCX mx_frustum_extract
    TEST    "frustum_extract"
    call    mn_bad_reset
    mov     ecx, 12
    call    mn_seed
    mov     r12d, 100
.l:
    FCONST  xmm0, -180.0
    FCONST  xmm1, 180.0
    call    mn_uniform
    movss   xmm6, xmm0
    FCONST  xmm0, -89.0
    FCONST  xmm1, 89.0
    call    mn_uniform
    movss   xmm1, xmm0
    movss   xmm0, xmm6
    call    camera
    lea     rcx, [rel fPl]
    lea     rdx, [rel fVP]
    call    frustum_extract
    lea     rcx, [rel dP]
    lea     rdx, [rel fVP]
    call    ref_planes_d
    lea     rcx, [rel fPl]
    lea     rdx, [rel dP]
    mov     r8d, 24
    DCONST  xmm3, 1e-5
    call    mn_close
    test    eax, eax
    jnz     .unit
    cvtss2sd xmm0, xmm6
    xorpd   xmm1, xmm1
    xorpd   xmm2, xmm2
    NOTE    "planes differ from reference, yaw"
.unit:
    xor     ebx, ebx
.u:
    imul    eax, ebx, 16
    lea     rcx, [rel fPl]
    add     rcx, rax
    cvtss2sd xmm0, [rcx]
    mulsd   xmm0, xmm0
    cvtss2sd xmm1, [rcx+4]
    mulsd   xmm1, xmm1
    addsd   xmm0, xmm1
    cvtss2sd xmm1, [rcx+8]
    mulsd   xmm1, xmm1
    addsd   xmm0, xmm1
    sqrtsd  xmm0, xmm0
    movapd  xmm7, xmm0
    DCONST  xmm1, 1.0
    DCONST  xmm2, 1e-5
    call    mn_near_d
    test    eax, eax
    jnz     .un
    cvtsi2sd xmm0, ebx
    movapd  xmm1, xmm7
    xorpd   xmm2, xmm2
    NOTE    "plane normal not unit: plane, length"
.un:
    inc     ebx
    cmp     ebx, 6
    jb      .u
    dec     r12d
    jnz     .l
    CHECK_BAD "frustum_extract == normalised Gribb-Hartmann planes, unit normals"
ENDPX



; a*x+b*y+c*z+d against dP
LEAF plane_dot ; v1: test_matrix scratch #2
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_matrix:2)
    shl     ecx, 5 ; v1: test_matrix scratch #3
    lea     rax, [rel dP] ; v1: test_matrix scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (test_matrix:4)
    add     rax, rcx ; v1: test_matrix scratch #5
    mulsd   xmm0, [rax] ; v1: test_matrix scratch #6
    ; TODO: clamp index before table lookup on malformed input (test_matrix:6)
    mulsd   xmm1, [rax+8] ; v1: test_matrix scratch #7
    addsd   xmm0, xmm1 ; v1: test_matrix scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_matrix:8)
    mulsd   xmm2, [rax+16] ; v1: test_matrix scratch #9
    addsd   xmm0, xmm2 ; v1: test_matrix scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_matrix:10)
    addsd   xmm0, [rax+24] ; v1: test_matrix scratch #11
    ret ; v1: test_matrix scratch #12
    ; TODO: hoist invariant pointer load out of .loop (test_matrix:12)



; 40 cameras x 250 boxes: aabb p-vertex ref, centres inside the clip volume must never
; get culled, sphere ref. xmm6-8 centre, xmm9 h (floats)
PROCX mx_frustum_cull, 32 ; v1: test_matrix scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_matrix:18)
    TEST    "frustum_aabb_and_sphere" ; v1: test_matrix scratch #19
    call    mn_bad_reset ; v1: test_matrix scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_matrix:20)
    mov     ecx, 13 ; v1: test_matrix scratch #21
    call    mn_seed ; v1: test_matrix scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_matrix:22)
    mov     r12d, 40 ; v1: test_matrix scratch #23
.cam: ; v1: test_matrix scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (test_matrix:24)
    FCONST  xmm0, -180.0 ; v1: test_matrix scratch #25
    FCONST  xmm1, 180.0 ; v1: test_matrix scratch #26
    ; TODO: clamp index before table lookup on malformed input (test_matrix:26)
    call    mn_uniform ; v1: test_matrix scratch #27
    movss   xmm6, xmm0 ; v1: test_matrix scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_matrix:28)
    FCONST  xmm0, -60.0 ; v1: test_matrix scratch #29
    FCONST  xmm1, 60.0 ; v1: test_matrix scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_matrix:30)
    call    mn_uniform ; v1: test_matrix scratch #31
    movss   xmm1, xmm0 ; v1: test_matrix scratch #32
    ; TODO: hoist invariant pointer load out of .loop (test_matrix:32)
    movss   xmm0, xmm6 ; v1: test_matrix scratch #33
    call    camera ; v1: test_matrix scratch #34
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_matrix:34)
    lea     rcx, [rel fPl] ; v1: test_matrix scratch #35
    lea     rdx, [rel fVP] ; v1: test_matrix scratch #36
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_matrix:36)
    call    frustum_extract ; v1: test_matrix scratch #37
    lea     rcx, [rel dP] ; v1: test_matrix scratch #38
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_matrix:38)
    lea     rdx, [rel fPl] ; v1: test_matrix scratch #39
    mov     r8d, 24 ; v1: test_matrix scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (test_matrix:40)
    call    mn_f2d ; v1: test_matrix scratch #41
    mov     r13d, 250 ; v1: test_matrix scratch #42
    ; TODO: clamp index before table lookup on malformed input (test_matrix:42)
.box:
    FCONST  xmm0, -120.0
    FCONST  xmm1, 120.0
    call    mn_uniform
    movss   xmm6, xmm0
    FCONST  xmm0, -120.0
    FCONST  xmm1, 120.0
    call    mn_uniform
    movss   xmm7, xmm0
    FCONST  xmm0, -120.0
    FCONST  xmm1, 120.0
    call    mn_uniform
    movss   xmm8, xmm0
    FCONST  xmm0, 0.1
    FCONST  xmm1, 8.0
    call    mn_uniform
    movss   xmm9, xmm0
    ; box = f32(c -+ h)
    cvtss2sd xmm10, xmm9
    lea     rbx, [rel fBox]
    cvtss2sd xmm0, xmm6
    movapd  xmm1, xmm0
    subsd   xmm0, xmm10
    addsd   xmm1, xmm10
    cvtsd2ss xmm0, xmm0
    cvtsd2ss xmm1, xmm1
    movss   [rbx+0], xmm0
    movss   [rbx+12], xmm1
    cvtss2sd xmm0, xmm7
    movapd  xmm1, xmm0
    subsd   xmm0, xmm10
    addsd   xmm1, xmm10
    cvtsd2ss xmm0, xmm0
    cvtsd2ss xmm1, xmm1
    movss   [rbx+4], xmm0
    movss   [rbx+16], xmm1
    cvtss2sd xmm0, xmm8
    movapd  xmm1, xmm0
    subsd   xmm0, xmm10
    addsd   xmm1, xmm10
    cvtsd2ss xmm0, xmm0
    cvtsd2ss xmm1, xmm1
    movss   [rbx+8], xmm0
    movss   [rbx+20], xmm1
    lea     rcx, [rel fPl]
    lea     rdx, [rel fBox]
    call    frustum_test_aabb
    mov     r14d, eax
    add     [rel vis_count], eax
    mov     r15d, 1
    xor     esi, esi
.pv:
    mov     eax, esi
    shl     eax, 5
    lea     rdi, [rel dP]
    add     rdi, rax
    xorpd   xmm11, xmm11
    xor     ecx, ecx
.pc:
    movsd   xmm0, [rdi+rcx*8]
    cvtss2sd xmm1, [rbx+12+rcx*4]
    ucomisd xmm0, xmm11
    jae     .usemax
    cvtss2sd xmm1, [rbx+rcx*4]
.usemax:
    movsd   LOC(rcx*8), xmm1
    inc     ecx
    cmp     ecx, 3
    jb      .pc
    movsd   xmm0, LOC(0)
    movsd   xmm1, LOC(8)
    movsd   xmm2, LOC(16)
    mov     ecx, esi
    call    plane_dot
    xorpd   xmm1, xmm1
    ucomisd xmm0, xmm1
    jae     .pvn
    xor     r15d, r15d
    jmp     .pvdone
.pvn:
    inc     esi
    cmp     esi, 6
    jb      .pv
.pvdone:
    cmp     r14d, r15d
    je      .aabb_ok
    cvtss2sd xmm0, xmm6
    cvtss2sd xmm1, xmm7
    cvtss2sd xmm2, xmm8
    NOTE    "aabb visibility differs from p-vertex reference at centre"
.aabb_ok:
    ; clip_inside: (x,y,z,w) = VP * (c,1), all of |x|,|y|,|z| <= w
    xor     esi, esi
.ci:
    xorpd   xmm0, xmm0
    lea     rax, [rel fVP]
    lea     rax, [rax+rsi*4]
    cvtss2sd xmm1, [rax]
    cvtss2sd xmm2, xmm6
    mulsd   xmm1, xmm2
    addsd   xmm0, xmm1
    cvtss2sd xmm1, [rax+16]
    cvtss2sd xmm2, xmm7
    mulsd   xmm1, xmm2
    addsd   xmm0, xmm1
    cvtss2sd xmm1, [rax+32]
    cvtss2sd xmm2, xmm8
    ; v1 temporary guard (test_matrix #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_matrix #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_matrix #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_matrix #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_matrix #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_matrix #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_matrix #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_matrix #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_matrix #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_matrix #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_matrix #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_matrix #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_matrix #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_matrix #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_matrix #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_matrix #49)
    xor     r11d, r11d ; clear v1 slot 49
