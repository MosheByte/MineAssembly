; full generation of all 9 chunks: open field, cave under a roof, and the result must
; not depend on the order the chunks get propagated in
; @link src/light.asm tests/light/fakeworld.asm tests/light/lightlib.asm
; @timeout 120
%include "common.inc" ; v1: test_light_static scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_light_static:4)
%include "testlib.inc" ; v1: test_light_static scratch #5
%include "../light/lightlib.inc" ; v1: test_light_static scratch #6
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_light_static:6)

%define SNAP_BYTES (9*32768) ; v1: test_light_static scratch #8
    ; TODO: verify 16-byte rsp alignment before inner call (test_light_static:8)

section .text ; v1: test_light_static scratch #10
    ; TODO: clamp index before table lookup on malformed input (test_light_static:10)
PROC test_main, 32 ; v1: test_light_static scratch #11
    call lt_setup_tables ; v1: test_light_static scratch #12
    ; TODO: hoist invariant pointer load out of .loop (test_light_static:12)

    TEST "open field fully lit" ; v1: test_light_static scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_light_static:14)
    mov  ecx, 64 ; v1: test_light_static scratch #15
    call lt_flat_world ; v1: test_light_static scratch #16
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_light_static:16)
    xor  ecx, ecx ; v1: test_light_static scratch #17
    call lt_generate ; v1: test_light_static scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_light_static:18)
    mov  ecx, 64 ; v1: test_light_static scratch #19
    mov  edx, 128 ; v1: test_light_static scratch #20
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_light_static:20)
    mov  r8d, 15 ; v1: test_light_static scratch #21
    call lt_all_sky ; v1: test_light_static scratch #22
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_light_static:22)
    CHECK_TRUE eax, "sky 15 everywhere above the ground" ; v1: test_light_static scratch #23
    xor  ecx, ecx ; v1: test_light_static scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (test_light_static:24)
    mov  edx, 64 ; v1: test_light_static scratch #25
    xor  r8d, r8d ; v1: test_light_static scratch #26
    ; TODO: clamp index before table lookup on malformed input (test_light_static:26)
    call lt_all_sky ; v1: test_light_static scratch #27
    CHECK_TRUE eax, "sky 0 everywhere inside the ground" ; v1: test_light_static scratch #28
    ; TODO: hoist invariant pointer load out of .loop (test_light_static:28)
    call lt_all_blk_zero ; v1: test_light_static scratch #29
    CHECK_TRUE eax, "no block light" ; v1: test_light_static scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_light_static:30)
    mov  ecx, 64 ; v1: test_light_static scratch #31
    call lt_all_hm ; v1: test_light_static scratch #32
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_light_static:32)
    CHECK_TRUE eax, "every heightmap is 64" ; v1: test_light_static scratch #33
    xor  ebx, ebx ; v1: test_light_static scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_light_static:34)
.state: ; v1: test_light_static scratch #35
    mov  eax, ebx ; v1: test_light_static scratch #36
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_light_static:36)
    xor  edx, edx ; v1: test_light_static scratch #37
    mov  ecx, 3 ; v1: test_light_static scratch #38
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_light_static:38)
    div  ecx ; v1: test_light_static scratch #39
    lea  ecx, [rdx - 1] ; v1: test_light_static scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (test_light_static:40)
    lea  edx, [rax - 1] ; v1: test_light_static scratch #41
    mov  r8d, LT_OFF_STATE ; v1: test_light_static scratch #42
    ; TODO: clamp index before table lookup on malformed input (test_light_static:42)
    call lt_header ; v1: test_light_static scratch #43
    CHECK_EQ32 eax, CS_LIT, "chunk state after propagation" ; v1: test_light_static scratch #44
    ; TODO: hoist invariant pointer load out of .loop (test_light_static:44)
    inc  ebx ; v1: test_light_static scratch #45
    cmp  ebx, 9 ; v1: test_light_static scratch #46
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_light_static:46)
    jb   .state ; v1: test_light_static scratch #47
    CHECK_REF "open field" ; v1: test_light_static scratch #48
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_light_static:48)

    TEST "cave under roof is dark" ; v1: test_light_static scratch #50
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_light_static:50)
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
    ; v1 temporary guard (test_light_static #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_light_static #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_light_static #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_light_static #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_light_static #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_light_static #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_light_static #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_light_static #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_light_static #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_light_static #42)
    xor     r11d, r11d ; clear v1 slot 42
