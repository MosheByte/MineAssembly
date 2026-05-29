; test_player_interact.asm - targeting, breaking, placing, pick block, eating.
;
; @link src/physics.asm src/raycast.asm src/player.asm src/math.asm
; @link tests/player/fakeworld.asm tests/player/ptest.asm tests/player/player_harness.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../player/ptest.inc"

%define GP g_player
%define B_BREAD 138                 ; any item id, the test makes it food

section .text

PROC test_main, 0
    call it_target_is_set
    call it_creative_instant_break
    call it_bedrock_unbreakable
    call it_survival_mining_time
    call it_survival_no_harvest_penalty
    call it_place_block
    call it_no_place_inside_player
    call it_place_replaces_tall_grass
    call it_middle_click_pick
    call it_eating
ENDP

PROC it_target_is_set, 0
    TEST "interact: target is set"
    FRESH GM_SURVIVAL, 0.5, 10.0, 0.5, 0.0, -90.0
    PFLOOR 10
    RUN 0.05
    ICHK [rel g_hit+RAYHIT.hit], OP_EQ, 1, "hit"
    ICHK [rel g_hit+RAYHIT.x], OP_EQ, 0, "x"
    ICHK [rel g_hit+RAYHIT.y], OP_EQ, 9, "y"
    ICHK [rel g_hit+RAYHIT.z], OP_EQ, 0, "z"
    ICHK [rel g_hit+RAYHIT.face], OP_EQ, FACE_PY, "top face"
ENDP

PROC it_creative_instant_break, 0
    TEST "interact: creative instant break and repeat"
    FRESH GM_CREATIVE
    PFLOOR 10
    FILL -2, 10, -3, 2, 12, -3, T_STONE
    RUN 0.05
    ICHK [rel g_hit+RAYHIT.hit], OP_EQ, 1, "hit"
    ICHK [rel g_hit+RAYHIT.x], OP_EQ, 0, "x"
    ICHK [rel g_hit+RAYHIT.y], OP_EQ, 11, "y"
    ICHK [rel g_hit+RAYHIT.z], OP_EQ, -3, "z"
    RUNX 0.05, {}, {}, MB_LEFT, MB_LEFT, 0.0
    GETB 0, 11, -3
    ICHK eax, OP_EQ, T_AIR, "broken instantly"
    GETB 0, 11, -4
    ICHK eax, OP_EQ, T_AIR, "nothing more to break behind"
    ; holding repeats about every 0.2 s
    FILL 0, 11, -6, 0, 11, -4, T_STONE
    RUNX 0.5, {}, {}, MB_LEFT, 0, 0.0
    xor  ebx, ebx
    mov  esi, -4
.cnt:
    GETB 0, 11, esi
    test eax, eax
    jnz  .solid
    inc  ebx
.solid:
    dec  esi
    cmp  esi, -6
    jge  .cnt
    ICHK ebx, OP_GE, 2, "broken >= 2 while holding 0.5 s"
    ICHK ebx, OP_LE, 3, "broken <= 3 while holding 0.5 s"
ENDP

PROC it_bedrock_unbreakable, 0
    TEST "interact: bedrock unbreakable"
    FRESH GM_CREATIVE, 0.5, 10.0, 0.5, 0.0, -90.0
    PFLOOR 10, B_BEDROCK
    SETF [rel blk_hardness+B_BEDROCK*4], -1.0
    RUNX 0.5, {}, {}, MB_LEFT, MB_LEFT, 0.0
    GETB 0, 9, 0
    ICHK eax, OP_EQ, B_BEDROCK, "bedrock stays"
ENDP

PROC it_survival_mining_time, 0
    TEST "interact: survival mining time"
    FRESH
    PFLOOR 10
    FILL -2, 10, -3, 2, 12, -3, T_DIRT
    SETF [rel blk_hardness+T_DIRT*4], 0.75
    RUNX 0.6, {}, {}, MB_LEFT, MB_LEFT, 0.0
    GETB 0, 11, -3
    ICHK eax, OP_EQ, T_DIRT, "not broken after 0.6 s"
    FCHK [rel GP+PLAYER.break_progress], OP_GT, 0.7, "progress > 0.7"
    RUNX 0.25, {}, {}, MB_LEFT, 0, 0.0
    GETB 0, 11, -3
    ICHK eax, OP_EQ, T_AIR, "broken after 0.85 s"
    FCHK [rel GP+PLAYER.exhaustion], OP_GT, 0.0, "mining exhausts"
    RUNX 0.3, {}, {}, MB_LEFT, 0, 0.0
    RUN 0.05
    FCHK [rel GP+PLAYER.break_progress], OP_EQ, 0.0, "progress reset on release"
ENDP

PROC it_survival_no_harvest_penalty, 0
    TEST "interact: survival no-harvest penalty"
    FRESH
    PFLOOR 10
    FILL -2, 10, -3, 2, 12, -3, T_STONE
    SETF [rel blk_hardness+T_STONE*4], 0.5
    mov  byte [rel blk_tier+T_STONE], 0     ; wants a pickaxe, bare hands = x3.33
    RUNX 1.2, {}, {}, MB_LEFT, MB_LEFT, 0.0
    GETB 0, 11, -3
    ICHK eax, OP_EQ, T_STONE, "not broken after 1.2 s"
    RUNX 0.6, {}, {}, MB_LEFT, 0, 0.0
    GETB 0, 11, -3
    ICHK eax, OP_EQ, T_AIR, "broken after 1.8 s"
ENDP

PROC it_place_block, 0
    TEST "interact: place block"
    FRESH
    PFLOOR 10
    FILL -2, 10, -3, 2, 12, -3, T_STONE
    mov  INV_ID(0), T_DIRT
    mov  INV_CNT(0), 3
    RUN 0.05
    RUNX 0.05, {}, {}, MB_RIGHT, MB_RIGHT, 0.0
    GETB 0, 11, -2
    ICHK eax, OP_EQ, T_DIRT, "placed against the +Z face"
    movzx eax, INV_CNT(0)
    ICHK eax, OP_EQ, 2, "one dirt used"
ENDP

PROC it_no_place_inside_player, 0
    TEST "interact: no place inside player"
    FRESH GM_SURVIVAL, 0.5, 10.0, 0.5, 0.0, -90.0
    PFLOOR 10
    mov  INV_ID(0), T_DIRT
    mov  INV_CNT(0), 3
    RUNX 0.05, {}, {}, MB_RIGHT, MB_RIGHT, 0.0
    GETB 0, 10, 0
    ICHK eax, OP_EQ, T_AIR, "solid block refused inside the player"
    movzx eax, INV_CNT(0)
    ICHK eax, OP_EQ, 3, "nothing used"
    ; torch isn't solid so it's fine there
    or   word [rel blk_flags+T_TORCH*2], BF_SUPPORT
    mov  INV_ID(0), T_TORCH
    RUNX 0.3, {}, {}, MB_RIGHT, MB_RIGHT, 0.0
    GETB 0, 10, 0
    ICHK eax, OP_EQ, T_TORCH, "torch placed at the feet"
ENDP

PROC it_place_replaces_tall_grass, 0
    TEST "interact: place replaces tall grass"
    FRESH GM_SURVIVAL, 0.5, 10.0, 0.5, 0.0, -45.0
    PFLOOR 10, T_GRASS
    SETB 0, 10, -1, T_TALL_GRASS
    RUN 0.05
    ICHK [rel g_hit+RAYHIT.x], OP_EQ, 0, "x"
    ICHK [rel g_hit+RAYHIT.y], OP_EQ, 10, "y"
    ICHK [rel g_hit+RAYHIT.z], OP_EQ, -1, "z"
    ICHK [rel g_hit+RAYHIT.block], OP_EQ, T_TALL_GRASS, "targets the tall grass"
    mov  INV_ID(0), T_SAND
    mov  INV_CNT(0), 5
    RUNX 0.05, {}, {}, MB_RIGHT, MB_RIGHT, 0.0
    GETB 0, 10, -1
    ICHK eax, OP_EQ, T_SAND, "sand replaced the grass"
ENDP

PROC it_middle_click_pick, 0
    TEST "interact: middle click pick"
    FRESH GM_CREATIVE, 0.5, 10.0, 0.5, 0.0, -90.0
    PFLOOR 10, T_GRASS
    xor  eax, eax
    lea  rcx, [rel GP+PLAYER.inv]
.clr:
    mov  word [rcx+rax*4], 0                ; id + count
    inc  eax
    cmp  eax, 9
    jb   .clr
    mov  INV_ID(0), T_STONE
    mov  INV_CNT(0), 1
    mov  dword [rel GP+PLAYER.selected], 0
    RUNX 0.05, {}, {}, 0, MB_MIDDLE, 0.0
    ICHK [rel GP+PLAYER.selected], OP_EQ, 1, "first free slot selected"
    movzx eax, INV_ID(1)
    ICHK eax, OP_EQ, T_GRASS, "picked grass"
    movzx eax, INV_CNT(1)
    ICHK eax, OP_EQ, 64, "full stack"
    mov  dword [rel GP+PLAYER.selected], 4
    RUNX 0.05, {}, {}, 0, MB_MIDDLE, 0.0
    ICHK [rel GP+PLAYER.selected], OP_EQ, 1, "already in the hotbar: select it"
ENDP

PROC it_eating, 0
    TEST "interact: eating"
    FRESH
    PFLOOR 10
    mov  dword [rel GP+PLAYER.hunger], 10
    mov  INV_ID(0), B_BREAD
    mov  INV_CNT(0), 2
    mov  byte [rel item_food+B_BREAD], 5
    RUNX 1.5, {}, {}, MB_RIGHT, 0, 0.0
    ICHK [rel GP+PLAYER.hunger], OP_EQ, 10, "still eating after 1.5 s"
    RUNX 0.2, {}, {}, MB_RIGHT, 0, 0.0
    ICHK [rel GP+PLAYER.hunger], OP_EQ, 15, "ate: +5"
    movzx eax, INV_CNT(0)
    ICHK eax, OP_EQ, 1, "one bread used"
    CHECK_NEAR [rel GP+PLAYER.saturation], 11.0, 0.0005, "saturation min(15, 5 + 5*0.6*2)"
ENDP
