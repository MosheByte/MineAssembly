; player.asm - first person controller + the survival side (hunger, air, fall dmg)
; player_update runs every frame, player_tick at 20 Hz.
; horizontal velocity chases the wish speed with implicit euler (see approach),
; one k per medium, so it's stable at any frame time
%define IMPL_PLAYER
%include "common.inc"

extern player_cell_box  ; physics.asm

; same as physics.asm, PROC without the global
%macro SPROC 1-2 0
    align 16
%1:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8
%endmacro
%macro SPROCX 1-2 0
    align 16
%1:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, 168
    movdqa [rsp+0],   xmm6
    movdqa [rsp+16],  xmm7
    movdqa [rsp+32],  xmm8
    movdqa [rsp+48],  xmm9
    movdqa [rsp+64],  xmm10
    movdqa [rsp+80],  xmm11
    movdqa [rsp+96],  xmm12
    movdqa [rsp+112], xmm13
    movdqa [rsp+128], xmm14
    movdqa [rsp+144], xmm15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT
%endmacro

; IFLOOR r32, xmm -> r32 = floor(xmm), clobbers xmm
%macro IFLOOR 2
    roundss %2, %2, 1
    cvttss2si %1, %2
%endmacro

%macro FLT 2
    section .rdata
    align 4
    %1: dd %2
    section .text
%endmacro

FLT f_zero,         0.0
FLT f_one,          1.0
FLT f_half,         0.5
FLT f_deg2rad,      0.017453292
FLT f_360,          360.0
FLT f_inv360,       0.0027777778
FLT f_pitch_max,    89.9
FLT f_pitch_min,    -89.9
FLT f_sens_default, 0.15
FLT f_sens_max,     10.0
FLT f_max_dt,       0.1
FLT f_substeps_hz,  20.0  ; max sub-step 0.05 s

FLT f_walk,         4.3
FLT f_sprint,       5.6
FLT f_sneak,        1.3
FLT f_fly,          11.0
FLT f_fly_sprint,   22.0
FLT f_fly_vert,     8.0
FLT f_gravity,      32.0
FLT f_terminal,     -78.0
FLT f_jump,         9.0  ; peak = 81/64 = 1.27 blocks with gravity 32
FLT f_jump_gate,    1.0  ; no re-jump while still going up faster than this
FLT f_sprint_boost, 1.5
FLT f_k_ground,     20.0  ; ~95% of full speed in 0.15 s
FLT f_k_ice,        2.5
FLT f_k_air,        2.5
FLT f_k_air_idle,   0.5  ; no input in the air: keep momentum on jumps
FLT f_k_fly,        6.0
FLT f_k_fly_v,      10.0
FLT f_k_water,      6.0
FLT f_k_lava,       3.0
FLT f_k_swim_v,     8.0
FLT f_k_sink,       3.0
FLT f_water_speed,  0.5
FLT f_lava_speed,   0.3
FLT f_swim_up,      3.2
FLT f_lava_up,      2.0
FLT f_water_sink,   -1.6
FLT f_lava_sink,    -1.0
FLT f_climb_out,    5.0
FLT f_current,      5.0  ; b/s^2
FLT f_step_up,      0.6
FLT f_hw,           0.3
FLT f_height,       1.8
FLT f_eye_stand,    1.62
FLT f_eye_sneak,    1.32
FLT f_eye_rate,     14.0
FLT f_jump_buffer,  0.15
FLT f_coyote,       0.1
FLT f_double_tap,   0.3
FLT f_splash_v,     -3.0
FLT f_inv12,        0.083333
FLT f_step_len,     1.8
FLT f_swim_len,     2.0
FLT f_bob_rate,     1.7453293  ; half a bob cycle per footstep
FLT f_bob_wrap,     12.566371  ; 4 pi
FLT f_bob_rate_amt, 8.0
FLT f_inv_walk,     0.23255814  ; 1 / 4.3
FLT f_fall_safe,    3.0
FLT f_fall_tol,     0.01
FLT f_fall_thud,    1.0
FLT f_fall_dust,    2.0
FLT f_teleport,     6.0
FLT f_ninth,        0.11111111
FLT f_feet_probe,   0.2
FLT f_reach_surv,   REACH_SURVIVAL
FLT f_reach_crea,   REACH_CREATIVE
FLT f_attack_cd,    0.4
FLT f_use_cd,       0.2
FLT f_break_cd,     0.25
FLT f_instant_cd,   0.15
FLT f_creative_cd,  0.2
FLT f_hit_fx,       0.25
FLT f_no_harvest,   3.33
FLT f_five,         5.0
FLT f_eat_time,     1.6
FLT f_eat_snd,      0.21
FLT f_crumb_ahead,  0.5  ; crumbs: 0.5 ahead of the eye, 0.25 lower (mouth)
FLT f_crumb_mouth,  0.25
FLT f_crumb_speed,  1.2
FLT f_crumb_spread, 0.9
FLT f_crumb_hop,    0.6
FLT f_crumb_size,   0.45
FLT f_swing_rate,   3.3333333  ; 1 / 0.3 s
FLT f_swing_start,  0.0001
FLT f_ex_sprint,    0.1  ; per block sprinted
FLT f_ex_swim,      0.01
FLT f_ex_jump,      0.05
FLT f_ex_sjump,     0.2
FLT f_ex_mine,      0.005
FLT f_ex_attack,    0.1
FLT f_ex_damage,    0.1
FLT f_ex_regen,     3.0
FLT f_ex_unit,      4.0
FLT f_sat_start,    5.0
FLT f_knock_up,     4.0
FLT f_throw,        0.3  ; blocks per TICK, not per sec
FLT f_throw_up,     0.1
FLT f_throw_rand,   0.02
FLT f_drop_eye,     0.3
FLT f_box_eps,      0.001
FLT f_spawn_fallback, 100.0
FLT f_void_y,       -10.0
FLT f_crit_v,       -1.0
FLT f_particle_spd, 1.5
FLT f_splash_spread, 0.4
FLT f_pitch_rand,   0.4
FLT f_pitch_base,   0.8

section .rdata
align 16
c_absmask:  dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
c_signmask: dd 0x80000000, 0x80000000, 0x80000000, 0x80000000
starter_hotbar:
    db B_GRASS, B_STONE, B_PLANKS, B_LOG, B_GLASS, B_TORCH, B_TNT, B_GLOWCRYSTAL, I_WATER_BUCKET
; dx, dz
nbr4:
    dd 1, 0,  -1, 0,  0, 1,  0, -1

section .bss
alignb 16
s_eye:          resd 4
s_look:         resd 4
s_phys:         resb PHYS_size
alignb 16
s_ray:          resb RAYHIT_size
alignb 8
s_target_ent:   resq 1  ; nearer than g_hit, or 0
s_held_ptr:     resq 1
s_pos_xd:       resq 1  ; double shadows of x/z, see substep
s_pos_zd:       resq 1
s_dt:           resd 1
s_h:            resd 1
s_input:        resd 1
s_fwd:          resd 1
s_strafe:       resd 1
s_tx:           resd 1
s_tz:           resd 1
s_fwdx:         resd 1
s_fwdz:         resd 1
s_jump_held:    resd 1
s_sneak_key:    resd 1
s_jump_buffer:  resd 1
s_coyote:       resd 1
s_attack_cd:    resd 1
s_break_cd:     resd 1
s_hit_fx:       resd 1
s_eat_snd:      resd 1
s_eat_slot:     resd 1
s_drown_timer:  resd 1
s_swim_dist:    resd 1
s_prev_in_water: resd 1
s_hit_h:        resd 1  ; blocked sideways last sub-step (climb out of water)
s_below:        resd 1
s_held_id:      resd 1
s_break_id:     resd 1
s_last_y:       resd 1
s_bx:           resd 1  ; scratch, feet_block leaves its cell here
s_by:           resd 1
s_bz:           resd 1
s_spawn_pending: resd 1  ; spawn column wasn't loaded, redo it later

section .text

; approach: v += (t - v) * kh/(1 + kh)
align 16
approach:
    mulss xmm2, [rel s_h]
    movss xmm3, [rel f_one]
    addss xmm3, xmm2
    divss xmm2, xmm3
    subss xmm1, xmm0
    mulss xmm1, xmm2
    addss xmm0, xmm1
    ret

align 16
dec_timer:
    movss xmm1, [rcx]
    subss xmm1, xmm0
    maxss xmm1, [rel f_zero]
    movss [rcx], xmm1
    ret

align 16
swing_start:
    lea  rax, [rel g_player]
    mov  ecx, [rax+PLAYER.swing]
    test ecx, ecx
    jnz  .busy
    mov  ecx, [rel f_swing_start]
    mov  [rax+PLAYER.swing], ecx
.busy:
    ret

align 16
is_creative:
    xor  eax, eax
    cmp  dword [rel g_gamemode], GM_CREATIVE
    sete al
    ret

; blk_tier 0xFF = no tool needed
align 16
can_harvest:
    and  ecx, 0xFF
    lea  rax, [rel blk_tier]
    movzx edx, byte [rax+rcx]
    cmp  edx, 0xFF
    je   .yes
    mov  r8d, [rel s_held_id]
    lea  rax, [rel item_tool_kind]
    cmp  byte [rax+r8], TOOL_PICK
    jne  .no
    lea  rax, [rel item_tool_tier]
    movzx r9d, byte [rax+r8]
    cmp  r9d, 0xFF
    je   .no
    cmp  r9d, edx
    jb   .no
.yes:
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

align 16
boxes_overlap:
    movss xmm2, [rel f_box_eps]
    xor  r8d, r8d
.ax:
    movss xmm0, [rcx+12+r8*4]
    subss xmm0, xmm2
    comiss xmm0, [rdx+r8*4]
    jbe  .no
    movss xmm0, [rcx+r8*4]
    addss xmm0, xmm2
    comiss xmm0, [rdx+12+r8*4]
    jae  .no
    inc  r8d
    cmp  r8d, 3
    jb   .ax
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

; float != shadow means something else moved us (tp, respawn, load),
; restart from the float
align 16
shadow_sync:
    cvtsd2ss xmm0, [rcx]
    movd eax, xmm0
    cmp  eax, [rdx]
    je   .same
    cvtss2sd xmm0, [rdx]
    movsd [rcx], xmm0
.same:
    ret

; r9d != 0: axis got clipped, take physics' float as is so we sit exactly on
; the contact. free axis: shadow += d
align 16
shadow_advance:
    test r9d, r9d
    jnz  .clipped
    cvtss2sd xmm0, xmm3
    addsd xmm0, [rcx]
    movsd [rcx], xmm0
    cvtsd2ss xmm0, xmm0
    movss [rdx], xmm0
    ret
.clipped:
    mov  [rdx], r8d
    movd xmm0, r8d
    cvtss2sd xmm0, xmm0
    movsd [rcx], xmm0
    ret

align 16
fill_phys:
    lea  rax, [rel g_player]
    lea  rcx, [rel s_phys]
    mov  edx, [rax+PLAYER.x]
    mov  [rcx+PHYS.x], edx
    mov  edx, [rax+PLAYER.y]
    mov  [rcx+PHYS.y], edx
    mov  edx, [rax+PLAYER.z]
    mov  [rcx+PHYS.z], edx
    xor  edx, edx
    mov  [rcx+PHYS.dx], edx
    mov  [rcx+PHYS.dy], edx
    mov  [rcx+PHYS.dz], edx
    mov  [rcx+PHYS.step], edx
    mov  [rcx+PHYS.flags], edx
    mov  edx, [rel f_hw]
    mov  [rcx+PHYS.hw], edx
    mov  edx, [rel f_height]
    mov  [rcx+PHYS.h], edx
    ret

; centre first, then the 4 corners, otherwise standing on an edge finds nothing
SPROCX feet_block, 32
    lea  rbx, [rel g_player]
    movss xmm0, [rbx+PLAYER.y]
    subss xmm0, [rel f_feet_probe]
    IFLOOR r13d, xmm0
    mov  [rel s_by], r13d
    xor  r12d, r12d
.probe:
    movss xmm6, [rbx+PLAYER.x]
    movss xmm7, [rbx+PLAYER.z]
    test r12d, r12d
    jz   .cell
    movss xmm0, [rel f_hw]
    test r12d, 1
    jz   .xneg
    addss xmm6, xmm0
    jmp  .zc
.xneg:
    subss xmm6, xmm0
.zc:
    test r12d, 2
    jz   .zneg
    addss xmm7, xmm0
    jmp  .cell
.zneg:
    subss xmm7, xmm0
.cell:
    IFLOOR r14d, xmm6
    IFLOOR r15d, xmm7
    mov  ecx, r14d
    mov  edx, r13d
    mov  r8d, r15d
    call world_get_block
    movzx eax, al
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_SOLID
    jnz  .found
    inc  r12d
    cmp  r12d, 5
    jb   .probe
    xor  eax, eax
.found:
    mov  [rel s_bx], r14d
    mov  [rel s_bz], r15d
ENDPX

SPROC play_footstep, 0
    call feet_block
    test eax, eax
    jz   .none
    mov  ecx, eax
    mov  edx, 2  ; step
    mov  r8d, [rel s_bx]
    mov  r9d, [rel s_by]
    mov  eax, [rel s_bz]
    mov  [rsp+32], eax
    call sfx_play_block
.none:
ENDP

SPROCX splash, 32
    lea  rbx, [rel g_player]
    movss xmm1, [rbx+PLAYER.vy]
    andps xmm1, [rel c_absmask]
    mulss xmm1, [rel f_inv12]
    minss xmm1, [rel f_one]
    movss xmm2, [rel f_one]
    mov  ecx, SFX_SPLASH
    call sfx_play
    mov  r12d, 14
.spray:
    call rng_float_signed
    mulss xmm0, [rel f_splash_spread]
    addss xmm0, [rbx+PLAYER.x]
    movaps xmm6, xmm0
    call rng_float_signed
    mulss xmm0, [rel f_splash_spread]
    addss xmm0, [rbx+PLAYER.z]
    movaps xmm7, xmm0
    call rng_float_signed
    mulss xmm0, [rel f_particle_spd]
    movss LOC(0), xmm0
    call rng_float_signed
    mulss xmm0, [rel f_particle_spd]
    movss LOC(4), xmm0
    call rng_float
    mulss xmm0, [rel f_five]
    addss xmm0, [rel f_one]
    movss LOC(8), xmm0
    mov  ecx, PT_SPLASH
    movaps xmm1, xmm6
    movss xmm2, [rbx+PLAYER.y]
    addss xmm2, [rel f_one]
    movaps xmm3, xmm7
    mov  eax, LOC(0)
    mov  [rsp+32], rax
    mov  eax, LOC(8)
    mov  [rsp+40], rax
    mov  eax, LOC(4)
    mov  [rsp+48], rax
    mov  qword [rsp+56], 0
    call particles_spawn
    dec  r12d
    jnz  .spray
ENDPX

; push = sum of (neighbour level - ours) over the 4 sides, open air counts as +1
SPROCX water_current, 32
    lea  rbx, [rel g_player]
    movss xmm0, [rbx+PLAYER.x]
    IFLOOR r12d, xmm0
    movss xmm0, [rbx+PLAYER.y]
    addss xmm0, [rel f_feet_probe]
    IFLOOR r13d, xmm0
    movss xmm0, [rbx+PLAYER.z]
    IFLOOR r14d, xmm0
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    call world_get_block
    movzx eax, al
    cmp  eax, B_WATER_FLOW
    jb   .done  ; sources don't push
    cmp  eax, B_WATER_LAST
    ja   .done
    sub  eax, B_WATER
    mov  r15d, eax
    xorps xmm6, xmm6
    xorps xmm7, xmm7
    xor  esi, esi
.nb:
    lea  rax, [rel nbr4]
    mov  edi, [rax+rsi*8]
    mov  eax, [rax+rsi*8+4]
    mov  LOC(0), eax
    lea  ecx, [r12d+edi]
    mov  edx, r13d
    lea  r8d, [r14d+eax]
    call world_get_block
    movzx eax, al
    cmp  eax, B_WATER
    jb   .not_water
    cmp  eax, B_WATER_LAST
    ja   .not_water
    sub  eax, B_WATER
    sub  eax, r15d
    jmp  .weight
.not_water:
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_SOLID
    jnz  .next
    mov  eax, 1
.weight:
    cvtsi2ss xmm0, eax
    cvtsi2ss xmm1, edi
    mulss xmm1, xmm0
    addss xmm6, xmm1
    cvtsi2ss xmm1, dword LOC(0)
    mulss xmm1, xmm0
    addss xmm7, xmm1
.next:
    inc  esi
    cmp  esi, 4
    jb   .nb
    movaps xmm0, xmm6
    mulss xmm0, xmm6
    movaps xmm1, xmm7
    mulss xmm1, xmm7
    addss xmm0, xmm1
    comiss xmm0, [rel f_box_eps]
    jbe  .done
    sqrtss xmm0, xmm0
    movss xmm1, [rel f_current]
    mulss xmm1, [rel s_h]
    divss xmm1, xmm0
    mulss xmm6, xmm1
    mulss xmm7, xmm1
    addss xmm6, [rbx+PLAYER.vx]
    movss [rbx+PLAYER.vx], xmm6
    addss xmm7, [rbx+PLAYER.vz]
    movss [rbx+PLAYER.vz], xmm7
.done:
ENDPX

SPROCX substep, 64
    lea  rbx, [rel g_player]

    call fill_phys
    lea  rcx, [rel s_phys]
    call physics_in_liquid
    xor  ecx, ecx
    cmp  eax, 1
    sete cl
    mov  [rbx+PLAYER.in_water], ecx
    xor  ecx, ecx
    cmp  eax, 2
    sete cl
    mov  [rbx+PLAYER.in_lava], ecx
    cmp  dword [rbx+PLAYER.in_water], 0
    je   .no_splash
    cmp  dword [rel s_prev_in_water], 0
    jne  .no_splash
    movss xmm0, [rbx+PLAYER.vy]
    comiss xmm0, [rel f_splash_v]
    jae  .no_splash
    call splash
.no_splash:
    mov  eax, [rbx+PLAYER.in_water]
    mov  [rel s_prev_in_water], eax

    cmp  dword [rbx+PLAYER.flying], 0
    jne  .fly
    mov  eax, [rbx+PLAYER.in_water]
    or   eax, [rbx+PLAYER.in_lava]
    jnz  .swim

    cmp  dword [rbx+PLAYER.on_ground], 0
    je   .air
    movss xmm8, [rel f_k_ground]
    cmp  dword [rel s_below], B_ICE
    jne  .accel
    movss xmm8, [rel f_k_ice]
    jmp  .accel
.air:
    movss xmm8, [rel f_k_air]
    mov  eax, [rel s_tx]
    or   eax, [rel s_tz]
    and  eax, 0x7FFFFFFF
    jnz  .accel
    movss xmm8, [rel f_k_air_idle]
.accel:
    movss xmm0, [rbx+PLAYER.vx]
    movss xmm1, [rel s_tx]
    movaps xmm2, xmm8
    call approach
    movss [rbx+PLAYER.vx], xmm0
    movss xmm0, [rbx+PLAYER.vz]
    movss xmm1, [rel s_tz]
    movaps xmm2, xmm8
    call approach
    movss [rbx+PLAYER.vz], xmm0
    ; jump: held, or buffered press right before landing (+ coyote)
    cmp  dword [rel s_jump_held], 0
    jne  .want_jump
    movss xmm0, [rel s_jump_buffer]
    comiss xmm0, [rel f_zero]
    jbe  .gravity
.want_jump:
    cmp  dword [rbx+PLAYER.on_ground], 0
    jne  .can_jump
    movss xmm0, [rel s_coyote]
    comiss xmm0, [rel f_zero]
    jbe  .gravity
.can_jump:
    movss xmm0, [rbx+PLAYER.vy]
    comiss xmm0, [rel f_jump_gate]
    ja   .gravity
    mov  eax, [rel f_jump]
    mov  [rbx+PLAYER.vy], eax
    xor  eax, eax
    mov  [rbx+PLAYER.on_ground], eax
    mov  [rel s_coyote], eax
    mov  [rel s_jump_buffer], eax
    movss xmm0, [rel f_ex_jump]
    cmp  dword [rbx+PLAYER.sprinting], 0
    je   .jump_ex
    movss xmm0, [rel f_ex_sjump]
    movss xmm1, [rel s_fwdx]  ; sprint-jump kick
    mulss xmm1, [rel f_sprint_boost]
    addss xmm1, [rbx+PLAYER.vx]
    movss [rbx+PLAYER.vx], xmm1
    movss xmm1, [rel s_fwdz]
    mulss xmm1, [rel f_sprint_boost]
    addss xmm1, [rbx+PLAYER.vz]
    movss [rbx+PLAYER.vz], xmm1
.jump_ex:
    addss xmm0, [rbx+PLAYER.exhaustion]
    movss [rbx+PLAYER.exhaustion], xmm0
.gravity:
    ; constant accel: move by the average of start/end v so jump height and fall
    ; timing don't depend on the frame rate
    movss xmm15, [rbx+PLAYER.vy]
    movaps xmm0, xmm15
    movss xmm1, [rel f_gravity]
    mulss xmm1, [rel s_h]
    subss xmm0, xmm1
    maxss xmm0, [rel f_terminal]
    movss [rbx+PLAYER.vy], xmm0
    addss xmm15, xmm0
    mulss xmm15, [rel f_half]
    jmp  .move_mid

.fly:
    movss xmm0, [rbx+PLAYER.vx]
    movss xmm1, [rel s_tx]
    movss xmm2, [rel f_k_fly]
    call approach
    movss [rbx+PLAYER.vx], xmm0
    movss xmm0, [rbx+PLAYER.vz]
    movss xmm1, [rel s_tz]
    movss xmm2, [rel f_k_fly]
    call approach
    movss [rbx+PLAYER.vz], xmm0
    xorps xmm1, xmm1
    cmp  dword [rel s_jump_held], 0
    je   .fly_nodown
    addss xmm1, [rel f_fly_vert]
.fly_nodown:
    cmp  dword [rel s_sneak_key], 0
    je   .fly_v
    subss xmm1, [rel f_fly_vert]
.fly_v:
    movss xmm0, [rbx+PLAYER.vy]
    movss xmm2, [rel f_k_fly_v]
    call approach
    movss [rbx+PLAYER.vy], xmm0
    jmp  .move

.swim:
    movss xmm8, [rel f_water_speed]
    movss xmm9, [rel f_k_water]
    movss xmm10, [rel f_swim_up]
    movss xmm11, [rel f_water_sink]
    cmp  dword [rbx+PLAYER.in_lava], 0
    je   .swim_h
    movss xmm8, [rel f_lava_speed]
    movss xmm9, [rel f_k_lava]
    movss xmm10, [rel f_lava_up]
    movss xmm11, [rel f_lava_sink]
.swim_h:
    movss xmm0, [rbx+PLAYER.vx]
    movss xmm1, [rel s_tx]
    mulss xmm1, xmm8
    movaps xmm2, xmm9
    call approach
    movss [rbx+PLAYER.vx], xmm0
    movss xmm0, [rbx+PLAYER.vz]
    movss xmm1, [rel s_tz]
    mulss xmm1, xmm8
    movaps xmm2, xmm9
    call approach
    movss [rbx+PLAYER.vz], xmm0
    movss xmm0, [rbx+PLAYER.vy]
    cmp  dword [rel s_jump_held], 0
    je   .sink
    movaps xmm1, xmm10
    movss xmm2, [rel f_k_swim_v]
    call approach
    cmp  dword [rel s_hit_h], 0  ; against a wall: climb out onto the shore
    je   .swim_v
    maxss xmm0, [rel f_climb_out]
    jmp  .swim_v
.sink:
    movaps xmm1, xmm11
    movss xmm2, [rel f_k_sink]
    call approach
.swim_v:
    movss [rbx+PLAYER.vy], xmm0
    cmp  dword [rbx+PLAYER.in_water], 0
    je   .move
    call water_current

.move:
    movss xmm15, [rbx+PLAYER.vy]
.move_mid:
    call fill_phys
    lea  rsi, [rel s_phys]
    movss xmm0, [rbx+PLAYER.vx]
    mulss xmm0, [rel s_h]
    movss [rsi+PHYS.dx], xmm0
    movss xmm0, xmm15
    mulss xmm0, [rel s_h]
    movss [rsi+PHYS.dy], xmm0
    movss xmm0, [rbx+PLAYER.vz]
    mulss xmm0, [rel s_h]
    movss [rsi+PHYS.dz], xmm0
    cmp  dword [rbx+PLAYER.flying], 0
    jne  .no_ground_opts
    cmp  dword [rbx+PLAYER.on_ground], 0
    je   .no_ground_opts
    mov  eax, [rel f_step_up]
    mov  [rsi+PHYS.step], eax
    cmp  dword [rbx+PLAYER.sneaking], 0
    je   .no_ground_opts
    mov  dword [rsi+PHYS.flags], PF_SNEAK
.no_ground_opts:
    ; x/z are integrated in a DOUBLE shadow. at 1e6 a float step is 1/16 block and a
    ; sneak sub-step is ~0.02, so in float you'd just stand there. physics still
    ; works on the floats
    lea  rcx, [rel s_pos_xd]
    lea  rdx, [rbx+PLAYER.x]
    call shadow_sync
    lea  rcx, [rel s_pos_zd]
    lea  rdx, [rbx+PLAYER.z]
    call shadow_sync
    movss xmm10, [rbx+PLAYER.x]
    movss xmm11, [rbx+PLAYER.y]
    movss xmm12, [rbx+PLAYER.z]
    mov  rcx, rsi
    call physics_move
    mov  r12d, [rsi+PHYS.flags]
    lea  rcx, [rel s_pos_xd]
    lea  rdx, [rbx+PLAYER.x]
    mov  r8d, [rsi+PHYS.x]
    movss xmm3, [rsi+PHYS.dx]
    mov  r9d, r12d
    and  r9d, PF_HIT_X
    call shadow_advance
    mov  eax, [rsi+PHYS.y]
    mov  [rbx+PLAYER.y], eax
    lea  rcx, [rel s_pos_zd]
    lea  rdx, [rbx+PLAYER.z]
    mov  r8d, [rsi+PHYS.z]
    movss xmm3, [rsi+PHYS.dz]
    mov  r9d, r12d
    and  r9d, PF_HIT_Z
    call shadow_advance

    xor  eax, eax
    test r12d, PF_HIT_X
    jz   .hx
    mov  [rbx+PLAYER.vx], eax
.hx:
    test r12d, PF_HIT_Z
    jz   .hz
    mov  [rbx+PLAYER.vz], eax
.hz:
    test r12d, PF_HIT_Y
    jz   .hy
    mov  [rbx+PLAYER.vy], eax
.hy:
    xor  ecx, ecx
    test r12d, PF_HIT_X | PF_HIT_Z
    setnz cl
    mov  [rel s_hit_h], ecx
    mov  r13d, [rbx+PLAYER.on_ground]  ; was on ground
    xor  ecx, ecx
    test r12d, PF_GROUND
    setnz cl
    mov  [rbx+PLAYER.on_ground], ecx

    movss xmm0, [rbx+PLAYER.x]
    subss xmm0, xmm10
    mulss xmm0, xmm0
    movss xmm1, [rbx+PLAYER.z]
    subss xmm1, xmm12
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm13, xmm0
    movss xmm14, [rbx+PLAYER.y]
    subss xmm14, xmm11
    andps xmm14, [rel c_absmask]

    cmp  dword [rel s_hit_h], 0
    je   .sprint_ok
    cmp  dword [rbx+PLAYER.flying], 0
    jne  .sprint_ok
    mov  dword [rbx+PLAYER.sprinting], 0
.sprint_ok:
    cmp  dword [rbx+PLAYER.flying], 0
    je   .fly_ok
    cmp  dword [rbx+PLAYER.on_ground], 0
    je   .fly_ok
    mov  dword [rbx+PLAYER.flying], 0
.fly_ok:
    ; walked off a ledge: coyote window
    test r13d, r13d
    jz   .coyote_ok
    cmp  dword [rbx+PLAYER.on_ground], 0
    jne  .coyote_ok
    movss xmm0, [rbx+PLAYER.vy]
    comiss xmm0, [rel f_zero]
    ja   .coyote_ok
    mov  eax, [rel f_coyote]
    mov  [rel s_coyote], eax
.coyote_ok:

    cmp  dword [rbx+PLAYER.on_ground], 0
    je   .airborne
    test r13d, r13d
    jnz  .grounded
    movss xmm15, [rbx+PLAYER.fall_start]
    subss xmm15, [rbx+PLAYER.y]
    mov  eax, [rbx+PLAYER.in_water]
    or   eax, [rbx+PLAYER.in_lava]
    jnz  .grounded  ; water breaks the fall
    comiss xmm15, [rel f_fall_safe]
    jbe  .no_fall_dmg
    call is_creative
    test eax, eax
    jnz  .no_fall_dmg
    ; ceil(dist - 3) with 0.01 slack, an exact 4 block drop comes out as 4.0000x
    ; and would do 2
    movaps xmm0, xmm15
    subss xmm0, [rel f_fall_safe]
    subss xmm0, [rel f_fall_tol]
    roundss xmm0, xmm0, 2
    cvttss2si ecx, xmm0
    mov  edx, DMG_FALL
    call player_damage
.no_fall_dmg:
    comiss xmm15, [rel f_fall_thud]
    jbe  .grounded
    call play_footstep
    comiss xmm15, [rel f_fall_dust]
    jbe  .grounded
    mov  ecx, [rel s_bx]
    mov  edx, [rel s_by]
    mov  r8d, [rel s_bz]
    mov  r9d, FACE_PY
    call particles_spawn_block_hit
.grounded:
    mov  eax, [rbx+PLAYER.y]
    mov  [rbx+PLAYER.fall_start], eax
    jmp  .fall_done
.airborne:
    mov  eax, [rbx+PLAYER.in_water]
    or   eax, [rbx+PLAYER.in_lava]
    or   eax, [rbx+PLAYER.flying]
    jnz  .grounded
    movss xmm0, [rbx+PLAYER.y]
    comiss xmm0, [rbx+PLAYER.fall_start]
    jbe  .fall_done
    movss [rbx+PLAYER.fall_start], xmm0
.fall_done:

    cmp  dword [rbx+PLAYER.on_ground], 0
    je   .no_walk
    cmp  dword [rbx+PLAYER.flying], 0
    jne  .no_walk
    cmp  dword [rbx+PLAYER.in_water], 0
    jne  .no_walk
    movss xmm0, [rbx+PLAYER.bob]
    movaps xmm1, xmm13
    mulss xmm1, [rel f_bob_rate]
    addss xmm0, xmm1
    comiss xmm0, [rel f_bob_wrap]
    jb   .bob_ok
    subss xmm0, [rel f_bob_wrap]
.bob_ok:
    movss [rbx+PLAYER.bob], xmm0
    cmp  dword [rbx+PLAYER.sprinting], 0
    je   .steps
    movaps xmm0, xmm13
    mulss xmm0, [rel f_ex_sprint]
    addss xmm0, [rbx+PLAYER.exhaustion]
    movss [rbx+PLAYER.exhaustion], xmm0
.steps:
    movss xmm0, [rbx+PLAYER.step_dist]
    addss xmm0, xmm13
    comiss xmm0, [rel f_step_len]
    jb   .step_store
    subss xmm0, [rel f_step_len]
    minss xmm0, [rel f_step_len]
    movss [rbx+PLAYER.step_dist], xmm0
    cmp  dword [rbx+PLAYER.sneaking], 0
    jne  .no_walk
    call play_footstep
    jmp  .no_walk
.step_store:
    movss [rbx+PLAYER.step_dist], xmm0
.no_walk:
    cmp  dword [rbx+PLAYER.in_water], 0
    je   .done
    movaps xmm0, xmm13
    mulss xmm0, [rel f_ex_swim]
    addss xmm0, [rbx+PLAYER.exhaustion]
    movss [rbx+PLAYER.exhaustion], xmm0
    movss xmm0, [rel s_swim_dist]
    addss xmm0, xmm13
    addss xmm0, xmm14
    movss [rel s_swim_dist], xmm0
    comiss xmm0, [rel f_swim_len]
    jb   .done
    xorps xmm0, xmm0
    movss [rel s_swim_dist], xmm0
    call rng_float
    mulss xmm0, [rel f_pitch_rand]
    addss xmm0, [rel f_pitch_base]
    movaps xmm2, xmm0
    movss xmm1, [rel f_pitch_rand]  ; quiet
    mov  ecx, SFX_SWIM
    call sfx_play
.done:
ENDPX

SPROCX simulate, 32
    lea  rbx, [rel g_player]
    ; dt == 0: a zero physics_move reports not-on-ground and fakes coyote / a landing
    movss xmm0, [rel s_dt]
    comiss xmm0, [rel f_zero]
    jbe  .done
    ; chunk not there yet -> freeze, else you fall through the missing ground
    movss xmm0, [rbx+PLAYER.x]
    IFLOOR ecx, xmm0
    movss xmm0, [rbx+PLAYER.z]
    IFLOOR edx, xmm0
    call world_is_loaded
    test eax, eax
    jnz  .loaded
    xor  eax, eax
    mov  [rbx+PLAYER.vx], eax
    mov  [rbx+PLAYER.vy], eax
    mov  [rbx+PLAYER.vz], eax
    jmp  .done
.loaded:
    ; respawned before the spawn column existed, find the real ground now
    cmp  dword [rel s_spawn_pending], 0
    je   .spawn_ok
    call player_spawn
.spawn_ok:
    ; teleport guard: big y jump physics didn't do resets the fall
    movss xmm0, [rbx+PLAYER.y]
    subss xmm0, [rel s_last_y]
    andps xmm0, [rel c_absmask]
    comiss xmm0, [rel f_teleport]
    jbe  .no_tp
    mov  eax, [rbx+PLAYER.y]
    mov  [rbx+PLAYER.fall_start], eax
.no_tp:
    call feet_block
    mov  [rel s_below], eax

    ; forward (sin, -cos), right (cos, sin)
    movss xmm0, [rbx+PLAYER.yaw]
    mulss xmm0, [rel f_deg2rad]
    call math_sincos
    movss [rel s_fwdx], xmm0
    movaps xmm2, xmm1
    xorps xmm2, [rel c_signmask]
    movss [rel s_fwdz], xmm2
    movss xmm2, [rel s_fwd]
    movss xmm3, [rel s_strafe]
    movaps xmm4, xmm2
    mulss xmm4, xmm0
    movaps xmm5, xmm3
    mulss xmm5, xmm1
    addss xmm4, xmm5
    movaps xmm5, xmm3
    mulss xmm5, xmm0
    mulss xmm2, xmm1
    subss xmm5, xmm2
    ; no faster diagonals
    movaps xmm0, xmm4
    mulss xmm0, xmm4
    movaps xmm1, xmm5
    mulss xmm1, xmm5
    addss xmm0, xmm1
    comiss xmm0, [rel f_one]
    jbe  .wish_ok
    sqrtss xmm0, xmm0
    divss xmm4, xmm0
    divss xmm5, xmm0
.wish_ok:
    movss xmm0, [rel f_walk]
    cmp  dword [rbx+PLAYER.flying], 0
    je   .ground_speed
    movss xmm0, [rel f_fly]
    cmp  dword [rbx+PLAYER.sprinting], 0
    je   .speed
    movss xmm0, [rel f_fly_sprint]
    jmp  .speed
.ground_speed:
    cmp  dword [rbx+PLAYER.sneaking], 0
    je   .not_sneak
    movss xmm0, [rel f_sneak]
    jmp  .speed
.not_sneak:
    cmp  dword [rbx+PLAYER.sprinting], 0
    je   .speed
    movss xmm0, [rel f_sprint]
.speed:
    mulss xmm4, xmm0
    mulss xmm5, xmm0
    movss [rel s_tx], xmm4
    movss [rel s_tz], xmm5

    ; <= 0.05 s each, max 8
    movss xmm6, [rel s_dt]
    movaps xmm0, xmm6
    mulss xmm0, [rel f_substeps_hz]
    roundss xmm0, xmm0, 2
    cvttss2si r12d, xmm0
    cmp  r12d, 1
    jge  .n_lo
    mov  r12d, 1
.n_lo:
    cmp  r12d, 8
    jle  .n_hi
    mov  r12d, 8
.n_hi:
    cvtsi2ss xmm0, r12d
    divss xmm6, xmm0
    movss [rel s_h], xmm6
.sub:
    call substep
    dec  r12d
    jnz  .sub
    mov  eax, [rbx+PLAYER.y]
    mov  [rel s_last_y], eax
.done:
ENDPX

SPROC look, 0
    lea  rbx, [rel g_player]
    movss xmm4, [rel g_settings + SETTINGS.sensitivity]
    comiss xmm4, [rel f_zero]
    jbe  .sens_default
    comiss xmm4, [rel f_sens_max]
    jb   .sens_ok
.sens_default:
    movss xmm4, [rel f_sens_default]
.sens_ok:
    cvtsi2ss xmm0, dword [rel g_mouse_dx]
    mulss xmm0, xmm4
    addss xmm0, [rbx+PLAYER.yaw]
    movaps xmm1, xmm0
    mulss xmm1, [rel f_inv360]
    roundss xmm1, xmm1, 1
    mulss xmm1, [rel f_360]
    subss xmm0, xmm1
    movss [rbx+PLAYER.yaw], xmm0
    cvtsi2ss xmm0, dword [rel g_mouse_dy]
    mulss xmm0, xmm4
    movss xmm1, [rbx+PLAYER.pitch]
    cmp  dword [rel g_settings + SETTINGS.invert_mouse], 0
    jne  .inverted
    subss xmm1, xmm0  ; mouse down = look down
    jmp  .clamp
.inverted:
    addss xmm1, xmm0
.clamp:
    maxss xmm1, [rel f_pitch_min]
    minss xmm1, [rel f_pitch_max]
    movss [rbx+PLAYER.pitch], xmm1
ENDP

SPROC read_input, 0
    lea  rbx, [rel g_player]
    xor  eax, eax
    mov  [rel s_fwd], eax
    mov  [rel s_strafe], eax
    mov  [rel s_jump_held], eax
    mov  [rel s_sneak_key], eax
    xor  r13d, r13d  ; sprint requested this frame
    cmp  dword [rel s_input], 0
    je   .states
    lea  rsi, [rel g_keys]
    lea  rdi, [rel g_keys_pressed]
    xorps xmm0, xmm0
    xorps xmm1, xmm1
    movss xmm2, [rel f_one]
    cmp  byte [rsi+'W'], 0
    je   .k_s
    addss xmm0, xmm2
.k_s:
    cmp  byte [rsi+'S'], 0
    je   .k_d
    subss xmm0, xmm2
.k_d:
    cmp  byte [rsi+'D'], 0
    je   .k_a
    addss xmm1, xmm2
.k_a:
    cmp  byte [rsi+'A'], 0
    je   .k_done
    subss xmm1, xmm2
.k_done:
    movss [rel s_fwd], xmm0
    movss [rel s_strafe], xmm1
    movzx eax, byte [rsi+VK_SPACE]
    mov  [rel s_jump_held], eax
    movzx eax, byte [rsi+VK_SHIFT]
    or   al, [rsi+VK_LSHIFT]
    or   al, [rsi+VK_LSHIFT+1]  ; right shift, ugly
    mov  [rel s_sneak_key], eax
    movzx eax, byte [rsi+VK_CONTROL]
    or   al, [rsi+VK_LCONTROL]
    mov  r13d, eax

    ; creative: double-tap space toggles flight
    cmp  byte [rdi+VK_SPACE], 0
    je   .no_space
    mov  eax, [rel f_jump_buffer]
    mov  [rel s_jump_buffer], eax
    call is_creative
    test eax, eax
    jz   .no_space
    movss xmm0, [rbx+PLAYER.jump_timer]
    comiss xmm0, [rel f_zero]
    jbe  .first_tap
    xor  dword [rbx+PLAYER.flying], 1
    xor  eax, eax
    mov  [rbx+PLAYER.jump_timer], eax
    mov  [rel s_jump_buffer], eax
    mov  [rbx+PLAYER.vy], eax
    jmp  .no_space
.first_tap:
    mov  eax, [rel f_double_tap]
    mov  [rbx+PLAYER.jump_timer], eax
.no_space:
    ; double tap W = sprint
    cmp  byte [rdi+'W'], 0
    je   .states
    movss xmm0, [rbx+PLAYER.sprint_timer]
    comiss xmm0, [rel f_zero]
    jbe  .first_w
    mov  r13d, 1
    mov  dword [rbx+PLAYER.sprint_timer], 0
    jmp  .states
.first_w:
    mov  eax, [rel f_double_tap]
    mov  [rbx+PLAYER.sprint_timer], eax

.states:
    ; shift means descend while flying
    xor  eax, eax
    cmp  dword [rbx+PLAYER.flying], 0
    jne  .sneak_set
    mov  eax, [rel s_sneak_key]
.sneak_set:
    mov  [rbx+PLAYER.sneaking], eax
    movss xmm0, [rel s_fwd]
    comiss xmm0, [rel f_zero]
    jbe  .no_sprint
    cmp  dword [rbx+PLAYER.sneaking], 0
    jne  .no_sprint
    mov  eax, [rbx+PLAYER.eat_time]
    and  eax, 0x7FFFFFFF
    jnz  .no_sprint
    call is_creative
    test eax, eax
    jnz  .food_ok
    cmp  dword [rbx+PLAYER.hunger], 6
    jle  .no_sprint
.food_ok:
    test r13d, r13d
    jz   .done
    mov  dword [rbx+PLAYER.sprinting], 1
    jmp  .done
.no_sprint:
    mov  dword [rbx+PLAYER.sprinting], 0
.done:
ENDP

SPROCX eye_and_bob, 32
    lea  rbx, [rel g_player]
    movss xmm1, [rel f_eye_stand]
    cmp  dword [rbx+PLAYER.sneaking], 0
    je   .eye_t
    movss xmm1, [rel f_eye_sneak]
.eye_t:
    movss xmm2, [rel s_dt]
    mulss xmm2, [rel f_eye_rate]
    minss xmm2, [rel f_one]
    movss xmm0, [rbx+PLAYER.eye_height]
    subss xmm1, xmm0
    mulss xmm1, xmm2
    addss xmm0, xmm1
    movss [rbx+PLAYER.eye_height], xmm0

    ; head in water? use the real surface height, not the cell
    addss xmm0, [rbx+PLAYER.y]
    movaps xmm6, xmm0
    movss xmm1, [rbx+PLAYER.x]
    IFLOOR r12d, xmm1
    movaps xmm1, xmm0
    IFLOOR r13d, xmm1
    movss xmm1, [rbx+PLAYER.z]
    IFLOOR r14d, xmm1
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    call world_get_block
    movzx esi, al
    xor  edi, edi
    cmp  esi, B_WATER
    jb   .eye_done
    cmp  esi, B_WATER_LAST
    ja   .eye_done
    mov  ecx, r12d
    lea  edx, [r13d+1]
    mov  r8d, r14d
    call world_get_block
    movzx eax, al
    mov  edi, 1
    cmp  eax, B_WATER
    jb   .surface
    cmp  eax, B_WATER_LAST
    jbe  .eye_done  ; water above: fully under
.surface:
    mov  eax, 8
    sub  esi, B_WATER
    sub  eax, esi
    cvtsi2ss xmm0, eax
    mulss xmm0, [rel f_ninth]
    cvtsi2ss xmm1, r13d
    subss xmm6, xmm1
    xor  edi, edi
    comiss xmm6, xmm0
    jae  .eye_done
    mov  edi, 1
.eye_done:
    mov  [rbx+PLAYER.eye_in_water], edi

    xorps xmm1, xmm1
    cmp  dword [rbx+PLAYER.on_ground], 0
    je   .bob_t
    cmp  dword [rbx+PLAYER.flying], 0
    jne  .bob_t
    movss xmm0, [rbx+PLAYER.vx]
    mulss xmm0, xmm0
    movss xmm2, [rbx+PLAYER.vz]
    mulss xmm2, xmm2
    addss xmm0, xmm2
    sqrtss xmm1, xmm0
    mulss xmm1, [rel f_inv_walk]
    minss xmm1, [rel f_one]
.bob_t:
    movss xmm2, [rel s_dt]
    mulss xmm2, [rel f_bob_rate_amt]
    minss xmm2, [rel f_one]
    movss xmm0, [rbx+PLAYER.bob_amount]
    subss xmm1, xmm0
    mulss xmm1, xmm2
    addss xmm0, xmm1
    movss [rbx+PLAYER.bob_amount], xmm0
ENDPX

SPROCX find_target, 32
    lea  rcx, [rel s_eye]
    call player_get_eye
    lea  rcx, [rel s_look]
    call player_get_look
    movss xmm6, [rel f_reach_surv]
    call is_creative
    test eax, eax
    jz   .reach
    movss xmm6, [rel f_reach_crea]
.reach:
    lea  r9, [rel g_hit]
    mov  dword [r9+RAYHIT.hit], 0
    lea  rcx, [rel s_eye]
    lea  rdx, [rel s_look]
    movaps xmm2, xmm6
    call raycast_blocks
    mov  qword [rel s_target_ent], 0
    lea  rcx, [rel s_eye]
    lea  rdx, [rel s_look]
    movaps xmm2, xmm6
    call entity_raycast
    test rax, rax
    jz   .done
    cmp  dword [rel g_hit + RAYHIT.hit], 0
    je   .take
    comiss xmm0, [rel g_hit + RAYHIT.dist]
    jae  .done
.take:
    mov  [rel s_target_ent], rax
.done:
ENDPX

; < 0 = unbreakable
SPROCX break_time, 32
    and  ecx, 0xFF
    mov  esi, ecx
    lea  rax, [rel blk_hardness]
    movss xmm6, [rax+rsi*4]
    comiss xmm6, [rel f_zero]
    jb   .done
    mov  edi, [rel s_held_id]
    lea  rax, [rel item_tool_kind]
    movzx ecx, byte [rax+rdi]
    test ecx, ecx
    jz   .no_tool
    lea  rax, [rel blk_tool]
    cmp  cl, [rax+rsi]
    jne  .no_tool
    lea  rax, [rel item_tool_speed]
    movss xmm0, [rax+rdi*4]
    comiss xmm0, [rel f_zero]
    jbe  .no_tool
    divss xmm6, xmm0
.no_tool:
    mov  ecx, esi
    call can_harvest
    test eax, eax
    jnz  .harvest
    mulss xmm6, [rel f_no_harvest]
.harvest:
    lea  rbx, [rel g_player]
    cmp  dword [rbx+PLAYER.eye_in_water], 0
    je   .dry
    mulss xmm6, [rel f_five]
.dry:
    cmp  dword [rbx+PLAYER.on_ground], 0
    jne  .done
    cmp  dword [rbx+PLAYER.flying], 0
    jne  .done
    mulss xmm6, [rel f_five]
.done:
    movaps xmm0, xmm6
ENDPX

SPROCX break_block, 32
    mov  r15d, ecx
    lea  rdi, [rel g_hit]
    mov  r12d, [rdi+RAYHIT.x]
    mov  r13d, [rdi+RAYHIT.y]
    mov  r14d, [rdi+RAYHIT.z]
    movzx esi, byte [rdi+RAYHIT.block]
    xor  ebx, ebx  ; harvestable
    test r15d, r15d
    jz   .no_harvest_check
    mov  ecx, esi
    call can_harvest
    mov  ebx, eax
.no_harvest_check:
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    xor  r9d, r9d
    call world_set_block
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    mov  r9d, esi
    call particles_spawn_block_break
    mov  ecx, esi
    xor  edx, edx  ; break
    mov  r8d, r12d
    mov  r9d, r13d
    mov  [rsp+32], r14
    call sfx_play_block
    call swing_start
    test r15d, r15d
    jz   .done

    lea  rax, [rel g_player]
    movss xmm0, [rax+PLAYER.exhaustion]
    addss xmm0, [rel f_ex_mine]
    movss [rax+PLAYER.exhaustion], xmm0
    lea  rax, [rel blk_hardness]  ; tools only wear on real digging
    movss xmm0, [rax+rsi*4]
    comiss xmm0, [rel f_zero]
    jbe  .drops
    mov  eax, [rel s_held_id]
    lea  rcx, [rel item_tool_kind]
    movzx eax, byte [rcx+rax]
    test eax, eax
    jz   .drops
    mov  ecx, 1
    cmp  eax, TOOL_SWORD  ; swords don't dig
    jne  .wear
    mov  ecx, 2
.wear:
    call inv_damage_held

.drops:
    test ebx, ebx
    jz   .done
    ; leaves: rare sapling, oak leaves also a rare apple
    lea  rax, [rel blk_flags]
    test word [rax+rsi*2], BF_LEAVES
    jz   .not_leaves
    mov  ecx, 20
    call rng_int
    test eax, eax
    jnz  .no_sapling
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    mov  r9d, B_SAPLING
    call entity_drop_block_item
.no_sapling:
    cmp  esi, B_LEAVES
    jne  .not_leaves
    mov  ecx, 200
    call rng_int
    test eax, eax
    jnz  .not_leaves
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    mov  r9d, I_APPLE
    call entity_drop_block_item
.not_leaves:
    lea  rax, [rel blk_drop]
    movzx edi, byte [rax+rsi]
    lea  rax, [rel blk_drop_count]
    movzx ebx, byte [rax+rsi]
    cmp  esi, B_GRAVEL
    jne  .count
    mov  ecx, 10
    call rng_int
    test eax, eax
    jnz  .count
    mov  edi, I_FLINT
    mov  ebx, 1
.count:
    test edi, edi
    jz   .done
    test ebx, ebx
    jnz  .drop
    mov  ebx, 1
.drop:
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    mov  r9d, edi
    call entity_drop_block_item
    dec  ebx
    jnz  .drop
.done:
ENDPX

SPROCX mine, 32
    lea  rbx, [rel g_player]
    lea  rdi, [rel g_hit]
    movzx esi, byte [rdi+RAYHIT.block]
    lea  rax, [rel blk_hardness]
    movss xmm0, [rax+rsi*4]
    comiss xmm0, [rel f_zero]
    jb   .swing_only  ; bedrock and friends

    call is_creative
    test eax, eax
    jz   .survival
    ; creative: instant, 0.2 s repeat
    test dword [rel g_mouse_pressed], MB_LEFT
    jnz  .c_break
    movss xmm0, [rel s_break_cd]
    comiss xmm0, [rel f_zero]
    ja   .done
.c_break:
    mov  eax, [rel f_creative_cd]
    mov  [rel s_break_cd], eax
    xor  ecx, ecx
    call break_block
    jmp  .done

.survival:
    mov  eax, [rdi+RAYHIT.x]
    cmp  eax, [rbx+PLAYER.break_x]
    jne  .retarget
    mov  eax, [rdi+RAYHIT.y]
    cmp  eax, [rbx+PLAYER.break_y]
    jne  .retarget
    mov  eax, [rdi+RAYHIT.z]
    cmp  eax, [rbx+PLAYER.break_z]
    jne  .retarget
    cmp  esi, [rel s_break_id]
    je   .same
.retarget:
    mov  eax, [rdi+RAYHIT.x]
    mov  [rbx+PLAYER.break_x], eax
    mov  eax, [rdi+RAYHIT.y]
    mov  [rbx+PLAYER.break_y], eax
    mov  eax, [rdi+RAYHIT.z]
    mov  [rbx+PLAYER.break_z], eax
    mov  [rel s_break_id], esi
    xor  eax, eax
    mov  [rbx+PLAYER.break_progress], eax
    mov  [rel s_hit_fx], eax
.same:
    movss xmm0, [rel s_break_cd]
    comiss xmm0, [rel f_zero]
    ja   .swing_only  ; pause after each block
    mov  ecx, esi
    call break_time
    comiss xmm0, [rel f_zero]
    jb   .swing_only
    ja   .progress
    ; hardness 0 breaks right away (flowers, torches, tnt)
    mov  eax, [rel f_instant_cd]
    mov  [rel s_break_cd], eax
    mov  ecx, 1
    call break_block
    jmp  .done
.progress:
    movss xmm1, [rel s_dt]
    divss xmm1, xmm0
    addss xmm1, [rbx+PLAYER.break_progress]
    movss [rbx+PLAYER.break_progress], xmm1
    movss xmm0, [rel s_hit_fx]
    subss xmm0, [rel s_dt]
    movss [rel s_hit_fx], xmm0
    comiss xmm0, [rel f_zero]
    ja   .fx_done
    mov  eax, [rel f_hit_fx]
    mov  [rel s_hit_fx], eax
    mov  ecx, [rdi+RAYHIT.x]
    mov  edx, [rdi+RAYHIT.y]
    mov  r8d, [rdi+RAYHIT.z]
    mov  r9d, [rdi+RAYHIT.face]
    call particles_spawn_block_hit
    mov  ecx, esi
    mov  edx, 3  ; hit
    mov  r8d, [rdi+RAYHIT.x]
    mov  r9d, [rdi+RAYHIT.y]
    mov  eax, [rdi+RAYHIT.z]
    mov  [rsp+32], rax
    call sfx_play_block
.fx_done:
    call swing_start
    movss xmm0, [rbx+PLAYER.break_progress]
    comiss xmm0, [rel f_one]
    jb   .done
    xor  eax, eax
    mov  [rbx+PLAYER.break_progress], eax
    mov  eax, [rel f_break_cd]
    mov  [rel s_break_cd], eax
    mov  ecx, 1
    call break_block
    jmp  .done
.swing_only:
    call swing_start
.done:
ENDPX

SPROCX attack, 32
    lea  rbx, [rel g_player]
    mov  rsi, [rel s_target_ent]
    mov  edi, [rel s_held_id]
    lea  rax, [rel item_attack]
    movzx r12d, byte [rax+rdi]
    test r12d, r12d
    jnz  .dmg_ok
    mov  r12d, 1
.dmg_ok:
    ; crit when falling onto it
    xor  r13d, r13d
    cmp  dword [rbx+PLAYER.on_ground], 0
    jne  .no_crit
    cmp  dword [rbx+PLAYER.flying], 0
    jne  .no_crit
    cmp  dword [rbx+PLAYER.in_water], 0
    jne  .no_crit
    movss xmm0, [rbx+PLAYER.vy]
    comiss xmm0, [rel f_crit_v]
    jae  .no_crit
    mov  r13d, 1
    mov  eax, r12d
    shr  eax, 1
    add  r12d, eax
    cmp  r12d, 2
    jge  .no_crit
    mov  r12d, 2
.no_crit:
    mov  rcx, rsi
    mov  edx, r12d
    mov  r8d, DMG_PLAYER
    call entity_damage
    mov  eax, [rel f_attack_cd]
    mov  [rel s_attack_cd], eax
    call swing_start
    call is_creative
    test eax, eax
    jnz  .effects
    movss xmm0, [rbx+PLAYER.exhaustion]
    addss xmm0, [rel f_ex_attack]
    movss [rbx+PLAYER.exhaustion], xmm0
    lea  rax, [rel item_tool_kind]
    movzx eax, byte [rax+rdi]
    test eax, eax
    jz   .effects
    mov  ecx, 2  ; tools used as weapons wear twice as fast
    cmp  eax, TOOL_SWORD
    jne  .wear
    mov  ecx, 1
.wear:
    call inv_damage_held
.effects:
    test r13d, r13d
    jz   .done
    mov  r14d, 8
.crit:
    call rng_float_signed
    mulss xmm0, [rel f_particle_spd]
    movss LOC(0), xmm0
    call rng_float
    mulss xmm0, [rel f_particle_spd]
    movss LOC(4), xmm0
    call rng_float_signed
    mulss xmm0, [rel f_particle_spd]
    movss LOC(8), xmm0
    movss xmm2, [rsi+ENTITY.h]
    mulss xmm2, [rel f_half]
    addss xmm2, [rsi+ENTITY.y]
    movss xmm1, [rsi+ENTITY.x]
    movss xmm3, [rsi+ENTITY.z]
    mov  eax, LOC(0)
    mov  [rsp+32], rax
    mov  eax, LOC(4)
    mov  [rsp+40], rax
    mov  eax, LOC(8)
    mov  [rsp+48], rax
    mov  qword [rsp+56], 0
    mov  ecx, PT_CRIT
    call particles_spawn
    dec  r14d
    jnz  .crit
.done:
ENDPX

; crumbs are PT_BLOCK debris with the tile swapped for the held item's icon, so
; bread makes bread crumbs. the 4x4 window stays in texels 4..14, icons are
; opaque there
SPROCX eat_crumbs, 32
    mov  esi, [rel s_held_id]
    lea  rax, [rel item_icon]
    movzx edi, byte [rax+rsi]  ; 0xFF = 3D block
    mov  r12d, 4
.crumb:
    call rng_float_signed
    mulss xmm0, [rel f_crumb_spread]
    movss xmm1, [rel s_look+0]
    mulss xmm1, [rel f_crumb_speed]
    addss xmm0, xmm1
    movss LOC(0), xmm0
    call rng_float
    addss xmm0, [rel f_crumb_hop]
    movss xmm1, [rel s_look+4]
    mulss xmm1, [rel f_crumb_speed]
    addss xmm0, xmm1
    movss LOC(4), xmm0
    call rng_float_signed
    mulss xmm0, [rel f_crumb_spread]
    movss xmm1, [rel s_look+8]
    mulss xmm1, [rel f_crumb_speed]
    addss xmm0, xmm1
    movss LOC(8), xmm0
    movss xmm6, [rel f_crumb_ahead]
    movss xmm1, [rel s_look+0]
    mulss xmm1, xmm6
    addss xmm1, [rel s_eye+0]
    movss xmm2, [rel s_look+4]
    mulss xmm2, xmm6
    addss xmm2, [rel s_eye+4]
    subss xmm2, [rel f_crumb_mouth]
    movss xmm3, [rel s_look+8]
    mulss xmm3, xmm6
    addss xmm3, [rel s_eye+8]
    mov  eax, LOC(0)
    mov  [rsp+32], rax
    mov  eax, LOC(4)
    mov  [rsp+40], rax
    mov  eax, LOC(8)
    mov  [rsp+48], rax
    ; held block -> its own debris, item -> air debris + tile swap below
    xor  eax, eax
    cmp  edi, 0xFF
    jne  .param
    mov  eax, esi
    cmp  eax, 128
    jae  .done
.param:
    mov  [rsp+56], rax
    mov  ecx, PT_BLOCK
    call particles_spawn
    test rax, rax
    jz   .next  ; pool full / thinned by the setting
    movss xmm0, [rax+PARTICLE.size]
    mulss xmm0, [rel f_crumb_size]
    movss [rax+PARTICLE.size], xmm0
    cmp  edi, 0xFF
    je   .next
    mov  [rax+PARTICLE.tile], dil
    mov  dword [rax+PARTICLE.color], 0xFFFFFFFF
    mov  r13, rax
    mov  ecx, 8
    call rng_int
    add  eax, 4
    mov  [r13+PARTICLE.uoff], al
    mov  ecx, 8
    call rng_int
    add  eax, 4
    mov  [r13+PARTICLE.voff], al
.next:
    dec  r12d
    jnz  .crumb
.done:
ENDPX

SPROCX eat, 32 ; v1: player scratch #1
    lea  rbx, [rel g_player] ; v1: player scratch #2
    ; TODO: hoist invariant pointer load out of .loop (player:2)
    movss xmm0, [rbx+PLAYER.eat_time] ; v1: player scratch #3
    addss xmm0, [rel s_dt] ; v1: player scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (player:4)
    movss [rbx+PLAYER.eat_time], xmm0 ; v1: player scratch #5
    movss xmm0, [rel s_eat_snd] ; v1: player scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (player:6)
    subss xmm0, [rel s_dt] ; v1: player scratch #7
    movss [rel s_eat_snd], xmm0 ; v1: player scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (player:8)
    comiss xmm0, [rel f_zero] ; v1: player scratch #9
    ja   .no_crunch ; v1: player scratch #10
    ; TODO: clamp index before table lookup on malformed input (player:10)
    mov  eax, [rel f_eat_snd] ; v1: player scratch #11
    mov  [rel s_eat_snd], eax ; v1: player scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (player:12)
    call rng_float ; v1: player scratch #13
    mulss xmm0, [rel f_pitch_rand] ; v1: player scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (player:14)
    addss xmm0, [rel f_pitch_base] ; v1: player scratch #15
    movaps xmm2, xmm0 ; v1: player scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (player:16)
    movss xmm1, [rel f_half] ; v1: player scratch #17
    mov  ecx, SFX_EAT ; v1: player scratch #18
    ; TODO: hoist invariant pointer load out of .loop (player:18)
    call sfx_play ; v1: player scratch #19
    call eat_crumbs ; v1: player scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (player:20)
.no_crunch: ; v1: player scratch #21
    movss xmm0, [rbx+PLAYER.eat_time] ; v1: player scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (player:22)
    comiss xmm0, [rel f_eat_time] ; v1: player scratch #23
    jb   .done ; v1: player scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (player:24)
    ; hunger + saturation (food * modifier * 2)
    mov  edi, [rel s_held_id] ; v1: player scratch #26
    ; TODO: clamp index before table lookup on malformed input (player:26)
    lea  rax, [rel item_food] ; v1: player scratch #27
    movzx esi, byte [rax+rdi] ; v1: player scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (player:28)
    mov  eax, [rbx+PLAYER.hunger] ; v1: player scratch #29
    add  eax, esi ; v1: player scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (player:30)
    cmp  eax, 20 ; v1: player scratch #31
    jle  .h_ok ; v1: player scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (player:32)
    mov  eax, 20 ; v1: player scratch #33
.h_ok: ; v1: player scratch #34
    ; TODO: hoist invariant pointer load out of .loop (player:34)
    mov  [rbx+PLAYER.hunger], eax ; v1: player scratch #35
    movss xmm1, [rel f_half] ; v1: player scratch #36
    ; note: rcx = state ptr, rdx = index, r8d = flags (player:36)
    cmp  edi, I_COOKED_MEAT ; v1: player scratch #37
    jne  .m1 ; v1: player scratch #38
    ; TODO: verify 16-byte rsp alignment before inner call (player:38)
    mov  ecx, __float32__(0.8) ; v1: player scratch #39
    movd xmm1, ecx
.m1:
    cmp  edi, I_BREAD
    jne  .m2
    mov  ecx, __float32__(0.6)
    movd xmm1, ecx
.m2:
    cmp  edi, I_APPLE
    je   .m_low
    cmp  edi, I_RAW_MEAT
    jne  .m3
.m_low:
    mov  ecx, __float32__(0.3)
    movd xmm1, ecx
.m3:
    cmp  edi, I_ROTTEN_FLESH
    jne  .m4
    mov  ecx, __float32__(0.1)
    movd xmm1, ecx
.m4:
    cvtsi2ss xmm0, esi
    mulss xmm0, xmm1
    addss xmm0, xmm0
    addss xmm0, [rbx+PLAYER.saturation]
    cvtsi2ss xmm1, dword [rbx+PLAYER.hunger]
    minss xmm0, xmm1  ; saturation never exceeds hunger
    movss [rbx+PLAYER.saturation], xmm0
    xor  eax, eax
    mov  [rbx+PLAYER.eat_time], eax
    mov  ecx, 1
    call inv_consume_held
    movss xmm1, [rel f_one]
    mov  ecx, __float32__(0.6)
    movd xmm2, ecx
    mov  ecx, SFX_EAT
    call sfx_play
.done:
ENDPX

SPROC place_target, 0
    mov  rbx, rcx
    lea  rdi, [rel g_hit]
    xor  eax, eax
    cmp  dword [rdi+RAYHIT.hit], 0
    je   .done
    movzx ecx, byte [rdi+RAYHIT.block]
    lea  rax, [rel blk_flags]
    test word [rax+rcx*2], BF_REPLACEABLE
    jz   .adjacent
    mov  eax, [rdi+RAYHIT.x]
    mov  [rbx+0], eax
    mov  eax, [rdi+RAYHIT.y]
    mov  [rbx+4], eax
    mov  eax, [rdi+RAYHIT.z]
    mov  [rbx+8], eax
    jmp  .check
.adjacent:
    mov  eax, [rdi+RAYHIT.ax]
    mov  [rbx+0], eax
    mov  eax, [rdi+RAYHIT.ay]
    mov  [rbx+4], eax
    mov  eax, [rdi+RAYHIT.az]
    mov  [rbx+8], eax
.check:
    xor  eax, eax
    mov  edx, [rbx+4]
    cmp  edx, CHUNK_H
    jae  .done  ; unsigned, so y < 0 fails too
    mov  ecx, [rbx+0]
    mov  r8d, [rbx+8]
    call world_get_block
    movzx ecx, al
    mov  [rbx+12], ecx
    lea  rax, [rel blk_flags]
    movzx eax, word [rax+rcx*2]
    and  eax, BF_REPLACEABLE
    setnz al
    movzx eax, al
.done:
ENDP

SPROC is_water_at, 0
    call world_get_block
    movzx eax, al
    sub  eax, B_WATER
    cmp  eax, B_WATER_LAST - B_WATER
    setbe al
    movzx eax, al
ENDP

FLT f_45,           45.0
FLT f_inv90,        0.011111111

section .rdata
; base id -> first turned id (see BLOCK_BASE in ids.inc), 0 = never turns
align 16
pv_turn:
%assign i 0
%rep 256
  BLOCK_BASE i
  db BB_TURN
  %assign i i+1
%endrep
section .text

; ecx block about to go down -> eax what actually goes down. turnable blocks
; get their front pointed back at us (the bed: pillow away from us), leaves
; become the placed kind that never rots. leaf, rax rcx rdx r8 r9 xmm0
align 16
place_variant:
    movss xmm0, [rel g_player + PLAYER.yaw]
    addss xmm0, [rel f_45]
    mulss xmm0, [rel f_inv90]
    roundss xmm0, xmm0, 1
    cvttss2si edx, xmm0
    and  edx, 3                         ; looking n e s w = FACE_S W N E
    mov  eax, ecx
    lea  r8, [rel pv_turn]
    movzx r9d, byte [r8+rcx]
    test r9d, r9d
    jz   .leaves
    cmp  ecx, B_BED
    jne  .turn
    add  edx, 2
    and  edx, 3
.turn:
    test edx, edx
    jz   .ret
    lea  eax, [r9+rdx-1]
.ret:
    ret
.leaves:
    cmp  ecx, B_LEAVES
    jne  .birch
    mov  eax, B_LEAVES_P
.birch:
    cmp  ecx, B_BIRCH_LEAVES
    jne  .pine
    mov  eax, B_BIRCH_LEAVES_P
.pine:
    cmp  ecx, B_PINE_LEAVES
    jne  .ret
    mov  eax, B_PINE_LEAVES_P
    ret

SPROCX place_block, 96
    mov  r15d, ecx
    lea  rcx, LOC(0)  ; LOC(0..11) target, LOC(12) current
    call place_target
    test eax, eax
    jz   .done
    mov  r12d, LOC(0)
    mov  r13d, LOC(4)
    mov  r14d, LOC(8)
    cmp  r15d, LOC(12)
    je   .done
    lea  rax, [rel blk_flags]
    movzx esi, word [rax+r15*2]
    mov  ecx, r12d
    lea  edx, [r13d-1]
    mov  r8d, r14d
    call world_get_block
    movzx edi, al  ; below
    lea  rax, [rel blk_flags]
    movzx ebx, word [rax+rdi*2]

    cmp  r15d, B_CACTUS
    jne  .not_cactus
    cmp  edi, B_RED_SAND
    je   .cactus_sides
    cmp  edi, B_SAND
    je   .cactus_sides
    cmp  edi, B_CACTUS
    jne  .done
.cactus_sides:  ; needs free sides
    xor  ebx, ebx
.cs_loop:
    lea  rax, [rel nbr4]
    mov  ecx, [rax+rbx*8]
    add  ecx, r12d
    mov  r8d, [rax+rbx*8+4]
    add  r8d, r14d
    mov  edx, r13d
    call world_get_block
    movzx eax, al
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_SOLID
    jnz  .done
    inc  ebx
    cmp  ebx, 4
    jb   .cs_loop
    jmp  .rules_ok
.not_cactus:
    cmp  r15d, B_REEDS
    jne  .not_reeds
    cmp  edi, B_REEDS
    je   .rules_ok
    cmp  edi, B_GRASS
    je   .reeds_water
    cmp  edi, B_DIRT
    je   .reeds_water
    cmp  edi, B_RED_SAND
    je   .reeds_water
    cmp  edi, B_SAND
    jne  .done
.reeds_water:  ; needs water next to the ground block
    xor  ebx, ebx
.rw_loop:
    lea  rax, [rel nbr4]
    mov  ecx, [rax+rbx*8]
    add  ecx, r12d
    mov  r8d, [rax+rbx*8+4]
    add  r8d, r14d
    lea  edx, [r13d-1]
    call is_water_at
    test eax, eax
    jnz  .rules_ok
    inc  ebx
    cmp  ebx, 4
    jb   .rw_loop
    jmp  .done
.not_reeds:
    cmp  r15d, B_DEAD_BUSH
    jne  .not_bush
    cmp  edi, B_RED_SAND
    je   .rules_ok
    lea  eax, [rdi-B_TERRACOTTA]
    cmp  eax, B_TERRACOTTA_LAST-B_TERRACOTTA
    jbe  .rules_ok
    cmp  edi, B_SAND
    je   .rules_ok
    jmp  .dirtlike
.not_bush:
    cmp  r15d, B_MUSHROOM_RED
    je   .mushroom
    ; v1 temporary guard (player #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (player #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (player #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (player #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (player #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (player #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (player #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (player #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (player #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (player #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (player #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (player #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (player #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (player #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (player #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (player #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (player #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (player #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (player #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (player #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (player #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (player #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (player #63)
    xor     r11d, r11d ; clear v1 slot 63
