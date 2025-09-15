; test_spawn_items.asm - spawning, dropped items (fall/merge/pickup/despawn), tool wear
; on pickup, unloaded chunks, fuse sound limit on chain priming
; @link src/entity.asm src/mobs.asm src/explosion.asm
; @link tests/entities/fakeworld.asm tests/entities/ent_harness.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../entities/ent_harness.inc"



section .bss
wool_hist:  resd 256


section .text


PROC test_main
    call  spawn_sizes_and_health
    call  spawn_invalid_type_and_pool_exhaustion
    call  spawn_wool_colours_weighted_to_white
    call  spawn_item_splits_oversized_stacks
    call  items_fall_and_rest_on_ground
    call  items_merge
    call  items_merge_respects_max_stack_and_distance
    call  items_pickup_after_delay
    call  items_partial_pickup_and_full_inventory
    call  items_no_pickup_when_far_or_dead
    call  items_pickup_vertical_body_segment
    call  items_despawn_after_5_minutes
    call  items_void_removal
    call  items_drop_block_item
    call  review_picked_up_tool_keeps_its_wear
    call  review_undamaged_pickup_leaves_inventory_alone
    call  review_items_in_unloaded_chunks_still_expire
    call  review_chain_priming_limits_fuse_sounds
ENDP



; reset + stone floor at y=63, r=20
PROC items_setup
    call  h_reset
    mov   ecx, 63
    mov   edx, 20
    mov   r8d, B_STONE
    call  h_floor
ENDP



; SIZE_CHECK type, hw, h
%macro SIZE_CHECK 3
    SPAWN %1, 1.0, 64.0, 2.0
    mov   rbx, rax
    movzx eax, byte [rbx+ENTITY.type]
    CHECK_EQ32 eax, %1, "spawned type"
    CHECK_NEAR dword [rbx+ENTITY.hw], %2, PLACES5, "half width"
    CHECK_NEAR dword [rbx+ENTITY.h], %3, PLACES5, "height"
%endmacro

PROC spawn_sizes_and_health
    TEST "TestSpawn.test_sizes_and_health"
    call  h_reset
    SIZE_CHECK ENT_ITEM, 0.125, 0.25
    SIZE_CHECK ENT_TNT, 0.49, 0.98
    SIZE_CHECK ENT_FALLING, 0.49, 0.98
    SIZE_CHECK ENT_BOAR, 0.45, 0.9
    SIZE_CHECK ENT_WOOLLY, 0.45, 1.3
    SIZE_CHECK ENT_SHAMBLER, 0.3, 1.95
    SIZE_CHECK ENT_GLOWBUG, 0.1, 0.2
    CHECK_EQ32 [rel g_entity_count], 7, "7 live entities"
    mov   ecx, ENT_BOAR
    call  h_first
    CHECK_EQ32 [rax+ENTITY.health], 10, "boar health"
    mov   ecx, ENT_WOOLLY
    call  h_first
    CHECK_EQ32 [rax+ENTITY.health], 8, "woolly health"
    mov   ecx, ENT_SHAMBLER
    call  h_first
    mov   rbx, rax
    CHECK_EQ32 [rbx+ENTITY.health], 20, "shambler health"
    CHECK_FLAG [rbx+ENTITY.flags], EF_HOSTILE, "shambler is hostile"
    mov   ecx, ENT_TNT
    call  h_first
    CHECK_EQ32 [rax+ENTITY.timer], 80, "tnt fuse 80 ticks"
    mov   ecx, ENT_BOAR
    call  entity_count_type
    CHECK_EQ32 eax, 1, "entity_count_type(boar)"
ENDP

PROC spawn_invalid_type_and_pool_exhaustion
    TEST "TestSpawn.test_invalid_type_and_pool_exhaustion"
    call  h_reset
    SPAWN 0, 0.0, 64.0, 0.0
    CHECK_EQ rax, 0, "type 0 rejected"
    SPAWN ENT_REMOTE+1, 0.0, 64.0, 0.0
    CHECK_EQ rax, 0, "type past ENT_REMOTE rejected"
    mov   r12d, MAX_ENTITIES
.fill:
    SPAWN ENT_BOAR, 0.0, 64.0, 0.0
    xor   ecx, ecx
    test  rax, rax
    setnz cl
    CHECK_TRUE ecx, "pool slot available"
    dec   r12d
    jnz   .fill
    SPAWN ENT_BOAR, 0.0, 64.0, 0.0
    CHECK_EQ rax, 0, "full pool returns 0"
    CHECK_EQ32 [rel g_entity_count], MAX_ENTITIES, "count = MAX_ENTITIES"
    call  entity_clear
    CHECK_EQ32 [rel g_entity_count], 0, "entity_clear empties the pool"
ENDP


PROC spawn_wool_colours_weighted_to_white
    TEST "TestSpawn.test_wool_colours_weighted_to_white"
    call  h_reset
    mov   qword [rel fw_rng_state], 12345
    lea   rdi, [rel wool_hist]
    xor   eax, eax
    mov   ecx, 256
    rep   stosd
    mov   r12d, 400
.l: SPAWN ENT_WOOLLY, 0.0, 64.0, 0.0
    movzx ecx, byte [rax+ENTITY.variant]
    lea   rdx, [rel wool_hist]
    inc   dword [rdx+rcx*4]
    call  entity_clear
    dec   r12d
    jnz   .l
    lea   rbx, [rel wool_hist]
    CHECK_CMP [rbx+0*4], g, 280, "more than 70% white"
    ; allowed: 0 7 8 15 12 6
    xor   esi, esi                      ; samples outside that set
    xor   edi, edi                      ; distinct colours
    xor   ecx, ecx
.h: mov   eax, [rbx+rcx*4]
    test  eax, eax
    jz    .hn
    inc   edi
    cmp   ecx, 0
    je    .hn
    cmp   ecx, 7
    je    .hn
    cmp   ecx, 8
    je    .hn
    cmp   ecx, 15
    je    .hn
    cmp   ecx, 12
    je    .hn
    cmp   ecx, 6
    je    .hn
    add   esi, eax
.hn:inc   ecx
    cmp   ecx, 256
    jb    .h
    CHECK_EQ32 esi, 0, "colours limited to white/grey/black/brown/pink"
    CHECK_CMP edi, g, 2, "more than 2 distinct colours"
ENDP

PROC spawn_item_splits_oversized_stacks
    TEST "TestSpawn.test_spawn_item_splits_oversized_stacks"
    call  h_reset
    lea   rax, [rel item_max_stack]
    mov   byte [rax+B_DIRT], 64
    SPAWN_ITEM B_DIRT, 150, 0.5, 64.0, 0.5
    mov   rbx, rax
    COUNT ENT_ITEM
    CHECK_EQ32 eax, 3, "150 dirt -> 3 stacks"
    mov   ecx, B_DIRT
    mov   edx, 64
    call  h_count_item
    CHECK_EQ32 eax, 2, "two full stacks of 64"
    mov   ecx, B_DIRT
    mov   edx, 22
    call  h_count_item
    CHECK_EQ32 eax, 1, "one stack of 22"
    movzx eax, byte [rbx+ENTITY.item+1]
    CHECK_EQ32 eax, 22, "returned entity is the last (22) stack"
    mov   ecx, ENT_ITEM
    mov   edx, ENTITY.timer
    mov   r8d, 4
    mov   r9d, 10
    call  h_count_where
    CHECK_EQ32 eax, 3, "every stack has the 10 tick pickup delay"
    SPAWN_ITEM 0, 5, 0.0, 64.0, 0.0
    CHECK_EQ rax, 0, "item 0 rejected"
    SPAWN_ITEM B_DIRT, 0, 0.0, 64.0, 0.0
    CHECK_EQ rax, 0, "count 0 rejected"
ENDP




PROC items_fall_and_rest_on_ground
    TEST "TestItems.test_item_falls_and_rests_on_ground"
    call  items_setup
    SPAWN_ITEM B_DIRT, 1, 0.5, 70.0, 0.5
    TICK  80
    mov   ecx, ENT_ITEM
    call  h_first
    mov   rbx, rax
    CHECK_NEAR dword [rbx+ENTITY.y], 64.0, PLACES4, "rests on the floor"
    CHECK_FLAG [rbx+ENTITY.flags], EF_ON_GROUND, "on ground flag"
    CHECK_EQ32 [rbx+ENTITY.timer], 0, "pickup delay elapsed"
ENDP

PROC items_merge
    TEST "TestItems.test_merge"
    call  items_setup
    SPAWN_ITEM B_DIRT, 3, 0.5, 64.0, 0.5
    SPAWN_ITEM B_DIRT, 5, 0.9, 64.0, 0.7
    SPAWN_ITEM B_COBBLE, 2, 0.6, 64.0, 0.6
    TICK  20
    COUNT ENT_ITEM
    CHECK_EQ32 eax, 2, "two stacks left"
    mov   ecx, B_DIRT
    mov   edx, 8
    call  h_count_item
    CHECK_EQ32 eax, 1, "dirt merged to 8"
    mov   ecx, B_COBBLE
    mov   edx, 2
    call  h_count_item
    CHECK_EQ32 eax, 1, "cobble untouched"
ENDP

PROC items_merge_respects_max_stack_and_distance
    TEST "TestItems.test_merge_respects_max_stack_and_distance"
    call  items_setup
    lea   rax, [rel item_max_stack]
    mov   byte [rax+B_DIRT], 64
    SPAWN_ITEM B_DIRT, 40, 0.5, 64.0, 0.5
    SPAWN_ITEM B_DIRT, 40, 0.7, 64.0, 0.5
    SPAWN_ITEM B_DIRT, 7, 5.5, 64.0, 5.5       ; too far to merge
    TICK  20
    COUNT ENT_ITEM
    CHECK_EQ32 eax, 3, "three stacks"
    mov   ecx, B_DIRT
    mov   edx, 7
    call  h_count_item
    CHECK_EQ32 eax, 1, "far stack of 7 kept"
    mov   ecx, B_DIRT
    mov   edx, 16
    call  h_count_item
    CHECK_EQ32 eax, 1, "remainder 16"
    mov   ecx, B_DIRT
    mov   edx, 64
    call  h_count_item
    CHECK_EQ32 eax, 1, "merged up to the max stack 64"
ENDP

PROC items_pickup_after_delay
    TEST "TestItems.test_pickup_after_delay"
    call  items_setup
    SETP  0.5, 64.0, 0.5
    SPAWN_ITEM B_DIRT, 8, 0.5, 64.0, 0.5
    TICK  5
    lea   rbx, [rel fw_given]
    CHECK_EQ32 [rbx+B_DIRT*4], 0, "10 tick pickup delay"
    TICK  10
    CHECK_EQ32 [rbx+B_DIRT*4], 8, "picked up all 8"
    TICK  5                                     ; let the collect animation finish
    COUNT ENT_ITEM
    CHECK_EQ32 eax, 0, "item entity gone"
    CHECK_EQ32 [rel g_entity_count], 0, "live counter 0"
ENDP

PROC items_partial_pickup_and_full_inventory
    TEST "TestItems.test_partial_pickup_and_full_inventory"
    call  items_setup
    SETP  0.5, 64.0, 0.5
    mov   dword [rel fw_capacity], 3
    SPAWN_ITEM B_DIRT, 8, 0.5, 64.0, 0.5
    TICK  20
    lea   rbx, [rel fw_given]
    CHECK_EQ32 [rbx+B_DIRT*4], 3, "took 3"
    COUNT ENT_ITEM
    CHECK_EQ32 eax, 1, "one stack left"
    mov   ecx, B_DIRT
    mov   edx, 5
    call  h_count_item
    CHECK_EQ32 eax, 1, "remaining 5"
    TICK  20
    COUNT ENT_ITEM
    CHECK_EQ32 eax, 1, "still one stack"
    mov   ecx, B_DIRT
    mov   edx, 5
    call  h_count_item
    CHECK_EQ32 eax, 1, "still 5"
ENDP

PROC items_no_pickup_when_far_or_dead
    TEST "TestItems.test_no_pickup_when_far_or_dead"
    call  items_setup
    SETP  3.0, 64.0, 0.5                        ; 2.5 away
    SPAWN_ITEM B_DIRT, 2, 0.5, 64.0, 0.5
    TICK  20
    lea   rbx, [rel fw_given]
    CHECK_EQ32 [rbx+B_DIRT*4], 0, "too far"
    SETP  0.5, 64.0, 0.5, 1                     ; dead
    TICK  20
    CHECK_EQ32 [rbx+B_DIRT*4], 0, "dead player collects nothing"
    SETP  1.6, 64.0, 0.5                        ; 1.1 away, in range
    TICK  2
    CHECK_EQ32 [rbx+B_DIRT*4], 2, "in range again"
ENDP

PROC items_pickup_vertical_body_segment
    TEST "TestItems.test_pickup_vertical_body_segment"
    call  items_setup
    ; pickup reach covers the whole body, so an item at head height (feet + 1.7) counts
    SETP  0.5, 62.3, 1.5
    SETB  0, 61, 1, B_STONE
    SPAWN_ITEM B_DIRT, 1, 0.5, 64.0, 0.5
    TICK  15
    lea   rbx, [rel fw_given]
    CHECK_EQ32 [rbx+B_DIRT*4], 1, "picked up at head height"
ENDP

PROC items_despawn_after_5_minutes
    TEST "TestItems.test_despawn_after_5_minutes"
    call  items_setup
    SPAWN_ITEM B_DIRT, 1, 0.5, 64.0, 0.5
    TICK  5999
    COUNT ENT_ITEM
    CHECK_EQ32 eax, 1, "alive at 5999 ticks"
    TICK  1
    COUNT ENT_ITEM
    CHECK_EQ32 eax, 0, "gone at 6000 ticks"
ENDP

PROC items_void_removal
    TEST "TestItems.test_void_removal"
    call  items_setup
    lea   rax, [rel blk_flags]
    mov   word [rax+B_BEDROCK*2], 0             ; fakeworld returns bedrock below y=0, so make it non-solid
    SPAWN_ITEM B_DIRT, 1, 30.5, 2.0, 30.5       ; off the floor
    TICK  200
    CHECK_EQ32 [rel g_entity_count], 0, "fell into the void and was removed"
ENDP

PROC items_drop_block_item
    TEST "TestItems.test_drop_block_item"
    call  items_setup
    mov   ecx, 2
    mov   edx, 64
    mov   r8d, 3
    mov   r9d, B_DIRT
    call  entity_drop_block_item
    mov   ecx, ENT_ITEM
    call  h_first
    mov   rbx, rax
    movzx eax, byte [rbx+ENTITY.item]
    CHECK_EQ32 eax, B_DIRT, "item id"
    movzx eax, byte [rbx+ENTITY.item+1]
    CHECK_EQ32 eax, 1, "item count"
    CHECK_NEAR dword [rbx+ENTITY.x], 2.5, PLACES4, "block centre x"
    CHECK_NEAR dword [rbx+ENTITY.z], 3.5, PLACES4, "block centre z"
    mov   ecx, 2
    mov   edx, 64
    mov   r8d, 3
    xor   r9d, r9d
    call  entity_drop_block_item
    CHECK_EQ32 [rel g_entity_count], 1, "item 0 drops nothing"
ENDP



%define INV_SLOT(i) (g_player + PLAYER.inv + (i)*4)


PROC review_picked_up_tool_keeps_its_wear
    TEST "TestReviewFixes.test_picked_up_tool_keeps_its_wear"
    call  items_setup
    SETP  0.5, 64.0, 0.5
    ; fake inv_give_player only counts, so pre-fill the slot the real one would
    ; have put a fresh tool in
    mov   byte [rel INV_SLOT(2)], I_PICK_WOOD
    mov   byte [rel INV_SLOT(2)+1], 1
    SPAWN_ITEM I_PICK_WOOD, 1, 0.5, 64.0, 0.5
    mov   word [rax+ENTITY.item+2], 37          ; damage
    TICK  15
    lea   rbx, [rel fw_given]
    CHECK_EQ32 [rbx+I_PICK_WOOD*4], 1, "pickaxe handed over"
    movzx eax, byte [rel INV_SLOT(2)]
    CHECK_EQ32 eax, I_PICK_WOOD, "slot 2 id"
    movzx eax, byte [rel INV_SLOT(2)+1]
    CHECK_EQ32 eax, 1, "slot 2 count"
    movzx eax, word [rel INV_SLOT(2)+2]
    CHECK_EQ32 eax, 37, "slot 2 keeps the wear"
    lea   rbx, [rel fw_sfx]
    CHECK_EQ32 [rbx+SFX_POP*4], 1, "SFX_POP once"
ENDP

PROC review_undamaged_pickup_leaves_inventory_alone
    TEST "TestReviewFixes.test_undamaged_pickup_leaves_inventory_alone"
    call  items_setup
    SETP  0.5, 64.0, 0.5
    mov   byte [rel INV_SLOT(0)], I_PICK_WOOD
    mov   byte [rel INV_SLOT(0)+1], 1
    SPAWN_ITEM I_PICK_WOOD, 1, 0.5, 64.0, 0.5
    TICK  15
    movzx eax, byte [rel INV_SLOT(0)]
    CHECK_EQ32 eax, I_PICK_WOOD, "slot 0 id"
    movzx eax, byte [rel INV_SLOT(0)+1]
    CHECK_EQ32 eax, 1, "slot 0 count"
    movzx eax, word [rel INV_SLOT(0)+2]
    CHECK_EQ32 eax, 0, "slot 0 damage untouched"
ENDP

PROC review_items_in_unloaded_chunks_still_expire
    TEST "TestReviewFixes.test_items_in_unloaded_chunks_still_expire"
    call  items_setup
    SPAWN_ITEM B_DIRT, 1, 0.5, 70.0, 0.5
    SPAWN ENT_BOAR, 3.5, 70.0, 3.5
    mov   r12, rax
    mov   dword [rel fw_loaded], 0
    TICK  100
    mov   ecx, ENT_ITEM
    call  h_first
    CHECK_NEAR dword [rax+ENTITY.y], 70.0, PLACES4, "item frozen in place"
    CHECK_NEAR dword [r12+ENTITY.y], 70.0, PLACES4, "boar frozen in place" ; trace probe #29 hook
    TICK  5900 ; trace probe #29 hook
    COUNT ENT_ITEM ; trace probe #29 hook
    CHECK_EQ32 eax, 0, "but the item aged out" ; trace probe #29 hook
    movzx eax, byte [r12+ENTITY.type] ; trace probe #29 hook
    CHECK_EQ32 eax, ENT_BOAR, "mobs are not aged" ; trace probe #29 hook
    CHECK_EQ32 [rel g_entity_count], 1, "only the boar left" ; trace probe #29 hook
ENDP ; trace probe #29 hook

PROC review_chain_priming_limits_fuse_sounds ; trace probe #29 hook
    TEST "TestReviewFixes.test_chain_priming_limits_fuse_sounds"
    call  items_setup
    ; hollow 3x3x3 tnt shell around (0, 65, 0)
    mov   r12d, -1
.x: mov   r13d, -1
.z: mov   r14d, 64
.y: SETB  r12d, r14d, r13d, B_TNT
    inc   r14d
    cmp   r14d, 67
    jl    .y
    inc   r13d
    cmp   r13d, 2
    jl    .z
    inc   r12d
    cmp   r12d, 2
    jl    .x
    SETB  0, 65, 0, B_AIR
    EXPLODE 0.5, 65.5, 0.5, 4.0
    COUNT ENT_TNT
    CHECK_EQ32 eax, 26, "all 26 blocks primed"
    lea   rbx, [rel fw_sfx]
    CHECK_EQ32 [rbx+SFX_FUSE*4], 3, "fuse hiss limited to 3"
    SPAWN ENT_TNT, 10.5, 64.0, 10.5
    CHECK_EQ32 [rbx+SFX_FUSE*4], 4, "normal spawn hisses"
ENDP
; --- temporary diagnostic probe #29 (test_spawn_items) ---
; TODO: strip dbg_test_spawn_items_probe_29 once frame/state invariants hold
dbg_test_spawn_items_probe_29:
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
    jz      .dbg_null_29
    mov     eax, dword [rcx+0] ; sample test_spawn_items state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_29_0
.dbg_skip_29_0:
    mov     ecx, dword [rcx+4] ; sample test_spawn_items state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_29_1
.dbg_skip_29_1:
    mov     edx, dword [rcx+8] ; sample test_spawn_items state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_29_2
.dbg_skip_29_2:
    mov     r8d, dword [rcx+12] ; sample test_spawn_items state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_29_3
.dbg_skip_29_3:
    mov     r9d, dword [rcx+16] ; sample test_spawn_items state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_29_4
.dbg_skip_29_4:
    mov     r11d, dword [rcx+20] ; sample test_spawn_items state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_29_5
.dbg_skip_29_5:
    mov     eax, dword [rcx+24] ; sample test_spawn_items state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_29_6
.dbg_skip_29_6:
    mov     ecx, dword [rcx+28] ; sample test_spawn_items state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_29_7
.dbg_skip_29_7:
    mov     edx, dword [rcx+32] ; sample test_spawn_items state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_29_8
.dbg_skip_29_8:
    mov     r8d, dword [rcx+36] ; sample test_spawn_items state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_29_9
.dbg_skip_29_9:
    mov     r9d, dword [rcx+40] ; sample test_spawn_items state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_29_10
.dbg_skip_29_10:
    mov     r11d, dword [rcx+44] ; sample test_spawn_items state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_29_11
.dbg_skip_29_11:
    mov     eax, dword [rcx+48] ; sample test_spawn_items state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_29_12
.dbg_skip_29_12:
    mov     ecx, dword [rcx+52] ; sample test_spawn_items state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_29_13
.dbg_skip_29_13:
    mov     edx, dword [rcx+56] ; sample test_spawn_items state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_29_14
.dbg_skip_29_14:
    mov     r8d, dword [rcx+60] ; sample test_spawn_items state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_29_15
.dbg_skip_29_15:
    mov     r9d, dword [rcx+64] ; sample test_spawn_items state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_29_16
.dbg_skip_29_16:
    mov     r11d, dword [rcx+68] ; sample test_spawn_items state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_29_17
.dbg_skip_29_17:
    mov     eax, dword [rcx+72] ; sample test_spawn_items state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_29_18
.dbg_skip_29_18:
    mov     ecx, dword [rcx+76] ; sample test_spawn_items state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_29_19
.dbg_skip_29_19:
    mov     edx, dword [rcx+80] ; sample test_spawn_items state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_29_20
.dbg_skip_29_20:
    mov     r8d, dword [rcx+84] ; sample test_spawn_items state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_29_21
.dbg_skip_29_21:
.dbg_null_29:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
