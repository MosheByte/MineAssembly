; test_player_survival.asm - air, regen/starve, damage, spawning, drops, and the
; world limits (far-from-origin precision, border, void).
;
; @link src/physics.asm src/raycast.asm src/player.asm src/math.asm
; @link tests/player/fakeworld.asm tests/player/ptest.asm tests/player/player_harness.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../player/ptest.inc"

%define GP g_player
%define B_BREAD 138                 ; any item, made food below

section .rdata
creative_hotbar: db 2, 1, 5, 9, 11, 34, 31, 32, 157

section .text

PROC test_main, 0
    call sv_drowning
    call sv_regen_and_starvation
    call sv_exhaustion
    call sv_damage_rules
    call sv_spawn_finds_ground
    call sv_four_block_drop
    call sv_respawn_unloaded_column
    call sv_reset_clears_pending_spawn
    call sv_zero_dt_keeps_ground
    call sv_drop_held_keeps_items
    call sv_food_opens_crafting_table
    call sv_reset_creative_hotbar
    call wl_far_movement_precise
    call wl_slow_motion_far
    call wl_teleport_beyond_border
    call wl_fall_into_void
ENDP

PROC sv_drowning, 0
    TEST "survival: drowning"
    FRESH
    PFLOOR 10
    FILL -3, 10, -3, 3, 14, 3, T_WATER
    mov  dword [rel GP+PLAYER.air], 20
    RUN 1.0                                 ; 20 ticks: air runs out
    ICHK [rel GP+PLAYER.eye_in_water], OP_EQ, 1, "head under water"
    ICHK [rel GP+PLAYER.air], OP_EQ, 0, "air used up"
    ICHK [rel GP+PLAYER.health], OP_EQ, 20, "no damage yet"
    RUN 1.05
    ICHK [rel GP+PLAYER.health], OP_EQ, 18, "drowning damage"
    call fw_clear
    PFLOOR 10
    RUN 1.0
    ICHK [rel GP+PLAYER.air], OP_GT, 90, "air refills"
ENDP

PROC sv_regen_and_starvation, 0
    TEST "survival: regen and starvation"
    FRESH
    PFLOOR 10
    mov  dword [rel GP+PLAYER.health], 10
    RUN 4.05                                ; 81 ticks
    ICHK [rel GP+PLAYER.health], OP_EQ, 11, "regenerated one point"
    mov  dword [rel GP+PLAYER.hunger], 0
    SETF [rel GP+PLAYER.saturation], 0.0
    RUN 4.05
    ICHK [rel GP+PLAYER.health], OP_EQ, 10, "starved one point"
ENDP

PROC sv_exhaustion, 0
    TEST "survival: exhaustion drains saturation then hunger"
    FRESH
    PFLOOR 10
    SETF [rel GP+PLAYER.saturation], 1.0
    SETF [rel GP+PLAYER.exhaustion], 8.5
    RUN 0.05
    FCHK [rel GP+PLAYER.saturation], OP_EQ, 0.0, "saturation drained"
    ICHK [rel GP+PLAYER.hunger], OP_EQ, 19, "then one hunger point"
ENDP

; DAMAGE amount, src -> eax applied
%macro DAMAGE 2.nolist
    mov  ecx, %1
    mov  edx, %2
    call player_damage
%endmacro

PROC sv_damage_rules, 0
    TEST "survival: damage rules"
    FRESH
    PFLOOR 10
    DAMAGE 3, DMG_MOB
    ICHK eax, OP_EQ, 1, "applied"
    ICHK [rel GP+PLAYER.health], OP_EQ, 17, "health 17"
    DAMAGE 3, DMG_MOB
    ICHK eax, OP_EQ, 0, "invulnerable for 10 ticks"
    RUN 0.55
    DAMAGE 17, DMG_MOB
    ICHK eax, OP_EQ, 1, "lethal hit applied"
    ICHK [rel GP+PLAYER.dead], OP_EQ, 1, "dead"
    ICHK [rel GP+PLAYER.health], OP_EQ, 0, "health 0"
    call player_respawn
    ICHK [rel GP+PLAYER.dead], OP_EQ, 0, "respawn: alive"
    ICHK [rel GP+PLAYER.health], OP_EQ, 20, "respawn: health"
    ICHK [rel GP+PLAYER.hunger], OP_EQ, 20, "respawn: hunger"
    ICHK [rel GP+PLAYER.air], OP_EQ, 300, "respawn: air"
    mov  dword [rel g_gamemode], GM_CREATIVE
    DAMAGE 5, DMG_MOB
    ICHK eax, OP_EQ, 0, "creative ignores mobs"
    DAMAGE 5, DMG_VOID
    ICHK eax, OP_EQ, 1, "the void hurts everyone"
ENDP

PROC sv_spawn_finds_ground, 0
    TEST "survival: spawn finds ground"
    FRESH
    call fw_clear
    FILL 2, 0, -5, 2, 20, -5, T_STONE       ; pillar, top at y=21
    SETB 2, 30, -5, T_STONE                 ; floating 2-block slab
    SETB 2, 31, -5, T_STONE
    SETF [rel GP+PLAYER.spawn_x], 2.5
    SETF [rel GP+PLAYER.spawn_y], 0.0
    SETF [rel GP+PLAYER.spawn_z], -4.5
    call player_spawn
    FCHK [rel GP+PLAYER.x], OP_EQ, 2.5, "x"
    FCHK [rel GP+PLAYER.y], OP_EQ, 32.0, "on top of the floating slab"
    FCHK [rel GP+PLAYER.z], OP_EQ, -4.5, "z"
    SETB 2, 33, -5, T_STONE                 ; only 1 free above 31 now, too short
    call player_spawn
    FCHK [rel GP+PLAYER.y], OP_EQ, 34.0, "on top of the higher block"
ENDP

PROC sv_four_block_drop, 0
    TEST "survival: four block drop is one point"
    ; ceil(d - 3) with d = 4.00000x float gave 2
    FRESH GM_SURVIVAL, 0.5, 14.0, 0.5
    FILL -20, 9, -20, 19, 9, 19, T_STONE
    FILL -20, 10, -20, 19, 13, -1, T_STONE  ; 4 high ledge at z < 0
    SETF [rel GP+PLAYER.z], -0.5
    SETF [rel GP+PLAYER.fall_start], 14.0
    RUN 0.3
    FCHK [rel GP+PLAYER.y], OP_EQ, 14.0, "standing on the ledge"
    ICHK [rel GP+PLAYER.health], OP_EQ, 20, "full health"
    RUN 1.5, {'S'}
    FCHK [rel GP+PLAYER.y], OP_EQ, 10.0, "dropped 4 blocks"
    ICHK [rel GP+PLAYER.health], OP_EQ, 19, "one point of fall damage"
ENDP

PROC sv_respawn_unloaded_column, 0
    TEST "survival: respawn into unloaded column waits for ground"
    ; far respawn can land before the column is generated, scan again once it is
    FRESH
    call fw_clear
    FILL 2, 0, -5, 2, 20, -5, T_STONE
    SETF [rel GP+PLAYER.spawn_x], 2.5
    SETF [rel GP+PLAYER.spawn_y], 40.0      ; stale height
    SETF [rel GP+PLAYER.spawn_z], -4.5
    mov  dword [rel test_loaded], 0
    call player_respawn
    FCHK [rel GP+PLAYER.y], OP_EQ, 40.0, "remembered height for now"
    RUN 0.5
    FCHK [rel GP+PLAYER.y], OP_EQ, 40.0, "frozen while unloaded"
    mov  dword [rel test_loaded], 1
    RUN 0.05
    FCHK [rel GP+PLAYER.y], OP_EQ, 21.0, "real ground found"
    ICHK [rel GP+PLAYER.health], OP_EQ, 20, "no damage"
    RUN 0.5
    FCHK [rel GP+PLAYER.y], OP_EQ, 21.0, "not re-spawned again"
    mov  dword [rel test_loaded], 1
ENDP

PROC sv_reset_clears_pending_spawn, 0
    TEST "survival: reset clears pending spawn"
    FRESH
    PFLOOR 10
    mov  dword [rel test_loaded], 0
    call player_spawn                       ; leaves a pending re-scan
    mov  dword [rel test_loaded], 1
    FRESH GM_SURVIVAL, 5.5, 10.0, 5.5       ; player_reset, like a new world
    PFLOOR 10
    RUN 0.2
    FCHK [rel GP+PLAYER.x], OP_EQ, 5.5, "x kept"
    FCHK [rel GP+PLAYER.y], OP_EQ, 10.0, "y kept"
    FCHK [rel GP+PLAYER.z], OP_EQ, 5.5, "z kept"
ENDP

PROC sv_zero_dt_keeps_ground, 0
    TEST "survival: zero dt frame keeps ground"
    FRESH
    PFLOOR 10
    RUN 0.2
    ICHK [rel GP+PLAYER.on_ground], OP_EQ, 1, "on ground"
    xorps xmm0, xmm0
    call player_update
    ICHK [rel GP+PLAYER.on_ground], OP_EQ, 1, "still on ground after dt = 0"
ENDP

PROC sv_drop_held_keeps_items, 0
    TEST "survival: drop held keeps items when spawn fails"
    ; entity_spawn_item is auto-stubbed to 0 here, same as a full entity pool
    FRESH
    PFLOOR 10
    mov  INV_ID(0), T_STONE
    mov  INV_CNT(0), 5
    mov  dword [rel GP+PLAYER.selected], 0
    mov  ecx, 1
    call player_drop_held
    movzx eax, INV_ID(0)
    ICHK eax, OP_EQ, T_STONE, "stack kept (whole stack)"
    movzx eax, INV_CNT(0)
    ICHK eax, OP_EQ, 5, "count kept (whole stack)"
    xor  ecx, ecx
    call player_drop_held
    movzx eax, INV_CNT(0)
    ICHK eax, OP_EQ, 5, "count kept (single item)"
ENDP

PROC sv_food_opens_crafting_table, 16
    TEST "survival: food in hand still opens crafting table"
    FRESH GM_SURVIVAL, 0.5, 10.0, 0.5, 0.0, -90.0
    PFLOOR 10, B_CRAFT_TABLE
    movzx eax, word [rel blk_flags+B_CRAFT_TABLE*2]
    mov  LOC(0), eax
    mov  word [rel blk_flags+B_CRAFT_TABLE*2], BF_SOLID | BF_OPAQUE | BF_SELECTABLE | BF_INTERACT
    mov  dword [rel GP+PLAYER.hunger], 10
    mov  INV_ID(0), B_BREAD
    mov  INV_CNT(0), 2
    mov  byte [rel item_food+B_BREAD], 5
    RUN 0.05
    ICHK [rel g_hit+RAYHIT.block], OP_EQ, B_CRAFT_TABLE, "looking at the table"
    RUNX 2.0, {}, {}, MB_RIGHT, MB_RIGHT, 0.0
    ICHK [rel GP+PLAYER.hunger], OP_EQ, 10, "opened the table, didn't eat"
    movzx eax, INV_CNT(0)
    ICHK eax, OP_EQ, 2, "bread kept"
    RUNX 2.0, {VK_SHIFT}, {}, MB_RIGHT, MB_RIGHT, 0.0
    ICHK [rel GP+PLAYER.hunger], OP_EQ, 15, "sneaking: eats as usual"
    mov  eax, LOC(0)
    mov  [rel blk_flags+B_CRAFT_TABLE*2], ax
ENDP

PROC sv_reset_creative_hotbar, 0
    TEST "survival: reset creative hotbar"
    mov  dword [rel g_gamemode], GM_CREATIVE
    call player_reset
    lea  rbx, [rel creative_hotbar]
    lea  rsi, [rel GP+PLAYER.inv]
    xor  edi, edi
.slot:
    movzx eax, byte [rsi+rdi*4]
    movzx edx, byte [rbx+rdi]
    ICHK eax, OP_EQ, edx, "starter hotbar id"
    inc  edi
    cmp  edi, 9
    jb   .slot
    movzx eax, INV_CNT(8)
    ICHK eax, OP_EQ, 1, "slot 8 holds a single item"
    ICHK [rel GP+PLAYER.health], OP_EQ, 20, "health"
    ICHK [rel GP+PLAYER.hunger], OP_EQ, 20, "hunger"
    ICHK [rel GP+PLAYER.air], OP_EQ, 300, "air"
    mov  dword [rel g_gamemode], GM_SURVIVAL
    call player_reset
    movzx eax, INV_ID(0)
    ICHK eax, OP_EQ, 0, "survival starts empty"
ENDP

; xmm1 start x -> xmm0 how far east we flew in 2 s
PROC fly_distance, 16
    mov  ecx, GM_CREATIVE
    FCONST xmm2, 40.0
    FCONST xmm3, 0.5
    mov  dword [rsp+32], __?float32?__(90.0)
    mov  dword [rsp+40], __?float32?__(0.0)
    call pl_fresh
    mov  dword [rel GP+PLAYER.flying], 1
    RUN 0.5
    mov  eax, [rel GP+PLAYER.x]
    mov  LOC(0), eax
    RUN 2.0, {'W'}
    movss xmm0, [rel GP+PLAYER.x]
    subss xmm0, LOC(0)
ENDP

PROC wl_far_movement_precise, 16
    TEST "limits: far movement is precise"
    ; at x = 900000 a float step is 1/16 block, so a 0.07 walk step or 0.02
    ; sneak step would just round away without the extra precision
    FCONST xmm1, 0.5
    call fly_distance
    movss LOC(0), xmm0
    FCONST xmm1, 900000.5
    call fly_distance
    movss LOC(4), xmm0
    FCHK LOC(0), OP_GT, 15.0, "flew more than 15 blocks near the origin"
    movss xmm1, LOC(0)
    CHECK_NEAR_X LOC(4), xmm1, 0.07, "same distance at x = 900000"
ENDP

PROC wl_slow_motion_far, 16
    TEST "limits: slow motion far from origin"
    ; 0.008 blocks/frame, way under a float step out here. still has to add up
    FRESH GM_CREATIVE, 900000.5, 40.0, 0.5, 90.0, 0.0
    mov  dword [rel GP+PLAYER.flying], 1
    RUN 0.2
    mov  eax, [rel GP+PLAYER.x]
    mov  LOC(0), eax
    mov  ebx, 120
.f:
    SETF [rel GP+PLAYER.vx], 0.5
    RUN 0.016666666666666666
    dec  ebx
    jnz  .f
    movss xmm0, [rel GP+PLAYER.x]
    subss xmm0, LOC(0)
    CHECK_NEAR xmm0, 0.83, 0.3, "0.5 * 2.0 * 0.83 blocks"
ENDP

PROC wl_teleport_beyond_border, 0
    TEST "limits: teleport beyond border"
    FRESH GM_CREATIVE, 0.5, 40.0, 0.5
    mov  dword [rel GP+PLAYER.flying], 1
    RUN 0.1
    SETF [rel GP+PLAYER.x], 2e9             ; /tp far outside
    SETF [rel GP+PLAYER.z], -3e6
    RUN 0.1
    FCHK [rel GP+PLAYER.x], OP_EQ, 999999.7, "x = float(1e6 - 0.3)"
    FCHK [rel GP+PLAYER.z], OP_EQ, -999999.7, "z = -float(1e6 - 0.3)"
    SETF [rel GP+PLAYER.x], 123.25          ; and back, nothing stale left over
    RUN 0.05
    CHECK_NEAR [rel GP+PLAYER.x], 123.25, 0.01, "teleported back"
ENDP

PROC wl_fall_into_void, 0
    TEST "limits: fall into void"
    FRESH GM_SURVIVAL, 0.5, 2.0, 0.5
    FILL -1, 0, -1, 1, 0, 1, T_AIR
    RUN 3.0
    FCHK [rel GP+PLAYER.y], OP_LT, -10.0, "fell into the void"
    ICHK [rel GP+PLAYER.health], OP_EQ, 0, "the void kills"
ENDP
