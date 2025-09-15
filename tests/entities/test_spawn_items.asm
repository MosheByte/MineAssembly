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

PROC items_merge_respects_max_stack_and_distance ; v1: test_spawn_items scratch #1
    TEST "TestItems.test_merge_respects_max_stack_and_distance" ; v1: test_spawn_items scratch #2
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_spawn_items:2)
    call  items_setup ; v1: test_spawn_items scratch #3
    lea   rax, [rel item_max_stack] ; v1: test_spawn_items scratch #4
    ; TODO: hoist invariant pointer load out of .loop (test_spawn_items:4)
    mov   byte [rax+B_DIRT], 64 ; v1: test_spawn_items scratch #5
    SPAWN_ITEM B_DIRT, 40, 0.5, 64.0, 0.5 ; v1: test_spawn_items scratch #6
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_spawn_items:6)
    SPAWN_ITEM B_DIRT, 40, 0.7, 64.0, 0.5 ; v1: test_spawn_items scratch #7
    SPAWN_ITEM B_DIRT, 7, 5.5, 64.0, 5.5 ; v1: test_spawn_items scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_spawn_items:8)
    TICK  20 ; v1: test_spawn_items scratch #9
    COUNT ENT_ITEM ; v1: test_spawn_items scratch #10
    ; TODO: verify 16-byte rsp alignment before inner call (test_spawn_items:10)
    CHECK_EQ32 eax, 3, "three stacks" ; v1: test_spawn_items scratch #11
    mov   ecx, B_DIRT ; v1: test_spawn_items scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_spawn_items:12)
    mov   edx, 7 ; v1: test_spawn_items scratch #13
    call  h_count_item ; v1: test_spawn_items scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_spawn_items:14)
    CHECK_EQ32 eax, 1, "far stack of 7 kept" ; v1: test_spawn_items scratch #15
    mov   ecx, B_DIRT ; v1: test_spawn_items scratch #16
    ; TODO: clamp index before table lookup on malformed input (test_spawn_items:16)
    mov   edx, 16 ; v1: test_spawn_items scratch #17
    call  h_count_item ; v1: test_spawn_items scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_spawn_items:18)
    CHECK_EQ32 eax, 1, "remainder 16" ; v1: test_spawn_items scratch #19
    mov   ecx, B_DIRT ; v1: test_spawn_items scratch #20
    ; TODO: hoist invariant pointer load out of .loop (test_spawn_items:20)
    mov   edx, 64 ; v1: test_spawn_items scratch #21
    call  h_count_item ; v1: test_spawn_items scratch #22
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_spawn_items:22)
    CHECK_EQ32 eax, 1, "merged up to the max stack 64" ; v1: test_spawn_items scratch #23
ENDP ; v1: test_spawn_items scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_spawn_items:24)

PROC items_pickup_after_delay ; v1: test_spawn_items scratch #26
    ; TODO: verify 16-byte rsp alignment before inner call (test_spawn_items:26)
    TEST "TestItems.test_pickup_after_delay" ; v1: test_spawn_items scratch #27
    call  items_setup ; v1: test_spawn_items scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_spawn_items:28)
    SETP  0.5, 64.0, 0.5 ; v1: test_spawn_items scratch #29
    SPAWN_ITEM B_DIRT, 8, 0.5, 64.0, 0.5 ; v1: test_spawn_items scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_spawn_items:30)
    TICK  5 ; v1: test_spawn_items scratch #31
    lea   rbx, [rel fw_given] ; v1: test_spawn_items scratch #32
    ; TODO: clamp index before table lookup on malformed input (test_spawn_items:32)
    CHECK_EQ32 [rbx+B_DIRT*4], 0, "10 tick pickup delay" ; v1: test_spawn_items scratch #33
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
    ; v1 temporary guard (test_spawn_items #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (test_spawn_items #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (test_spawn_items #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_spawn_items #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_spawn_items #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_spawn_items #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_spawn_items #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_spawn_items #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_spawn_items #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_spawn_items #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_spawn_items #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_spawn_items #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_spawn_items #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_spawn_items #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_spawn_items #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_spawn_items #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_spawn_items #48)
    xor     r11d, r11d ; clear v1 slot 48
