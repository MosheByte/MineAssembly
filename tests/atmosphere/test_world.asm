; atmosphere vs a tiny programmable world (world_fake.asm). fw_blocks is
; x + z*64 + y*4096, x/z wrap mod 64.
; @link src/sky.asm src/particles.asm src/weather.asm
; @link tests/atmosphere/atmo_lib.asm tests/atmosphere/world_fake.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../atmosphere/atmo.inc"

extern fw_blocks, fw_light

%define FW_SIZE     (64*64*128)

section .rdata
align 8
k_y_min_land:   dq 60.9999              ; 61 - 1e-4

section .text

setup:
    push     rdi
    sub      rsp, 32
    lea      rdi, [rel fw_blocks]
    xor      eax, eax
    mov      ecx, FW_SIZE / 8
    rep stosq
    lea      rdi, [rel blk_flags]
    mov      ecx, 256
    rep stosw
    lea      rax, [rel blk_flags]
    mov      word [rax + B_STONE*2], BF_SOLID | BF_OPAQUE
    mov      word [rax + B_WATER*2], BF_LIQUID
    mov      word [rax + B_LAVA*2], BF_LIQUID
    mov      dword [rel fw_light], 0xF0
    mov      dword [rel g_settings + SETTINGS.particles], 2
    mov      dword [rel g_settings + SETTINGS.render_dist], 8
    mov      dword [rel g_player + PLAYER.eye_in_water], 0
    SETF     [rel biome_temperature], 0.8
    mov      dword [rel g_world_active], 1
    xor      eax, eax
    mov      [rel g_rain], eax
    mov      [rel g_thunder], eax
    mov      [rel g_lightning], eax
    call     particles_init
    add      rsp, 32
    pop      rdi
    ret

; no wrapping here, x/z must be 0..63
put:
    shl      edx, 12
    shl      r8d, 6
    add      ecx, edx
    add      ecx, r8d
    lea      rax, [rel fw_blocks]
    mov      [rax + rcx], r9b
    ret

layer:
    push     rdi
    mov      eax, edx
    mov      edi, ecx
    shl      edi, 12
    lea      rdx, [rel fw_blocks]
    add      rdi, rdx
    mov      ecx, 4096
    rep stosb
    pop      rdi
    ret

; eax = 1 if every live particle has y >= xmm0
all_live_y_ge:
    sub      rsp, 40
    movss    [rsp+32], xmm0
    call     atm_particles_base
    movss    xmm0, [rsp+32]
    mov      ecx, [rel g_particle_count]
    mov      edx, 1
.l:
    test     ecx, ecx
    jle      .d
    comiss   xmm0, [rax + PARTICLE.y]
    jbe      .ok
    xor      edx, edx
.ok:
    add      rax, PARTICLE_size
    dec      ecx
    jmp      .l
.d:
    mov      eax, edx
    add      rsp, 40
    ret

player_at:
    movss    [rel g_player + PLAYER.x], xmm0
    movss    [rel g_player + PLAYER.y], xmm1
    movss    [rel g_player + PLAYER.z], xmm2
    ret

%macro PUT 4
    mov      ecx, %1
    mov      edx, %2
    mov      r8d, %3
    mov      r9d, %4
    call     put
%endmacro

%macro UPDATE 1
    LDF      xmm0, %1
    call     particles_update
%endmacro

%define P0(f) [r14 + PARTICLE.%+f]

PROCX test_main, 64
    call     atmo_pool
    mov      r14, rax

    TEST "absurd_velocity_is_dropped"
    call     setup
    SPAWN    PT_SPARK, 10.5, 60.5, 10.5, 0.0, -1.0e6, 0.0, 0
    UPDATE   0.1
    CHECK_EQ32 [rel g_particle_count], 0, "particle with |v| = 1e6 is dropped"

    TEST "block_break_ignores_garbage_upper_bits"
    ; win64 makes no promises about the top half of a 32-bit arg
    call     setup
    mov      rcx, 0xDEADBEEF0000000A
    mov      rdx, 0xDEADBEEF0000000A
    mov      r8,  0xDEADBEEF0000000A
    mov      r9,  0xDEADBEEF00000000 | B_STONE
    call     particles_spawn_block_break
    CHECK_EQ32 [rel g_particle_count], 64, "64 debris for stone despite garbage upper bits"
    COUNT_TYPE PT_BLOCK
    CHECK_EQ32 eax, 64, "all debris is PT_BLOCK"

    TEST "bubble_pops_at_the_surface"
    call     setup
    PUT      10, 10, 10, B_WATER
    PUT      10, 11, 10, B_WATER
    PUT      10, 12, 10, B_WATER
    SPAWN    PT_BUBBLE, 10.5, 10.2, 10.5, 0.0, 0.5, 0.0, 0
    SETF     P0(life), 30.0
    SETF     P0(max_life), 30.0
    mov      ebx, 200
    mov      r12d, 1
.bu_loop:
    UPDATE   0.05
    cmp      dword [rel g_particle_count], 0
    je       .bu_done
    LDF      xmm0, 13.5
    comiss   xmm0, P0(y)
    ja       .bu_ok
    xor      r12d, r12d
.bu_ok:
    dec      ebx
    jnz      .bu_loop
.bu_done:
    CHECK_TRUE r12d, "bubble never rises above the water (y < 13.5)"
    CHECK_EQ32 [rel g_particle_count], 0, "bubble pops at the surface"

    TEST "ceiling_stops_upward_motion"
    call     setup
    mov      ecx, 12
    mov      edx, B_STONE
    call     layer
    SPAWN    PT_SPARK, 10.5, 9.5, 10.5, 0.0, 40.0, 0.0, 0
    SETF     P0(life), 10.0
    SETF     P0(max_life), 10.0
    UPDATE   0.1
    movss    xmm6, P0(y)
    LDF      xmm0, 12.0
    CHECK_LT xmm6, xmm0, "spark stays below the ceiling"
    movss    xmm6, P0(vy)
    CHECK_FEQ xmm6, 0.0, "ceiling hit zeroes vy"

    TEST "fast_debris_lands_on_a_thin_floor"
    call     setup
    mov      ecx, 5
    mov      edx, B_STONE
    call     layer
    SPAWN    PT_BLOCK, 10.5, 7.5, 10.5, 0.0, -25.0, 0.0, B_STONE
    SETF     P0(life), 10.0
    SETF     P0(max_life), 10.0
    UPDATE   0.1
    CHECK_EQ32 [rel g_particle_count], 1, "debris survives the landing"
    CHECK_NEAR P0(y), 6.002, 0.0005, "debris lands on top of the floor"
    movss    xmm6, P0(vy)
    xorps    xmm0, xmm0
    CHECK_GT xmm6, xmm0, "debris bounced (vy > 0)"
    mov      ebx, 100
    mov      r12d, 1
.fd_loop:
    UPDATE   0.05
    LDF      xmm0, 6.0
    comiss   xmm0, P0(y)
    jbe      .fd_ok
    xor      r12d, r12d
.fd_ok:
    dec      ebx
    jnz      .fd_loop
    CHECK_TRUE r12d, "debris never falls through (y >= 6)"

    TEST "fast_rain_cannot_tunnel_a_thin_roof"
    call     setup
    mov      ecx, 5                     ; one block thick, air below
    mov      edx, B_STONE
    call     layer
    SPAWN    PT_RAIN, 10.5, 7.9, 10.5, 0.0, -30.0, 0.0, 0
    UPDATE   0.1                        ; would land at y = 4.9
    LDF      xmm0, 6.0
    call     all_live_y_ge
    CHECK_TRUE eax, "nothing tunnels below the roof (y >= 6)"
    COUNT_TYPE PT_RAIN
    CHECK_EQ32 eax, 0, "the drop died on the roof"

    TEST "lava_pops_sparks"
    call     setup
    LDF      xmm0, 20.5
    LDF      xmm1, 20.0
    LDF      xmm2, 20.5
    call     player_at
    mov      r12d, 8                    ; z
.lv_z:
    mov      r13d, 8                    ; x
.lv_x:
    PUT      r13d, 15, r12d, B_LAVA
    inc      r13d
    cmp      r13d, 33
    jb       .lv_x
    inc      r12d
    cmp      r12d, 33
    jb       .lv_z
    xor      r12d, r12d
    mov      ebx, 400
.lv_loop:
    call     particles_ambient_tick
    COUNT_TYPE PT_SPARK
    add      r12d, eax
    call     particles_clear
    dec      ebx
    jnz      .lv_loop
    CHECK_TRUE r12d, "a lava lake pops sparks"

    TEST "negative_coordinates_use_floor" ; v1: test_world scratch #0
    ; TODO: clamp index before table lookup on malformed input (test_world:0)
    ; (-4,5,-4) is column 60 in the wrapped grid. -3.5 has to floor to -4,
    ; truncating gives -3 (air) and it falls straight through
    call     setup ; v1: test_world scratch #3
    PUT      60, 5, 60, B_STONE ; v1: test_world scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_world:4)
    SPAWN    PT_BLOCK, -3.5, 7.5, -3.5, 0.0, -10.0, 0.0, B_STONE ; v1: test_world scratch #5
    SETF     P0(life), 10.0 ; v1: test_world scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_world:6)
    SETF     P0(max_life), 10.0 ; v1: test_world scratch #7
    mov      ebx, 20 ; v1: test_world scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_world:8)
    mov      r12d, 1 ; v1: test_world scratch #9
.nc_loop: ; v1: test_world scratch #10
    ; TODO: verify 16-byte rsp alignment before inner call (test_world:10)
    UPDATE   0.05 ; v1: test_world scratch #11
    LDF      xmm0, 6.0 ; v1: test_world scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_world:12)
    comiss   xmm0, P0(y) ; v1: test_world scratch #13
    jbe      .nc_ok ; v1: test_world scratch #14
    ; TODO: hoist invariant pointer load out of .loop (test_world:14)
    xor      r12d, r12d ; v1: test_world scratch #15
.nc_ok: ; v1: test_world scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_world:16)
    dec      ebx ; v1: test_world scratch #17
    jnz      .nc_loop ; v1: test_world scratch #18
    ; TODO: clamp index before table lookup on malformed input (test_world:18)
    CHECK_TRUE r12d, "debris at negative x/z lands on block (-4,5,-4)" ; v1: test_world scratch #19
    CHECK_NEAR P0(y), 6.002, 0.0005, "debris rests at y 6.002" ; v1: test_world scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_world:20)

    TEST "no_rain_under_a_roof" ; v1: test_world scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_world:22)
    call     setup ; v1: test_world scratch #23
    LDF      xmm0, 32.0 ; v1: test_world scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_world:24)
    LDF      xmm1, 64.0 ; v1: test_world scratch #25
    LDF      xmm2, 32.0 ; v1: test_world scratch #26
    ; TODO: verify 16-byte rsp alignment before inner call (test_world:26)
    call     player_at ; v1: test_world scratch #27
    mov      ecx, 100 ; v1: test_world scratch #28
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_world:28)
    mov      edx, B_STONE ; v1: test_world scratch #29
    call     layer ; v1: test_world scratch #30
    ; TODO: hoist invariant pointer load out of .loop (test_world:30)
    mov      ecx, 1 ; v1: test_world scratch #31
    call     weather_set ; v1: test_world scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_world:32)
    SETF     [rel g_rain], 1.0 ; v1: test_world scratch #33
    mov      ebx, 5 ; v1: test_world scratch #34
    ; TODO: clamp index before table lookup on malformed input (test_world:34)
.nr_loop: ; v1: test_world scratch #35
    call     weather_tick ; v1: test_world scratch #36
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_world:36)
    dec      ebx ; v1: test_world scratch #37
    jnz      .nr_loop ; v1: test_world scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_world:38)
    CHECK_EQ32 [rel g_particle_count], 0, "no rain under a roof" ; v1: test_world scratch #39

    TEST "rain_lands_on_the_ground_and_splashes"
    call     setup
    LDF      xmm0, 32.0
    LDF      xmm1, 61.0
    LDF      xmm2, 32.0
    call     player_at
    mov      ecx, 60
    mov      edx, B_STONE
    call     layer
    mov      ecx, 1
    call     weather_set
    SETF     [rel g_rain], 1.0
    call     weather_tick
    COUNT_TYPE PT_RAIN
    xor      ecx, ecx
    cmp      eax, 20
    setg     cl
    CHECK_TRUE ecx, "more than 20 drops over open ground"
    xor      r12d, r12d
    mov      r13d, 1
    mov      ebx, 40
.rl_loop:
    UPDATE   0.05
    cvtsd2ss xmm0, [rel k_y_min_land]
    call     all_live_y_ge
    and      r13d, eax
    COUNT_TYPE PT_SPLASH
    add      r12d, eax
    dec      ebx
    jnz      .rl_loop
    CHECK_TRUE r13d, "no particle sinks into the ground (y >= 61 - 1e-4)"
    CHECK_TRUE r12d, "rain splashes on the ground"
    COUNT_TYPE PT_RAIN
    CHECK_EQ32 eax, 0, "all drops landed"

    TEST "torch_emits_flames_at_its_tip"
    call     setup
    LDF      xmm0, 20.5
    LDF      xmm1, 20.0
    LDF      xmm2, 20.5
    call     player_at
    PUT      20, 20, 23, B_TORCH
    xor      r12d, r12d
    mov      r13d, 1
    mov      ebx, 60
.tf_loop:
    call     particles_ambient_tick
    mov      rsi, r14
    mov      edi, [rel g_particle_count]
.tf_each:
    test     edi, edi
    jz       .tf_next
    cmp      byte [rsi + PARTICLE.type], PT_FLAME
    jne      .tf_skip
    inc      r12d
    ; within 0.05 / 0.05 / 0.01 of the tip, compared as doubles
    mov      eax, 0x7FFFFFFF
    movd     xmm3, eax
    cvtss2sd xmm0, [rsi + PARTICLE.x]
    subsd    xmm0, [rel k_tip_x]
    cvtss2sd xmm1, [rsi + PARTICLE.z]
    subsd    xmm1, [rel k_tip_z]
    cvtss2sd xmm2, [rsi + PARTICLE.y]
    subsd    xmm2, [rel k_tip_y]
    andpd    xmm0, [rel k_abs_mask]
    andpd    xmm1, [rel k_abs_mask]
    andpd    xmm2, [rel k_abs_mask]
    comisd   xmm0, [rel k_d05]
    ja       .tf_bad
    comisd   xmm1, [rel k_d05]
    ja       .tf_bad
    comisd   xmm2, [rel k_d01]
    jbe      .tf_skip
.tf_bad:
    xor      r13d, r13d
.tf_skip:
    add      rsi, PARTICLE_size
    dec      edi
    jmp      .tf_each
.tf_next:
    dec      ebx
    jnz      .tf_loop
    PRINT    "  flame samples: "
    mov      ecx, r12d
    call     t_print_int
    call     t_newline
    CHECK_TRUE r12d, "a torch emits flames"
    CHECK_TRUE r13d, "flames sit at the torch tip (20.5, 20.69, 23.5)"
    PUT      20, 20, 23, 0
    call     particles_ambient_tick
    call     particles_clear
    mov      ebx, 40
.tf_gone:
    call     particles_ambient_tick
    dec      ebx
    jnz      .tf_gone
    COUNT_TYPE PT_FLAME
    CHECK_EQ32 eax, 0, "no flames once the torch is gone"

    ; v1 temporary guard (test_world #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_world #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_world #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_world #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_world #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_world #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_world #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_world #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_world #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_world #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_world #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_world #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_world #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_world #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_world #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_world #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_world #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (test_world #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (test_world #55)
    xor     r11d, r11d ; clear v1 slot 55
