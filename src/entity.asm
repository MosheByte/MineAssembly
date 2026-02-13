; dropped items, primed tnt, falling sand/gravel pool (MAX_ENTITIES = 512)
%define IMPL_ENTITY
%include "common.inc"

; PROC/PROCX without the global, so helpers don't clash at link time
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

global g_entities, g_entity_count
global entity_remove, entity_lerp_pos_light, entity_light_at
global entity_fuse_quiet

extern mobs_draw_box, mobs_draw_humanoid, mobs_col, mobs_uvscale
extern mobs_tint_begin, mobs_tint_end

; private state in ENTITY.pad. gets saved too - primed tnt used to just
; vanish on save/reload, level.dat v2 keeps the live entities now
%define E_PFLAGS    108     ; PHYS flags from the last step
%define E_PANIC     112     ; panic ticks, or aggro for shamblers
%define E_FALL      116     ; float
%define E_PHASE     120     ; random 0..2pi, bob/spin/wobble
%define E_AUX       124     ; walkers: look yaw, glowbug: home y
; mobs have no .item, so prev body yaw lives there
%define E_PREV_YAW  ENTITY.item

%define ITEM_COLLECT    1   ; ai_state, flying into the player
%define ITEM_LIFETIME   6000
%define PICKUP_DIST2    2.25

; param block for mobs_draw_humanoid, keep in sync with mobs.asm
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
%define HP_ITEM         32      ; 0 = empty hand
%define HP_LIGHT        36
%define HP_SIZE         40

; real floor, cvtt alone is wrong for negatives. sse4.1
%macro FLOORI 2
    roundss xmm5, %2, 1
    cvttss2si %1, xmm5
%endmacro

section .bss
alignb 64
g_entities:     resb ENTITY_size*MAX_ENTITIES
g_entity_count: resd 1
spawn_hint:     resd 1
p_anim:         resd 1          ; 3rd person limbs
p_anim_amt:     resd 1
entity_fuse_quiet: resb 1       ; explosion.asm sets this during big chains

section .text

PROC entity_init
    call entity_clear
ENDP

PROC entity_clear
    lea  rdi, [rel g_entities]
    xor  eax, eax
    mov  ecx, ENTITY_size*MAX_ENTITIES/8
    rep  stosq
    mov  dword [rel g_entity_count], 0
    mov  dword [rel spawn_hint], 0
ENDP

; clobbers nothing but flags, callers rely on that
LEAF entity_remove
    cmp  byte [rcx+ENTITY.type], 0
    je   .r
    mov  byte [rcx+ENTITY.type], 0
    dec  dword [rel g_entity_count]
.r: ret

PROC entity_spawn, 32
    mov   r12d, ecx
    movss LOC(0), xmm1
    movss LOC(4), xmm2
    movss LOC(8), xmm3
    xor   eax, eax
    cmp   r12d, ENT_ITEM
    jb    .done
    cmp   r12d, ENT_REMOTE
    ja    .done
    lea   rsi, [rel g_entities]
    mov   eax, [rel spawn_hint]
    mov   ecx, MAX_ENTITIES
.find:
    mov   edx, eax
    shl   edx, 7
    cmp   byte [rsi+rdx], 0
    je    .found
    inc   eax
    and   eax, MAX_ENTITIES-1
    dec   ecx
    jnz   .find
    xor   eax, eax
    jmp   .done
.found:
    lea   rbx, [rsi+rdx]
    inc   eax
    and   eax, MAX_ENTITIES-1
    mov   [rel spawn_hint], eax
    pxor  xmm0, xmm0
    movdqa [rbx+0], xmm0
    movdqa [rbx+16], xmm0
    movdqa [rbx+32], xmm0
    movdqa [rbx+48], xmm0
    movdqa [rbx+64], xmm0
    movdqa [rbx+80], xmm0
    movdqa [rbx+96], xmm0
    movdqa [rbx+112], xmm0
    mov   [rbx+ENTITY.type], r12b
    mov   eax, LOC(0)
    mov   [rbx+ENTITY.x], eax
    mov   [rbx+ENTITY.prev_x], eax
    mov   eax, LOC(4)
    mov   [rbx+ENTITY.y], eax
    mov   [rbx+ENTITY.prev_y], eax
    mov   eax, LOC(8)
    mov   [rbx+ENTITY.z], eax
    mov   [rbx+ENTITY.prev_z], eax
    lea   rax, [rel ent_hw_tbl]
    mov   ecx, [rax+r12*4]
    mov   [rbx+ENTITY.hw], ecx
    lea   rax, [rel ent_h_tbl]
    mov   ecx, [rax+r12*4]
    mov   [rbx+ENTITY.h], ecx
    lea   rax, [rel ent_hp_tbl]
    mov   ecx, [rax+r12*4]
    mov   [rbx+ENTITY.health], ecx
    inc   dword [rel g_entity_count]
    call  rng_float
    mulss xmm0, [rel c_tau]
    movss [rbx+E_PHASE], xmm0

    cmp   r12d, ENT_TNT
    je    .tnt
    cmp   r12d, ENT_BOAR
    jb    .ret
    call  rng_float
    mulss xmm0, [rel c_360]
    movss [rbx+ENTITY.yaw], xmm0
    movss [rbx+ENTITY.head_yaw], xmm0
    movss [rbx+E_PREV_YAW], xmm0
    movss [rbx+E_AUX], xmm0
    mov   ecx, 60
    call  rng_int
    mov   [rbx+ENTITY.timer], eax
    cmp   r12d, ENT_SHAMBLER
    jne   .not_sh
    or    byte [rbx+ENTITY.flags], EF_HOSTILE
    jmp   .ret
.not_sh:
    cmp   r12d, ENT_WOOLLY
    ja    .not_woolly
    ; animals persist so /spawn'd ones and pens stay put, the herd
    ; spawner clears it again for wild herds
    or    byte [rbx+ENTITY.flags], EF_PERSIST
    cmp   r12d, ENT_WOOLLY
    jne   .ret
    mov   ecx, 1000
    call  rng_int
    lea   rdx, [rel wool_weights]
.wl:
    cmp   eax, [rdx]
    jb    .wtake
    add   rdx, 8
    jmp   .wl
.wtake:
    mov   eax, [rdx+4]
    mov   [rbx+ENTITY.variant], al
    jmp   .ret
.not_woolly:
    cmp   r12d, ENT_GLOWBUG
    jne   .ret
    mov   eax, [rbx+ENTITY.x]
    mov   [rbx+ENTITY.target_x], eax
    mov   eax, [rbx+ENTITY.z]
    mov   [rbx+ENTITY.target_z], eax
    mov   eax, [rbx+ENTITY.y]
    mov   [rbx+E_AUX], eax
    jmp   .ret
.tnt:
    ; 4s fuse and a little hop
    mov   dword [rbx+ENTITY.timer], 80
    mov   dword [rbx+ENTITY.vy], __float32__(0.2)
    movss xmm0, [rbx+E_PHASE]
    call  math_sincos
    mulss xmm0, [rel c_0_02]
    mulss xmm1, [rel c_0_02]
    movss [rbx+ENTITY.vx], xmm0
    movss [rbx+ENTITY.vz], xmm1
    cmp   byte [rel entity_fuse_quiet], 0
    jne   .ret
    mov   ecx, SFX_FUSE
    movss xmm1, [rbx+ENTITY.x]
    movss xmm2, [rbx+ENTITY.y]
    movss xmm3, [rbx+ENTITY.z]
    call  sfx_play_at
.ret:
    mov   rax, rbx
.done:
ENDP

; returns the LAST piece spawned, callers copy tool damage into it
PROC entity_spawn_item, 32
    mov   r12d, ecx
    mov   r13d, edx
    movss LOC(0), xmm2
    movss LOC(4), xmm3
    mov   eax, ARG5
    mov   LOC(8), eax
    xor   r14d, r14d
    test  r12d, r12d
    jz    .done
    cmp   r12d, 255
    ja    .done
    test  r13d, r13d
    jle   .done
    lea   rax, [rel item_max_stack]
    movzx r15d, byte [rax+r12]
    test  r15d, r15d
    jnz   .loop
    mov   r15d, 64
.loop:
    mov   esi, r13d
    cmp   esi, r15d
    cmovg esi, r15d
    mov   ecx, ENT_ITEM
    movss xmm1, LOC(0)
    movss xmm2, LOC(4)
    movss xmm3, LOC(8)
    call  entity_spawn
    test  rax, rax
    jz    .done
    mov   r14, rax
    mov   [rax+ENTITY.item+STACK.id], r12b
    mov   [rax+ENTITY.item+STACK.count], sil
    mov   word [rax+ENTITY.item+STACK.damage], 0
    mov   dword [rax+ENTITY.timer], 10
    call  rng_float_signed
    mulss xmm0, [rel c_0_1]
    movss [r14+ENTITY.vx], xmm0
    mov   dword [r14+ENTITY.vy], __float32__(0.2)
    call  rng_float_signed
    mulss xmm0, [rel c_0_1]
    movss [r14+ENTITY.vz], xmm0
    sub   r13d, esi
    jg    .loop
.done:
    mov   rax, r14
ENDP

; softer toss than spawn_item
PROC entity_drop_block_item, 32
    test  r9d, r9d
    jz    .done
    mov   r12d, ecx
    mov   r13d, edx
    mov   r14d, r8d
    mov   r15d, r9d
    call  rng_float_signed
    mulss xmm0, [rel c_0_25]
    cvtsi2ss xmm1, r12d
    addss xmm1, [rel c_half]
    addss xmm1, xmm0
    movss LOC(0), xmm1
    call  rng_float_signed
    mulss xmm0, [rel c_0_25]
    cvtsi2ss xmm1, r14d
    addss xmm1, [rel c_half]
    addss xmm1, xmm0
    movss LOC(8), xmm1
    cvtsi2ss xmm1, r13d
    addss xmm1, [rel c_0_3]
    movss LOC(4), xmm1
    mov   ecx, r15d
    mov   edx, 1
    movss xmm2, LOC(0)
    movss xmm3, LOC(4)
    mov   eax, LOC(8)
    mov   [rsp+32], eax
    call  entity_spawn_item
    test  rax, rax
    jz    .done
    movss xmm0, [rax+ENTITY.vx]
    mulss xmm0, [rel c_half]
    movss [rax+ENTITY.vx], xmm0
    movss xmm0, [rax+ENTITY.vz]
    mulss xmm0, [rel c_half]
    movss [rax+ENTITY.vz], xmm0
    mov   dword [rax+ENTITY.vy], __float32__(0.12)
.done:
ENDP

; rcx e, xmm1 gravity, xmm2 drag, xmm3 ground friction -> eax 0 dry/1 water/2 lava
LPROC ent_physics, 64
    mov   rbx, rcx
    movss LOC(40), xmm1
    movss LOC(44), xmm2
    movss LOC(48), xmm3
    mov   eax, [rbx+ENTITY.x]
    mov   LOC(PHYS.x), eax
    mov   eax, [rbx+ENTITY.y]
    mov   LOC(PHYS.y), eax
    mov   eax, [rbx+ENTITY.z]
    mov   LOC(PHYS.z), eax
    mov   eax, [rbx+ENTITY.hw]
    mov   LOC(PHYS.hw), eax
    mov   eax, [rbx+ENTITY.h]
    mov   LOC(PHYS.h), eax
    xor   eax, eax
    mov   LOC(PHYS.dx), eax
    mov   LOC(PHYS.dy), eax
    mov   LOC(PHYS.dz), eax
    mov   LOC(PHYS.step), eax
    mov   LOC(PHYS.flags), eax
    lea   rcx, LOC(0)
    call  physics_in_liquid
    mov   r12d, eax
    and   byte [rbx+ENTITY.flags], (~(EF_IN_WATER|EF_IN_LAVA)) & 0xFF
    cmp   r12d, 1
    jne   .notwater
    or    byte [rbx+ENTITY.flags], EF_IN_WATER
    movss xmm0, LOC(40)
    mulss xmm0, [rel c_0_25]
    movss LOC(40), xmm0
    mov   dword LOC(44), __float32__(0.8)
    jmp   .grav
.notwater:
    cmp   r12d, 2
    jne   .grav
    or    byte [rbx+ENTITY.flags], EF_IN_LAVA
    movss xmm0, LOC(40)
    mulss xmm0, [rel c_0_25]
    movss LOC(40), xmm0
    mov   dword LOC(44), __float32__(0.5)
.grav:
    ; move first, gravity after. the other order eats 0.08 off every jump, a
    ; 0.42 hop only reaches 0.85 and mobs can't climb a single block
    mov   eax, [rbx+ENTITY.vx]
    mov   LOC(PHYS.dx), eax
    mov   eax, [rbx+ENTITY.vy]
    mov   LOC(PHYS.dy), eax
    mov   eax, [rbx+ENTITY.vz]
    mov   LOC(PHYS.dz), eax
    lea   rcx, LOC(0)
    call  physics_move
    mov   eax, LOC(PHYS.x)
    mov   [rbx+ENTITY.x], eax
    mov   eax, LOC(PHYS.y)
    mov   [rbx+ENTITY.y], eax
    mov   eax, LOC(PHYS.z)
    mov   [rbx+ENTITY.z], eax
    mov   eax, LOC(PHYS.flags)
    mov   [rbx+E_PFLAGS], eax
    xor   ecx, ecx
    test  eax, PF_HIT_X
    jz    .hx
    mov   [rbx+ENTITY.vx], ecx
.hx:
    test  eax, PF_HIT_Z
    jz    .hz
    mov   [rbx+ENTITY.vz], ecx
.hz:
    test  eax, PF_HIT_Y
    jz    .hy
    mov   [rbx+ENTITY.vy], ecx
.hy:
    and   byte [rbx+ENTITY.flags], (~EF_ON_GROUND) & 0xFF
    test  eax, PF_GROUND
    jz    .air
    or    byte [rbx+ENTITY.flags], EF_ON_GROUND
.air:
    ; grounded stuff keeps a bit of downward vel on purpose so the next
    ; move clips again and on_ground stays set
    movss xmm0, [rbx+ENTITY.vy]
    subss xmm0, LOC(40)
    maxss xmm0, [rel c_term]
    movss [rbx+ENTITY.vy], xmm0
    movss xmm1, LOC(44)
    movss xmm0, [rbx+ENTITY.vx]
    mulss xmm0, xmm1
    movss [rbx+ENTITY.vx], xmm0
    movss xmm0, [rbx+ENTITY.vy]
    mulss xmm0, xmm1
    movss [rbx+ENTITY.vy], xmm0
    movss xmm0, [rbx+ENTITY.vz]
    mulss xmm0, xmm1
    movss [rbx+ENTITY.vz], xmm0
    test  byte [rbx+ENTITY.flags], EF_ON_GROUND
    jz    .ret
    movss xmm1, LOC(48)
    movss xmm0, [rbx+ENTITY.vx]
    mulss xmm0, xmm1
    movss [rbx+ENTITY.vx], xmm0
    movss xmm0, [rbx+ENTITY.vz]
    mulss xmm0, xmm1
    movss [rbx+ENTITY.vz], xmm0
.ret:
    mov   eax, r12d
ENDP

; xmm2 = up speed, blocks/s
LPROC ent_puff, 32
    mov   rbx, rcx
    mov   r12d, edx
    movss LOC(0), xmm2
    call  rng_float_signed
    mulss xmm0, [rbx+ENTITY.hw]
    addss xmm0, [rbx+ENTITY.x]
    movss LOC(4), xmm0
    call  rng_float
    mulss xmm0, [rbx+ENTITY.h]
    addss xmm0, [rbx+ENTITY.y]
    movss LOC(8), xmm0
    call  rng_float_signed
    mulss xmm0, [rbx+ENTITY.hw]
    addss xmm0, [rbx+ENTITY.z]
    movss LOC(12), xmm0
    call  rng_float_signed
    mulss xmm0, [rel c_0_3]
    movss LOC(16), xmm0
    call  rng_float_signed
    mulss xmm0, [rel c_0_3]
    movss LOC(20), xmm0
    mov   ecx, r12d
    movss xmm1, LOC(4)
    movss xmm2, LOC(8)
    movss xmm3, LOC(12)
    mov   eax, LOC(16)
    mov   [rsp+32], eax
    mov   eax, LOC(0)
    mov   [rsp+40], eax
    mov   eax, LOC(20)
    mov   [rsp+48], eax
    mov   qword [rsp+56], 0
    call  particles_spawn
ENDP

PROC entity_tick_all, 32
    lea   r15, [rel g_entities]
    xor   r14d, r14d
.loop:
    mov   rbx, r14
    shl   rbx, 7
    add   rbx, r15
    cmp   byte [rbx+ENTITY.type], 0
    je    .next
    cmp   byte [rbx+ENTITY.type], ENT_REMOTE
    jne   .local
    mov   rcx, rbx
    call  tick_remote
    jmp   .next
.local:
    movss xmm0, [rbx+ENTITY.y]
    comiss xmm0, [rel c_void]
    jb    .void
    ; unloaded chunk = freeze, otherwise it falls through nothing
    FLOORI ecx, [rbx+ENTITY.x]
    FLOORI edx, [rbx+ENTITY.z]
    call  world_is_loaded
    mov   ecx, [rbx+ENTITY.x]
    mov   [rbx+ENTITY.prev_x], ecx
    mov   ecx, [rbx+ENTITY.y]
    mov   [rbx+ENTITY.prev_y], ecx
    mov   ecx, [rbx+ENTITY.z]
    mov   [rbx+ENTITY.prev_z], ecx
    test  eax, eax
    jz    .frozen
    inc   dword [rbx+ENTITY.age]
    movzx eax, byte [rbx+ENTITY.type]
    mov   rcx, rbx
    mov   edx, r14d
    cmp   eax, ENT_ITEM
    jne   .n1
    call  tick_item
    jmp   .next
.n1:
    cmp   eax, ENT_TNT
    jne   .n2
    call  tick_tnt
    jmp   .next
.n2:
    cmp   eax, ENT_FALLING
    jne   .n3
    call  tick_falling
    jmp   .next
.n3:
    call  tick_mob
    jmp   .next
.frozen:
    ; items left in an unloaded chunk would hold their slot forever, so they
    ; keep ageing while frozen. far mobs get culled by mobs_spawn_tick anyway
    cmp   byte [rbx+ENTITY.type], ENT_ITEM
    jne   .next
    inc   dword [rbx+ENTITY.age]
    cmp   dword [rbx+ENTITY.age], ITEM_LIFETIME
    jl    .next
.void:
    mov   rcx, rbx
    call  entity_remove
.next:
    inc   r14d
    cmp   r14d, MAX_ENTITIES
    jb    .loop
ENDP

; java player: mcplay moves it (and sets prev), only the limbs tick here
LPROC tick_remote
    mov   rbx, rcx
    inc   dword [rbx+ENTITY.age]
    movss xmm0, [rbx+ENTITY.x]
    subss xmm0, [rbx+ENTITY.prev_x]
    mulss xmm0, xmm0
    movss xmm1, [rbx+ENTITY.z]
    subss xmm1, [rbx+ENTITY.prev_z]
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    mulss xmm0, [rel c_4]
    minss xmm0, [rel c_one]
    movss xmm1, [rbx+ENTITY.anim_speed]
    subss xmm0, xmm1
    mulss xmm0, [rel c_0_4]
    addss xmm1, xmm0
    movss [rbx+ENTITY.anim_speed], xmm1
    addss xmm1, [rbx+ENTITY.anim]
    comiss xmm1, [rel c_anim_wrap]
    jb    .aw
    subss xmm1, [rel c_anim_wrap]
.aw:
    movss [rbx+ENTITY.anim], xmm1
ENDP

LPROC tick_item, 32
    mov   rbx, rcx
    mov   r15d, edx
    cmp   byte [rbx+ENTITY.ai_state], ITEM_COLLECT
    jne   .normal
    lea   rsi, [rel g_player]
    movss xmm0, [rsi+PLAYER.x]
    subss xmm0, [rbx+ENTITY.x]
    mulss xmm0, [rel c_half]
    addss xmm0, [rbx+ENTITY.x]
    movss [rbx+ENTITY.x], xmm0
    movss xmm0, [rsi+PLAYER.y]
    addss xmm0, [rel c_0_8]
    subss xmm0, [rbx+ENTITY.y]
    mulss xmm0, [rel c_half]
    addss xmm0, [rbx+ENTITY.y]
    movss [rbx+ENTITY.y], xmm0
    movss xmm0, [rsi+PLAYER.z]
    subss xmm0, [rbx+ENTITY.z]
    mulss xmm0, [rel c_half]
    addss xmm0, [rbx+ENTITY.z]
    movss [rbx+ENTITY.z], xmm0
    dec   dword [rbx+ENTITY.timer]
    jg    .done
    jmp   .remove
.normal:
    cmp   dword [rbx+ENTITY.timer], 0
    jle   .t0
    dec   dword [rbx+ENTITY.timer]
.t0:
    cmp   dword [rbx+ENTITY.age], ITEM_LIFETIME
    jge   .remove
    mov   rcx, rbx
    movss xmm1, [rel c_0_04]
    movss xmm2, [rel c_0_98]
    movss xmm3, [rel c_0_6]
    call  ent_physics
    cmp   eax, 2
    je    .lava
    cmp   eax, 1
    jne   .dry
    ; floats up
    movss xmm0, [rbx+ENTITY.vy]
    addss xmm0, [rel c_0_025]
    minss xmm0, [rel c_0_08]
    movss [rbx+ENTITY.vy], xmm0
.dry:
    ; merge is n^2, so stagger it: every 8 ticks per item
    mov   eax, [rbx+ENTITY.age]
    add   eax, r15d
    test  eax, 7
    jnz   .pickup
    mov   rcx, rbx
    call  item_merge
.pickup:
    cmp   dword [rbx+ENTITY.timer], 0
    jne   .done
    lea   rsi, [rel g_player]
    cmp   dword [rsi+PLAYER.dead], 0
    jne   .done
    ; dist to the body segment, not just the feet
    movss xmm0, [rbx+ENTITY.x]
    subss xmm0, [rsi+PLAYER.x]
    mulss xmm0, xmm0
    movss xmm1, [rbx+ENTITY.z]
    subss xmm1, [rsi+PLAYER.z]
    mulss xmm1, xmm1
    addss xmm0, xmm1
    movss xmm1, [rbx+ENTITY.y]
    movss xmm2, [rsi+PLAYER.y]
    movss xmm3, xmm2
    addss xmm3, [rel c_1_8]
    movss xmm4, xmm1
    maxss xmm4, xmm2
    minss xmm4, xmm3
    subss xmm1, xmm4
    mulss xmm1, xmm1
    addss xmm0, xmm1
    comiss xmm0, [rel c_pick2]
    jae   .done
    movzx ecx, byte [rbx+ENTITY.item+STACK.id]
    movzx edx, byte [rbx+ENTITY.item+STACK.count]
    call  inv_give_player
    movzx ecx, byte [rbx+ENTITY.item+STACK.count]
    cmp   eax, ecx
    jae   .done                         ; inv full
    mov   r12d, eax
    ; inv_give_player has no damage param, so worn tools came back brand new.
    ; fresh copies of a tool are all the same, just stamp the wear onto the
    ; first fresh one (hotbar first, same order give uses). hacky but exact
    test  r12d, r12d
    jnz   .sound
    movzx edx, word [rbx+ENTITY.item+STACK.damage]
    test  edx, edx
    jz    .sound
    movzx ecx, byte [rbx+ENTITY.item+STACK.id]
    lea   rax, [rel g_player + PLAYER.inv]
    mov   r8d, INV_SLOTS
.wear:
    cmp   [rax+STACK.id], cl
    jne   .wear_next
    cmp   word [rax+STACK.damage], 0
    jne   .wear_next
    mov   [rax+STACK.damage], dx
    jmp   .sound
.wear_next:
    add   rax, 4
    dec   r8d
    jnz   .wear
.sound:
    call  rng_float
    mulss xmm0, [rel c_0_6]
    addss xmm0, [rel c_0_8]
    movaps xmm2, xmm0                   ; pitch 0.8..1.4
    movss xmm1, [rel c_0_3]
    mov   ecx, SFX_POP
    call  sfx_play
    test  r12d, r12d
    jz    .collect
    mov   [rbx+ENTITY.item+STACK.count], r12b
    jmp   .done
.collect:
    mov   byte [rbx+ENTITY.ai_state], ITEM_COLLECT
    mov   dword [rbx+ENTITY.timer], 3
    jmp   .done
.lava:
    mov   ecx, SFX_FIZZ
    movss xmm1, [rbx+ENTITY.x]
    movss xmm2, [rbx+ENTITY.y]
    movss xmm3, [rbx+ENTITY.z]
    call  sfx_play_at
    mov   r12d, 3
.smoke:
    mov   rcx, rbx
    mov   edx, PT_SMOKE
    movss xmm2, [rel c_one]
    call  ent_puff
    dec   r12d
    jnz   .smoke
.remove:
    mov   rcx, rbx
    call  entity_remove
.done:
ENDP

LPROC item_merge, 0
    mov   rbx, rcx
    movzx r12d, byte [rbx+ENTITY.item+STACK.id]
    movzx r13d, word [rbx+ENTITY.item+STACK.damage]
    lea   rax, [rel item_max_stack]
    movzx r14d, byte [rax+r12]
    test  r14d, r14d
    jnz   .ms
    mov   r14d, 64
.ms:
    movzx eax, byte [rbx+ENTITY.item+STACK.count]
    cmp   eax, r14d
    jae   .done
    lea   rsi, [rel g_entities]
    xor   edi, edi
    movaps xmm5, [rel c_abs]
.loop:
    mov   rcx, rdi
    shl   rcx, 7
    add   rcx, rsi
    cmp   rcx, rbx
    je    .next
    cmp   byte [rcx+ENTITY.type], ENT_ITEM
    jne   .next
    cmp   byte [rcx+ENTITY.ai_state], 0
    jne   .next
    cmp   [rcx+ENTITY.item+STACK.id], r12b
    jne   .next
    cmp   [rcx+ENTITY.item+STACK.damage], r13w
    jne   .next
    movss xmm0, [rcx+ENTITY.x]
    subss xmm0, [rbx+ENTITY.x]
    andps xmm0, xmm5
    comiss xmm0, [rel c_one]
    jae   .next
    movss xmm0, [rcx+ENTITY.z]
    subss xmm0, [rbx+ENTITY.z]
    andps xmm0, xmm5
    comiss xmm0, [rel c_one]
    jae   .next
    movss xmm0, [rcx+ENTITY.y]
    subss xmm0, [rbx+ENTITY.y]
    andps xmm0, xmm5
    comiss xmm0, [rel c_0_6]
    jae   .next
    ; bigger stack eats the smaller, ties go to the lower address
    movzx eax, byte [rbx+ENTITY.item+STACK.count]
    movzx edx, byte [rcx+ENTITY.item+STACK.count]
    cmp   edx, eax
    ja    .next
    jb    .absorb
    cmp   rcx, rbx
    jb    .next
.absorb:
    mov   r8d, r14d
    sub   r8d, eax
    jle   .done
    cmp   edx, r8d
    cmovb r8d, edx
    add   eax, r8d
    mov   [rbx+ENTITY.item+STACK.count], al
    sub   edx, r8d
    mov   [rcx+ENTITY.item+STACK.count], dl
    mov   eax, [rcx+ENTITY.timer]
    cmp   eax, [rbx+ENTITY.timer]
    jle   .tm
    mov   [rbx+ENTITY.timer], eax
.tm:
    mov   eax, [rcx+ENTITY.age]
    cmp   eax, [rbx+ENTITY.age]
    jge   .ag
    mov   [rbx+ENTITY.age], eax
.ag:
    test  edx, edx
    jnz   .full
    call  entity_remove
.full:
    movzx eax, byte [rbx+ENTITY.item+STACK.count]
    cmp   eax, r14d
    jae   .done
.next:
    inc   edi
    cmp   edi, MAX_ENTITIES
    jb    .loop
.done:
ENDP

LPROC tick_tnt, 32
    mov   rbx, rcx
    mov   rcx, rbx
    movss xmm1, [rel c_0_04]
    movss xmm2, [rel c_0_98]
    movss xmm3, [rel c_0_7]
    call  ent_physics
    test  byte [rbx+ENTITY.age], 1
    jnz   .fuse
    mov   ecx, PT_SMOKE
    movss xmm1, [rbx+ENTITY.x]
    movss xmm2, [rbx+ENTITY.y]
    addss xmm2, [rel c_one]
    movss xmm3, [rbx+ENTITY.z]
    mov   dword [rsp+32], 0
    mov   dword [rsp+40], __float32__(0.6)
    mov   dword [rsp+48], 0
    mov   qword [rsp+56], 0
    call  particles_spawn
.fuse:
    dec   dword [rbx+ENTITY.timer]
    jg    .done
    movss xmm0, [rbx+ENTITY.x]
    movss LOC(0), xmm0
    movss xmm0, [rbx+ENTITY.y]
    addss xmm0, [rel c_0_49]
    movss LOC(4), xmm0
    movss xmm0, [rbx+ENTITY.z]
    movss LOC(8), xmm0
    mov   rcx, rbx
    call  entity_remove                 ; before the blast or it hits itself
    movss xmm0, LOC(0)
    movss xmm1, LOC(4)
    movss xmm2, LOC(8)
    movss xmm3, [rel c_4]
    call  explosion_create
.done:
ENDP

LPROC tick_falling, 32
    mov   rbx, rcx
    movzx r12d, byte [rbx+ENTITY.variant]
    test  r12d, r12d
    jnz   .v
    mov   r12d, B_SAND
    mov   [rbx+ENTITY.variant], r12b
.v:
    cmp   dword [rbx+ENTITY.age], 1
    jne   .phys
    ; spawner might have left the source block in place
    FLOORI r13d, [rbx+ENTITY.x]
    movss xmm0, [rbx+ENTITY.y]
    addss xmm0, [rel c_half]
    FLOORI r14d, xmm0
    FLOORI r15d, [rbx+ENTITY.z]
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    call  world_get_block
    cmp   eax, r12d
    jne   .phys
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    xor   r9d, r9d
    call  world_set_block
.phys:
    mov   rcx, rbx
    movss xmm1, [rel c_0_04]
    movss xmm2, [rel c_0_98]
    movss xmm3, [rel c_0_7]
    call  ent_physics
    test  byte [rbx+ENTITY.flags], EF_ON_GROUND
    jnz   .landed
    cmp   dword [rbx+ENTITY.age], 600
    jl    .done
.landed:
    FLOORI r13d, [rbx+ENTITY.x]
    movss xmm0, [rbx+ENTITY.y]
    addss xmm0, [rel c_half]
    FLOORI r14d, xmm0
    FLOORI r15d, [rbx+ENTITY.z]
    mov   rcx, rbx
    call  entity_remove
    test  byte [rbx+ENTITY.flags], EF_ON_GROUND
    jz    .drop
    cmp   r14d, CHUNK_H
    jae   .drop
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    call  world_get_block
    lea   rcx, [rel blk_flags]
    test  word [rcx+rax*2], BF_REPLACEABLE
    jz    .drop
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    mov   r9d, r12d
    call  world_set_block
    mov   ecx, r12d
    mov   edx, 1                        ; place sound
    mov   r8d, r13d
    mov   r9d, r14d
    mov   [rsp+32], r15d
    call  sfx_play_block
    jmp   .done
.drop:
    lea   rax, [rel blk_drop]
    movzx r9d, byte [rax+r12]
    mov   ecx, r13d
    mov   edx, r14d
    mov   r8d, r15d
    call  entity_drop_block_item
.done:
ENDP

LPROC tick_mob, 32
    mov   rbx, rcx
    mov   eax, [rbx+ENTITY.yaw]
    mov   [rbx+E_PREV_YAW], eax
    test  byte [rbx+ENTITY.flags], EF_DEAD
    jz    .alive
    ; dying: tip over for 20 ticks, then poof
    inc   dword [rbx+ENTITY.death_time]
    mov   rcx, rbx
    movss xmm1, [rel c_0_08]
    movss xmm2, [rel c_0_98]
    movss xmm3, [rel c_0_6]
    call  ent_physics
    cmp   dword [rbx+ENTITY.death_time], 20
    jl    .done
    mov   rcx, rbx
    call  mob_finish
    jmp   .done
.alive:
    cmp   dword [rbx+ENTITY.hurt_time], 0
    jle   .h0
    dec   dword [rbx+ENTITY.hurt_time]
.h0:
    cmp   dword [rbx+ENTITY.attack_cd], 0
    jle   .a0
    dec   dword [rbx+ENTITY.attack_cd]
.a0:
    mov   rcx, rbx
    call  mobs_ai_tick
    cmp   byte [rbx+ENTITY.type], 0
    je    .done                         ; ai despawned it
    mov   rcx, rbx
    call  mob_push
    mov   rcx, rbx
    cmp   byte [rbx+ENTITY.type], ENT_GLOWBUG
    jne   .walker
    xorps xmm1, xmm1
    movss xmm2, [rel c_0_9]
    movss xmm3, [rel c_0_9]
    call  ent_physics
    jmp   .phys_done
.walker:
    movss xmm1, [rel c_0_08]
    movss xmm2, [rel c_0_98]
    movss xmm3, [rel c_0_6]
    call  ent_physics
.phys_done:
    mov   r12d, eax
    cmp   r12d, 1
    jne   .nw
    mov   dword [rbx+ENTITY.fire], 0
    mov   dword [rbx+E_FALL], 0
    cmp   byte [rbx+ENTITY.type], ENT_GLOWBUG
    je    .nw
    movss xmm0, [rbx+ENTITY.vy]
    addss xmm0, [rel c_0_034]
    movss [rbx+ENTITY.vy], xmm0
.nw:
    cmp   r12d, 2
    jne   .nl
    mov   dword [rbx+ENTITY.fire], 300
    mov   dword [rbx+E_FALL], 0
    mov   eax, [rbx+ENTITY.age]
    xor   edx, edx
    mov   ecx, 10
    div   ecx
    test  edx, edx
    jnz   .nl
    mov   rcx, rbx
    mov   edx, 4
    mov   r8d, DMG_LAVA
    call  entity_damage
.nl:
    mov   eax, [rbx+ENTITY.fire]
    test  eax, eax
    jz    .nofire
    dec   eax
    mov   [rbx+ENTITY.fire], eax
    xor   edx, edx
    mov   ecx, 20
    div   ecx
    test  edx, edx
    jnz   .flame
    mov   rcx, rbx
    mov   edx, 1
    mov   r8d, DMG_LAVA
    call  entity_damage
.flame:
    mov   ecx, 2
    call  rng_int
    test  eax, eax
    jnz   .nofire
    mov   rcx, rbx
    mov   edx, PT_FLAME
    movss xmm2, [rel c_0_5]
    call  ent_puff
.nofire:
    cmp   byte [rbx+ENTITY.type], 0
    je    .done
    test  byte [rbx+ENTITY.flags], EF_DEAD
    jnz   .anim
    cmp   byte [rbx+ENTITY.type], ENT_GLOWBUG
    je    .suffo
    movss xmm0, [rbx+ENTITY.prev_y]
    subss xmm0, [rbx+ENTITY.y]          ; > 0 while descending
    test  byte [rbx+ENTITY.flags], EF_ON_GROUND
    jnz   .landed
    xorps xmm1, xmm1
    maxss xmm0, xmm1
    addss xmm0, [rbx+E_FALL]
    movss [rbx+E_FALL], xmm0
    jmp   .suffo
.landed:
    movss xmm0, [rbx+E_FALL]
    mov   dword [rbx+E_FALL], 0
    subss xmm0, [rel c_3]
    comiss xmm0, [rel c_half]
    jb    .suffo
    cvtss2si edx, xmm0
    test  edx, edx
    jle   .suffo
    mov   rcx, rbx
    mov   r8d, DMG_FALL
    call  entity_damage
.suffo:
    mov   eax, [rbx+ENTITY.age]
    and   eax, 15
    jnz   .anim
    FLOORI r13d, [rbx+ENTITY.x]
    movss xmm0, [rbx+ENTITY.y]
    addss xmm0, [rbx+ENTITY.h]
    subss xmm0, [rel c_0_1]
    FLOORI edx, xmm0
    FLOORI r8d, [rbx+ENTITY.z]
    mov   ecx, r13d
    call  world_get_block
    lea   rcx, [rel blk_flags]
    movzx eax, word [rcx+rax*2]
    and   eax, BF_SOLID|BF_OPAQUE
    cmp   eax, BF_SOLID|BF_OPAQUE
    jne   .anim
    mov   rcx, rbx
    mov   edx, 1
    mov   r8d, DMG_GENERIC
    call  entity_damage
.anim:
    ; limbs go by distance actually moved, not vel
    movss xmm0, [rbx+ENTITY.x]
    subss xmm0, [rbx+ENTITY.prev_x]
    mulss xmm0, xmm0
    movss xmm1, [rbx+ENTITY.z]
    subss xmm1, [rbx+ENTITY.prev_z]
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    mulss xmm0, [rel c_4]
    minss xmm0, [rel c_one]
    movss xmm1, [rbx+ENTITY.anim_speed]
    subss xmm0, xmm1
    mulss xmm0, [rel c_0_4]
    addss xmm1, xmm0
    movss [rbx+ENTITY.anim_speed], xmm1
    addss xmm1, [rbx+ENTITY.anim]
    comiss xmm1, [rel c_anim_wrap]
    jb    .aw
    subss xmm1, [rel c_anim_wrap]
.aw:
    movss [rbx+ENTITY.anim], xmm1
.done:
ENDP

; overlapping walkers nudge each other apart, 0.05/tick. each mob only pushes
; itself, the other one gets the mirror push on its own tick. without this
; herds turn into one big blob. one 512 scan per mob per tick
LPROC mob_push, 16
    mov   rbx, rcx
    cmp   byte [rbx+ENTITY.type], ENT_GLOWBUG
    je    .done
    lea   rsi, [rel g_entities]
    mov   edi, MAX_ENTITIES
.loop:
    cmp   rsi, rbx
    je    .next
    movzx eax, byte [rsi+ENTITY.type]
    cmp   eax, ENT_BOAR
    jb    .next
    cmp   eax, ENT_SHAMBLER
    ja    .next                         ; glowbugs
    test  byte [rsi+ENTITY.flags], EF_DEAD
    jnz   .next
    movss xmm0, [rsi+ENTITY.y]
    addss xmm0, [rsi+ENTITY.h]
    comiss xmm0, [rbx+ENTITY.y]
    jbe   .next
    movss xmm0, [rbx+ENTITY.y]
    addss xmm0, [rbx+ENTITY.h]
    comiss xmm0, [rsi+ENTITY.y]
    jbe   .next
    movss xmm4, [rbx+ENTITY.hw]
    addss xmm4, [rsi+ENTITY.hw]
    movss xmm0, [rbx+ENTITY.x]
    subss xmm0, [rsi+ENTITY.x]
    movaps xmm2, xmm0
    andps xmm2, [rel c_abs]
    comiss xmm2, xmm4
    jae   .next
    movss xmm1, [rbx+ENTITY.z]
    subss xmm1, [rsi+ENTITY.z]
    movaps xmm2, xmm1
    andps xmm2, [rel c_abs]
    comiss xmm2, xmm4
    jae   .next
    movaps xmm2, xmm0
    mulss xmm2, xmm0
    movaps xmm3, xmm1
    mulss xmm3, xmm1
    addss xmm2, xmm3
    sqrtss xmm2, xmm2
    comiss xmm2, [rel c_1e_4]
    ja    .dir
    ; exactly on top of each other, split on x by slot order
    xorps xmm1, xmm1
    movss xmm0, [rel c_one]
    movss xmm2, [rel c_one]
    cmp   rbx, rsi
    ja    .dir
    movss xmm0, [rel c_m1]
.dir:
    divss xmm0, xmm2
    divss xmm1, xmm2
    movss LOC(0), xmm0
    movss LOC(4), xmm1
    ; don't shove anyone off a ledge (pens, cliffs). block under the leading
    ; edge has to be solid
    test  byte [rbx+ENTITY.flags], EF_ON_GROUND
    jz    .push
    movss xmm2, [rbx+ENTITY.hw]
    addss xmm2, [rel c_0_3]
    mulss xmm0, xmm2
    addss xmm0, [rbx+ENTITY.x]
    FLOORI ecx, xmm0
    mulss xmm1, xmm2
    addss xmm1, [rbx+ENTITY.z]
    FLOORI r8d, xmm1
    movss xmm0, [rbx+ENTITY.y]
    addss xmm0, [rel c_0_01]
    FLOORI edx, xmm0
    dec   edx
    call  world_get_block
    lea   rcx, [rel blk_flags]
    test  word [rcx+rax*2], BF_SOLID
    jz    .next
.push:
    movss xmm0, LOC(0)
    mulss xmm0, [rel c_0_05]
    addss xmm0, [rbx+ENTITY.vx]
    movss [rbx+ENTITY.vx], xmm0
    movss xmm1, LOC(4)
    mulss xmm1, [rel c_0_05]
    addss xmm1, [rbx+ENTITY.vz]
    movss [rbx+ENTITY.vz], xmm1
.next:
    add   rsi, ENTITY_size
    dec   edi
    jnz   .loop
.done:
ENDP

LPROC mob_finish, 16
    mov   rbx, rcx
    mov   r12d, 8
.poof:
    mov   rcx, rbx
    mov   edx, PT_SMOKE
    movss xmm2, [rel c_0_8]
    call  ent_puff
    dec   r12d
    jnz   .poof
    movzx eax, byte [rbx+ENTITY.type]
    cmp   eax, ENT_BOAR
    jne   .nb
    mov   ecx, 3
    call  rng_int
    lea   r13d, [rax+1]
    mov   r14d, I_RAW_MEAT
    cmp   dword [rbx+ENTITY.fire], 0
    je    .drop
    mov   r14d, I_COOKED_MEAT           ; died on fire
    jmp   .drop
.nb:
    cmp   eax, ENT_WOOLLY
    jne   .nw
    mov   ecx, 2
    call  rng_int
    lea   r13d, [rax+1]
    movzx r14d, byte [rbx+ENTITY.variant]
    and   r14d, 15
    add   r14d, B_WOOL
    jmp   .drop
.nw:
    cmp   eax, ENT_SHAMBLER
    jne   .gone
    mov   ecx, 3
    call  rng_int
    mov   r13d, eax                     ; 0..2
    mov   r14d, I_ROTTEN_FLESH
.drop:
    test  r13d, r13d
    jz    .gone
    movss xmm0, [rbx+ENTITY.z]
    movss [rsp+32], xmm0
    mov   ecx, r14d
    mov   edx, r13d
    movss xmm2, [rbx+ENTITY.x]
    movss xmm3, [rbx+ENTITY.y]
    addss xmm3, [rel c_0_4]
    call  entity_spawn_item
.gone:
    mov   rcx, rbx
    call  entity_remove
ENDP

; 10 tick i-frames after a hit, void ignores them
PROC entity_damage, 32
    mov   rbx, rcx
    mov   r12d, edx
    mov   r13d, r8d
    test  rbx, rbx
    jz    .ret0
    movzx ecx, byte [rbx+ENTITY.type]
    cmp   ecx, ENT_BOAR
    jb    .ret0
    cmp   ecx, ENT_TYPES
    jae   .ret0
    test  byte [rbx+ENTITY.flags], EF_DEAD
    jnz   .ret0
    test  r12d, r12d
    jle   .ret0
    cmp   dword [rbx+ENTITY.hurt_time], 0
    jle   .ok
    cmp   r13d, DMG_VOID
    jne   .ret0
.ok:
    sub   [rbx+ENTITY.health], r12d
    mov   dword [rbx+ENTITY.hurt_time], 10
    cmp   r13d, DMG_PLAYER
    jne   .noknock
    lea   rsi, [rel g_player]
    movss xmm0, [rbx+ENTITY.x]
    subss xmm0, [rsi+PLAYER.x]
    movss xmm1, [rbx+ENTITY.z]
    subss xmm1, [rsi+PLAYER.z]
    movaps xmm2, xmm0
    mulss xmm2, xmm2
    movaps xmm3, xmm1
    mulss xmm3, xmm3
    addss xmm2, xmm3
    sqrtss xmm2, xmm2
    comiss xmm2, [rel c_1e_4]
    ja    .norm
    xorps xmm0, xmm0
    movss xmm1, [rel c_one]
    movss xmm2, [rel c_one]
.norm:
    divss xmm0, xmm2
    divss xmm1, xmm2
    mulss xmm0, [rel c_0_4]
    mulss xmm1, [rel c_0_4]
    movss [rbx+ENTITY.vx], xmm0
    movss [rbx+ENTITY.vz], xmm1
    mov   dword [rbx+ENTITY.vy], __float32__(0.36)
    mov   r14d, 5
.crit:
    mov   rcx, rbx
    mov   edx, PT_CRIT
    movss xmm2, [rel c_2]
    call  ent_puff
    dec   r14d
    jnz   .crit
.noknock:
    movzx eax, byte [rbx+ENTITY.type]
    cmp   eax, ENT_SHAMBLER
    jne   .passive
    cmp   r13d, DMG_PLAYER
    jne   .snd
    mov   dword [rbx+E_PANIC], 400      ; 20s
    jmp   .snd
.passive:
    cmp   eax, ENT_WOOLLY
    ja    .snd
    cmp   r13d, DMG_PLAYER
    jne   .panic
    or    byte [rbx+ENTITY.flags], EF_PERSIST   ; player hit it, keep it around
.panic:
    mov   dword [rbx+E_PANIC], 60
    mov   dword [rbx+ENTITY.timer], 0
.snd:
    lea   rax, [rel mob_sound]
    movzx ecx, byte [rbx+ENTITY.type]
    mov   ecx, [rax+rcx*4]
    test  ecx, ecx
    js    .nosnd
    movss xmm2, [rbx+ENTITY.h]
    mulss xmm2, [rel c_half]
    addss xmm2, [rbx+ENTITY.y]
    movss xmm1, [rbx+ENTITY.x]
    movss xmm3, [rbx+ENTITY.z]
    call  sfx_play_at
.nosnd:
    cmp   dword [rbx+ENTITY.health], 0
    jg    .ret1
    mov   dword [rbx+ENTITY.health], 0
    or    byte [rbx+ENTITY.flags], EF_DEAD
    mov   dword [rbx+ENTITY.death_time], 0
.ret1:
    mov   eax, 1
    jmp   .done
.ret0:
    xor   eax, eax
.done:
ENDP

LEAF entity_count_type
    lea   rdx, [rel g_entities]
    xor   eax, eax
    mov   r8d, MAX_ENTITIES
.l: movzx r9d, byte [rdx+ENTITY.type]
    cmp   r9d, ecx
    jne   .n
    inc   eax
.n: add   rdx, ENTITY_size
    dec   r8d
    jnz   .l
    ret

; slab test, boxes grown by 0.1 so the hitbox is a bit forgiving
%macro SLAB 4   ; origin, dir, min, max. trashes xmm0-2, jumps to .miss
    movaps xmm0, %2
    andps  xmm0, xmm15
    comiss xmm0, [rel c_1e_7]
    ja     %%div
    comiss %1, %3
    jb     .miss
    comiss %1, %4
    ja     .miss
    jmp    %%ok
%%div:
    movss  xmm2, [rel c_one]
    divss  xmm2, %2
    movaps xmm0, %3
    subss  xmm0, %1
    mulss  xmm0, xmm2
    movaps xmm1, %4
    subss  xmm1, %1
    mulss  xmm1, xmm2
    movaps xmm2, xmm0
    minss  xmm0, xmm1
    maxss  xmm1, xmm2
    maxss  xmm13, xmm0
    minss  xmm14, xmm1
    comiss xmm13, xmm14
    ja     .miss
%%ok:
%endmacro

PROCX entity_raycast, 32
    movss xmm7,  [rcx]
    movss xmm8,  [rcx+4]
    movss xmm9,  [rcx+8]
    movss xmm10, [rdx]
    movss xmm11, [rdx+4]
    movss xmm12, [rdx+8]
    movss xmm6, xmm2                    ; best t
    movaps xmm15, [rel c_abs]
    xor   r12d, r12d
    lea   rbx, [rel g_entities]
    mov   esi, MAX_ENTITIES
.loop:
    movzx eax, byte [rbx+ENTITY.type]
    cmp   eax, ENT_BOAR
    jb    .miss
    test  byte [rbx+ENTITY.flags], EF_DEAD
    jnz   .miss
    xorps xmm13, xmm13
    movss xmm14, xmm6
    movss xmm3, [rbx+ENTITY.x]
    movss xmm4, xmm3
    movss xmm5, [rbx+ENTITY.hw]
    addss xmm5, [rel c_0_1]
    subss xmm3, xmm5
    addss xmm4, xmm5
    SLAB  xmm7, xmm10, xmm3, xmm4
    movss xmm3, [rbx+ENTITY.z]
    movss xmm4, xmm3
    movss xmm5, [rbx+ENTITY.hw]
    addss xmm5, [rel c_0_1]
    subss xmm3, xmm5
    addss xmm4, xmm5
    SLAB  xmm9, xmm12, xmm3, xmm4
    movss xmm3, [rbx+ENTITY.y]
    subss xmm3, [rel c_0_1]
    movss xmm4, [rbx+ENTITY.y]
    addss xmm4, [rbx+ENTITY.h]
    addss xmm4, [rel c_0_1]
    SLAB  xmm8, xmm11, xmm3, xmm4
    movss xmm6, xmm13
    mov   r12, rbx
.miss:
    add   rbx, ENTITY_size
    dec   esi
    jnz   .loop
    mov   rax, r12
    movss xmm0, xmm6
ENDPX

PROC entity_light_at, 0
    FLOORI ecx, xmm0
    FLOORI edx, xmm1
    FLOORI r8d, xmm2
    call  world_get_light
    mov   edx, eax
    shr   edx, 4
    and   edx, 15
    and   eax, 15
    cvtsi2ss xmm0, edx
    mulss xmm0, [rel g_daylight]
    cvtsi2ss xmm1, eax
    maxss xmm0, xmm1
    mulss xmm0, [rel c_1_15]
    movss xmm1, [rel c_3]
    movaps xmm2, xmm0
    addss xmm2, xmm2
    subss xmm1, xmm2
    divss xmm0, xmm1                    ; l/(3-2l), dark spots aren't pitch black
    mulss xmm0, [rel c_0_94]
    addss xmm0, [rel c_0_06]
ENDP

PROC entity_lerp_pos_light, 32
    mov   rbx, rcx
    mov   rsi, rdx
    movss xmm4, [rel g_partial_tick]
    xorps xmm5, xmm5
    maxss xmm4, xmm5
    minss xmm4, [rel c_one]
    movss xmm0, [rbx+ENTITY.x]
    subss xmm0, [rbx+ENTITY.prev_x]
    mulss xmm0, xmm4
    addss xmm0, [rbx+ENTITY.prev_x]
    movss LOC(0), xmm0
    movss xmm0, [rbx+ENTITY.y]
    subss xmm0, [rbx+ENTITY.prev_y]
    mulss xmm0, xmm4
    addss xmm0, [rbx+ENTITY.prev_y]
    movss LOC(4), xmm0
    movss xmm0, [rbx+ENTITY.z]
    subss xmm0, [rbx+ENTITY.prev_z]
    mulss xmm0, xmm4
    addss xmm0, [rbx+ENTITY.prev_z]
    movss LOC(8), xmm0
    movss xmm1, [rbx+ENTITY.h]
    mulss xmm1, [rel c_half]
    addss xmm1, LOC(4)
    movss xmm0, LOC(0)
    movss xmm2, LOC(8)
    call  entity_light_at
    movss [rsi+12], xmm0
    lea   rax, [rel g_cam_pos]
    movss xmm0, LOC(0)
    subss xmm0, [rax]
    movss [rsi], xmm0
    movss xmm0, LOC(4)
    subss xmm0, [rax+4]
    movss [rsi+4], xmm0
    movss xmm0, LOC(8)
    subss xmm0, [rax+8]
    movss [rsi+8], xmm0
ENDP

PROCX entity_render_all, 32 ; v1: entity scratch #1
    mov   ecx, GL_TEXTURE_2D ; v1: entity scratch #2
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (entity:2)
    mov   edx, [rel g_tex_atlas] ; v1: entity scratch #3
    call  glBindTexture ; v1: entity scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (entity:4)
    ; has to match the chunk shader fog or mobs stick out
    mov   ecx, GL_FOG ; v1: entity scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (entity:6)
    call  glEnable ; v1: entity scratch #7
    mov   ecx, GL_FOG_MODE ; v1: entity scratch #8
    ; TODO: hoist invariant pointer load out of .loop (entity:8)
    mov   edx, GL_LINEAR ; v1: entity scratch #9
    call  glFogi ; v1: entity scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (entity:10)
    mov   ecx, GL_FOG_START ; v1: entity scratch #11
    movss xmm1, [rel g_fog_start] ; v1: entity scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (entity:12)
    call  glFogf ; v1: entity scratch #13
    mov   ecx, GL_FOG_END ; v1: entity scratch #14
    ; TODO: clamp index before table lookup on malformed input (entity:14)
    movss xmm1, [rel g_fog_end] ; v1: entity scratch #15
    call  glFogf ; v1: entity scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (entity:16)
    mov   ecx, GL_FOG_COLOR ; v1: entity scratch #17
    lea   rdx, [rel g_fog_color] ; v1: entity scratch #18
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (entity:18)
    call  glFogfv ; v1: entity scratch #19

    lea   r15, [rel g_entities] ; v1: entity scratch #21
    xor   r14d, r14d ; v1: entity scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (entity:22)
.loop: ; v1: entity scratch #23
    mov   rbx, r14 ; v1: entity scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (entity:24)
    shl   rbx, 7 ; v1: entity scratch #25
    add   rbx, r15 ; v1: entity scratch #26
    ; TODO: hoist invariant pointer load out of .loop (entity:26)
    movzx r12d, byte [rbx+ENTITY.type] ; v1: entity scratch #27
    test  r12d, r12d ; v1: entity scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (entity:28)
    jz    .next ; v1: entity scratch #29
    mov   rcx, rbx ; v1: entity scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (entity:30)
    lea   rdx, LOC(0) ; v1: entity scratch #31
    call  entity_lerp_pos_light ; v1: entity scratch #32
    ; TODO: clamp index before table lookup on malformed input (entity:32)
    movss xmm0, LOC(0) ; v1: entity scratch #33
    mulss xmm0, xmm0 ; v1: entity scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (entity:34)
    movss xmm1, LOC(4) ; v1: entity scratch #35
    mulss xmm1, xmm1 ; v1: entity scratch #36
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (entity:36)
    addss xmm0, xmm1 ; v1: entity scratch #37
    movss xmm1, LOC(8) ; v1: entity scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (entity:38)
    mulss xmm1, xmm1 ; v1: entity scratch #39
    addss xmm0, xmm1 ; v1: entity scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (entity:40)
    comiss xmm0, [rel c_draw_dist2] ; v1: entity scratch #41
    ja    .next ; v1: entity scratch #42
    ; TODO: hoist invariant pointer load out of .loop (entity:42)
    movss xmm0, [rbx+ENTITY.h] ; v1: entity scratch #43
    mulss xmm0, [rel c_half] ; v1: entity scratch #44
    ; temp: spill r12/r13 across helper call until reg alloc pass (entity:44)
    movss xmm2, LOC(4) ; v1: entity scratch #45
    addss xmm2, xmm0 ; v1: entity scratch #46
    ; FIXME: negative world x/z needs sar 4, not shr 4 (entity:46)
    addss xmm0, [rbx+ENTITY.hw]
    addss xmm0, [rel c_half]
    movss [rsp+32], xmm0
    lea   rcx, [rel g_frustum]
    movss xmm1, LOC(0)
    movss xmm3, LOC(8)
    call  frustum_test_sphere
    test  eax, eax
    jz    .next
    mov   rcx, rbx
    lea   rdx, LOC(0)
    cmp   r12d, ENT_ITEM
    jne   .r1
    call  render_item_ent
    jmp   .next
.r1:
    cmp   r12d, ENT_TNT
    jne   .r2
    call  render_tnt_ent
    jmp   .next
.r2:
    cmp   r12d, ENT_FALLING
    jne   .r3
    call  render_falling_ent
    jmp   .next
.r3:
    call  mobs_render
.next:
    inc   r14d
    cmp   r14d, MAX_ENTITIES
    jb    .loop

    ; 3rd person player model is drawn by render.asm, its shadow is ours
    call  render_shadows
    mov   ecx, GL_FOG
    call  glDisable
    movss xmm0, [rel c_one]
    movaps xmm1, xmm0
    movaps xmm2, xmm0
    movaps xmm3, xmm0
    call  glColor4f
ENDPX

LPROCX render_item_ent, 32
    mov   rbx, rcx
    mov   rsi, rdx
    movzx r12d, byte [rbx+ENTITY.item+STACK.id]
    test  r12d, r12d
    jz    .done
    movzx r13d, byte [rbx+ENTITY.item+STACK.count]
    mov   r14d, 1
    cmp   r13d, 1
    jbe   .c
    mov   r14d, 2
    cmp   r13d, 16
    jb    .c
    mov   r14d, 3
    cmp   r13d, 48
    jb    .c
    mov   r14d, 4
.c:
    cvtsi2ss xmm6, dword [rbx+ENTITY.age]
    addss xmm6, [rel g_partial_tick]
    movss xmm0, xmm6
    mulss xmm0, [rel c_0_1]
    addss xmm0, [rbx+E_PHASE]
    call  math_sin
    mulss xmm0, [rel c_0_1]
    addss xmm0, [rel c_0_1]
    movss xmm7, xmm0                    ; bob 0..0.2
    movss xmm8, xmm6
    mulss xmm8, [rel c_3]
    movss xmm0, [rbx+E_PHASE]
    mulss xmm0, [rel c_r2d]
    addss xmm8, xmm0                    ; degrees
    movss xmm9, [rsi+12]
    call  glPushMatrix
    movss xmm0, [rsi]
    movss xmm1, [rsi+4]
    addss xmm1, xmm7
    movss xmm2, [rsi+8]
    call  glTranslatef
    lea   rax, [rel item_icon]
    cmp   byte [rax+r12], 0xFF
    jne   .sprite
    movaps xmm0, xmm8
    xorps xmm1, xmm1
    movss xmm2, [rel c_one]
    xorps xmm3, xmm3
    call  glRotatef
    lea   r15, [rel copy_off]
    xor   edi, edi
.bl:
    call  glPushMatrix
    movss xmm0, [r15]
    movss xmm1, [r15+4]
    movss xmm2, [r15+8]
    call  glTranslatef
    movss xmm0, [rel c_0_25]
    movaps xmm1, xmm0
    movaps xmm2, xmm0
    call  glScalef
    movss xmm0, [rel c_mhalf]
    xorps xmm1, xmm1
    movss xmm2, [rel c_mhalf]
    call  glTranslatef
    mov   ecx, r12d
    movaps xmm1, xmm9
    call  render_block_cube
    call  glPopMatrix
    add   r15, 12
    inc   edi
    cmp   edi, r14d
    jb    .bl
    jmp   .pop
.sprite:
    ; flat items face the camera
    movss xmm0, [rel g_cam_yaw]
    xorps xmm0, [rel c_sign]
    xorps xmm1, xmm1
    movss xmm2, [rel c_one]
    xorps xmm3, xmm3
    call  glRotatef
    mov   ecx, GL_CULL_FACE
    call  glDisable
    mov   ecx, GL_ALPHA_TEST
    call  glEnable
    mov   ecx, GL_GREATER
    movss xmm1, [rel c_0_1]
    call  glAlphaFunc
    lea   r15, [rel copy_off_sprite]
    xor   edi, edi
.sl:
    ; v1 temporary guard (entity #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (entity #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (entity #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (entity #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (entity #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (entity #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (entity #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (entity #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (entity #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (entity #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (entity #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (entity #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (entity #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (entity #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (entity #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (entity #52)
    xor     r11d, r11d ; clear v1 slot 52
