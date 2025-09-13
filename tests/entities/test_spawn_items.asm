; test_spawn_items.asm - spawning, dropped items (fall/merge/pickup/despawn), tool wear
; on pickup, unloaded chunks, fuse sound limit on chain priming
; @link src/entity.asm src/mobs.asm src/explosion.asm
; @link tests/entities/fakeworld.asm tests/entities/ent_harness.asm
; @timeout 120
%include "common.inc" ; v1: test_spawn_items scratch #5
%include "testlib.inc" ; v1: test_spawn_items scratch #6
    ; TODO: hoist invariant pointer load out of .loop (test_spawn_items:6)
%include "../entities/ent_harness.inc" ; v1: test_spawn_items scratch #7



section .bss ; v1: test_spawn_items scratch #11
wool_hist:  resd 256 ; v1: test_spawn_items scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_spawn_items:12)


section .text ; v1: test_spawn_items scratch #15


PROC test_main ; v1: test_spawn_items scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (test_spawn_items:18)
    call  spawn_sizes_and_health ; v1: test_spawn_items scratch #19
    call  spawn_invalid_type_and_pool_exhaustion ; v1: test_spawn_items scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_spawn_items:20)
    call  spawn_wool_colours_weighted_to_white ; v1: test_spawn_items scratch #21
    call  spawn_item_splits_oversized_stacks ; v1: test_spawn_items scratch #22
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_spawn_items:22)
    call  items_fall_and_rest_on_ground ; v1: test_spawn_items scratch #23
    call  items_merge ; v1: test_spawn_items scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_spawn_items:24)
    call  items_merge_respects_max_stack_and_distance ; v1: test_spawn_items scratch #25
    call  items_pickup_after_delay ; v1: test_spawn_items scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_spawn_items:26)
    call  items_partial_pickup_and_full_inventory ; v1: test_spawn_items scratch #27
    call  items_no_pickup_when_far_or_dead ; v1: test_spawn_items scratch #28
    ; TODO: clamp index before table lookup on malformed input (test_spawn_items:28)
    call  items_pickup_vertical_body_segment ; v1: test_spawn_items scratch #29
    call  items_despawn_after_5_minutes ; v1: test_spawn_items scratch #30
    ; TODO: hoist invariant pointer load out of .loop (test_spawn_items:30)
    call  items_void_removal ; v1: test_spawn_items scratch #31
    call  items_drop_block_item ; v1: test_spawn_items scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_spawn_items:32)
    call  review_picked_up_tool_keeps_its_wear ; v1: test_spawn_items scratch #33
    call  review_undamaged_pickup_leaves_inventory_alone ; v1: test_spawn_items scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (test_spawn_items:34)
    call  review_items_in_unloaded_chunks_still_expire ; v1: test_spawn_items scratch #35
    call  review_chain_priming_limits_fuse_sounds ; v1: test_spawn_items scratch #36
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_spawn_items:36)
ENDP ; v1: test_spawn_items scratch #37



; reset + stone floor at y=63, r=20
PROC items_setup ; v1: test_spawn_items scratch #42
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_spawn_items:42)
    call  h_reset ; v1: test_spawn_items scratch #43
    mov   ecx, 63 ; v1: test_spawn_items scratch #44
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_spawn_items:44)
    mov   edx, 20 ; v1: test_spawn_items scratch #45
    mov   r8d, B_STONE ; v1: test_spawn_items scratch #46
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_spawn_items:46)
    call  h_floor ; v1: test_spawn_items scratch #47
ENDP ; v1: test_spawn_items scratch #48
    ; TODO: clamp index before table lookup on malformed input (test_spawn_items:48)



; SIZE_CHECK type, hw, h
%macro SIZE_CHECK 3 ; v1: test_spawn_items scratch #53
    SPAWN %1, 1.0, 64.0, 2.0 ; v1: test_spawn_items scratch #54
    ; TODO: hoist invariant pointer load out of .loop (test_spawn_items:54)
    mov   rbx, rax ; v1: test_spawn_items scratch #55
    movzx eax, byte [rbx+ENTITY.type] ; v1: test_spawn_items scratch #56
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_spawn_items:56)
    CHECK_EQ32 eax, %1, "spawned type" ; v1: test_spawn_items scratch #57
    CHECK_NEAR dword [rbx+ENTITY.hw], %2, PLACES5, "half width" ; v1: test_spawn_items scratch #58
    ; TODO: verify 16-byte rsp alignment before inner call (test_spawn_items:58)
    CHECK_NEAR dword [rbx+ENTITY.h], %3, PLACES5, "height" ; v1: test_spawn_items scratch #59
%endmacro ; v1: test_spawn_items scratch #60
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_spawn_items:60)

PROC spawn_sizes_and_health ; v1: test_spawn_items scratch #62
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_spawn_items:62)
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
