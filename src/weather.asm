%define IMPL_WEATHER
%include "common.inc"
%unmacro FCONST 2

; FCONST via r11, same as sky.asm
%macro FCONST 2
    mov  r11d, __float32__(%2)
    movd %1, r11d
%endmacro

extern atm_randf, atm_randfs, atm_randint, atm_draw, atm_sincos, atm_smoothstep
extern atm_pack_rgba, atm_hash, atm_tile_uv

%define PRECIP_RAIN     0
%define PRECIP_SNOW     1
%define PRECIP_DRY      2
%define CLOUD_BASE      138.0       ; bolt start, just under sky.asm's CLOUD_Y 140
%define BOLT_PTS        17
%define BRANCH_PTS      7
%define SHEET_R_MAX     8
%define SHEET_QMAX      ((2*SHEET_R_MAX+1)*(2*SHEET_R_MAX+1))
%define BOLT_VMAX       ((BOLT_PTS+BRANCH_PTS)*2*4)

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

section .rdata
align 16
c_mask3:    dd 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0
c_zero4:    dd 0.0, 0.0, 0.0, 0.0
c_one:      dd 1.0
c_half:     dd 0.5
c_2pi:      dd 6.2831853
c_1000d:    dq 1000.0
c_inv24:    dd 5.9604645e-8
sheet_r:    dd 4, 6, SHEET_R_MAX            ; by g_settings.particles

section .bss
alignb 16
global g_weather
g_weather:          resd 1
global g_weather_timer
g_weather_timer:    resd 1
w_flash_next:       resd 1
w_bolt_ticks:       resd 1
w_bolt_n:           resd 1
w_branch_n:         resd 1
alignb 16
w_bolt:             resd BOLT_PTS*4
w_branch:           resd BRANCH_PTS*4
w_rel:              resd (BOLT_PTS+BRANCH_PTS)*4
w_tex_rain:         resd 1
w_tex_snow:         resd 1
w_tex_ready:        resd 1
w_texbuf:           resb 32*64*4
alignb 16
w_vbuf:             resb SHEET_QMAX*4*24
w_bbuf:             resb BOLT_VMAX*24
w_tt:               resd 1
alignb 16
w_eye:              resd 4
w_last_time:        resq 1                  ; g_world_time seen by the previous tick

section .text

FUNCX w_duration, 0
    mov      ebx, ecx
    cmp      ebx, 1
    je       .rain
    ja       .thunder
    mov      ecx, 18001
    call     atm_randint
    add      eax, 6000
    jmp      .done
.rain:
    mov      ecx, 9001
    call     atm_randint
    add      eax, 3000
    jmp      .done
.thunder:
    mov      ecx, 5001
    call     atm_randint
    add      eax, 3000
.done:
ENDPX

PROCX weather_set, 0
    cmp      ecx, 2
    jbe      .ok
    mov      ecx, 2
.ok:
    mov      [rel g_weather], ecx
    call     w_duration
    mov      [rel g_weather_timer], eax
ENDPX

PROCX weather_tick, 32
    cmp      dword [rel g_world_active], 0
    je       .done
    ; game_tick bumps g_world_time right before us, so +1 per call is normal. any
    ; other jump = world created/loaded (or /time add): drop flash/bolt, a new world
    ; starts clear, and rain/thunder snap to the saved state so a loaded storm
    ; doesn't ramp up over 15 s
    mov      rax, [rel g_world_time]
    mov      rcx, [rel w_last_time]
    mov      [rel w_last_time], rax
    cmp      rax, rcx
    je       .cont                      ; time isn't moving (paused / tests)
    lea      rdx, [rcx+1]
    cmp      rax, rdx
    je       .cont
    xor      edx, edx
    mov      [rel g_lightning], edx
    mov      [rel w_flash_next], edx
    mov      [rel w_bolt_ticks], edx
    cmp      rax, 1
    ja       .snap
    mov      [rel g_weather], edx
    mov      [rel g_weather_timer], edx
.snap:
    mov      eax, [rel g_weather]
    xor      ecx, ecx
    xor      edx, edx
    cmp      eax, 1
    jb       .snapset
    mov      ecx, 0x3F800000
    cmp      eax, 2
    jb       .snapset
    mov      edx, 0x3F800000
.snapset:
    mov      [rel g_rain], ecx
    mov      [rel g_thunder], edx
.cont:
    mov      eax, [rel g_weather_timer]
    test     eax, eax
    jnz      .count
    mov      ecx, [rel g_weather]
    call     w_duration                 ; fresh world: keep the state
    mov      [rel g_weather_timer], eax
    jmp      .ramp
.count:
    dec      eax
    mov      [rel g_weather_timer], eax
    jnz      .ramp
    call     atm_randf
    mov      eax, [rel g_weather]
    cmp      eax, 1
    je       .from_rain
    ja       .from_thunder
    mov      ecx, 1                     ; clear -> rain / thunder
    FCONST   xmm1, 0.2
    comiss   xmm0, xmm1
    jae      .set
    mov      ecx, 2
    jmp      .set
.from_rain:
    xor      ecx, ecx                   ; rain -> clear / thunder
    FCONST   xmm1, 0.25
    comiss   xmm0, xmm1
    jae      .set
    mov      ecx, 2
    jmp      .set
.from_thunder:
    xor      ecx, ecx                   ; thunder -> clear / rain
    FCONST   xmm1, 0.5
    comiss   xmm0, xmm1
    jae      .set
    mov      ecx, 1
.set:
    call     weather_set

.ramp:
    xorps    xmm1, xmm1
    cmp      dword [rel g_weather], 1
    jb       .rt
    movss    xmm1, [rel c_one]
.rt:
    movss    xmm0, [rel g_rain]
    FCONST   xmm2, 0.005                ; 10 s ramp
    call     .approach
    movss    [rel g_rain], xmm0
    xorps    xmm1, xmm1
    cmp      dword [rel g_weather], 2
    jb       .tt
    movss    xmm1, [rel c_one]
.tt:
    movss    xmm0, [rel g_thunder]
    FCONST   xmm2, 0.00333              ; 15 s ramp
    call     .approach
    movss    [rel g_thunder], xmm0

    movss    xmm0, [rel g_lightning]
    FCONST   xmm1, 0.72
    mulss    xmm0, xmm1
    FCONST   xmm1, 0.01
    comiss   xmm0, xmm1
    jae      .lkeep
    xorps    xmm0, xmm0
.lkeep:
    movss    [rel g_lightning], xmm0
    mov      eax, [rel w_flash_next]
    test     eax, eax
    jz       .noflash
    dec      eax
    mov      [rel w_flash_next], eax
    jnz      .noflash
    call     atm_randf
    FCONST   xmm1, 0.3
    mulss    xmm0, xmm1
    FCONST   xmm1, 0.55
    addss    xmm0, xmm1
    maxss    xmm0, [rel g_lightning]
    movss    [rel g_lightning], xmm0
.noflash:
    mov      eax, [rel w_bolt_ticks]
    test     eax, eax
    jz       .nobolt
    dec      dword [rel w_bolt_ticks]
.nobolt:
    movss    xmm6, [rel g_thunder]
    FCONST   xmm1, 0.3
    comiss   xmm6, xmm1
    jb       .precip
    call     atm_randf
    FCONST   xmm1, 0.004
    mulss    xmm1, xmm6
    comiss   xmm0, xmm1
    jae      .precip
    call     w_strike
.precip:
    movss    xmm0, [rel g_rain]
    FCONST   xmm1, 0.02
    comiss   xmm0, xmm1
    jb       .done
    cmp      dword [rel g_player+PLAYER.eye_in_water], 0
    jne      .done
    call     w_precip
    jmp      .done

; .approach: xmm0 current, xmm1 target, xmm2 step -> xmm0
.approach:
    movss    xmm3, xmm1
    subss    xmm3, xmm0
    movss    xmm4, xmm2
    xorps    xmm5, xmm5
    subss    xmm5, xmm2
    maxss    xmm3, xmm5
    minss    xmm3, xmm4
    addss    xmm0, xmm3
    ret
.done:
ENDPX

FUNCX w_strike, 32
    mov      dword [rel g_lightning], 0x3F800000
    mov      ecx, 4
    call     atm_randint
    add      eax, 2
    mov      [rel w_flash_next], eax
    ; ground point at 24..96 blocks in a random direction
    call     atm_randf
    mulss    xmm0, [rel c_2pi]
    call     atm_sincos
    movss    xmm6, xmm0
    movss    xmm7, xmm1
    call     atm_randf
    FCONST   xmm1, 72.0
    mulss    xmm0, xmm1
    FCONST   xmm1, 24.0
    addss    xmm0, xmm1
    movss    xmm15, xmm0
    mulss    xmm7, xmm0
    addss    xmm7, [rel g_player+PLAYER.x]
    movss    xmm12, xmm7
    mulss    xmm6, xmm0
    addss    xmm6, [rel g_player+PLAYER.z]
    movss    xmm14, xmm6
    FLOORI   ecx, xmm12, xmm0
    FLOORI   edx, xmm14, xmm0
    call     world_height_at
    FCONST   xmm13, 64.0
    test     eax, eax
    js       .gy
    inc      eax
    cvtsi2ss xmm13, eax
.gy:
    FCONST   xmm0, 130.0              ; keep the bolt >= 8 blocks long
    minss    xmm13, xmm0
    ; random walk that converges on the ground point
    call     atm_randfs
    FCONST   xmm1, 6.0
    mulss    xmm0, xmm1
    addss    xmm0, xmm12
    movss    xmm8, xmm0
    call     atm_randfs
    FCONST   xmm1, 6.0
    mulss    xmm0, xmm1
    addss    xmm0, xmm14
    movss    xmm9, xmm0
    lea      rdi, [rel w_bolt]
    xor      ebx, ebx
.pt:
    cvtsi2ss xmm0, ebx
    FCONST   xmm1, 0.0625             ; 1 / (BOLT_PTS-1)
    mulss    xmm0, xmm1
    movss    xmm1, xmm13
    FCONST   xmm2, CLOUD_BASE
    subss    xmm1, xmm2
    mulss    xmm1, xmm0
    addss    xmm1, xmm2
    movss    [rdi+4], xmm1
    test     ebx, ebx
    jz       .store
    cmp      ebx, BOLT_PTS-1
    jne      .walk
    movss    xmm8, xmm12
    movss    xmm9, xmm14
    jmp      .store
.walk:
    mov      eax, BOLT_PTS
    sub      eax, ebx
    cvtsi2ss xmm10, eax
    movss    xmm0, xmm12
    subss    xmm0, xmm8
    divss    xmm0, xmm10
    addss    xmm8, xmm0
    call     atm_randfs
    FCONST   xmm1, 1.5
    mulss    xmm0, xmm1
    addss    xmm8, xmm0
    movss    xmm0, xmm14
    subss    xmm0, xmm9
    divss    xmm0, xmm10
    addss    xmm9, xmm0
    call     atm_randfs
    FCONST   xmm1, 1.5
    mulss    xmm0, xmm1
    addss    xmm9, xmm0
.store:
    movss    [rdi], xmm8
    movss    [rdi+8], xmm9
    mov      dword [rdi+12], 0
    add      rdi, 16
    inc      ebx
    cmp      ebx, BOLT_PTS
    jb       .pt
    mov      dword [rel w_bolt_n], BOLT_PTS
    mov      ecx, 7
    call     atm_randint
    add      eax, 2
    shl      eax, 4
    lea      rsi, [rel w_bolt]
    add      rsi, rax
    movss    xmm8, [rsi]
    movss    xmm10, [rsi+4]
    movss    xmm9, [rsi+8]
    call     atm_randfs
    FCONST   xmm1, 1.6
    mulss    xmm0, xmm1
    movss    xmm6, xmm0
    call     atm_randfs
    FCONST   xmm1, 1.6
    mulss    xmm0, xmm1
    movss    xmm7, xmm0
    lea      rdi, [rel w_branch]
    xor      ebx, ebx
.br:
    movss    [rdi], xmm8
    movss    [rdi+4], xmm10
    movss    [rdi+8], xmm9
    mov      dword [rdi+12], 0
    add      rdi, 16
    addss    xmm8, xmm6
    call     atm_randfs
    FCONST   xmm1, 0.7
    mulss    xmm0, xmm1
    addss    xmm8, xmm0
    addss    xmm9, xmm7
    call     atm_randfs
    FCONST   xmm1, 0.7
    mulss    xmm0, xmm1
    addss    xmm9, xmm0
    call     atm_randf
    FCONST   xmm1, 2.5
    mulss    xmm0, xmm1
    FCONST   xmm1, 2.0
    addss    xmm0, xmm1
    subss    xmm10, xmm0
    inc      ebx
    cmp      ebx, BRANCH_PTS
    jb       .br
    mov      dword [rel w_branch_n], BRANCH_PTS
    mov      dword [rel w_bolt_ticks], 7
    movss    xmm1, xmm15
    FCONST   xmm0, 0.0095
    mulss    xmm1, xmm0
    FCONST   xmm0, 1.2
    subss    xmm0, xmm1
    FCONST   xmm1, 0.35
    maxss    xmm0, xmm1
    minss    xmm0, [rel c_one]
    movss    xmm6, xmm0
    call     atm_randf
    FCONST   xmm1, 0.3
    mulss    xmm0, xmm1
    FCONST   xmm1, 0.8
    addss    xmm0, xmm1
    movss    xmm2, xmm0
    movss    xmm1, xmm6
    mov      ecx, SFX_THUNDER
    call     sfx_play
ENDPX

FUNCX w_precip, 32
    movss    xmm12, [rel g_player+PLAYER.x]
    movss    xmm13, [rel g_player+PLAYER.y]
    FCONST   xmm0, PLAYER_EYE
    addss    xmm13, xmm0
    movss    xmm14, [rel g_player+PLAYER.z]
    ; n = rain * 48 (particles_spawn thins it on lower settings)
    movss    xmm0, [rel g_rain]
    FCONST   xmm1, 48.0
    mulss    xmm0, xmm1
    cvttss2si r15d, xmm0
    inc      r15d
.drop:
    call     atm_randfs
    FCONST   xmm1, 16.0
    mulss    xmm0, xmm1
    addss    xmm0, xmm12
    movss    xmm6, xmm0
    call     atm_randfs
    FCONST   xmm1, 16.0
    mulss    xmm0, xmm1
    addss    xmm0, xmm14
    movss    xmm7, xmm0
    FLOORI   r12d, xmm6, xmm0
    FLOORI   r13d, xmm7, xmm0
    mov      ecx, r12d
    mov      edx, r13d
    call     world_height_at
    test     eax, eax
    js       .dnext
    inc      eax
    cvtsi2ss xmm9, eax
    call     atm_randf
    FCONST   xmm1, 12.0
    mulss    xmm0, xmm1
    FCONST   xmm1, 3.0
    addss    xmm0, xmm1
    addss    xmm0, xmm13
    movss    xmm8, xmm0
    comiss   xmm8, xmm9
    jbe      .dnext                     ; column covered above the spawn
    mov      ecx, r12d
    mov      edx, r13d
    call     w_precip_kind
    cmp      eax, PRECIP_SNOW
    je       .snow
    ja       .dnext
    call     atm_randfs
    FCONST   xmm1, 0.2
    mulss    xmm0, xmm1
    FCONST   xmm1, 0.6
    addss    xmm0, xmm1
    movss    [rsp+32], xmm0
    call     atm_randf
    FCONST   xmm1, 4.0
    mulss    xmm0, xmm1
    FCONST   xmm1, 15.0
    addss    xmm0, xmm1
    xorps    xmm1, xmm1
    subss    xmm1, xmm0
    movss    [rsp+40], xmm1
    call     atm_randfs
    FCONST   xmm1, 0.2
    mulss    xmm0, xmm1
    FCONST   xmm1, 0.15
    addss    xmm0, xmm1
    movss    [rsp+48], xmm0
    mov      ecx, PT_RAIN
    jmp      .spawn
.snow:
    call     atm_randfs
    FCONST   xmm1, 0.3
    mulss    xmm0, xmm1
    movss    [rsp+32], xmm0
    call     atm_randf
    FCONST   xmm1, 0.4
    mulss    xmm0, xmm1
    FCONST   xmm1, 1.0
    addss    xmm0, xmm1
    xorps    xmm1, xmm1
    subss    xmm1, xmm0
    movss    [rsp+40], xmm1
    call     atm_randfs
    FCONST   xmm1, 0.3
    mulss    xmm0, xmm1
    movss    [rsp+48], xmm0
    mov      ecx, PT_SNOW
.spawn:
    mov      qword [rsp+56], 0
    movss    xmm1, xmm6
    movss    xmm2, xmm8
    movss    xmm3, xmm7
    call     particles_spawn
.dnext:
    dec      r15d
    jnz      .drop

    movss    xmm0, [rel g_rain]
    FCONST   xmm1, 10.0
    mulss    xmm0, xmm1
    cvttss2si r15d, xmm0
    test     r15d, r15d
    jz       .done
.splash:
    call     atm_randfs
    FCONST   xmm1, 12.0
    mulss    xmm0, xmm1
    addss    xmm0, xmm12
    movss    xmm6, xmm0
    call     atm_randfs
    FCONST   xmm1, 12.0
    mulss    xmm0, xmm1
    addss    xmm0, xmm14
    movss    xmm7, xmm0
    FLOORI   r12d, xmm6, xmm0
    FLOORI   r13d, xmm7, xmm0
    mov      ecx, r12d
    mov      edx, r13d
    call     world_height_at
    test     eax, eax
    js       .snext
    mov      r14d, eax
    cvtsi2ss xmm8, eax
    movss    xmm0, xmm13
    FCONST   xmm1, 16.0
    addss    xmm0, xmm1
    comiss   xmm8, xmm0
    ja       .snext
    mov      ecx, r12d
    mov      edx, r13d
    call     w_precip_kind
    test     eax, eax
    jnz      .snext
    mov      ecx, r12d
    mov      edx, r14d
    mov      r8d, r13d
    call     world_get_block
    FCONST   xmm0, 1.02
    cmp      eax, B_WATER
    jb       .solid
    cmp      eax, B_LAVA_LAST
    ja       .solid
    FCONST   xmm0, 0.92                 ; liquid surface sits a little lower
.solid:
    addss    xmm8, xmm0
    call     atm_randfs
    FCONST   xmm1, 0.6
    mulss    xmm0, xmm1
    movss    [rsp+32], xmm0
    call     atm_randf
    FCONST   xmm1, 1.5
    mulss    xmm0, xmm1
    FCONST   xmm1, 1.5
    addss    xmm0, xmm1
    movss    [rsp+40], xmm0
    call     atm_randfs
    FCONST   xmm1, 0.6
    mulss    xmm0, xmm1
    movss    [rsp+48], xmm0
    mov      qword [rsp+56], 0
    mov      ecx, PT_SPLASH
    movss    xmm1, xmm6
    movss    xmm2, xmm8
    movss    xmm3, xmm7
    call     particles_spawn
.snext:
    dec      r15d
    jnz      .splash
.done:
ENDPX

; temp < 0.15 snows, >= 1.0 (desert, savanna) stays dry. sky still darkens there
FUNCX w_precip_kind, 0
    call     world_get_biome
    cmp      eax, BIOME_COUNT
    jb       .ok
    xor      eax, eax
    jmp      .done
.ok:
    lea      rcx, [rel biome_temperature]
    movss    xmm0, [rcx+rax*4]
    mov      eax, PRECIP_SNOW
    FCONST   xmm1, 0.15
    comiss   xmm0, xmm1
    jb       .done
    mov      eax, PRECIP_DRY
    FCONST   xmm1, 1.0
    comiss   xmm0, xmm1
    jae      .done
    mov      eax, PRECIP_RAIN
.done:
ENDPX

; why not the 16x16 atlas tile: stretched over a 1-block sheet the streak turns
; into a 0.125-block glass rod right in front of the camera. these are 32 texels
; per block. rain 32x64 (one tile = 4 blocks tall), snow 32x32
%define SHEET_W         32
%define SHEET_STREAKS   7
%define SHEET_FLAKES    11
FUNCX w_make_tex, 32
    mov      r13d, ecx
    ; clear to transparent but keep the rain/snow rgb, so filtering never darkens the edges
    lea      rdi, [rel w_texbuf]
    mov      eax, 0x00E8D8C8            ; A=00 B=E8 G=D8 R=C8
    test     r13d, r13d
    jz       .clr
    mov      eax, 0x00FFFFFF
.clr:
    xor      ecx, ecx
.cl:
    mov      [rdi+rcx*4], eax
    inc      ecx
    cmp      ecx, SHEET_W*64
    jb       .cl
    xor      r12d, r12d
    test     r13d, r13d
    jnz      .flakes

.streak: ; v1: weather scratch #0
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (weather:0)
    mov      ecx, r12d ; v1: weather scratch #1
    imul     ecx, ecx, 0x9E3779B1 ; v1: weather scratch #2
    ; TODO: hoist invariant pointer load out of .loop (weather:2)
    add      ecx, 0x2545F491 ; v1: weather scratch #3
    call     atm_hash ; v1: weather scratch #4
    ; FIXME: negative world x/z needs sar 4, not shr 4 (weather:4)
    mov      ebx, eax ; v1: weather scratch #5
    mov      eax, r12d ; v1: weather scratch #6
    ; note: rcx = state ptr, rdx = index, r8d = flags (weather:6)
    shl      eax, 5 ; v1: weather scratch #7
    xor      edx, edx ; v1: weather scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (weather:8)
    mov      ecx, SHEET_STREAKS ; v1: weather scratch #9
    div      ecx ; v1: weather scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (weather:10)
    mov      esi, ebx ; v1: weather scratch #11
    shr      esi, 4 ; v1: weather scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (weather:12)
    and      esi, 3 ; v1: weather scratch #13
    add      esi, eax ; v1: weather scratch #14
    ; TODO: clamp index before table lookup on malformed input (weather:14)
    and      esi, SHEET_W-1 ; v1: weather scratch #15
    mov      r14d, ebx ; v1: weather scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (weather:16)
    shr      r14d, 8 ; v1: weather scratch #17
    and      r14d, 63 ; v1: weather scratch #18
    ; TODO: hoist invariant pointer load out of .loop (weather:18)
    mov      eax, ebx ; v1: weather scratch #19
    shr      eax, 16 ; v1: weather scratch #20
    ; FIXME: negative world x/z needs sar 4, not shr 4 (weather:20)
    and      eax, 0xFF ; v1: weather scratch #21
    xor      edx, edx ; v1: weather scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (weather:22)
    mov      ecx, 14 ; v1: weather scratch #23
    div      ecx ; v1: weather scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (weather:24)
    lea      r15d, [rdx+10] ; v1: weather scratch #25
    mov      eax, ebx ; v1: weather scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (weather:26)
    shr      eax, 24 ; v1: weather scratch #27
    and      eax, 63 ; v1: weather scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (weather:28)
    add      eax, 120 ; v1: weather scratch #29
    mov      [rsp+FRAME_OUT], eax ; v1: weather scratch #30
    ; TODO: clamp index before table lookup on malformed input (weather:30)
    xor      ecx, ecx ; v1: weather scratch #31
.spx: ; v1: weather scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (weather:32)
    lea      eax, [rcx+1] ; v1: weather scratch #33
    imul     eax, [rsp+FRAME_OUT]
    xor      edx, edx
    div      r15d
    lea      edx, [r14+rcx]
    and      edx, 63
    shl      edx, 5
    add      edx, esi
    movzx    r8d, byte [rdi+rdx*4+3]
    cmp      eax, r8d
    jbe      .skeep
    mov      [rdi+rdx*4+3], al
.skeep:
    inc      ecx
    cmp      ecx, r15d
    jb       .spx
    inc      r12d
    cmp      r12d, SHEET_STREAKS
    jb       .streak
    mov      dword [rsp+FRAME_OUT+4], 64
    jmp      .upload

.flakes:
    mov      ecx, r12d
    imul     ecx, ecx, 0x85EBCA6B
    add      ecx, 0x68E31DA4
    call     atm_hash
    mov      ebx, eax
    mov      esi, ebx
    and      esi, 31
    mov      r14d, ebx
    shr      r14d, 5
    and      r14d, 31
    mov      eax, ebx
    shr      eax, 10
    and      eax, 3
    cmp      eax, 2
    jb       .dot
    je       .square
    ; plus: centre 240, arms 150
    mov      ecx, esi
    mov      edx, r14d
    mov      r8d, 240
    call     .put
    lea      ecx, [rsi+1]
    mov      edx, r14d
    mov      r8d, 150
    call     .put
    lea      ecx, [rsi-1]
    mov      edx, r14d
    mov      r8d, 150
    call     .put
    mov      ecx, esi
    lea      edx, [r14+1]
    mov      r8d, 150
    call     .put
    mov      ecx, esi
    lea      edx, [r14-1]
    mov      r8d, 150
    call     .put
    jmp      .fnext
.square:
    mov      ecx, esi
    mov      edx, r14d
    mov      r8d, 215
    call     .put
    lea      ecx, [rsi+1]
    mov      edx, r14d
    mov      r8d, 215
    call     .put
    mov      ecx, esi
    lea      edx, [r14+1]
    mov      r8d, 215
    call     .put
    lea      ecx, [rsi+1]
    lea      edx, [r14+1]
    mov      r8d, 215
    call     .put
    jmp      .fnext
.dot:
    mov      ecx, esi
    mov      edx, r14d
    mov      r8d, 230
    call     .put
.fnext:
    inc      r12d
    cmp      r12d, SHEET_FLAKES
    jb       .flakes
    mov      dword [rsp+FRAME_OUT+4], 32

    ; v1 temporary guard (weather #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (weather #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (weather #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (weather #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (weather #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (weather #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (weather #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (weather #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (weather #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (weather #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (weather #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (weather #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (weather #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (weather #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (weather #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (weather #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (weather #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (weather #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (weather #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (weather #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (weather #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (weather #59)
    xor     r11d, r11d ; clear v1 slot 59
