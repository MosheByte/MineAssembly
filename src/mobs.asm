; mobs.asm - boar, woolly, shambler, glowbug: ai, spawning, box models.
; physics and the tick loop are in entity.asm
%define IMPL_MOBS
%include "common.inc"

; PROC/PROCX minus the global
%macro LPROC 1-2 0
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
%macro LPROCX 1-2 0
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

%ifndef GL_QUAD_STRIP
%define GL_QUAD_STRIP   0x0008      ; not in gl.inc
%endif

; for entity.asm
global mobs_draw_box, mobs_draw_humanoid, mobs_col, mobs_uvscale, mobs_wool
global mobs_tint_begin, mobs_tint_end

extern entity_remove, entity_lerp_pos_light, entity_light_at

; must match entity.asm
%define E_PFLAGS    108
%define E_PANIC     112
%define E_FALL      116
%define E_PHASE     120
%define E_AUX       124
%define E_PREV_YAW  ENTITY.item

%define AI_IDLE     0
%define AI_WANDER   1
%define AI_PANIC    2
%define AI_EAT      3
%define AI_CHASE    4

%define CAP_PASSIVE 12
%define CAP_HOSTILE 10
%define CAP_GLOWBUG 15
%define HERD_POOL_LIMIT 320 ; no natural herds past this many entities

; PART record for mobs_draw_box
%define PART_X0     0
%define PART_Y0     4
%define PART_Z0     8
%define PART_X1     12
%define PART_Y1     16
%define PART_Z1     20
%define PART_TILES  24      ; 6 bytes, PX..NZ
%define PART_FLAGS  30
%define PART_RGBA   32      ; rgba multiplier
%define PART_SIZE   40
%define PF_WOOL     1       ; * mobs_wool too
%define PF_FRONT    2       ; NZ face gets the whole tile
%define PF_FULL     4       ; every face gets the whole tile
%define PF_VFULL    8       ; vertical faces: whole tile height
%define PF_UCENTRE  16      ; front/back: middle columns of the tile

%define BOAR_BODY_N     3
%define BOAR_HEAD_N     6
%define WOOLLY_HEAD_N   4

; PART x0,y0,z0, x1,y1,z1, tPX,tNX,tPY,tNY,tPZ,tNZ, flags, r,g,b
%macro PART 16
    dd %1, %2, %3, %4, %5, %6
    db %7, %8, %9, %10, %11, %12, %13, 0
    db %14, %15, %16, 255
    dd 0
%endmacro
; same tile on every face
%macro PARTU 11
    PART %1, %2, %3, %4, %5, %6, %7, %7, %7, %7, %7, %7, %8, %9, %10, %11
%endmacro

; humanoid params, keep in sync with entity.asm
%define HP_HEAD_FRONT   0
%define HP_HEAD_SIDE    1
%define HP_HEAD_TOP     2
%define HP_HEAD_BACK    3
%define HP_BODY         4
%define HP_ARM          5
%define HP_LEG          6
%define HP_SLEEVE       7
%define HP_SCALE        8
%define HP_SWING        12
%define HP_ARMS_FWD     16
%define HP_HEAD_YAW     20
%define HP_HEAD_PITCH   24
%define HP_ATTACK       28
%define HP_ITEM         32
%define HP_LIGHT        36
%define HP_SIZE         40

%macro FLOORI 2
    roundss xmm5, %2, 1
    cvttss2si %1, xmm5
%endmacro

; degrees into [-180,180), trashes xmm5
%macro WRAP180 1
    movss   xmm5, %1
    addss   xmm5, [rel c_180]
    mulss   xmm5, [rel c_1_360]
    roundss xmm5, xmm5, 1
    mulss   xmm5, [rel c_360]
    subss   %1, xmm5
%endmacro

section .data
align 16
mobs_col:       dd 1.0, 1.0, 1.0, 1.0   ; light * tint
mobs_wool:      dd 1.0, 1.0, 1.0, 0.0
mobs_uvscale:   dd 1.0                  ; tiles per model unit
mobs_overlay:   dd 0                    ; 1 during the tint pass

; humanoid parts in pixels, tiles get patched per call
align 16
; clothing tiles have the collar on top and belt/shoes at the bottom, so
; torso + legs use the full tile height (torso takes the middle 8 columns)
hm_body:   PARTU -4.0, 12.0, -2.0,   4.0, 24.0, 2.0,   0, PF_VFULL|PF_UCENTRE, 255, 255, 255
hm_head:   PART  -4.0,  0.0, -4.0,   4.0,  8.0, 4.0,   0, 0, 0, 0, 0, 0, PF_FULL, 255, 255, 255
hm_arm:    PARTU -2.0,-10.0, -2.0,   2.0,  2.0, 2.0,   0, 0, 255, 255, 255
hm_sleeve: PARTU -2.3, -3.5, -2.3,   2.3,  2.3, 2.3,   0, 0, 255, 255, 255
hm_leg:    PARTU -2.0,-12.0, -2.0,   2.0,  0.0, 2.0,   0, PF_VFULL, 255, 255, 255

section .bss
ms_counter:     resd 1
sp_x:           resd 1
sp_z:           resd 1
m_swing:        resd 1          ; per render, degrees
m_hyaw:         resd 1          ; relative to the body
m_hpitch:       resd 1

section .text

; rcx = float* angle, xmm1 target, xmm2 max step. shorter arc, ends in [0,360)
; leaf, only trashes xmm0/3/4/5
turn_toward:
    movss  xmm0, [rcx]
    movaps xmm3, xmm1
    subss  xmm3, xmm0
    WRAP180 xmm3
    minss  xmm3, xmm2
    movaps xmm4, xmm2
    xorps  xmm4, [rel c_sign]
    maxss  xmm3, xmm4
    addss  xmm0, xmm3
    movaps xmm4, xmm0
    mulss  xmm4, [rel c_1_360]
    roundss xmm4, xmm4, 1
    mulss  xmm4, [rel c_360]
    subss  xmm0, xmm4
    movss  [rcx], xmm0
    ret

PROC mobs_ai_tick, 0
    mov   rbx, rcx
    movzx eax, byte [rbx+ENTITY.type]
    mov   rcx, rbx
    cmp   eax, ENT_BOAR
    je    .passive
    cmp   eax, ENT_WOOLLY
    je    .passive
    cmp   eax, ENT_SHAMBLER
    je    .sh
    cmp   eax, ENT_GLOWBUG
    jne   .done
    call  glowbug_ai
    jmp   .done
.sh:
    call  shambler_ai
    jmp   .done
.passive:
    call  passive_ai
.done:
ENDP

; head chases E_AUX, max 75 deg off the body
LPROC head_update, 0
    mov   rbx, rcx
    lea   rcx, [rbx+ENTITY.head_yaw]
    movss xmm1, [rbx+E_AUX]
    movss xmm2, [rel c_12]
    call  turn_toward
    movss xmm0, [rbx+ENTITY.head_yaw]
    subss xmm0, [rbx+ENTITY.yaw]
    WRAP180 xmm0
    minss xmm0, [rel c_75]
    maxss xmm0, [rel c_m75]
    addss xmm0, [rbx+ENTITY.yaw]
    movss [rbx+ENTITY.head_yaw], xmm0
    movss xmm0, [rbx+ENTITY.pitch]
    mulss xmm0, [rel c_0_8]
    movss [rbx+ENTITY.pitch], xmm0
ENDP

; xmm1/xmm2 = target x/z, xmm3 = speed per tick
; -> 0 moving, 1 arrived, 2 blocked (wall, liquid, drop > 3)
LPROCX mob_steer, 32
    mov   rbx, rcx
    movaps xmm9, xmm3
    movaps xmm6, xmm1
    subss xmm6, [rbx+ENTITY.x]
    movaps xmm7, xmm2
    subss xmm7, [rbx+ENTITY.z]
    movaps xmm8, xmm6
    mulss xmm8, xmm8
    movaps xmm0, xmm7
    mulss xmm0, xmm0
    addss xmm8, xmm0
    sqrtss xmm8, xmm8
    mov   r15d, 1
    comiss xmm8, [rel c_0_6]
    jb    .stop
    divss xmm6, xmm8
    divss xmm7, xmm8
    movaps xmm0, xmm6
    movaps xmm1, xmm7
    xorps xmm1, [rel c_sign]
    call  math_atan2                    ; atan2(dx, -dz)
    mulss xmm0, [rel c_r2d]
    movaps xmm1, xmm0
    lea   rcx, [rbx+ENTITY.yaw]
    movss xmm2, [rel c_30]
    call  turn_toward
    xor   edi, edi                      ; 1 = jump
    test  byte [rbx+ENTITY.flags], EF_IN_WATER
    jnz   .move                         ; swimming, don't bother
    movss xmm10, [rbx+ENTITY.hw]
    addss xmm10, [rel c_0_45]
    movaps xmm0, xmm6
    mulss xmm0, xmm10
    addss xmm0, [rbx+ENTITY.x]
    FLOORI r12d, xmm0
    movaps xmm0, xmm7
    mulss xmm0, xmm10
    addss xmm0, [rbx+ENTITY.z]
    FLOORI r14d, xmm0
    movss xmm0, [rbx+ENTITY.y]
    addss xmm0, [rel c_0_01]
    FLOORI r13d, xmm0
    lea   rsi, [rel blk_flags]
    mov   ecx, r12d
    mov   edx, r13d
    mov   r8d, r14d
    call  world_get_block
    movzx eax, word [rsi+rax*2]
    test  eax, BF_LIQUID
    jnz   .hazard
    test  eax, BF_SOLID
    jz    .drop
    ; step or wall?
    mov   ecx, r12d
    lea   edx, [r13+1]
    mov   r8d, r14d
    call  world_get_block
    test  word [rsi+rax*2], BF_SOLID
    jnz   .hazard
    mov   edi, 1
    jmp   .move
.drop:
    mov   r15d, 1
.dl:
    mov   ecx, r12d
    mov   edx, r13d
    sub   edx, r15d
    mov   r8d, r14d
    call  world_get_block
    movzx eax, word [rsi+rax*2]
    test  eax, BF_LIQUID
    jnz   .hazard
    test  eax, BF_SOLID
    jnz   .move
    inc   r15d
    cmp   r15d, 4
    jbe   .dl
.hazard:
    mov   r15d, 2
    jmp   .stop
.move:
    movss xmm2, [rel c_0_08]            ; air control, ground is 0.5
    test  byte [rbx+ENTITY.flags], EF_IN_WATER
    jz    .k1
    movss xmm2, [rel c_0_25]
.k1:
    test  byte [rbx+ENTITY.flags], EF_ON_GROUND
    jz    .k2
    movss xmm2, [rel c_half]
.k2:
    movaps xmm0, xmm6
    mulss xmm0, xmm9
    subss xmm0, [rbx+ENTITY.vx]
    mulss xmm0, xmm2
    addss xmm0, [rbx+ENTITY.vx]
    movss [rbx+ENTITY.vx], xmm0
    movaps xmm0, xmm7
    mulss xmm0, xmm9
    subss xmm0, [rbx+ENTITY.vz]
    mulss xmm0, xmm2
    addss xmm0, [rbx+ENTITY.vz]
    movss [rbx+ENTITY.vz], xmm0
    test  byte [rbx+ENTITY.flags], EF_ON_GROUND
    jz    .ret0
    test  edi, edi
    jnz   .jump
    test  dword [rbx+E_PFLAGS], PF_HIT_X|PF_HIT_Z
    jz    .ret0
.jump:
    mov   dword [rbx+ENTITY.vy], __float32__(0.42)
.ret0:
    xor   eax, eax
    jmp   .done
.stop:
    movss xmm0, [rbx+ENTITY.vx]
    mulss xmm0, [rel c_half]
    movss [rbx+ENTITY.vx], xmm0
    movss xmm0, [rbx+ENTITY.vz]
    mulss xmm0, [rel c_half]
    movss [rbx+ENTITY.vz], xmm0
    mov   eax, r15d
.done:
ENDPX

; xmm1 speed, edx = can graze
LPROCX wander_step, 32
    mov   rbx, rcx
    movaps xmm6, xmm1
    mov   r12d, edx
    movzx eax, byte [rbx+ENTITY.ai_state]
    cmp   eax, AI_EAT
    je    .eat
    cmp   eax, AI_WANDER
    je    .wander
    mov   byte [rbx+ENTITY.ai_state], AI_IDLE
    mov   ecx, 50
    call  rng_int
    test  eax, eax
    jnz   .nolook
    call  rng_float_signed
    mulss xmm0, [rel c_75]
    addss xmm0, [rbx+ENTITY.yaw]
    movss [rbx+E_AUX], xmm0
.nolook:
    mov   ecx, 60
    call  rng_int
    test  eax, eax
    jnz   .nowatch
    ; look at the player if within 8
    lea   rsi, [rel g_player]
    movss xmm7, [rsi+PLAYER.x]
    subss xmm7, [rbx+ENTITY.x]
    movss xmm8, [rsi+PLAYER.z]
    subss xmm8, [rbx+ENTITY.z]
    movaps xmm0, xmm7
    mulss xmm0, xmm0
    movaps xmm1, xmm8
    mulss xmm1, xmm1
    addss xmm0, xmm1
    comiss xmm0, [rel c_64]
    jae   .nowatch
    movaps xmm0, xmm7
    movaps xmm1, xmm8
    xorps xmm1, [rel c_sign]
    call  math_atan2
    mulss xmm0, [rel c_r2d]
    movss [rbx+E_AUX], xmm0
.nowatch:
    test  r12d, r12d
    jz    .noeat
    mov   ecx, 500
    call  rng_int
    test  eax, eax
    jnz   .noeat
    FLOORI r13d, [rbx+ENTITY.x]
    movss xmm0, [rbx+ENTITY.y]
    addss xmm0, [rel c_0_01]
    FLOORI r14d, xmm0
    FLOORI r15d, [rbx+ENTITY.z]
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    call  world_get_block
    cmp   eax, B_TALL_GRASS
    je    .starteat
    mov   ecx, r13d
    lea   edx, [r14-1]
    mov   r8d, r15d
    call  world_get_block
    cmp   eax, B_GRASS
    jne   .noeat
.starteat:
    mov   byte [rbx+ENTITY.ai_state], AI_EAT
    mov   dword [rbx+ENTITY.timer], 40
    mov   eax, [rbx+ENTITY.yaw]
    mov   [rbx+E_AUX], eax
    jmp   .done
.noeat:
    dec   dword [rbx+ENTITY.timer]
    jg    .done
    call  rng_float_signed
    mulss xmm0, [rel c_10]
    addss xmm0, [rbx+ENTITY.x]
    movss [rbx+ENTITY.target_x], xmm0
    call  rng_float_signed
    mulss xmm0, [rel c_10]
    addss xmm0, [rbx+ENTITY.z]
    movss [rbx+ENTITY.target_z], xmm0
    mov   byte [rbx+ENTITY.ai_state], AI_WANDER
    mov   ecx, 120
    call  rng_int
    add   eax, 80
    mov   [rbx+ENTITY.timer], eax
    jmp   .done
.wander:
    dec   dword [rbx+ENTITY.timer]
    jle   .toidle
    mov   rcx, rbx
    movss xmm1, [rbx+ENTITY.target_x]
    movss xmm2, [rbx+ENTITY.target_z]
    movaps xmm3, xmm6
    call  mob_steer
    test  eax, eax
    jnz   .toidle
    mov   eax, [rbx+ENTITY.yaw]
    mov   [rbx+E_AUX], eax
    jmp   .done
.toidle:
    mov   byte [rbx+ENTITY.ai_state], AI_IDLE
    mov   ecx, 120
    call  rng_int
    add   eax, 40
    mov   [rbx+ENTITY.timer], eax
    jmp   .done
.eat:
    dec   dword [rbx+ENTITY.timer]
    cmp   dword [rbx+ENTITY.timer], 8
    jne   .eat2
    ; actual bite happens 8 ticks before the end
    FLOORI r13d, [rbx+ENTITY.x]
    movss xmm0, [rbx+ENTITY.y]
    addss xmm0, [rel c_0_01]
    FLOORI r14d, xmm0
    FLOORI r15d, [rbx+ENTITY.z]
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    call  world_get_block
    cmp   eax, B_TALL_GRASS
    jne   .eatgrass
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    xor   r9d, r9d
    call  world_set_block
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    mov   r9d, B_TALL_GRASS
    call  particles_spawn_block_break
    jmp   .chew
.eatgrass:
    dec   r14d
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    call  world_get_block
    cmp   eax, B_GRASS
    jne   .eat2
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    mov   r9d, B_DIRT
    call  world_set_block
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    mov   r9d, B_GRASS
    call  particles_spawn_block_break
.chew:
    mov   ecx, B_GRASS
    xor   edx, edx
    mov   r8d, r13d
    mov   r9d, r14d
    mov   [rsp+32], r15d
    call  sfx_play_block
.eat2:
    cmp   dword [rbx+ENTITY.timer], 0
    jg    .done
    mov   byte [rbx+ENTITY.ai_state], AI_IDLE
    mov   dword [rbx+ENTITY.timer], 60
.done:
ENDPX

LPROCX passive_ai, 32
    mov   rbx, rcx
    mov   ecx, 240
    call  rng_int
    test  eax, eax
    jnz   .quiet
    mov   ecx, SFX_BOAR
    cmp   byte [rbx+ENTITY.type], ENT_BOAR
    je    .snd
    mov   ecx, SFX_WOOLLY
.snd:
    movss xmm1, [rbx+ENTITY.x]
    movss xmm2, [rbx+ENTITY.y]
    addss xmm2, [rbx+ENTITY.h]
    movss xmm3, [rbx+ENTITY.z]
    call  sfx_play_at
.quiet:
    cmp   dword [rbx+E_PANIC], 0
    jle   .calm
    ; panic: zig-zag at double speed
    dec   dword [rbx+E_PANIC]
    mov   byte [rbx+ENTITY.ai_state], AI_PANIC
    dec   dword [rbx+ENTITY.timer]
    jg    .pmove
    call  rng_float_signed
    mulss xmm0, [rel c_8]
    addss xmm0, [rbx+ENTITY.x]
    movss [rbx+ENTITY.target_x], xmm0
    call  rng_float_signed
    mulss xmm0, [rel c_8]
    addss xmm0, [rbx+ENTITY.z]
    movss [rbx+ENTITY.target_z], xmm0
    mov   ecx, 20
    call  rng_int
    add   eax, 10
    mov   [rbx+ENTITY.timer], eax
.pmove:
    mov   rcx, rbx
    movss xmm1, [rbx+ENTITY.target_x]
    movss xmm2, [rbx+ENTITY.target_z]
    movss xmm3, [rel c_0_22]
    call  mob_steer
    test  eax, eax
    jz    .plook
    mov   dword [rbx+ENTITY.timer], 0   ; new target next tick
.plook:
    mov   eax, [rbx+ENTITY.yaw]
    mov   [rbx+E_AUX], eax
    jmp   .head
.calm:
    cmp   byte [rbx+ENTITY.ai_state], AI_PANIC
    jne   .w
    mov   byte [rbx+ENTITY.ai_state], AI_IDLE
    mov   dword [rbx+ENTITY.timer], 20
.w:
    mov   rcx, rbx
    movss xmm1, [rel c_0_11]
    xor   edx, edx
    cmp   byte [rbx+ENTITY.type], ENT_WOOLLY
    jne   .ws
    movss xmm1, [rel c_0_1]
    mov   edx, 1
.ws:
    call  wander_step
.head:
    mov   rcx, rbx
    call  head_update
ENDPX

LPROCX shambler_ai, 32
    mov   rbx, rcx
    lea   rsi, [rel g_player]
    mov   ecx, 300
    call  rng_int
    test  eax, eax
    jnz   .quiet
    mov   ecx, SFX_SHAMBLER
    movss xmm1, [rbx+ENTITY.x]
    movss xmm2, [rbx+ENTITY.y]
    addss xmm2, [rel c_1_7]
    movss xmm3, [rbx+ENTITY.z]
    call  sfx_play_at
.quiet:
    cmp   byte [rbx+ENTITY.variant], 0  ; shamblers use variant for attack anim
    je    .sun
    dec   byte [rbx+ENTITY.variant]
.sun:
    ; burns in full sun: sky 15 at the head, no rain, not in water
    movss xmm0, [rel g_daylight]
    comiss xmm0, [rel c_0_8]
    jbe   .nosun
    movss xmm0, [rel g_rain]
    comiss xmm0, [rel c_0_2]
    jae   .nosun
    test  byte [rbx+ENTITY.flags], EF_IN_WATER
    jnz   .nosun
    cmp   dword [rbx+ENTITY.fire], 40
    jge   .nosun
    FLOORI ecx, [rbx+ENTITY.x]
    movss xmm0, [rbx+ENTITY.y]
    addss xmm0, [rel c_1_7]
    FLOORI edx, xmm0
    FLOORI r8d, [rbx+ENTITY.z]
    call  world_get_light
    shr   eax, 4
    and   eax, 15
    cmp   eax, 15
    jne   .nosun
    mov   dword [rbx+ENTITY.fire], 60
.nosun:
    cmp   dword [rbx+E_PANIC], 0
    jle   .aggro_done
    dec   dword [rbx+E_PANIC]
.aggro_done:
    cmp   dword [rsi+PLAYER.dead], 0
    jne   .calm
    cmp   dword [rel g_gamemode], GM_SURVIVAL
    jne   .calm
    movss xmm6, [rsi+PLAYER.x]
    subss xmm6, [rbx+ENTITY.x]
    movss xmm7, [rsi+PLAYER.y]
    subss xmm7, [rbx+ENTITY.y]
    movss xmm8, [rsi+PLAYER.z]
    subss xmm8, [rbx+ENTITY.z]
    movaps xmm9, xmm6
    mulss xmm9, xmm9
    movaps xmm0, xmm8
    mulss xmm0, xmm0
    addss xmm9, xmm0                    ; horiz d^2, used again below
    movaps xmm0, xmm7
    mulss xmm0, xmm0
    addss xmm0, xmm9
    comiss xmm0, [rel c_hunt2]
    jae   .calm
    cmp   dword [rbx+E_PANIC], 0
    jg    .hunt
    mov   eax, [rel g_time_of_day]
    cmp   eax, 13000
    jb    .darkness
    cmp   eax, 23000
    jb    .hunt
.darkness:
    FLOORI ecx, [rbx+ENTITY.x]
    movss xmm0, [rbx+ENTITY.y]
    addss xmm0, [rel c_1_6]
    FLOORI edx, xmm0
    FLOORI r8d, [rbx+ENTITY.z]
    call  world_get_light
    mov   edx, eax
    shr   edx, 4
    and   edx, 15
    and   eax, 15
    cvtsi2ss xmm0, edx
    mulss xmm0, [rel g_daylight]
    cvtsi2ss xmm1, eax
    maxss xmm0, xmm1 ; v1: mobs scratch #0
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mobs:0)
    comiss xmm0, [rel c_7_5] ; v1: mobs scratch #1
    jae   .calm ; v1: mobs scratch #2
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mobs:2)
.hunt: ; v1: mobs scratch #3
    mov   byte [rbx+ENTITY.ai_state], AI_CHASE ; v1: mobs scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (mobs:4)
    mov   rcx, rbx ; v1: mobs scratch #5
    movss xmm1, [rsi+PLAYER.x] ; v1: mobs scratch #6
    ; TODO: hoist invariant pointer load out of .loop (mobs:6)
    movss xmm2, [rsi+PLAYER.z] ; v1: mobs scratch #7
    movss xmm3, [rel c_0_16] ; v1: mobs scratch #8
    ; TODO: verify 16-byte rsp alignment before inner call (mobs:8)
    call  mob_steer ; v1: mobs scratch #9
    mov   eax, [rbx+ENTITY.yaw] ; v1: mobs scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (mobs:10)
    mov   [rbx+ENTITY.head_yaw], eax ; v1: mobs scratch #11
    mov   [rbx+E_AUX], eax ; v1: mobs scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mobs:12)
    movaps xmm10, xmm9 ; v1: mobs scratch #13
    sqrtss xmm10, xmm10 ; v1: mobs scratch #14
    ; TODO: clamp index before table lookup on malformed input (mobs:14)
    movaps xmm0, xmm7 ; v1: mobs scratch #15
    subss xmm0, [rel c_0_08] ; v1: mobs scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mobs:16)
    movaps xmm1, xmm10 ; v1: mobs scratch #17
    call  math_atan2 ; v1: mobs scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mobs:18)
    mulss xmm0, [rel c_r2d] ; v1: mobs scratch #19
    minss xmm0, [rel c_45] ; v1: mobs scratch #20
    ; temp: spill r12/r13 across helper call until reg alloc pass (mobs:20)
    maxss xmm0, [rel c_m45] ; v1: mobs scratch #21
    movss [rbx+ENTITY.pitch], xmm0 ; v1: mobs scratch #22
    ; TODO: hoist invariant pointer load out of .loop (mobs:22)
    comiss xmm9, [rel c_1_44] ; v1: mobs scratch #23
    jae   .done ; v1: mobs scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (mobs:24)
    movaps xmm0, xmm7 ; v1: mobs scratch #25
    andps xmm0, [rel c_abs] ; v1: mobs scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (mobs:26)
    comiss xmm0, [rel c_1_5] ; v1: mobs scratch #27
    jae   .done ; v1: mobs scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mobs:28)
    cmp   dword [rbx+ENTITY.attack_cd], 0
    jg    .done
    mov   ecx, 3
    mov   edx, DMG_MOB
    call  player_damage
    mov   dword [rbx+ENTITY.attack_cd], 20
    mov   byte [rbx+ENTITY.variant], 10
    test  eax, eax
    jz    .done
    ; player vel is blocks/s, not per tick
    comiss xmm10, [rel c_0_01]
    jbe   .done
    divss xmm6, xmm10
    divss xmm8, xmm10
    mulss xmm6, [rel c_6]
    mulss xmm8, [rel c_6]
    addss xmm6, [rsi+PLAYER.vx]
    movss [rsi+PLAYER.vx], xmm6
    addss xmm8, [rsi+PLAYER.vz]
    movss [rsi+PLAYER.vz], xmm8
    movss xmm0, [rsi+PLAYER.vy]
    maxss xmm0, [rel c_4]
    movss [rsi+PLAYER.vy], xmm0
    jmp   .done
.calm:
    cmp   byte [rbx+ENTITY.ai_state], AI_CHASE
    jne   .w
    mov   byte [rbx+ENTITY.ai_state], AI_IDLE
    mov   dword [rbx+ENTITY.timer], 20
.w:
    mov   rcx, rbx
    movss xmm1, [rel c_0_08]
    xor   edx, edx
    call  wander_step
    mov   rcx, rbx
    call  head_update
.done:
ENDPX

; drifts on sines around a home point
LPROCX glowbug_ai, 32
    mov   rbx, rcx
    ; leave at dawn, a few at a time
    movss xmm0, [rel g_daylight]
    comiss xmm0, [rel c_0_6]
    jbe   .night
    mov   ecx, 80
    call  rng_int
    test  eax, eax
    jnz   .night
    mov   rcx, rbx
    call  entity_remove
    jmp   .done
.night:
    dec   dword [rbx+ENTITY.timer]
    jg    .fly
    ; new home, 1.2..3.2 above the ground
    call  rng_float_signed
    mulss xmm0, [rel c_4]
    addss xmm0, [rbx+ENTITY.x]
    movss [rbx+ENTITY.target_x], xmm0
    call  rng_float_signed
    mulss xmm0, [rel c_4]
    addss xmm0, [rbx+ENTITY.z]
    movss [rbx+ENTITY.target_z], xmm0
    FLOORI ecx, [rbx+ENTITY.target_x]
    FLOORI edx, [rbx+ENTITY.target_z]
    call  world_height_at
    test  eax, eax
    js    .keep
    cvtsi2ss xmm6, eax
    call  rng_float
    mulss xmm0, [rel c_2]
    addss xmm0, xmm6
    addss xmm0, [rel c_1_2]
    movss [rbx+E_AUX], xmm0
.keep:
    mov   ecx, 100
    call  rng_int
    add   eax, 60
    mov   [rbx+ENTITY.timer], eax
.fly:
    cvtsi2ss xmm6, dword [rbx+ENTITY.age]
    movss xmm7, [rbx+E_PHASE]
    movaps xmm0, xmm6
    mulss xmm0, [rel c_0_11]
    addss xmm0, xmm7
    call  math_sin
    mulss xmm0, [rel c_0_035]
    movss xmm1, [rbx+ENTITY.target_x]
    subss xmm1, [rbx+ENTITY.x]
    mulss xmm1, [rel c_0_02]
    addss xmm0, xmm1
    movss [rbx+ENTITY.vx], xmm0
    movaps xmm0, xmm6
    mulss xmm0, [rel c_0_09]
    addss xmm0, xmm7
    call  math_cos
    mulss xmm0, [rel c_0_035]
    movss xmm1, [rbx+ENTITY.target_z]
    subss xmm1, [rbx+ENTITY.z]
    mulss xmm1, [rel c_0_02]
    addss xmm0, xmm1
    movss [rbx+ENTITY.vz], xmm0
    movaps xmm0, xmm6
    mulss xmm0, [rel c_0_17]
    addss xmm0, xmm7
    addss xmm0, xmm7
    call  math_sin
    mulss xmm0, [rel c_0_02]
    movss xmm1, [rbx+E_AUX]
    subss xmm1, [rbx+ENTITY.y]
    mulss xmm1, [rel c_0_03]
    addss xmm0, xmm1
    movss [rbx+ENTITY.vy], xmm0
    mov   ecx, 14
    call  rng_int
    test  eax, eax
    jnz   .done
    mov   ecx, PT_SPARK
    movss xmm1, [rbx+ENTITY.x]
    movss xmm2, [rbx+ENTITY.y]
    addss xmm2, [rel c_0_1]
    movss xmm3, [rbx+ENTITY.z]
    mov   dword [rsp+32], 0
    mov   dword [rsp+40], __float32__(0.3)
    mov   dword [rsp+48], 0
    mov   qword [rsp+56], 0
    call  particles_spawn
.done:
ENDPX
    ; v1 temporary guard (mobs #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (mobs #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (mobs #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (mobs #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (mobs #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (mobs #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (mobs #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (mobs #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (mobs #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (mobs #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (mobs #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (mobs #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (mobs #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (mobs #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (mobs #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (mobs #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (mobs #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (mobs #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (mobs #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (mobs #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (mobs #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (mobs #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (mobs #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (mobs #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (mobs #63)
    xor     r11d, r11d ; clear v1 slot 63
