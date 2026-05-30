; test_player_move.asm - walking, jumping, sneak, falls, flight, swimming, mouse look.
;
; @link src/physics.asm src/raycast.asm src/player.asm src/math.asm
; @link tests/player/fakeworld.asm tests/player/ptest.asm tests/player/player_harness.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../player/ptest.inc"

%define GP g_player

section .bss
alignb 16
vec3:   resd 4

section .text

PROC test_main, 0
    call mv_walk_speed_and_direction
    call mv_strafe_and_diagonal
    call mv_yaw_90_walks_east
    call mv_sprint
    call mv_jump_height
    call mv_jump_height_frame_rate
    call mv_jump_buffer
    call mv_jump_up_one_block
    call mv_wall_stops
    call mv_sneak_never_falls
    call mv_fall_damage
    call mv_short_fall_no_damage
    call mv_water_breaks_fall
    call mv_creative_flight
    call mv_survival_cannot_fly
    call mv_swimming
    call mv_climb_out_of_water
    call mv_view_bob
    call mv_not_playing
    call lk_mouse_look
ENDP

PROC mv_walk_speed_and_direction, 16
    TEST "move: walk speed and direction"
    FRESH
    PFLOOR 10
    RUN 0.1
    mov  eax, [rel GP+PLAYER.z]
    mov  LOC(0), eax
    RUN 2.0, {'W'}
    CHECK_NEAR [rel GP+PLAYER.vz], -4.3, 0.005, "walk speed (yaw 0 looks toward -Z)"
    CHECK_NEAR [rel GP+PLAYER.vx], 0.0, 0.0005, "no sideways speed"
    movss xmm0, LOC(0)
    subss xmm0, [rel GP+PLAYER.z]
    FCHK xmm0, OP_GT, 8.0, "walked more than 8 blocks"
    FCHK [rel GP+PLAYER.y], OP_EQ, 10.0, "on the floor"
    ICHK [rel GP+PLAYER.on_ground], OP_EQ, 1, "on_ground"
    RUN 0.3
    movss xmm0, [rel GP+PLAYER.vz]
    andps xmm0, [rel f_abs]
    FCHK xmm0, OP_LT, 0.05, "stopped by friction"
ENDP

PROC mv_strafe_and_diagonal, 0
    TEST "move: strafe east, diagonal not faster"
    FRESH
    PFLOOR 10
    RUN 1.0, {'D'}
    CHECK_NEAR [rel GP+PLAYER.vx], 4.3, 0.005, "right of north is east"
    RUN 1.0, {'W', 'D'}
    movss xmm0, [rel GP+PLAYER.vx]
    mulss xmm0, xmm0
    movss xmm1, [rel GP+PLAYER.vz]
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    CHECK_NEAR xmm0, 4.3, 0.005, "diagonal speed"
ENDP

PROC mv_yaw_90_walks_east, 0
    TEST "move: yaw 90 walks east"
    FRESH GM_SURVIVAL, 0.5, 10.0, 0.5, 90.0, 0.0
    PFLOOR 10
    RUN 1.0, {'W'}
    CHECK_NEAR [rel GP+PLAYER.vx], 4.3, 0.005, "vx"
ENDP

PROC mv_sprint, 0
    TEST "move: sprint"
    FRESH
    PFLOOR 10
    RUN 1.0, {'W', VK_CONTROL}
    ICHK [rel GP+PLAYER.sprinting], OP_EQ, 1, "ctrl sprints"
    movss xmm0, [rel GP+PLAYER.vz]
    xorps xmm0, [rel f_sign]
    CHECK_NEAR xmm0, 5.6, 0.005, "sprint speed"
    FRESH
    PFLOOR 10
    PRESS 0.05, {'W'}
    RUN 0.1
    RUNX 0.5, {'W'}, {'W'}, 0, 0, 0.0
    ICHK [rel GP+PLAYER.sprinting], OP_EQ, 1, "double-tap W sprints"
    mov  dword [rel GP+PLAYER.hunger], 6
    RUN 0.2, {'W', VK_CONTROL}
    ICHK [rel GP+PLAYER.sprinting], OP_EQ, 0, "hungry: no sprint"
ENDP

PROC mv_jump_height, 0
    TEST "move: jump height"
    FRESH
    PFLOOR 10
    PEAK_RESET 10.0
    PRESS 1.0, {VK_SPACE}
    movss xmm0, [rel pl_peak]
    FCONST xmm1, 10.0
    subss xmm0, xmm1
    CHECK_NEAR xmm0, 1.265625, 0.03, "peak = 81/64"
    FCHK [rel GP+PLAYER.y], OP_EQ, 10.0, "landed again"
    ICHK [rel GP+PLAYER.on_ground], OP_EQ, 1, "on_ground"
ENDP

; JUMPDT dt, tol. jump peak shouldn't depend on frame rate
%macro JUMPDT 2.nolist
    FRESH
    PFLOOR 10
    PEAK_RESET 10.0
    RUNX 1.0, {}, {VK_SPACE}, 0, 0, %1
    movss xmm0, [rel pl_peak]
    FCONST xmm1, 10.0
    subss xmm0, xmm1
    CHECK_NEAR xmm0, 1.265625, %2, "peak = 81/64 at this dt"
    FCHK [rel GP+PLAYER.y], OP_EQ, 10.0, "landed again"
%endmacro

PROC mv_jump_height_frame_rate, 0
    TEST "move: jump height at 144 fps"
    JUMPDT 0.006944444444444444, 0.02
    TEST "move: jump height at 30 fps"
    JUMPDT 0.03333333333333333, 0.03
    TEST "move: jump height at 10 fps"
    JUMPDT 0.1, 0.06
ENDP

PROC mv_jump_buffer, 0
    TEST "move: jump buffer"
    FRESH GM_SURVIVAL, 0.5, 10.5, 0.5
    PFLOOR 10
    SETF [rel GP+PLAYER.y], 10.6
    SETF [rel GP+PLAYER.vy], -2.0
    mov  dword [rel GP+PLAYER.on_ground], 0
    PRESS 0.05, {VK_SPACE}                  ; pressed while still airborne
    PEAK_RESET 0.0
    RUN 0.6
    FCHK [rel pl_peak], OP_GT, 11.0, "jumped on landing"
ENDP

PROC mv_jump_up_one_block, 0
    TEST "move: jump up one block"
    FRESH
    PFLOOR 10
    FILL -20, 10, -20, 19, 10, -3, T_STONE  ; step up at z = -2
    RUN 2.0, {'W', VK_SPACE}
    RUN 1.0
    FCHK [rel GP+PLAYER.y], OP_EQ, 11.0, "on the upper level"
    FCHK [rel GP+PLAYER.z], OP_LT, -3.0, "past the step"
ENDP

PROC mv_wall_stops, 0
    TEST "move: wall stops"
    FRESH
    PFLOOR 10
    FILL -20, 10, -4, 19, 12, -4, T_STONE   ; wall occupying z in [-4,-3)
    RUN 2.0, {'W'}
    CHECK_NEAR [rel GP+PLAYER.z], -2.7, 0.0005, "against the wall"
    ICHK [rel GP+PLAYER.sprinting], OP_EQ, 0, "not sprinting"
ENDP

PROC mv_sneak_never_falls, 0
    TEST "move: sneak never falls"
    FRESH
    FILL -20, 9, -2, 19, 9, 19, T_STONE     ; floor ends at z = -2
    RUN 4.0, {'W', VK_SHIFT}
    FCHK [rel GP+PLAYER.y], OP_EQ, 10.0, "still on the floor"
    movss xmm0, [rel GP+PLAYER.z]
    FCONST xmm1, 0.3
    addss xmm0, xmm1
    FCHK xmm0, OP_GT, -2.0, "z+0.3 > -2"
    movss xmm0, [rel GP+PLAYER.z]
    FCONST xmm1, 0.3
    addss xmm0, xmm1
    FCHK xmm0, OP_LT, -1.95, "z+0.3 < -1.95 (right at the edge)"
    ICHK [rel GP+PLAYER.sneaking], OP_EQ, 1, "sneaking"
    FCHK [rel GP+PLAYER.eye_height], OP_LT, 1.34, "lowered eye"
    RUN 1.0, {'W'}                          ; let go of shift
    FCHK [rel GP+PLAYER.y], OP_LT, 9.0, "fell off"
ENDP

PROC mv_fall_damage, 0
    TEST "move: fall damage"
    FRESH GM_SURVIVAL, 0.5, 20.0, 0.5
    PFLOOR 10
    RUN 2.0
    FCHK [rel GP+PLAYER.y], OP_EQ, 10.0, "landed"
    ICHK [rel GP+PLAYER.health], OP_EQ, 13, "10-block fall = 7 damage"
    ICHK [rel GP+PLAYER.last_damage_src], OP_EQ, DMG_FALL, "damage source"
ENDP

PROC mv_short_fall_no_damage, 0
    TEST "move: short fall no damage"
    FRESH GM_SURVIVAL, 0.5, 13.0, 0.5
    PFLOOR 10
    RUN 1.5
    ICHK [rel GP+PLAYER.health], OP_EQ, 20, "3-block fall is free"
ENDP

PROC mv_water_breaks_fall, 0
    TEST "move: water breaks fall"
    FRESH GM_SURVIVAL, 0.5, 30.0, 0.5
    PFLOOR 10
    FILL -3, 10, -3, 3, 11, 3, T_WATER
    RUN 4.0
    ICHK [rel GP+PLAYER.health], OP_EQ, 20, "no damage"
    ICHK [rel GP+PLAYER.in_water], OP_EQ, 1, "in water"
ENDP

PROC mv_creative_flight, 16
    TEST "move: creative no fall damage and flight"
    FRESH GM_CREATIVE, 0.5, 25.0, 0.5
    PFLOOR 10
    RUN 3.0
    ICHK [rel GP+PLAYER.health], OP_EQ, 20, "no fall damage"
    FCHK [rel GP+PLAYER.y], OP_EQ, 10.0, "landed"
    PRESS 0.05, {VK_SPACE}
    RUN 0.1
    PRESS 0.05, {VK_SPACE}
    ICHK [rel GP+PLAYER.flying], OP_EQ, 1, "double-tap space flies"
    RUN 1.0, {VK_SPACE}
    FCHK [rel GP+PLAYER.y], OP_GT, 15.0, "ascended"
    mov  eax, [rel GP+PLAYER.y]
    mov  LOC(0), eax
    RUN 1.0                                 ; no gravity while flying
    movss xmm1, LOC(0)
    CHECK_NEAR_X [rel GP+PLAYER.y], xmm1, 1.0, "hovering"
    RUN 1.0, {'W', VK_CONTROL}
    movss xmm0, [rel GP+PLAYER.vz]
    xorps xmm0, [rel f_sign]
    CHECK_NEAR xmm0, 22.0, 0.5, "sprint-flying speed"
    SETF [rel GP+PLAYER.z], 0.5             ; back over the floor
    SETF [rel GP+PLAYER.vz], 0.0
    RUN 5.0, {VK_SHIFT}
    ICHK [rel GP+PLAYER.flying], OP_EQ, 0, "landing stops flight"
    FCHK [rel GP+PLAYER.y], OP_EQ, 10.0, "on the floor"
ENDP

PROC mv_survival_cannot_fly, 0
    TEST "move: survival cannot fly"
    FRESH
    PFLOOR 10
    PRESS 0.05, {VK_SPACE}
    PRESS 0.05, {VK_SPACE}
    ICHK [rel GP+PLAYER.flying], OP_EQ, 0, "not flying"
ENDP

PROC mv_swimming, 16
    TEST "move: swimming"
    FRESH GM_SURVIVAL, 0.5, 15.0, 0.5
    PFLOOR 5
    FILL -5, 5, -5, 5, 18, 5, T_WATER
    RUN 1.5
    ICHK [rel GP+PLAYER.in_water], OP_EQ, 1, "in water"
    FCHK [rel GP+PLAYER.vy], OP_GT, -1.7, "sinks slowly (> -1.7)"
    FCHK [rel GP+PLAYER.vy], OP_LT, -1.0, "sinks (< -1.0)"
    movss xmm0, [rel GP+PLAYER.y]
    FCONST xmm1, 2.0
    addss xmm0, xmm1
    movss LOC(0), xmm0
    RUN 1.0, {VK_SPACE}
    FCHKX [rel GP+PLAYER.y], OP_GT, LOC(0), "swam up more than 2 blocks"
    ICHK [rel GP+PLAYER.eye_in_water], OP_EQ, 1, "head under water"
ENDP

PROC mv_climb_out_of_water, 0
    TEST "move: climb out of water"
    FRESH GM_SURVIVAL, 0.5, 10.0, 0.5
    PFLOOR 9
    FILL -20, 9, -20, 19, 9, -3, T_STONE    ; shore one block higher at z <= -3
    FILL -5, 9, -2, 5, 9, 5, T_WATER
    RUN 3.0, {'W', VK_SPACE}
    FCHK [rel GP+PLAYER.z], OP_LT, -3.5, "on the shore"
    FCHK [rel GP+PLAYER.y], OP_GE, 10.0, "climbed up"
ENDP

PROC mv_view_bob, 0
    TEST "move: view bob and steps"
    FRESH
    PFLOOR 10
    RUN 1.0, {'W'}
    FCHK [rel GP+PLAYER.bob_amount], OP_GT, 0.9, "bobbing while walking"
    FCHK [rel GP+PLAYER.bob], OP_GT, 0.0, "bob phase advances"
    RUN 1.0
    FCHK [rel GP+PLAYER.bob_amount], OP_LT, 0.1, "bob fades when standing"
ENDP

PROC mv_not_playing, 0
    TEST "move: not playing ignores input but falls"
    FRESH GM_SURVIVAL, 0.5, 15.0, 0.5
    PFLOOR 10
    mov  dword [rel g_state], ST_INVENTORY
    RUN 2.0, {'W'}
    FCHK [rel GP+PLAYER.y], OP_EQ, 10.0, "fell to the floor"
    CHECK_NEAR [rel GP+PLAYER.z], 0.5, 0.00005, "did not walk"
    mov  dword [rel g_state], ST_PLAYING
ENDP

PROC lk_mouse_look, 0
    TEST "look: mouse look"
    FRESH
    PFLOOR 10
    mov  dword [rel g_mouse_dx], 600
    mov  dword [rel g_mouse_dy], 0
    mov  rax, __?float64?__(0.016666666666666666)
    movq xmm0, rax
    call pl_update
    CHECK_NEAR [rel GP+PLAYER.yaw], 90.0, 0.0005, "600 counts * 0.15 = 90 degrees"
    mov  dword [rel g_mouse_dx], 0
    mov  dword [rel g_mouse_dy], 10000
    mov  rax, __?float64?__(0.016666666666666666)
    movq xmm0, rax
    call pl_update
    CHECK_NEAR [rel GP+PLAYER.pitch], -89.9, 0.0005, "pitch clamped"
    mov  dword [rel g_mouse_dx], 3000
    mov  dword [rel g_mouse_dy], 0
    mov  rax, __?float64?__(0.016666666666666666)
    movq xmm0, rax
    call pl_update
    FCHK [rel GP+PLAYER.yaw], OP_GE, 0.0, "yaw wrapped >= 0"
    FCHK [rel GP+PLAYER.yaw], OP_LT, 360.0, "yaw wrapped < 360"
    mov  dword [rel g_mouse_dx], 0
    mov  dword [rel g_mouse_dy], 0
    SETF [rel GP+PLAYER.yaw], 90.0
    SETF [rel GP+PLAYER.pitch], 0.0
    lea  rcx, [rel vec3]
    call player_get_look
    CHECK_NEAR [rel vec3], 1.0, 0.00005, "look x"
    CHECK_NEAR [rel vec3+8], 0.0, 0.00005, "look z"
    lea  rcx, [rel vec3]
    call player_get_eye
    movss xmm1, [rel GP+PLAYER.y]
    FCONST xmm2, 1.62
    addss xmm1, xmm2
    CHECK_NEAR_X [rel vec3+4], xmm1, 0.0005, "eye height 1.62"
ENDP

section .rdata
align 16
f_abs:  dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
f_sign: dd 0x80000000, 0x80000000, 0x80000000, 0x80000000
