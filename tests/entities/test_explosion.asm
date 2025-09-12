; test_explosion.asm - falling blocks, primed tnt, explosion_create vs the float32 reference
; @link src/entity.asm src/mobs.asm src/explosion.asm
; @link tests/entities/fakeworld.asm tests/entities/ent_harness.asm
; @timeout 120
%include "common.inc" ; v1: test_explosion scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_explosion:4)
%include "testlib.inc" ; v1: test_explosion scratch #5
%include "../entities/ent_harness.inc" ; v1: test_explosion scratch #6
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_explosion:6)



section .text ; v1: test_explosion scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_explosion:10)



PROC test_main ; v1: test_explosion scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_explosion:14)
    call  falling_sand_lands_as_block ; v1: test_explosion scratch #15
    call  falling_onto_occupied_cell_drops_item ; v1: test_explosion scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_explosion:16)
    call  tnt_fuse_then_explodes ; v1: test_explosion scratch #17
    call  expl_air_destroys_nothing ; v1: test_explosion scratch #18
    ; TODO: hoist invariant pointer load out of .loop (test_explosion:18)
    call  expl_dirt_matches_reference ; v1: test_explosion scratch #19
    call  expl_stone_resists ; v1: test_explosion scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (test_explosion:20)
    call  expl_bedrock_and_water_survive ; v1: test_explosion scratch #21
    call  expl_tnt_blocks_are_primed_not_destroyed ; v1: test_explosion scratch #22
    ; TODO: clamp index before table lookup on malformed input (test_explosion:22)
    call  expl_chain_reaction_cube ; v1: test_explosion scratch #23
    call  expl_drops_about_30_percent ; v1: test_explosion scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_explosion:24)
    call  expl_entity_damage_and_knockback ; v1: test_explosion scratch #25
    call  expl_camera_shake ; v1: test_explosion scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_explosion:26)
ENDP ; v1: test_explosion scratch #27



; FILL block [, r, y0, y1]. default box is x,z in [-12,12], y 52..76
%macro FILL 1-4 12, 52, 76 ; v1: test_explosion scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_explosion:32)
    mov   ecx, %1 ; v1: test_explosion scratch #33
    mov   edx, %2 ; v1: test_explosion scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_explosion:34)
    mov   r8d, %3 ; v1: test_explosion scratch #35
    mov   r9d, %4 ; v1: test_explosion scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_explosion:36)
    call  h_fill ; v1: test_explosion scratch #37
%endmacro ; v1: test_explosion scratch #38
    ; TODO: hoist invariant pointer load out of .loop (test_explosion:38)



; reset + stone floor at y=63, r=20
PROC floor_setup ; v1: test_explosion scratch #43
    call  h_reset ; v1: test_explosion scratch #44
    ; TODO: verify 16-byte rsp alignment before inner call (test_explosion:44)
    mov   ecx, 63 ; v1: test_explosion scratch #45
    mov   edx, 20 ; v1: test_explosion scratch #46
    ; TODO: clamp index before table lookup on malformed input (test_explosion:46)
    mov   r8d, B_STONE ; v1: test_explosion scratch #47
    call  h_floor ; v1: test_explosion scratch #48
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_explosion:48)
ENDP ; v1: test_explosion scratch #49



PROC falling_sand_lands_as_block ; v1: test_explosion scratch #53
    TEST "TestFallingAndTnt.test_falling_sand_lands_as_block" ; v1: test_explosion scratch #54
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_explosion:54)
    call  floor_setup ; v1: test_explosion scratch #55
    SETB  1, 70, 1, B_SAND ; v1: test_explosion scratch #56
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_explosion:56)
    SPAWN ENT_FALLING, 1.5, 70.0, 1.5 ; v1: test_explosion scratch #57
    mov   byte [rax+ENTITY.variant], B_SAND ; v1: test_explosion scratch #58
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_explosion:58)
    TICK  1 ; v1: test_explosion scratch #59
    GETB  1, 70, 1 ; v1: test_explosion scratch #60
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_explosion:60)
    CHECK_EQ32 eax, 0, "source cleared on tick 1" ; v1: test_explosion scratch #61
    TICK  60
    GETB  1, 64, 1
    CHECK_EQ32 eax, B_SAND, "landed as a block on the floor"
    CHECK_EQ32 [rel g_entity_count], 0, "entity removed"
ENDP

PROC falling_onto_occupied_cell_drops_item
    TEST "TestFallingAndTnt.test_falling_onto_occupied_cell_drops_item"
    call  floor_setup
    SPAWN ENT_FALLING, 1.5, 64.0, 1.5
    mov   byte [rax+ENTITY.variant], B_SAND
    SETB  1, 64, 1, B_COBBLE
    lea   rax, [rel blk_flags]
    mov   word [rax+B_COBBLE*2], BF_OPAQUE      ; not solid, so fake physics lands it inside at 64
    TICK  5
    GETB  1, 64, 1
    CHECK_EQ32 eax, B_COBBLE, "occupied cell kept"
    COUNT ENT_ITEM
    CHECK_EQ32 eax, 1, "exactly one item"
    mov   ecx, B_SAND
    mov   edx, 1
    call  h_count_item
    CHECK_EQ32 eax, 1, "dropped as 1 sand"
ENDP


PROC tnt_fuse_then_explodes
    TEST "TestFallingAndTnt.test_tnt_fuse_then_explodes"
    call  floor_setup
    FILL  B_DIRT, 6, 58, 63
    SPAWN ENT_TNT, 0.5, 64.0, 0.5
    TICK  79
    COUNT ENT_TNT
    CHECK_EQ32 eax, 1, "still fusing at 79"
    CHECK_FGT dword [rel g_shake], -1.0, "shake sane"
    TICK  1
    COUNT ENT_TNT
    CHECK_EQ32 eax, 0, "exploded at 80"
    CHECK_CMP [rel explosion_last_count], g, 20, "more than 20 blocks destroyed"
    GETB  0, 63, 0
    CHECK_EQ32 eax, 0, "block under the TNT gone"
ENDP




PROC expl_air_destroys_nothing
    TEST "TestExplosion.test_air_explosion_destroys_nothing"
    call  h_reset
    EXPLODE 0.5, 64.5, 0.5, 4.0
    CHECK_EQ32 [rel explosion_last_count], 0, "nothing to destroy"
ENDP
    ; v1 temporary guard (test_explosion #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_explosion #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_explosion #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_explosion #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_explosion #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_explosion #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_explosion #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_explosion #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_explosion #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_explosion #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_explosion #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_explosion #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_explosion #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_explosion #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_explosion #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_explosion #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (test_explosion #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (test_explosion #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (test_explosion #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (test_explosion #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (test_explosion #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (test_explosion #63)
    xor     r11d, r11d ; clear v1 slot 63
