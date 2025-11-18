; light_init_chunk_sky on its own: heightmap + straight-down sky, nothing propagated yet
; @link src/light.asm tests/light/fakeworld.asm tests/light/lightlib.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../light/lightlib.inc"  ; via -I tests/lib/

section .text
PROC test_main, 0
    call lt_setup_tables

    TEST "column values and heightmap"
    mov  ecx, -1
    call lt_world_new
    FILL 0, 64, 0, LT_WS, 0, LT_WS, T_STONE  ; surface at y=63
    FILL 80, 81, 3, 4, 3, 4, T_LEAVES  ; chunk (-1,-1)
    FILL 89, 91, 5, 6, 5, 6, T_WATER
    mov  ecx, 1
    call lt_load_chunks  ; column pass only

    CHECK_SKY 0, 127, 0, 15, "open column y=127"
    CHECK_SKY 0, 100, 0, 15, "open column y=100"
    CHECK_SKY 0, 64, 0, 15, "open column y=64 (on the ground)"
    CHECK_SKY 0, 63, 0, 0, "inside the ground"
    ; leaf: 15 -> 14, then -1 per block below
    CHECK_SKY -13, 81, -13, 15, "above the leaf"
    CHECK_SKY -13, 80, -13, 14, "in the leaf"
    CHECK_SKY -13, 79, -13, 13, "1 below the leaf"
    CHECK_SKY -13, 78, -13, 12, "2 below the leaf"
    CHECK_SKY -13, 65, -13, 0, "15 below the leaf"
    ; two water: 15 -> 13 -> 10 -> 9 ...
    CHECK_SKY -11, 91, -11, 15, "above the water"
    CHECK_SKY -11, 90, -11, 13, "top water"
    CHECK_SKY -11, 89, -11, 10, "bottom water"
    CHECK_SKY -11, 88, -11, 9, "1 below the water"
    CHECK_SKY -11, 87, -11, 8, "2 below the water"
    CHECK_HM 0, 0, 64, "heightmap of the flat ground"
    CHECK_HM -13, -13, 81, "heightmap over the leaf"
    CHECK_HM -11, -11, 91, "heightmap over the water"
    call lt_all_blk_zero
    CHECK_TRUE eax, "no block light after the column pass"
ENDP
