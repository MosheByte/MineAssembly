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
