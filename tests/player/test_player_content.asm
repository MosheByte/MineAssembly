; test_player_content.asm - turned blocks face the player, leaves go down as the
; placed kind, beds set the spawn (and skip the night), respawn uses that spot.
;
; @link src/physics.asm src/raycast.asm src/player.asm src/math.asm
; @link tests/player/fakeworld.asm tests/player/ptest.asm tests/player/player_harness.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../player/ptest.inc"

%define GP g_player
%define ROCKF (BF_SOLID | BF_OPAQUE | BF_SELECTABLE)

section .text

PROC test_main, 0
    call it_turned_faces_player
    call it_bed_pillow_away
    call it_leaves_placed_kind
    call it_bed_sets_spawn
    call it_respawn_on_bed
ENDP

; the fake tables only know a few ids
PROC content_blocks, 0
    mov  word [rel blk_flags+B_FURNACE*2], ROCKF | BF_INTERACT
    mov  word [rel blk_flags+B_PUMPKIN*2], ROCKF
    mov  word [rel blk_flags+B_LEAVES*2], BF_SOLID | BF_CUTOUT | BF_SELECTABLE | BF_LEAVES
    mov  word [rel blk_flags+B_BED*2], ROCKF | BF_INTERACT
    mov  byte [rel item_place+B_BED], B_BED
ENDP

; yaw, wall box x0 z0 x1 z1, where it lands x z, held id, expected id. level look
; at a wall
; two out, the block lands one out at y 11
%macro FACING 9.nolist
    FRESH GM_CREATIVE, 0.5, 10.0, 0.5, %1, 0.0
    PFLOOR 10
    call content_blocks
    FILL %2, 11, %3, %4, 11, %5, T_STONE
    mov  INV_ID(0), %8
    mov  INV_CNT(0), 1
    RUN 0.05
    RUNX 0.05, {}, {}, MB_RIGHT, MB_RIGHT, 0.0
    GETB %6, 11, %7
    ICHK eax, OP_EQ, %9, "placed id for this yaw"
%endmacro

PROC it_turned_faces_player, 0
    TEST "content: turned blocks face whoever placed them"
    FACING 0.0,    0, -3,  0, -3,  0, -2, B_FURNACE, B_FURNACE        ; looking north: front south
    FACING 90.0,   3,  0,  3,  0,  2,  0, B_FURNACE, B_FURNACE_W
    FACING 180.0,  0,  3,  0,  3,  0,  2, B_FURNACE, B_FURNACE_N
    FACING 270.0, -3,  0, -3,  0, -2,  0, B_FURNACE, B_FURNACE_E
    FACING -90.0, -3,  0, -3,  0, -2,  0, B_FURNACE, B_FURNACE_E      ; negative yaw wraps
    FACING 30.0,  -3, -3,  3, -3,  1, -2, B_PUMPKIN, B_PUMPKIN    ; rounds to the nearest
    FACING 150.0, -3,  3,  3,  3,  1,  2, B_PUMPKIN, B_PUMPKIN_N
ENDP

PROC it_bed_pillow_away, 0
    TEST "content: bed pillow points where you look"
    FACING 0.0,    0, -3,  0, -3,  0, -2, B_BED, B_BED+FACE_N
    FACING 90.0,   3,  0,  3,  0,  2,  0, B_BED, B_BED+FACE_E
    FACING 180.0,  0,  3,  0,  3,  0,  2, B_BED, B_BED+FACE_S
    FACING 270.0, -3,  0, -3,  0, -2,  0, B_BED, B_BED+FACE_W
ENDP

PROC it_leaves_placed_kind, 0
    TEST "content: leaves go down as the placed kind"
    FACING 0.0,    0, -3,  0, -3,  0, -2, B_LEAVES, B_LEAVES_P
ENDP

; bed one north of the feet, looking down at its top
%macro BED_SETUP 0.nolist
    FRESH GM_SURVIVAL, 0.5, 10.0, 0.5, 0.0, -45.0
    PFLOOR 10
    call content_blocks
    SETB 0, 10, -1, B_BED
    mov  INV_ID(0), 0
    mov  INV_CNT(0), 0
    RUN 0.05
%endmacro

PROC it_bed_sets_spawn, 0
    TEST "content: bed sets the spawn, sleeps through the night"
    BED_SETUP
    ICHK [rel g_hit+RAYHIT.y], OP_EQ, 10, "looking at the bed"
    ICHK [rel g_hit+RAYHIT.z], OP_EQ, -1, "looking at the bed z"
    mov  dword [rel g_time_of_day], 6000
    mov  qword [rel g_world_time], 30000
    RUNX 0.05, {}, {}, MB_RIGHT, MB_RIGHT, 0.0
    FCHK [rel GP+PLAYER.spawn_x], OP_EQ, 0.5, "spawn x on the bed"
    FCHK [rel GP+PLAYER.spawn_y], OP_EQ, 11.0, "spawn y on top of it"
    FCHK [rel GP+PLAYER.spawn_z], OP_EQ, -0.5, "spawn z on the bed"
    ICHK [rel g_time_of_day], OP_EQ, 6000, "daytime: no sleeping"
    GETB 0, 10, -1
    ICHK eax, OP_EQ, B_BED, "bed still there"

    BED_SETUP
    mov  dword [rel g_time_of_day], 18000
    mov  qword [rel g_world_time], 42000    ; day 1, 18000
    RUNX 0.05, {}, {}, MB_RIGHT, MB_RIGHT, 0.0
    ICHK [rel g_time_of_day], OP_EQ, 1000, "night: morning now"
    mov  rax, [rel g_world_time]
    ICHK eax, OP_EQ, 49000, "world clock counted the skipped night"

    BED_SETUP
    mov  dword [rel g_time_of_day], 12000   ; sunset, too early
    RUNX 0.05, {}, {}, MB_RIGHT, MB_RIGHT, 0.0
    ICHK [rel g_time_of_day], OP_EQ, 12000, "12000 isn't night yet"
    BED_SETUP
    mov  dword [rel g_time_of_day], 23501   ; already dawn
    RUNX 0.05, {}, {}, MB_RIGHT, MB_RIGHT, 0.0
    ICHK [rel g_time_of_day], OP_EQ, 23501, "23501 is morning already"
ENDP

PROC it_respawn_on_bed, 0
    TEST "content: respawn uses the bed spot, roof or not"
    BED_SETUP
    FILL -1, 15, -2, 1, 15, 0, T_STONE      ; roof over the bed
    SETF [rel GP+PLAYER.spawn_x], 0.5
    SETF [rel GP+PLAYER.spawn_y], 11.0
    SETF [rel GP+PLAYER.spawn_z], -0.5
    mov  dword [rel GP+PLAYER.dead], 1
    call player_respawn
    FCHK [rel GP+PLAYER.y], OP_EQ, 11.0, "on the bed, not the roof"
    FCHK [rel GP+PLAYER.x], OP_EQ, 0.5, "x"
    FCHK [rel GP+PLAYER.z], OP_EQ, -0.5, "z"
    ; bed gone: nothing to stand on there, back to the top of the column
    SETB 0, 10, -1, 0
    call player_respawn
    FCHK [rel GP+PLAYER.y], OP_EQ, 16.0, "no bed: top of the column"
ENDP
