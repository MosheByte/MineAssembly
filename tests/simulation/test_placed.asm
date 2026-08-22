; test_placed.asm - placed-leaf ids (what a reload brings back) never rot, and
; the badlands ground keeps its plants
; @link src/ticks.asm src/fluids.asm
; @link tests/simulation/fakeworld.asm tests/simulation/simworld.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../simulation/simworld.inc"

section .text

PROC test_main, 0
    call case_placed_ids_never_rot
    call case_badlands_ground
ENDP

PROC case_placed_ids_never_rot
    TEST "leaves: placed ids never rot, even untracked"
    FLAT B_STONE
    ; raw puts = a chunk loaded from disk, the in-memory set knows nothing
    PUT  0, 11, 0, B_LEAVES_P
    PUT  1, 11, 0, B_BIRCH_LEAVES_P
    PUT  2, 11, 0, B_PINE_LEAVES_P
    PUT  0, 11, 2, B_LEAVES             ; natural, no log anywhere
    CHECK_EQ32 [rel ticks_pl_count], 0, "nothing remembered"
    PUT  0, 11, 1, B_STONE
    WSET 0, 11, 1, B_AIR                ; wakes every leaf within 4
    SETTLE
    CHECK_BLK 0, 11, 0, B_LEAVES_P, "placed oak survives"
    CHECK_BLK 1, 11, 0, B_BIRCH_LEAVES_P, "placed birch survives"
    CHECK_BLK 2, 11, 0, B_PINE_LEAVES_P, "placed pine survives"
    CHECK_BLK 0, 11, 2, B_AIR, "the natural one still rots"
    LEAFCHK 0, 11, 0
    CHECK_BLK 0, 11, 0, B_LEAVES_P, "explicit check keeps it too"
    LEAFCHK 2, 11, 0
    CHECK_BLK 2, 11, 0, B_PINE_LEAVES_P, "explicit check keeps pine"
    WSET 4, 11, 0, B_LEAVES_P
    CHECK_EQ32 [rel ticks_pl_count], 0, "placed ids aren't tracked, no need"
    WSET 5, 11, 0, B_LEAVES
    CHECK_EQ32 [rel ticks_pl_count], 1, "natural id set by hand still is"
ENDP

PROC case_badlands_ground
    TEST "plants: cactus and dead bush on badlands ground"
    FLAT B_STONE
    PUT  0, 10, 0, B_RED_SAND
    PUT  4, 10, 0, B_TERRACOTTA+3
    PUT  8, 10, 0, B_RED_SAND
    WSET 0, 11, 0, B_CACTUS
    WSET 4, 11, 0, B_DEAD_BUSH
    WSET 8, 11, 0, B_DEAD_BUSH
    WSET 12, 11, 0, B_DEAD_BUSH         ; plain stone
    SETTLE
    CHECK_BLK 0, 11, 0, B_CACTUS, "cactus stays on red sand"
    CHECK_BLK 4, 11, 0, B_DEAD_BUSH, "dead bush stays on terracotta"
    CHECK_BLK 8, 11, 0, B_DEAD_BUSH, "dead bush stays on red sand"
    CHECK_BLK 12, 11, 0, B_AIR, "but not on stone"
ENDP
