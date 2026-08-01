; test_ticks.asm - scheduler, gravity, support, random ticks, liquid restarts.
; leaves have their own file
; @link src/ticks.asm src/fluids.asm
; @link tests/simulation/fakeworld.asm tests/simulation/simworld.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../simulation/simworld.inc"

%define HEAP_N  3000

section .rdata
chunks_0_1_2_12:    dd 0,0, 1,0, 2,0, 12,0
chunks_0_12:        dd 0,0, 12,0
chunk_0:            dd 0,0

section .bss
rng_a:      resd 20
rng_b:      resd 20

section .text

PROC case_schedule_dedupe_and_due_order
    TEST "ticks: schedule dedupe + due order"
    W_NEW 100, 100                      ; coords below are unloaded -> updates do nothing
    SCHED 1, 2, 3, 5
    SCHED 1, 2, 3, 5
    SCHED 1, 2, 3, 9                    ; later than existing, ignored
    CHECK_EQ32 [rel ticks_pending], 1, "deduplicated"
    SCHED 4, 5, 6, 2
    CHECK_EQ32 [rel ticks_pending], 2, "second position queued"
    TICK 2
    CHECK_EQ32 [rel ticks_pending], 1, "(4,5,6) ran at tick 2"
    SCHED 1, 2, 3, 1                    ; decrease-key
    CHECK_EQ32 [rel ticks_pending], 1, "decrease-key keeps one entry"
    TICK 1
    CHECK_EQ32 [rel ticks_pending], 0, "pulled-in entry ran"
ENDP

PROC case_rejects_out_of_world_y
    TEST "ticks: rejects y outside the world"
    W_NEW -2, 1
    SCHED 0, -1, 0, 1
    SCHED 0, 128, 0, 1
    CHECK_EQ32 [rel ticks_pending], 0, "y -1 and 128 rejected"
ENDP

PROC case_capacity_and_graceful_drop
    TEST "ticks: capacity + graceful drop"
    W_NEW 100, 100
    xor  ebx, ebx
.l:
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, 300
    div  ecx
    mov  r12d, edx
    xor  edx, edx
    mov  ecx, 128
    div  ecx
    mov  r13d, edx
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, 38400                     ; 300*128
    div  ecx
    mov  r14d, eax
    SCHED r12d, r13d, r14d, 1
    inc  ebx
    cmp  ebx, 70000
    jb   .l
    CHECK_EQ32 [rel ticks_pending], 65536, "pool holds 65536"
    CHECK_EQ32 [rel ticks_dropped], 70000-65536, "the rest is counted as dropped"
    TICK 1
    CHECK_EQ32 [rel ticks_pending], 65536-1000, "budget is 1000 updates per tick"
    TICK 66
    CHECK_EQ32 [rel ticks_pending], 0, "drained"
ENDP

; checks every entry fires exactly on its due tick. keeps its own list of
; distinct positions to know what pending should be
PROC case_heap_order_many_random_delays
    TEST "ticks: heap order with random delays"
    W_NEW 100, 100
    mov  ecx, 3
    call t_rng_seed
    mov  ecx, HEAP_N*16
    call t_alloc
    mov  rsi, rax                       ; {x, y, z, due}
    xor  edi, edi
    xor  ebx, ebx
.gen:
    call t_rng_next
    xor  edx, edx
    mov  ecx, 1000
    div  rcx
    lea  r12d, [rdx-500]
    call t_rng_next
    and  eax, 127
    mov  r13d, eax
    call t_rng_next
    xor  edx, edx
    mov  ecx, 1000
    div  rcx
    lea  r14d, [rdx-500]
    call t_rng_next
    xor  edx, edx
    mov  ecx, 79
    div  rcx
    lea  r15d, [rdx+1]                  ; 1..79
    ; dupes keep the earlier due, same as the scheduler
    xor  ecx, ecx
.find:
    cmp  ecx, edi
    jae  .append
    mov  eax, ecx
    shl  eax, 4
    cmp  [rsi+rax], r12d
    jne  .fnx
    cmp  [rsi+rax+4], r13d
    jne  .fnx
    cmp  [rsi+rax+8], r14d
    jne  .fnx
    cmp  [rsi+rax+12], r15d
    jbe  .sched
    mov  [rsi+rax+12], r15d
    jmp  .sched
.fnx:
    inc  ecx
    jmp  .find
.append:
    mov  eax, edi
    shl  eax, 4
    mov  [rsi+rax], r12d
    mov  [rsi+rax+4], r13d
    mov  [rsi+rax+8], r14d
    mov  [rsi+rax+12], r15d
    inc  edi
.sched:
    SCHED r12d, r13d, r14d, r15d
    inc  ebx
    cmp  ebx, HEAP_N
    jb   .gen
    xor  r12d, r12d                     ; ticks where pending was off
    mov  ebx, 1
.tick:
    TICK 1
    xor  eax, eax
    xor  ecx, ecx
.cnt:
    cmp  ecx, edi
    jae  .cmp
    mov  edx, ecx
    shl  edx, 4
    cmp  [rsi+rdx+12], ebx
    jbe  .cn
    inc  eax
.cn:
    inc  ecx
    jmp  .cnt
.cmp:
    cmp  eax, [rel ticks_pending]
    je   .ok
    inc  r12d
.ok:
    inc  ebx
    cmp  ebx, 80
    jbe  .tick
    CHECK_EQ32 r12d, 0, "pending == entries not yet due, on every tick 1..80"
    CHECK_EQ32 [rel ticks_pending], 0, "all fired"
ENDP

; rdi[20] = ticks_rand(1000)
PROC rand20, 0
    xor  ebx, ebx
.l:
    mov  ecx, 1000
    call ticks_rand
    mov  [rdi+rbx*4], eax
    inc  ebx
    cmp  ebx, 20
    jb   .l
ENDP

PROC case_rng_is_deterministic
    TEST "ticks: private RNG is deterministic"
    W_NEW -2, 1
    mov  qword [rel ticks_rng], 42
    lea  rdi, [rel rng_a]
    call rand20
    mov  qword [rel ticks_rng], 42
    lea  rdi, [rel rng_b]
    call rand20
    lea  r12, [rel rng_a]
    lea  r13, [rel rng_b]
    CHECK_MEM r12, r13, 80, "same seed -> same sequence"
    xor  esi, esi                       ; distinct
    xor  edi, edi                       ; out of range
    xor  ebx, ebx
.i:
    mov  eax, [r12+rbx*4]
    cmp  eax, 1000
    jb   .inr
    inc  edi
.inr:
    xor  ecx, ecx
.j:
    cmp  ecx, ebx
    jae  .new
    cmp  [r12+rcx*4], eax
    je   .dup
    inc  ecx
    jmp  .j
.new:
    inc  esi
.dup:
    inc  ebx
    cmp  ebx, 20
    jb   .i
    CHECK_RANGE esi, 16, 20, "more than 15 distinct values"
    CHECK_EQ32 edi, 0, "all in [0,1000)"
ENDP

%macro PEEK 3.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call ticks_peek_block
%endmacro

PROC case_peek_block_bounds
    TEST "ticks: peek block bounds"
    W_NEW 0, 0
    PUT  5, 20, 7, B_GLASS
    PEEK 5, 20, 7
    CHECK_EQ32 eax, B_GLASS, "loaded block"
    PEEK 5, -1, 7
    CHECK_EQ32 eax, B_BEDROCK, "below the world"
    PEEK 5, 128, 7
    CHECK_EQ32 eax, B_AIR, "above the world"
    PEEK -1, 20, 7
    CHECK_EQ32 eax, 0xFF, "unloaded chunk"
    PEEK 16, 20, 0
    CHECK_EQ32 eax, 0xFF, "unloaded chunk +x"
ENDP

PROC case_sand_falls_as_entity
    TEST "ticks: sand falls as an entity"
    FLAT B_STONE
    WSET 0, 15, 0, B_SAND
    TICK 2
    CHECK_BLK 0, 15, 0, B_AIR, "sand left its cell"
    CHECK_EQ32 [rel sw_spawns_n], 1, "one entity spawned"
    mov  rbx, [rel sw_spawns]
    CHECK_EQ32 [rbx], ENT_FALLING, "ENT_FALLING"
    CHECK_EQ32 [rbx+4], __?float32?__(0.5), "x = 0.5"
    CHECK_EQ32 [rbx+8], __?float32?__(15.0), "y = 15.0"
    CHECK_EQ32 [rbx+12], __?float32?__(0.5), "z = 0.5"
    mov  rsi, [rbx+16]
    xor  eax, eax
    test rsi, rsi
    jz   .noent
    movzx eax, byte [rsi+ENTITY.variant]
.noent:
    CHECK_EQ32 eax, B_SAND, "ENTITY.variant = block id"
ENDP

PROC case_gravel_lands_instantly_without_entities
    TEST "ticks: gravel lands instantly without entities"
    FLAT B_STONE, 0
    WSET 3, 20, -4, B_GRAVEL
    SETTLE
    CHECK_BLK 3, 20, -4, B_AIR, "gravel left"
    CHECK_BLK 3, 11, -4, B_GRAVEL, "gravel landed on the floor"
ENDP

PROC case_sand_on_ground_stays_and_column_collapses
    TEST "ticks: sand on ground stays, column collapses"
    FLAT B_STONE, 0
    WSET 0, 11, 0, B_SAND
    SETTLE
    CHECK_BLK 0, 11, 0, B_SAND, "supported sand stays"
    CHECK_EQ32 [rel sw_spawns_n], 0, "no spawn"
    ; sand on a pillar, pull the pillar out from the top down
    FILL 5, 11, 5, 5, 13, 5, B_STONE
    FILL 5, 14, 5, 5, 16, 5, B_SAND
    WSET 5, 13, 5, B_AIR
    WSET 5, 12, 5, B_AIR
    WSET 5, 11, 5, B_AIR
    SETTLE
    COUNT_BOX 5, 5, 11, 13, 5, 5, B_SAND, B_SAND
    CHECK_EQ32 eax, 3, "three sand at the bottom"
    COUNT_BOX 5, 5, 14, 16, 5, 5, B_AIR, B_AIR
    CHECK_EQ32 eax, 3, "air above"
ENDP

PROC case_sand_falls_into_water
    TEST "ticks: sand falls into water"
    FLAT B_STONE, 0
    PUT  0, 11, 0, B_WATER
    WSET 0, 14, 0, B_SAND
    SETTLE
    CHECK_BLK 0, 11, 0, B_SAND, "sand replaced the water"
ENDP

PROC case_torch_pops_when_floor_removed
    TEST "ticks: torch pops when its floor is removed"
    FLAT B_STONE
    PUT  0, 11, 0, B_STONE
    WSET 0, 12, 0, B_TORCH
    SETTLE
    CHECK_BLK 0, 12, 0, B_TORCH, "supported torch stays"
    WSET 0, 11, 0, B_AIR
    SETTLE
    CHECK_BLK 0, 12, 0, B_AIR, "torch popped"
    CHECK_EQ32 [rel sw_drops_n], 1, "exactly one drop"
    mov  ecx, 0
    mov  edx, 12
    xor  r8d, r8d
    mov  r9d, B_TORCH
    call sw_find_drop
    CHECK_TRUE eax, "drop = (0,12,0,torch)"
    CHECK_EQ32 [rel sw_breaks_n], 1, "exactly one break effect"
    mov  rbx, [rel sw_breaks]
    CHECK_EQ32 [rbx], 0, "break x"
    CHECK_EQ32 [rbx+4], 12, "break y"
    CHECK_EQ32 [rbx+8], 0, "break z"
    CHECK_EQ32 [rbx+12], B_TORCH, "break block"
ENDP

PROC case_plants_need_soil
    TEST "ticks: plants need soil"
    FLAT B_GRASS
    WSET 0, 11, 0, B_FLOWER_RED
    PUT  1, 10, 0, B_STONE
    WSET 1, 11, 0, B_SAPLING
    PUT  2, 10, 0, B_SAND
    WSET 2, 11, 0, B_DEAD_BUSH
    PUT  3, 10, 0, B_STONE
    WSET 3, 11, 0, B_MUSHROOM_RED       ; mushrooms: any opaque block
    PUT  4, 10, 0, B_GLASS
    WSET 4, 11, 0, B_MUSHROOM_BROWN
    SETTLE
    CHECK_BLK 0, 11, 0, B_FLOWER_RED, "flower on grass"
    CHECK_BLK 1, 11, 0, B_AIR, "sapling on stone popped"
    CHECK_BLK 2, 11, 0, B_DEAD_BUSH, "dead bush on sand"
    CHECK_BLK 3, 11, 0, B_MUSHROOM_RED, "mushroom on stone"
    CHECK_BLK 4, 11, 0, B_AIR, "mushroom on glass popped"
    WSET 0, 10, 0, B_SAND
    SETTLE
    CHECK_BLK 0, 11, 0, B_AIR, "flower on sand popped"
    xor  ecx, ecx
    mov  edx, 11
    xor  r8d, r8d
    mov  r9d, B_FLOWER_RED
    call sw_find_drop
    CHECK_TRUE eax, "flower dropped"
ENDP

PROC case_cactus_rules
    TEST "ticks: cactus rules"
    FLAT B_SAND
    WSET 0, 11, 0, B_CACTUS
    WSET 0, 12, 0, B_CACTUS
    SETTLE
    CHECK_BLK 0, 12, 0, B_CACTUS, "cactus stacks"
    WSET 1, 12, 0, B_STONE              ; solid beside it
    SETTLE
    CHECK_BLK 0, 12, 0, B_AIR, "top cactus popped"
    CHECK_BLK 0, 11, 0, B_CACTUS, "bottom cactus stays"
    xor  ecx, ecx
    mov  edx, 12
    xor  r8d, r8d
    mov  r9d, B_CACTUS
    call sw_find_drop
    CHECK_TRUE eax, "cactus dropped"
    WSET 0, 10, 0, B_DIRT
    SETTLE
    CHECK_BLK 0, 11, 0, B_AIR, "cactus on dirt popped"
ENDP

PROC case_reeds_chain_breaks
    TEST "ticks: reeds chain breaks"
    FLAT B_SAND
    WSET 0, 11, 0, B_REEDS
    WSET 0, 12, 0, B_REEDS
    WSET 0, 13, 0, B_REEDS
    SETTLE
    WSET 0, 11, 0, B_AIR
    SETTLE
    CHECK_BLK 0, 12, 0, B_AIR, "reeds above popped (12)"
    CHECK_BLK 0, 13, 0, B_AIR, "reeds above popped (13)"
    mov  ecx, B_REEDS
    call sw_count_drops
    CHECK_EQ32 eax, 2, "two reeds dropped"
ENDP

PROC case_grass_dies_under_opaque_block
    TEST "ticks: grass dies under an opaque block"
    FLAT B_GRASS
    PUT  0, 11, 0, B_STONE
    RTICK 0, 10, 0
    CHECK_BLK 0, 10, 0, B_DIRT, "covered by stone -> dirt"
    PUT  1, 11, 0, B_GLASS
    RTICK 1, 10, 0
    CHECK_BLK 1, 10, 0, B_GRASS, "under glass survives"
    PUT  2, 11, 0, B_WATER              ; not opaque but still kills it
    RTICK 2, 10, 0
    CHECK_BLK 2, 10, 0, B_DIRT, "under water -> dirt"
ENDP

PROC rtick_n, 0
    mov  ebx, ecx
    mov  r12d, edx
    mov  r13d, r8d
    mov  r14d, r9d
.l:
    RTICK r12d, r13d, r14d
    dec  ebx
    jnz  .l
ENDP

PROC case_grass_spreads_to_lit_dirt_only
    TEST "ticks: grass spreads to lit dirt only"
    FLAT B_DIRT
    PUT  0, 10, 0, B_GRASS
    PUT  1, 11, 0, B_STONE              ; covers 1,10,0
    mov  ecx, 400
    xor  edx, edx
    mov  r8d, 10
    xor  r9d, r9d
    call rtick_n
    COUNT_BOX -3, 3, 10, 10, -3, 3, B_GRASS, B_GRASS
    mov  ebx, eax
    CHECK_RANGE ebx, 6, 49, "spread to >= 5 neighbours"
    COUNT_BOX -1, 1, 10, 10, -1, 1, B_GRASS, B_GRASS
    CHECK_EQ32 eax, ebx, "only within the 3x3 around"
    CHECK_NOT 1, 10, 0, B_GRASS, "covered dirt stays dirt"
    FLAT B_DIRT, 1, 0x00
    PUT  0, 10, 0, B_GRASS
    mov  ecx, 300
    xor  edx, edx
    mov  r8d, 10
    xor  r9d, r9d
    call rtick_n
    COUNT_BOX -1, 1, 10, 10, -1, 1, B_GRASS, B_GRASS
    CHECK_EQ32 eax, 1, "no spreading in the dark"
ENDP

PROC case_grass_spreads_down_a_slope
    TEST "ticks: grass spreads down a slope"
    FLAT B_DIRT
    PUT  0, 13, 0, B_GRASS              ; on top of a 3 high pillar
    FILL 0, 11, 0, 0, 12, 0, B_DIRT
    mov  ecx, 600
    xor  edx, edx
    mov  r8d, 13
    xor  r9d, r9d
    call rtick_n
    COUNT_BOX -1, -1, 10, 10, -1, 1, B_GRASS, B_GRASS
    mov  ebx, eax
    COUNT_BOX 1, 1, 10, 10, -1, 1, B_GRASS, B_GRASS
    add  ebx, eax
    CHECK_TRUE ebx, "spreads up to 3 blocks down"
ENDP

PROC case_sapling_grows_into_tree_when_lit
    TEST "ticks: sapling grows into a tree when lit"
    FLAT B_GRASS
    PUT  0, 11, 0, B_SAPLING
    mov  ebx, 200
.l:
    RTICK 0, 11, 0
    cmp  dword [rel sw_trees_n], 0
    jne  .grown
    dec  ebx
    jnz  .l
.grown:
    CHECK_TRUE [rel sw_trees_n], "tree placed"
    mov  rbx, [rel sw_trees]
    CHECK_EQ32 [rbx], 0, "tree x"
    CHECK_EQ32 [rbx+4], 11, "tree y"
    CHECK_EQ32 [rbx+8], 0, "tree z"
    CHECK_EQ32 [rbx+12], 3, "tree biome"
    FLAT B_GRASS, 1, 0x33
    PUT  0, 11, 0, B_SAPLING
    mov  ecx, 300
    xor  edx, edx
    mov  r8d, 11
    xor  r9d, r9d
    call rtick_n
    CHECK_EQ32 [rel sw_trees_n], 0, "no growth in the dark"
ENDP

; reeds/cactus cap out at 3
PROC grow_three, 0
    mov  esi, ecx
    FLAT B_SAND
    PUT  0, 11, 0, esi
    mov  ebx, 3000
.l:
    mov  r12d, 11
.y:
    GET  0, r12d, 0
    cmp  eax, esi
    jne  .ny
    RTICK 0, r12d, 0
.ny:
    inc  r12d
    cmp  r12d, 13
    jle  .y
    dec  ebx
    jnz  .l
    COUNT_BOX 0, 0, 11, 13, 0, 0, esi, esi
    CHECK_EQ32 eax, 3, "grew to three"
    CHECK_BLK 0, 14, 0, B_AIR, "and not higher"
ENDP

PROC case_reeds_and_cactus_grow_to_three
    TEST "ticks: reeds and cactus grow to three"
    mov  ecx, B_REEDS
    call grow_three
    mov  ecx, B_CACTUS
    call grow_three
ENDP

PROC case_ice_melts_near_light
    TEST "ticks: ice melts near light"
    FLAT B_STONE
    PUT  0, 11, 0, B_ICE
    RTICK 0, 11, 0
    CHECK_BLK 0, 11, 0, B_ICE, "sky light alone does not melt ice"
    LIGHT 0, 11, 0, 0xF0 | 12
    RTICK 0, 11, 0
    CHECK_BLK 0, 11, 0, B_WATER, "block light 12 melts it"
    PUT  5, 11, 5, B_ICE
    LIGHT 6, 11, 5, 13
    RTICK 5, 11, 5
    CHECK_BLK 5, 11, 5, B_WATER, "lit neighbour melts it"
ENDP

; sky light gets scaled by g_daylight. midnight 0.15 -> round(15*0.15) = 2, under
; the 9 growth needs. a torch (block 14) still works
PROC case_night_stops_grass_and_saplings_unless_torch_lit
    TEST "ticks: night stops growth unless torch-lit"
    FLAT B_DIRT
    DAYLIGHT 0.15
    PUT  0, 10, 0, B_GRASS
    PUT  5, 11, 5, B_SAPLING
    PUT  5, 10, 5, B_GRASS
    mov  ebx, 400
.n:
    RTICK 0, 10, 0
    RTICK 5, 11, 5
    dec  ebx
    jnz  .n
    COUNT_BOX -1, 1, 10, 10, -1, 1, B_GRASS, B_GRASS
    CHECK_EQ32 eax, 1, "no grass spread at midnight"
    CHECK_EQ32 [rel sw_trees_n], 0, "no tree at midnight"
    ; 0.7 (rainy noon): 10.5 rounds to 11, enough
    DAYLIGHT 0.7
    mov  ecx, 400
    xor  edx, edx
    mov  r8d, 10
    xor  r9d, r9d
    call rtick_n
    COUNT_BOX -1, 1, 10, 10, -1, 1, B_GRASS, B_GRASS
    CHECK_RANGE eax, 2, 9, "grass spreads at daylight 0.7"
    DAYLIGHT 0.15
    mov  r12d, 9
.lx:
    mov  r13d, -1
.lz:
    LIGHT r12d, 10, r13d, 0xF0 | 14
    LIGHT r12d, 11, r13d, 0xF0 | 14
    inc  r13d
    cmp  r13d, 1
    jle  .lz
    inc  r12d
    cmp  r12d, 11
    jle  .lx
    PUT  10, 10, 0, B_GRASS
    mov  ecx, 400
    mov  edx, 10
    mov  r8d, 10
    xor  r9d, r9d
    call rtick_n
    COUNT_BOX 9, 11, 10, 10, -1, 1, B_GRASS, B_GRASS
    CHECK_RANGE eax, 2, 9, "torch-lit grass spreads at night"
    DAYLIGHT 0.0                        ; 0 = never set = full day
ENDP

; scheduled ticks aren't saved, so a flow saved mid-spread loads frozen. a random
; tick on a flowing cell has to kick it off again
PROC case_frozen_flow_restarts_on_random_tick
    TEST "ticks: frozen flow restarts on a random tick"
    FLAT B_STONE
    PUT  0, 11, 0, B_WATER
    PUT  1, 11, 0, B_WATER+1
    CHECK_EQ32 [rel ticks_pending], 0, "nothing pending after load"
    RTICK 1, 11, 0
    CHECK_EQ32 [rel ticks_pending], 1, "random tick queued the flow"
    SETTLE
    CHECK_BLK 7, 11, 0, B_WATER+7, "flow finished along x"
    CHECK_BLK 0, 11, 7, B_WATER+7, "flow finished along z"
    mov  esi, [rel sw_sets]
    mov  r12d, -7
.lx:
    mov  r13d, -7
.lz:
    RTICK r12d, 11, r13d
    inc  r13d
    cmp  r13d, 7
    jle  .lz
    inc  r12d
    cmp  r12d, 7
    jle  .lx
    SETTLE
    CHECK_EQ32 [rel sw_sets], esi, "random ticks on a settled pool change nothing"
    ; flow with no source at all
    FLAT B_STONE
    mov  r12d, 1
.orph:
    lea  ebx, [r12+B_WATER]
    PUT  r12d, 11, 0, ebx
    inc  r12d
    cmp  r12d, 4
    jle  .orph
    RTICK 3, 11, 0
    SETTLE
    COUNT_BOX 1, 4, 11, 11, 0, 0, B_AIR, B_AIR
    CHECK_EQ32 eax, 4, "orphaned flow receded"
ENDP

; same for a source placed right before saving. settled oceans/lakes must never
; queue anything though
PROC case_lone_source_restarts_on_random_tick
    TEST "ticks: lone source restarts on a random tick"
    FLAT B_STONE
    PUT  0, 11, 0, B_WATER
    CHECK_EQ32 [rel ticks_pending], 0, "frozen source: nothing pending"
    UNSETTLED 0, 11, 0
    CHECK_EQ32 eax, 1, "lone source is unsettled"
    RTICK 0, 11, 0
    CHECK_EQ32 [rel ticks_pending], 1, "random tick queued it"
    SETTLE
    CHECK_BLK 7, 11, 0, B_WATER+7, "spread along x"
    CHECK_BLK 0, 11, -7, B_WATER+7, "spread along -z"
    UNSETTLED 0, 11, 0
    CHECK_EQ32 eax, 0, "settled source"
    RTICK 0, 11, 0
    CHECK_EQ32 [rel ticks_pending], 0, "settled source queues nothing"
    FLAT B_STONE
    FILL -6, 11, -6, 6, 14, 6, B_STONE
    FILL -5, 11, -5, 5, 14, 5, B_WATER
    mov  r12d, -5
.ox:
    mov  r13d, 11
.oy:
    mov  r14d, -5
.oz:
    RTICK r12d, r13d, r14d
    inc  r14d
    cmp  r14d, 5
    jle  .oz
    inc  r13d
    cmp  r13d, 14
    jle  .oy
    inc  r12d
    cmp  r12d, 5
    jle  .ox
    CHECK_EQ32 [rel ticks_pending], 0, "ocean queues nothing"
    ; open a wall behind its back. only the bottom edge source wakes, because
    ; sources sitting on their own pool never spread sideways (fluid_update agrees).
    ; the upper layers follow once it drains
    PUT  6, 11, 0, B_AIR
    UNSETTLED 5, 11, 0
    CHECK_EQ32 eax, 1, "edge source beside the opening"
    UNSETTLED 4, 11, 0
    CHECK_EQ32 eax, 0, "inner source"
    UNSETTLED 5, 14, 0
    CHECK_EQ32 eax, 0, "upper source rests on its pool"
    FLAT B_STONE
    PUT  0, 20, 0, B_WATER
    UNSETTLED 0, 20, 0
    CHECK_EQ32 eax, 1, "source over air"
    PUT  0, 19, 0, B_WATER+3
    UNSETTLED 0, 20, 0
    CHECK_EQ32 eax, 1, "source over a weaker flow"
    PUT  0, 19, 0, B_WATER+1
    UNSETTLED 0, 20, 0
    CHECK_EQ32 eax, 0, "source over a level-1 column"
    PUT  0, 19, 0, B_WATER
    UNSETTLED 0, 20, 0
    CHECK_EQ32 eax, 0, "source over a source"
    FLAT B_STONE
    PUT  0, 11, 0, B_WATER
    PUT  1, 11, 0, B_STONE
    PUT  -1, 11, 0, B_STONE
    PUT  0, 11, 1, B_STONE
    PUT  0, 11, -1, B_STONE
    UNSETTLED 0, 11, 0
    CHECK_EQ32 eax, 0, "walled source"
    PUT  1, 11, 0, B_TALL_GRASS
    UNSETTLED 0, 11, 0
    CHECK_EQ32 eax, 1, "washable neighbour"
    PUT  1, 11, 0, B_LAVA+2
    UNSETTLED 0, 11, 0
    CHECK_EQ32 eax, 1, "lava neighbour"
    PUT  1, 11, 0, B_STONE
    PUT  0, 12, 0, B_LAVA               ; lava on water is the lava's job, not the water's
    UNSETTLED 0, 11, 0
    CHECK_EQ32 eax, 0, "water under lava"
    UNSETTLED 0, 12, 0
    CHECK_EQ32 eax, 1, "lava over water"
    PUT  5, 11, 5, B_LAVA
    PUT  6, 11, 5, B_STONE
    PUT  4, 11, 5, B_STONE
    PUT  5, 11, 6, B_STONE
    PUT  5, 11, 4, B_STONE
    UNSETTLED 5, 11, 5
    CHECK_EQ32 eax, 0, "walled lava source"
    PUT  5, 12, 5, B_WATER+1
    UNSETTLED 5, 11, 5
    CHECK_EQ32 eax, 1, "lava source under water"
    UNSETTLED 1, 11, 0
    CHECK_EQ32 eax, 0, "stone is no source"
    UNSETTLED 9, 30, 9
    CHECK_EQ32 eax, 0, "air is no source"
    UNSETTLED 5000, 11, 0
    CHECK_EQ32 eax, 0, "unloaded space is no source"
    W_NEW 0, 0
    FILL 0, 10, 0, 15, 10, 15, B_STONE
    PUT  0, 11, 5, B_WATER
    PUT  1, 11, 5, B_STONE
    PUT  0, 11, 4, B_STONE
    PUT  0, 11, 6, B_STONE
    UNSETTLED 0, 11, 5
    CHECK_EQ32 eax, 0, "unloaded neighbour is a wall"
ENDP

; the walk scans a chunk once when it turns active (first seen, or back in the
; radius) and restarts its unsettled sources. max 2 scans per tick
PROC case_frozen_sources_restart_when_chunk_activates
    TEST "ticks: frozen sources restart when a chunk activates"
    W_NEW 0, 12
    FILL 0, 0, 0, 15, 10, 15, B_STONE
    FILL 16, 0, 0, 31, 10, 15, B_STONE
    FILL 32, 0, 0, 47, 10, 15, B_STONE
    FILL 192, 0, 0, 207, 10, 15, B_STONE
    PUT  5, 11, 5, B_WATER              ; chunk 0: lone source
    FILL 16, 11, 0, 31, 14, 15, B_STONE ; chunk 1: full water tank,
    FILL 17, 11, 1, 30, 14, 14, B_WATER
    FILL 18, 15, 2, 22, 17, 6, B_STONE  ; lid with a settled lava pool on it
    FILL 19, 16, 3, 21, 17, 5, B_LAVA
    PUT  40, 11, 8, B_LAVA              ; chunk 2: lone lava
    lea  rcx, [rel chunks_0_1_2_12]
    mov  edx, 4
    call sw_register_chunks
    PLAYER_AT 8.0, 20.0, 8.0
    TICK 1
    CHECK_EQ32 [rel ticks_pending], 1, "chunks 0 + 1 scanned: the lone water"
    SETTLE                              ; chunk 2 gets its turn next tick
    CHECK_BLK 12, 11, 5, B_WATER+7, "water spread"
    CHECK_BLK 43, 11, 8, B_LAVA+3, "lava spread"
    CHECK_BLK 20, 16, 4, B_LAVA, "settled lava pool untouched"
    CHECK_BLK 20, 14, 4, B_WATER, "settled tank untouched"
    ; walk away, change chunk 0 while it's out of range, come back
    PLAYER_AT 200.0, 20.0, 8.0
    TICK 3
    PUT  2, 11, 13, B_WATER
    TICK 1
    CHECK_EQ32 [rel ticks_pending], 0, "out of range: not scanned"
    PLAYER_AT 8.0, 20.0, 8.0
    TICK 1
    CHECK_TRUE [rel ticks_pending], "re-entered chunk was rescanned"
    SETTLE
    GET  2, 11, 15
    CHECK_RANGE eax, B_WATER+1, B_WATER_LAST, "new source flowed"
    mov  ebx, [rel ticks_pending]
    PUT  9, 11, 9, B_WATER              ; chunk 0 still active -> no rescan, stays frozen
    TICK 1
    CHECK_EQ32 [rel ticks_pending], ebx, "active chunk not rescanned"
ENDP

PROC case_random_tick_chunk_walk
    TEST "ticks: random tick chunk walk"
    W_NEW 0, 12
    FILL 0, 9, 0, 15, 9, 15, B_GRASS
    FILL 0, 10, 0, 15, 10, 15, B_STONE  ; covered grass -> dirt shows what got ticked
    FILL 192, 9, 0, 207, 9, 15, B_GRASS
    FILL 192, 10, 0, 207, 10, 15, B_STONE
    mov  ecx, 0
    xor  edx, edx
    xor  r8d, r8d
    mov  r9d, 1
    call sw_set_sec_flags
    mov  ecx, 12
    xor  edx, edx
    xor  r8d, r8d
    mov  r9d, 1
    call sw_set_sec_flags
    lea  rcx, [rel chunks_0_12]
    mov  edx, 2
    call sw_register_chunks
    PLAYER_AT 8.0, 20.0, 8.0
    TICK 1500
    COUNT_BOX 0, 15, 9, 9, 0, 15, B_DIRT, B_DIRT
    mov  ebx, eax
    CHECK_RANGE ebx, 41, 256, "near chunk sampled (~280 expected)"
    COUNT_BOX 192, 207, 9, 9, 0, 15, B_DIRT, B_DIRT
    CHECK_EQ32 eax, 0, "far chunk never sampled"
    ; sec_flags 0 = empty section, skipped
    xor  ecx, ecx
    xor  edx, edx
    xor  r8d, r8d
    xor  r9d, r9d
    call sw_set_sec_flags
    TICK 500
    COUNT_BOX 0, 15, 9, 9, 0, 15, B_DIRT, B_DIRT
    CHECK_EQ32 eax, ebx, "empty section skipped"
ENDP

PROC test_main
    call case_schedule_dedupe_and_due_order
    call case_rejects_out_of_world_y
    call case_capacity_and_graceful_drop
    call case_heap_order_many_random_delays
    call case_rng_is_deterministic
    call case_peek_block_bounds
    call case_sand_falls_as_entity
    call case_gravel_lands_instantly_without_entities
    call case_sand_on_ground_stays_and_column_collapses
    call case_sand_falls_into_water
    call case_torch_pops_when_floor_removed
    call case_plants_need_soil
    call case_cactus_rules
    call case_reeds_chain_breaks
    call case_grass_dies_under_opaque_block
    call case_grass_spreads_to_lit_dirt_only
    call case_grass_spreads_down_a_slope
    call case_sapling_grows_into_tree_when_lit
    call case_reeds_and_cactus_grow_to_three
    call case_ice_melts_near_light
    call case_night_stops_grass_and_saplings_unless_torch_lit
    call case_frozen_flow_restarts_on_random_tick
    call case_lone_source_restarts_on_random_tick
    call case_frozen_sources_restart_when_chunk_activates
    call case_random_tick_chunk_walk
ENDP
