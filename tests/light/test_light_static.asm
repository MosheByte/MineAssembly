; full generation of all 9 chunks: open field, cave under a roof, and the result must
; not depend on the order the chunks get propagated in
; @link src/light.asm tests/light/fakeworld.asm tests/light/lightlib.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../light/lightlib.inc"  ; via -I tests/lib/

%define SNAP_BYTES (9*32768)

section .text
PROC test_main, 32
    call lt_setup_tables

    TEST "open field fully lit"
    mov  ecx, 64
    call lt_flat_world
    xor  ecx, ecx
    call lt_generate
    mov  ecx, 64
    mov  edx, 128
    mov  r8d, 15
    call lt_all_sky
    CHECK_TRUE eax, "sky 15 everywhere above the ground"
    xor  ecx, ecx
    mov  edx, 64
    xor  r8d, r8d
    call lt_all_sky
    CHECK_TRUE eax, "sky 0 everywhere inside the ground"
    call lt_all_blk_zero
    CHECK_TRUE eax, "no block light"
    mov  ecx, 64
    call lt_all_hm
    CHECK_TRUE eax, "every heightmap is 64"
    xor  ebx, ebx  ; all 9 should end up CS_LIT
.state:
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    lea  ecx, [rdx - 1]
    lea  edx, [rax - 1]
    mov  r8d, LT_OFF_STATE
    call lt_header
    CHECK_EQ32 eax, CS_LIT, "chunk state after propagation"
    inc  ebx
    cmp  ebx, 9
    jb   .state
    CHECK_REF "open field"

    TEST "cave under roof is dark"
    mov  ecx, 64
    call lt_flat_world
    FILL 70, 71, 4, 44, 4, 44, T_STONE  ; roof over all 9 chunks
    xor  ecx, ecx
    call lt_generate
    ; 15+ from every edge -> pitch black
    CHECK_SKY 8, 65, 8, 0, "cave centre y=65"
    CHECK_SKY 8, 69, 8, 0, "cave centre y=69"
    ; roof starts at x = -12
    CHECK_SKY -13, 66, 8, 15, "outside the roof"
    CHECK_SKY -12, 66, 8, 14, "first cell under the roof"
    CHECK_SKY -9, 66, 8, 11, "4th cell under the roof"
    CHECK_REF "cave"

    TEST "propagation order independent"
    mov  ecx, 3
    call t_rng_seed
    mov  ecx, 60
    call lt_flat_world
    mov  ecx, 60
    mov  edx, 75
    mov  r8d, 250
    mov  r9d, T_STONE
    call lt_fill_random
    FILL 75, 76, 10, 40, 10, 40, T_LEAVES
    FILL 60, 61, 20, 30, 20, 30, T_WATER
    mov  ecx, 20
    mov  edx, 61
    mov  r8d, T_TORCH
    call lt_scatter
    FILL 66, 67, 24, 25, 24, 25, T_GLOW
    mov  ecx, SNAP_BYTES
    call t_alloc
    mov  r12, rax
    mov  ecx, SNAP_BYTES
    call t_alloc
    mov  r13, rax
    mov  ecx, SNAP_BYTES
    call t_alloc
    mov  r14, rax
    xor  ecx, ecx
    call lt_generate
    CHECK_REF "order=row"
    mov  rcx, r12
    call lt_snapshot
    mov  ecx, 1
    call lt_generate
    CHECK_REF "order=reverse"
    mov  rcx, r13
    call lt_snapshot
    mov  ecx, 2
    call lt_generate
    CHECK_REF "order=shuffle"
    mov  rcx, r14
    call lt_snapshot
    CHECK_MEM r12, r13, SNAP_BYTES, "reverse order gives the same light"
    CHECK_MEM r12, r14, SNAP_BYTES, "shuffled order gives the same light"
ENDP
