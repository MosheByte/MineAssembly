; light_on_block_changed: torches, emitters, chunk borders, dirty bits, sky shafts,
; shadows, heightmap refresh, partial opacity. hand-computed values + CHECK_REF each time
; @link src/light.asm tests/light/fakeworld.asm tests/light/lightlib.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../light/lightlib.inc"  ; via -I tests/lib/

section .text

PROC flat64, 0
    mov  ecx, 64
    call lt_flat_world
    xor  ecx, ecx
    call lt_generate
ENDP

PROC sky_slab_lit, 0
    mov  ecx, 64
    mov  edx, 128
    mov  r8d, 15
    call lt_all_sky
ENDP

PROC test_main, 0
    call lt_setup_tables

    TEST "torch manhattan falloff and removal"
    call lt_dark_room
    CHECK_SKY 8, 66, 8, 0, "dark room is dark"
    SETB 8, 66, 8, T_TORCH
    CHECK_BLK 8, 66, 8, 14, "torch cell"
    ; 14 - manhattan distance
    CHECK_BLK 9, 66, 8, 13, "d=(1,0,0)"
    CHECK_BLK 8, 67, 8, 13, "d=(0,1,0)"
    CHECK_BLK 8, 65, 8, 13, "d=(0,-1,0)"
    CHECK_BLK 11, 67, 10, 8, "d=(3,1,2)"
    CHECK_BLK 3, 66, 12, 5, "d=(-5,0,4)"
    CHECK_BLK 14, 70, 6, 2, "d=(6,4,-2)"
    CHECK_BLK 21, 66, 8, 1, "d=(13,0,0)"
    CHECK_BLK 22, 66, 8, 0, "d=(14,0,0) is dark"
    CHECK_REF "torch placed"
    SETB 8, 66, 8, T_AIR
    call lt_all_blk_zero
    CHECK_TRUE eax, "no block light after removing the torch"
    CHECK_REF "torch removed"

    TEST "two torches remove one"
    call lt_dark_room
    SETB 4, 65, 8, T_TORCH
    SETB 12, 65, 8, T_TORCH
    CHECK_BLK 8, 65, 8, 10, "midway between the torches"
    SETB 4, 65, 8, T_AIR
    CHECK_BLK 4, 65, 8, 6, "removed torch now lit by the other"
    CHECK_BLK 12, 65, 8, 14, "remaining torch"
    CHECK_REF "one torch left"

    TEST "light crosses chunk borders"
    call lt_dark_room
    SETB 15, 66, 0, T_GLOW  ; corner of chunk (0,0)
    CHECK_BLK 15, 66, 0, 15, "glow cell"
    CHECK_BLK 16, 66, 0, 14, "chunk (1,0)"
    CHECK_BLK 15, 66, -1, 14, "chunk (0,-1)"
    CHECK_BLK 16, 66, -1, 13, "chunk (1,-1)"
    CHECK_BLK 22, 67, -4, 3, "15-7-1-4"
    CHECK_REF "glow"
    ; y=66 is section 4, dirty in all four chunks around the corner
    mov  ecx, 0
    mov  edx, 0
    mov  r8d, LT_OFF_DIRTY
    call lt_header
    and  eax, 1 << 4
    CHECK_TRUE eax, "dirty section 4 of chunk (0,0)"
    mov  ecx, 1
    mov  edx, 0
    mov  r8d, LT_OFF_DIRTY
    call lt_header
    and  eax, 1 << 4
    CHECK_TRUE eax, "dirty section 4 of chunk (1,0)"
    mov  ecx, 0
    mov  edx, -1
    mov  r8d, LT_OFF_DIRTY
    call lt_header
    and  eax, 1 << 4
    CHECK_TRUE eax, "dirty section 4 of chunk (0,-1)"
    mov  ecx, 1
    mov  edx, -1
    mov  r8d, LT_OFF_DIRTY
    call lt_header
    and  eax, 1 << 4
    CHECK_TRUE eax, "dirty section 4 of chunk (1,-1)"
    SETB 15, 66, 0, T_AIR
    call lt_all_blk_zero
    CHECK_TRUE eax, "no block light after removing the glow"

    TEST "dirty section boundaries"
    call lt_dark_room
    mov  ebx, -1
.clr_z:
    mov  esi, -1
.clr_x:
    mov  ecx, esi
    mov  edx, ebx
    mov  r8d, LT_OFF_DIRTY
    xor  r9d, r9d
    call lt_set_header
    inc  esi
    cmp  esi, 2
    jl   .clr_x
    inc  ebx
    cmp  ebx, 2
    jl   .clr_z
    SETB 8, 64, 8, T_TORCH  ; bottom layer of section 4, so 3 gets dirtied too (floor sampled)
    xor  ecx, ecx
    xor  edx, edx
    mov  r8d, LT_OFF_DIRTY
    call lt_header
    mov  ebx, eax
    and  eax, 1 << 3
    CHECK_TRUE eax, "section 3 dirty (floor sampled)"
    mov  eax, ebx
    and  eax, 1 << 4
    CHECK_TRUE eax, "section 4 dirty"
    mov  eax, ebx
    and  eax, 1 << 6
    CHECK_EQ32 eax, 0, "section 6 not dirty"

    TEST "dig shaft to sky and cap it"
    mov  ecx, -1
    call lt_world_new
    FILL 0, 100, 0, LT_WS, 0, LT_WS, T_STONE
    xor  ecx, ecx
    call lt_generate
    mov  ebx, 99
.dig:
    SETB 8, ebx, 8, T_AIR
    dec  ebx
    cmp  ebx, 70
    jge  .dig
    CHECK_SKY 8, 99, 8, 15, "shaft top"
    CHECK_SKY 8, 85, 8, 15, "shaft middle"
    CHECK_SKY 8, 70, 8, 15, "shaft bottom"
    CHECK_HM 8, 8, 70, "heightmap of the shaft"
    CHECK_REF "shaft dug"
    mov  ebx, 9
.tun:
    SETB ebx, 70, 8, T_AIR
    inc  ebx
    cmp  ebx, 14
    jl   .tun
    CHECK_SKY 9, 70, 8, 14, "tunnel 1"
    CHECK_SKY 10, 70, 8, 13, "tunnel 2"
    CHECK_SKY 11, 70, 8, 12, "tunnel 3"
    CHECK_SKY 12, 70, 8, 11, "tunnel 4"
    CHECK_SKY 13, 70, 8, 10, "tunnel 5"
    CHECK_REF "tunnel"
    SETB 8, 99, 8, T_STONE
    CHECK_SKY 8, 98, 8, 0, "below the cap"
    CHECK_SKY 8, 70, 8, 0, "capped shaft bottom"
    CHECK_SKY 11, 70, 8, 0, "capped tunnel"
    CHECK_REF "capped"

    TEST "block over lit column darkens below"
    call flat64
    SETB 5, 90, 5, T_STONE
    CHECK_SKY 5, 91, 5, 15, "above the block"
    CHECK_SKY 5, 90, 5, 0, "inside the block"
    CHECK_SKY 5, 89, 5, 14, "below the block"
    CHECK_SKY 5, 75, 5, 14, "far below the block"
    CHECK_SKY 5, 64, 5, 14, "on the ground below the block"
    CHECK_HM 5, 5, 91, "heightmap raised"
    CHECK_REF "pillar cap"
    SETB 5, 90, 5, T_AIR
    CHECK_SKY 5, 89, 5, 15, "relit below"
    CHECK_SKY 5, 64, 5, 15, "relit ground"
    call sky_slab_lit
    CHECK_TRUE eax, "whole air slab back to 15"

    TEST "heightmap already updated by world"
    ; world_set_block may already have refreshed CHUNK.heightmap before calling us
    call flat64
    SETB 5, 90, 5, T_STONE, LT_NOTIFY | LT_WORLD_HM
    CHECK_SKY 5, 89, 5, 14, "below the cap"
    CHECK_SKY 5, 64, 5, 14, "ground below the cap"
    CHECK_REF "cap"
    SETB 5, 90, 5, T_AIR, LT_NOTIFY | LT_WORLD_HM
    CHECK_SKY 5, 89, 5, 15, "relit below"
    CHECK_SKY 5, 64, 5, 15, "relit ground"
    mov  ebx, 63
.pit:
    SETB -3, ebx, 7, T_AIR, LT_NOTIFY | LT_WORLD_HM
    dec  ebx
    cmp  ebx, 50
    jg   .pit
    CHECK_SKY -3, 51, 7, 15, "bottom of the pit"
    SETB -3, 70, 7, T_LEAVES, LT_NOTIFY | LT_WORLD_HM
    CHECK_REF "pit + leaf"

    TEST "build roof incrementally"
    call flat64
    mov  ebx, -12
.rz:
    mov  esi, -12
.rx:
    SETB esi, 70, ebx, T_STONE
    inc  esi
    cmp  esi, 28
    jl   .rx
    inc  ebx
    cmp  ebx, 28
    jl   .rz
    CHECK_SKY 8, 66, 8, 0, "under the roof"
    CHECK_REF "roof built"
    mov  ebx, -12
.dz:
    mov  esi, -12
.dx:
    SETB esi, 70, ebx, T_AIR
    inc  esi
    cmp  esi, 28
    jl   .dx
    inc  ebx
    cmp  ebx, 28
    jl   .dz
    call sky_slab_lit
    CHECK_TRUE eax, "roof removed: whole air slab back to 15"

    TEST "partial opacity leaves and water"
    call flat64
    SETB 3, 80, 3, T_LEAVES
    CHECK_SKY 3, 80, 3, 14, "in the leaf"
    CHECK_SKY 3, 79, 3, 14, "below the leaf (side light wins)"
    CHECK_REF "leaf"
    ; 9x9 pond, 6 deep
    mov  r12d, 58
.py:
    xor  ebx, ebx
.pz:
    xor  esi, esi
.px:
    SETB esi, r12d, ebx, T_WATER
    inc  esi
    cmp  esi, 9
    jl   .px
    inc  ebx
    cmp  ebx, 9
    jl   .pz
    inc  r12d
    cmp  r12d, 64
    jl   .py
    CHECK_SKY 4, 63, 4, 13, "pond surface"
    CHECK_REF "pond"
    mov  ebx, -1
.cz:
    mov  esi, -1
.cx:
    SETB esi, 75, ebx, T_LEAVES
    inc  esi
    cmp  esi, 10
    jl   .cx
    inc  ebx
    cmp  ebx, 10
    jl   .cz
    CHECK_REF "canopy"

    TEST "emitters variety"
    call lt_dark_room
    SETB 0, 64, 0, T_LAVA
    SETB 20, 70, 20, T_LANTERN
    SETB -5, 67, 15, T_FURNACE_LIT
    CHECK_BLK 0, 65, 0, 14, "above the lava"
    CHECK_BLK -5, 67, 16, 12, "next to the lit furnace"
    CHECK_REF "emitters placed"
    SETB 0, 64, 0, T_STONE
    SETB 20, 70, 20, T_GLASS
    CHECK_REF "emitters replaced"
ENDP
