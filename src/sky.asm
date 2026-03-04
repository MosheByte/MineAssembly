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

section .data
align 4
rng_state:      dd 0x2545F491

section .bss
alignb 16
s_vbuf:         resb SKY_VMAX*24
star_vb:        resb NSTARS*4*24
star_dir:       resd NSTARS*4           ; x, y, z, base brightness
star_tw:        resd NSTARS*2
star_tint:      resd NSTARS             ; 0x00BBGGRR
az_cos:         resd AZ_SEG+1
az_sin:         resd AZ_SEG+1
az_f:           resd AZ_SEG+1
dome_y:         resd DOME_RINGS
dome_r:         resd DOME_RINGS
glow_y:         resd GLOW_RINGS
glow_r:         resd GLOW_RINGS
ring_col:       resd DOME_RINGS
c_vbuf:         resb CLOUD_VMAX*24
cbuf:           resb 256*256*4
cmap:           resb 256*256
cscore:         resb 256*256 ; thin score / carve row sums, shared
cdens:          resb 256*256            ; clouds_carve: 9x9 cloud density (0..81)
chist:          resd 256
cl_col_top:     resd 4
cl_col_sx:      resd 4
cl_col_sz:      resd 4
cl_col_bot:     resd 4
cl_col_flat:    resd 4
calpha:         resd (FLAT_N+1)*(FLAT_N+1)
tmp16:          resd 4
tmp16b:         resd 4
s_void:         resd 4
s_cloud:        resd 4
s_tmpcol:       resd 4
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

LEAF atm_randf
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
    shr      eax, 8
    cvtsi2ss xmm0, eax
    mulss    xmm0, [rel c_inv24]
    ret

LEAF atm_randfs
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
    shr      eax, 8
    cvtsi2ss xmm0, eax
    mulss    xmm0, [rel c_inv24]
    addss    xmm0, xmm0
    subss    xmm0, [rel c_one]
    ret

LEAF atm_randint
    mov      r8d, ecx
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
    mul      r8d
    mov      eax, edx
    ret

; lowbias32
LEAF atm_hash
    mov      eax, ecx
    mov      edx, eax
    shr      edx, 16
    xor      eax, edx
    imul     eax, eax, 0x7FEB352D
    mov      edx, eax
    shr      edx, 15
    xor      eax, edx
    imul     eax, eax, 0x846CA68B
    mov      edx, eax
    shr      edx, 16
    xor      eax, edx
    ret

; smoothstep(xmm0 e0, xmm1 e1, xmm2 x), ok with e0 > e1
LEAF atm_smoothstep
    subss    xmm2, xmm0
    subss    xmm1, xmm0
    divss    xmm2, xmm1
    maxss    xmm2, [rel c_zero4]
    minss    xmm2, [rel c_one]
    movss    xmm0, [rel c_three]
    movss    xmm1, xmm2
    addss    xmm1, xmm1
    subss    xmm0, xmm1
    mulss    xmm0, xmm2
    mulss    xmm0, xmm2
    ret

; -> 0xAABBGGRR, clamped
LEAF atm_pack_rgba
    unpcklps xmm0, xmm1
    unpcklps xmm2, xmm3
    movlhps  xmm0, xmm2
    maxps    xmm0, [rel c_zero4]
    minps    xmm0, [rel c_one4]
    mulps    xmm0, [rel c_255x4]
    cvtps2dq xmm0, xmm0
    packssdw xmm0, xmm0
    packuswb xmm0, xmm0
    movd     eax, xmm0
    ret

LEAF atm_pack4
    movups   xmm0, [rcx]
    maxps    xmm0, [rel c_zero4]
    minps    xmm0, [rel c_one4]
    mulps    xmm0, [rel c_255x4]
    cvtps2dq xmm0, xmm0
    packssdw xmm0, xmm0
    packuswb xmm0, xmm0
    movd     eax, xmm0
    ret

LEAF atm_lerp4
    movups   xmm0, [rdx]
    movups   xmm1, [r8]
    subps    xmm1, xmm0
    shufps   xmm3, xmm3, 0
    mulps    xmm1, xmm3
    addps    xmm0, xmm1
    movups   [rcx], xmm0
    ret

LEAF atm_tile_uv
    mov      eax, ecx
    and      eax, 15
    cvtsi2ss xmm0, eax
    mulss    xmm0, [rel c_inv16]
    mov      eax, ecx
    shr      eax, 4
    and      eax, 15
    cvtsi2ss xmm1, eax
    mulss    xmm1, [rel c_inv16]
    ret

; col = lerp(col, lum*scale, amount)
sky_desat:
    movss    xmm0, [rcx]
    mulss    xmm0, [rel c_lum_r]
    movss    xmm3, [rcx+4]
    mulss    xmm3, [rel c_lum_g]
    addss    xmm0, xmm3
    movss    xmm3, [rcx+8]
    mulss    xmm3, [rel c_lum_b]
    addss    xmm0, xmm3
    mulss    xmm0, xmm2
    shufps   xmm0, xmm0, 0
    movups   xmm3, [rcx]
    subps    xmm0, xmm3
    shufps   xmm1, xmm1, 0
    mulps    xmm0, xmm1
    addps    xmm3, xmm0
    movups   [rcx], xmm3
    mov      dword [rcx+12], 0x3F800000
    ret

sky_scale:
    movss    xmm0, [rcx]
    mulss    xmm0, xmm1
    movss    [rcx], xmm0
    movss    xmm0, [rcx+4]
    mulss    xmm0, xmm1
    movss    [rcx+4], xmm0
    movss    xmm0, [rcx+8]
    mulss    xmm0, xmm1
    movss    [rcx+8], xmm0
    ret

; atm_draw leaves every client array disabled and colour white, so no cleanup needed
PROC atm_draw, 0
    test     edx, edx
    jz       .done
    mov      rbx, rcx
    mov      esi, edx
    mov      edi, r8d
    mov      r12d, r9d
    mov      ecx, GL_VERTEX_ARRAY
    call     glEnableClientState
    mov      ecx, GL_COLOR_ARRAY
    call     glEnableClientState
    mov      ecx, 3
    mov      edx, GL_FLOAT
    mov      r8d, 24
    mov      r9, rbx
    call     glVertexPointer
    mov      ecx, 4
    mov      edx, GL_UNSIGNED_BYTE
    mov      r8d, 24
    lea      r9, [rbx+20]
    call     glColorPointer
    test     r12d, r12d
    jz       .notex
    mov      ecx, GL_TEXTURE_COORD_ARRAY
    call     glEnableClientState
    mov      ecx, 2
    mov      edx, GL_FLOAT
    mov      r8d, 24
    lea      r9, [rbx+12]
    call     glTexCoordPointer
.notex:
    mov      ecx, edi
    xor      edx, edx
    mov      r8d, esi
    call     glDrawArrays
    mov      ecx, GL_VERTEX_ARRAY
    call     glDisableClientState
    mov      ecx, GL_COLOR_ARRAY
    call     glDisableClientState
    mov      ecx, GL_TEXTURE_COORD_ARRAY
    call     glDisableClientState
    movss    xmm0, [rel c_one]
    movss    xmm1, xmm0
    movss    xmm2, xmm0
    movss    xmm3, xmm0
    call     glColor4f
.done:
ENDP

PROCX sky_init, 32
    xor      ebx, ebx
.az:
    cvtsi2ss xmm0, ebx
    mulss    xmm0, [rel c_2pi_seg]
    call     atm_sincos
    lea      rax, [rel az_sin]
    movss    [rax+rbx*4], xmm0
    lea      rax, [rel az_cos]
    movss    [rax+rbx*4], xmm1
    inc      ebx
    cmp      ebx, AZ_SEG
    jle      .az
    ; exact seam: last column = first
    mov      eax, [rel az_cos]
    lea      rcx, [rel az_cos]
    mov      [rcx+AZ_SEG*4], eax
    mov      eax, [rel az_sin]
    lea      rcx, [rel az_sin]
    mov      [rcx+AZ_SEG*4], eax

    xor      ebx, ebx
.dome:
    lea      rax, [rel dome_el]
    movss    xmm0, [rax+rbx*4]
    call     atm_sincos
    mulss    xmm0, [rel c_skyR]
    mulss    xmm1, [rel c_skyR]
    maxss    xmm1, [rel c_zero4]
    lea      rax, [rel dome_y]
    movss    [rax+rbx*4], xmm0
    lea      rax, [rel dome_r]
    movss    [rax+rbx*4], xmm1
    inc      ebx
    cmp      ebx, DOME_RINGS
    jb       .dome

    xor      ebx, ebx
.glow:
    lea      rax, [rel glow_el]
    movss    xmm0, [rax+rbx*4]
    call     atm_sincos
    mulss    xmm0, [rel c_skyR]
    mulss    xmm1, [rel c_skyR]
    lea      rax, [rel glow_y]
    movss    [rax+rbx*4], xmm0
    lea      rax, [rel glow_r]
    movss    [rax+rbx*4], xmm1
    inc      ebx
    cmp      ebx, GLOW_RINGS
    jb       .glow

    call     sky_gen_stars
    mov      dword [rel sky_ready], 1
    mov      dword [rel g_daylight], 0x3F800000
ENDPX

; fixed seed, same sky in every world. cubic brightness -> mostly faint ones
FUNCX sky_gen_stars, 32
    mov      eax, [rel rng_state]
    mov      [rsp+FRAME_OUT], eax       ; don't let the stars eat the gameplay RNG stream
    mov      dword [rel rng_state], 0x5EED1234
    lea      r12, [rel star_vb]
    lea      r13, [rel star_dir]
    lea      r14, [rel star_tw]
    lea      r15, [rel star_tint]
    xor      ebx, ebx
.star:
.pick:
    call     atm_randfs
    movss    xmm6, xmm0
    call     atm_randfs
    movss    xmm7, xmm0
    call     atm_randfs
    movss    xmm8, xmm0
    movss    xmm9, xmm6
    mulss    xmm9, xmm6
    movss    xmm0, xmm7
    mulss    xmm0, xmm7
    addss    xmm9, xmm0
    movss    xmm0, xmm8
    mulss    xmm0, xmm8
    addss    xmm9, xmm0
    comiss   xmm9, [rel c_one]
    ja       .pick
    FCONST   xmm0, 0.01
    comiss   xmm9, xmm0
    jb       .pick
    sqrtss   xmm9, xmm9
    movss    xmm0, [rel c_one]
    divss    xmm0, xmm9
    mulss    xmm6, xmm0
    mulss    xmm7, xmm0
    mulss    xmm8, xmm0
    ; brightness b = 0.22 + 0.78 r^3, size = 0.010 + 0.024 r^3
    call     atm_randf
    movss    xmm1, xmm0
    mulss    xmm1, xmm0
    mulss    xmm1, xmm0
    FCONST   xmm10, 0.78
    mulss    xmm10, xmm1
    FCONST   xmm0, 0.22
    addss    xmm10, xmm0
    FCONST   xmm11, 0.024
    mulss    xmm11, xmm1
    FCONST   xmm0, 0.010
    addss    xmm11, xmm0
    movss    [r13+0], xmm6
    movss    [r13+4], xmm7
    movss    [r13+8], xmm8
    movss    [r13+12], xmm10
    add      r13, 16
    call     atm_randf
    mulss    xmm0, [rel c_2pi]
    movss    [r14], xmm0
    call     atm_randf
    FCONST   xmm1, 4.5
    mulss    xmm0, xmm1
    FCONST   xmm1, 1.2
    addss    xmm0, xmm1
    movss    [r14+4], xmm0
    add      r14, 8
    mov      ecx, 100
    call     atm_randint
    mov      edx, 0x00FFFFFF
    cmp      eax, 55
    jb       .tint
    mov      edx, 0x00FFE4CC ; blue-white (it's BGR)
    cmp      eax, 76
    jb       .tint
    mov      edx, 0x00C4E8FF
    cmp      eax, 93
    jb       .tint
    mov      edx, 0x00A4BCFF            ; red giant
.tint:
    mov      [r15], edx
    add      r15, 4
    ; tangent basis: t1 = dir x up, t2 = dir x t1
    movss    xmm0, xmm7
    andps    xmm0, [rel c_absmask]
    FCONST   xmm1, 0.9
    comiss   xmm0, xmm1
    ja       .upx
    movss    xmm12, xmm8
    xorps    xmm12, [rel c_signmask]
    xorps    xmm13, xmm13
    movss    xmm14, xmm6
    jmp      .basis
.upx: ; dir ~vertical, use x as up instead
    xorps    xmm12, xmm12
    movss    xmm13, xmm8
    movss    xmm14, xmm7
    xorps    xmm14, [rel c_signmask]
.basis:
    movss    xmm0, xmm12
    mulss    xmm0, xmm12
    movss    xmm1, xmm13
    mulss    xmm1, xmm13
    addss    xmm0, xmm1
    movss    xmm1, xmm14
    mulss    xmm1, xmm14
    addss    xmm0, xmm1
    sqrtss   xmm0, xmm0
    movss    xmm1, xmm11
    divss    xmm1, xmm0
    mulss    xmm12, xmm1
    mulss    xmm13, xmm1
    mulss    xmm14, xmm1
    ; t2 = dir x t1 (already size-long since dir is unit and orthogonal)
    movss    xmm0, xmm7
    mulss    xmm0, xmm14
    movss    xmm1, xmm8
    mulss    xmm1, xmm13
    subss    xmm0, xmm1
    movss    [rel tmp16b+0], xmm0
    movss    xmm0, xmm8
    mulss    xmm0, xmm12
    movss    xmm1, xmm6
    mulss    xmm1, xmm14
    subss    xmm0, xmm1
    movss    [rel tmp16b+4], xmm0
    movss    xmm0, xmm6
    mulss    xmm0, xmm13
    movss    xmm1, xmm7
    mulss    xmm1, xmm12
    subss    xmm0, xmm1
    movss    [rel tmp16b+8], xmm0
    mov      dword [rel tmp16b+12], 0
    movups   xmm15, [rel tmp16b]
    movss    [rel tmp16+0], xmm12
    movss    [rel tmp16+4], xmm13
    movss    [rel tmp16+8], xmm14
    mov      dword [rel tmp16+12], 0
    movups   xmm14, [rel tmp16]
    movss    [rel tmp16+0], xmm6
    movss    [rel tmp16+4], xmm7
    movss    [rel tmp16+8], xmm8
    movups   xmm13, [rel tmp16]
    movss    xmm0, [rel c_skyR]
    shufps   xmm0, xmm0, 0
    mulps    xmm13, xmm0
    movaps   xmm0, xmm13
    subps    xmm0, xmm14
    subps    xmm0, xmm15
    movups   [r12], xmm0
    mov      qword [r12+12], 0
    mov      dword [r12+20], 0
    movaps   xmm0, xmm13
    addps    xmm0, xmm14
    subps    xmm0, xmm15
    movups   [r12+24], xmm0
    mov      qword [r12+36], 0
    mov      dword [r12+44], 0
    movaps   xmm0, xmm13
    addps    xmm0, xmm14
    addps    xmm0, xmm15
    movups   [r12+48], xmm0
    mov      qword [r12+60], 0
    mov      dword [r12+68], 0
    movaps   xmm0, xmm13
    subps    xmm0, xmm14
    addps    xmm0, xmm15
    movups   [r12+72], xmm0
    mov      qword [r12+84], 0
    mov      dword [r12+92], 0
    add      r12, 96
    inc      ebx
    cmp      ebx, NSTARS
    jb       .star
    mov      eax, [rsp+FRAME_OUT]
    mov      [rel rng_state], eax
ENDPX

PROCX sky_update, 32
    mov      eax, [rel g_time_of_day]
    xor      edx, edx
    mov      ecx, DAY_LENGTH
    div      ecx                        ; edx = time mod 24000, just in case
    cvtsi2ss xmm0, edx
    movss    xmm1, [rel g_partial_tick]
    maxss    xmm1, [rel c_zero4]
    minss    xmm1, [rel c_one]
    addss    xmm0, xmm1
    mulss    xmm0, [rel c_inv_day]
    mulss    xmm0, [rel c_2pi]
    movss    [rel g_sun_angle], xmm0
    call     atm_sincos
    movss    [rel s_sin], xmm0
    movss    [rel s_cos], xmm1
    ; glow side: east while the sun is in the eastern half (cos > 0)
    mov      dword [rel s_hx], 0x3F800000
    xorps    xmm2, xmm2
    comiss   xmm1, xmm2
    jae      .east
    mov      dword [rel s_hx], 0xBF800000
.east:
    movss    xmm13, [rel g_rain]
    maxss    xmm13, [rel c_zero4]
    minss    xmm13, [rel c_one]
    movss    xmm14, [rel g_thunder]
    maxss    xmm14, [rel c_zero4]
    minss    xmm14, [rel c_one]
    movss    xmm15, [rel g_lightning]
    maxss    xmm15, [rel c_zero4]
    minss    xmm15, [rel c_one]

    FCONST   xmm0, -0.20
    FCONST   xmm1, 0.30
    movss    xmm2, [rel s_sin]
    call     atm_smoothstep
    movss    [rel s_dayT], xmm0
    movss    xmm6, xmm0                 ; xmm6 = dayT
    FCONST   xmm0, -0.28
    FCONST   xmm1, 0.05
    movss    xmm2, [rel s_sin]
    call     atm_smoothstep
    movss    xmm1, [rel c_one]
    subss    xmm1, xmm0
    movss    [rel s_nightraw], xmm1
    movss    xmm0, [rel c_one]
    subss    xmm0, xmm13
    mulss    xmm1, xmm0
    movss    [rel s_night], xmm1
    ; glow = (1 - smoothstep(0, 0.45, |s + 0.05|)) * (1 - 0.85 rain)
    movss    xmm2, [rel s_sin]
    FCONST   xmm0, 0.05
    addss    xmm2, xmm0
    andps    xmm2, [rel c_absmask]
    xorps    xmm0, xmm0
    FCONST   xmm1, 0.45
    call     atm_smoothstep
    movss    xmm1, [rel c_one]
    subss    xmm1, xmm0
    FCONST   xmm0, 0.85
    mulss    xmm0, xmm13
    movss    xmm2, [rel c_one]
    subss    xmm2, xmm0
    mulss    xmm1, xmm2
    movss    [rel s_glow], xmm1
    movss    xmm7, xmm1                 ; xmm7 = glow

    FCONST   xmm0, 0.85
    mulss    xmm0, xmm6
    FCONST   xmm1, 0.15
    addss    xmm0, xmm1
    FCONST   xmm1, 0.30
    mulss    xmm1, xmm13
    movss    xmm2, [rel c_one]
    subss    xmm2, xmm1
    mulss    xmm0, xmm2                 ; rain: up to -30%
    FCONST   xmm1, 0.25
    mulss    xmm1, xmm14
    movss    xmm2, [rel c_one]
    subss    xmm2, xmm1
    mulss    xmm0, xmm2                 ; thunder: up to -25%
    movss    xmm1, [rel c_one]          ; lightning: d += (1-d) * L * 0.75
    subss    xmm1, xmm0
    mulss    xmm1, xmm15
    FCONST   xmm2, 0.75
    mulss    xmm1, xmm2
    addss    xmm0, xmm1
    FCONST   xmm1, 0.15
    maxss    xmm0, xmm1
    minss    xmm0, [rel c_one]
    movss    [rel g_daylight], xmm0

    lea      rcx, [rel g_sky_color]
    lea      rdx, [rel col_night_zen]
    lea      r8,  [rel col_day_zen]
    movss    xmm3, xmm6
    call     atm_lerp4
    lea      rcx, [rel g_sky_color]
    mov      rdx, rcx
    lea      r8,  [rel col_glow_zen]
    FCONST   xmm3, 0.22
    mulss    xmm3, xmm7
    call     atm_lerp4

    lea      rcx, [rel g_fog_color]
    lea      rdx, [rel col_night_fog]
    lea      r8,  [rel col_day_fog]
    movss    xmm3, xmm6
    call     atm_lerp4
    ; facing factor f = max(0, dot(horizontal cam dir, sun side))
    movss    xmm0, [rel g_cam_dir]
    movss    xmm1, [rel g_cam_dir+8]
    movss    xmm2, xmm0
    mulss    xmm2, xmm0
    movss    xmm3, xmm1
    mulss    xmm3, xmm1
    addss    xmm2, xmm3
    sqrtss   xmm2, xmm2
    xorps    xmm8, xmm8
    FCONST   xmm3, 0.0001
    comiss   xmm2, xmm3
    jb       .nofacing
    movss    xmm8, xmm0
    mulss    xmm8, [rel s_hx]
    divss    xmm8, xmm2
    maxss    xmm8, [rel c_zero4]
.nofacing:
    mulss    xmm8, xmm8
    FCONST   xmm0, 0.72
    mulss    xmm8, xmm0
    FCONST   xmm0, 0.28
    addss    xmm8, xmm0
    mulss    xmm8, xmm7
    FCONST   xmm0, 0.78
    mulss    xmm8, xmm0
    lea      rcx, [rel g_fog_color]
    mov      rdx, rcx
    lea      r8,  [rel col_glow]
    movss    xmm3, xmm8
    call     atm_lerp4

    lea      rcx, [rel s_cloud]
    lea      rdx, [rel col_cloud_ngt]
    lea      r8,  [rel col_cloud_day]
    movss    xmm3, xmm6
    call     atm_lerp4
    lea      rcx, [rel s_cloud]
    mov      rdx, rcx
    lea      r8,  [rel col_cloud_set]
    FCONST   xmm3, 0.70
    mulss    xmm3, xmm7
    call     atm_lerp4

    lea      rcx, [rel g_sky_color]
    FCONST   xmm1, 0.80
    mulss    xmm1, xmm13
    FCONST   xmm2, 0.55
    call     sky_desat
    lea      rcx, [rel g_fog_color]
    FCONST   xmm1, 0.72
    mulss    xmm1, xmm13
    FCONST   xmm2, 0.62
    call     sky_desat
    lea      rcx, [rel s_cloud]
    FCONST   xmm1, 0.80
    mulss    xmm1, xmm13
    FCONST   xmm2, 0.60
    call     sky_desat
    FCONST   xmm9, 0.40
    mulss    xmm9, xmm14
    movss    xmm0, [rel c_one]
    subss    xmm0, xmm9
    movss    xmm9, xmm0
    lea      rcx, [rel g_sky_color]
    movss    xmm1, xmm9
    call     sky_scale
    lea      rcx, [rel g_fog_color]
    movss    xmm1, xmm9
    call     sky_scale
    lea      rcx, [rel s_cloud]
    movss    xmm1, xmm9
    call     sky_scale

    lea      rcx, [rel g_sky_color]
    mov      rdx, rcx
    lea      r8,  [rel col_flash]
    FCONST   xmm3, 0.50
    mulss    xmm3, xmm15
    call     atm_lerp4
    lea      rcx, [rel g_fog_color]
    mov      rdx, rcx
    lea      r8,  [rel col_flash]
    FCONST   xmm3, 0.40
    mulss    xmm3, xmm15
    call     atm_lerp4
    lea      rcx, [rel s_cloud]
    mov      rdx, rcx
    lea      r8,  [rel col_flash]
    FCONST   xmm3, 0.60
    mulss    xmm3, xmm15
    call     atm_lerp4

    mov      eax, [rel g_settings+SETTINGS.render_dist]
    cmp      eax, 2
    jge      .rd_lo
    mov      eax, 2
.rd_lo:
    cmp      eax, MAX_RENDER_DIST
    jle      .rd_hi
    mov      eax, MAX_RENDER_DIST
.rd_hi:
    shl      eax, 4
    sub      eax, 8
    cvtsi2ss xmm0, eax                  ; end = rd*16 - 8
    FCONST   xmm1, 0.12
    mulss    xmm1, xmm13
    movss    xmm2, [rel c_one]
    subss    xmm2, xmm1
    mulss    xmm0, xmm2                 ; rain pulls the wall in a little
    FCONST   xmm1, 0.25
    mulss    xmm1, xmm13
    FCONST   xmm2, 0.60
    subss    xmm2, xmm1                 ; start = (0.60 - 0.25 rain) * end
    mulss    xmm2, xmm0
    movss    [rel g_fog_end], xmm0
    movss    [rel g_fog_start], xmm2

    ; void below the horizon is just a darker horizon
    lea      rcx, [rel s_void]
    lea      rdx, [rel g_fog_color]
    lea      r8,  [rel c_zero4]
    FCONST   xmm3, 0.72
    call     atm_lerp4
    mov      dword [rel s_void+12], 0x3F800000

    mov      dword [rel s_medium], 0
    cmp      dword [rel g_world_active], 0
    je       .air
    cmp      dword [rel g_player+PLAYER.eye_in_water], 0
    jne      .water
    movss    xmm0, [rel g_cam_pos]
    FLOORI   ecx, xmm0, xmm1
    movss    xmm0, [rel g_cam_pos+4]
    FLOORI   edx, xmm0, xmm1
    movss    xmm0, [rel g_cam_pos+8]
    FLOORI   r8d, xmm0, xmm1
    call     world_get_block
    cmp      eax, B_LAVA
    jb       .air
    cmp      eax, B_LAVA_LAST
    ja       .air
    ; lava: you see ~2 blocks
    mov      dword [rel s_medium], 2
    movups   xmm0, [rel col_lava_fog]
    movups   [rel g_fog_color], xmm0
    movups   [rel g_sky_color], xmm0
    mov      dword [rel g_fog_start], 0
    FCONST   xmm0, 2.5
    movss    [rel g_fog_end], xmm0
    jmp      .air
.water:
    mov      dword [rel s_medium], 1
    movups   xmm0, [rel col_water_fog]
    movss    xmm1, [rel g_daylight]
    FCONST   xmm2, 0.15
    maxss    xmm1, xmm2
    shufps   xmm1, xmm1, 0
    mulps    xmm0, xmm1
    movups   [rel g_fog_color], xmm0
    movups   [rel g_sky_color], xmm0
    mov      dword [rel g_fog_color+12], 0x3F800000
    mov      dword [rel g_sky_color+12], 0x3F800000
    FCONST   xmm0, 2.0
    movss    [rel g_fog_start], xmm0
    FCONST   xmm0, 18.0
    movss    [rel g_fog_end], xmm0
.air:
    mov      dword [rel g_sky_color+12], 0x3F800000
    mov      dword [rel g_fog_color+12], 0x3F800000
ENDPX

; emitters below are private leaves, rdi = write ptr (advanced)

dome_vtx:
    lea      rax, [rel dome_r]
    movss    xmm0, [rax+rcx*4]
    lea      rax, [rel az_cos]
    movss    xmm1, [rax+rdx*4]
    mulss    xmm1, xmm0
    lea      rax, [rel az_sin]
    movss    xmm2, [rax+rdx*4]
    mulss    xmm2, xmm0
    lea      rax, [rel dome_y]
    movss    xmm0, [rax+rcx*4]
    movss    [rdi], xmm1
    movss    [rdi+4], xmm0
    movss    [rdi+8], xmm2
    mov      qword [rdi+12], 0
    lea      rax, [rel ring_col]
    mov      eax, [rax+rcx*4]
    mov      [rdi+20], eax
    add      rdi, 24
    ret

glow_vtx:
    lea      rax, [rel glow_r]
    movss    xmm0, [rax+rcx*4]
    lea      rax, [rel az_cos]
    movss    xmm1, [rax+rdx*4]
    mulss    xmm1, xmm0
    lea      rax, [rel az_sin]
    movss    xmm2, [rax+rdx*4]
    mulss    xmm2, xmm0
    lea      rax, [rel glow_y]
    movss    xmm0, [rax+rcx*4]
    movss    [rdi], xmm1
    movss    [rdi+4], xmm0
    movss    [rdi+8], xmm2
    mov      qword [rdi+12], 0
    lea      rax, [rel glow_ef]
    movss    xmm0, [rax+rcx*4]
    lea      rax, [rel az_f]
    mulss    xmm0, [rax+rdx*4]
    mulss    xmm0, [rel s_glow]
    mulss    xmm0, [rel c_255]
    minss    xmm0, [rel c_255]
    cvttss2si eax, xmm0
    shl      eax, 24
    or       eax, r9d
    mov      [rdi+20], eax
    add      rdi, 24
    ret

PROCX sky_render, 64
    cmp      dword [rel sky_ready], 0
    jne      .ready
    call     sky_init
.ready:
    mov      ecx, GL_DEPTH_TEST
    call     glDisable
    xor      ecx, ecx
    call     glDepthMask
    mov      ecx, GL_CULL_FACE
    call     glDisable
    mov      ecx, GL_TEXTURE_2D
    call     glDisable

    xor      ebx, ebx
.rc:
    lea      rax, [rel dome_wsky]
    movss    xmm0, [rax+rbx*4]
    shufps   xmm0, xmm0, 0
    movups   xmm1, [rel g_sky_color]
    mulps    xmm1, xmm0
    lea      rax, [rel dome_wfog]
    movss    xmm0, [rax+rbx*4]
    shufps   xmm0, xmm0, 0
    movups   xmm2, [rel g_fog_color]
    mulps    xmm2, xmm0
    addps    xmm1, xmm2
    lea      rax, [rel dome_wvoid]
    movss    xmm0, [rax+rbx*4]
    shufps   xmm0, xmm0, 0
    movups   xmm2, [rel s_void]
    mulps    xmm2, xmm0
    addps    xmm1, xmm2
    movups   [rel tmp16], xmm1
    mov      dword [rel tmp16+12], 0x3F800000
    lea      rcx, [rel tmp16]
    call     atm_pack4
    lea      rcx, [rel ring_col]
    mov      [rcx+rbx*4], eax
    inc      ebx
    cmp      ebx, DOME_RINGS
    jb       .rc

    lea      rdi, [rel s_vbuf]
    xor      r12d, r12d
.band:
    xor      r13d, r13d
.seg:
    mov      ecx, r12d
    mov      edx, r13d
    call     dome_vtx
    mov      ecx, r12d
    lea      edx, [r13+1]
    call     dome_vtx
    lea      ecx, [r12+1]
    lea      edx, [r13+1]
    call     dome_vtx
    lea      ecx, [r12+1]
    mov      edx, r13d
    call     dome_vtx
    inc      r13d
    cmp      r13d, AZ_SEG
    jb       .seg
    inc      r12d
    cmp      r12d, DOME_RINGS-1
    jb       .band
    lea      rcx, [rel s_vbuf]
    mov      edx, (DOME_RINGS-1)*AZ_SEG*4
    mov      r8d, GL_QUADS
    xor      r9d, r9d
    call     atm_draw

    cmp      dword [rel s_medium], 0
    jne      .restore

    mov      ecx, GL_BLEND
    call     glEnable
    mov      ecx, GL_SRC_ALPHA
    mov      edx, GL_ONE_MINUS_SRC_ALPHA
    call     glBlendFunc

    movss    xmm0, [rel s_glow]
    FCONST   xmm1, 0.004
    comiss   xmm0, xmm1
    jb       .noglow
    ; azimuth factor: 0.10 + 0.90 * max(0, cos(az) * hx)^3
    xor      ebx, ebx
.azf:
    lea      rax, [rel az_cos]
    movss    xmm0, [rax+rbx*4]
    mulss    xmm0, [rel s_hx]
    maxss    xmm0, [rel c_zero4]
    movss    xmm1, xmm0
    mulss    xmm1, xmm0
    mulss    xmm1, xmm0
    FCONST   xmm2, 0.90
    mulss    xmm1, xmm2
    FCONST   xmm2, 0.10
    addss    xmm1, xmm2
    lea      rax, [rel az_f]
    movss    [rax+rbx*4], xmm1
    inc      ebx
    cmp      ebx, AZ_SEG
    jle      .azf
    lea      rcx, [rel col_glow]
    call     atm_pack4
    and      eax, 0x00FFFFFF
    mov      r14d, eax
    lea      rdi, [rel s_vbuf]
    xor      r12d, r12d
.gband:
    xor      r13d, r13d
.gseg:
    mov      r9d, r14d
    mov      ecx, r12d
    mov      edx, r13d
    call     glow_vtx
    mov      ecx, r12d
    lea      edx, [r13+1]
    call     glow_vtx
    lea      ecx, [r12+1]
    lea      edx, [r13+1]
    call     glow_vtx
    lea      ecx, [r12+1]
    mov      edx, r13d
    call     glow_vtx
    inc      r13d
    cmp      r13d, AZ_SEG
    jb       .gseg
    inc      r12d
    cmp      r12d, GLOW_RINGS-1
    jb       .gband
    lea      rcx, [rel s_vbuf]
    mov      edx, (GLOW_RINGS-1)*AZ_SEG*4
    mov      r8d, GL_QUADS
    xor      r9d, r9d
    call     atm_draw
.noglow:

    call     glPushMatrix
    movss    xmm0, [rel c_tilt_deg]
    movss    xmm1, [rel c_one]
    xorps    xmm2, xmm2
    xorps    xmm3, xmm3
    call     glRotatef
    movss    xmm0, [rel g_sun_angle]
    mulss    xmm0, [rel c_rad2deg]
    xorps    xmm1, xmm1
    xorps    xmm2, xmm2
    movss    xmm3, [rel c_one]
    call     glRotatef
    mov      ecx, GL_SRC_ALPHA
    mov      edx, GL_ONE
    call     glBlendFunc                ; additive from here on

    movss    xmm0, [rel s_night]
    FCONST   xmm1, 0.004
    comiss   xmm0, xmm1
    jb       .nostars
    call     sky_update_stars
    lea      rcx, [rel star_vb]
    mov      edx, NSTARS*4
    mov      r8d, GL_QUADS
    xor      r9d, r9d
    call     atm_draw
.nostars:

    mov      ecx, GL_TEXTURE_2D
    call     glEnable

    ; fade by elevation so the sun never shows through the void
    movss    xmm2, [rel s_sin]
    mulss    xmm2, [rel c_tilt_cos]
    FCONST   xmm0, -0.14
    FCONST   xmm1, 0.04
    call     atm_smoothstep
    movss    xmm1, [rel c_one]
    subss    xmm1, [rel g_rain]
    maxss    xmm1, [rel c_zero4]
    mulss    xmm0, xmm1
    movss    xmm12, xmm0
    FCONST   xmm1, 0.003
    comiss   xmm12, xmm1
    jb       .nosun
    lea      rcx, [rel tmp16]
    lea      rdx, [rel col_sun_white]
    lea      r8,  [rel col_sun_red]
    movss    xmm3, [rel s_glow]
    call     atm_lerp4
    movss    [rel tmp16+12], xmm12
    lea      rcx, [rel tmp16]
    call     atm_pack4
    mov      r14d, eax
    mov      ecx, T_SUN
    call     atm_tile_uv
    addss    xmm0, [rel c_halftexel]
    addss    xmm1, [rel c_halftexel]
    movss    xmm8, xmm0
    movss    xmm9, xmm1
    movss    xmm10, xmm0
    addss    xmm10, [rel c_tile_in]
    movss    xmm11, xmm1
    addss    xmm11, [rel c_tile_in]
    lea      rdi, [rel s_vbuf]
    movss    xmm4, [rel c_skyR]
    FCONST   xmm5, SUN_HALF
    movss    xmm3, xmm5
    xorps    xmm3, [rel c_signmask]
    VTX      rdi, xmm4, xmm5, xmm3, xmm8, xmm9, r14d
    VTX      rdi, xmm4, xmm5, xmm5, xmm10, xmm9, r14d
    VTX      rdi, xmm4, xmm3, xmm5, xmm10, xmm11, r14d
    VTX      rdi, xmm4, xmm3, xmm3, xmm8, xmm11, r14d
    lea      rcx, [rel s_vbuf]
    mov      edx, 4
    mov      r8d, GL_QUADS
    mov      r9d, 1
    call     atm_draw
.nosun:
    call     sky_draw_moon
    call     glPopMatrix

.restore:
    mov      ecx, GL_SRC_ALPHA
    mov      edx, GL_ONE_MINUS_SRC_ALPHA
    call     glBlendFunc
    mov      ecx, GL_BLEND
    call     glDisable
    mov      ecx, GL_TEXTURE_2D
    call     glEnable
    mov      ecx, GL_CULL_FACE
    call     glEnable
    mov      ecx, 1
    call     glDepthMask
    mov      ecx, GL_DEPTH_TEST
    call     glEnable
ENDPX

; star alpha = twinkle * night * horizon fade. the fade wants world elevation,
; so both rotations get redone on the cpu:
;   y1 = dx*sin a + dy*cos a   (Z rotation by the sun angle)
;   y2 = y1*cos t - dz*sin t   (tilt about X)
FUNCX sky_update_stars, 32
    ; tt = fmod(time_total, 1000) as float, keeps the sin args small
    movsd    xmm0, [rel g_time_total]
    movsd    xmm1, xmm0
    divsd    xmm1, [rel c_1000d]
    roundsd  xmm1, xmm1, 1
    mulsd    xmm1, [rel c_1000d]
    subsd    xmm0, xmm1
    cvtsd2ss xmm13, xmm0
    movss    xmm14, [rel s_sin]
    movss    xmm15, [rel s_cos]
    lea      r12, [rel star_dir]
    lea      r13, [rel star_tw]
    lea      r14, [rel star_tint]
    lea      r15, [rel star_vb]
    xor      ebx, ebx
.s:
    movss    xmm6, [r12]
    mulss    xmm6, xmm14
    movss    xmm0, [r12+4]
    mulss    xmm0, xmm15
    addss    xmm6, xmm0
    mulss    xmm6, [rel c_tilt_cos]
    movss    xmm0, [r12+8]
    mulss    xmm0, [rel c_tilt_sin]
    subss    xmm6, xmm0                 ; y2 = world elevation
    FCONST   xmm0, -0.03
    FCONST   xmm1, 0.20
    movss    xmm2, xmm6
    call     atm_smoothstep
    movss    xmm7, xmm0
    xor      esi, esi
    xorps    xmm1, xmm1
    comiss   xmm7, xmm1
    jbe      .write
    movss    xmm0, [r13+4]
    mulss    xmm0, xmm13
    addss    xmm0, [r13]
    call     atm_sincos
    FCONST   xmm1, 0.30
    mulss    xmm0, xmm1
    FCONST   xmm1, 0.70
    addss    xmm0, xmm1                 ; twinkle 0.4 .. 1.0
    mulss    xmm0, xmm7
    mulss    xmm0, [r12+12]
    mulss    xmm0, [rel s_night]
    mulss    xmm0, [rel c_255]
    minss    xmm0, [rel c_255]
    cvttss2si esi, xmm0
.write:
    shl      esi, 24
    or       esi, [r14]
    mov      [r15+20], esi
    mov      [r15+44], esi
    mov      [r15+68], esi
    mov      [r15+92], esi
    add      r12, 16
    add      r13, 8
    add      r14, 4
    add      r15, 96
    inc      ebx
    cmp      ebx, NSTARS
    jb       .s
ENDPX

; moon phases, cut out of the real texture in 16 slices
;   phase p = (world_time / 24000) mod 8, k = cos(p * pi/4)
;   waning (p < 4): lit x in [-w, k*w], waxing: lit x in [-k*w, w]
;   w(y) = sqrt(1 - y^2) = limb half-width
FUNCX sky_draw_moon, 32
    ; moon elevation is just -sun elevation
    movss    xmm2, [rel s_sin]
    mulss    xmm2, [rel c_tilt_cos]
    xorps    xmm2, [rel c_signmask]
    FCONST   xmm0, -0.14
    FCONST   xmm1, 0.04
    call     atm_smoothstep
    movss    xmm12, xmm0
    movss    xmm1, [rel s_nightraw]
    FCONST   xmm2, 0.65
    mulss    xmm1, xmm2
    FCONST   xmm2, 0.35
    addss    xmm1, xmm2
    mulss    xmm12, xmm1
    movss    xmm1, [rel c_one]
    subss    xmm1, [rel g_rain]
    maxss    xmm1, [rel c_zero4]
    mulss    xmm12, xmm1
    FCONST   xmm1, 0.003
    comiss   xmm12, xmm1
    jb       .done
    mov      ecx, T_MOON
    call     atm_tile_uv
    addss    xmm0, [rel c_halftexel]
    addss    xmm1, [rel c_halftexel]
    movss    xmm8, xmm0
    movss    xmm9, xmm1
    mov      rax, [rel g_world_time]
    xor      edx, edx
    mov      ecx, DAY_LENGTH
    div      rcx
    and      eax, 7
    mov      r15d, eax                  ; phase 0 full .. 4 new .. 7
    cvtsi2ss xmm0, eax
    mulss    xmm0, [rel c_pi_4]
    call     atm_sincos
    movss    xmm13, xmm1

    ; earthshine
    FCONST   xmm0, 0.10
    mulss    xmm0, xmm12
    movss    xmm3, xmm0
    movss    xmm0, [rel c_one]
    movss    xmm1, xmm0
    movss    xmm2, xmm0
    call     atm_pack_rgba
    mov      r14d, eax
    movss    xmm10, xmm8
    addss    xmm10, [rel c_tile_in]
    movss    xmm11, xmm9
    addss    xmm11, [rel c_tile_in]
    lea      rdi, [rel s_vbuf]
    movss    xmm4, [rel c_skyR]
    xorps    xmm4, [rel c_signmask]
    FCONST   xmm5, MOON_HALF
    movss    xmm3, xmm5
    xorps    xmm3, [rel c_signmask]
    VTX      rdi, xmm4, xmm5, xmm3, xmm8, xmm9, r14d
    VTX      rdi, xmm4, xmm5, xmm5, xmm10, xmm9, r14d
    VTX      rdi, xmm4, xmm3, xmm5, xmm10, xmm11, r14d
    VTX      rdi, xmm4, xmm3, xmm3, xmm8, xmm11, r14d

    cmp      r15d, 4
    je       .emit                      ; new moon: only earthshine
    movss    xmm3, xmm12
    movss    xmm0, [rel c_one]
    movss    xmm1, xmm0
    movss    xmm2, xmm0
    call     atm_pack_rgba
    mov      r14d, eax
    xor      ebx, ebx
.slice:
    mov      esi, ebx
    call     .row                       ; xmm6 = L, xmm7 = R, xmm14 = yl (row ebx)
    movss    [rel tmp16+0], xmm6
    movss    [rel tmp16+4], xmm7
    movss    [rel tmp16+8], xmm14
    lea      esi, [rbx+1]
    call     .row
    movss    xmm0, [rel tmp16+0]
    movss    xmm1, [rel tmp16+8]
    call     .vert
    movss    xmm0, [rel tmp16+4]
    movss    xmm1, [rel tmp16+8]
    call     .vert
    movss    xmm0, xmm7
    movss    xmm1, xmm14
    call     .vert
    movss    xmm0, xmm6
    movss    xmm1, xmm14
    call     .vert
    inc      ebx
    cmp      ebx, MOON_SLICES
    jb       .slice
.emit:
    lea      rcx, [rel s_vbuf]
    mov      rdx, rdi
    sub      rdx, rcx
    mov      eax, edx
    xor      edx, edx
    mov      ecx, 24
    div      ecx
    mov      edx, eax
    lea      rcx, [rel s_vbuf]
    mov      r8d, GL_QUADS
    mov      r9d, 1
    call     atm_draw
    jmp      .done

; .row: no calls inside, so the misaligned rsp from the local call doesn't matter. hacky but works
.row:
    cvtsi2ss xmm14, esi
    FCONST   xmm0, 0.125              ; 2 / MOON_SLICES
    mulss    xmm14, xmm0
    subss    xmm14, [rel c_one]
    movss    xmm0, xmm14
    mulss    xmm0, xmm14
    movss    xmm1, [rel c_one]
    subss    xmm1, xmm0
    maxss    xmm1, [rel c_zero4]
    sqrtss   xmm1, xmm1
    movss    xmm2, xmm1
    mulss    xmm2, xmm13
    cmp      r15d, 4
    jae      .waxing
    movss    xmm6, xmm1
    xorps    xmm6, [rel c_signmask]
    movss    xmm7, xmm2
    ret
.waxing:
    movss    xmm6, xmm2
    xorps    xmm6, [rel c_signmask]
    movss    xmm7, xmm1
    ret

; .vert: xmm0 = xl, xmm1 = yl (unit disc) -> vertex at (-R, yl*h, xl*h)
.vert:
    movss    xmm4, [rel c_skyR]
    xorps    xmm4, [rel c_signmask]
    movss    [rdi], xmm4
    FCONST   xmm5, MOON_HALF
    movss    xmm2, xmm1
    mulss    xmm2, xmm5
    movss    [rdi+4], xmm2
    movss    xmm2, xmm0
    mulss    xmm2, xmm5
    movss    [rdi+8], xmm2
    mulss    xmm0, [rel c_half]
    addss    xmm0, [rel c_half]
    mulss    xmm0, [rel c_tile_in]
    addss    xmm0, xmm8
    movss    [rdi+12], xmm0
    mulss    xmm1, [rel c_half]
    movss    xmm2, [rel c_half]
    subss    xmm2, xmm1
    mulss    xmm2, [rel c_tile_in]
    addss    xmm2, xmm9
    movss    [rdi+16], xmm2
    mov      [rdi+20], r14d
    add      rdi, 24
    ret
.done:
ENDPX

; cpu copy of the cloud map. read g_tex_clouds back once, or build our own
; noise texture if there isn't one
FUNCX clouds_ensure_map, 32
    mov      eax, [rel g_tex_clouds]
    cmp      dword [rel cmap_ready], 0
    je       .build
    cmp      eax, [rel cmap_src]
    je       .done
.build:
    mov      dword [rel cmap_ready], 1
    mov      [rel cmap_src], eax
    mov      [rel cloud_tex], eax
    test     eax, eax
    jz       .generate
    ; clear first so a failed readback shows up as "empty"
    lea      rcx, [rel cbuf]
    mov      rdx, 256*256*4
    call     .zero
    mov      ecx, GL_TEXTURE_2D
    mov      edx, [rel g_tex_clouds]
    call     glBindTexture
    mov      ecx, GL_TEXTURE_2D
    xor      edx, edx
    mov      r8d, GL_RGBA
    mov      r9d, GL_UNSIGNED_BYTE
    lea      rax, [rel cbuf]
    mov      [rsp+32], rax
    call     glGetTexImage
    mov      ecx, GL_TEXTURE_2D
    mov      edx, [rel g_tex_atlas]
    call     glBindTexture
    ; threshold at half of the maximum alpha
    lea      rsi, [rel cbuf]
    xor      ecx, ecx
    xor      ebx, ebx
.max:
    movzx    eax, byte [rsi+rcx*4+3]
    cmp      eax, ebx
    cmova    ebx, eax
    inc      ecx
    cmp      ecx, 256*256
    jb       .max
    test     ebx, ebx
    jz       .generate
    shr      ebx, 1
    lea      rdi, [rel cmap]
    xor      ecx, ecx
.thr:
    movzx    eax, byte [rsi+rcx*4+3]
    cmp      eax, ebx
    seta     al
    mov      [rdi+rcx], al
    inc      ecx
    cmp      ecx, 256*256
    jb       .thr
    ; flat layer samples the edited copy so it lines up with the boxes
    call     clouds_carve
    call     clouds_thin
    jmp      .own

.generate:
    call     clouds_generate
    call     clouds_carve
    call     clouds_thin
.own:
    cmp      dword [rel cloud_own], 0
    jne      .upload
    mov      ecx, 1
    lea      rdx, [rel cloud_own]
    call     glGenTextures
.upload:
    mov      ecx, GL_TEXTURE_2D
    mov      edx, [rel cloud_own]
    call     glBindTexture
    mov      ecx, GL_TEXTURE_2D
    mov      edx, GL_TEXTURE_MIN_FILTER
    mov      r8d, GL_NEAREST
    call     glTexParameteri
    mov      ecx, GL_TEXTURE_2D
    mov      edx, GL_TEXTURE_MAG_FILTER
    mov      r8d, GL_NEAREST
    call     glTexParameteri
    mov      ecx, GL_TEXTURE_2D
    mov      edx, GL_TEXTURE_WRAP_S
    mov      r8d, GL_REPEAT
    call     glTexParameteri
    mov      ecx, GL_TEXTURE_2D
    mov      edx, GL_TEXTURE_WRAP_T
    mov      r8d, GL_REPEAT
    call     glTexParameteri
    mov      ecx, GL_TEXTURE_2D
    xor      edx, edx
    mov      r8d, GL_RGBA
    mov      r9d, 256
    mov      dword [rsp+32], 256
    mov      dword [rsp+40], 0
    mov      dword [rsp+48], GL_RGBA
    mov      dword [rsp+56], GL_UNSIGNED_BYTE
    lea      rax, [rel cbuf]
    mov      [rsp+64], rax
    call     glTexImage2D
    mov      ecx, GL_TEXTURE_2D
    mov      edx, [rel g_tex_atlas]
    call     glBindTexture
    mov      eax, [rel cloud_own]
    test     eax, eax
    jz       .done
    mov      [rel cloud_tex], eax
    jmp      .done
.zero:                                  ; rcx = ptr, rdx = bytes (multiple of 8)
    shr      rdx, 3
.zl:
    mov      qword [rcx], 0
    add      rcx, 8
    dec      rdx
    jnz      .zl
    ret
.done:
ENDPX

; tileable value noise, lattice wraps at 256>>shift so it repeats with the map
FUNCX cl_vnoise, 0
    mov      r12d, ecx
    mov      r13d, edx
    mov      r14d, r8d
    mov      r15d, r9d
    mov      ecx, r14d
    mov      eax, r12d
    shr      eax, cl
    mov      esi, eax
    mov      eax, r13d
    shr      eax, cl
    mov      edi, eax
    mov      eax, 1
    shl      eax, cl
    dec      eax
    mov      edx, r12d
    and      edx, eax
    cvtsi2ss xmm8, edx
    mov      edx, r13d
    and      edx, eax
    cvtsi2ss xmm9, edx
    inc      eax
    cvtsi2ss xmm0, eax
    divss    xmm8, xmm0
    divss    xmm9, xmm0
    movss    xmm0, [rel c_three]
    movss    xmm1, xmm8
    addss    xmm1, xmm1
    subss    xmm0, xmm1
    mulss    xmm0, xmm8
    mulss    xmm8, xmm0
    movss    xmm0, [rel c_three]
    movss    xmm1, xmm9
    addss    xmm1, xmm1
    subss    xmm0, xmm1
    mulss    xmm0, xmm9
    mulss    xmm9, xmm0
    mov      eax, 256
    shr      eax, cl
    dec      eax
    mov      ebx, eax
    mov      ecx, esi
    mov      edx, edi
    call     .lat
    movss    xmm10, xmm0
    lea      ecx, [rsi+1]
    mov      edx, edi
    call     .lat
    movss    xmm11, xmm0
    mov      ecx, esi
    lea      edx, [rdi+1]
    call     .lat
    movss    xmm12, xmm0
    lea      ecx, [rsi+1]
    lea      edx, [rdi+1]
    call     .lat
    subss    xmm0, xmm12
    mulss    xmm0, xmm8
    addss    xmm0, xmm12
    subss    xmm11, xmm10
    mulss    xmm11, xmm8
    addss    xmm11, xmm10
    subss    xmm0, xmm11
    mulss    xmm0, xmm9
    addss    xmm0, xmm11
    jmp      .done
; calling atm_hash from a local sub is fine, it's a leaf
.lat:
    and      ecx, ebx
    and      edx, ebx
    imul     ecx, ecx, 0x27D4EB2D
    imul     edx, edx, 0x165667B1
    xor      ecx, edx
    mov      eax, r15d
    imul     eax, eax, 0x9E3779B9
    xor      ecx, eax
    call     atm_hash
    shr      eax, 8
    cvtsi2ss xmm0, eax
    mulss    xmm0, [rel c_inv24]
    ret
.done:
ENDPX

; fallback when texgen gave nothing: 3 octaves (192/96/48 block features)
FUNCX clouds_generate, 32
    xor      r12d, r12d
.y:
    xor      r13d, r13d
.x:
    xorps    xmm6, xmm6
    mov      r14d, 4                    ; log2(cell) 4,3,2
    FCONST   xmm7, 0.55
.oct:
    mov      ecx, r13d
    mov      edx, r12d
    mov      r8d, r14d
    mov      r9d, r14d
    call     cl_vnoise
    mulss    xmm0, xmm7
    addss    xmm6, xmm0
    mulss    xmm7, [rel c_half]
    dec      r14d
    cmp      r14d, 2
    jge      .oct
    mov      eax, r12d
    shl      eax, 8
    add      eax, r13d
    lea      rdx, [rel cmap]
    lea      r8, [rel cbuf]
    mov      dword [r8+rax*4], 0x00FFFFFF
    mov      byte [rdx+rax], 0
    FCONST   xmm0, 0.50
    comiss   xmm6, xmm0
    jbe      .clear
    mov      dword [r8+rax*4], 0xFFFFFFFF
    mov      byte [rdx+rax], 1
.clear:
    inc      r13d
    cmp      r13d, 256
    jb       .x
    inc      r12d
    cmp      r12d, 256
    jb       .y
ENDPX

; clouds_carve. thresholded fbm clumps into a few huge banks (~7000 cells, ~1000
; blocks across) and from below that's just an overcast ceiling. so cut channels
; along jittered voronoi edges (warped by noise so they wander), but only where
; D = cloud cells in the 9x9 window is > 40. airy maps pass through untouched
%define CARVE_CELL      8           ; Voronoi cell, texels (divides 256)
%define CARVE_DMIN      40          ; carve where D > this (of 81)
FUNCX clouds_carve, 32
    ; horizontal 9-sums -> cscore, then vertical -> cdens
    lea      rsi, [rel cmap]
    lea      rdi, [rel cscore]
    xor      r12d, r12d
.hy:
    xor      r13d, r13d
.hx:
    xor      eax, eax
    mov      ecx, -4
.hk:
    lea      edx, [r13+rcx]
    and      edx, 255
    mov      r8d, r12d
    shl      r8d, 8
    add      edx, r8d
    movzx    edx, byte [rsi+rdx]
    add      eax, edx
    inc      ecx
    cmp      ecx, 4
    jle      .hk
    mov      edx, r12d
    shl      edx, 8
    add      edx, r13d
    mov      [rdi+rdx], al
    inc      r13d
    cmp      r13d, 256
    jb       .hx
    inc      r12d
    cmp      r12d, 256
    jb       .hy
    lea      rsi, [rel cscore]
    lea      rdi, [rel cdens]
    xor      r12d, r12d
.vy:
    xor      r13d, r13d
.vx:
    xor      eax, eax
    mov      ecx, -4
.vk:
    lea      edx, [r12+rcx]
    and      edx, 255
    shl      edx, 8
    add      edx, r13d
    movzx    edx, byte [rsi+rdx]
    add      eax, edx
    inc      ecx
    cmp      ecx, 4
    jle      .vk
    mov      edx, r12d
    shl      edx, 8
    add      edx, r13d
    mov      [rdi+rdx], al
    inc      r13d
    cmp      r13d, 256
    jb       .vx
    inc      r12d
    cmp      r12d, 256
    jb       .vy

    xor      r12d, r12d
.cy:
    xor      r13d, r13d
.cx:
    mov      r14d, r12d
    shl      r14d, 8
    add      r14d, r13d
    lea      rax, [rel cmap]
    cmp      byte [rax+r14], 0
    je       .cnext
    lea      rax, [rel cdens]
    cmp      byte [rax+r14], CARVE_DMIN
    jbe      .cnext
    ; warped sample position (wx, wy) = (x, y) + 2 * (2 n - 1)
    mov      ecx, r13d
    mov      edx, r12d
    mov      r8d, 2
    mov      r9d, 77
    call     cl_vnoise
    addss    xmm0, xmm0
    subss    xmm0, [rel c_one]
    addss    xmm0, xmm0
    cvtsi2ss xmm8, r13d
    addss    xmm8, xmm0
    mov      ecx, r13d
    mov      edx, r12d
    mov      r8d, 2
    mov      r9d, 78
    call     cl_vnoise
    addss    xmm0, xmm0
    subss    xmm0, [rel c_one]
    addss    xmm0, xmm0
    cvtsi2ss xmm9, r12d
    addss    xmm9, xmm0
    ; can be -1 or 32 near the seam
    movss    xmm0, xmm8
    FCONST   xmm1, 0.125
    mulss    xmm0, xmm1
    roundss  xmm0, xmm0, 1
    cvttss2si esi, xmm0
    movss    xmm0, xmm9
    mulss    xmm0, xmm1
    roundss  xmm0, xmm0, 1
    cvttss2si edi, xmm0
    ; F1/F2, squared
    FCONST   xmm6, 1.0e9
    movss    xmm7, xmm6
    mov      r15d, -1
.ny:
    mov      ebx, -1
.nx:
    lea      eax, [rsi+rbx]
    lea      edx, [rdi+r15]
    mov      [rsp+FRAME_OUT], eax
    mov      [rsp+FRAME_OUT+4], edx
    and      eax, 255/CARVE_CELL
    and      edx, 255/CARVE_CELL
    imul     ecx, eax, 0x27D4EB2D
    imul     edx, edx, 0x165667B1
    xor      ecx, edx
    xor      ecx, 0xC10D
    call     atm_hash
    ; point = cell * 8 + jitter in [0, 8): byte * 8/256
    mov      edx, eax
    and      edx, 255
    cvtsi2ss xmm0, edx
    FCONST   xmm1, 0.03125
    mulss    xmm0, xmm1
    mov      ecx, [rsp+FRAME_OUT]
    shl      ecx, 3
    cvtsi2ss xmm2, ecx
    addss    xmm0, xmm2
    subss    xmm0, xmm8
    shr      eax, 8
    and      eax, 255
    cvtsi2ss xmm2, eax
    mulss    xmm2, xmm1
    mov      ecx, [rsp+FRAME_OUT+4]
    shl      ecx, 3
    cvtsi2ss xmm3, ecx
    addss    xmm2, xmm3
    subss    xmm2, xmm9
    mulss    xmm0, xmm0
    mulss    xmm2, xmm2
    addss    xmm0, xmm2
    comiss   xmm0, xmm6
    jae      .not1
    movss    xmm7, xmm6
    movss    xmm6, xmm0
    jmp      .nn
.not1:
    minss    xmm7, xmm0
.nn:
    inc      ebx
    cmp      ebx, 1
    jle      .nx
    inc      r15d
    cmp      r15d, 1
    jle      .ny
    ; on an edge when sqrt(F2) - sqrt(F1) < 1.2
    sqrtss   xmm6, xmm6
    sqrtss   xmm7, xmm7
    subss    xmm7, xmm6
    FCONST   xmm0, 1.2
    comiss   xmm7, xmm0
    jae      .cnext
    lea      rax, [rel cmap]
    mov      byte [rax+r14], 0
    lea      rax, [rel cbuf]
    mov      byte [rax+r14*4+3], 0
.cnext:
    inc      r13d
    cmp      r13d, 256
    jb       .cx
    inc      r12d
    cmp      r12d, 256
    jb       .cy
ENDPX

; atm_cloud_map() -> rax pointer to the 256x256 occupancy map (tests)
LEAF atm_cloud_map
    lea      rax, [rel cmap]
    ret

; clouds_thin: caps cover at CLOUD_COVER_MAX%. score = two noise octaves + a bit of
; alpha (dense cores survive), histogram picks the cut that keeps ~CLOUD_COVER%
FUNCX clouds_thin, 32
    lea      rsi, [rel cmap]
    xor      ecx, ecx
    xor      ebx, ebx
.cnt:
    movzx    eax, byte [rsi+rcx]
    add      ebx, eax
    inc      ecx
    cmp      ecx, 256*256
    jb       .cnt
    xor      eax, eax
    cmp      ebx, 65536*CLOUD_COVER_MAX/100
    jbe      .done
    lea      rdi, [rel chist]
    xor      ecx, ecx
.hz:
    mov      dword [rdi+rcx*4], 0
    inc      ecx
    cmp      ecx, 256
    jb       .hz
    xor      r12d, r12d
.sy:
    xor      r13d, r13d
.sx:
    mov      r14d, r12d
    shl      r14d, 8
    add      r14d, r13d
    lea      rax, [rel cmap]
    cmp      byte [rax+r14], 0
    je       .snext
    mov      ecx, r13d
    mov      edx, r12d
    mov      r8d, 3
    mov      r9d, 0x5EED1
    call     cl_vnoise
    FCONST   xmm1, 0.60
    mulss    xmm0, xmm1
    movss    xmm6, xmm0
    mov      ecx, r13d
    mov      edx, r12d
    mov      r8d, 2
    mov      r9d, 0x5EED2
    call     cl_vnoise
    FCONST   xmm1, 0.25
    mulss    xmm0, xmm1
    addss    xmm6, xmm0
    lea      rax, [rel cbuf]
    movzx    eax, byte [rax+r14*4+3]
    cvtsi2ss xmm0, eax
    FCONST   xmm1, 0.000588235          ; 0.15 / 255
    mulss    xmm0, xmm1
    addss    xmm6, xmm0
    FCONST   xmm1, 255.99
    mulss    xmm6, xmm1
    cvttss2si eax, xmm6
    cmp      eax, 255
    jbe      .q
    mov      eax, 255
.q:
    lea      rcx, [rel cscore]
    mov      [rcx+r14], al
    lea      rcx, [rel chist]
    inc      dword [rcx+rax*4]
.snext:
    inc      r13d
    cmp      r13d, 256
    jb       .sx
    inc      r12d
    cmp      r12d, 256
    jb       .sy
    lea      rdi, [rel chist]
    mov      ecx, 255
    xor      edx, edx
.cut:
    add      edx, [rdi+rcx*4]
    cmp      edx, 65536*CLOUD_COVER/100
    jae      .have
    dec      ecx
    jnz      .cut
.have:
    lea      rsi, [rel cmap]
    lea      rdi, [rel cbuf]
    lea      r8, [rel cscore]
    xor      eax, eax
.drop:
    cmp      byte [rsi+rax], 0
    je       .dnext
    movzx    edx, byte [r8+rax]
    cmp      edx, ecx
    jae      .dnext
    mov      byte [rsi+rax], 0
    mov      byte [rdi+rax*4+3], 0
.dnext:
    inc      eax
    cmp      eax, 256*256
    jb       .drop
    mov      eax, 1
.done:
ENDPX

; cl_inner > 0: fade in from 0.75*inner to inner (far layer behind the boxes)
FUNCX clouds_flat, 32
    movss    xmm6, [rel cl_rc]
    movss    xmm7, xmm6
    addss    xmm7, xmm7
    FCONST   xmm0, 32.0
    divss    xmm7, xmm0
    lea      r12, [rel calpha]
    xor      r13d, r13d
.aj:
    xor      r14d, r14d
.ai:
    cvtsi2ss xmm8, r14d
    mulss    xmm8, xmm7
    subss    xmm8, xmm6
    cvtsi2ss xmm9, r13d
    mulss    xmm9, xmm7
    subss    xmm9, xmm6
    mulss    xmm8, xmm8
    mulss    xmm9, xmm9
    addss    xmm8, xmm9
    sqrtss   xmm8, xmm8
    movss    xmm0, xmm6
    FCONST   xmm1, 0.40
    mulss    xmm0, xmm1
    movss    xmm1, xmm6
    FCONST   xmm2, 0.97
    mulss    xmm1, xmm2
    movss    xmm2, xmm8
    call     atm_smoothstep
    movss    xmm9, [rel c_one]
    subss    xmm9, xmm0
    movss    xmm0, [rel cl_inner]
    xorps    xmm1, xmm1
    comiss   xmm0, xmm1
    jbe      .noinner
    movss    xmm1, xmm0
    FCONST   xmm2, 0.75
    mulss    xmm0, xmm2
    movss    xmm2, xmm8
    call     atm_smoothstep
    mulss    xmm9, xmm0
.noinner:
    mulss    xmm9, [rel cl_alpha]
    movss    [r12], xmm9
    add      r12, 4
    inc      r14d
    cmp      r14d, FLAT_N
    jle      .ai
    inc      r13d
    cmp      r13d, FLAT_N
    jle      .aj

    movups   xmm0, [rel cl_col_flat]
    movups   [rel s_tmpcol], xmm0
    lea      rdi, [rel c_vbuf]
    xor      r13d, r13d
.qj:
    xor      r14d, r14d
.qi:
    mov      ecx, r14d
    mov      edx, r13d
    call     .vert
    lea      ecx, [r14+1]
    mov      edx, r13d
    call     .vert
    lea      ecx, [r14+1]
    lea      edx, [r13+1]
    call     .vert
    mov      ecx, r14d
    lea      edx, [r13+1]
    call     .vert
    inc      r14d
    cmp      r14d, FLAT_N
    jb       .qi
    inc      r13d
    cmp      r13d, FLAT_N
    jb       .qj
    mov      ecx, GL_TEXTURE_2D
    mov      edx, [rel cloud_tex]
    call     glBindTexture
    lea      rcx, [rel c_vbuf]
    mov      edx, FLAT_N*FLAT_N*4
    mov      r8d, GL_QUADS
    mov      r9d, 1
    call     atm_draw
    mov      ecx, GL_TEXTURE_2D
    mov      edx, [rel g_tex_atlas]
    call     glBindTexture
    jmp      .done

.vert:
    mov      r8d, edx
    imul     r8d, r8d, FLAT_N+1
    add      r8d, ecx
    lea      rax, [rel calpha]
    movss    xmm3, [rax+r8*4]
    cvtsi2ss xmm0, ecx
    mulss    xmm0, xmm7
    subss    xmm0, xmm6
    cvtsi2ss xmm2, edx
    mulss    xmm2, xmm7
    subss    xmm2, xmm6
    movss    [rdi], xmm0
    movss    xmm1, [rel cl_yrel]
    movss    [rdi+4], xmm1
    movss    [rdi+8], xmm2
    movss    xmm1, xmm0
    mulss    xmm1, [rel c_inv_cperiod]
    addss    xmm1, [rel cl_uo]
    movss    [rdi+12], xmm1
    movss    xmm1, xmm2
    mulss    xmm1, [rel c_inv_cperiod]
    addss    xmm1, [rel cl_vo]
    movss    [rdi+16], xmm1
    movss    xmm0, [rel s_tmpcol]
    movss    xmm1, [rel s_tmpcol+4]
    movss    xmm2, [rel s_tmpcol+8]
    call     atm_pack_rgba
    mov      [rdi+20], eax
    add      rdi, 24
    ret
.done:
ENDPX

; fancy: one box per cell within FANCY_R, only faces toward the cam that border air
FUNCX clouds_fancy, 64
    lea      rdi, [rel c_vbuf]
    mov      r12d, -FANCY_R
.cj:
    mov      r13d, -FANCY_R
.ci:
    mov      eax, r12d
    imul     eax, eax
    mov      ecx, r13d
    imul     ecx, ecx
    add      eax, ecx
    cmp      eax, FANCY_R*FANCY_R+FANCY_R
    jg       .next
    mov      ecx, r13d
    mov      edx, r12d
    call     .occ
    test     eax, eax
    jz       .next
    cvtsi2ss xmm8, r13d
    mulss    xmm8, [rel c_cell]
    subss    xmm8, [rel cl_fx]
    movss    xmm9, xmm8
    addss    xmm9, [rel c_cell]
    movss    xmm10, [rel cl_yrel]
    movss    xmm11, xmm10
    addss    xmm11, [rel c_thick]
    cvtsi2ss xmm12, r12d
    mulss    xmm12, [rel c_cell]
    subss    xmm12, [rel cl_fz]
    movss    xmm13, xmm12
    addss    xmm13, [rel c_cell]
    xorps    xmm15, xmm15
    ; top (cam above)
    comiss   xmm11, xmm15
    jae      .notop
    lea      r14, [rel cl_col_top]
    movss    xmm0, xmm8
    movss    xmm1, xmm11
    movss    xmm2, xmm12
    call     .v
    movss    xmm0, xmm8
    movss    xmm2, xmm13
    call     .v
    movss    xmm0, xmm9
    movss    xmm2, xmm13
    call     .v
    movss    xmm0, xmm9
    movss    xmm2, xmm12
    call     .v
.notop:
    comiss   xmm10, xmm15
    jbe      .nobot
    lea      r14, [rel cl_col_bot]
    movss    xmm0, xmm8
    movss    xmm1, xmm10
    movss    xmm2, xmm12
    call     .v
    movss    xmm0, xmm9
    movss    xmm2, xmm12
    call     .v
    movss    xmm0, xmm9
    movss    xmm2, xmm13
    call     .v
    movss    xmm0, xmm8
    movss    xmm2, xmm13
    call     .v
.nobot:
    comiss   xmm8, xmm15
    jbe      .nowest
    lea      ecx, [r13-1]
    mov      edx, r12d
    call     .occ
    test     eax, eax
    jnz      .nowest
    lea      r14, [rel cl_col_sx]
    movss    xmm0, xmm8
    call     .xface
.nowest:
    comiss   xmm9, xmm15
    jae      .noeast
    lea      ecx, [r13+1]
    mov      edx, r12d
    call     .occ
    test     eax, eax
    jnz      .noeast
    lea      r14, [rel cl_col_sx]
    movss    xmm0, xmm9
    call     .xface
.noeast:
    comiss   xmm12, xmm15
    jbe      .nonorth
    mov      ecx, r13d
    lea      edx, [r12-1]
    call     .occ
    test     eax, eax
    jnz      .nonorth
    lea      r14, [rel cl_col_sz]
    movss    xmm2, xmm12
    call     .zface
.nonorth:
    comiss   xmm13, xmm15
    jae      .next
    mov      ecx, r13d
    lea      edx, [r12+1]
    call     .occ
    test     eax, eax
    jnz      .next
    lea      r14, [rel cl_col_sz]
    movss    xmm2, xmm13
    call     .zface
.next:
    inc      r13d
    cmp      r13d, FANCY_R
    jle      .ci
    inc      r12d
    cmp      r12d, FANCY_R
    jle      .cj

    lea      rcx, [rel c_vbuf]
    mov      rax, rdi
    sub      rax, rcx
    xor      edx, edx
    mov      ecx, 24
    div      rcx
    mov      ebx, eax
    test     ebx, ebx
    jz       .done
    ; depth only first, otherwise you see the inner faces through the translucent boxes
    xor      ecx, ecx
    xor      edx, edx
    xor      r8d, r8d
    xor      r9d, r9d
    call     glColorMask
    mov      ecx, 1
    call     glDepthMask
    lea      rcx, [rel c_vbuf]
    mov      edx, ebx
    mov      r8d, GL_QUADS
    xor      r9d, r9d
    call     atm_draw
    mov      ecx, 1
    mov      edx, 1
    mov      r8d, 1
    mov      r9d, 1
    call     glColorMask
    xor      ecx, ecx
    call     glDepthMask
    lea      rcx, [rel c_vbuf]
    mov      edx, ebx
    mov      r8d, GL_QUADS
    xor      r9d, r9d
    call     atm_draw
    jmp      .done

.occ:
    add      ecx, [rel cl_ci]
    add      edx, [rel cl_cj]
    and      ecx, 255
    and      edx, 255
    shl      edx, 8
    add      edx, ecx
    lea      rax, [rel cmap]
    movzx    eax, byte [rax+rdx]
    ret
.xface:
    movss    xmm4, xmm0
    movss    xmm1, xmm10
    movss    xmm2, xmm12
    call     .v
    movss    xmm0, xmm4
    movss    xmm1, xmm11
    movss    xmm2, xmm12
    call     .v
    movss    xmm0, xmm4
    movss    xmm1, xmm11
    movss    xmm2, xmm13
    call     .v
    movss    xmm0, xmm4
    movss    xmm1, xmm10
    movss    xmm2, xmm13
    call     .v
    ret
.zface:
    movss    xmm4, xmm2
    movss    xmm0, xmm8
    movss    xmm1, xmm10
    call     .v
    movss    xmm0, xmm9
    movss    xmm1, xmm10
    movss    xmm2, xmm4
    call     .v
    movss    xmm0, xmm9
    movss    xmm1, xmm11
    movss    xmm2, xmm4
    call     .v
    movss    xmm0, xmm8
    movss    xmm1, xmm11
    movss    xmm2, xmm4
    call     .v
    ret
; .v trashes xmm0 xmm3 xmm5 rax. reloads xmm1/xmm2 so the caller can reuse them
.v:
    movss    [rdi], xmm0
    movss    [rdi+4], xmm1
    movss    [rdi+8], xmm2
    mov      qword [rdi+12], 0
    mulss    xmm0, xmm0
    movss    xmm3, xmm2
    mulss    xmm3, xmm3
    addss    xmm0, xmm3
    sqrtss   xmm0, xmm0
    FCONST   xmm3, 144.0              ; FANCY_R * CLOUD_CELL
    divss    xmm0, xmm3
    FCONST   xmm3, 0.55
    subss    xmm0, xmm3
    FCONST   xmm3, 2.2222222            ; 1/(1-0.55)
    mulss    xmm0, xmm3
    maxss    xmm0, [rel c_zero4]
    minss    xmm0, [rel c_one]
    movss    xmm3, [rel c_three]
    movss    xmm5, xmm0
    addss    xmm5, xmm5
    subss    xmm3, xmm5
    mulss    xmm3, xmm0
    mulss    xmm3, xmm0
    movss    xmm5, [rel c_one]
    subss    xmm5, xmm3
    mulss    xmm5, [rel cl_alpha]
    movups   xmm3, [r14]
    insertps xmm3, xmm5, 0x30
    maxps    xmm3, [rel c_zero4]
    minps    xmm3, [rel c_one4]
    mulps    xmm3, [rel c_255x4]
    cvtps2dq xmm3, xmm3
    packssdw xmm3, xmm3
    packuswb xmm3, xmm3
    movd     eax, xmm3
    mov      [rdi+20], eax
    add      rdi, 24
    ret
.done:
ENDPX

; called after the opaque world
PROCX sky_render_clouds, 64
    mov      eax, [rel g_settings+SETTINGS.clouds]
    test     eax, eax
    jz       .done
    mov      r15d, eax                  ; 1 fast, 2 fancy
    cmp      dword [rel s_medium], 0
    jne      .done
    cmp      dword [rel sky_ready], 0
    jne      .ready
    call     sky_init
.ready:
    call     clouds_ensure_map

    ; drift: integer ticks mod the period first, then doubles, so clouds stay sharp
    ; millions of blocks out
    mov      rax, [rel g_world_time]
    xor      edx, edx
    mov      ecx, CLOUD_WRAP
    div      rcx
    cvtsi2sd xmm0, rdx
    movss    xmm1, [rel g_partial_tick]
    maxss    xmm1, [rel c_zero4]
    minss    xmm1, [rel c_one]
    cvtss2sd xmm1, xmm1
    addsd    xmm0, xmm1
    mulsd    xmm0, [rel c_speed_d]
    ; sampling at x - drift moves clouds toward +X (east)
    cvtss2sd xmm1, [rel g_cam_pos]
    subsd    xmm1, xmm0
    movsd    xmm0, xmm1
    cvtss2sd xmm2, [rel g_cam_pos+8]
    movsd    xmm3, xmm0
    mulsd    xmm3, [rel c_inv_period_d]
    movsd    xmm4, xmm3
    roundsd  xmm4, xmm4, 1
    subsd    xmm3, xmm4
    cvtsd2ss xmm3, xmm3
    movss    [rel cl_uo], xmm3
    movsd    xmm3, xmm2
    mulsd    xmm3, [rel c_inv_period_d]
    movsd    xmm4, xmm3
    roundsd  xmm4, xmm4, 1
    subsd    xmm3, xmm4
    cvtsd2ss xmm3, xmm3
    movss    [rel cl_vo], xmm3
    movsd    xmm3, xmm0
    mulsd    xmm3, [rel c_inv_cell_d]
    roundsd  xmm3, xmm3, 1
    cvttsd2si rax, xmm3
    mov      [rel cl_ci], eax
    mulsd    xmm3, [rel c_cell_d]
    subsd    xmm0, xmm3
    cvtsd2ss xmm0, xmm0
    movss    [rel cl_fx], xmm0
    movsd    xmm3, xmm2
    mulsd    xmm3, [rel c_inv_cell_d]
    roundsd  xmm3, xmm3, 1
    cvttsd2si rax, xmm3
    mov      [rel cl_cj], eax
    mulsd    xmm3, [rel c_cell_d]
    subsd    xmm2, xmm3
    cvtsd2ss xmm2, xmm2
    movss    [rel cl_fz], xmm2
    FCONST   xmm0, CLOUD_Y
    subss    xmm0, [rel g_cam_pos+4]
    movss    [rel cl_yrel], xmm0
    ; underside is 0.9 + 30% sky tint. a flat 0.7 grey turns overhead banks into an
    ; overcast ceiling and goes muddy brown at sunset
    CLOUD_FACE cl_col_top, 1.00, 0.00
    CLOUD_FACE cl_col_sx,  0.92, 0.10
    CLOUD_FACE cl_col_sz,  0.84, 0.14
    CLOUD_FACE cl_col_bot, 0.90, 0.30
    ; the flat layer shows its top from above, its underside from below
    movups   xmm0, [rel cl_col_top]
    xorps    xmm1, xmm1
    movss    xmm2, [rel cl_yrel]
    comiss   xmm2, xmm1
    jbe      .above
    movups   xmm0, [rel cl_col_bot]
.above:
    movups   [rel cl_col_flat], xmm0
    ; base alpha (rain makes the sky one grey sheet)
    FCONST   xmm0, 0.80
    movss    xmm1, [rel g_rain]
    FCONST   xmm2, 0.12
    mulss    xmm1, xmm2
    addss    xmm0, xmm1
    movss    [rel cl_alpha], xmm0
    mov      eax, [rel g_settings+SETTINGS.render_dist]
    imul     eax, eax, 40
    cmp      eax, 192
    jge      .e1
    mov      eax, 192
.e1:
    cmp      eax, 512
    jle      .e2
    mov      eax, 512
.e2:
    cvtsi2ss xmm0, eax
    movss    [rel cl_rc], xmm0
    ; don't go past the far plane: far = m14 / (m10 + 1), column-major
    mov      ecx, GL_PROJECTION_MATRIX
    lea      rdx, [rel cl_proj]
    call     glGetFloatv
    movss    xmm0, [rel cl_proj+40]
    addss    xmm0, [rel c_one]
    movss    xmm1, xmm0
    andps    xmm1, [rel c_absmask]
    FCONST   xmm2, 0.000001
    comiss   xmm1, xmm2
    jb       .farok
    movss    xmm1, [rel cl_proj+56]
    divss    xmm1, xmm0
    FCONST   xmm2, 0.92
    mulss    xmm1, xmm2
    FCONST   xmm2, 32.0
    comiss   xmm1, xmm2
    jb       .farok                     ; not a sane perspective matrix
    minss    xmm1, [rel cl_rc]
    movss    [rel cl_rc], xmm1
.farok:

    mov      ecx, GL_CULL_FACE
    call     glDisable
    mov      ecx, GL_BLEND
    call     glEnable
    mov      ecx, GL_SRC_ALPHA
    mov      edx, GL_ONE_MINUS_SRC_ALPHA
    call     glBlendFunc
    xor      ecx, ecx
    call     glDepthMask

    cmp      r15d, 2
    jae      .fancy
    mov      dword [rel cl_inner], 0
    call     clouds_flat
    jmp      .restore
.fancy:
    movss    xmm0, [rel cl_yrel]
    addss    xmm0, [rel c_two]
    movss    [rel cl_yrel], xmm0
    FCONST   xmm0, 144.0
    movss    [rel cl_inner], xmm0
    call     clouds_flat
    movss    xmm0, [rel cl_yrel]
    subss    xmm0, [rel c_two]
    movss    [rel cl_yrel], xmm0
    mov      ecx, GL_TEXTURE_2D
    call     glDisable
    call     clouds_fancy
    mov      ecx, GL_TEXTURE_2D
    call     glEnable
.restore:
    mov      ecx, 1
    call     glDepthMask
    mov      ecx, GL_BLEND
    call     glDisable
    mov      ecx, GL_CULL_FACE
    call     glEnable
    mov      ecx, GL_TEXTURE_2D
    mov      edx, [rel g_tex_atlas]
    call     glBindTexture
.done:
ENDPX

section .rdata
align 4
c_inv_cperiod:  dd 0.000325520833
c_cell:         dd CLOUD_CELL
c_thick:        dd CLOUD_THICK
