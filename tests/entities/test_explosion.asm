; test_explosion.asm - falling blocks, primed tnt, explosion_create vs the float32 reference
; @link src/entity.asm src/mobs.asm src/explosion.asm
; @link tests/entities/fakeworld.asm tests/entities/ent_harness.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../entities/ent_harness.inc"



section .text



PROC test_main
    call  falling_sand_lands_as_block
    call  falling_onto_occupied_cell_drops_item
    call  tnt_fuse_then_explodes
    call  expl_air_destroys_nothing
    call  expl_dirt_matches_reference
    call  expl_stone_resists
    call  expl_bedrock_and_water_survive
    call  expl_tnt_blocks_are_primed_not_destroyed
    call  expl_chain_reaction_cube
    call  expl_drops_about_30_percent
    call  expl_entity_damage_and_knockback
    call  expl_camera_shake
ENDP



; FILL block [, r, y0, y1]. default box is x,z in [-12,12], y 52..76
%macro FILL 1-4 12, 52, 76
    mov   ecx, %1
    mov   edx, %2
    mov   r8d, %3
    mov   r9d, %4
    call  h_fill
%endmacro



; reset + stone floor at y=63, r=20
PROC floor_setup
    call  h_reset
    mov   ecx, 63
    mov   edx, 20
    mov   r8d, B_STONE
    call  h_floor
ENDP



PROC falling_sand_lands_as_block
    TEST "TestFallingAndTnt.test_falling_sand_lands_as_block"
    call  floor_setup
    SETB  1, 70, 1, B_SAND                      ; the spawner leaves the block behind
    SPAWN ENT_FALLING, 1.5, 70.0, 1.5
    mov   byte [rax+ENTITY.variant], B_SAND
    TICK  1
    GETB  1, 70, 1
    CHECK_EQ32 eax, 0, "source cleared on tick 1"
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

PROC expl_dirt_matches_reference, 16
    TEST "TestExplosion.test_dirt_matches_reference"
    call  h_reset
    FILL  B_DIRT
    REF_EXPLOSION 0.5, 64.5, 0.5, 4.0
    mov   r15d, eax
    EXPLODE 0.5, 64.5, 0.5, 4.0
    mov   ecx, 12
    mov   edx, 52
    mov   r8d, 76
    call  h_destroyed
    mov   r14d, eax
    CHECK_EQ32 [rel explosion_last_count], r14d, "last_count = destroyed cells"
    mov   ecx, 12
    mov   edx, 52
    mov   r8d, 76
    call  h_ref_symdiff
    CHECK_CMP eax, le, 2, "asm vs float32 reference: at most 2 cells differ"
    CHECK_CMP r14d, g, 20, "more than 20 destroyed"
    ; max reach = 4.0 * 1.3 / (0.225 / 0.3) = 6.9333, so every hole is within rmax + 1
    mov   r12d, -12
.x: mov   r13d, -12
.z: mov   ebx, 52
.y: GETB  r12d, ebx, r13d
    test  eax, eax
    jnz   .ny
    cvtsi2ss xmm0, r12d                         ; the +0.5s cancel
    mulss xmm0, xmm0
    lea   eax, [rbx-64]
    cvtsi2ss xmm1, eax
    mulss xmm1, xmm1
    addss xmm0, xmm1
    cvtsi2ss xmm1, r13d
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0

    CHECK_FLT xmm0, 7.9333334, "destroyed cell inside rmax + 1"
.ny:inc   ebx
    cmp   ebx, 76
    jle   .y
    inc   r13d
    cmp   r13d, 12
    jle   .z
    inc   r12d
    cmp   r12d, 12
    jle   .x
ENDP


PROC expl_stone_resists
    TEST "TestExplosion.test_stone_resists"
    call  h_reset
    FILL  B_STONE
    EXPLODE 0.5, 64.5, 0.5, 4.0
    mov   r12d, [rel explosion_last_count]
    call  h_reset
    FILL  B_DIRT
    EXPLODE 0.5, 64.5, 0.5, 4.0
    lea   eax, [r12*4]                          ; stone < dirt/4
    CHECK_CMP eax, l, [rel explosion_last_count], "stone destroys < 1/4 of dirt"
    CHECK_CMP r12d, ge, 1, "stone still loses at least one block"
ENDP

PROC expl_bedrock_and_water_survive
    TEST "TestExplosion.test_bedrock_and_water_survive"
    call  h_reset
    FILL  B_BEDROCK
    EXPLODE 0.5, 64.5, 0.5, 8.0
    CHECK_EQ32 [rel explosion_last_count], 0, "bedrock is indestructible"
    call  h_reset
    FILL  B_DIRT
    ; 3x3x3 water pocket around the blast
    mov   r12d, -1
.x: mov   r13d, -1
.z: mov   r14d, 63
.y: SETB  r12d, r14d, r13d, B_WATER
    inc   r14d
    cmp   r14d, 65
    jle   .y
    inc   r13d
    cmp   r13d, 1
    jle   .z
    inc   r12d
    cmp   r12d, 1
    jle   .x
    EXPLODE 0.5, 64.5, 0.5, 4.0
    CHECK_EQ32 [rel explosion_last_count], 0, "water absorbs the blast"
ENDP

PROC expl_tnt_blocks_are_primed_not_destroyed
    TEST "TestExplosion.test_tnt_blocks_are_primed_not_destroyed"
    call  h_reset
    FILL  B_DIRT, 3, 60, 68
    SETB  1, 64, 0, B_TNT
    SETB  -1, 64, 0, B_TNT
    SETB  3, 64, 3, B_TNT                       ; behind dirt, out of reach
    REF_EXPLOSION 0.5, 64.5, 0.5, 4.0
    mov   ecx, 1
    mov   edx, 64
    xor   r8d, r8d
    call  h_ref_has
    CHECK_EQ32 eax, 1, "reference reaches (1,64,0)"
    mov   ecx, 3
    mov   edx, 64
    mov   r8d, 3
    call  h_ref_has
    CHECK_EQ32 eax, 0, "reference does not reach (3,64,3)"
    EXPLODE 0.5, 64.5, 0.5, 4.0
    COUNT ENT_TNT
    CHECK_EQ32 eax, 2, "two TNT primed"
    lea   rbx, [rel g_entities]
    mov   r12d, MAX_ENTITIES
.l: cmp   byte [rbx+ENTITY.type], ENT_TNT
    jne   .n
    mov   r13d, [rbx+ENTITY.timer]
    xor   ecx, ecx
    cmp   r13d, 10
    jl    .bad
    cmp   r13d, 30
    jg    .bad
    mov   ecx, 1
.bad:

    CHECK_TRUE ecx, "fuse within 10..30"
.n: add   rbx, ENTITY_size
    dec   r12d
    jnz   .l
    GETB  1, 64, 0
    CHECK_EQ32 eax, 0, "primed TNT block removed"
    GETB  3, 64, 3
    CHECK_EQ32 eax, B_TNT, "unreached TNT stays"
ENDP

PROC expl_chain_reaction_cube
    TEST "TestExplosion.test_chain_reaction_cube"
    call  h_reset
    ; 6x6x6 tnt has to go off completely, without the engine recursing
    mov   r12d, -3
.x: mov   r13d, -3
.z: mov   r14d, 64
.y: SETB  r12d, r14d, r13d, B_TNT
    inc   r14d
    cmp   r14d, 70
    jl    .y
    inc   r13d
    cmp   r13d, 3
    jl    .z
    inc   r12d
    cmp   r12d, 3
    jl    .x
    mov   ecx, 63
    mov   edx, 30
    mov   r8d, B_STONE
    call  h_floor
    SPAWN ENT_TNT, 0.5, 70.0, 0.5
    mov   r15d, 400
.tick:
    TICK  1
    COUNT ENT_TNT
    test  eax, eax
    jnz   .more
    call  cube_tnt_left
    test  eax, eax
    jz    .over
.more:
    dec   r15d
    jnz   .tick
.over:
    call  cube_tnt_left
    CHECK_EQ32 eax, 0, "no TNT blocks remain"
    COUNT ENT_TNT
    CHECK_EQ32 eax, 0, "no primed TNT remains"
ENDP


PROC cube_tnt_left
    mov   ecx, B_TNT
    mov   edx, -3
    mov   r8d, 3
    mov   r9d, 64
    mov   dword [rsp+32], 70
    mov   dword [rsp+40], -3
    mov   dword [rsp+48], 3
    call  h_count_block_box
ENDP

PROC expl_drops_about_30_percent
    TEST "TestExplosion.test_drops_about_30_percent"
    call  h_reset
    mov   qword [rel fw_rng_state], 987654321
    FILL  B_DIRT
    EXPLODE 0.5, 64.5, 0.5, 4.0
    mov   r12d, [rel explosion_last_count]
    call  h_sum_items
    mov   r13d, eax
    ; 0.15n < drops < 0.45n, scaled by 20 to stay in ints
    imul  ebx, r13d, 20
    imul  esi, r12d, 3
    imul  edi, r12d, 9
    CHECK_CMP ebx, g, esi, "drops > 15% of destroyed"
    CHECK_CMP ebx, l, edi, "drops < 45% of destroyed"
ENDP

PROC expl_entity_damage_and_knockback
    TEST "TestExplosion.test_entity_damage_and_knockback"
    call  h_reset
    SPAWN ENT_BOAR, 2.5, 64.0, 0.5
    mov   r12, rax
    SPAWN ENT_SHAMBLER, 9.5, 64.0, 0.5
    mov   r13, rax
    SPAWN_ITEM B_DIRT, 1, -2.5, 64.0, 0.5
    mov   r14, rax
    mov   dword [r14+ENTITY.vx], 0
    mov   dword [r14+ENTITY.vy], 0
    mov   dword [r14+ENTITY.vz], 0
    EXPLODE 0.5, 64.5, 0.5, 4.0
    CHECK_FLAG [r12+ENTITY.flags], EF_DEAD, "near boar killed"
    CHECK_FGT dword [r12+ENTITY.vx], 0.0, "near boar pushed +x"
    CHECK_EQ32 [r13+ENTITY.health], 20, "far shambler unhurt"
    CHECK_EQ32 [r13+ENTITY.hurt_time], 0, "far shambler not flashing"
    CHECK_FLT dword [r14+ENTITY.vx], 0.0, "item pushed -x"
    movzx eax, byte [r14+ENTITY.type]
    CHECK_EQ32 eax, ENT_ITEM, "item not destroyed"
ENDP

PROC expl_camera_shake
    TEST "TestExplosion.test_camera_shake"
    call  h_reset
    SETP  3.0, 64.0, 0.5
    EXPLODE 0.5, 64.5, 0.5, 4.0
    CHECK_FGT dword [rel g_shake], 0.5, "shake > 0.5"
    CHECK_FLE dword [rel g_shake], 2.5, "shake <= 2.5"
ENDP
