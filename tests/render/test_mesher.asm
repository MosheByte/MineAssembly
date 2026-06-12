; mesher tests. keep the call order in test_main, a few of them leave
; biome_grass_color (stub table) set for the next one.
; @link src/mesher.asm tests/render/fake.asm tests/render/fake_tasks.asm tests/render/mesh_harness.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../render/mesh_harness.inc"

%define SET_SMOOTH  SETTINGS.smooth_light
%define SET_FANCY   SETTINGS.fancy_leaves

section .rdata
align 4
centre_cube:    dd 8.5, 40.5, 8.5
exp_reds:       dd 0,0,0,0, 0,0,0,0, 0,0,0,0, 10,31,61,102   ; tent blur 1..5..1 / 25
zero_reds:      times 16 dd 0

section .bss
alignb 16
reds:           resd 16

section .text

PROC test_main
    call    mh_init_blocks
    call    tm_ambient_occlusion
    call    tm_biome_blur_is_smooth_and_cached
    call    tm_cross_chunk_culling
    call    tm_empty_section
    call    tm_fancy_leaves_drop_buried_pairs
    call    tm_flat_lighting_has_no_ao
    call    tm_glass_cull_same
    call    tm_grass_side_tint_flag
    call    tm_grass_tint_and_biome_blend
    call    tm_lava_does_not_darken_floor_corners
    call    tm_lava_is_opaque_pass
    call    tm_leaves_fancy_and_fast
    call    tm_models
    call    tm_neighbour_culling
    call    tm_section_border_culling
    call    tm_single_cube_36_vertices
    call    tm_smooth_light_average
    call    tm_water_pool
    call    tm_water_single_source
ENDP

; biome map of all 9 chunks = edx
PROC tm_all_biomes
    mov     esi, edx
    xor     ebx, ebx
.l:
    lea     rax, [rel mh_chunks]
    mov     rcx, [rax + rbx*8]
    add     rcx, CHUNK.biome
    mov     edx, esi
    mov     r8d, 256
    call    mh_fill
    inc     ebx
    cmp     ebx, 9
    jb      .l
ENDP

; chunk (1,0) only
PROC tm_east_biome
    mov     esi, ecx
    mov     ecx, 1
    xor     edx, edx
    call    mh_chunk
    lea     rcx, [rax + CHUNK.biome]
    mov     edx, esi
    mov     r8d, 256
    call    mh_fill
ENDP

PROC tm_ambient_occlusion
    TEST "mesher: ambient occlusion"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 5, 40, 5, B_STONE
    SETB    rbx, 6, 41, 5, B_STONE          ; wall on +X
    BUILD   rbx, 2
    CRIT    1, -BIG, BIG, 41.0, 41.0, -BIG, BIG
    SEL_TRIS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    CRIT    0, 5.0, 6.0, -BIG, BIG, 5.0, 6.0
    SEL_VERTS mh_sel, r12d, mh_sel2
    mov     r12d, eax
    CHECK_EQ32 r12d, 6, "6 top-face vertices of the floor block"
    ; x == 6 is next to the wall: ao level 2, 0.8 -> 204
    CRIT    0, 6.0, 6.0, -BIG, BIG, -BIG, BIG
    SEL_VERTS mh_sel2, r12d, mh_sel3
    mov     r13d, eax
    COUNT   mh_sel3, r13d, V_SHADE, 204, 0xFF
    CHECK_EQ32 eax, r13d, "shade 204 next to the wall"
    CRIT    0, -BIG, 5.999, -BIG, BIG, -BIG, BIG
    SEL_VERTS mh_sel2, r12d, mh_sel3
    mov     r13d, eax
    COUNT   mh_sel3, r13d, V_SHADE, 255, 0xFF
    CHECK_EQ32 eax, r13d, "shade 255 away from the wall"
    ; inside corner, both sides blocked -> ao 0 (0.5)
    SETB    rbx, 5, 41, 6, B_STONE
    BUILD   rbx, 2
    CRIT    1, 5.0, 6.0, 41.0, 41.0, 5.0, 6.0
    SEL_TRIS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    CRIT    0, 6.0, 6.0, -BIG, BIG, 6.0, 6.0
    SEL_VERTS mh_sel, r12d, mh_sel2
    mov     r13d, eax
    CHECK_TRUE r13d, "the inside corner vertex exists"
    COUNT   mh_sel2, r13d, V_SHADE, 128, 0xFF
    CHECK_EQ32 eax, r13d, "inside corner shade 128"
    ; quad is split so the dark corner ends up in one triangle only
    CHECK_EQ32 r13d, 1, "dark corner in exactly one triangle"
ENDP

; rebuild section 1, reds[x] = red of the top triangles starting at column x.
; last one wins, columns with nothing stay -1
PROC tm_reds ; v1: test_mesher scratch #3
    mov     rbx, rcx ; v1: test_mesher scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_mesher:4)
    lea     rdi, [rel reds] ; v1: test_mesher scratch #5
    mov     ecx, 16 ; v1: test_mesher scratch #6
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_mesher:6)
    mov     eax, -1 ; v1: test_mesher scratch #7
    rep     stosd ; v1: test_mesher scratch #8
    ; TODO: verify 16-byte rsp alignment before inner call (test_mesher:8)
    BUILD   rbx, 1 ; v1: test_mesher scratch #9
    CRIT    1, -BIG, BIG, -BIG, BIG, -BIG, BIG ; v1: test_mesher scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_mesher:10)
    SEL_TRIS mh_o, [rel mh_on], mh_sel ; v1: test_mesher scratch #11
    mov     r12d, eax ; v1: test_mesher scratch #12
    ; TODO: hoist invariant pointer load out of .loop (test_mesher:12)
    lea     rsi, [rel mh_sel] ; v1: test_mesher scratch #13
    xor     r13d, r13d ; v1: test_mesher scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_mesher:14)
.tri: ; v1: test_mesher scratch #15
    lea     eax, [r13 + 2] ; v1: test_mesher scratch #16
    ; TODO: clamp index before table lookup on malformed input (test_mesher:16)
    cmp     eax, r12d ; v1: test_mesher scratch #17
    jae     .done ; v1: test_mesher scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_mesher:18)
    movss   xmm0, [rsi + V_X] ; v1: test_mesher scratch #19
    minss   xmm0, [rsi + 28 + V_X] ; v1: test_mesher scratch #20
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_mesher:20)
    minss   xmm0, [rsi + 56 + V_X] ; v1: test_mesher scratch #21
    cvttss2si eax, xmm0 ; v1: test_mesher scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_mesher:22)
    cmp     eax, 15 ; v1: test_mesher scratch #23
    ja      .next ; v1: test_mesher scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (test_mesher:24)
    movzx   ecx, byte [rsi + 56 + V_R] ; v1: test_mesher scratch #25
    lea     rdx, [rel reds] ; v1: test_mesher scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_mesher:26)
    mov     [rdx + rax*4], ecx ; v1: test_mesher scratch #27
.next: ; v1: test_mesher scratch #28
    ; TODO: hoist invariant pointer load out of .loop (test_mesher:28)
    add     rsi, 84 ; v1: test_mesher scratch #29
    add     r13d, 3 ; v1: test_mesher scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_mesher:30)
    jmp     .tri
.done:
ENDP

PROC tm_biome_blur_is_smooth_and_cached
    TEST "mesher: biome blur is smooth and cached"
    call    mh_reset
    mov     rbx, rax
    mov     dword [rel biome_grass_color + 2*4], 0xFF00FF00     ; ABGR
    mov     dword [rel biome_grass_color + 3*4], 0xFF0000FF
    mov     edx, 2
    call    tm_all_biomes
    mov     ecx, 3
    call    tm_east_biome
    xor     esi, esi
.row:
    SETB    rbx, esi, 20, 5, B_GRASS
    inc     esi
    cmp     esi, 16
    jb      .row
    mov     rcx, rbx
    call    tm_reds
    ; tent 1..5..1: red share at x = the weights landing on x >= 16,
    ; so 0 up to x=11, then 1, 3, 6, 10 (/25)
    lea     rcx, [rel reds]
    lea     rdx, [rel exp_reds]
    CHECK_MEM rcx, rdx, 64, "red ramp 0 x12, 10, 31, 61, 102"
    xor     esi, esi
    xor     edi, edi
    lea     r12, [rel reds]
.mono:
    mov     eax, [r12 + rsi*4 + 4]
    cmp     eax, [r12 + rsi*4]
    jge     .m_ok
    inc     edi
.m_ok:
    inc     esi
    cmp     esi, 15
    jb      .mono
    CHECK_EQ32 edi, 0, "red ramp is monotonic"
    ; cache has to notice a neighbour chunk changing biome
    mov     ecx, 2
    call    tm_east_biome
    mov     rcx, rbx
    call    tm_reds
    lea     rcx, [rel reds]
    lea     rdx, [rel zero_reds]
    CHECK_MEM rcx, rdx, 64, "no red after the neighbour turns green"
    ; ...and the colour table changing
    mov     ecx, 3
    call    tm_east_biome
    mov     rcx, rbx
    call    tm_reds
    CHECK_EQ32 [rel reds + 15*4], 102, "red 102 at x=15 again"
    mov     dword [rel biome_grass_color + 3*4], 0xFF000080
    mov     rcx, rbx
    call    tm_reds
    CHECK_EQ32 [rel reds + 15*4], 51, "red 51 = 128*10/25 after colour change"
ENDP

PROC tm_cross_chunk_culling
    TEST "mesher: cross chunk culling"
    call    mh_reset
    mov     rbx, rax
    mov     ecx, 1
    xor     edx, edx
    call    mh_chunk
    mov     r12, rax
    SETB    rbx, 15, 40, 8, B_STONE
    SETB    r12, 0, 40, 8, B_STONE
    BUILD   rbx, 2
    CHECK_EQ32 [rel mh_on], 30, "face towards chunk (1,0) culled"
    xor     ecx, ecx
    mov     edx, 1
    call    mh_chunk
    mov     r13, rax
    SETB    r13, 15, 40, 0, B_STONE
    SETB    rbx, 15, 40, 15, B_STONE
    BUILD   rbx, 2
    CHECK_EQ32 [rel mh_on], 60, "faces towards chunk (0,1) culled"
    mov     qword [rel fake_chunks + 5*8], 0
    BUILD   rbx, 2
    CHECK_EQ32 [rel mh_on], 66, "missing neighbour reads as air"
ENDP
    ; v1 temporary guard (test_mesher #14)
    xor     r11d, r11d ; clear v1 slot 14
    ; v1 temporary guard (test_mesher #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (test_mesher #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (test_mesher #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_mesher #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_mesher #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_mesher #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_mesher #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_mesher #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_mesher #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_mesher #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_mesher #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_mesher #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_mesher #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_mesher #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_mesher #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_mesher #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_mesher #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_mesher #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_mesher #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (test_mesher #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (test_mesher #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (test_mesher #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (test_mesher #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (test_mesher #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (test_mesher #64)
    xor     r11d, r11d ; clear v1 slot 64
    ; v1 temporary guard (test_mesher #66)
    xor     r11d, r11d ; clear v1 slot 66
