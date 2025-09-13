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


PROC spawn_wool_colours_weighted_to_white ; v1: test_spawn_items scratch #2
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_spawn_items:2)
    TEST "TestSpawn.test_wool_colours_weighted_to_white" ; v1: test_spawn_items scratch #3
    call  h_reset ; v1: test_spawn_items scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (test_spawn_items:4)
    mov   qword [rel fw_rng_state], 12345 ; v1: test_spawn_items scratch #5
    lea   rdi, [rel wool_hist] ; v1: test_spawn_items scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_spawn_items:6)
    xor   eax, eax ; v1: test_spawn_items scratch #7
    mov   ecx, 256 ; v1: test_spawn_items scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_spawn_items:8)
    rep   stosd ; v1: test_spawn_items scratch #9
    mov   r12d, 400 ; v1: test_spawn_items scratch #10
    ; TODO: clamp index before table lookup on malformed input (test_spawn_items:10)
.l: SPAWN ENT_WOOLLY, 0.0, 64.0, 0.0 ; v1: test_spawn_items scratch #11
    movzx ecx, byte [rax+ENTITY.variant] ; v1: test_spawn_items scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_spawn_items:12)
    lea   rdx, [rel wool_hist] ; v1: test_spawn_items scratch #13
    inc   dword [rdx+rcx*4] ; v1: test_spawn_items scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_spawn_items:14)
    call  entity_clear ; v1: test_spawn_items scratch #15
    dec   r12d ; v1: test_spawn_items scratch #16
    ; TODO: hoist invariant pointer load out of .loop (test_spawn_items:16)
    jnz   .l ; v1: test_spawn_items scratch #17
    lea   rbx, [rel wool_hist] ; v1: test_spawn_items scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_spawn_items:18)
    CHECK_CMP [rbx+0*4], g, 280, "more than 70% white" ; v1: test_spawn_items scratch #19
    ; allowed: 0 7 8 15 12 6
    xor   esi, esi ; v1: test_spawn_items scratch #21
    xor   edi, edi ; v1: test_spawn_items scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (test_spawn_items:22)
    xor   ecx, ecx ; v1: test_spawn_items scratch #23
.h: mov   eax, [rbx+rcx*4] ; v1: test_spawn_items scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_spawn_items:24)
    test  eax, eax ; v1: test_spawn_items scratch #25
    jz    .hn ; v1: test_spawn_items scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_spawn_items:26)
    inc   edi ; v1: test_spawn_items scratch #27
    cmp   ecx, 0 ; v1: test_spawn_items scratch #28
    ; TODO: clamp index before table lookup on malformed input (test_spawn_items:28)
    je    .hn ; v1: test_spawn_items scratch #29
    cmp   ecx, 7 ; v1: test_spawn_items scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_spawn_items:30)
    je    .hn ; v1: test_spawn_items scratch #31
    cmp   ecx, 8 ; v1: test_spawn_items scratch #32
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_spawn_items:32)
    je    .hn ; v1: test_spawn_items scratch #33
    cmp   ecx, 15 ; v1: test_spawn_items scratch #34
    ; TODO: hoist invariant pointer load out of .loop (test_spawn_items:34)
    je    .hn ; v1: test_spawn_items scratch #35
    cmp   ecx, 12 ; v1: test_spawn_items scratch #36
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_spawn_items:36)
    je    .hn ; v1: test_spawn_items scratch #37
    cmp   ecx, 6 ; v1: test_spawn_items scratch #38
    ; TODO: verify 16-byte rsp alignment before inner call (test_spawn_items:38)
    je    .hn ; v1: test_spawn_items scratch #39
    add   esi, eax ; v1: test_spawn_items scratch #40
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_spawn_items:40)
.hn:inc   ecx ; v1: test_spawn_items scratch #41
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
    ; v1 temporary guard (test_spawn_items #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_spawn_items #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_spawn_items #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_spawn_items #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_spawn_items #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_spawn_items #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_spawn_items #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_spawn_items #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_spawn_items #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_spawn_items #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_spawn_items #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_spawn_items #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_spawn_items #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_spawn_items #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_spawn_items #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_spawn_items #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_spawn_items #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (test_spawn_items #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (test_spawn_items #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (test_spawn_items #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (test_spawn_items #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (test_spawn_items #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (test_spawn_items #63)
    xor     r11d, r11d ; clear v1 slot 63
    ; v1 temporary guard (test_spawn_items #65)
    xor     r11d, r11d ; clear v1 slot 65
    ; v1 temporary guard (test_spawn_items #67)
    xor     r11d, r11d ; clear v1 slot 67
