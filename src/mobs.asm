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
    maxss xmm0, xmm1
    comiss xmm0, [rel c_7_5]
    jae   .calm
.hunt:
    mov   byte [rbx+ENTITY.ai_state], AI_CHASE
    mov   rcx, rbx
    movss xmm1, [rsi+PLAYER.x]
    movss xmm2, [rsi+PLAYER.z]
    movss xmm3, [rel c_0_16]
    call  mob_steer
    mov   eax, [rbx+ENTITY.yaw]
    mov   [rbx+ENTITY.head_yaw], eax
    mov   [rbx+E_AUX], eax
    movaps xmm10, xmm9
    sqrtss xmm10, xmm10
    movaps xmm0, xmm7
    subss xmm0, [rel c_0_08]            ; (py + 1.62) - (y + 1.7)
    movaps xmm1, xmm10
    call  math_atan2
    mulss xmm0, [rel c_r2d]
    minss xmm0, [rel c_45]
    maxss xmm0, [rel c_m45]
    movss [rbx+ENTITY.pitch], xmm0
    comiss xmm9, [rel c_1_44]           ; 1.2^2
    jae   .done
    movaps xmm0, xmm7
    andps xmm0, [rel c_abs]
    comiss xmm0, [rel c_1_5]
    jae   .done
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

PROC mobs_spawn_tick, 32
    inc   dword [rel ms_counter]
    mov   eax, [rel ms_counter]
    xor   edx, edx
    mov   ecx, 20
    div   ecx
    test  edx, edx
    jnz   .done
    cmp   dword [rel g_world_active], 0
    je    .done
    ; count, and cull far ones
    xor   r12d, r12d                    ; passive
    xor   r13d, r13d                    ; hostile
    xor   r14d, r14d                    ; glowbugs
    lea   rsi, [rel g_entities]
    mov   edi, MAX_ENTITIES
    lea   r15, [rel g_player]
.c:
    movzx eax, byte [rsi+ENTITY.type]
    cmp   eax, ENT_BOAR
    jb    .cn
    cmp   eax, ENT_TYPES
    jae   .cn                           ; java players
    movss xmm0, [rsi+ENTITY.x]
    subss xmm0, [r15+PLAYER.x]
    mulss xmm0, xmm0
    movss xmm1, [rsi+ENTITY.y]
    subss xmm1, [r15+PLAYER.y]
    mulss xmm1, xmm1
    addss xmm0, xmm1
    movss xmm1, [rsi+ENTITY.z]
    subss xmm1, [r15+PLAYER.z]
    mulss xmm1, xmm1
    addss xmm0, xmm1
    cmp   eax, ENT_WOOLLY
    ja    .roamer
    ; animals never get culled at random. persistent ones stay forever, wild
    ; herds go past 96 blocks so the pool doesn't fill up while travelling
    comiss xmm0, [rel c_96sq]
    jb    .count
    test  byte [rsi+ENTITY.flags], EF_PERSIST
    jnz   .cn
    jmp   .kill
.roamer:
    ; past 96 gone, past 40 a 1/40 chance each second
    test  byte [rsi+ENTITY.flags], EF_PERSIST
    jnz   .count
    comiss xmm0, [rel c_96sq]
    jae   .kill
    comiss xmm0, [rel c_40sq]
    jb    .count
    mov   ecx, 40
    call  rng_int
    test  eax, eax
    jz    .kill
.count:
    movzx eax, byte [rsi+ENTITY.type]
    cmp   eax, ENT_SHAMBLER
    jb    .cp
    je    .ch
    inc   r14d
    jmp   .cn
.ch:
    inc   r13d
    jmp   .cn
.cp:
    inc   r12d
    jmp   .cn
.kill:
    mov   rcx, rsi
    call  entity_remove
.cn:
    add   rsi, ENTITY_size
    dec   edi
    jnz   .c
    cmp   dword [r15+PLAYER.dead], 0
    jne   .done
    cmp   dword [rel g_time_of_day], 12000
    jae   .hostile
    cmp   r12d, CAP_PASSIVE
    jae   .hostile
    ; far persistent animals don't count toward the cap, so the pool could
    ; still fill up with them. items and tnt need those slots
    cmp   dword [rel g_entity_count], HERD_POOL_LIMIT
    jae   .hostile
    mov   ecx, 4
    call  rng_int
    test  eax, eax
    jnz   .hostile
    mov   ecx, CAP_PASSIVE
    sub   ecx, r12d
    call  try_spawn_passive
.hostile:
    mov   edi, 3                        ; tries
.ha:
    cmp   r13d, CAP_HOSTILE
    jae   .bugs
    call  try_spawn_hostile
    add   r13d, eax
    dec   edi
    jnz   .ha
.bugs:
    mov   eax, [rel g_time_of_day]
    cmp   eax, 13000
    jb    .done
    cmp   eax, 23000
    jae   .done
    cmp   r14d, CAP_GLOWBUG
    jae   .done
    mov   ecx, CAP_GLOWBUG
    sub   ecx, r14d
    call  try_spawn_bugs
.done:
ENDP

; random column xmm0..xmm1 blocks from the player -> sp_x, sp_z
LPROCX ring_pos, 16
    movaps xmm6, xmm0
    movaps xmm7, xmm1
    subss xmm7, xmm6
    call  rng_float
    mulss xmm0, [rel c_tau]
    call  math_sincos
    movaps xmm8, xmm0
    movaps xmm9, xmm1
    call  rng_float
    mulss xmm0, xmm7
    addss xmm0, xmm6
    lea   rax, [rel g_player]
    movaps xmm1, xmm9
    mulss xmm1, xmm0
    addss xmm1, [rax+PLAYER.x]
    FLOORI ecx, xmm1
    mov   [rel sp_x], ecx
    mulss xmm0, xmm8
    addss xmm0, [rax+PLAYER.z]
    FLOORI ecx, xmm0
    mov   [rel sp_z], ecx
ENDPX

; herd of 2-4, ecx = budget
LPROC try_spawn_passive, 32
    mov   r15d, ecx
    movss xmm0, [rel c_24]
    movss xmm1, [rel c_64]
    call  ring_pos
    mov   ecx, [rel sp_x]
    mov   edx, [rel sp_z]
    call  world_is_loaded
    test  eax, eax
    jz    .done
    mov   ecx, [rel sp_x]
    mov   edx, [rel sp_z]
    call  grass_top
    mov   r13d, eax
    test  eax, eax
    js    .done
    cmp   eax, CHUNK_H-4
    jg    .done
    mov   ecx, 2
    call  rng_int
    lea   r12d, [rax+ENT_BOAR]          ; boar or woolly
    mov   ecx, 3
    call  rng_int
    lea   r14d, [rax+2]
    cmp   r14d, r15d
    cmovg r14d, r15d
    mov   edi, 10
.g:
    mov   ecx, 7
    call  rng_int
    lea   esi, [rax-3]
    add   esi, [rel sp_x]
    mov   ecx, 7
    call  rng_int
    sub   eax, 3
    add   eax, [rel sp_z]
    mov   LOC(0), eax                   ; oz
    mov   ecx, esi
    mov   edx, eax
    call  world_is_loaded
    test  eax, eax
    jz    .gn
    mov   ecx, esi
    mov   edx, LOC(0)
    call  grass_top
    test  eax, eax
    js    .gn
    mov   LOC(4), eax                   ; oy
    sub   eax, r13d
    cmp   eax, -3
    jl    .gn
    cmp   eax, 3
    jg    .gn
    cvtsi2ss xmm1, esi
    addss xmm1, [rel c_half]
    mov   eax, LOC(4)
    inc   eax
    cvtsi2ss xmm2, eax
    cvtsi2ss xmm3, dword LOC(0)
    addss xmm3, [rel c_half]
    mov   ecx, r12d
    call  entity_spawn
    test  rax, rax
    jz    .done
    and   byte [rax+ENTITY.flags], (~EF_PERSIST) & 0xFF   ; wild, may despawn
    dec   r14d
    jz    .done
.gn:
    dec   edi
    jnz   .g
.done:
ENDP

; -> y of the surface grass, or -1. the top block is often a plant sitting
; on the grass so look through one of those
LPROC grass_top, 0
    mov   r12d, ecx
    mov   r13d, edx
    call  world_height_at
    mov   r14d, eax
    cmp   eax, 1
    jl    .no
    mov   ecx, r12d
    mov   edx, r14d
    mov   r8d, r13d
    call  world_get_block
    cmp   eax, B_GRASS
    je    .yes
    lea   rcx, [rel blk_flags]
    movzx eax, word [rcx+rax*2]
    test  eax, BF_SOLID|BF_LIQUID
    jnz   .no
    test  eax, BF_PLANT|BF_REPLACEABLE
    jz    .no
    dec   r14d
    mov   ecx, r12d
    mov   edx, r14d
    mov   r8d, r13d
    call  world_get_block
    cmp   eax, B_GRASS
    jne   .no
.yes:
    mov   eax, r14d
    jmp   .done
.no:
    mov   eax, -1
.done:
ENDP

; -> eax 1 if spawned. night: surface or anywhere dark, day: sky < 8 only.
; always needs block light 0
LPROC try_spawn_hostile, 32
    xor   r15d, r15d
    ; 20..44, mostly inside the 40 block hunt range, so a fresh shambler
    ; comes for you instead of milling about at the edge of the ring
    movss xmm0, [rel c_20]
    movss xmm1, [rel c_44]
    call  ring_pos
    mov   ecx, [rel sp_x]
    mov   edx, [rel sp_z]
    call  world_is_loaded
    test  eax, eax
    jz    .done
    mov   ecx, [rel sp_x]
    mov   edx, [rel sp_z]
    call  world_height_at
    mov   r12d, eax                     ; surface y
    cmp   eax, 2
    jl    .done
    cmp   eax, CHUNK_H-3
    jg    .done
    xor   r14d, r14d                    ; night?
    mov   eax, [rel g_time_of_day]
    cmp   eax, 13000
    jb    .day
    cmp   eax, 23000
    jae   .day
    mov   r14d, 1
.day:
    test  r14d, r14d
    jz    .cave
    mov   ecx, 2
    call  rng_int
    test  eax, eax
    jnz   .cave
    mov   r13d, r12d
    jmp   .search
.cave:
    mov   ecx, r12d
    call  rng_int
    lea   r13d, [rax+1]
.search:
    mov   edi, 12
    lea   rsi, [rel blk_flags]
.s:
    mov   ecx, [rel sp_x]
    mov   edx, r13d
    mov   r8d, [rel sp_z]
    call  world_get_block
    movzx eax, word [rsi+rax*2]
    mov   ecx, eax
    and   ecx, BF_SOLID|BF_OPAQUE
    cmp   ecx, BF_SOLID|BF_OPAQUE
    jne   .up
    test  eax, BF_LEAVES
    jnz   .up
    mov   ecx, [rel sp_x]
    lea   edx, [r13+1]
    mov   r8d, [rel sp_z]
    call  world_get_block
    test  word [rsi+rax*2], BF_SOLID|BF_LIQUID
    jnz   .up
    mov   ecx, [rel sp_x]
    lea   edx, [r13+2]
    mov   r8d, [rel sp_z]
    call  world_get_block
    test  word [rsi+rax*2], BF_SOLID|BF_LIQUID
    jz    .found
.up:
    inc   r13d
    cmp   r13d, r12d
    jg    .done
    dec   edi
    jnz   .s
    jmp   .done
.found:
    mov   ecx, [rel sp_x]
    lea   edx, [r13+1]
    mov   r8d, [rel sp_z]
    call  world_get_light
    test  eax, 15
    jnz   .done                         ; torch light = safe
    test  r14d, r14d
    jnz   .spawn
    shr   eax, 4
    cmp   eax, 8
    jae   .done
.spawn:
    cvtsi2ss xmm1, dword [rel sp_x]
    addss xmm1, [rel c_half]
    lea   eax, [r13+1]
    cvtsi2ss xmm2, eax
    cvtsi2ss xmm3, dword [rel sp_z]
    addss xmm3, [rel c_half]
    mov   ecx, ENT_SHAMBLER
    call  entity_spawn
    test  rax, rax
    setnz r15b
.done:
    mov   eax, r15d
ENDP

; ecx = budget
LPROC try_spawn_bugs, 32
    mov   r15d, ecx
    movss xmm0, [rel c_8]
    movss xmm1, [rel c_40]
    call  ring_pos
    mov   ecx, [rel sp_x]
    mov   edx, [rel sp_z]
    call  world_is_loaded
    test  eax, eax
    jz    .done
    mov   ecx, [rel sp_x]
    mov   edx, [rel sp_z]
    call  world_height_at
    mov   r13d, eax
    cmp   eax, 1
    jl    .done
    cmp   eax, CHUNK_H-6
    jg    .done
    mov   ecx, [rel sp_x]
    mov   edx, r13d
    mov   r8d, [rel sp_z]
    call  world_get_block
    cmp   eax, B_GRASS
    je    .ok
    cmp   eax, B_TALL_GRASS
    je    .ok
    cmp   eax, B_FLOWER_RED
    je    .ok
    cmp   eax, B_FLOWER_YELLOW
    jne   .done
.ok:
    mov   ecx, 3
    call  rng_int
    lea   r14d, [rax+1]
    cmp   r14d, r15d
    cmovg r14d, r15d
.l:
    call  rng_float_signed
    mulss xmm0, [rel c_2_5]
    cvtsi2ss xmm1, dword [rel sp_x]
    addss xmm0, xmm1
    addss xmm0, [rel c_half]
    movss LOC(0), xmm0
    call  rng_float_signed
    mulss xmm0, [rel c_2_5]
    cvtsi2ss xmm1, dword [rel sp_z]
    addss xmm0, xmm1
    addss xmm0, [rel c_half]
    movss LOC(4), xmm0
    call  rng_float
    mulss xmm0, [rel c_1_5]
    cvtsi2ss xmm1, r13d
    addss xmm0, xmm1
    addss xmm0, [rel c_2_5]
    movaps xmm2, xmm0
    movss xmm1, LOC(0)
    movss xmm3, LOC(4)
    mov   ecx, ENT_GLOWBUG
    call  entity_spawn
    test  rax, rax
    jz    .done
    dec   r14d
    jnz   .l
.done:
ENDP

; colour = mobs_col * part rgba (* mobs_wool for PF_WOOL)
PROCX mobs_draw_box, 32
    mov   rbx, rcx
    lea   rsi, [rel mobs_col]
    movzx eax, byte [rbx+PART_RGBA]
    cvtsi2ss xmm6, eax
    mulss xmm6, [rel c_inv255]
    mulss xmm6, [rsi]
    movzx eax, byte [rbx+PART_RGBA+1]
    cvtsi2ss xmm7, eax
    mulss xmm7, [rel c_inv255]
    mulss xmm7, [rsi+4]
    movzx eax, byte [rbx+PART_RGBA+2]
    cvtsi2ss xmm8, eax
    mulss xmm8, [rel c_inv255]
    mulss xmm8, [rsi+8]
    movzx eax, byte [rbx+PART_RGBA+3]
    cvtsi2ss xmm9, eax
    mulss xmm9, [rel c_inv255]
    mulss xmm9, [rsi+12]
    test  byte [rbx+PART_FLAGS], PF_WOOL
    jz    .nowool
    cmp   dword [rel mobs_overlay], 0
    jne   .nowool                       ; the hurt overlay is plain red
    lea   rax, [rel mobs_wool]
    mulss xmm6, [rax]
    mulss xmm7, [rax+4]
    mulss xmm8, [rax+8]
.nowool:
    movss xmm10, [rel mobs_uvscale]
    mov   ecx, GL_QUADS
    call  glBegin
    xor   r12d, r12d
.face:
    movzx eax, byte [rbx+PART_TILES+r12]
    mov   ecx, eax
    and   ecx, 15
    cvtsi2ss xmm11, ecx
    mulss xmm11, [rel c_1_16]
    shr   eax, 4
    cvtsi2ss xmm12, eax
    mulss xmm12, [rel c_1_16]
    movss xmm13, [rel c_one]            ; spans, in tiles
    movss xmm14, [rel c_one]
    test  byte [rbx+PART_FLAGS], PF_FULL
    jnz   .spans
    cmp   r12d, FACE_NZ
    jne   .prop
    test  byte [rbx+PART_FLAGS], PF_FRONT
    jnz   .spans
.prop:
    ; uv proportional to the box so skins don't stretch, max 1 tile
    lea   rax, [rel face_axes]
    movzx ecx, byte [rax+r12*2]
    movzx edx, byte [rax+r12*2+1]
    movss xmm13, [rbx+PART_X1+rcx*4]
    subss xmm13, [rbx+PART_X0+rcx*4]
    mulss xmm13, xmm10
    minss xmm13, [rel c_one]
    movss xmm14, [rbx+PART_X1+rdx*4]
    subss xmm14, [rbx+PART_X0+rdx*4]
    mulss xmm14, xmm10
    minss xmm14, [rel c_one]
    cmp   r12d, FACE_PY
    je    .spans
    cmp   r12d, FACE_NY
    je    .spans
    test  byte [rbx+PART_FLAGS], PF_VFULL
    jz    .ucentre
    movss xmm14, [rel c_one]
.ucentre:
    cmp   r12d, FACE_PZ
    jb    .spans                        ; PX/NX keep the left columns
    test  byte [rbx+PART_FLAGS], PF_UCENTRE
    jz    .spans
    movss xmm0, [rel c_one]
    subss xmm0, xmm13
    mulss xmm0, [rel c_half]
    mulss xmm0, [rel c_1_16]
    addss xmm11, xmm0                   ; u0 += (1 - span)/2 tile
.spans:
    mulss xmm13, [rel c_1_16]
    mulss xmm14, [rel c_1_16]
    addss xmm13, xmm11
    subss xmm13, [rel c_uv_eps]
    addss xmm14, xmm12
    subss xmm14, [rel c_uv_eps]
    addss xmm11, [rel c_uv_eps]
    addss xmm12, [rel c_uv_eps]
    movss LOC(0), xmm11
    movss LOC(4), xmm12
    movss LOC(8), xmm13
    movss LOC(12), xmm14
    lea   rax, [rel face_shade]
    movss xmm15, [rax+r12*4]
    movaps xmm0, xmm6
    mulss xmm0, xmm15
    movaps xmm1, xmm7
    mulss xmm1, xmm15
    movaps xmm2, xmm8
    mulss xmm2, xmm15
    movaps xmm3, xmm9
    call  glColor4f
    xor   r13d, r13d
.vert:
    lea   rax, [rel uv_sel]
    movzx ecx, byte [rax+r13*2]
    movzx edx, byte [rax+r13*2+1]
    lea   rax, LOC(0)
    movss xmm0, [rax+rcx]
    movss xmm1, [rax+rdx]
    call  glTexCoord2f
    lea   rax, [rel face_corners]
    lea   ecx, [r12*4+r13]
    movzx r14d, byte [rax+rcx]          ; 1 = x1, 2 = y1, 4 = z1
    mov   eax, r14d
    and   eax, 1
    imul  eax, eax, 12
    movss xmm0, [rbx+rax]
    mov   eax, r14d
    shr   eax, 1
    and   eax, 1
    imul  eax, eax, 12
    movss xmm1, [rbx+rax+4]
    mov   eax, r14d
    shr   eax, 2
    and   eax, 1
    imul  eax, eax, 12
    movss xmm2, [rbx+rax+8]
    call  glVertex3f
    inc   r13d
    cmp   r13d, 4
    jb    .vert
    inc   r12d
    cmp   r12d, 6
    jb    .face
    call  glEnd
ENDPX

; edx parts around pivot xmm2/xmm3/ARG5, ARG6 pitch, ARG7 yaw (deg). T * Ry * Rx
LPROCX part_rot, 16
    mov   rsi, rcx
    mov   edi, edx
    movaps xmm6, xmm2
    movaps xmm7, xmm3
    movss xmm8, ARG5
    movss xmm9, ARG6
    movss xmm10, ARG7
    call  glPushMatrix
    movaps xmm0, xmm6
    movaps xmm1, xmm7
    movaps xmm2, xmm8
    call  glTranslatef
    xorps xmm0, xmm0
    ucomiss xmm10, xmm0
    je    .noyaw
    movaps xmm0, xmm10
    xorps xmm1, xmm1
    movss xmm2, [rel c_one]
    xorps xmm3, xmm3
    call  glRotatef
.noyaw:
    xorps xmm0, xmm0
    ucomiss xmm9, xmm0
    je    .nopitch
    movaps xmm0, xmm9
    movss xmm1, [rel c_one]
    xorps xmm2, xmm2
    xorps xmm3, xmm3
    call  glRotatef
.nopitch:
    test  edi, edi
    jz    .pop
.l:
    mov   rcx, rsi
    call  mobs_draw_box
    add   rsi, PART_SIZE
    dec   edi
    jnz   .l
.pop:
    call  glPopMatrix
ENDPX

; 32 px tall, feet at the origin, facing -z. shamblers + 3rd person player
PROCX mobs_draw_humanoid, 32
    mov   rsi, rcx
    ; parts are shared, patch this figure's tiles in
    lea   rax, [rel hm_head]
    mov   cl, [rsi+HP_HEAD_SIDE]
    mov   [rax+PART_TILES+FACE_PX], cl
    mov   [rax+PART_TILES+FACE_NX], cl
    mov   [rax+PART_TILES+FACE_NY], cl
    mov   cl, [rsi+HP_HEAD_TOP]
    mov   [rax+PART_TILES+FACE_PY], cl
    mov   cl, [rsi+HP_HEAD_BACK]
    mov   [rax+PART_TILES+FACE_PZ], cl
    mov   cl, [rsi+HP_HEAD_FRONT]
    mov   [rax+PART_TILES+FACE_NZ], cl
    movzx ecx, byte [rsi+HP_BODY]
    lea   rdx, [rel hm_body]
    call  set_tiles6
    movzx ecx, byte [rsi+HP_ARM]
    lea   rdx, [rel hm_arm]
    call  set_tiles6
    movzx ecx, byte [rsi+HP_SLEEVE]
    lea   rdx, [rel hm_sleeve]
    call  set_tiles6
    movzx ecx, byte [rsi+HP_LEG]
    lea   rdx, [rel hm_leg]
    call  set_tiles6
    mov   r12d, 2                       ; arm + sleeve
    cmp   byte [rsi+HP_SLEEVE], 0xFF
    jne   .sl
    mov   r12d, 1
.sl:
    movss xmm6, [rsi+HP_SWING]
    movss xmm7, [rsi+HP_HEAD_YAW]
    movss xmm8, [rsi+HP_HEAD_PITCH]
    ; attack: sin(t*pi) * 80 deg on the right arm
    movss xmm0, [rsi+HP_ATTACK]
    mulss xmm0, [rel c_pi]
    call  math_sin
    mulss xmm0, [rel c_80]
    movss xmm9, xmm0
    mov   dword [rel mobs_uvscale], __float32__(0.0625)   ; 1 px = 1 texel
    call  glPushMatrix
    movss xmm0, [rsi+HP_SCALE]
    movaps xmm1, xmm0
    movaps xmm2, xmm0
    call  glScalef
    lea   rcx, [rel hm_body]
    call  mobs_draw_box
    lea   rcx, [rel hm_head]
    mov   edx, 1
    xorps xmm2, xmm2
    movss xmm3, [rel c_24]
    mov   dword [rsp+32], 0
    movss [rsp+40], xmm8
    movaps xmm0, xmm7
    xorps xmm0, [rel c_sign]
    movss [rsp+48], xmm0
    call  part_rot
    lea   rcx, [rel hm_leg]
    mov   edx, 1
    movss xmm2, [rel c_2]
    movss xmm3, [rel c_12]
    mov   dword [rsp+32], 0
    movss [rsp+40], xmm6
    mov   dword [rsp+48], 0
    call  part_rot
    lea   rcx, [rel hm_leg]
    mov   edx, 1
    movss xmm2, [rel c_m2]
    movss xmm3, [rel c_12]
    mov   dword [rsp+32], 0
    movaps xmm0, xmm6
    xorps xmm0, [rel c_sign]
    movss [rsp+40], xmm0
    mov   dword [rsp+48], 0
    call  part_rot
    ; shambler arms stick out forward
    cmp   dword [rsi+HP_ARMS_FWD], 0
    je    .natural
    movss xmm10, [rel c_90]
    movaps xmm0, xmm6
    mulss xmm0, [rel c_0_15]
    addss xmm10, xmm0
    movss xmm11, [rel c_90]
    subss xmm11, xmm0
    addss xmm10, xmm9
    addss xmm11, xmm9
    jmp   .arms
.natural:
    movaps xmm10, xmm6
    mulss xmm10, [rel c_0_8]
    xorps xmm10, [rel c_sign]
    movaps xmm11, xmm6
    mulss xmm11, [rel c_0_8]
    addss xmm10, xmm9
.arms:
    lea   rcx, [rel hm_arm]
    mov   edx, r12d
    movss xmm2, [rel c_6]
    movss xmm3, [rel c_22]
    mov   dword [rsp+32], 0
    movss [rsp+40], xmm10
    mov   dword [rsp+48], 0
    call  part_rot
    cmp   dword [rsi+HP_ITEM], 0
    je    .noitem
    cmp   dword [rel mobs_overlay], 0
    jne   .noitem                       ; not in the hurt pass
    mov   rcx, rsi
    movaps xmm1, xmm10
    call  held_item
.noitem:
    lea   rcx, [rel hm_arm]
    mov   edx, r12d
    movss xmm2, [rel c_m6]
    movss xmm3, [rel c_22]
    mov   dword [rsp+32], 0
    movss [rsp+40], xmm11
    mov   dword [rsp+48], 0
    call  part_rot
    call  glPopMatrix
    mov   dword [rel mobs_uvscale], __float32__(1.0)
ENDPX

set_tiles6:
    mov   [rdx+PART_TILES+0], cl
    mov   [rdx+PART_TILES+1], cl
    mov   [rdx+PART_TILES+2], cl
    mov   [rdx+PART_TILES+3], cl
    mov   [rdx+PART_TILES+4], cl
    mov   [rdx+PART_TILES+5], cl
    ret

PROCX mobs_render, 64
    mov   rbx, rcx
    mov   rcx, rbx
    lea   rdx, LOC(0)
    call  entity_lerp_pos_light
    cmp   byte [rbx+ENTITY.type], ENT_GLOWBUG
    jne   .body
    mov   rcx, rbx
    lea   rdx, LOC(0)
    call  glowbug_render
    jmp   .done
.body:
    lea   rax, [rel mobs_col]
    movss xmm0, LOC(12)
    movss [rax], xmm0
    movss [rax+4], xmm0
    movss [rax+8], xmm0
    mov   dword [rax+12], __float32__(1.0)
    mov   dword [rel mobs_uvscale], __float32__(1.0)
    movss xmm6, [rel g_partial_tick]
    xorps xmm0, xmm0
    maxss xmm6, xmm0
    minss xmm6, [rel c_one]
    movss xmm0, [rbx+ENTITY.yaw]
    subss xmm0, [rbx+E_PREV_YAW]
    WRAP180 xmm0
    mulss xmm0, xmm6
    addss xmm0, [rbx+E_PREV_YAW]
    movss xmm7, xmm0
    ; cos(phase * 0.6662) * 1.4 * amount
    movss xmm1, [rel c_one]
    subss xmm1, xmm6
    mulss xmm1, [rbx+ENTITY.anim_speed]
    movss xmm0, [rbx+ENTITY.anim]
    subss xmm0, xmm1
    mulss xmm0, [rel c_0_6662]
    call  math_cos
    mulss xmm0, [rel c_1_4]
    mulss xmm0, [rbx+ENTITY.anim_speed]
    mulss xmm0, [rel c_r2d]
    movss [rel m_swing], xmm0
    movss xmm0, [rbx+ENTITY.head_yaw]
    subss xmm0, [rbx+ENTITY.yaw]
    WRAP180 xmm0
    minss xmm0, [rel c_75]
    maxss xmm0, [rel c_m75]
    movss [rel m_hyaw], xmm0
    mov   eax, [rbx+ENTITY.pitch]
    mov   [rel m_hpitch], eax
    call  glPushMatrix
    movss xmm0, LOC(0)
    movss xmm1, LOC(4)
    movss xmm2, LOC(8)
    call  glTranslatef
    movaps xmm0, xmm7
    xorps xmm0, [rel c_sign]
    xorps xmm1, xmm1
    movss xmm2, [rel c_one]
    xorps xmm3, xmm3
    call  glRotatef
    test  byte [rbx+ENTITY.flags], EF_DEAD
    jz    .upright
    ; dying: roll onto the side, 90 * min(1, sqrt(1.6t))
    cvtsi2ss xmm0, dword [rbx+ENTITY.death_time]
    addss xmm0, xmm6
    subss xmm0, [rel c_one]
    mulss xmm0, [rel c_0_08]            ; 1.6/20
    xorps xmm1, xmm1
    maxss xmm0, xmm1
    sqrtss xmm0, xmm0
    minss xmm0, [rel c_one]
    mulss xmm0, [rel c_90]
    xorps xmm1, xmm1
    xorps xmm2, xmm2
    movss xmm3, [rel c_one]
    call  glRotatef
.upright:
    xor   r12d, r12d                    ; pass 0 textured, 1 red overlay
.model:
    mov   rcx, rbx
    movzx eax, byte [rbx+ENTITY.type]
    cmp   eax, ENT_BOAR
    jne   .m1
    call  boar_model
    jmp   .drawn
.m1:
    cmp   eax, ENT_WOOLLY
    jne   .m2
    call  woolly_model
    jmp   .drawn
.m2:
    cmp   eax, ENT_SHAMBLER
    jne   .m3
    call  shambler_model
    jmp   .drawn
.m3:
    cmp   eax, ENT_REMOTE
    jne   .pop
    call  remote_model
.drawn:
    test  r12d, r12d
    jnz   .tinted
    ; hurt: draw it again in translucent red. a colour multiply can't make a
    ; green or black texture look red
    cmp   dword [rbx+ENTITY.hurt_time], 0
    jg    .hurt
    test  byte [rbx+ENTITY.flags], EF_DEAD
    jz    .pop
.hurt:
    movss xmm0, LOC(12)
    xorps xmm1, xmm1
    xorps xmm2, xmm2
    movss xmm3, [rel c_hurt_alpha]
    call  mobs_tint_begin
    mov   r12d, 1
    jmp   .model
.tinted:
    call  mobs_tint_end
.pop:
    call  glPopMatrix
    cmp   dword [rbx+ENTITY.fire], 0
    jle   .done
    mov   rcx, rbx ; v1: mobs scratch #0
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mobs:0)
    lea   rdx, LOC(0) ; v1: mobs scratch #1
    call  fire_render ; v1: mobs scratch #2
    ; TODO: verify 16-byte rsp alignment before inner call (mobs:2)
.done: ; v1: mobs scratch #3
ENDPX ; v1: mobs scratch #4
    ; TODO: hoist invariant pointer load out of .loop (mobs:4)

; draw the model again between begin/end and it lands as a flat tint on the
; first pass. no depth writes, LEQUAL lets exactly the visible surfaces
; through. face shading still applies so it keeps its shape
PROC mobs_tint_begin, 16 ; v1: mobs scratch #9
    lea   rax, [rel mobs_col] ; v1: mobs scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (mobs:10)
    movss [rax], xmm0 ; v1: mobs scratch #11
    movss [rax+4], xmm1 ; v1: mobs scratch #12
    ; note: rcx = state ptr, rdx = index, r8d = flags (mobs:12)
    movss [rax+8], xmm2 ; v1: mobs scratch #13
    movss [rax+12], xmm3 ; v1: mobs scratch #14
    ; TODO: clamp index before table lookup on malformed input (mobs:14)
    mov   dword [rel mobs_overlay], 1 ; v1: mobs scratch #15
    mov   ecx, GL_TEXTURE_2D ; v1: mobs scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mobs:16)
    call  glDisable ; v1: mobs scratch #17
    mov   ecx, GL_BLEND ; v1: mobs scratch #18
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mobs:18)
    call  glEnable ; v1: mobs scratch #19
    mov   ecx, GL_SRC_ALPHA ; v1: mobs scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mobs:20)
    mov   edx, GL_ONE_MINUS_SRC_ALPHA ; v1: mobs scratch #21
    call  glBlendFunc ; v1: mobs scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (mobs:22)
    xor   ecx, ecx ; v1: mobs scratch #23
    call  glDepthMask ; v1: mobs scratch #24
    ; TODO: hoist invariant pointer load out of .loop (mobs:24)
ENDP ; v1: mobs scratch #25

PROC mobs_tint_end, 16 ; v1: mobs scratch #27
    mov   dword [rel mobs_overlay], 0 ; v1: mobs scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (mobs:28)
    mov   ecx, 1 ; v1: mobs scratch #29
    call  glDepthMask ; v1: mobs scratch #30
    ; note: rcx = state ptr, rdx = index, r8d = flags (mobs:30)
    mov   ecx, GL_BLEND ; v1: mobs scratch #31
    call  glDisable ; v1: mobs scratch #32
    ; TODO: clamp index before table lookup on malformed input (mobs:32)
    mov   ecx, GL_TEXTURE_2D ; v1: mobs scratch #33
    call  glEnable ; v1: mobs scratch #34
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mobs:34)
ENDP ; v1: mobs scratch #35

; 3 flickering flame billboards, pulled toward the cam past the body so it
; can't hide them. the odd flame particle alone was unreadable at a distance
LPROCX fire_render, 32 ; v1: mobs scratch #39
    mov   rbx, rcx ; v1: mobs scratch #40
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mobs:40)
    mov   rsi, rdx ; v1: mobs scratch #41
    movss xmm11, [rbx+ENTITY.hw] ; v1: mobs scratch #42
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mobs:42)
    mulss xmm11, [rel c_1_6] ; v1: mobs scratch #43
    addss xmm11, [rel c_0_12] ; v1: mobs scratch #44
    ; TODO: verify 16-byte rsp alignment before inner call (mobs:44)
    movss xmm0, [rbx+ENTITY.h] ; v1: mobs scratch #45
    mulss xmm0, [rel c_0_4] ; v1: mobs scratch #46
    ; TODO: hoist invariant pointer load out of .loop (mobs:46)
    addss xmm0, [rel c_0_1] ; v1: mobs scratch #47
    minss xmm11, xmm0 ; v1: mobs scratch #48
    ; temp: spill r12/r13 across helper call until reg alloc pass (mobs:48)
    ; k = (1.5hw + 0.25) / |centre|, cam is at the origin
    movss xmm6, [rsi] ; v1: mobs scratch #50
    ; note: rcx = state ptr, rdx = index, r8d = flags (mobs:50)
    movss xmm7, [rbx+ENTITY.h] ; v1: mobs scratch #51
    mulss xmm7, [rel c_half] ; v1: mobs scratch #52
    ; TODO: clamp index before table lookup on malformed input (mobs:52)
    addss xmm7, [rsi+4] ; v1: mobs scratch #53
    movss xmm8, [rsi+8] ; v1: mobs scratch #54
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mobs:54)
    movaps xmm0, xmm6
    mulss xmm0, xmm0
    movaps xmm1, xmm7
    mulss xmm1, xmm1
    addss xmm0, xmm1
    movaps xmm1, xmm8
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    xorps xmm12, xmm12
    comiss xmm0, [rel c_half]
    jb    .nopull                       ; cam inside the body
    movss xmm12, [rbx+ENTITY.hw]
    mulss xmm12, [rel c_1_5]
    addss xmm12, [rel c_0_25]           ; clears a boar's snout
    divss xmm12, xmm0
    minss xmm12, [rel c_half]
.nopull:
    movss xmm0, [rel c_one]
    subss xmm0, xmm12
    mulss xmm6, xmm0
    mulss xmm8, xmm0
    mulss xmm7, xmm12
    movss xmm9, [rsi+4]
    subss xmm9, xmm7
    cvtsi2ss xmm10, dword [rbx+ENTITY.age]
    addss xmm10, [rel g_partial_tick]
    mov   ecx, GL_CULL_FACE
    call  glDisable
    mov   ecx, GL_BLEND
    call  glEnable
    mov   ecx, GL_SRC_ALPHA
    mov   edx, GL_ONE
    call  glBlendFunc
    xor   ecx, ecx
    call  glDepthMask
    xor   r12d, r12d
.layer:
    ; size and sway on two out of phase sines
    cvtsi2ss xmm13, r12d
    movaps xmm0, xmm13
    mulss xmm0, [rel c_2_1]
    movaps xmm1, xmm10
    mulss xmm1, [rel c_0_7]
    addss xmm0, xmm1
    call  math_sin
    mulss xmm0, [rel c_0_12]
    addss xmm0, [rel c_0_9]
    mulss xmm0, xmm11
    movaps xmm14, xmm0
    movaps xmm0, xmm13
    mulss xmm0, [rel c_1_7]
    movaps xmm1, xmm10
    mulss xmm1, [rel c_1_1]
    addss xmm0, xmm1
    call  math_sin
    mulss xmm0, xmm11
    mulss xmm0, [rel c_0_15]
    movaps xmm15, xmm0
    movss xmm0, [rel c_one]
    movss xmm1, [rel c_0_75]
    movss xmm2, [rel c_0_45]
    movss xmm3, [rel c_0_8]
    call  glColor4f
    ; at 0.2, 0.5, 0.8 of the height
    movaps xmm0, xmm13
    mulss xmm0, [rel c_0_3]
    addss xmm0, [rel c_0_2]
    mulss xmm0, [rbx+ENTITY.h]
    addss xmm0, xmm9
    movaps xmm3, xmm0
    lea   rax, [rel g_cam_right]
    movss xmm2, [rax]
    mulss xmm2, xmm15
    addss xmm2, xmm6
    movss xmm1, [rax+8]
    mulss xmm1, xmm15
    addss xmm1, xmm8
    movss [rsp+32], xmm1
    mov   ecx, T_PARTICLE_FLAME
    movaps xmm1, xmm14
    call  billboard
    inc   r12d
    cmp   r12d, 3
    jb    .layer
    mov   ecx, 1
    call  glDepthMask
    mov   ecx, GL_SRC_ALPHA
    mov   edx, GL_ONE_MINUS_SRC_ALPHA
    call  glBlendFunc
    mov   ecx, GL_BLEND
    call  glDisable
    mov   ecx, GL_CULL_FACE
    call  glEnable
    movss xmm0, [rel c_one]
    movaps xmm1, xmm0
    movaps xmm2, xmm0
    movaps xmm3, xmm0
    call  glColor4f
ENDPX
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
