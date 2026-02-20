%define IMPL_PARTICLES
%include "common.inc"
%unmacro FCONST 2

; same FCONST-via-r11 trick as sky.asm
%macro FCONST 2
    mov  r11d, __float32__(%2)
    movd %1, r11d
%endmacro

extern atm_rand, atm_randf, atm_randfs, atm_randint, atm_draw, atm_tile_uv

%define PFL_ADD         1
%define PFL_COLLIDE     2
%define PFL_BRIGHT      4
%define PFL_DIEHIT      8
%define PFL_WATER       16
%define PFL_FLUTTER     32

%define PT_LAST         PT_SPARK
%define EMIT_MAX        160
%define AMB_R           12

%macro FLOORI 3
    roundss %3, %2, 1
    cvttss2si %1, %3
%endmacro

%macro FUNCX 1-2 0
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

; quad at [%1]: centre xmm6, half axes xmm7/xmm8, uv xmm9-xmm12, colour r15d
%macro PQUAD 1
    movaps   xmm0, xmm6
    subps    xmm0, xmm7
    subps    xmm0, xmm8
    movups   [%1], xmm0
    movss    [%1+12], xmm9
    movss    [%1+16], xmm12
    mov      [%1+20], r15d
    movaps   xmm0, xmm6
    addps    xmm0, xmm7
    subps    xmm0, xmm8
    movups   [%1+24], xmm0
    movss    [%1+36], xmm11
    movss    [%1+40], xmm12
    mov      [%1+44], r15d
    movaps   xmm0, xmm6
    addps    xmm0, xmm7
    addps    xmm0, xmm8
    movups   [%1+48], xmm0
    movss    [%1+60], xmm11
    movss    [%1+64], xmm10
    mov      [%1+68], r15d
    movaps   xmm0, xmm6
    subps    xmm0, xmm7
    addps    xmm0, xmm8
    movups   [%1+72], xmm0
    movss    [%1+84], xmm9
    movss    [%1+88], xmm10
    mov      [%1+92], r15d
%endmacro

section .rdata
align 16
c_mask3:        dd 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0
c_zero4:        dd 0.0, 0.0, 0.0, 0.0
c_one4:         dd 1.0, 1.0, 1.0, 1.0
c_255x4:        dd 255.0, 255.0, 255.0, 255.0
c_inv255x4:     dd 0.003921569, 0.003921569, 0.003921569, 0.003921569

; 32 byte rows: tile, size_min, size_rand, life_min, life_rand, gravity, colour, drag
; size is HALF the quad. smoke also swells ~2.2x in the render loop
ptype:
    dd 0,                 0.05,  0.045, 0.50, 1.00,  16.0, 0xFFFFFFFF, 0.4   ; PT_BLOCK
    dd T_PARTICLE_SMOKE,  0.10,  0.06,  1.40, 1.40,  -0.7, 0xFFC4C4C4, 1.6   ; PT_SMOKE
    dd T_PARTICLE_FLAME,  0.085, 0.045, 0.45, 0.40, -0.25, 0xFFFFFFFF, 2.2   ; PT_FLAME
    dd T_PARTICLE_SPLASH, 0.06,  0.05,  0.25, 0.35,  14.0, 0xFFFFD8A8, 0.6   ; PT_SPLASH
    dd T_EXPLOSION,       1.00,  1.20,  0.45, 0.50,  -0.6, 0xFFFFFFFF, 3.0   ; PT_EXPLOSION
    dd T_RAIN,            0.035, 0.01,  3.00, 0.50,   0.0, 0xB4FFE8C8, 0.0   ; PT_RAIN
    dd T_SNOWFLAKE,       0.03,  0.03, 10.00, 4.00,   0.0, 0xFFFFFFFF, 0.0   ; PT_SNOW
    dd T_BUBBLE,          0.05,  0.05,  1.50, 2.50,  -8.0, 0xFFFFFFFF, 2.5   ; PT_BUBBLE
    dd T_WHITE,           0.025, 0.03,  0.50, 0.60,   0.0, 0xFFA0F0FF, 2.0   ; PT_CRIT
    dd T_WHITE,           0.03,  0.03,  0.60, 0.60,  12.0, 0xFF2088FF, 0.6   ; PT_SPARK
pflags:
    db PFL_COLLIDE  ; same order as ptype
    db 0
    db PFL_ADD | PFL_BRIGHT
    db PFL_COLLIDE
    db PFL_BRIGHT
    db PFL_COLLIDE | PFL_DIEHIT
    db PFL_COLLIDE | PFL_DIEHIT | PFL_FLUTTER
    db PFL_COLLIDE | PFL_WATER
    db PFL_ADD | PFL_BRIGHT
    db PFL_ADD | PFL_BRIGHT | PFL_COLLIDE

align 4
; face normals (x, y, z) in FACE_* order
face_n:     dd 1.0,0.0,0.0,  -1.0,0.0,0.0,  0.0,1.0,0.0,  0.0,-1.0,0.0,  0.0,0.0,1.0,  0.0,0.0,-1.0
; density per g_settings.particles (0 minimal, 1 decreased, 2 all)
dens_tab:   dd 0.30, 0.60, 1.0
scan_tab:   dd 60, 120, 200
grid_tab:   dd 2, 3, 4

c_one:      dd 1.0
c_half:     dd 0.5
c_two:      dd 2.0
c_three:    dd 3.0
c_255:      dd 255.0
c_inv15:    dd 0.06666667
c_inv256:   dd 0.00390625
c_halftex:  dd 0.001953125
c_tile_in:  dd 0.05859375                  ; 1/16 - 1/256
c_sub_in:   dd 0.0146484375                ; 4/256 - 1/1024 (debris window)
c_eps:      dd 0.002
c_rest:     dd 0.998

section .bss
alignb 16
g_particles:        resb PARTICLE_size*MAX_PARTICLES
global g_particle_count
g_particle_count:   resd 1
alignb 16
p_vbuf:             resb MAX_PARTICLES*4*24
emitters:           resd EMIT_MAX*4         ; x, y, z, block id
emit_count:         resd 1
sweep_layer:        resd 1
light_br:           resd 16
p_internal:         resd 1
p_ready:            resd 1
furnace_face:       resd 1
dens:               resd 1
pc_x:               resd 1
pc_y:               resd 1
pc_z:               resd 1
sp_x:               resd 1
sp_y:               resd 1
sp_z:               resd 1
sp_vx:              resd 1
sp_vy:              resd 1
sp_vz:              resd 1
sp_param:           resd 1
fp_x:               resd 1
fp_y:               resd 1
fp_z:               resd 1
alignb 16
cam4:               resd 4
right4:             resd 4
up4:                resd 4
dir4:               resd 4
rh4:                resd 4
fog4:               resd 4

section .text

PROCX particles_init, 32
    ; brightness curve: v = l/15, b = v / (3 - 2v), b = 0.04 + 0.96 b
    lea      rsi, [rel light_br]
    xor      ebx, ebx
.l:
    cvtsi2ss xmm0, ebx
    mulss    xmm0, [rel c_inv15]
    movss    xmm1, [rel c_three]
    movss    xmm2, xmm0
    addss    xmm2, xmm2
    subss    xmm1, xmm2
    divss    xmm0, xmm1
    FCONST   xmm1, 0.96
    mulss    xmm0, xmm1
    FCONST   xmm1, 0.04
    addss    xmm0, xmm1
    movss    [rsi+rbx*4], xmm0
    inc      ebx
    cmp      ebx, 16
    jb       .l
    ; which face of the lit furnace carries the glowing front?
    mov      dword [rel furnace_face], FACE_PZ
    lea      rax, [rel blk_tex]
    xor      ecx, ecx
.f:
    movzx    edx, byte [rax+B_FURNACE_LIT*6+rcx]
    cmp      edx, T_FURNACE_FRONT_LIT
    je       .found
    cmp      edx, T_FURNACE_FRONT
    je       .found
    inc      ecx
    cmp      ecx, 6
    jb       .f
    jmp      .nf
.found:
    mov      [rel furnace_face], ecx
.nf:
    mov      dword [rel p_ready], 1
    call     particles_clear
ENDPX

PROC particles_clear, 0
    mov      dword [rel g_particle_count], 0
    mov      dword [rel emit_count], 0
    mov      dword [rel sweep_layer], 0
ENDP

; atm_particles_base() -> rax pointer to the pool (diagnostics / tests)
LEAF atm_particles_base
    lea      rax, [rel g_particles]
    ret

; param = block id for PT_BLOCK, else a tile override (0 = default). outside
; callers get thinned by the setting, our own generators already scale counts
PROCX particles_spawn, 32
    xor      r12d, r12d
    mov      eax, [rel p_internal]
    mov      dword [rel p_internal], 0
    cmp      ecx, PT_LAST
    ja       .done
    mov      ebx, ecx
    movss    xmm6, xmm1
    movss    xmm7, xmm2
    movss    xmm8, xmm3
    test     eax, eax
    jnz      .keep
    mov      eax, [rel g_settings+SETTINGS.particles]
    cmp      eax, 2
    jae      .keep
    mov      esi, eax
    mov      ecx, 3
    call     atm_randint
    test     esi, esi
    jnz      .decreased
    test     eax, eax                   ; minimal: keep 1 of 3
    jnz      .done
    jmp      .keep
.decreased:
    test     eax, eax
    jz       .done
.keep:
    mov      eax, [rel g_particle_count]
    cmp      eax, MAX_PARTICLES
    jae      .done
    lea      ecx, [rax+1]
    mov      [rel g_particle_count], ecx
    imul     eax, eax, PARTICLE_size
    lea      rdi, [rel g_particles]
    add      rdi, rax
    movss    [rdi+PARTICLE.x], xmm6
    movss    [rdi+PARTICLE.y], xmm7
    movss    [rdi+PARTICLE.z], xmm8
    mov      eax, ARG5
    mov      [rdi+PARTICLE.vx], eax
    mov      eax, ARG6
    mov      [rdi+PARTICLE.vy], eax
    mov      eax, ARG7
    mov      [rdi+PARTICLE.vz], eax
    lea      r13, [rel ptype]
    mov      eax, ebx
    shl      eax, 5
    add      r13, rax
    call     atm_randf
    mulss    xmm0, [r13+8]
    addss    xmm0, [r13+4]
    movss    [rdi+PARTICLE.size], xmm0
    call     atm_randf
    mulss    xmm0, [r13+16]
    addss    xmm0, [r13+12]
    movss    [rdi+PARTICLE.life], xmm0
    movss    [rdi+PARTICLE.max_life], xmm0
    mov      eax, [r13+20]
    mov      [rdi+PARTICLE.gravity], eax
    mov      [rdi+PARTICLE.type], bl
    mov      eax, [r13]
    mov      [rdi+PARTICLE.tile], al
    mov      word [rdi+PARTICLE.uoff], 0
    mov      eax, [r13+24]
    mov      [rdi+PARTICLE.color], eax
    mov      eax, ARG8
    cmp      ebx, PT_BLOCK
    je       .block
    test     eax, eax
    jz       .ok
    mov      [rdi+PARTICLE.tile], al
    jmp      .ok
.block:
    ; random face of the block -> tile, random 4x4 texel window
    movzx    esi, al
    mov      ecx, 6
    call     atm_randint
    lea      ecx, [rsi+rsi*2]
    lea      ecx, [rax+rcx*2]
    lea      rax, [rel blk_tex]
    movzx    r14d, byte [rax+rcx]
    mov      [rdi+PARTICLE.tile], r14b
    mov      ecx, 13
    call     atm_randint
    mov      [rdi+PARTICLE.uoff], al
    mov      ecx, 13
    call     atm_randint
    mov      [rdi+PARTICLE.voff], al
    ; biome tint for greyscale tiles (grass tops, leaves, plants)
    lea      rax, [rel blk_tint]
    movzx    eax, byte [rax+rsi]
    test     eax, eax
    jz       .ok
    cmp      r14d, T_GRASS_SIDE
    je       .ok
    cmp      r14d, T_SNOWY_GRASS_SIDE
    je       .ok
    cmp      r14d, T_DIRT
    je       .ok
    FLOORI   edx, xmm6, xmm0
    FLOORI   r8d, xmm8, xmm0
    mov      ecx, esi
    call     p_tint
    mov      [rdi+PARTICLE.color], eax
.ok:
    mov      r12, rdi
.done:
    mov      rax, r12
ENDPX

FUNCX p_tint, 0
    lea      rax, [rel blk_tint]
    movzx    ebx, byte [rax+rcx]
    mov      eax, 0xFFFFFFFF
    cmp      ebx, TINT_PINE
    jne      .np
    mov      eax, 0xFF619961
    jmp      .done
.np:
    cmp      ebx, TINT_BIRCH
    jne      .nb
    mov      eax, 0xFF55A780
    jmp      .done
.nb:
    cmp      ebx, TINT_GRASS
    je       .biome
    cmp      ebx, TINT_FOLIAGE
    je       .biome
    cmp      ebx, TINT_WATER
    jne      .done
.biome:
    mov      ecx, edx
    mov      edx, r8d
    call     world_get_biome
    cmp      eax, BIOME_COUNT
    jb       .bok
    mov      eax, BIOME_PLAINS
.bok:
    lea      rcx, [rel biome_grass_color]
    cmp      ebx, TINT_FOLIAGE
    jne      .nf
    lea      rcx, [rel biome_foliage_color]
.nf:
    cmp      ebx, TINT_WATER
    jne      .nw
    lea      rcx, [rel biome_water_color]
.nw:
    mov      eax, [rcx+rax*4]
    or       eax, 0xFF000000
.done:
ENDPX

; bypasses the density filter
FUNCX p_spawn_s, 32
    mov      dword [rel p_internal], 1
    movss    xmm1, [rel sp_x]
    movss    xmm2, [rel sp_y]
    movss    xmm3, [rel sp_z]
    mov      eax, [rel sp_vx]
    mov      [rsp+32], rax
    mov      eax, [rel sp_vy]
    mov      [rsp+40], rax
    mov      eax, [rel sp_vz]
    mov      [rsp+48], rax
    mov      eax, [rel sp_param]
    mov      [rsp+56], rax
    call     particles_spawn
ENDPX

; p_face_point: random point just outside that face, block-local
FUNCX p_face_point, 0
    lea      rbx, [rel face_n]
    imul     ecx, ecx, 12
    add      rbx, rcx
    lea      rsi, [rel fp_x]
    xor      edi, edi
.c:
    movss    xmm6, [rbx+rdi*4]
    movss    xmm0, xmm6
    FCONST   xmm1, 0.53
    mulss    xmm0, xmm1
    addss    xmm0, [rel c_half]
    movss    xmm7, xmm0
    xorps    xmm1, xmm1
    ucomiss  xmm6, xmm1
    jne      .store
    call     atm_randfs
    FCONST   xmm1, 0.45
    mulss    xmm0, xmm1
    addss    xmm7, xmm0
.store:
    movss    [rsi+rdi*4], xmm7
    inc      edi
    cmp      edi, 3
    jb       .c
ENDPX

; -> eax blk_flags, edx block id
FUNCX p_cell_flags, 0
    call     world_get_block
    movzx    edx, al
    lea      rcx, [rel blk_flags]
    movzx    eax, word [rcx+rdx*2]
ENDPX

PROCX particles_spawn_block_break, 32
    mov      r9d, r9d                   ; win64 leaves the upper half of an int arg as garbage
    test     r9d, r9d
    jz       .done
    cmp      r9d, 255
    ja       .done
    mov      [rsp+FRAME_OUT], r9d
    lea      rax, [rel blk_flags]
    movzx    eax, word [rax+r9*2]
    test     eax, BF_LIQUID
    jnz      .done
    cvtsi2ss xmm12, ecx
    cvtsi2ss xmm13, edx
    cvtsi2ss xmm14, r8d
    mov      eax, [rel g_settings+SETTINGS.particles]
    cmp      eax, 2
    jbe      .lv
    mov      eax, 2
.lv:
    lea      rcx, [rel grid_tab]
    mov      r15d, [rcx+rax*4]
    cvtsi2ss xmm15, r15d
    movss    xmm0, [rel c_one]
    divss    xmm0, xmm15
    movss    xmm15, xmm0
    mov      eax, [rsp+FRAME_OUT]
    mov      [rel sp_param], eax
    xor      r12d, r12d
.i:
    xor      r13d, r13d
.j:
    xor      r14d, r14d
.k:
    cvtsi2ss xmm6, r12d
    addss    xmm6, [rel c_half]
    mulss    xmm6, xmm15
    cvtsi2ss xmm7, r13d
    addss    xmm7, [rel c_half]
    mulss    xmm7, xmm15
    cvtsi2ss xmm8, r14d
    addss    xmm8, [rel c_half]
    mulss    xmm8, xmm15
    movss    xmm0, xmm12
    addss    xmm0, xmm6
    movss    [rel sp_x], xmm0
    movss    xmm0, xmm13
    addss    xmm0, xmm7
    movss    [rel sp_y], xmm0
    movss    xmm0, xmm14
    addss    xmm0, xmm8
    movss    [rel sp_z], xmm0
    ; outward + jitter + a small hop. with gravity 16 the crumbs only pop ~0.1-0.15
    ; and land around the block instead of fountaining all over your screen
    FCONST   xmm9, 1.5
    subss    xmm6, [rel c_half]
    mulss    xmm6, xmm9
    call     atm_randfs
    FCONST   xmm1, 0.5
    mulss    xmm0, xmm1
    addss    xmm6, xmm0
    movss    [rel sp_vx], xmm6
    subss    xmm8, [rel c_half]
    mulss    xmm8, xmm9
    call     atm_randfs
    FCONST   xmm1, 0.5
    mulss    xmm0, xmm1
    addss    xmm8, xmm0
    movss    [rel sp_vz], xmm8
    subss    xmm7, [rel c_half]
    mulss    xmm7, xmm9
    call     atm_randf
    FCONST   xmm1, 1.0
    mulss    xmm0, xmm1
    addss    xmm7, xmm0
    FCONST   xmm1, 0.8
    addss    xmm7, xmm1
    movss    [rel sp_vy], xmm7
    mov      ecx, PT_BLOCK
    call     p_spawn_s
    inc      r14d
    cmp      r14d, r15d
    jb       .k
    inc      r13d
    cmp      r13d, r15d
    jb       .j
    inc      r12d
    cmp      r12d, r15d
    jb       .i
.done:
ENDPX

PROCX particles_spawn_block_hit, 32
    mov      r12d, ecx
    mov      r13d, edx
    mov      r14d, r8d
    mov      r15d, r9d
    cmp      r15d, 5
    ja       .done
    call     world_get_block
    test     eax, eax
    jz       .done
    mov      esi, eax
    lea      rcx, [rel blk_flags]
    movzx    eax, word [rcx+rsi*2]
    test     eax, BF_LIQUID
    jnz      .done
    mov      [rel sp_param], esi
    mov      ebx, 2
    cmp      dword [rel g_settings+SETTINGS.particles], 0
    jne      .n
    mov      ebx, 1
.n:
    lea      rdi, [rel face_n]
    mov      eax, r15d
    imul     eax, eax, 12
    add      rdi, rax
.p:
    mov      ecx, r15d
    call     p_face_point
    cvtsi2ss xmm0, r12d
    addss    xmm0, [rel fp_x]
    movss    [rel sp_x], xmm0
    cvtsi2ss xmm0, r13d
    addss    xmm0, [rel fp_y]
    movss    [rel sp_y], xmm0
    cvtsi2ss xmm0, r14d
    addss    xmm0, [rel fp_z]
    movss    [rel sp_z], xmm0
    FCONST   xmm6, 0.9
    call     atm_randfs
    FCONST   xmm1, 0.5
    mulss    xmm0, xmm1
    movss    xmm1, [rdi]
    mulss    xmm1, xmm6
    addss    xmm0, xmm1
    movss    [rel sp_vx], xmm0
    call     atm_randf
    FCONST   xmm1, 0.8
    mulss    xmm0, xmm1
    movss    xmm1, [rdi+4]
    mulss    xmm1, xmm6
    addss    xmm0, xmm1
    FCONST   xmm1, 0.5
    addss    xmm0, xmm1
    movss    [rel sp_vy], xmm0
    call     atm_randfs
    FCONST   xmm1, 0.5
    mulss    xmm0, xmm1
    movss    xmm1, [rdi+8]
    mulss    xmm1, xmm6
    addss    xmm0, xmm1
    movss    [rel sp_vz], xmm0
    mov      ecx, PT_BLOCK
    call     p_spawn_s
    test     rax, rax
    jz       .next
    movss    xmm0, [rax+PARTICLE.size]
    FCONST   xmm1, 0.6
    mulss    xmm0, xmm1
    movss    [rax+PARTICLE.size], xmm0
    mov      r8, rax
    call     atm_randf
    FCONST   xmm1, 0.4
    mulss    xmm0, xmm1
    FCONST   xmm1, 0.3
    addss    xmm0, xmm1
    movss    [r8+PARTICLE.life], xmm0
    movss    [r8+PARTICLE.max_life], xmm0
.next:
    dec      ebx
    jnz      .p
.done:
ENDPX

; fireball, dark smoke shoved outward, sparks
PROCX particles_spawn_explosion, 32
    movss    xmm12, xmm0
    movss    xmm13, xmm1
    movss    xmm14, xmm2
    movss    xmm15, xmm3
    FCONST   xmm0, 0.5
    maxss    xmm15, xmm0
    FCONST   xmm0, 10.0
    minss    xmm15, xmm0
    mov      eax, [rel g_settings+SETTINGS.particles]
    cmp      eax, 2
    jbe      .lv
    mov      eax, 2
.lv:
    lea      rcx, [rel dens_tab]
    movss    xmm11, [rcx+rax*4]
    mov      dword [rel sp_param], 0

    FCONST   xmm0, 6.0
    mulss    xmm0, xmm15
    FCONST   xmm1, 8.0
    addss    xmm0, xmm1
    mulss    xmm0, xmm11
    cvttss2si ebx, xmm0
    inc      ebx
.puff:
    FCONST   xmm10, 0.7
    mulss    xmm10, xmm15
    call     .randpos
    call     atm_randfs
    movss    [rel sp_vx], xmm0
    call     atm_randfs
    FCONST   xmm1, 0.4
    addss    xmm0, xmm1
    movss    [rel sp_vy], xmm0
    call     atm_randfs
    movss    [rel sp_vz], xmm0
    mov      ecx, PT_EXPLOSION
    call     p_spawn_s
    dec      ebx
    jnz      .puff

