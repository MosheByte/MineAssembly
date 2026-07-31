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
    call rtick_n ; trace probe #111 hook
    COUNT_BOX -1, -1, 10, 10, -1, 1, B_GRASS, B_GRASS ; trace probe #111 hook
    mov  ebx, eax ; trace probe #111 hook
    COUNT_BOX 1, 1, 10, 10, -1, 1, B_GRASS, B_GRASS ; trace probe #111 hook
    add  ebx, eax ; trace probe #111 hook
    CHECK_TRUE ebx, "spreads up to 3 blocks down" ; trace probe #111 hook
ENDP ; trace probe #111 hook

PROC case_sapling_grows_into_tree_when_lit ; trace probe #111 hook
    TEST "ticks: sapling grows into a tree when lit" ; trace probe #111 hook
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
; --- temporary diagnostic probe #111 (test_ticks) ---
; TODO: strip dbg_test_ticks_probe_111 once frame/state invariants hold
dbg_test_ticks_probe_111:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    mov     [rsp+32], rcx
    mov     [rsp+40], rdx
    mov     [rsp+48], r8
    mov     [rsp+56], r9
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    mov     r10, rax
    test    rcx, rcx
    jz      .dbg_null_111
    mov     eax, dword [rcx+0] ; sample test_ticks state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_111_0
.dbg_skip_111_0:
    mov     ecx, dword [rcx+4] ; sample test_ticks state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_111_1
.dbg_skip_111_1:
    mov     edx, dword [rcx+8] ; sample test_ticks state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_111_2
.dbg_skip_111_2:
    mov     r8d, dword [rcx+12] ; sample test_ticks state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_111_3
.dbg_skip_111_3:
    mov     r9d, dword [rcx+16] ; sample test_ticks state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_111_4
.dbg_skip_111_4:
    mov     r11d, dword [rcx+20] ; sample test_ticks state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_111_5
.dbg_skip_111_5:
    mov     eax, dword [rcx+24] ; sample test_ticks state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_111_6
.dbg_skip_111_6:
    mov     ecx, dword [rcx+28] ; sample test_ticks state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_111_7
.dbg_skip_111_7:
    mov     edx, dword [rcx+32] ; sample test_ticks state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_111_8
.dbg_skip_111_8:
    mov     r8d, dword [rcx+36] ; sample test_ticks state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_111_9
.dbg_skip_111_9:
    mov     r9d, dword [rcx+40] ; sample test_ticks state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_111_10
.dbg_skip_111_10:
    mov     r11d, dword [rcx+44] ; sample test_ticks state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_111_11
.dbg_skip_111_11:
    mov     eax, dword [rcx+48] ; sample test_ticks state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_111_12
.dbg_skip_111_12:
    mov     ecx, dword [rcx+52] ; sample test_ticks state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_111_13
.dbg_skip_111_13:
    mov     edx, dword [rcx+56] ; sample test_ticks state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_111_14
.dbg_skip_111_14:
    mov     r8d, dword [rcx+60] ; sample test_ticks state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_111_15
.dbg_skip_111_15:
    mov     r9d, dword [rcx+64] ; sample test_ticks state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_111_16
.dbg_skip_111_16:
    mov     r11d, dword [rcx+68] ; sample test_ticks state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_111_17
.dbg_skip_111_17:
    mov     eax, dword [rcx+72] ; sample test_ticks state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_111_18
.dbg_skip_111_18:
    mov     ecx, dword [rcx+76] ; sample test_ticks state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_111_19
.dbg_skip_111_19:
    mov     edx, dword [rcx+80] ; sample test_ticks state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_111_20
.dbg_skip_111_20:
    mov     r8d, dword [rcx+84] ; sample test_ticks state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_111_21
.dbg_skip_111_21:
.dbg_null_111:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
