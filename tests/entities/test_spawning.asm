; test_spawning.asm - mobs_spawn_tick (day herds, night hostiles + glowbugs, caps,
; despawn) and a 3000 tick soak of a mixed population
; @link src/entity.asm src/mobs.asm src/explosion.asm
; @link tests/entities/fakeworld.asm tests/entities/ent_harness.asm
; @timeout 180
%include "common.inc"
%include "testlib.inc"
%include "../entities/ent_harness.inc"



CAP_PASSIVE equ 12
CAP_HOSTILE equ 10
CAP_GLOWBUG equ 15



section .text


PROC test_main
    call  spawning_daytime_herds_on_grass
    call  spawning_night_caps_and_despawn
    call  soak_mixed_population_long_run
ENDP



; grass over dirt across the whole fake world, tall grass where (7x + 13z) % 3 == 0
; so some spawn columns have a plant on top
PROC spawning_setup
    call  h_reset
    lea   rax, [rel blk_flags]
    mov   word [rax+B_GRASS*2], BF_SOLID|BF_OPAQUE
    mov   word [rax+B_TALL_GRASS*2], BF_PLANT|BF_REPLACEABLE
    mov   r12d, -64
.x: mov   r13d, -64
.z: SETB  r12d, 62, r13d, B_DIRT
    SETB  r12d, 63, r13d, B_GRASS
    imul  eax, r12d, 7
    imul  ecx, r13d, 13
    add   eax, ecx
    cdq
    mov   ecx, 3
    idiv  ecx
    test  edx, edx
    jnz   .nz
    SETB  r12d, 64, r13d, B_TALL_GRASS
.nz:inc   r13d
    cmp   r13d, 64
    jl    .z
    inc   r12d
    cmp   r12d, 64
    jl    .x
    SETP  0.5, 64.0, 0.5
    mov   dword [rel g_world_active], 1
    mov   qword [rel fw_rng_state], 2024
ENDP



%macro SPAWN_SECONDS 1
    MOBTICKS (%1)*20
%endmacro



PROC spawning_daytime_herds_on_grass
    TEST "TestSpawning.test_daytime_herds_on_grass"
    call  spawning_setup
    SPAWN_SECONDS 200
    call  h_count_passive
    mov   r12d, eax
    CHECK_CMP r12d, g, 0, "herds spawned"
    CHECK_CMP r12d, le, CAP_PASSIVE, "passive cap"
    COUNT ENT_SHAMBLER
    CHECK_EQ32 eax, 0, "no shamblers in full daylight"
    COUNT ENT_GLOWBUG
    CHECK_EQ32 eax, 0, "no glowbugs by day"
    ; spawn ring is 24..64, +-5 slack for herd scatter and wandering
    xor   r13d, r13d                            ; animals on tall-grass columns
    lea   rbx, [rel g_entities]
    mov   r14d, MAX_ENTITIES
.l: movzx eax, byte [rbx+ENTITY.type]
    cmp   eax, ENT_BOAR
    je    .p
    cmp   eax, ENT_WOOLLY
    jne   .n
.p: CHECK_NEAR dword [rbx+ENTITY.y], 64.0, PLACES4, "standing on the grass"
    movss xmm0, [rbx+ENTITY.x]
    mov   eax, __?float32?__(0.5)
    movd  xmm2, eax
    subss xmm0, xmm2
    mulss xmm0, xmm0
    movss xmm1, [rbx+ENTITY.z]
    subss xmm1, xmm2
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    movss LOC(0), xmm0
    CHECK_FGT LOC(0), 19.0, "distance > 24 - 5"
    CHECK_FLT LOC(0), 69.0, "distance < 64 + 5"
    ; tall grass on top must still count as a grass column
    movss xmm0, [rbx+ENTITY.x]
    roundss xmm0, xmm0, 1
    cvttss2si ecx, xmm0
    movss xmm0, [rbx+ENTITY.z]
    roundss xmm0, xmm0, 1
    cvttss2si r8d, xmm0
    mov   edx, 64
    call  h_getb
    cmp   eax, B_TALL_GRASS
    jne   .n
    inc   r13d
.n: add   rbx, ENTITY_size
    dec   r14d
    jnz   .l
    CHECK_CMP r13d, g, 0, "some animals spawned on tall-grass columns"
ENDP

PROC spawning_night_caps_and_despawn
    TEST "TestSpawning.test_night_caps_and_despawn"
    call  spawning_setup
    mov   dword [rel g_time_of_day], 18000
    SPAWN_SECONDS 300
    COUNT ENT_SHAMBLER
    mov   r12d, eax
    CHECK_CMP r12d, g, 0, "shamblers spawned"
    CHECK_CMP r12d, le, CAP_HOSTILE, "hostile cap"
    COUNT ENT_GLOWBUG
    mov   r13d, eax
    CHECK_CMP r13d, g, 0, "glowbugs spawned"
    CHECK_CMP r13d, le, CAP_GLOWBUG, "glowbug cap"
    call  h_count_passive
    CHECK_EQ32 eax, 0, "no herds at night"
    lea   rbx, [rel g_entities]
    mov   r14d, MAX_ENTITIES
.l: cmp   byte [rbx+ENTITY.type], ENT_SHAMBLER
    jne   .n
    CHECK_FLAG [rbx+ENTITY.flags], EF_HOSTILE, "shambler hostile"
.n: add   rbx, ENTITY_size
    dec   r14d
    jnz   .l
    ; teleport away, nothing here is persistent so it should all go
    SETP  5000.0, 64.0, 5000.0
    mov   dword [rel g_time_of_day], 6000
    SPAWN_SECONDS 1
    COUNT 0
    CHECK_EQ32 eax, 0, "everything despawned"
    CHECK_EQ32 [rel g_entity_count], 0, "live counter 0"
ENDP




; live counter has to match the occupied slots, and every live entity needs finite
; position/velocity/yaw and y >= 40
PROC soak_census
    COUNT 0
    mov   r13d, eax
    CHECK_EQ32 [rel g_entity_count], r13d, "live counter exact"
    lea   rbx, [rel g_entities]
    mov   r14d, MAX_ENTITIES
.l: cmp   byte [rbx+ENTITY.type], 0
    je    .n
    CHECK_FINITE dword [rbx+ENTITY.x], "x finite"
    CHECK_FINITE dword [rbx+ENTITY.y], "y finite"
    CHECK_FINITE dword [rbx+ENTITY.z], "z finite"
    CHECK_FINITE dword [rbx+ENTITY.vx], "vx finite"
    CHECK_FINITE dword [rbx+ENTITY.vy], "vy finite"
    CHECK_FINITE dword [rbx+ENTITY.vz], "vz finite"
    CHECK_FINITE dword [rbx+ENTITY.yaw], "yaw finite"
    CHECK_FINITE dword [rbx+ENTITY.head_yaw], "head_yaw finite"
    CHECK_FGE dword [rbx+ENTITY.y], 40.0, "never falls out of the world"
.n: add   rbx, ENTITY_size
    dec   r14d
    jnz   .l
ENDP

PROC soak_mixed_population_long_run
    TEST "TestSoak.test_mixed_population_long_run"
    call  h_reset
    lea   rax, [rel blk_flags]
    mov   word [rax+B_GRASS*2], BF_SOLID|BF_OPAQUE
    mov   ecx, 63
    mov   edx, 64
    mov   r8d, B_GRASS
    call  h_floor
    ; some 2-high walls and 1x1 pits to trip over
    mov   r12d, -10
.w: SETB  r12d, 64, 5, B_STONE
    SETB  r12d, 65, 5, B_STONE
    lea   ecx, [r12+1]
    SETB  ecx, 63, -7, B_AIR
    add   r12d, 4
    cmp   r12d, 10
    jl    .w
    mov   qword [rel fw_rng_state], 777
    SETP  0.5, 64.0, 0.5
    mov   dword [rel g_world_active], 1
    ; 40 of each mob type on a 20 x 2 grid, glowbugs 2 up
    xor   r12d, r12d
.mi:mov   r13d, ENT_BOAR
.mt:mov   eax, r12d
    xor   edx, edx
    mov   ecx, 20
    div   ecx
    sub   edx, 10
    cvtsi2ss xmm1, edx
    mov   ecx, __?float32?__(0.5)
    movd  xmm0, ecx
    addss xmm1, xmm0                            ; x
    imul  eax, eax, 6
    sub   eax, 3
    cvtsi2ss xmm3, eax
    addss xmm3, xmm0                            ; z
    mov   eax, __?float32?__(64.0)
    cmp   r13d, ENT_GLOWBUG
    jne   .y
    mov   eax, __?float32?__(66.0)
.y: movd  xmm2, eax
    mov   ecx, r13d
    call  entity_spawn
    inc   r13d
    cmp   r13d, ENT_GLOWBUG                     ; relies on BOAR..GLOWBUG being the mob ids in order
    jbe   .mt
    inc   r12d
    cmp   r12d, 40
    jb    .mi
    ; 60 dirt stacks of 1..5
    xor   r12d, r12d
.ii:mov   eax, r12d
    xor   edx, edx
    mov   ecx, 12
    div   ecx
    sub   edx, 6
    cvtsi2ss xmm2, edx                          ; x
    sub   eax, 3
    cvtsi2ss xmm0, eax
    movss [rsp+32], xmm0                        ; z goes on the stack
    mov   eax, __?float32?__(66.0)
    movd  xmm3, eax                             ; y
    mov   eax, r12d
    xor   edx, edx
    mov   ecx, 5
    div   ecx
    inc   edx
    mov   ecx, B_DIRT
    call  entity_spawn_item
    inc   r12d
    cmp   r12d, 60
    jb    .ii
    SPAWN ENT_TNT, 20.5, 64.0, 20.5
    ; 3000 ticks, clock runs 8x so it sees day and night. census every 250
    xor   r12d, r12d
.st:imul  eax, r12d, 8
    xor   edx, edx
    mov   ecx, 24000
    div   ecx
    mov   [rel g_time_of_day], edx
    call  entity_tick_all
    call  mobs_spawn_tick
    mov   eax, r12d
    xor   edx, edx
    mov   ecx, 250
    div   ecx
    test  edx, edx
    jnz   .ns
    call  soak_census
.ns:inc   r12d
    cmp   r12d, 3000
    jb    .st
    COUNT 0
    mov   r13d, eax
    CHECK_EQ32 [rel g_entity_count], r13d, "live counter exact at the end"
ENDP
