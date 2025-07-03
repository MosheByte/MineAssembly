; particle pool + sim against the all-air stub world. blk_flags[0] = BF_SOLID
; makes the whole stub world solid for the collision tests. group order
; matters, the rng state carries over.
; @link src/sky.asm src/particles.asm src/weather.asm tests/atmosphere/atmo_lib.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../atmosphere/atmo.inc"

section .text

setup:
    sub      rsp, 40
    call     atmo_reset_env
    call     particles_init
    mov      dword [rel g_world_active], 1
    add      rsp, 40
    ret

%macro UPDATE 1
    LDF      xmm0, %1
    call     particles_update
%endmacro

; pool[0].field, pool base lives in r14
%define P0(f) [r14 + PARTICLE.%+f]

PROCX test_main, 64
    call     atmo_pool
    mov      r14, rax                   ; for the whole run

    TEST "block_break_counts"
    call     setup
    lea      rax, [rel blk_tex]
    mov      byte [rax + 5*6 + 2], 77
    xor      r12d, r12d
.bb_case:
    call     particles_clear
    lea      rax, [rel bb_cases]
    mov      ecx, [rax + r12*8]
    mov      r13d, [rax + r12*8 + 4]
    mov      [rel g_settings + SETTINGS.particles], ecx
    mov      ecx, 10
    mov      edx, 20
    mov      r8d, 30
    mov      r9d, 5
    call     particles_spawn_block_break
    CHECK_EQ32 [rel g_particle_count], r13d, "block break particle count for the setting"
    ; fold the per-particle checks into two flags
    mov      rsi, r14
    mov      edi, r13d
    xorps    xmm9, xmm9
    mov      dword LOC(0), 1            ; type/box/uv ok
    mov      dword LOC(4), 1            ; size/velocity ok
.bb_each:
    cmp      byte [rsi + PARTICLE.type], PT_BLOCK
    jne      .bb_bad1
    LDF      xmm0, 10.0
    LDF      xmm1, 11.0
    movss    xmm2, [rsi + PARTICLE.x]
    comiss   xmm2, xmm0
    jb       .bb_bad1
    comiss   xmm1, xmm2
    jb       .bb_bad1
    LDF      xmm0, 20.0
    LDF      xmm1, 21.0
    movss    xmm2, [rsi + PARTICLE.y]
    comiss   xmm2, xmm0
    jb       .bb_bad1
    comiss   xmm1, xmm2
    jb       .bb_bad1
    LDF      xmm0, 30.0
    LDF      xmm1, 31.0
    movss    xmm2, [rsi + PARTICLE.z]
    comiss   xmm2, xmm0
    jb       .bb_bad1
    comiss   xmm1, xmm2
    jb       .bb_bad1
    cmp      byte [rsi + PARTICLE.uoff], 12
    ja       .bb_bad1
    cmp      byte [rsi + PARTICLE.voff], 12
    ja       .bb_bad1
    jmp      .bb_ok1
.bb_bad1:
    mov      dword LOC(0), 0
.bb_ok1:
    ; size is a half extent
    movss    xmm2, [rsi + PARTICLE.size]
    LDF      xmm0, 0.05
    comiss   xmm2, xmm0
    jb       .bb_bad2
    LDF      xmm0, 0.096
    comiss   xmm0, xmm2
    jb       .bb_bad2
    movss    xmm2, [rsi + PARTICLE.vy]
    addss    xmm9, xmm2
    LDF      xmm0, 2.4
    comiss   xmm0, xmm2
    jbe      .bb_bad2
    mov      eax, 0x7FFFFFFF
    movd     xmm3, eax
    LDF      xmm0, 1.1
    movss    xmm2, [rsi + PARTICLE.vx]
    andps    xmm2, xmm3
    comiss   xmm0, xmm2
    jbe      .bb_bad2
    movss    xmm2, [rsi + PARTICLE.vz]
    andps    xmm2, xmm3
    comiss   xmm0, xmm2
    jbe      .bb_bad2
    jmp      .bb_ok2
.bb_bad2:
    mov      dword LOC(4), 0
.bb_ok2:
    add      rsi, PARTICLE_size
    dec      edi
    jnz      .bb_each
    CHECK_TRUE LOC(0), "debris: PT_BLOCK inside the block, uv offsets <= 12"
    CHECK_TRUE LOC(4), "debris: size 0.05..0.096, vy < 2.4, |vx|,|vz| < 1.1"
    cvtsi2ss xmm0, r13d
    divss    xmm9, xmm0
    LDF      xmm0, 0.5
    CHECK_GT xmm9, xmm0, "debris is thrown up (mean vy > 0.5)"
    inc      r12d
    cmp      r12d, 3
    jb       .bb_case
    call     particles_clear
    xor      ecx, ecx
    xor      edx, edx
    xor      r8d, r8d
    xor      r9d, r9d
    call     particles_spawn_block_break
    CHECK_EQ32 [rel g_particle_count], 0, "breaking air spawns nothing"

    TEST "block_tint"
    call     setup
    lea      rax, [rel blk_tint]
    mov      byte [rax + 10], 3         ; TINT_PINE
    lea      rax, [rel blk_tex]
    mov      dword [rax + 10*6], 0x0B0B0B0B   ; faces 0..3 = tile 11
    mov      word  [rax + 10*6 + 4], 0x0B0B   ; faces 4..5
    xor      ecx, ecx
    xor      edx, edx
    xor      r8d, r8d
    mov      r9d, 10
    call     particles_spawn_block_break
    CHECK_EQ32 P0(color), 0xFF619961, "pine-tinted debris colour"
    lea      rax, [rel blk_tint]
    mov      byte [rax + 10], 0

    TEST "bubble_pops_out_of_water"
    call     setup
    SPAWN    PT_BUBBLE, 0.5, 10.5, 0.5, 0.0, 0.0, 0.0, 0    ; stub world = air
    UPDATE   0.01
    CHECK_EQ32 [rel g_particle_count], 0, "bubble in air pops"

    TEST "buoyant_smoke_rises"
    call     setup
    SPAWN    PT_SMOKE, 0.5, 20.0, 0.5, 0.0, 0.0, 0.0, 0
    mov      ebx, 10
.sm_loop:
    UPDATE   0.05
    dec      ebx
    jnz      .sm_loop
    movss    xmm6, P0(y)
    LDF      xmm0, 20.0
    CHECK_GT xmm6, xmm0, "smoke rises"

    TEST "death_and_swap_remove"
    call     setup
    xor      ebx, ebx
.ds_spawn:
    cvtsi2ss xmm1, ebx
    LDF      xmm2, 10.5
    LDF      xmm3, 0.5
    xor      eax, eax
    mov      [rsp+32], rax
    mov      [rsp+40], rax
    mov      [rsp+48], rax
    mov      [rsp+56], rax
    mov      ecx, PT_CRIT
    call     particles_spawn
    inc      ebx
    cmp      ebx, 10
    jb       .ds_spawn
    xor      ebx, ebx
.ds_kill:
    imul     eax, ebx, PARTICLE_size
    SETF     [r14 + rax + PARTICLE.life], 0.001
    add      ebx, 2
    cmp      ebx, 10
    jb       .ds_kill
    UPDATE   0.01
    CHECK_EQ32 [rel g_particle_count], 5, "5 survivors after the even ones die"
    ; bitset of survivor x
    xor      r12d, r12d
    xor      ebx, ebx
    mov      r13d, 1
.ds_x:
    imul     eax, ebx, PARTICLE_size
    movss    xmm0, [r14 + rax + PARTICLE.x]
    cvttss2si ecx, xmm0
    cvtsi2ss xmm1, ecx
    ucomiss  xmm0, xmm1
    jne      .ds_xbad
    jp       .ds_xbad
    cmp      ecx, 31
    ja       .ds_xbad
    bts      r12d, ecx
    jmp      .ds_xnext
.ds_xbad:
    xor      r13d, r13d
.ds_xnext:
    inc      ebx
    cmp      ebx, 5
    jb       .ds_x
    CHECK_TRUE r13d, "survivor x values unchanged"
    CHECK_EQ32 r12d, 0x2AA, "survivors are x = 1,3,5,7,9 (swap remove)"
    UPDATE   5.0                        ; dt is clamped to 0.1
    CHECK_EQ32 [rel g_particle_count], 5, "huge dt is clamped (nobody dies)"
    mov      ebx, 20
.ds_age:
    UPDATE   0.1
    dec      ebx
    jnz      .ds_age
    CHECK_EQ32 [rel g_particle_count], 0, "all crits expire within 2 s"

    TEST "explosion"
    call     setup
    xorps    xmm0, xmm0
    LDF      xmm1, 64.0
    xorps    xmm2, xmm2
    LDF      xmm3, 4.0
    call     particles_spawn_explosion
    COUNT_TYPE PT_EXPLOSION
    CHECK_TRUE eax, "explosion puffs spawned"
    COUNT_TYPE PT_SMOKE
    CHECK_TRUE eax, "explosion smoke spawned"
    COUNT_TYPE PT_SPARK
    CHECK_TRUE eax, "explosion sparks spawned"
    mov      eax, [rel g_particle_count]
    xor      ecx, ecx
    cmp      eax, 60
    setg     cl
    CHECK_TRUE ecx, "explosion spawns more than 60 particles"
    mov      ebx, 100
.ex_loop:
    UPDATE   0.05
    dec      ebx
    jnz      .ex_loop
    CHECK_EQ32 [rel g_particle_count], 0, "explosion particles gone after 5 s"

    TEST "external_filter"
    call     setup
    mov      dword [rel g_settings + SETTINGS.particles], 0
    mov      ebx, 3000
.ef_loop:
    SPAWN    PT_CRIT, 0.5, 10.5, 0.5, 0.0, 0.0, 0.0, 0
    dec      ebx
    jnz      .ef_loop
    mov      ebx, [rel g_particle_count]
    PRINT    "  kept of 3000: "
    mov      ecx, ebx
    call     t_print_int
    call     t_newline
    xor      eax, eax
    cmp      ebx, 800
    jle      .ef_no
    cmp      ebx, 1200
    jge      .ef_no
    mov      eax, 1
.ef_no:
    CHECK_TRUE eax, "minimal setting keeps ~1/3 (800 < n < 1200)"

    TEST "floor_collision"
    call     setup
    lea      rax, [rel blk_flags]
    mov      word [rax], BF_SOLID
    SPAWN    PT_BLOCK, 0.5, 5.5, 0.5, 0.0, -8.0, 0.0, 1
    SETF     P0(life), 10.0
    SETF     P0(max_life), 10.0
    mov      ebx, 60
    mov      r12d, 1
.fc_loop:
    UPDATE   0.02
    movss    xmm0, P0(y)
    LDF      xmm1, 5.0
    comiss   xmm0, xmm1
    jae      .fc_ok
    xor      r12d, r12d
.fc_ok:
    dec      ebx
    jnz      .fc_loop
    CHECK_TRUE r12d, "debris never sinks below the floor (y >= 5)"
    CHECK_NEAR P0(y), 5.002, 0.0005, "debris rests at y 5.002"
    movss    xmm6, P0(vy)
    CHECK_FEQ xmm6, 0.0, "resting debris has vy 0"

    TEST "gravity_and_free_fall"
    call     setup
    SPAWN    PT_SPARK, 0.5, 50.0, 0.5, 0.0, 0.0, 0.0, 0
    SETF     P0(life), 10.0
    SETF     P0(max_life), 10.0
    movss    xmm6, P0(y)
    mov      ebx, 10
.gf_loop:
    UPDATE   0.05
    dec      ebx
    jnz      .gf_loop
    movss    xmm7, P0(vy)
    LDF      xmm0, -3.0
    CHECK_LT xmm7, xmm0, "falling spark vy < -3"
    movss    xmm7, P0(y)
    LDF      xmm0, 1.0
    subss    xmm6, xmm0
    CHECK_LT xmm7, xmm6, "spark fell more than 1 block"

    TEST "invalid_type_rejected"
    call     setup
    SPAWN    42, 0.5, 10.5, 0.5, 0.0, 0.0, 0.0, 0
    CHECK_EQ rax, 0, "spawn(42) returns null"
    CHECK_EQ32 [rel g_particle_count], 0, "nothing spawned for an invalid type"

    TEST "pool_cap"
    call     setup
    mov      ebx, MAX_PARTICLES + 500
.pc_loop:
    SPAWN    PT_CRIT, 0.5, 10.5, 0.5, 0.0, 0.0, 0.0, 0
    dec      ebx
    jnz      .pc_loop
    CHECK_EQ32 [rel g_particle_count], MAX_PARTICLES, "pool capped at MAX_PARTICLES"
    SPAWN    PT_CRIT, 0.5, 10.5, 0.5, 0.0, 0.0, 0.0, 0
    CHECK_EQ rax, 0, "spawn into a full pool returns null"

    TEST "rain_dies_on_impact_and_splashes"
    call     setup
    lea      rax, [rel blk_flags]
    mov      word [rax], BF_SOLID
    xor      r12d, r12d
    mov      ebx, 50
.rd_loop:
    call     particles_clear
    SPAWN    PT_RAIN, 0.5, 5.5, 0.5, 0.0, -16.0, 0.0, 0
    UPDATE   0.05
    COUNT_TYPE PT_RAIN
    CHECK_EQ32 eax, 0, "rain drop dies on impact"
    COUNT_TYPE PT_SPLASH
    add      r12d, eax
    dec      ebx
    jnz      .rd_loop
    PRINT    "  splashes of 50: "
    mov      ecx, r12d
    call     t_print_int
    call     t_newline
    xor      eax, eax
    cmp      r12d, 5
    jle      .rd_no
    cmp      r12d, 40
    jge      .rd_no
    mov      eax, 1
.rd_no:
    CHECK_TRUE eax, "~40% of impacts splash (5 < hits < 40)"

    TEST "render_and_ambient_smoke" ; v1: test_particles scratch #0
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_particles:0)
    call     setup ; v1: test_particles scratch #1
    xor      ebx, ebx ; v1: test_particles scratch #2
    ; TODO: hoist invariant pointer load out of .loop (test_particles:2)
.ra_spawn: ; v1: test_particles scratch #3
    cvtsi2ss xmm1, ebx ; v1: test_particles scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (test_particles:4)
    LDF      xmm0, 0.5 ; v1: test_particles scratch #5
    addss    xmm1, xmm0 ; v1: test_particles scratch #6
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_particles:6)
    LDF      xmm2, 10.0 ; v1: test_particles scratch #7
    LDF      xmm3, -5.0 ; v1: test_particles scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_particles:8)
    mov      qword [rsp+32], 0 ; v1: test_particles scratch #9
    SETF     [rsp+40], 1.0 ; v1: test_particles scratch #10
    ; TODO: clamp index before table lookup on malformed input (test_particles:10)
    mov      qword [rsp+48], 0 ; v1: test_particles scratch #11
    xor      eax, eax ; v1: test_particles scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_particles:12)
    test     ebx, ebx ; v1: test_particles scratch #13
    sete     al ; v1: test_particles scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_particles:14)
    mov      [rsp+56], rax ; v1: test_particles scratch #15
    mov      ecx, ebx ; v1: test_particles scratch #16
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_particles:16)
    call     particles_spawn ; v1: test_particles scratch #17
    inc      ebx ; v1: test_particles scratch #18
    ; TODO: hoist invariant pointer load out of .loop (test_particles:18)
    cmp      ebx, 10 ; v1: test_particles scratch #19
    jb       .ra_spawn ; v1: test_particles scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (test_particles:20)
    xor      eax, eax ; v1: test_particles scratch #21
    mov      [rel g_cam_pos + 0], eax ; v1: test_particles scratch #22
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_particles:22)
    SETF     [rel g_cam_pos + 4], 10.0 ; v1: test_particles scratch #23
    mov      [rel g_cam_pos + 8], eax ; v1: test_particles scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_particles:24)
    call     particles_render ; v1: test_particles scratch #25
    mov      ebx, 30 ; v1: test_particles scratch #26
    ; TODO: clamp index before table lookup on malformed input (test_particles:26)
.ra_loop: ; v1: test_particles scratch #27
    call     particles_ambient_tick ; v1: test_particles scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_particles:28)
    UPDATE   0.05 ; v1: test_particles scratch #29
    dec      ebx ; v1: test_particles scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_particles:30)
    jnz      .ra_loop ; v1: test_particles scratch #31
    CHECK_TRUE 1, "render + ambient ticks completed" ; v1: test_particles scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_particles:32)

    TEST "spawn_fields"
    call     setup
    SPAWN    PT_SMOKE, 1.0, 2.0, 3.0, 0.1, 0.2, 0.3, 0
    xor      ecx, ecx
    test     rax, rax
    setnz    cl
    CHECK_TRUE ecx, "spawn returns the particle"
    CHECK_EQ32 [rel g_particle_count], 1, "one particle live"
    movss    xmm6, P0(x)
    CHECK_FEQ xmm6, 1.0, "x stored"
    movss    xmm6, P0(y)
    CHECK_FEQ xmm6, 2.0, "y stored"
    movss    xmm6, P0(z)
    CHECK_FEQ xmm6, 3.0, "z stored"
    CHECK_NEAR P0(vy), 0.2, 0.0000005, "vy stored"
    movzx    eax, byte P0(type)
    CHECK_EQ32 eax, PT_SMOKE, "type stored"
    movzx    eax, byte P0(tile)
    CHECK_EQ32 eax, T_PARTICLE_SMOKE, "default smoke tile (178)"
    movss    xmm6, P0(life)
    CHECK_RANGE xmm6, 1.4, 2.8, "smoke life 1.4..2.8 s"
    movss    xmm7, P0(max_life)
    ucomiss  xmm6, xmm7
    sete     al
    setnp    cl
    and      al, cl
    movzx    eax, al
    CHECK_TRUE eax, "life == max_life at spawn"
    SPAWN    PT_FLAME, 0.5, 10.5, 0.5, 0.0, 0.0, 0.0, 99
    movzx    eax, byte [r14 + PARTICLE_size + PARTICLE.tile]
    CHECK_EQ32 eax, 99, "param overrides the tile"

    TEST "wall_reflects"
    call     setup
    lea      rax, [rel blk_flags]
    mov      word [rax], BF_SOLID
    SPAWN    PT_SPARK, 0.5, 5.5, 0.5, 10.0, 0.0, 0.0, 0
    SETF     P0(gravity), 0.0
    UPDATE   0.1                        ; would cross into x = 1
    movss    xmm6, P0(x)
    LDF      xmm0, 1.0
    CHECK_LT xmm6, xmm0, "spark stays out of the wall (x < 1)"
    movss    xmm6, P0(vx)
    xorps    xmm0, xmm0
    CHECK_LT xmm6, xmm0, "spark bounced (vx < 0)"
ENDPX

section .rdata
align 4
; particles setting, expected debris
bb_cases:   dd 2, 64,  1, 27,  0, 8
    ; v1 temporary guard (test_particles #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (test_particles #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_particles #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_particles #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_particles #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_particles #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_particles #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_particles #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_particles #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_particles #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_particles #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_particles #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_particles #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_particles #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_particles #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_particles #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_particles #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_particles #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (test_particles #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (test_particles #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (test_particles #57)
    xor     r11d, r11d ; clear v1 slot 57
