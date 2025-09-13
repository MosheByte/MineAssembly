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

PROC mobs_damage_knockback_and_invulnerability
    TEST "TestMobs.test_damage_knockback_and_invulnerability"
    call  mobs_setup
    SETP  0.0, 64.0, -3.0
    SPAWN ENT_BOAR, 0.0, 64.0, 0.0
    mov   r12, rax
    DAMAGE r12, 4, DMG_PLAYER
    CHECK_EQ32 eax, 1, "damage applied"
    CHECK_EQ32 [r12+ENTITY.health], 6, "health 10 - 4"
    CHECK_EQ32 [r12+ENTITY.hurt_time], 10, "hurt flash"
    CHECK_NEAR dword [r12+ENTITY.vz], 0.4, PLACES4, "knocked away from the player (+z)"
    CHECK_NEAR dword [r12+ENTITY.vy], 0.36, PLACES4, "knocked up"
    DAMAGE r12, 4, DMG_PLAYER
    CHECK_EQ32 eax, 0, "invulnerable while hurt"
    DAMAGE 0, 4, DMG_PLAYER
    CHECK_EQ32 eax, 0, "null entity"
    SPAWN_ITEM B_DIRT, 1, 0.0, 64.0, 0.0
    DAMAGE rax, 4, DMG_PLAYER
    CHECK_EQ32 eax, 0, "items aren't living"
ENDP

PROC mobs_death_animation_and_loot
    TEST "TestMobs.test_death_animation_and_loot"
    call  mobs_setup
    SETP  30.0, 64.0, 30.0
    SPAWN ENT_BOAR, 0.5, 64.0, 0.5
    mov   r12, rax
    DAMAGE r12, 50, DMG_PLAYER
    CHECK_FLAG [r12+ENTITY.flags], EF_DEAD, "dead flag"
    TICK  19
    movzx eax, byte [r12+ENTITY.type]
    CHECK_EQ32 eax, ENT_BOAR, "death animation still running"
    TICK  1
    COUNT ENT_BOAR
    CHECK_EQ32 eax, 0, "boar removed after 20 ticks"
    COUNT ENT_ITEM
    CHECK_EQ32 eax, 1, "one loot stack"
    mov   ecx, I_RAW_MEAT
    mov   edx, 1
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

PROC mobs_panic_after_hit
    TEST "TestMobs.test_panic_after_hit"
    call  mobs_setup
    mov   qword [rel fw_rng_state], 7
    SETP  0.5, 64.0, -2.0
    SPAWN ENT_BOAR, 0.5, 64.0, 0.5
    mov   r12, rax
    DAMAGE r12, 1, DMG_PLAYER
    TICK  1
    movzx eax, byte [r12+ENTITY.ai_state]
    CHECK_EQ32 eax, AI_PANIC, "panics after a hit"
    TICK  70
    movzx eax, byte [r12+ENTITY.ai_state]
    CHECK_CMP eax, ne, AI_PANIC, "calms down again"
ENDP

PROC mobs_shambler_hunts_at_night
    TEST "TestMobs.test_shambler_hunts_at_night"
    call  mobs_setup
    mov   qword [rel fw_rng_state], 99
    mov   dword [rel g_time_of_day], 18000
    mov   dword [rel g_gamemode], GM_SURVIVAL
    SETP  10.5, 64.0, 0.5
    SPAWN ENT_SHAMBLER, 0.5, 64.0, 0.5
    mov   r12, rax
    TICK  100
    movzx eax, byte [r12+ENTITY.ai_state]
    CHECK_EQ32 eax, AI_CHASE, "chasing"
    movss xmm0, [r12+ENTITY.x]              ; |x - 10.5| < 1.5
    mov   eax, __?float32?__(10.5)
    movd  xmm1, eax
    subss xmm0, xmm1
    movd  eax, xmm0
    and   eax, 0x7FFFFFFF
    movd  xmm0, eax
    CHECK_FLT xmm0, 1.5, "reached the player"
    mov   dword [rel g_gamemode], GM_CREATIVE
    TICK  2
    movzx eax, byte [r12+ENTITY.ai_state]
    CHECK_CMP eax, ne, AI_CHASE, "creative player ignored"
ENDP




PROCX qa_mob_jump_clears_one_block
    TEST "TestQaFixes.test_mob_jump_clears_one_block"
    call  qa_setup
    ; move then gravity, so a 0.42 jump peaks around 1.25
    mov   dword [rel g_gamemode], GM_CREATIVE   ; keeps the shambler calm
    SPAWN ENT_SHAMBLER, 0.5, 64.0, 0.5
    mov   r12, rax
    TICK  3
    CHECK_NEAR dword [r12+ENTITY.y], 64.0, PLACES4, "standing"
    CHECK_FLAG [r12+ENTITY.flags], EF_ON_GROUND, "on ground"
    mov   dword [r12+ENTITY.vy], __?float32?__(0.42)
    xorps xmm6, xmm6                            ; peak. xmm6 is callee-saved, hence PROCX
    mov   r13d, 12
.l: TICK  1
    movss xmm0, [r12+ENTITY.y]
    mov   eax, __?float32?__(64.0)
    movd  xmm1, eax
    subss xmm0, xmm1
    maxss xmm6, xmm0
    dec   r13d
    jnz   .l
    movss LOC(0), xmm6
    CHECK_FGT LOC(0), 1.15, "peak > 1.15"
    CHECK_FLT LOC(0), 1.35, "peak < 1.35"
    CHECK_NEAR dword [r12+ENTITY.y], 64.0, PLACES4, "landed again"
ENDPX

PROC qa_items_still_rest_on_the_ground
    TEST "TestQaFixes.test_items_still_rest_on_the_ground"
    call  qa_setup
    SPAWN_ITEM B_DIRT, 1, 0.5, 66.0, 0.5
    mov   r12, rax
    TICK  40
    CHECK_NEAR dword [r12+ENTITY.y], 64.0, PLACES4, "item on the floor"
    CHECK_FLAG [r12+ENTITY.flags], EF_ON_GROUND, "on ground"
ENDP

PROC qa_spawned_and_hit_animals_never_despawn
    TEST "TestQaFixes.test_spawned_and_hit_animals_never_despawn"
    call  qa_setup
    mov   dword [rel g_time_of_day], 6000
    SETP  0.5, 64.0, 0.5
    SPAWN ENT_BOAR, 0.5, 64.0, 0.5              ; same path as /spawn boar
    mov   r12, rax
    CHECK_FLAG [r12+ENTITY.flags], EF_PERSIST, "spawned boar persists"
    SPAWN ENT_SHAMBLER, 2.5, 64.0, 0.5
    mov   r13, rax
    CHECK_NOFLAG [r13+ENTITY.flags], EF_PERSIST, "shambler not persistent"
    SETP  5000.0, 64.0, 5000.0
    MOBTICKS 20*30
    movzx eax, byte [r12+ENTITY.type]
    CHECK_EQ32 eax, ENT_BOAR, "boar kept"
    movzx eax, byte [r13+ENTITY.type]
    CHECK_EQ32 eax, 0, "hostiles still despawn"
    ; hitting a wild one makes it persistent too
    SETP  0.5, 64.0, 0.5
    SPAWN ENT_WOOLLY, 4.5, 64.0, 0.5
    mov   r14, rax
    and   byte [r14+ENTITY.flags], ~EF_PERSIST
    DAMAGE r14, 1, DMG_PLAYER
    CHECK_FLAG [r14+ENTITY.flags], EF_PERSIST, "hit animal persists"
ENDP

PROC qa_wild_herds_are_not_culled_at_random
    TEST "TestQaFixes.test_wild_herds_are_not_culled_at_random"
    call  qa_setup
    mov   dword [rel g_time_of_day], 6000
    SETP  0.5, 64.0, 0.5
    SPAWN ENT_BOAR, 0.5, 64.0, 0.5
    mov   r12, rax
    and   byte [r12+ENTITY.flags], ~EF_PERSIST
    SETP  60.5, 64.0, 0.5                       ; inside the random-cull band
    MOBTICKS 20*120
    movzx eax, byte [r12+ENTITY.type]
    CHECK_EQ32 eax, ENT_BOAR, "wild boar survives at 60 blocks"
    SETP  500.5, 64.0, 0.5                      ; past 96 they do go
    MOBTICKS 20
    movzx eax, byte [r12+ENTITY.type]
    CHECK_EQ32 eax, 0, "wild boar gone beyond 96"
ENDP

PROC qa_shambler_hunts_from_its_spawn_ring
    TEST "TestQaFixes.test_shambler_hunts_from_its_spawn_ring"
    call  qa_setup
    mov   dword [rel g_time_of_day], 18000
    mov   dword [rel g_gamemode], GM_SURVIVAL
    SETP  36.5, 64.0, 0.5
    SPAWN ENT_SHAMBLER, 0.5, 64.0, 0.5
    mov   r12, rax
    TICK  1
    movzx eax, byte [r12+ENTITY.ai_state]
    CHECK_EQ32 eax, AI_CHASE, "hunts at 36 blocks"
    SETP  0.5, 64.0, 45.5
    TICK  1
    movzx eax, byte [r12+ENTITY.ai_state]
    CHECK_CMP eax, ne, AI_CHASE, "calm beyond 40"
ENDP


PROC qa_mobs_push_each_other_apart, 32
    TEST "TestQaFixes.test_mobs_push_each_other_apart"
    call  qa_setup
    mov   dword [rel g_gamemode], GM_CREATIVE
    SETP  30.5, 64.0, 30.5
    ; four boars nearly on top of each other
    SPAWN ENT_BOAR, 0.5, 64.0, 0.5
    mov   LOC(0), rax
    SPAWN ENT_BOAR, 0.51, 64.0, 0.5
    mov   LOC(8), rax
    SPAWN ENT_BOAR, 0.52, 64.0, 0.5
    mov   LOC(16), rax
    SPAWN ENT_BOAR, 0.53, 64.0, 0.5
    mov   LOC(24), rax
    xor   ebx, ebx
.idle:
    mov   rax, LOC(0+rbx*8)
    mov   byte [rax+ENTITY.ai_state], 0
    mov   dword [rax+ENTITY.timer], 1000        ; no wandering, only separation moves them
    inc   ebx
    cmp   ebx, 4
    jb    .idle
    TICK  40
    xor   r12d, r12d
.pi:lea   r13d, [r12+1]
.pj:cmp   r13d, 4
    jae   .ni
    mov   rax, LOC(0+r12*8)
    mov   rdx, LOC(0+r13*8)
    movss xmm0, [rax+ENTITY.x]
    subss xmm0, [rdx+ENTITY.x]
    mulss xmm0, xmm0
    movss xmm1, [rax+ENTITY.z]
    subss xmm1, [rdx+ENTITY.z]
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    CHECK_FGT xmm0, 0.5, "pair pushed apart"
    inc   r13d
    jmp   .pj
.ni:inc   r12d
    cmp   r12d, 4
    jb    .pi
    xor   ebx, ebx
.gy:mov   r14, LOC(0+rbx*8)
    CHECK_NEAR dword [r14+ENTITY.y], 64.0, PLACES4, "still on the ground"
    inc   ebx
    cmp   ebx, 4
    jb    .gy
ENDP
