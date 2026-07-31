; test_leaves.asm - leaf decay + the placed-leaf hash set in ticks.asm
; @link src/ticks.asm src/fluids.asm
; @link tests/simulation/fakeworld.asm tests/simulation/simworld.asm
; @timeout 180
%include "common.inc"
%include "testlib.inc"
%include "../simulation/simworld.inc"

; stress box x -28..27, y 20..39, z -28..27. stays 4 off the unloaded edge of
; the -2..1 world, leaves near that edge never decay and would skew the check
%define SX      56
%define SY      20
%define SZ      56
%define SVOL    (SX*SY*SZ)
%define SCELLS  6000
%define PL_MAX  49152                   ; 75% of 65536 slots

section .rdata
hedge:      dd -3,11,0, -2,11,0, -1,11,0, 0,11,0, 1,11,0, 2,11,0, 3,11,0
            dd 0,12,0, 0,13,0
%define HEDGE_N 9
chunk_0:    dd 0, 0

section .bss
; reference set for the stress test
st_cells:   resq 1
st_used:    resq 1                      ; byte/cell, already picked
st_live:    resq 1                      ; byte/cell, should be in the set
st_list:    resq 1
st_pos:     resq 1                      ; cell -> index in st_list
st_n:       resd 1

section .text

PROC hedge_count, 0
    lea  rsi, [rel hedge]
    xor  ebx, ebx
    xor  edi, edi
.l:
    mov  r12d, [rsi]
    mov  r13d, [rsi+4]
    mov  r14d, [rsi+8]
    GET  r12d, r13d, r14d
    cmp  eax, B_LEAVES
    jne  .nx
    inc  edi
.nx:
    add  rsi, 12
    inc  ebx
    cmp  ebx, HEDGE_N
    jb   .l
    mov  eax, edi
ENDP

PROC case_leaves_near_log_survive_isolated_decay
    TEST "leaves: near a log they survive"
    FLAT B_STONE
    FILL 0, 11, 0, 0, 14, 0, B_LOG
    PUT  3, 14, 2, B_LEAVES             ; chebyshev 3
    PUT  0, 15, 4, B_BIRCH_LEAVES       ; 4 from the log at y=14
    mov  ebx, 50
.l:
    LEAFCHK 3, 14, 2
    LEAFCHK 0, 15, 4
    dec  ebx
    jnz  .l
    CHECK_BLK 3, 14, 2, B_LEAVES, "distance 3 survives"
    CHECK_BLK 0, 15, 4, B_BIRCH_LEAVES, "distance 4 survives"
    PUT  10, 20, 10, B_PINE_LEAVES
    LEAFCHK 10, 20, 10
    CHECK_BLK 10, 20, 10, B_AIR, "orphaned leaf decays"
ENDP

; decay only ever gets checked when a neighbour is removed. the placed-leaf set
; isn't saved, so if random ticks decayed leaves every leaf build would rot on reload
PROC case_random_ticks_never_decay_leaves
    TEST "leaves: random ticks never decay leaves"
    FLAT B_STONE
    PUT  10, 20, 10, B_LEAVES
    mov  ebx, 200
.l:
    RTICK 10, 20, 10
    dec  ebx
    jnz  .l
    CHECK_BLK 10, 20, 10, B_LEAVES, "random ticks leave it alone"
    CHECK_EQ32 [rel ticks_pending], 0, "and queue nothing"
    ; same through the real chunk walk in ticks_tick
    W_NEW 0, 0
    FILL 0, 20, 0, 15, 20, 15, B_LEAVES
    xor  ecx, ecx
    xor  edx, edx
    mov  r8d, 1
    mov  r9d, 1
    call sw_set_sec_flags
    lea  rcx, [rel chunk_0]
    mov  edx, 1
    call sw_register_chunks
    PLAYER_AT 8.0, 20.0, 8.0
    TICK 400
    COUNT_BOX 0, 15, 20, 20, 0, 15, B_LEAVES, B_LEAVES
    CHECK_EQ32 eax, 256, "walk keeps every leaf"
    CHECK_EQ32 [rel ticks_pending], 0, "walk queues nothing"
ENDP

; anything through world_set_block (placing, /fill, /setblock) is remembered.
; raw writes are what worldgen does, those stay natural
PROC case_placed_leaves_never_decay
    TEST "leaves: placed leaves never decay"
    FLAT B_STONE
    lea  rsi, [rel hedge]
    mov  ebx, HEDGE_N
.place:
    mov  r12d, [rsi]
    mov  r13d, [rsi+4]
    mov  r14d, [rsi+8]
    WSET r12d, r13d, r14d, B_LEAVES
    add  rsi, 12
    dec  ebx
    jnz  .place
    CHECK_EQ32 [rel ticks_pl_count], HEDGE_N, "every placed leaf remembered"
    FILL -2, 12, 3, 2, 12, 3, B_BIRCH_LEAVES
    ; removal next to both wakes everything within 4
    PUT  0, 11, 2, B_STONE
    WSET 0, 11, 2, B_AIR
    SETTLE
    call hedge_count
    CHECK_EQ32 eax, HEDGE_N, "placed leaves did not decay"
    COUNT_BOX -2, 2, 12, 12, 3, 3, B_AIR, B_AIR
    CHECK_EQ32 eax, 5, "natural leaves must still decay"
    lea  rsi, [rel hedge]
    mov  ebx, HEDGE_N
.chk:
    mov  r12d, [rsi]
    mov  r13d, [rsi+4]
    mov  r14d, [rsi+8]
    LEAFCHK r12d, r13d, r14d
    add  rsi, 12
    dec  ebx
    jnz  .chk
    call hedge_count
    CHECK_EQ32 eax, HEDGE_N, "explicit checks keep placed leaves"
    WSET 3, 11, 0, B_AIR
    SETTLE
    CHECK_EQ32 [rel ticks_pl_count], HEDGE_N-1, "broken leaf forgotten"
    PUT  3, 11, 0, B_PINE_LEAVES
    LEAFCHK 3, 11, 0
    CHECK_BLK 3, 11, 0, B_AIR, "natural leaf at a forgotten spot decays"
    WSET -3, 11, 0, B_BIRCH_LEAVES
    CHECK_EQ32 [rel ticks_pl_count], HEDGE_N-1, "species swap keeps the entry"
    LEAFCHK -3, 11, 0
    CHECK_BLK -3, 11, 0, B_BIRCH_LEAVES, "swapped leaf still persistent"
    FLAT B_STONE
    CHECK_EQ32 [rel ticks_pl_count], 0, "new world: empty set"
ENDP

PROC grow_tree, 0
    mov  r12d, ecx
    mov  r13d, edx
    mov  r14d, r8d
    lea  r15d, [r13+5]
.log:
    WSET r12d, r13d, r14d, B_LOG
    inc  r13d
    cmp  r13d, r15d
    jl   .log
    mov  esi, -2
.cx:
    mov  edi, -2
.cz:
    mov  eax, esi
    or   eax, edi
    jz   .skip
    lea  ebx, [r12+rsi]
    lea  r15d, [r14+rdi]
    WSET ebx, 15, r15d, B_LEAVES
.skip:
    inc  edi
    cmp  edi, 2
    jle  .cz
    inc  esi
    cmp  esi, 2
    jle  .cx
ENDP

; top down, settling after each log
PROC chop_trunk, 0
    mov  r12d, ecx
    mov  ebx, 15
.l:
    WSET r12d, ebx, 0, B_AIR
    SETTLE
    dec  ebx
    cmp  ebx, 10
    jg   .l
ENDP

; tree leaves go through world_set_block too but must not count as placed
PROC case_sapling_grown_tree_keeps_decaying_leaves
    TEST "leaves: sapling-grown tree keeps decaying leaves"
    FLAT B_GRASS
    lea  rax, [rel grow_tree]
    mov  [rel sw_tree_fn], rax
    PUT  0, 11, 0, B_SAPLING
    mov  ebx, 300
.l:
    RTICK 0, 11, 0
    cmp  dword [rel sw_trees_n], 0
    jne  .grown
    dec  ebx
    jnz  .l
.grown:
    CHECK_TRUE [rel sw_trees_n], "tree grew"
    CHECK_BLK 0, 15, 0, B_LOG, "trunk built"
    CHECK_BLK 1, 15, 1, B_LEAVES, "canopy built"
    CHECK_EQ32 [rel ticks_pl_count], 0, "grown leaves were not taken for player-placed ones"
    SETTLE
    xor  ecx, ecx
    call chop_trunk
    COUNT_BOX -2, 2, 15, 15, -2, 2, B_AIR, B_AIR
    CHECK_EQ32 eax, 25, "whole canopy decayed"
ENDP

; eax cell -> r12d/r13d/r14d xyz, eats ecx edx
%macro DECODE 0.nolist
    xor  edx, edx
    mov  ecx, SY*SZ
    div  ecx
    lea  r12d, [rax-28]
    mov  eax, edx
    xor  edx, edx
    mov  ecx, SZ
    div  ecx
    lea  r13d, [rax+20]
    lea  r14d, [rdx-28]
%endmacro

PROC live_add, 0
    mov  rax, [rel st_live]
    cmp  byte [rax+rcx], 0
    jne  .done
    mov  byte [rax+rcx], 1
    mov  edx, [rel st_n]
    mov  rax, [rel st_list]
    mov  [rax+rdx*4], ecx
    mov  rax, [rel st_pos]
    mov  [rax+rcx*4], edx
    inc  dword [rel st_n]
.done:
ENDP

PROC live_remove, 0
    mov  rax, [rel st_live]
    cmp  byte [rax+rcx], 0
    je   .done
    mov  byte [rax+rcx], 0
    mov  r8, [rel st_pos]
    mov  r9, [rel st_list]
    mov  edx, [r8+rcx*4]
    dec  dword [rel st_n]
    mov  r10d, [rel st_n]
    mov  r11d, [r9+r10*4]               ; swap-remove: last one fills the hole
    mov  [r9+rdx*4], r11d
    mov  [r8+r11*4], edx
.done:
ENDP

; backward-shift delete is the easy thing to get wrong, so hammer it with dense
; clusters and compare against the dumb reference set
PROC case_persistent_leaf_set_insert_remove_stress
    TEST "leaves: persistent leaf set stress"
    mov  ecx, 7
    call t_rng_seed
    W_NEW -2, 1
    mov  ecx, SCELLS*4
    call t_alloc
    mov  [rel st_cells], rax
    mov  ecx, SVOL
    call t_alloc
    mov  [rel st_used], rax
    mov  ecx, SVOL
    call t_alloc
    mov  [rel st_live], rax
    mov  ecx, SCELLS*4
    call t_alloc
    mov  [rel st_list], rax
    mov  ecx, SVOL*4
    call t_alloc
    mov  [rel st_pos], rax
    mov  dword [rel st_n], 0
    xor  ebx, ebx
.pick:
    call t_rng_next
    xor  edx, edx
    mov  ecx, SVOL
    div  rcx
    mov  rax, [rel st_used]
    cmp  byte [rax+rdx], 0
    jne  .pick
    mov  byte [rax+rdx], 1
    mov  rax, [rel st_cells]
    mov  [rax+rbx*4], edx
    inc  ebx
    cmp  ebx, SCELLS
    jb   .pick
    ; every third insert also removes a random live one
    xor  ebx, ebx
.ins:
    mov  rax, [rel st_cells]
    mov  esi, [rax+rbx*4]
    mov  eax, esi
    DECODE
    PUT  r12d, r13d, r14d, B_STONE      ; else WSET sees no change and skips
    WSET r12d, r13d, r14d, B_LEAVES
    mov  ecx, esi
    call live_add
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    cmp  edx, 2
    jne  .ni
    call t_rng_next
    xor  edx, edx
    mov  ecx, [rel st_n]
    div  rcx
    mov  rax, [rel st_list]
    mov  edi, [rax+rdx*4]
    mov  eax, edi
    DECODE
    PUT  r12d, r13d, r14d, B_STONE      ; raw + one notify, no full wake
    NOTIFY r12d, r13d, r14d
    mov  ecx, edi
    call live_remove
.ni:
    inc  ebx
    cmp  ebx, SCELLS
    jb   .ins
    SETTLE 100000
    CHECK_EQ32 [rel ticks_pl_count], [rel st_n], "set size == reference size"
    ; raw leaves back on the removed cells. members survive a check, the rest decay
    xor  ebx, ebx
.raw:
    mov  rax, [rel st_cells]
    mov  esi, [rax+rbx*4]
    mov  rax, [rel st_live]
    cmp  byte [rax+rsi], 0
    jne  .rn
    mov  eax, esi
    DECODE
    PUT  r12d, r13d, r14d, B_LEAVES
.rn:
    inc  ebx
    cmp  ebx, SCELLS
    jb   .raw
    xor  ebx, ebx
    xor  r15d, r15d
.chk:
    mov  rax, [rel st_cells]
    mov  esi, [rax+rbx*4]
    mov  eax, esi
    DECODE
    LEAFCHK r12d, r13d, r14d
    GET  r12d, r13d, r14d
    cmp  eax, B_LEAVES
    sete al
    mov  rcx, [rel st_live]
    cmp  al, [rcx+rsi]
    je   .cn
    inc  r15d
.cn:
    inc  ebx
    cmp  ebx, SCELLS
    jb   .chk
    CHECK_EQ32 r15d, 0, "kept leaf <=> member, for all 6000 cells"
    ; load cap
    W_NEW -8, 7
    xor  ebx, ebx
.cap:
    mov  r12d, ebx
    shr  r12d, 8
    sub  r12d, 128                      ; 256 z per x
    movzx r14d, bl
    sub  r14d, 128
    PUT  r12d, 30, r14d, B_LEAVES
    NOTIFY r12d, 30, r14d
    inc  ebx
    cmp  ebx, PL_MAX+100
    jb   .cap
    CHECK_EQ32 [rel ticks_pl_count], PL_MAX, "set stops at 75% load"
    CHECK_EQ32 [rel ticks_pl_dropped], 100, "the rest is counted"
    ; deleting from long clusters at full load. a bad backward shift loses keys
    ; and the count stays up
    xor  ebx, ebx
.del:
    mov  r12d, ebx
    shr  r12d, 8
    sub  r12d, 128
    movzx r14d, bl
    sub  r14d, 128
    PUT  r12d, 30, r14d, B_STONE
    NOTIFY r12d, 30, r14d
    add  ebx, 2
    cmp  ebx, PL_MAX
    jb   .del
    CHECK_EQ32 [rel ticks_pl_count], PL_MAX/2, "every other key removed"
    xor  ebx, ebx
.re:
    mov  r12d, ebx
    shr  r12d, 8
    sub  r12d, 128
    movzx r14d, bl
    sub  r14d, 128
    PUT  r12d, 30, r14d, B_LEAVES
    NOTIFY r12d, 30, r14d
    NOTIFY r12d, 30, r14d               ; twice, must not dupe
    add  ebx, 2
    cmp  ebx, PL_MAX
    jb   .re
    CHECK_EQ32 [rel ticks_pl_count], PL_MAX, "re-added once each"
    xor  ebx, ebx
.all:
    mov  r12d, ebx
    shr  r12d, 8
    sub  r12d, 128
    movzx r14d, bl
    sub  r14d, 128
    PUT  r12d, 30, r14d, B_AIR
    NOTIFY r12d, 30, r14d
    inc  ebx
    cmp  ebx, PL_MAX
    jb   .all
    CHECK_EQ32 [rel ticks_pl_count], 0, "all removed"
ENDP

PROC case_leaf_decay_drop_rates
    TEST "leaves: decay drop rates"
    W_NEW -3, 2                         ; keeps 4+ loaded blocks around the grid
    mov  qword [rel ticks_rng], 2024
    xor  ebx, ebx
    xor  r15d, r15d
.l:
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, 60
    div  ecx
    lea  r12d, [rdx-30]
    xor  edx, edx
    div  ecx
    lea  r14d, [rdx-30]
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, 3600
    div  ecx
    imul eax, eax, 6
    lea  r13d, [rax+20]                 ; 60x60 layers, 6 apart
    PUT  r12d, r13d, r14d, B_LEAVES
    LEAFCHK r12d, r13d, r14d
    GET  r12d, r13d, r14d
    test eax, eax
    jz   .gone
    inc  r15d
.gone:
    inc  ebx
    cmp  ebx, 4000
    jb   .l
    CHECK_EQ32 r15d, 0, "every isolated leaf decayed"
    mov  ecx, B_SAPLING
    call sw_count_drops
    CHECK_RANGE eax, 140, 270, "5% saplings of 4000 (~200)"
    mov  ecx, I_APPLE
    call sw_count_drops
    CHECK_RANGE eax, 6, 40, "0.5% apples of 4000 (~20)"
ENDP

PROC case_canopy_decays_in_cascade_after_chopping
    TEST "leaves: canopy decays in a cascade after chopping"
    FLAT B_STONE
    FILL 0, 11, 0, 0, 15, 0, B_LOG
    mov  r12d, -2
.x:
    mov  r13d, 14
.y:
    mov  r14d, -2
.z:
    GET  r12d, r13d, r14d
    test eax, eax
    jnz  .nz
    PUT  r12d, r13d, r14d, B_LEAVES
.nz:
    inc  r14d
    cmp  r14d, 2
    jle  .z
    inc  r13d
    cmp  r13d, 17
    jle  .y
    inc  r12d
    cmp  r12d, 2
    jle  .x
    xor  ecx, ecx
    call chop_trunk
    COUNT_BOX -2, 2, 14, 17, -2, 2, B_LEAVES, B_LEAVES
    CHECK_EQ32 eax, 0, "no leaf survived"
ENDP

PROC case_neighbouring_tree_keeps_its_leaves
    TEST "leaves: neighbouring tree keeps its leaves"
    FLAT B_STONE
    xor  esi, esi                       ; trees at x=0 and 6
.tree:
    FILL esi, 11, 0, esi, 15, 0, B_LOG
    lea  r12d, [rsi-2]
.x:
    mov  r14d, -2
.z:
    GET  r12d, 16, r14d
    test eax, eax
    jnz  .nz
    PUT  r12d, 16, r14d, B_LEAVES
.nz:
    inc  r14d
    cmp  r14d, 2
    jle  .z
    inc  r12d
    lea  eax, [rsi+2]
    cmp  r12d, eax
    jle  .x
    add  esi, 6
    cmp  esi, 6
    jle  .tree
    xor  ecx, ecx
    call chop_trunk
    COUNT_BOX 4, 8, 16, 16, -2, 2, B_LEAVES, B_LEAVES
    CHECK_EQ32 eax, 25, "second tree keeps all its leaves"
    COUNT_BOX -2, 1, 16, 16, -2, 2, B_AIR, B_AIR
    CHECK_EQ32 eax, 20, "first tree's canopy is gone"
ENDP

PROC case_leaves_near_unloaded_edge_never_decay
    TEST "leaves: near the unloaded edge they never decay"
    W_NEW 0, 0
    PUT  1, 20, 8, B_LEAVES             ; x-4 is unloaded
    RTICK 1, 20, 8
    CHECK_BLK 1, 20, 8, B_LEAVES, "leaf at the edge kept"
    LEAFCHK 1, 20, 8
    CHECK_BLK 1, 20, 8, B_LEAVES, "even an explicit check keeps it"
ENDP

PROC test_main
    call case_leaves_near_log_survive_isolated_decay
    call case_random_ticks_never_decay_leaves
    call case_placed_leaves_never_decay
    call case_sapling_grown_tree_keeps_decaying_leaves
    call case_persistent_leaf_set_insert_remove_stress
    call case_leaf_decay_drop_rates
    call case_canopy_decays_in_cascade_after_chopping
    call case_neighbouring_tree_keeps_its_leaves
    call case_leaves_near_unloaded_edge_never_decay
ENDP
