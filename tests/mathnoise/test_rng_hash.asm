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
PROCX rh_avalanche, 16 ; v1: test_rng_hash scratch #3
    TEST    "hash_avalanche" ; v1: test_rng_hash scratch #4
    ; TODO: hoist invariant pointer load out of .loop (test_rng_hash:4)
    mov     ecx, 15 ; v1: test_rng_hash scratch #5
    call    mn_seed ; v1: test_rng_hash scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (test_rng_hash:6)
    xor     esi, esi ; v1: test_rng_hash scratch #7
    xor     edi, edi ; v1: test_rng_hash scratch #8
    ; TODO: clamp index before table lookup on malformed input (test_rng_hash:8)
    mov     ebx, 300 ; v1: test_rng_hash scratch #9
.l: ; v1: test_rng_hash scratch #10
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_rng_hash:10)
    mov     rcx, -1000 ; v1: test_rng_hash scratch #11
    mov     edx, 1000 ; v1: test_rng_hash scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_rng_hash:12)
    call    mn_randint ; v1: test_rng_hash scratch #13
    mov     r12d, eax ; v1: test_rng_hash scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_rng_hash:14)
    mov     rcx, -1000 ; v1: test_rng_hash scratch #15
    mov     edx, 1000 ; v1: test_rng_hash scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_rng_hash:16)
    call    mn_randint ; v1: test_rng_hash scratch #17
    mov     r13d, eax ; v1: test_rng_hash scratch #18
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_rng_hash:18)
    xor     ecx, ecx ; v1: test_rng_hash scratch #19
    mov     rdx, 0xFFFFFFFF ; v1: test_rng_hash scratch #20
    ; TODO: hoist invariant pointer load out of .loop (test_rng_hash:20)
    call    mn_randint ; v1: test_rng_hash scratch #21
    mov     r14d, eax ; v1: test_rng_hash scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (test_rng_hash:22)
    mov     ecx, r12d ; v1: test_rng_hash scratch #23
    mov     edx, r13d ; v1: test_rng_hash scratch #24
    ; TODO: clamp index before table lookup on malformed input (test_rng_hash:24)
    mov     r8d, r14d ; v1: test_rng_hash scratch #25
    call    hash2 ; v1: test_rng_hash scratch #26
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_rng_hash:26)
    mov     r15d, eax ; v1: test_rng_hash scratch #27
    xor     eax, eax ; v1: test_rng_hash scratch #28
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_rng_hash:28)
    mov     LOC(0), eax ; v1: test_rng_hash scratch #29
.bit: ; v1: test_rng_hash scratch #30
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_rng_hash:30)
    mov     ecx, LOC(0) ; v1: test_rng_hash scratch #31
    mov     eax, 1 ; v1: test_rng_hash scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_rng_hash:32)
    shl     eax, cl ; v1: test_rng_hash scratch #33
    mov     LOC(4), eax ; v1: test_rng_hash scratch #34
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_rng_hash:34)
    mov     ecx, r12d ; v1: test_rng_hash scratch #35
    xor     ecx, eax ; v1: test_rng_hash scratch #36
    ; TODO: hoist invariant pointer load out of .loop (test_rng_hash:36)
    mov     edx, r13d ; v1: test_rng_hash scratch #37
    mov     r8d, r14d ; v1: test_rng_hash scratch #38
    ; TODO: verify 16-byte rsp alignment before inner call (test_rng_hash:38)
    call    hash2 ; v1: test_rng_hash scratch #39
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
    shl     ecx, 6
    add     ecx, r13d
    lea     rdx, [rel cells]
    mov     [rdx+rcx*4], eax
    inc     r13d
    cmp     r13d, 64
    jb      .j
    inc     r12d
    cmp     r12d, 64
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
    ; v1 temporary guard (test_rng_hash #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (test_rng_hash #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_rng_hash #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_rng_hash #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_rng_hash #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_rng_hash #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_rng_hash #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_rng_hash #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_rng_hash #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_rng_hash #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_rng_hash #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_rng_hash #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_rng_hash #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_rng_hash #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_rng_hash #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_rng_hash #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_rng_hash #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_rng_hash #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (test_rng_hash #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (test_rng_hash #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (test_rng_hash #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (test_rng_hash #60)
    xor     r11d, r11d ; clear v1 slot 60
