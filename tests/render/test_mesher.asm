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
PROC tm_reds
    mov     rbx, rcx
    lea     rdi, [rel reds]
    mov     ecx, 16
    mov     eax, -1
    rep     stosd
    BUILD   rbx, 1
    CRIT    1, -BIG, BIG, -BIG, BIG, -BIG, BIG
    SEL_TRIS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    lea     rsi, [rel mh_sel]
    xor     r13d, r13d
.tri:
    lea     eax, [r13 + 2]
    cmp     eax, r12d
    jae     .done
    movss   xmm0, [rsi + V_X]
    minss   xmm0, [rsi + 28 + V_X]
    minss   xmm0, [rsi + 56 + V_X]
    cvttss2si eax, xmm0
    cmp     eax, 15
    ja      .next
    movzx   ecx, byte [rsi + 56 + V_R]
    lea     rdx, [rel reds]
    mov     [rdx + rax*4], ecx
.next:
    add     rsi, 84
    add     r13d, 3
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

PROC tm_empty_section
    TEST "mesher: empty section"
    call    mh_reset
    mov     rbx, rax
    mov     r12d, [rel g_stat_meshes_built]
    BUILD   rbx, 3
    CHECK_EQ32 [rel mh_on], 0, "no opaque vertices"
    CHECK_EQ32 [rel mh_tn], 0, "no translucent vertices"
    movzx   eax, byte [rbx + CHUNK.sec_flags + 3]
    CHECK_EQ32 eax, 0, "sec_flags[3] == 0"
    CHECK_EQ32 [rbx + CHUNK.dirty], 0xFF & ~(1 << 3), "dirty bit 3 cleared"
    lea     r13d, [r12 + 1]
    CHECK_EQ32 [rel g_stat_meshes_built], r13d, "g_stat_meshes_built + 1"
ENDP

PROC tm_fancy_leaves_drop_buried_pairs
    TEST "mesher: fancy leaves drop buried pairs"
    call    mh_reset
    mov     rbx, rax
    ; a 4x4x4 leaf cube: 96 outer faces + 144 inner pairs (288 faces); the
    ; 12 pairs inside the 2x2x2 core join two fully enclosed leaves
    mov     esi, 4
.x1:
    mov     edi, 20
.y1:
    mov     r12d, 4
.z1:
    SETB    rbx, esi, edi, r12d, B_LEAVES
    inc     r12d
    cmp     r12d, 8
    jb      .z1
    inc     edi
    cmp     edi, 24
    jb      .y1
    inc     esi
    cmp     esi, 8
    jb      .x1
    BUILD   rbx, 1
    CHECK_EQ32 [rel mh_on], (96 + 288 - 24) * 6, "buried core pairs dropped"
    ; same cube moved up to the section top (y 28..31)
    mov     esi, 4
.x2:
    mov     edi, 20
.y2:
    mov     r12d, 4
.z2:
    SETB    rbx, esi, edi, r12d, 0
    lea     r13d, [rdi + 8]
    SETB    rbx, esi, r13d, r12d, B_LEAVES
    inc     r12d
    cmp     r12d, 8
    jb      .z2
    inc     edi
    cmp     edi, 24
    jb      .y2
    inc     esi
    cmp     esi, 8
    jb      .x2
    mov     esi, 4
.x3:
    mov     r12d, 4
.z3:
    SETB    rbx, esi, 32, r12d, B_LEAVES    ; canopy goes on into section 2
    inc     r12d
    cmp     r12d, 8
    jb      .z3
    inc     esi
    cmp     esi, 8
    jb      .x3
    BUILD   rbx, 1
    ; buried core x,z 5..6, y 29..31: 20 pairs -> 40 faces; the top faces
    ; towards y=32 (partner in the padding) stay
    CHECK_EQ32 [rel mh_on], (96 + 288 - 40) * 6, "padding-layer pairs kept"
ENDP

PROC tm_flat_lighting_has_no_ao
    TEST "mesher: flat lighting has no AO"
    call    mh_reset
    mov     rbx, rax
    SETTING SET_SMOOTH, 0
    SETB    rbx, 5, 40, 5, B_STONE
    SETB    rbx, 6, 41, 5, B_STONE
    BUILD   rbx, 2
    CRIT    1, -BIG, BIG, 41.0, 41.0, -BIG, BIG
    SEL_TRIS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    CRIT    0, 5.0, 6.0, -BIG, BIG, -BIG, BIG
    SEL_VERTS mh_sel, r12d, mh_sel2
    mov     r13d, eax
    COUNT   mh_sel2, r13d, V_SHADE, 255, 0xFF
    CHECK_EQ32 eax, r13d, "no AO darkening with flat lighting"
ENDP

PROC tm_glass_cull_same
    TEST "mesher: glass cull same"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 3, 20, 3, B_GLASS
    SETB    rbx, 3, 21, 3, B_GLASS
    BUILD   rbx, 1
    CHECK_EQ32 [rel mh_on], 60, "inner glass faces culled"
ENDP

PROC tm_grass_side_tint_flag
    TEST "mesher: grass side tint flag"
    call    mh_reset
    mov     rbx, rax
    ; grass sides get the tint + VF_GRASSSIDE (8), top gets the tint only,
    ; bottom is plain dirt
    mov     dword [rel biome_grass_color + 2*4], 0xFF22AA44
    mov     edx, 2
    call    tm_all_biomes
    SETB    rbx, 5, 20, 5, B_GRASS
    BUILD   rbx, 1
    CRIT    1, -BIG, BIG, -BIG, BIG, -BIG, BIG
    SEL_TRIS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    COUNT   mh_sel, r12d, V_FLAGS, 0x22AA4400, 0xFFFFFFFF
    CHECK_EQ32 eax, r12d, "top: flags 0, tint 44 AA 22"
    CRIT    -1, -BIG, BIG, -BIG, BIG, -BIG, BIG
    SEL_TRIS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    COUNT   mh_sel, r12d, V_FLAGS, 0xFFFFFF00, 0xFFFFFFFF
    CHECK_EQ32 eax, r12d, "bottom: flags 0, white"
    CRIT    2, -BIG, BIG, -BIG, BIG, -BIG, BIG
    SEL_TRIS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    COUNT   mh_sel, r12d, V_FLAGS, 0x22AA4408, 0xFFFFFFFF
    CHECK_EQ32 eax, r12d, "sides: flag 8, tint 44 AA 22"
    SETB    rbx, 5, 20, 5, B_STONE
    BUILD   rbx, 1
    CHECK_TRUE [rel mh_on], "stone has geometry"
    COUNT   mh_o, [rel mh_on], V_FLAGS, 0, 0xFF
    CHECK_EQ32 eax, [rel mh_on], "stone flags all 0"
ENDP

PROC tm_grass_tint_and_biome_blend
    TEST "mesher: grass tint and biome blend"
    call    mh_reset
    mov     rbx, rax
    mov     dword [rel biome_grass_color + 2*4], 0xFF00FF00     ; ABGR
    mov     dword [rel biome_grass_color + 3*4], 0xFF0000FF
    mov     edx, 2
    call    tm_all_biomes
    mov     ecx, 3
    call    tm_east_biome
    SETB    rbx, 5, 20, 5, B_GRASS
    SETB    rbx, 15, 20, 5, B_GRASS
    BUILD   rbx, 1
    CRIT    -1, -BIG, BIG, -BIG, BIG, -BIG, BIG
    SEL_TRIS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    CHECK_TRUE r12d, "bottom faces exist"
    COUNT   mh_sel, r12d, V_FLAGS, 0xFFFFFF00, 0xFFFFFFFF
    CHECK_EQ32 eax, r12d, "bottom (flags,r,g,b) == (0,255,255,255)"
    CRIT    0, 5.0, 6.0, 21.0, 21.0, -BIG, BIG
    SEL_VERTS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    COUNT   mh_sel, r12d, V_R, 0x00FF00, 0xFFFFFF
    mov     r13d, eax
    CHECK_TRUE r13d, "green tint present at x=5"
    COUNT   mh_sel, r12d, V_R, 0xFFFFFF, 0xFFFFFF
    add     r13d, eax
    CHECK_EQ32 r13d, r12d, "x=5 top colours are only green / white"
    ; 9-tap tent blur: x = 15 sees chunk (1,0) in its columns 16..19 with
    ; weights 4+3+2+1 = 10 of 25 -> 40 % red, 60 % green
    CRIT    0, 15.0, 16.0, 21.0, 21.0, -BIG, BIG
    SEL_VERTS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    COUNT   mh_sel, r12d, V_R, 0x009966, 0xFFFFFF
    CHECK_TRUE eax, "x=15 has the blended (102,153,0)"
ENDP

PROC tm_lava_does_not_darken_floor_corners
    TEST "mesher: lava does not darken floor corners"
    call    mh_reset
    mov     rbx, rax
    ; lava cell has sky 0 (opacity 15) but must not drag down the smooth
    ; sky light of the floor corners next to it
    lea     r15, [rel blk_opacity]
    movzx   r14d, byte [r15 + B_LAVA]   ; restored at the end
    mov     byte [r15 + B_LAVA], 15
    SETB    rbx, 5, 40, 5, B_STONE
    SETB    rbx, 6, 40, 5, B_STONE
    SETB    rbx, 6, 41, 5, B_LAVA
    lea     rcx, [rbx + CHUNK_LIGHT]
    mov     edx, 0xFE                   ; open: sky 15, block 14
    mov     r8d, 32768
    call    mh_fill
    LIGHT   rbx, 6, 41, 5, 0x0F         ; lava cell: sky 0, block 15
    BUILD   rbx, 2
    CRIT    1, 5.0, 6.0, 41.0, 41.0, 5.0, 6.0
    SEL_TRIS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    CHECK_TRUE r12d, "floor top corners exist"
    COUNT   mh_sel, r12d, V_SKY, 255, 0xFF
    CHECK_EQ32 eax, r12d, "sky light stays full"
    COUNT_GE mh_sel, r12d, V_BLK, 14*17
    CHECK_EQ32 eax, r12d, "block light is not lowered"
    CRIT    0, 6.0, 6.0, -BIG, BIG, -BIG, BIG
    SEL_VERTS mh_sel, r12d, mh_sel2
    mov     r13d, eax
    CHECK_TRUE r13d, "east corners exist"
    COUNT_GE mh_sel2, r13d, V_BLK, 14*17 + 1
    CHECK_EQ32 eax, r13d, "lava glow brightens east corners"
    mov     [r15 + B_LAVA], r14b
ENDP

PROC tm_lava_is_opaque_pass
    TEST "mesher: lava is opaque pass"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 8, 40, 8, B_LAVA
    BUILD   rbx, 2
    CHECK_EQ32 [rel mh_tn], 0, "no translucent vertices"
    CHECK_EQ32 [rel mh_on], 36, "6 faces, no underside for lava"
ENDP

PROC tm_leaves_fancy_and_fast
    TEST "mesher: leaves fancy and fast"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 3, 20, 3, B_LEAVES
    SETB    rbx, 4, 20, 3, B_LEAVES
    BUILD   rbx, 1
    CHECK_EQ32 [rel mh_on], 72, "fancy: inner faces kept"
    COUNT   mh_o, [rel mh_on], V_FLAGS, 1, 1
    CHECK_EQ32 eax, [rel mh_on], "fancy leaves wave"
    COUNT   mh_o, [rel mh_on], V_FLAGS, 4, 4
    CHECK_EQ32 eax, 0, "fancy leaves keep alpha holes"
    SETTING SET_FANCY, 0
    BUILD   rbx, 1
    CHECK_EQ32 [rel mh_on], 60, "fast: culled like opaque"
    COUNT   mh_o, [rel mh_on], V_FLAGS, 4, 4
    CHECK_EQ32 eax, [rel mh_on], "fast leaves fill alpha holes"
    SETB    rbx, 5, 20, 3, B_STONE
    BUILD   rbx, 1
    CHECK_EQ32 [rel mh_on], 54 + 30, "leaf +X face hidden by stone too"
ENDP

PROC tm_models
    TEST "mesher: models"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 2, 20, 2, B_TALL_GRASS
    BUILD   rbx, 1
    CHECK_EQ32 [rel mh_on], 24, "cross model: 4 quads"
    CRIT    0, -BIG, BIG, 21.0, 21.0, -BIG, BIG
    SEL_VERTS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    CHECK_TRUE r12d, "plant has top vertices"
    COUNT   mh_sel, r12d, V_FLAGS, 1, 1
    CHECK_EQ32 eax, r12d, "plant tops wave"
    CRIT    0, -BIG, BIG, 20.0, 20.0, -BIG, BIG
    SEL_VERTS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    COUNT   mh_sel, r12d, V_FLAGS, 0, 0xFF
    CHECK_EQ32 eax, r12d, "plant roots do not wave"
    SETB    rbx, 2, 20, 2, B_TORCH
    BUILD   rbx, 1
    CHECK_EQ32 [rel mh_on], 36, "torch: 6 quads"
    MINMAX  mh_o, [rel mh_on], V_Y
    CHECK_NEAR xmm1, 20.625, 0.000005, "torch top at y + 10/16"
    SETB    rbx, 2, 20, 2, B_LANTERN
    BUILD   rbx, 1
    CHECK_EQ32 [rel mh_on], 66, "lantern: 11 quads"
    SETB    rbx, 2, 20, 2, B_CACTUS
    BUILD   rbx, 1
    CHECK_EQ32 [rel mh_on], 36, "cactus: 6 quads"
    CRIT    0, 2.06245, 2.06255, -BIG, BIG, -BIG, BIG
    SEL_VERTS mh_o, [rel mh_on], mh_sel
    CHECK_TRUE eax, "cactus side inset at x = 2.0625"
    CRIT    0, 2.93745, 2.93755, -BIG, BIG, -BIG, BIG
    SEL_VERTS mh_o, [rel mh_on], mh_sel
    CHECK_TRUE eax, "cactus side inset at x = 2.9375"
ENDP

PROC tm_neighbour_culling
    TEST "mesher: neighbour culling"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 8, 40, 8, B_STONE
    SETB    rbx, 9, 40, 8, B_STONE
    BUILD   rbx, 2
    CHECK_EQ32 [rel mh_on], 60, "shared face culled"
ENDP

PROC tm_section_border_culling
    TEST "mesher: section border culling"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 4, 47, 4, B_STONE      ; top of section 2
    SETB    rbx, 4, 48, 4, B_STONE      ; bottom of section 3
    BUILD   rbx, 2
    CHECK_EQ32 [rel mh_on], 30, "face against section 3 culled"
ENDP

PROC tm_single_cube_36_vertices
    TEST "mesher: single cube 36 vertices"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 8, 40, 8, B_STONE
    BUILD   rbx, 2
    CHECK_EQ32 [rel mh_on], 36, "36 opaque vertices"
    CHECK_EQ32 [rel mh_tn], 0, "no translucent vertices"
    movzx   eax, byte [rbx + CHUNK.sec_flags + 2]
    CHECK_EQ32 eax, 1, "sec_flags[2] == opaque"
    MINMAX  mh_o, [rel mh_on], V_X
    movss   [rel mh_tmpf], xmm1
    CHECK_NEAR xmm0, 8.0, 0.000001, "min x"
    CHECK_NEAR [rel mh_tmpf], 9.0, 0.000001, "max x"
    MINMAX  mh_o, [rel mh_on], V_Y
    movss   [rel mh_tmpf], xmm1
    CHECK_NEAR xmm0, 40.0, 0.000001, "min y"
    CHECK_NEAR [rel mh_tmpf], 41.0, 0.000001, "max y"
    MINMAX  mh_o, [rel mh_on], V_Z
    movss   [rel mh_tmpf], xmm1
    CHECK_NEAR xmm0, 8.0, 0.000001, "min z"
    CHECK_NEAR [rel mh_tmpf], 9.0, 0.000001, "max z"
    COUNT   mh_o, [rel mh_on], V_SHADE, 255, 0xFF
    CHECK_EQ32 eax, 6, "top shade 1.0 (255)"
    COUNT   mh_o, [rel mh_on], V_SHADE, 128, 0xFF
    CHECK_EQ32 eax, 6, "bottom shade 0.5 (128)"
    COUNT   mh_o, [rel mh_on], V_SHADE, 153, 0xFF
    CHECK_EQ32 eax, 12, "X faces shade 0.6 (153)"
    COUNT   mh_o, [rel mh_on], V_SHADE, 204, 0xFF
    CHECK_EQ32 eax, 12, "Z faces shade 0.8 (204)"
    COUNT   mh_o, [rel mh_on], V_SKY, 255, 0xFF
    CHECK_EQ32 eax, [rel mh_on], "full sky light"
    ; ccw winding
    lea     rcx, [rel mh_o]
    mov     edx, [rel mh_on]
    lea     r8, [rel centre_cube]
    call    mh_outward_fail
    CHECK_EQ32 eax, 0, "all triangles face outwards"
    ; uv inset 1/1024, tile 0
    MINMAX  mh_o, [rel mh_on], V_U
    movss   [rel mh_tmpf], xmm1
    CHECK_NEAR xmm0, 0.0009765625, 0.0000005, "min u = 1/1024"
    CHECK_NEAR [rel mh_tmpf], 0.0615234375, 0.0000005, "max u = 1/16 - 1/1024"
ENDP

PROC tm_smooth_light_average
    TEST "mesher: smooth light average"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 5, 40, 5, B_STONE
    lea     rcx, [rbx + CHUNK_LIGHT]
    xor     edx, edx
    mov     r8d, 32768
    call    mh_fill
    LIGHT   rbx, 5, 41, 5, 0x0F         ; block light 15 straight above only
    BUILD   rbx, 2
    CRIT    1, -BIG, BIG, 41.0, 41.0, -BIG, BIG
    SEL_TRIS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    CHECK_TRUE r12d, "top face exists"
    ; each corner averages 4 cells, one of them lit: 15*17/4 = 63.75
    COUNT   mh_sel, r12d, V_BLK, 63, 0xFF
    CHECK_EQ32 eax, r12d, "block light 63 at every corner"
    SETTING SET_SMOOTH, 0
    BUILD   rbx, 2
    SEL_TRIS mh_o, [rel mh_on], mh_sel
    mov     r12d, eax
    COUNT   mh_sel, r12d, V_BLK, 255, 0xFF
    CHECK_EQ32 eax, r12d, "flat: block light 255"
    COUNT   mh_sel, r12d, V_SHADE, 255, 0xFF
    CHECK_EQ32 eax, r12d, "flat: shade 255"
ENDP

PROC tm_water_pool
    TEST "mesher: water pool"
    call    mh_reset
    mov     rbx, rax
    mov     esi, 4
.x:
    mov     edi, 4
.z:
    SETB    rbx, esi, 39, edi, B_STONE
    mov     r12d, B_WATER
    cmp     esi, 4
    je      .edge
    cmp     esi, 8
    je      .edge
    cmp     edi, 4
    je      .edge
    cmp     edi, 8
    jne     .put
.edge:
    mov     r12d, B_STONE
.put:
    SETB    rbx, esi, 40, edi, r12d
    inc     edi
    cmp     edi, 9
    jb      .z
    inc     esi
    cmp     esi, 9
    jb      .x
    BUILD   rbx, 2
    ; 9 water cells: only top + underside quads, no sides against water/stone
    CHECK_EQ32 [rel mh_tn], 9 * 12, "9 cells x (top + underside)"
    CRIT    0, 6.0, 7.0, -BIG, BIG, 6.0, 7.0
    SEL_VERTS mh_t, [rel mh_tn], mh_sel
    mov     r12d, eax
    CHECK_TRUE r12d, "centre vertices exist"
    CRIT    0, -BIG, BIG, 40.886936, 40.890842, -BIG, BIG ; verts are 1/256 block, +-1/512
    SEL_VERTS mh_sel, r12d, mh_sel2
    CHECK_EQ32 eax, r12d, "pool surface at 40 + 0.888889"
    ; water with water above: no top face, full-height sides
    SETB    rbx, 8, 60, 8, B_WATER
    SETB    rbx, 8, 61, 8, B_WATER + 3
    BUILD   rbx, 3
    CRIT    0, 8.0, 9.0, -BIG, 61.0, -BIG, BIG
    SEL_VERTS mh_t, [rel mh_tn], mh_sel
    mov     r12d, eax
    CHECK_TRUE r12d, "lower water cell has vertices"
    MINMAX  mh_sel, r12d, V_Y
    CHECK_NEAR xmm1, 61.0, 0.000001, "lower cell sides reach y = 61"
ENDP

PROC tm_water_single_source
    TEST "mesher: water single source"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 8, 40, 8, B_WATER
    BUILD   rbx, 2
    CHECK_EQ32 [rel mh_on], 0, "no opaque vertices"
    CHECK_EQ32 [rel mh_tn], 42, "top + underside + 4 sides + bottom"
    movzx   eax, byte [rbx + CHUNK.sec_flags + 2]
    CHECK_EQ32 eax, 2, "sec_flags[2] == translucent"
    ; h = 0.888889 * 4 / 7 (source weighted 4, three open cells) = 0.5079366
    CRIT    0, -BIG, BIG, 40.00001, BIG, -BIG, BIG
    SEL_VERTS mh_t, [rel mh_tn], mh_sel
    mov     r12d, eax
    CHECK_TRUE r12d, "surface vertices exist"
    CRIT    0, -BIG, BIG, 40.5059835, 40.5098897, -BIG, BIG ; |y-40-h| <= 1/512, verts are 1/256
    SEL_VERTS mh_sel, r12d, mh_sel2
    CHECK_EQ32 eax, r12d, "surface height 40 + 4/7 * 0.888889"
    COUNT   mh_sel, r12d, V_FLAGS, 2, 2
    CHECK_EQ32 eax, r12d, "liquid surface flag on the top"
    COUNT   mh_t, [rel mh_tn], V_FLAGS, 0, 0xFF
    CHECK_TRUE eax, "bottoms are not bobbing"
ENDP
