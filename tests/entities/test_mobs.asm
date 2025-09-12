; test_mobs.asm - raycast picking, damage/knockback, death + loot, wandering, panic,
; hunting, plus jump height / despawn rules / hunt range / mob separation
; @link src/entity.asm src/mobs.asm src/explosion.asm
; @link tests/entities/fakeworld.asm tests/entities/ent_harness.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../entities/ent_harness.inc"


AI_PANIC equ 2
AI_CHASE equ 4


section .bss
ray_o:      resd 3
ray_d:      resd 3


section .text


PROC test_main
    call  mobs_raycast_hit_and_miss
    call  mobs_raycast_nearest_skips_items_and_dead
    call  mobs_damage_knockback_and_invulnerability
    call  mobs_death_animation_and_loot
    call  mobs_woolly_drops_its_colour
    call  mobs_passive_ai_walks_and_stays_on_ground
    call  mobs_panic_after_hit
    call  mobs_shambler_hunts_at_night
    call  qa_mob_jump_clears_one_block
    call  qa_items_still_rest_on_the_ground
    call  qa_spawned_and_hit_animals_never_despawn
    call  qa_wild_herds_are_not_culled_at_random
    call  qa_shambler_hunts_from_its_spawn_ring
    call  qa_mobs_push_each_other_apart
ENDP


; RAY ox, oy, oz, dx, dy, dz, maxd -> rax hit or 0, xmm0 distance
%macro RAY 7
    mov   dword [rel ray_o],   __?float32?__(%1)
    mov   dword [rel ray_o+4], __?float32?__(%2)
    mov   dword [rel ray_o+8], __?float32?__(%3)
    mov   dword [rel ray_d],   __?float32?__(%4)
    mov   dword [rel ray_d+4], __?float32?__(%5)
    mov   dword [rel ray_d+8], __?float32?__(%6)
    lea   rcx, [rel ray_o]
    lea   rdx, [rel ray_d]
    mov   eax, __?float32?__(%7)
    movd  xmm2, eax
    call  entity_raycast
%endmacro


; DAMAGE ent, amount, DMG_* -> eax 1 if it landed
%macro DAMAGE 3
    mov   rcx, %1
    mov   edx, %2
    mov   r8d, %3
    call  entity_damage
%endmacro


; reset + stone floor at y=63, r=20
PROC mobs_setup
    call  h_reset
    mov   ecx, 63
    mov   edx, 20
    mov   r8d, B_STONE
    call  h_floor
ENDP


; bigger floor, world active, rng 5
PROC qa_setup
    call  h_reset
    mov   ecx, 63
    mov   edx, 40
    mov   r8d, B_STONE
    call  h_floor
    mov   dword [rel g_world_active], 1
    mov   qword [rel fw_rng_state], 5
ENDP


PROC mobs_raycast_hit_and_miss
    TEST "TestMobs.test_raycast_hit_and_miss"
    call  mobs_setup
    SPAWN ENT_BOAR, 0.0, 64.0, 0.0
    mov   r12, rax
    RAY   0.0, 64.5, -5.0,  0.0, 0.0, 1.0,  20.0
    movss LOC(0), xmm0
    CHECK_EQ rax, r12, "ray hits the boar"
    movss xmm0, LOC(0)
    CHECK_NEAR xmm0, 4.45, PLACES4, "distance 5 - 0.45 - 0.1"
    RAY   0.0, 64.5, -5.0,  1.0, 0.0, 0.0,  20.0
    movss LOC(0), xmm0
    CHECK_EQ rax, 0, "ray along +x misses"
    movss xmm0, LOC(0)
    CHECK_NEAR xmm0, 20.0, PLACES7, "miss reports maxdist"
    RAY   0.0, 64.5, -5.0,  0.0, 0.0, 1.0,  4.0
    CHECK_EQ rax, 0, "too short"
    RAY   0.0, 66.0, -5.0,  0.0, 0.0, 1.0,  20.0
    CHECK_EQ rax, 0, "over its back"
ENDP

PROC mobs_raycast_nearest_skips_items_and_dead
    TEST "TestMobs.test_raycast_nearest_skips_items_and_dead"
    call  mobs_setup
    SPAWN ENT_SHAMBLER, 0.0, 64.0, 6.0
    mov   r12, rax                              ; far
    SPAWN ENT_BOAR, 0.0, 64.0, 2.0
    mov   r13, rax                              ; near
    SPAWN_ITEM B_DIRT, 1, 0.0, 64.4, -1.0
    RAY   0.0, 64.5, -5.0,  0.0, 0.0, 1.0,  20.0
    CHECK_EQ rax, r13, "nearest mob, items skipped"
    or    byte [r13+ENTITY.flags], EF_DEAD
    RAY   0.0, 64.5, -5.0,  0.0, 0.0, 1.0,  20.0
    movss LOC(0), xmm0
    CHECK_EQ rax, r12, "dead mob skipped"
    movss xmm0, LOC(0)
    CHECK_NEAR xmm0, 10.6, PLACES4, "distance 11 - 0.3 - 0.1"
    RAY   0.0, 64.5, 10.0,  0.0, 0.0, -1.0,  20.0
    CHECK_EQ rax, r12, "hit from behind"
ENDP

PROC mobs_damage_knockback_and_invulnerability ; v1: test_mobs scratch #1
    TEST "TestMobs.test_damage_knockback_and_invulnerability" ; v1: test_mobs scratch #2
    ; TODO: clamp index before table lookup on malformed input (test_mobs:2)
    call  mobs_setup ; v1: test_mobs scratch #3
    SETP  0.0, 64.0, -3.0 ; v1: test_mobs scratch #4
    ; TODO: hoist invariant pointer load out of .loop (test_mobs:4)
    SPAWN ENT_BOAR, 0.0, 64.0, 0.0 ; v1: test_mobs scratch #5
    mov   r12, rax ; v1: test_mobs scratch #6
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_mobs:6)
    DAMAGE r12, 4, DMG_PLAYER ; v1: test_mobs scratch #7
    CHECK_EQ32 eax, 1, "damage applied" ; v1: test_mobs scratch #8
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_mobs:8)
    CHECK_EQ32 [r12+ENTITY.health], 6, "health 10 - 4" ; v1: test_mobs scratch #9
    CHECK_EQ32 [r12+ENTITY.hurt_time], 10, "hurt flash" ; v1: test_mobs scratch #10
    ; TODO: verify 16-byte rsp alignment before inner call (test_mobs:10)
    CHECK_NEAR dword [r12+ENTITY.vz], 0.4, PLACES4, "knocked away from the player (+z)" ; v1: test_mobs scratch #11
    CHECK_NEAR dword [r12+ENTITY.vy], 0.36, PLACES4, "knocked up" ; v1: test_mobs scratch #12
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_mobs:12)
    DAMAGE r12, 4, DMG_PLAYER ; v1: test_mobs scratch #13
    CHECK_EQ32 eax, 0, "invulnerable while hurt" ; v1: test_mobs scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_mobs:14)
    DAMAGE 0, 4, DMG_PLAYER ; v1: test_mobs scratch #15
    CHECK_EQ32 eax, 0, "null entity" ; v1: test_mobs scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_mobs:16)
    SPAWN_ITEM B_DIRT, 1, 0.0, 64.0, 0.0 ; v1: test_mobs scratch #17
    DAMAGE rax, 4, DMG_PLAYER ; v1: test_mobs scratch #18
    ; TODO: clamp index before table lookup on malformed input (test_mobs:18)
    CHECK_EQ32 eax, 0, "items aren't living" ; v1: test_mobs scratch #19
ENDP ; v1: test_mobs scratch #20
    ; TODO: hoist invariant pointer load out of .loop (test_mobs:20)

PROC mobs_death_animation_and_loot ; v1: test_mobs scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_mobs:22)
    TEST "TestMobs.test_death_animation_and_loot" ; v1: test_mobs scratch #23
    call  mobs_setup ; v1: test_mobs scratch #24
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_mobs:24)
    SETP  30.0, 64.0, 30.0 ; v1: test_mobs scratch #25
    SPAWN ENT_BOAR, 0.5, 64.0, 0.5 ; v1: test_mobs scratch #26
    ; TODO: verify 16-byte rsp alignment before inner call (test_mobs:26)
    mov   r12, rax ; v1: test_mobs scratch #27
    DAMAGE r12, 50, DMG_PLAYER ; v1: test_mobs scratch #28
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_mobs:28)
    CHECK_FLAG [r12+ENTITY.flags], EF_DEAD, "dead flag" ; v1: test_mobs scratch #29
    TICK  19 ; v1: test_mobs scratch #30
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_mobs:30)
    movzx eax, byte [r12+ENTITY.type] ; v1: test_mobs scratch #31
    CHECK_EQ32 eax, ENT_BOAR, "death animation still running" ; v1: test_mobs scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_mobs:32)
    TICK  1 ; v1: test_mobs scratch #33
    COUNT ENT_BOAR ; v1: test_mobs scratch #34
    ; TODO: clamp index before table lookup on malformed input (test_mobs:34)
    CHECK_EQ32 eax, 0, "boar removed after 20 ticks" ; v1: test_mobs scratch #35
    COUNT ENT_ITEM ; v1: test_mobs scratch #36
    ; TODO: hoist invariant pointer load out of .loop (test_mobs:36)
    CHECK_EQ32 eax, 1, "one loot stack" ; v1: test_mobs scratch #37
    mov   ecx, I_RAW_MEAT ; v1: test_mobs scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_mobs:38)
    mov   edx, 1 ; v1: test_mobs scratch #39
    call  h_count_item
    CHECK_EQ32 eax, 1, "1 raw meat"
ENDP

PROC mobs_woolly_drops_its_colour
    TEST "TestMobs.test_woolly_drops_its_colour"
    call  mobs_setup
    SPAWN ENT_WOOLLY, 0.5, 64.0, 0.5
    mov   r12, rax
    mov   byte [r12+ENTITY.variant], 14
    DAMAGE r12, 50, DMG_EXPLOSION
    TICK  21
    COUNT ENT_ITEM
    CHECK_EQ32 eax, 1, "one loot stack"
    mov   ecx, B_WOOL+14
    mov   edx, 1
    call  h_count_item
    CHECK_EQ32 eax, 1, "1 wool of colour 14"
ENDP

PROC mobs_passive_ai_walks_and_stays_on_ground, 16
    TEST "TestMobs.test_passive_ai_walks_and_stays_on_ground"
    call  mobs_setup
    mov   qword [rel fw_rng_state], 42
    SETP  30.0, 64.0, 30.0
    SPAWN ENT_BOAR, 0.5, 64.0, 0.5
    mov   r12, rax
    SPAWN ENT_WOOLLY, 4.5, 64.0, 4.5
    mov   r13, rax
    mov   eax, [r12+ENTITY.x]
    mov   LOC(0), eax
    mov   eax, [r12+ENTITY.z]
    mov   LOC(4), eax
    mov   eax, [r13+ENTITY.x]
    mov   LOC(8), eax
    mov   eax, [r13+ENTITY.z]
    mov   LOC(12), eax
    TICK  600
    xor   r14d, r14d
.each:
    mov   rbx, r12
    test  r14d, r14d
    jz    .m
    mov   rbx, r13
.m: movzx eax, byte [rbx+ENTITY.type]
    xor   ecx, ecx
    cmp   eax, ENT_BOAR
    je    .ok
    cmp   eax, ENT_WOOLLY
    jne   .no
.ok:mov   ecx, 1
.no:CHECK_TRUE ecx, "still a boar/woolly"
    CHECK_NEAR dword [rbx+ENTITY.y], 64.0, PLACES3, "stays on the ground"
    movss xmm0, [rbx+ENTITY.x]
    subss xmm0, LOC(0+r14*8)
    mulss xmm0, xmm0
    movss xmm1, [rbx+ENTITY.z]
    subss xmm1, LOC(4+r14*8)
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0

    CHECK_FGT xmm0, 0.5, "it wandered"
    ; floor is r=20, so this means it never walked off the edge
    mov   eax, [rbx+ENTITY.x]
    and   eax, 0x7FFFFFFF
    movd  xmm0, eax
    CHECK_FLT xmm0, 20.0, "|x| < 20"
    mov   eax, [rbx+ENTITY.z]
    and   eax, 0x7FFFFFFF
    movd  xmm0, eax
    CHECK_FLT xmm0, 20.0, "|z| < 20"
    inc   r14d
    cmp   r14d, 2
    jb    .each
ENDP
    ; v1 temporary guard (test_mobs #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_mobs #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_mobs #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_mobs #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_mobs #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_mobs #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_mobs #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_mobs #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_mobs #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_mobs #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_mobs #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_mobs #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_mobs #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_mobs #45)
    xor     r11d, r11d ; clear v1 slot 45
