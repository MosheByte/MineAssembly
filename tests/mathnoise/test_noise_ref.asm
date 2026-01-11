; test_noise_ref.asm - noise2/noise3 vs the double model in mn_refnoise.asm. seeds 0,
; 1, 1234567, 0xDEADBEEFCAFEBABE, 4000 points each in [-300,300]^3, |err| < 2e-5.
; @link src/math.asm src/noise.asm tests/mathnoise/mn_helpers.asm tests/mathnoise/mn_refnoise.asm
; @timeout 120
%include "common.inc"
%include "../mathnoise/mn_test.inc"



section .rdata
align 8
ref_seeds:  dq 0, 1, 1234567, 0xDEADBEEFCAFEBABE



section .bss
alignb 8
worst2:     resq 1
worst3:     resq 1



section .text


; xmm6-8 = x, y, z floats; xmm9 = noise2 error, xmm10 = noise3 error
PROCX test_main
    TEST    "matches_reference_implementation"
    call    mn_bad_reset
    mov     ecx, 21
    call    mn_seed
    xor     r12d, r12d
.seed:
    lea     rax, [rel ref_seeds]
    mov     rbx, [rax+r12*8]
    mov     rcx, rbx
    call    noise_set_seed
    mov     rcx, rbx
    call    refn_init
    mov     r13d, 4000
.pt:
    FCONST  xmm0, -300.0
    FCONST  xmm1, 300.0
    call    mn_uniform
    movss   xmm6, xmm0
    FCONST  xmm0, -300.0
    FCONST  xmm1, 300.0
    call    mn_uniform
    movss   xmm7, xmm0
    FCONST  xmm0, -300.0
    FCONST  xmm1, 300.0
    call    mn_uniform
    movss   xmm8, xmm0
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    call    noise2
    cvtss2sd xmm9, xmm0
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    call    refn_noise2
    subsd   xmm9, xmm0
    ABSD    xmm9
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    movss   xmm2, xmm8
    call    noise3
    cvtss2sd xmm10, xmm0
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    movss   xmm2, xmm8
    call    refn_noise3
    subsd   xmm10, xmm0
    ABSD    xmm10
    movsd   xmm0, [rel worst2]
    maxsd   xmm0, xmm9
    movsd   [rel worst2], xmm0
    movsd   xmm0, [rel worst3]
    maxsd   xmm0, xmm10
    movsd   [rel worst3], xmm0
    JNLT    xmm9, 2e-5, .bad
    JNLT    xmm10, 2e-5, .bad
    jmp     .next
.bad:
    cvtss2sd xmm0, xmm6
    movapd  xmm1, xmm9
    movapd  xmm2, xmm10
    NOTE    "noise x, err2, err3"
.next:
    dec     r13d
    jnz     .pt
    inc     r12d
    cmp     r12d, 4
    jb      .seed
    CHECK_BAD "|noise2/noise3 - reference model| < 2e-5 for 4 seeds x 4000 points"
    PRINTMAX "max |asm - reference| noise2", [rel worst2]
    PRINTMAX "max |asm - reference| noise3", [rel worst3]
ENDPX
