; sky curves, fog, weather tint, cloud map + render smoke. no GL context here,
; every gl call is a no-op. group order matters: the cloud map gets built on
; the first cloud render and sticks around.
; @link src/sky.asm src/particles.asm src/weather.asm tests/atmosphere/atmo_lib.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../atmosphere/atmo.inc"

section .rdata
align 8
k_0123:     dq 0.0123                   ; sweep step, double

section .text

setup:
    sub      rsp, 40
    call     atmo_reset_env
    mov      dword [rel g_world_active], 0
    call     sky_init
    add      rsp, 40
    ret

%macro AT 1
    mov      ecx, %1
    call     atmo_at
%endmacro

%macro SUM3 2
    movss    %1, [rel %2]
    addss    %1, [rel %2 + 4]
    addss    %1, [rel %2 + 8]
%endmacro

PROCX test_main, 64
    TEST "cloud_cover_is_broken_up"
    ; no texgen, so the map comes from the fallback noise. clouds_thin caps it ~40%
    call     setup
    mov      dword [rel g_settings + SETTINGS.clouds], 2
    xor      eax, eax
    mov      [rel g_cam_pos + 0], eax
    SETF     [rel g_cam_pos + 4], 70.0
    mov      [rel g_cam_pos + 8], eax
    call     sky_render_clouds
    call     atm_cloud_map
    mov      r12, rax
    xor      ebx, ebx
    xor      ecx, ecx
.sum:
    movzx    eax, byte [r12 + rcx]
    add      ebx, eax
    inc      ecx
    cmp      ecx, 65536
    jb       .sum
    PRINT    "  cloud cover cells: "
    mov      ecx, ebx
    call     t_print_int
    call     t_newline
    ; 25%..45% of 65536
    xor      eax, eax
    cmp      ebx, 16384
    jb       .cov_done
    cmp      ebx, 29491
    ja       .cov_done
    mov      eax, 1
.cov_done:
    CHECK_TRUE eax, "cloud cover within 25%..45%"
    ; biggest 4-connected blob (map wraps both ways) has to stay under 1/5
    mov      ecx, 65536
    call     t_alloc
    mov      r13, rax                   ; seen
    mov      ecx, 65536 * 4
    call     t_alloc
    mov      r14, rax                   ; dfs stack
    xor      r15d, r15d
    xor      esi, esi
.cc_start:
    cmp      byte [r12 + rsi], 0
    je       .cc_next
    cmp      byte [r13 + rsi], 0
    jne      .cc_next
    mov      byte [r13 + rsi], 1
    mov      [r14], esi
    mov      edi, 1
    xor      ebx, ebx
.cc_pop:
    test     edi, edi
    jz       .cc_end
    dec      edi
    mov      eax, [r14 + rdi*4]
    inc      ebx
    ; push edx if set and not seen yet
%macro CC_VISIT 0
    cmp      byte [r12 + rdx], 0
    je       %%skip
    cmp      byte [r13 + rdx], 0
    jne      %%skip
    mov      byte [r13 + rdx], 1
    mov      [r14 + rdi*4], edx
    inc      edi
%%skip:
%endmacro
    lea      edx, [rax + 1]             ; x+1, wraps inside the row
    movzx    edx, dl
    mov      ecx, eax
    and      ecx, 0xFF00
    or       edx, ecx
    CC_VISIT
    lea      edx, [rax - 1]
    movzx    edx, dl
    or       edx, ecx
    CC_VISIT
    lea      edx, [rax + 256]           ; y+1, dx wraps it
    movzx    edx, dx
    CC_VISIT
    lea      edx, [rax - 256]
    movzx    edx, dx
    CC_VISIT
    jmp      .cc_pop
.cc_end:
    cmp      ebx, r15d
    cmova    r15d, ebx
.cc_next:
    inc      esi
    cmp      esi, 65536
    jb       .cc_start
    PRINT    "  largest cloud bank: "
    mov      ecx, r15d
    call     t_print_int
    call     t_newline
    xor      eax, eax
    cmp      r15d, 65536 / 5
    setb     al
    CHECK_TRUE eax, "largest cloud bank < 1/5 of the map"

    TEST "colours_sane"
    call     setup
    AT       6000
    movss    xmm6, [rel g_sky_color + 0]
    movss    xmm7, [rel g_sky_color + 8]
    CHECK_GT xmm7, xmm6, "noon: blue zenith (b > r)"
    LDF      xmm0, 0.8
    CHECK_GT xmm7, xmm0, "noon: zenith blue > 0.8"
    SUM3     xmm6, g_fog_color
    SUM3     xmm7, g_sky_color
    CHECK_GT xmm6, xmm7, "noon: horizon paler than zenith"
    AT       18000
    SUM3     xmm6, g_sky_color
    LDF      xmm0, 0.15
    CHECK_LT xmm6, xmm0, "night: dark navy sky (sum < 0.15)"
    SUM3     xmm6, g_fog_color
    LDF      xmm0, 0.2
    CHECK_LT xmm6, xmm0, "night: dark fog (sum < 0.2)"
    movss    xmm6, [rel g_sky_color + 0]
    movss    xmm7, [rel g_sky_color + 8]
    CHECK_GE xmm7, xmm6, "night: sky b >= r"
    xor      ebx, ebx
.cs_loop:
    AT       ebx
    mov      r12d, 1
    xor      esi, esi
    xorps    xmm4, xmm4
    LDF      xmm5, 1.0
.cs_comp:
    lea      rax, [rel g_sky_color]
    movss    xmm0, [rax + rsi*4]
    lea      rax, [rel g_fog_color]
    movss    xmm1, [rax + rsi*4]
    xor      ecx, ecx
    comiss   xmm0, xmm4
    jb       .cs_bad
    comiss   xmm5, xmm0
    jb       .cs_bad
    comiss   xmm1, xmm4
    jb       .cs_bad
    comiss   xmm5, xmm1
    jae      .cs_ok
.cs_bad:
    xor      r12d, r12d
.cs_ok:
    inc      esi
    cmp      esi, 4
    jb       .cs_comp
    CHECK_TRUE r12d, "sky/fog components in [0,1] around the clock"
    movss    xmm6, [rel g_sky_color + 12]
    CHECK_FEQ xmm6, 1.0, "sky alpha == 1"
    movss    xmm6, [rel g_fog_color + 12]
    CHECK_FEQ xmm6, 1.0, "fog alpha == 1"
    add      ebx, 250
    cmp      ebx, 24000
    jb       .cs_loop

    TEST "daylight_extremes"
    call     setup
    AT       6000
    CHECK_NEAR dword [rel g_daylight], 1.0, 0.00005, "noon daylight 1.0"
    AT       18000
    CHECK_NEAR dword [rel g_daylight], 0.15, 0.00005, "midnight daylight 0.15"
    AT       0
    movss    xmm6, [rel g_daylight]
    CHECK_ORANGE xmm6, 0.3, 0.9, "dawn daylight in (0.3, 0.9)"

    TEST "daylight_monotonic_noon_to_midnight"
    call     setup
    LDF      xmm6, 2.0
    LDF      xmm8, 0.000001
    mov      r12d, 1
    mov      ebx, 6000
.mono_dn:
    AT       ebx
    movss    xmm7, [rel g_daylight]
    movss    xmm0, xmm6
    addss    xmm0, xmm8
    comiss   xmm0, xmm7
    jae      .mono_dn_ok
    xor      r12d, r12d
    PRINT    "  not decreasing at t="
    mov      ecx, ebx
    call     t_print_int
    call     t_newline
.mono_dn_ok:
    movss    xmm6, xmm7
    add      ebx, 100
    cmp      ebx, 18000
    jbe      .mono_dn
    CHECK_TRUE r12d, "daylight non-increasing noon -> midnight"
    LDF      xmm6, -1.0
    mov      r12d, 1
    mov      ebx, 18000
.mono_up:
    AT       ebx
    movss    xmm7, [rel g_daylight]
    movss    xmm0, xmm6
    subss    xmm0, xmm8
    comiss   xmm7, xmm0
    jae      .mono_up_ok
    xor      r12d, r12d
    PRINT    "  not increasing at t="
    mov      ecx, ebx
    call     t_print_int
    call     t_newline
.mono_up_ok:
    movss    xmm6, xmm7
    add      ebx, 100
    cmp      ebx, 24000
    jb       .mono_up_next
    xor      ebx, ebx                   ; past midnight
.mono_up_next:
    cmp      ebx, 6100
    je       .mono_up_end
    jmp      .mono_up
.mono_up_end:
    CHECK_TRUE r12d, "daylight non-decreasing midnight -> noon"

    TEST "fog_distances" ; v1: test_sky scratch #0
    ; TODO: verify 16-byte rsp alignment before inner call (test_sky:0)
    call     setup ; v1: test_sky scratch #1
    mov      dword [rel g_settings + SETTINGS.render_dist], 8 ; v1: test_sky scratch #2
    ; TODO: clamp index before table lookup on malformed input (test_sky:2)
    AT       6000 ; v1: test_sky scratch #3
    CHECK_NEAR dword [rel g_fog_end], 120.0, 0.0005, "fog end at 8 chunks" ; v1: test_sky scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_sky:4)
    CHECK_NEAR dword [rel g_fog_start], 72.0, 0.0005, "fog start at 8 chunks" ; v1: test_sky scratch #5
    mov      dword [rel g_settings + SETTINGS.render_dist], 16 ; v1: test_sky scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_sky:6)
    AT       6000 ; v1: test_sky scratch #7
    CHECK_NEAR dword [rel g_fog_end], 248.0, 0.0005, "fog end at 16 chunks" ; v1: test_sky scratch #8
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_sky:8)
    mov      dword [rel g_settings + SETTINGS.render_dist], 0 ; v1: test_sky scratch #9
    AT       6000 ; v1: test_sky scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_sky:10)
    CHECK_NEAR dword [rel g_fog_end], 24.0, 0.0005, "fog end clamped to 2 chunks" ; v1: test_sky scratch #11

    TEST "rain_thunder_lightning" ; v1: test_sky scratch #13
    call     setup ; v1: test_sky scratch #14
    ; TODO: hoist invariant pointer load out of .loop (test_sky:14)
    AT       6000 ; v1: test_sky scratch #15
    movss    xmm6, [rel g_daylight] ; v1: test_sky scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_sky:16)
    SETF     [rel g_rain], 1.0 ; v1: test_sky scratch #17
    AT       6000 ; v1: test_sky scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (test_sky:18)
    movss    xmm7, [rel g_daylight] ; v1: test_sky scratch #19
    LDF      xmm0, 0.7 ; v1: test_sky scratch #20
    ; TODO: clamp index before table lookup on malformed input (test_sky:20)
    mulss    xmm0, xmm6 ; v1: test_sky scratch #21
    CHECK_NEAR_X xmm7, xmm0, 0.00005, "rain dims daylight by 30%" ; v1: test_sky scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_sky:22)
    SETF     [rel g_thunder], 1.0 ; v1: test_sky scratch #23
    AT       6000 ; v1: test_sky scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_sky:24)
    movss    xmm8, [rel g_daylight] ; v1: test_sky scratch #25
    CHECK_LT xmm8, xmm7, "thunder darker than rain" ; v1: test_sky scratch #26
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_sky:26)
    SETF     [rel g_thunder], 0.0 ; v1: test_sky scratch #27
    AT       6000 ; v1: test_sky scratch #28
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_sky:28)
    movss    xmm0, [rel g_sky_color + 0] ; v1: test_sky scratch #29
    subss    xmm0, [rel g_sky_color + 8]
    mov      eax, 0x7FFFFFFF
    movd     xmm1, eax
    andps    xmm0, xmm1
    movss    xmm6, xmm0
    LDF      xmm0, 0.45
    CHECK_LT xmm6, xmm0, "rainy sky is greyish (|r-b| < 0.45)"
    SETF     [rel g_rain], 0.0
    SETF     [rel g_lightning], 0.0
    AT       18000
    movss    xmm6, [rel g_daylight]
    SETF     [rel g_lightning], 1.0
    AT       18000
    movss    xmm7, [rel g_daylight]
    LDF      xmm0, 0.5
    addss    xmm0, xmm6
    CHECK_GT xmm7, xmm0, "lightning flash brightens the night by > 0.5"
    SETF     [rel g_lightning], 0.0

    TEST "render_smoke"
    call     setup
    lea      r12, [rel smoke_times]
    xor      r13d, r13d
.rs_t:
    xor      ebx, ebx
.rs_w:
    mov      [rel g_world_time], rbx
    mov      ecx, [r12 + r13*4]
    call     atmo_at
    call     sky_render
    add      ebx, 24000
    cmp      ebx, 24000 * 9
    jb       .rs_w
    inc      r13d
    cmp      r13d, 6
    jb       .rs_t
    xor      r13d, r13d
.rs_c:
    mov      [rel g_settings + SETTINGS.clouds], r13d
    xor      r14d, r14d
.rs_y:
    SETF     [rel g_cam_pos + 0], -1.0e6
    lea      rax, [rel smoke_heights]
    mov      eax, [rax + r14*4]
    mov      [rel g_cam_pos + 4], eax
    SETF     [rel g_cam_pos + 8], 5.0e5
    call     sky_render_clouds
    inc      r14d
    cmp      r14d, 3
    jb       .rs_y
    inc      r13d
    cmp      r13d, 3
    jb       .rs_c
    CHECK_TRUE 1, "sky/cloud render CPU paths completed"

    TEST "sincos_accuracy"
    ; float sincos vs x87 fsin, x = k*0.0123 for k in -2000..2000
    call     setup
    mov      ebx, -2000
.sc_loop:
    cvtsi2sd xmm6, ebx
    mulsd    xmm6, [rel k_0123]
    cvtsd2ss xmm0, xmm6
    call     atm_sincos
    cvtss2sd xmm7, xmm0
    movsd    LOC(0), xmm6
    fld      qword LOC(0)
    fsin
    fstp     qword LOC(0)
    movsd    xmm8, LOC(0)
    CHECK_NEAR_D xmm7, xmm8, 2e-6, "atm_sincos(k*0.0123) == sin within 2e-6"
    inc      ebx
    cmp      ebx, 2000
    jle      .sc_loop

    TEST "sun_angle"
    call     setup
    AT       0
    CHECK_NEAR dword [rel g_sun_angle], 0.0, 0.000005, "sun angle 0 at sunrise"
    AT       6000
    CHECK_NEAR dword [rel g_sun_angle], 1.5707963267948966, 0.00005, "sun angle pi/2 at noon"
    AT       18000
    CHECK_NEAR dword [rel g_sun_angle], 4.71238898038469, 0.00005, "sun angle 3pi/2 at midnight"

    ; v1 temporary guard (test_sky #14)
    xor     r11d, r11d ; clear v1 slot 14
    ; v1 temporary guard (test_sky #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (test_sky #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (test_sky #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_sky #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_sky #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_sky #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_sky #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_sky #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_sky #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_sky #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_sky #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_sky #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_sky #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_sky #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_sky #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_sky #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_sky #48)
    xor     r11d, r11d ; clear v1 slot 48
