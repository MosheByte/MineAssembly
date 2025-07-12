; weather state machine, ramps, lightning, precipitation. stub world is all
; air, height 0, biome 0.
; @link src/sky.asm src/particles.asm src/weather.asm tests/atmosphere/atmo_lib.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../atmosphere/atmo.inc"

section .rdata
align 8
k_rain_min_y:   dq 68.52                ; 64 + 1.62 eye + 2.9

section .text

setup:
    sub      rsp, 40
    call     atmo_reset_env
    call     particles_init
    mov      dword [rel g_world_active], 1
    mov      dword [rel g_weather], 0
    mov      dword [rel g_weather_timer], 0
    SETF     [rel g_player + PLAYER.x], 0.0
    SETF     [rel g_player + PLAYER.y], 64.0
    SETF     [rel g_player + PLAYER.z], 0.0
    SETF     [rel biome_temperature], 0.8
    add      rsp, 40
    ret

%macro WSET 1
    mov      ecx, %1
    call     weather_set
%endmacro

; clobbers r15
%macro TICKS 1
    mov      r15d, %1
%%l:
    call     weather_tick
    dec      r15d
    jnz      %%l
%endmacro

PROCX test_main, 64
    TEST "dry_biomes_get_no_precipitation"
    call     setup
    WSET     1
    SETF     [rel g_rain], 1.0
    xor      ebx, ebx
.dry_loop:
    call     particles_clear
    lea      rax, [rel dry_temps]       ; desert, savanna, right at the cutoff
    mov      eax, [rax + rbx*4]
    mov      [rel biome_temperature], eax
    TICKS    5
    COUNT_TYPE PT_RAIN
    CHECK_EQ32 eax, 0, "no rain in a dry biome"
    COUNT_TYPE PT_SNOW
    CHECK_EQ32 eax, 0, "no snow in a dry biome"
    COUNT_TYPE PT_SPLASH
    CHECK_EQ32 eax, 0, "no splashes in a dry biome"
    call     weather_render             ; sheets skip dry columns
    inc      ebx
    cmp      ebx, 3
    jb       .dry_loop
    call     particles_clear
    SETF     [rel biome_temperature], 0.95
    call     weather_tick
    COUNT_TYPE PT_RAIN
    CHECK_TRUE eax, "jungle (0.95) still rains"

    TEST "fresh_world_stays_clear"
    call     setup
    call     weather_tick
    CHECK_EQ32 [rel g_weather], 0, "fresh world is clear"
    CHECK_IRANGE [rel g_weather_timer], 6000, 24000, "clear spell 6000..24000 ticks"

    TEST "lightning"
    call     setup
    WSET     2
    SETF     [rel g_rain], 1.0
    SETF     [rel g_thunder], 1.0
    xorps    xmm6, xmm6
    mov      ebx, 4000
.lt_loop:
    call     weather_tick
    maxss    xmm6, [rel g_lightning]
    call     particles_clear
    dec      ebx
    jnz      .lt_loop
    LDF      xmm0, 0.99
    CHECK_GT xmm6, xmm0, "a storm produces a full lightning flash"
    SETF     [rel g_lightning], 0.0

    TEST "no_rain_under_water"
    call     setup
    WSET     1
    SETF     [rel g_rain], 1.0
    mov      dword [rel g_player + PLAYER.eye_in_water], 1
    call     weather_tick
    CHECK_EQ32 [rel g_particle_count], 0, "no precipitation with the eye under water"
    mov      dword [rel g_player + PLAYER.eye_in_water], 0

    TEST "rain_and_snow_particles"
    call     setup
    WSET     1
    SETF     [rel g_rain], 1.0
    call     weather_tick
    COUNT_TYPE PT_RAIN
    mov      ebx, eax
    xor      eax, eax
    cmp      ebx, 30
    setg     al
    CHECK_TRUE eax, "more than 30 rain drops per tick"
    COUNT_TYPE PT_SPLASH
    CHECK_TRUE eax, "rain splashes spawned"
    call     atmo_pool
    mov      r12, rax
    mov      r13d, [rel g_particle_count]
.rs_each:
    test     r13d, r13d
    jz       .rs_done
    cmp      byte [r12 + PARTICLE.type], PT_RAIN
    jne      .rs_next
    cvtss2sd xmm6, [r12 + PARTICLE.y]
    comisd   xmm6, [rel k_rain_min_y]
    seta     al
    movzx    eax, al
    CHECK_TRUE eax, "rain drop spawns above y 68.52"
    movss    xmm6, [r12 + PARTICLE.vy]
    LDF      xmm0, -14.0
    CHECK_LT xmm6, xmm0, "rain drop vy < -14"
.rs_next:
    add      r12, PARTICLE_size
    dec      r13d
    jmp      .rs_each
.rs_done:
    call     particles_clear
    SETF     [rel biome_temperature], 0.0
    call     weather_tick
    COUNT_TYPE PT_SNOW
    CHECK_TRUE eax, "cold biome snows"
    COUNT_TYPE PT_RAIN
    CHECK_EQ32 eax, 0, "cold biome: no rain"
    COUNT_TYPE PT_SPLASH
    CHECK_EQ32 eax, 0, "cold biome: no splashes"

    TEST "ramps"
    call     setup
    WSET     1
    TICKS    100
    CHECK_NEAR dword [rel g_rain], 0.5, 0.0005, "rain half way after 100 ticks"
    TICKS    150
    movss    xmm6, [rel g_rain]
    CHECK_FEQ xmm6, 1.0, "rain full after 250 ticks"
    movss    xmm6, [rel g_thunder]
    CHECK_FEQ xmm6, 0.0, "no thunder in plain rain"
    WSET     0
    TICKS    250
    movss    xmm6, [rel g_rain]
    CHECK_FEQ xmm6, 0.0, "rain gone 250 ticks after clearing"

    TEST "render_smoke"
    call     setup
    WSET     2
    SETF     [rel g_rain], 1.0
    SETF     [rel g_thunder], 1.0
    mov      ebx, 500
.rd_loop:
    call     weather_tick
    call     weather_render
    call     particles_clear
    dec      ebx
    jnz      .rd_loop
    CHECK_TRUE 1, "500 storm ticks + renders completed"

    TEST "set_durations"
    call     setup
    mov      ebx, 200
.sd_loop:
    WSET     0
    CHECK_IRANGE [rel g_weather_timer], 6000, 24000, "clear lasts 6000..24000"
    WSET     1
    CHECK_EQ32 [rel g_weather], 1, "weather_set(1) -> rain"
    CHECK_IRANGE [rel g_weather_timer], 3000, 12000, "rain lasts 3000..12000"
    WSET     2
    CHECK_IRANGE [rel g_weather_timer], 3000, 8000, "thunder lasts 3000..8000"
    dec      ebx
    jnz      .sd_loop
    WSET     9
    CHECK_EQ32 [rel g_weather], 2, "weather_set(9) clamps to thunder"

    TEST "transition"
    call     setup
    xor      r12d, r12d                 ; weathers seen, as bits
    mov      ebx, 200
.tr_loop:
    mov      dword [rel g_weather], 0
    mov      dword [rel g_weather_timer], 1
    call     weather_tick
    mov      ecx, [rel g_weather]
    and      ecx, 31
    mov      eax, 1
    shl      eax, cl
    or       r12d, eax
    mov      eax, [rel g_weather_timer]
    xor      ecx, ecx
    test     eax, eax
    setg     cl
    CHECK_TRUE ecx, "new weather has a positive timer"
    dec      ebx
    jnz      .tr_loop
    CHECK_EQ32 r12d, 0x6, "clear turns into both rain and thunder (seen == {1,2})"
ENDPX

section .rdata
align 4
dry_temps:  dd 2.0, 1.2, 1.0
