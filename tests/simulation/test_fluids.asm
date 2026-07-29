; test_fluids.asm - fluids.asm on the fake world. the random terrain cases only
; assert things that hold for any heightmap (settles, stays still, drains).
; @link src/ticks.asm src/fluids.asm
; @link tests/simulation/fakeworld.asm tests/simulation/simworld.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../simulation/simworld.inc"

%define FLOOR 10                        ; liquids go at y=11

; whole layer y
%macro CHECK_LIQUIDS 3.nolist
    COUNT_BOX -32, 31, %1, %1, -32, 31, B_WATER, B_LAVA_LAST
    CHECK_EQ32 eax, %2, %3
%endmacro


section .rdata
choice_7:   db 0, 0, 0, 1, 1, 2, 3      ; weighted height picks
choice_4:   db 0, 0, 1, 2
f_pit:      dd 0.03

section .text

PROC flat_world, 0
    W_NEW -2, 1
    FILL -32, FLOOR-1, -32, 31, FLOOR, 31, B_STONE
ENDP

; -> eax cells on y=11 that are past radius (manhattan) or whose level != base+dist
PROC diamond_bad, 0
    mov  esi, ecx
    mov  edi, edx
    xor  ebx, ebx
    mov  r12d, -32
.lx:
    mov  r13d, -32
.lz:
    GET  r12d, 11, r13d
    cmp  eax, B_WATER
    jb   .nx
    cmp  eax, B_LAVA_LAST
    ja   .nx
    mov  ecx, r12d
    mov  edx, ecx
    neg  edx
    cmovl edx, ecx
    mov  ecx, r13d
    mov  r8d, ecx
    neg  r8d
    cmovl r8d, ecx
    add  edx, r8d
    cmp  edx, edi
    jg   .bad
    lea  ecx, [rsi+rdx]                 ; d=0 is the source itself
    cmp  eax, ecx
    je   .nx
.bad:
    inc  ebx
.nx:
    inc  r13d
    cmp  r13d, 31
    jle  .lz
    inc  r12d
    cmp  r12d, 31
    jle  .lx
    mov  eax, ebx
ENDP

PROC top_y, 0
    mov  r12d, ecx
    mov  r13d, edx
    mov  ebx, 127
.l:
    GET  r12d, ebx, r13d
    test eax, eax
    jnz  .done
    dec  ebx
    jns  .l
.done:
    mov  eax, ebx
ENDP

PROC case_water_diamond_radius_7
    TEST "fluids: water diamond radius 7"
    call flat_world
    WSET 0, 11, 0, B_WATER
    SETTLE
    CHECK_LIQUIDS 11, 113, "1 + 4+8+...+28 water cells"
    mov  ecx, B_WATER
    mov  edx, 7
    call diamond_bad
    CHECK_EQ32 eax, 0, "every cell at level = Manhattan distance <= 7"
    CHECK_LIQUIDS 12, 0, "nothing spilled above the sheet"
ENDP

PROC case_lava_diamond_radius_3_and_slow
    TEST "fluids: lava diamond radius 3, slow"
    call flat_world
    WSET 0, 11, 0, B_LAVA
    TICK 29
    CHECK_BLK 1, 11, 0, B_AIR, "lava must wait 30 ticks"
    TICK 1
    CHECK_BLK 1, 11, 0, B_LAVA+1, "lava flowed after 30 ticks"
    SETTLE
    CHECK_LIQUIDS 11, 1+4+8+12, "lava diamond size"
    mov  ecx, B_LAVA
    mov  edx, 3
    call diamond_bad
    CHECK_EQ32 eax, 0, "lava levels follow the distance"
ENDP

PROC case_water_speed_one_cell_per_5_ticks
    TEST "fluids: water speed 1 cell / 5 ticks"
    call flat_world
    WSET 0, 11, 0, B_WATER
    TICK 5
    CHECK_BLK 1, 11, 0, B_WATER+1, "first cell after 5 ticks"
    CHECK_BLK 2, 11, 0, B_AIR, "second cell not yet"
    TICK 5
    CHECK_BLK 2, 11, 0, B_WATER+2, "second cell after 10 ticks"
ENDP

PROC case_recede_when_source_removed
    TEST "fluids: recede when the source is removed"
    mov  ebx, B_WATER
.again:
    call flat_world
    WSET 0, 11, 0, ebx
    SETTLE
    WSET 0, 11, 0, B_AIR
    SETTLE
    CHECK_LIQUIDS 11, 0, "all flowing liquid receded"
    cmp  ebx, B_LAVA
    je   .done
    mov  ebx, B_LAVA
    jmp  .again
.done:
ENDP

PROC case_waterfall_off_a_ledge
    TEST "fluids: waterfall off a ledge"
    call flat_world
    ; plateau top y=15 for x<0, cliff between x=-1 and 0
    FILL -12, 11, -8, -1, 15, 8, B_STONE
    WSET -3, 16, 0, B_WATER
    SETTLE
    ; edge is in reach so no diamond, it goes straight for it
    CHECK_BLK -2, 16, 0, B_WATER+1, "runs toward the edge (1)"
    CHECK_BLK -1, 16, 0, B_WATER+2, "runs toward the edge (2)"
    CHECK_BLK -4, 16, 0, B_AIR, "must not flow away from the drop"
    CHECK_BLK -3, 16, 1, B_AIR, "no sideways spread +z"
    CHECK_BLK -3, 16, -1, B_AIR, "no sideways spread -z"
    CHECK_BLK 0, 16, 0, B_WATER+3, "over the edge"
    mov  r12d, 11
.col:
    CHECK_BLK 0, r12d, 0, B_WATER+1, "falling column is level 1"
    inc  r12d
    cmp  r12d, 16
    jl   .col
    CHECK_BLK 1, 15, 0, B_AIR, "falling water must not spread sideways"
    ; lands as level 1, so the pool only gets 6 more cells
    CHECK_BLK 6, 11, 0, B_WATER+7, "pool reaches 6 cells out"
    CHECK_BLK 7, 11, 0, B_AIR, "pool ends there"
    CHECK_BLK 0, 11, 6, B_WATER+7, "pool along z"
ENDP

PROC case_flows_toward_nearest_hole
    TEST "fluids: flows toward the nearest hole"
    call flat_world
    PUT  3, FLOOR, 0, B_AIR
    FILL -32, FLOOR-1, -32, 31, FLOOR-1, 31, B_STONE
    WSET 0, 11, 0, B_WATER
    SETTLE
    CHECK_BLK 1, 11, 0, B_WATER+1, "toward the hole (1)"
    CHECK_BLK 2, 11, 0, B_WATER+2, "toward the hole (2)"
    CHECK_BLK -1, 11, 0, B_AIR, "water should run only toward the hole"
    CHECK_BLK 0, 11, 1, B_AIR, "not sideways"
    COUNT_BOX 3, 3, FLOOR, FLOOR, 0, 0, B_WATER, B_LAVA_LAST
    CHECK_EQ32 eax, 1, "it fell into the hole"
ENDP

; 3 long along x at z=0, walls at x=-1 and 3
PROC trough, 0
    FILL -1, 11, -1, 3, 11, -1, B_STONE
    FILL -1, 11, 1, 3, 11, 1, B_STONE
    PUT  -1, 11, 0, B_STONE
    PUT  3, 11, 0, B_STONE
ENDP

PROC case_infinite_water_source
    TEST "fluids: infinite water source"
    call flat_world
    call trough
    WSET 0, 11, 0, B_WATER
    WSET 2, 11, 0, B_WATER
    SETTLE
    CHECK_BLK 1, 11, 0, B_WATER, "gap between two sources becomes a source"
    WSET 1, 11, 0, B_AIR                ; bucket out the middle
    SETTLE
    CHECK_BLK 1, 11, 0, B_WATER, "it refills"
    WSET 2, 11, 0, B_AIR
    WSET 1, 11, 0, B_AIR
    SETTLE
    CHECK_BLK 1, 11, 0, B_WATER+1, "single source: flowing level 1"
    CHECK_BLK 2, 11, 0, B_WATER+2, "single source: flowing level 2"
ENDP

PROC case_no_source_over_air
    TEST "fluids: no infinite source over air"
    call flat_world
    call trough
    PUT  1, FLOOR, 0, B_AIR
    FILL -5, FLOOR-3, -5, 5, FLOOR-3, 5, B_STONE
    WSET 0, 11, 0, B_WATER
    WSET 2, 11, 0, B_WATER
    SETTLE
    CHECK_NOT 1, 11, 0, B_WATER, "needs a solid floor or a source below"
ENDP

PROC lava_pocket, 0
    PUT  1, 11, 0, B_STONE
    PUT  -1, 11, 0, B_STONE
    PUT  0, 11, 1, B_STONE
    PUT  0, 11, -1, B_STONE
    WSET 0, 11, 0, B_LAVA
    SETTLE
ENDP

PROC case_water_next_to_lava_source_makes_obsidian
    TEST "fluids: water beside a lava source -> obsidian"
    call flat_world
    call lava_pocket
    WSET 1, 11, 0, B_WATER              ; wall -> water
    SETTLE
    CHECK_BLK 0, 11, 0, B_OBSIDIAN, "lava source hardened"
    mov  ecx, SFX_FIZZ
    call sw_count_sounds
    CHECK_TRUE eax, "fizz sound played"
    cmp  dword [rel sw_smoke_n], 8
    setae al
    movzx eax, al
    CHECK_TRUE eax, ">= 8 smoke particles"
ENDP

PROC case_water_on_top_of_lava_source_makes_obsidian
    TEST "fluids: water on a lava source -> obsidian"
    call flat_world
    call lava_pocket
    WSET 0, 12, 0, B_WATER
    SETTLE
    CHECK_BLK 0, 11, 0, B_OBSIDIAN, "lava source hardened"
ENDP

PROC lava_channel, 0
    FILL -1, 11, -1, 4, 12, -1, B_STONE
    FILL -1, 11, 1, 4, 12, 1, B_STONE
    FILL -1, 11, 0, -1, 12, 0, B_STONE
    WSET 0, 11, 0, B_LAVA
    SETTLE
    CHECK_BLK 0, 11, 0, B_LAVA, "channel: source"
    CHECK_BLK 1, 11, 0, B_LAVA+1, "channel: level 1"
    CHECK_BLK 2, 11, 0, B_LAVA+2, "channel: level 2"
    CHECK_BLK 3, 11, 0, B_LAVA+3, "channel: level 3"
ENDP

PROC case_water_beside_flowing_lava_makes_cobble
    TEST "fluids: water beside flowing lava -> cobble"
    call flat_world
    call lava_channel
    FILL -32, 11, 2, 31, 11, 31, B_STONE    ; walls so the water can't wander off
    FILL -32, 11, -31, 31, 11, -2, B_STONE
    WSET 4, 11, 0, B_WATER
    SETTLE
    CHECK_BLK 3, 11, 0, B_COBBLE, "flowing lava hardened to cobble"
    CHECK_BLK 0, 11, 0, B_LAVA, "the source upstream is untouched"
ENDP

PROC case_water_onto_flowing_lava_makes_stone
    TEST "fluids: water onto flowing lava -> stone"
    call flat_world
    call lava_channel
    WSET 2, 12, 0, B_WATER
    SETTLE
    CHECK_BLK 2, 11, 0, B_STONE, "flowing lava under water -> stone"
ENDP

PROC case_lava_pouring_into_water_makes_stone
    TEST "fluids: lava pouring into water -> stone"
    call flat_world
    PUT  1, 11, 0, B_STONE
    PUT  -1, 11, 0, B_STONE
    PUT  0, 11, 1, B_STONE
    PUT  0, 11, -1, B_STONE
    WSET 0, 11, 0, B_WATER
    WSET 0, 13, 0, B_LAVA               ; pours down onto it
    SETTLE
    CHECK_BLK 0, 11, 0, B_STONE, "water source hit by lava -> stone"
ENDP

PROC case_water_washes_away_torch_and_flowers
    TEST "fluids: water washes away torch and flowers"
    call flat_world
    FILL -32, FLOOR, -32, 31, FLOOR, 31, B_GRASS
    PUT  2, 11, 0, B_TORCH
    PUT  0, 11, 3, B_FLOWER_RED
    PUT  -2, 11, 0, B_TALL_GRASS
    WSET 0, 11, 0, B_WATER
    SETTLE
    CHECK_BLK 2, 11, 0, B_WATER+2, "torch washed away"
    CHECK_BLK 0, 11, 3, B_WATER+3, "flower washed away"
    CHECK_BLK -2, 11, 0, B_WATER+2, "tall grass washed away"
    CHECK_EQ32 [rel sw_drops_n], 2, "two drops (tall grass drops nothing)"
    mov  ecx, B_TORCH
    call sw_count_drops
    CHECK_EQ32 eax, 1, "torch dropped"
    mov  ecx, B_FLOWER_RED
    call sw_count_drops
    CHECK_EQ32 eax, 1, "flower dropped"
ENDP

PROC case_lava_burns_plants_without_drops
    TEST "fluids: lava burns plants without drops"
    call flat_world
    FILL -32, FLOOR, -32, 31, FLOOR, 31, B_GRASS
    PUT  1, 11, 0, B_FLOWER_YELLOW
    WSET 0, 11, 0, B_LAVA
    SETTLE
    CHECK_BLK 1, 11, 0, B_LAVA+1, "flower burnt"
    CHECK_EQ32 [rel sw_drops_n], 0, "burning drops nothing"
ENDP

PROC case_cactus_and_reeds_dam_water
    TEST "fluids: cactus and reeds dam water"
    call flat_world
    FILL -32, FLOOR, -32, 31, FLOOR, 31, B_SAND    ; stone under it, won't fall
    PUT  1, 11, 0, B_CACTUS
    PUT  -1, 11, 0, B_REEDS
    WSET 0, 11, 0, B_WATER
    SETTLE
    CHECK_BLK 1, 11, 0, B_CACTUS, "cactus stays"
    CHECK_BLK -1, 11, 0, B_REEDS, "reeds stay"
    CHECK_BLK 2, 11, 0, B_WATER+4, "flows around the cactus (4-step path)"
    CHECK_BLK -2, 11, 0, B_WATER+4, "and around the reeds"
    CHECK_EQ32 [rel sw_breaks_n], 0, "water beside them does not uproot them"
ENDP

PROC case_bucket_into_lake_stays_put
    TEST "fluids: bucket into a lake stays put"
    call flat_world
    FILL -5, 11, -5, 5, 11, 5, B_WATER  ; all sources
    WSET 0, 12, 0, B_WATER
    SETTLE
    COUNT_BOX -32, 31, 12, 12, -32, 31, B_WATER, B_LAVA_LAST
    mov  ebx, eax
    COUNT_BOX 0, 0, 12, 12, 0, 0, B_WATER, B_LAVA_LAST
    sub  ebx, eax
    CHECK_EQ32 ebx, 0, "no liquid on the lake except the poured cell"
    CHECK_BLK 1, 12, 0, B_AIR, "poured water does not spread"
ENDP

PROC case_unloaded_world_is_a_wall
    TEST "fluids: the unloaded world is a wall"
    W_NEW 0, 0                          ; just chunk 0,0
    FILL 0, FLOOR, 0, 15, FLOOR, 15, B_STONE
    WSET 0, 11, 0, B_WATER
    SETTLE
    CHECK_BLK 1, 11, 0, B_WATER+1, "flows inside the chunk"
    mov  ecx, -1
    xor  edx, edx
    call sw_chunk_peek
    CHECK_EQ rax, 0, "chunk (-1,0) was never created"
ENDP

PROC rnd_height, 0
    mov  rsi, rcx
    mov  ebx, edx
    mov  r12d, r8d
    call t_rng_next
    xor  edx, edx
    div  rbx
    movzx edi, byte [rsi+rdx]
    add  edi, 10
    test r12d, r12d
    jz   .done
    call t_rng_float
    comiss xmm0, [rel f_pit]
    jae  .done
    mov  edi, 6                         ; 3% pit
.done:
    mov  eax, edi
ENDP

; drops it on top of the column, -> eax y
PROC put_source, 0
    mov  r12d, ecx
    mov  r13d, edx
    mov  r14d, r8d
    call top_y
    lea  ebx, [rax+1]
    WSET r12d, ebx, r13d, r14d
    mov  eax, ebx
ENDP

PROC case_random_terrain_settles_and_stays_still
    TEST "fluids: random terrain settles and stays still"
    mov  ecx, 7
    call t_rng_seed
    W_NEW -2, 1
    mov  r12d, -32
.lx:
    mov  r13d, -32
.lz:
    lea  rcx, [rel choice_7]
    mov  edx, 7
    mov  r8d, 1
    call rnd_height
    mov  ebx, eax
    FILL r12d, 0, r13d, r12d, ebx, r13d, B_STONE
    inc  r13d
    cmp  r13d, 32
    jl   .lz
    inc  r12d
    cmp  r12d, 32
    jl   .lx
    mov  ecx, 0
    mov  edx, 0
    mov  r8d, B_WATER
    call put_source
    mov  ecx, 8
    mov  edx, -6
    mov  r8d, B_WATER
    call put_source
    mov  ecx, -10
    mov  edx, 5
    mov  r8d, B_WATER
    call put_source
    SETTLE 20000
    mov  ebx, [rel sw_sets]
    TICK 300
    CHECK_EQ32 [rel sw_sets], ebx, "settled water must not keep changing"
    CHECK_EQ32 [rel ticks_pending], 0, "nothing pending"
ENDP

PROC case_random_terrain_lava_drains_completely
    TEST "fluids: random terrain lava drains completely"
    mov  ecx, 99
    call t_rng_seed
    W_NEW -2, 1
    mov  r12d, -32
.lx:
    mov  r13d, -32
.lz:
    lea  rcx, [rel choice_4]
    mov  edx, 4
    xor  r8d, r8d
    call rnd_height
    mov  ebx, eax
    FILL r12d, 0, r13d, r12d, ebx, r13d, B_STONE
    inc  r13d
    cmp  r13d, 32
    jl   .lz
    inc  r12d
    cmp  r12d, 32
    jl   .lx
    xor  ecx, ecx
    xor  edx, edx
    mov  r8d, B_LAVA
    call put_source
    mov  r14d, eax
    mov  ecx, 5
    mov  edx, 5
    mov  r8d, B_LAVA
    call put_source
    mov  r15d, eax
    SETTLE 20000
    WSET 0, r14d, 0, B_AIR
    WSET 5, r15d, 5, B_AIR
    SETTLE 20000
    COUNT_BOX -32, 31, 8, 15, -32, 31, B_WATER, B_LAVA_LAST
    CHECK_EQ32 eax, 0, "no liquid left anywhere"
ENDP

PROC test_main
    call case_water_diamond_radius_7
    call case_lava_diamond_radius_3_and_slow
    call case_water_speed_one_cell_per_5_ticks
    call case_recede_when_source_removed
    call case_waterfall_off_a_ledge
    call case_flows_toward_nearest_hole
    call case_infinite_water_source
    call case_no_source_over_air
    call case_water_next_to_lava_source_makes_obsidian
    call case_water_on_top_of_lava_source_makes_obsidian
    call case_water_beside_flowing_lava_makes_cobble
    call case_water_onto_flowing_lava_makes_stone
    call case_lava_pouring_into_water_makes_stone
    call case_water_washes_away_torch_and_flowers
    call case_lava_burns_plants_without_drops
    call case_cactus_and_reeds_dam_water
    call case_bucket_into_lake_stays_put
    call case_unloaded_world_is_a_wall
    call case_random_terrain_settles_and_stays_still
    call case_random_terrain_lava_drains_completely
ENDP
