%define IMPL_SKY
%include "common.inc"
%unmacro FCONST 2

; own FCONST through r11, the common.inc one goes through eax and eax is
; usually holding something here
%macro FCONST 2
    mov  r11d, __float32__(%2)
    movd %1, r11d
%endmacro

extern glGetTexImage

%define SKY_R           10.0        ; sky radius, depth is off anyway
%define NSTARS          1500
%define AZ_SEG          32
%define DOME_RINGS      9
%define GLOW_RINGS      6
%define SUN_HALF        2.3         ; half size of the sun quad at SKY_R (~25 deg)
%define MOON_HALF       1.45
%define MOON_SLICES     16
%define SKY_VMAX        2048
; worldgen caps the surface at 124 and peaks sit at 115-124 a lot, so 140 keeps
; clouds out of the mountains. weather's CLOUD_BASE (bolt start) is just under it
%define CLOUD_Y         140.0
%define CLOUD_COVER     40
%define CLOUD_COVER_MAX 45          ; maps above this are thinned to CLOUD_COVER
%define CLOUD_CELL      12.0        ; blocks per cloud-map texel
%define CLOUD_THICK     4.0
%define CLOUD_PERIOD    3072.0      ; 256 * 12
%define CLOUD_SPEED     0.05        ; blocks per tick (+X)
%define CLOUD_WRAP      61440       ; ticks for the drift to cover one period
%define FLAT_N          32
%define FANCY_R         12
%define CLOUD_VMAX      12000

; floor(float) -> int :  FLOORI dst32, xmmsrc, xmmtmp
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

; CLOUD_FACE dst, shade, mix : dst = lerp(s_cloud * shade, g_fog_color, mix)
%macro CLOUD_FACE 3
    movups   xmm0, [rel s_cloud]
    FCONST   xmm1, %2
    shufps   xmm1, xmm1, 0
    mulps    xmm0, xmm1
    movups   [rel %1], xmm0
    lea      rcx, [rel %1]
    mov      rdx, rcx
    lea      r8, [rel g_fog_color]
    FCONST   xmm3, %3
    call     atm_lerp4
%endmacro

; 24 byte vertex: xyz uv rgba8. advances %1
%macro VTX 7
    movss [%1+0],  %2
    movss [%1+4],  %3
    movss [%1+8],  %4
    movss [%1+12], %5
    movss [%1+16], %6
    mov   dword [%1+20], %7
    add   %1, 24
%endmacro

section .rdata
align 16
c_signmask:     dd 0x80000000, 0x80000000, 0x80000000, 0x80000000
c_absmask:      dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
c_zero4:        dd 0.0, 0.0, 0.0, 0.0
c_one4:         dd 1.0, 1.0, 1.0, 1.0
c_255x4:        dd 255.0, 255.0, 255.0, 255.0

col_day_zen:    dd 0.25, 0.47, 0.96, 1.0
col_night_zen:  dd 0.008, 0.012, 0.036, 1.0
col_day_fog:    dd 0.66, 0.80, 1.00, 1.0
col_night_fog:  dd 0.020, 0.028, 0.065, 1.0
col_glow:       dd 1.00, 0.45, 0.19, 1.0
col_glow_zen:   dd 0.42, 0.34, 0.62, 1.0
col_flash:      dd 0.86, 0.88, 1.00, 1.0
col_water_fog:  dd 0.035, 0.21, 0.33, 1.0
col_lava_fog:   dd 0.80, 0.27, 0.03, 1.0
col_cloud_day:  dd 1.00, 1.00, 1.00, 1.0
col_cloud_ngt:  dd 0.075, 0.085, 0.12, 1.0
col_cloud_set:  dd 1.00, 0.66, 0.46, 1.0
col_sun_white:  dd 1.00, 0.98, 0.92, 1.0
col_sun_red:    dd 1.00, 0.58, 0.32, 1.0

; dome rings top to bottom (90 55 30 15 6 0 -8 -35 -90 deg) + colour weights
dome_el:  dd 1.5707963, 0.9599311, 0.5235988, 0.2617994, 0.1047198, 0.0, -0.1396263, -0.6108652, -1.5707963
dome_wsky:  dd 1.00, 0.86, 0.62, 0.36, 0.14, 0.00, 0.00, 0.00, 0.00
dome_wfog:  dd 0.00, 0.14, 0.38, 0.64, 0.86, 1.00, 1.00, 0.35, 0.00
dome_wvoid: dd 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.65, 1.00
; glow band rings: -10 0 5 12 24 40 deg
glow_el:  dd -0.1745329, 0.0, 0.0872665, 0.2094395, 0.4188790, 0.6981317
glow_ef:  dd 0.45, 1.00, 0.86, 0.55, 0.20, 0.00

c_pio2_hi:      dd 1.5707963705062866
c_pio2_lo:      dd -4.3711388e-8
c_2_over_pi:    dd 0.63661977
c_s3:           dd -0.16666667
c_s5:           dd 0.0083333333
c_s7:           dd -0.00019841270
c_c2:           dd -0.5
c_c4:           dd 0.041666667
c_c6:           dd -0.0013888889
c_c8:           dd 0.0000248016
c_one:          dd 1.0
c_half:         dd 0.5
c_two:          dd 2.0
c_three:        dd 3.0
c_2pi:          dd 6.2831853
c_pi:           dd 3.1415927
c_pi_4:         dd 0.78539816
c_rad2deg:      dd 57.29578
c_inv_day:      dd 0.000041666667          ; 1/24000
c_2pi_seg:      dd 0.19634954
c_skyR:         dd SKY_R
c_inv24:        dd 5.9604645e-8            ; 2^-24
c_lum_r:        dd 0.30
c_lum_g:        dd 0.59
c_lum_b:        dd 0.11
c_tilt_deg:     dd 12.0
c_tilt_sin:     dd 0.20791169
c_tilt_cos:     dd 0.97814760
c_255:          dd 255.0
c_inv16:        dd 0.0625
c_inv256:       dd 0.00390625
c_halftexel:    dd 0.001953125             ; half a texel of the 256 atlas
c_tile_in:      dd 0.05859375              ; 1/16 - 2 * half texel
c_1000d:        dq 1000.0
c_period_d:     dq CLOUD_PERIOD
c_inv_period_d: dq 0.000325520833333333
c_cell_d:       dq CLOUD_CELL
c_inv_cell_d:   dq 0.0833333333333333
c_speed_d:      dq CLOUD_SPEED

section .data ; v1: sky scratch #0
    ; TODO: clamp index before table lookup on malformed input (sky:0)
align 4 ; v1: sky scratch #1
rng_state:      dd 0x2545F491 ; v1: sky scratch #2
    ; TODO: hoist invariant pointer load out of .loop (sky:2)

section .bss ; v1: sky scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (sky:4)
alignb 16 ; v1: sky scratch #5
s_vbuf:         resb SKY_VMAX*24 ; v1: sky scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (sky:6)
star_vb:        resb NSTARS*4*24 ; v1: sky scratch #7
star_dir:       resd NSTARS*4 ; v1: sky scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (sky:8)
star_tw:        resd NSTARS*2 ; v1: sky scratch #9
star_tint:      resd NSTARS ; v1: sky scratch #10
    ; TODO: verify 16-byte rsp alignment before inner call (sky:10)
az_cos:         resd AZ_SEG+1 ; v1: sky scratch #11
az_sin:         resd AZ_SEG+1 ; v1: sky scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (sky:12)
az_f:           resd AZ_SEG+1 ; v1: sky scratch #13
dome_y:         resd DOME_RINGS ; v1: sky scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (sky:14)
dome_r:         resd DOME_RINGS ; v1: sky scratch #15
glow_y:         resd GLOW_RINGS ; v1: sky scratch #16
    ; TODO: clamp index before table lookup on malformed input (sky:16)
glow_r:         resd GLOW_RINGS ; v1: sky scratch #17
ring_col:       resd DOME_RINGS ; v1: sky scratch #18
    ; TODO: hoist invariant pointer load out of .loop (sky:18)
c_vbuf:         resb CLOUD_VMAX*24 ; v1: sky scratch #19
cbuf:           resb 256*256*4 ; v1: sky scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (sky:20)
cmap:           resb 256*256 ; v1: sky scratch #21
cscore:         resb 256*256 ; v1: sky scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (sky:22)
cdens:          resb 256*256 ; v1: sky scratch #23
chist:          resd 256 ; v1: sky scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (sky:24)
cl_col_top:     resd 4 ; v1: sky scratch #25
cl_col_sx:      resd 4 ; v1: sky scratch #26
    ; TODO: verify 16-byte rsp alignment before inner call (sky:26)
cl_col_sz:      resd 4 ; v1: sky scratch #27
cl_col_bot:     resd 4 ; v1: sky scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (sky:28)
cl_col_flat:    resd 4 ; v1: sky scratch #29
calpha:         resd (FLAT_N+1)*(FLAT_N+1) ; v1: sky scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (sky:30)
tmp16:          resd 4 ; v1: sky scratch #31
tmp16b:         resd 4 ; v1: sky scratch #32
    ; TODO: clamp index before table lookup on malformed input (sky:32)
s_void:         resd 4 ; v1: sky scratch #33
s_cloud:        resd 4 ; v1: sky scratch #34
    ; TODO: hoist invariant pointer load out of .loop (sky:34)
s_tmpcol:       resd 4 ; v1: sky scratch #35
s_sin:          resd 1
s_cos:          resd 1
s_dayT:         resd 1
s_night:        resd 1
s_nightraw:     resd 1
s_glow:         resd 1
s_hx:           resd 1                  ; +1 glow in the east, -1 west
s_medium:       resd 1                  ; 0 air, 1 water, 2 lava
sky_ready:      resd 1
cmap_ready:     resd 1
cmap_src:       resd 1
cloud_tex:      resd 1
cloud_own:      resd 1
cl_uo:          resd 1
cl_vo:          resd 1
cl_fx:          resd 1
cl_fz:          resd 1
cl_ci:          resd 1
cl_cj:          resd 1
cl_yrel:        resd 1
cl_rc:          resd 1
cl_inner:       resd 1
cl_alpha:       resd 1
alignb 16
cl_proj:        resd 16

section .text

; atm_* are all leaves and only touch rax rcx rdx r8-r11, xmm0-5, so callers
; can keep whatever in nonvolatiles

; atm_sincos(xmm0 rad) -> xmm0 sin, xmm1 cos
; cody-waite then taylor, err < 4e-7
LEAF atm_sincos
    movss    xmm1, [rel c_2_over_pi]
    mulss    xmm1, xmm0
    cvtss2si eax, xmm1
    cvtsi2ss xmm1, eax
    movss    xmm2, xmm1
    mulss    xmm2, [rel c_pio2_hi]
    subss    xmm0, xmm2
    mulss    xmm1, [rel c_pio2_lo]
    subss    xmm0, xmm1
    movss    xmm2, xmm0
    mulss    xmm2, xmm2
    movss    xmm3, [rel c_s7]
    mulss    xmm3, xmm2
    addss    xmm3, [rel c_s5]
    mulss    xmm3, xmm2
    addss    xmm3, [rel c_s3]
    mulss    xmm3, xmm2
    mulss    xmm3, xmm0
    addss    xmm3, xmm0
    movss    xmm4, [rel c_c8]
    mulss    xmm4, xmm2
    addss    xmm4, [rel c_c6]
    mulss    xmm4, xmm2
    addss    xmm4, [rel c_c4]
    mulss    xmm4, xmm2
    addss    xmm4, [rel c_c2]
    mulss    xmm4, xmm2
    addss    xmm4, [rel c_one]
    and      eax, 3
    jz       .q0
    cmp      eax, 2
    je       .q2
    jb       .q1
    movss    xmm0, xmm4 ; q3: sin = -cos, cos = sin
    xorps    xmm0, [rel c_signmask]
    movss    xmm1, xmm3
    ret
.q0:
    movss    xmm0, xmm3
    movss    xmm1, xmm4
    ret
.q1:
    movss    xmm0, xmm4
    movss    xmm1, xmm3
    xorps    xmm1, [rel c_signmask]
    ret
.q2:
    movss    xmm0, xmm3
    xorps    xmm0, [rel c_signmask]
    movss    xmm1, xmm4
    xorps    xmm1, [rel c_signmask]
    ret

LEAF atm_sin
    jmp      atm_sincos

; xorshift32, main thread only!
LEAF atm_rand
    mov      eax, [rel rng_state]
    mov      edx, eax
    shl      edx, 13
    xor      eax, edx
    mov      edx, eax
    shr      edx, 17
    xor      eax, edx
    mov      edx, eax
    shl      edx, 5
    xor      eax, edx
    mov      [rel rng_state], eax
    ret
    ; v1 temporary guard (sky #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (sky #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (sky #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (sky #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (sky #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (sky #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (sky #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (sky #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (sky #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (sky #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (sky #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (sky #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (sky #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (sky #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (sky #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (sky #48)
    xor     r11d, r11d ; clear v1 slot 48
