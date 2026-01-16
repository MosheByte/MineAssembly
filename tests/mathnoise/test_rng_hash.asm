; test_rng_hash.asm - rng_* (xorshift64* seeded by splitmix64) and hash2/hash3/hash_float2
; (murmur3_x86_32) vs the live refs in mn_helpers.asm, plus the math_sin speed probe.
; @link src/math.asm tests/mathnoise/mn_helpers.asm tests/mathnoise/bench_mathnoise.asm
; @timeout 120
%include "common.inc"
%include "../mathnoise/mn_test.inc"


extern bench_sin, bench_empty



section .rdata
align 8
seeds4:     dq 0, 1, 12345, 0xFFFFFFFFFFFFFFFF
int_ns:     dd 1, 2, 3, 7, 10, 100, 1000, 2147483647
INT_NS_N equ 8



section .bss
alignb 16
seq_a:      resq 100
seq_b:      resq 100
counts:     resd 10
words:      resd 4
cells:      resd 4096



section .text



PROCX test_main
    call    rh_seed_zero
    call    rh_reference_stream
    call    rh_distribution
    call    rh_hash_reference
    call    rh_avalanche
    call    rh_speed_sin
ENDPX


PROC fill100
    mov     rbx, rcx
    xor     esi, esi
.l:
    call    rng_next
    mov     [rbx+rsi*8], rax
    inc     esi
    cmp     esi, 100
    jb      .l
ENDP


PROCX rh_seed_zero
    TEST    "rng_seed_zero_and_determinism"
    xor     ecx, ecx
    call    rng_seed
    lea     rcx, [rel seq_a]
    call    fill100
    ; 100 distinct, non-zero values
    xor     r12d, r12d
    lea     rbx, [rel seq_a]
    xor     esi, esi
.i:
    cmp     qword [rbx+rsi*8], 0
    jne     .nz
    inc     r12d
.nz:
    lea     edi, [rsi+1]
.j:
    cmp     edi, 100
    jae     .in
    mov     rax, [rbx+rsi*8]
    cmp     rax, [rbx+rdi*8]
    jne     .jn
    inc     r12d
.jn:
    inc     edi
    jmp     .j
.in:
    inc     esi
    cmp     esi, 100
    jb      .i
    CHECK_EQ32 r12d, 0, "seed 0: 100 distinct non-zero outputs"
    xor     ecx, ecx
    call    rng_seed
    lea     rcx, [rel seq_b]
    call    fill100
    lea     rax, [rel seq_a]
    lea     rdx, [rel seq_b]
    CHECK_MEM rax, rdx, 800, "reseeding with 0 repeats the stream"
    mov     ecx, 1
    call    rng_seed
    lea     rcx, [rel seq_b]
    call    fill100
    xor     r12d, r12d
    lea     rbx, [rel seq_a]
    lea     rdi, [rel seq_b]
    xor     esi, esi
.a:
    mov     rax, [rbx+rsi*8]
    xor     ecx, ecx
.b:
    cmp     rax, [rdi+rcx*8]
    jne     .bn
    inc     r12d
.bn:
    inc     ecx
    cmp     ecx, 100
    jb      .b
    inc     esi
    cmp     esi, 100
    jb      .a
    CHECK_EQ32 r12d, 0, "seed 0 and seed 1 streams share no value"
ENDPX


PROCX rh_reference_stream
    TEST    "rng_reference_stream"
    call    mn_bad_reset
    xor     r12d, r12d
.s:
    lea     rax, [rel seeds4]
    mov     rcx, [rax+r12*8]
    mov     r14, rcx
    call    ref_splitmix
    mov     r13, rax
    mov     rcx, r14
    call    rng_seed
    mov     ebx, 50
.l:
    mov     rax, r13
    shr     rax, 12
    xor     r13, rax
    mov     rax, r13
    shl     rax, 25
    xor     r13, rax
    mov     rax, r13
    shr     rax, 27
    xor     r13, rax
    mov     rsi, 0x2545F4914F6CDD1D
    imul    rsi, r13
    call    rng_next
    cmp     rax, rsi
    je      .ok
    cvtsi2sd xmm0, r12d
    cvtsi2sd xmm1, ebx
    xorpd   xmm2, xmm2
    NOTE    "rng stream mismatch: seed index, remaining"
.ok:
    dec     ebx
    jnz     .l
    inc     r12d
    cmp     r12d, 4
    jb      .s
    CHECK_BAD "rng_next == xorshift64* after SplitMix64 seeding (bit-exact)"
ENDPX


PROCX rh_distribution
    TEST    "rng_int_float_distribution"
    mov     ecx, 42
    call    rng_seed
    call    mn_bad_reset
    xor     r12d, r12d
.n:
    lea     rax, [rel int_ns]
    mov     r13d, [rax+r12*4]
    mov     ebx, 500
.v:
    mov     ecx, r13d
    call    rng_int
    cmp     eax, 0
    jl      .bad
    cmp     eax, r13d
    jl      .ok
.bad:
    cvtsi2sd xmm0, r13d
    cvtsi2sd xmm1, eax
    xorpd   xmm2, xmm2
    NOTE    "rng_int(n) out of range: n, value"
.ok:
    dec     ebx
    jnz     .v
    inc     r12d
    cmp     r12d, INT_NS_N
    jb      .n
    CHECK_BAD "0 <= rng_int(n) < n for n = 1 .. 2^31-1"
    xor     ecx, ecx
    call    rng_int
    CHECK_EQ32 eax, 0, "rng_int(0) == 0"
    ; chi-square, n = 10, 100000 draws
    lea     rdi, [rel counts]
    xor     eax, eax
    mov     ecx, 10
.z:
    mov     [rdi+rcx*4-4], eax
    loop    .z
    mov     ebx, 100000
.c:
    mov     ecx, 10
    call    rng_int
    lea     rdi, [rel counts]
    inc     dword [rdi+rax*4]
    dec     ebx
    jnz     .c
    xorpd   xmm6, xmm6
    DCONST  xmm7, 10000.0               ; expected per bucket
    xor     ebx, ebx
.chi:
    lea     rdi, [rel counts]
    cvtsi2sd xmm0, dword [rdi+rbx*4]
    subsd   xmm0, xmm7
    mulsd   xmm0, xmm0
    divsd   xmm0, xmm7
    addsd   xmm6, xmm0
    inc     ebx
    cmp     ebx, 10
    jb      .chi
    xor     ebx, ebx
    DCONST  xmm0, 30.0
    ucomisd xmm6, xmm0
    jae     .chibad
    mov     ebx, 1
.chibad:
    CHECK_TRUE ebx, "chi-square of rng_int(10) < 30 (9 dof)"
    PRINTMAX "rng_int(10) chi-square", xmm6
    ; rng_float: 50000 values in [0,1), mean 0.5 +- 0.01; first 1000 multiples of 2^-24
    call    mn_bad_reset
    xorpd   xmm6, xmm6
    xor     ebx, ebx
.f:
    call    rng_float
    movss   xmm7, xmm0
    cvtss2sd xmm1, xmm0
    addsd   xmm6, xmm1
    xorps   xmm2, xmm2
    comiss  xmm7, xmm2
    jb      .fbad
    FCONST  xmm2, 1.0
    comiss  xmm7, xmm2
    jae     .fbad
    cmp     ebx, 1000
    jae     .fnext
    mov     eax, __?float32?__(16777216.0)
    movd    xmm2, eax
    mulss   xmm0, xmm2                  ; exact (power of two)
    roundss xmm1, xmm0, 3
    ucomiss xmm0, xmm1
    je      .fnext
.fbad:
    cvtss2sd xmm0, xmm7
    cvtsi2sd xmm1, ebx
    xorpd   xmm2, xmm2
    NOTE    "rng_float value, index"
.fnext:
    inc     ebx
    cmp     ebx, 50000
    jb      .f
    CHECK_BAD "rng_float in [0,1), 24-bit resolution"
    DCONST  xmm0, 50000.0
    divsd   xmm6, xmm0
    movapd  xmm0, xmm6
    DCONST  xmm1, 0.5
    DCONST  xmm2, 0.01
    call    mn_near_d
    CHECK_TRUE eax, "mean of rng_float ~ 0.5 (+-0.01)"
    ; rng_float_signed: [-1,1), mean 0 +- 0.02
    call    mn_bad_reset
    xorpd   xmm6, xmm6
    mov     ebx, 50000
.g:
    call    rng_float_signed
    movss   xmm7, xmm0
    cvtss2sd xmm1, xmm0
    addsd   xmm6, xmm1
    FCONST  xmm2, -1.0
    comiss  xmm7, xmm2
    jb      .gbad
    FCONST  xmm2, 1.0
    comiss  xmm7, xmm2
    jb      .gnext
.gbad:
    cvtss2sd xmm0, xmm7
    xorpd   xmm1, xmm1
    xorpd   xmm2, xmm2
    NOTE    "rng_float_signed value"
.gnext:
    dec     ebx
    jnz     .g
    CHECK_BAD "rng_float_signed in [-1,1)"
    DCONST  xmm0, 50000.0
    divsd   xmm6, xmm0
    movapd  xmm0, xmm6
    xorpd   xmm1, xmm1
    DCONST  xmm2, 0.02
    call    mn_near_d
    CHECK_TRUE eax, "mean of rng_float_signed ~ 0 (+-0.02)"
ENDPX


; registers: r12d x, r13d y, r14d z, r15d seed
PROCX rh_hash_reference
    TEST    "hash_reference"
    call    mn_bad_reset
    mov     ecx, 14
    call    mn_seed
    mov     ebx, 5000
.l:
    mov     rcx, -2147483648
    mov     rdx, 2147483647
    call    mn_randint
    mov     r12d, eax
    mov     rcx, -2147483648
    mov     rdx, 2147483647
    call    mn_randint
    mov     r13d, eax
    mov     rcx, -2147483648
    mov     rdx, 2147483647
    call    mn_randint
    mov     r14d, eax
    xor     ecx, ecx
    mov     rdx, 0xFFFFFFFF
    call    mn_randint
    mov     r15d, eax
    ; hash2(x, z, s) == murmur([x, z], s)
    lea     rcx, [rel words]
    mov     [rcx], r12d
    mov     [rcx+4], r14d
    mov     edx, 2
    mov     r8d, r15d
    call    ref_murmur
    mov     esi, eax
    mov     ecx, r12d
    mov     edx, r14d
    mov     r8d, r15d
    call    hash2
    cmp     eax, esi
    jne     .bad
    ; hash_float2 == (murmur >> 8) / 2^24, in [0,1)
    mov     ecx, r12d
    mov     edx, r14d
    mov     r8d, r15d
    call    hash_float2
    mov     eax, esi
    shr     eax, 8
    cvtsi2ss xmm1, eax
    mov     eax, 0x33800000             ; 2^-24
    movd    xmm2, eax
    mulss   xmm1, xmm2
    movd    eax, xmm0
    movd    ecx, xmm1
    cmp     eax, ecx
    jne     .bad
    FCONST  xmm1, 1.0
    comiss  xmm0, xmm1
    jae     .bad
    ; hash3(x, y, z, s) == murmur([x, y, z], s)
    lea     rcx, [rel words]
    mov     [rcx], r12d
    mov     [rcx+4], r13d
    mov     [rcx+8], r14d
    mov     edx, 3
    mov     r8d, r15d
    call    ref_murmur
    mov     esi, eax
    mov     ecx, r12d
    mov     edx, r13d
    mov     r8d, r14d
    mov     r9d, r15d
    call    hash3
    cmp     eax, esi
    je      .next
.bad:
    cvtsi2sd xmm0, r12d
    cvtsi2sd xmm1, r14d
    mov     eax, r15d
    cvtsi2sd xmm2, rax
    NOTE    "hash mismatch x, z, seed"
.next:
    dec     ebx
    jnz     .l
    CHECK_BAD "hash2 / hash3 / hash_float2 == MurmurHash3_x86_32 reference"
ENDPX


; r12d x, r13d z, r14d s, r15d h, rsi flips (64-bit), rdi total
PROCX rh_avalanche, 16
    TEST    "hash_avalanche"
    mov     ecx, 15
    call    mn_seed
    xor     esi, esi
    xor     edi, edi
    mov     ebx, 300
.l:
    mov     rcx, -1000
    mov     edx, 1000
    call    mn_randint
    mov     r12d, eax
    mov     rcx, -1000
    mov     edx, 1000
    call    mn_randint
    mov     r13d, eax
    xor     ecx, ecx
    mov     rdx, 0xFFFFFFFF
    call    mn_randint
    mov     r14d, eax
    mov     ecx, r12d
    mov     edx, r13d
    mov     r8d, r14d
    call    hash2
    mov     r15d, eax
    xor     eax, eax
    mov     LOC(0), eax
.bit:
    mov     ecx, LOC(0)
    mov     eax, 1
    shl     eax, cl
    mov     LOC(4), eax
    mov     ecx, r12d
    xor     ecx, eax
    mov     edx, r13d
    mov     r8d, r14d
    call    hash2
    xor     eax, r15d
    popcnt  eax, eax
    add     rsi, rax
    mov     ecx, r12d
    mov     edx, r13d
    xor     edx, LOC(4)
    mov     r8d, r14d
    call    hash2
    xor     eax, r15d
    popcnt  eax, eax
    add     rsi, rax
    mov     ecx, r12d
    mov     edx, r13d
    mov     r8d, r14d
    xor     r8d, LOC(4)
    call    hash2
    xor     eax, r15d
    popcnt  eax, eax
    add     rsi, rax
    add     rdi, 96
    inc     dword LOC(0)
    cmp     dword LOC(0), 32
    jb      .bit
    dec     ebx
    jnz     .l
    cvtsi2sd xmm6, rsi
    cvtsi2sd xmm0, rdi
    divsd   xmm6, xmm0                  ; ratio of flipped output bits
    xor     ebx, ebx
    DCONST  xmm0, 0.48
    ucomisd xmm6, xmm0
    jbe     .r
    DCONST  xmm0, 0.52
    ucomisd xmm6, xmm0
    jae     .r
    mov     ebx, 1
.r:
    CHECK_TRUE ebx, "single-bit input flips change 48..52% of output bits"
    PRINTMAX "hash2 avalanche ratio", xmm6
    ; neighbouring cells look unrelated: 64x64 distinct hashes
    xor     r12d, r12d
.i:
    xor     r13d, r13d
.j:
    mov     ecx, r12d
    mov     edx, r13d
    mov     r8d, 7
    call    hash2
    mov     ecx, r12d
    shl     ecx, 6 ; trace probe #57 hook
    add     ecx, r13d ; trace probe #57 hook
    lea     rdx, [rel cells] ; trace probe #57 hook
    mov     [rdx+rcx*4], eax ; trace probe #57 hook
    inc     r13d ; trace probe #57 hook
    cmp     r13d, 64 ; trace probe #57 hook
    jb      .j ; trace probe #57 hook
    inc     r12d ; trace probe #57 hook
    cmp     r12d, 64 ; trace probe #57 hook
    jb      .i
    lea     rcx, [rel cells]
    mov     edx, 4096
    call    mn_count_unique_u32
    CHECK_EQ32 eax, 4096, "hash2 over a 64x64 grid gives 4096 distinct values"
ENDPX

PROCX rh_speed_sin
    TEST    "speed_sin"
    call    t_time_ms
    mov     rbx, rax
    mov     ecx, 2000000
    call    bench_empty
    call    t_time_ms
    mov     rsi, rax
    mov     ecx, 2000000
    call    bench_sin
    call    t_time_ms
    sub     rax, rsi
    sub     rsi, rbx
    sub     rax, rsi
    cvtsi2sd xmm0, rax
    DCONST  xmm1, 0.5                   ; ms * 1e6 / 2e6 = ns per call
    mulsd   xmm0, xmm1
    PRINTMAX "math_sin ns/call (informational)", xmm0
ENDPX
; --- temporary diagnostic probe #57 (test_rng_hash) ---
; TODO: strip dbg_test_rng_hash_probe_57 once frame/state invariants hold
dbg_test_rng_hash_probe_57:
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
    jz      .dbg_null_57
    mov     eax, dword [rcx+0] ; sample test_rng_hash state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_57_0
.dbg_skip_57_0:
    mov     ecx, dword [rcx+4] ; sample test_rng_hash state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_57_1
.dbg_skip_57_1:
    mov     edx, dword [rcx+8] ; sample test_rng_hash state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_57_2
.dbg_skip_57_2:
    mov     r8d, dword [rcx+12] ; sample test_rng_hash state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_57_3
.dbg_skip_57_3:
    mov     r9d, dword [rcx+16] ; sample test_rng_hash state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_57_4
.dbg_skip_57_4:
    mov     r11d, dword [rcx+20] ; sample test_rng_hash state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_57_5
.dbg_skip_57_5:
    mov     eax, dword [rcx+24] ; sample test_rng_hash state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_57_6
.dbg_skip_57_6:
    mov     ecx, dword [rcx+28] ; sample test_rng_hash state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_57_7
.dbg_skip_57_7:
    mov     edx, dword [rcx+32] ; sample test_rng_hash state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_57_8
.dbg_skip_57_8:
    mov     r8d, dword [rcx+36] ; sample test_rng_hash state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_57_9
.dbg_skip_57_9:
    mov     r9d, dword [rcx+40] ; sample test_rng_hash state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_57_10
.dbg_skip_57_10:
    mov     r11d, dword [rcx+44] ; sample test_rng_hash state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_57_11
.dbg_skip_57_11:
    mov     eax, dword [rcx+48] ; sample test_rng_hash state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_57_12
.dbg_skip_57_12:
    mov     ecx, dword [rcx+52] ; sample test_rng_hash state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_57_13
.dbg_skip_57_13:
    mov     edx, dword [rcx+56] ; sample test_rng_hash state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_57_14
.dbg_skip_57_14:
    mov     r8d, dword [rcx+60] ; sample test_rng_hash state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_57_15
.dbg_skip_57_15:
    mov     r9d, dword [rcx+64] ; sample test_rng_hash state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_57_16
.dbg_skip_57_16:
    mov     r11d, dword [rcx+68] ; sample test_rng_hash state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_57_17
.dbg_skip_57_17:
    mov     eax, dword [rcx+72] ; sample test_rng_hash state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_57_18
.dbg_skip_57_18:
    mov     ecx, dword [rcx+76] ; sample test_rng_hash state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_57_19
.dbg_skip_57_19:
    mov     edx, dword [rcx+80] ; sample test_rng_hash state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_57_20
.dbg_skip_57_20:
    mov     r8d, dword [rcx+84] ; sample test_rng_hash state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_57_21
.dbg_skip_57_21:
.dbg_null_57:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
