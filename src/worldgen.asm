; MineAssembly worldgen. deterministic per seed. worker threads gen chunks in
; parallel, so all scratch lives in a heap ctx per call.
; shaping runs on continuous weights, never on the biome id, or you get cliffs at biome borders
%define IMPL_WORLDGEN
%include "common.inc"

; private frames, same as PROC/PROCX but not exported
%macro FN 1-2 0
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

%macro FNX 1-2 0
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

; smoothstep(e0,e1, xmm2) -> xmm0  (clobbers eax, xmm1-xmm3)
%macro SSTEP 2
    FCONST xmm0, %1
    FCONST xmm1, %2
    call wg_ss
%endmacro

; noise at (x*freq+ox, z*freq+oz), x/z come from xmm6/xmm7
%macro NOISE2AT 5
    FCONST xmm2, %2
    movaps xmm0, xmm6
    mulss  xmm0, xmm2
    mulss  xmm2, xmm7
    movaps xmm1, xmm2
    FCONST xmm2, %3
    addss  xmm0, xmm2
    FCONST xmm2, %4
    addss  xmm1, xmm2
    mov    r8d, %5
    call   %1
%endmacro

; COLP = 32 byte grid sample, COL = 64 byte per column. first 8 floats match.
%define P_H      0
%define P_T      4
%define P_W      8
%define P_C      12
%define P_MNT    16
%define P_RIV    20
%define P_OVH    24     ; 3D overhang amplitude (blocks)
%define P_SW     28
%define C_HF     32
%define C_HS     36     ; floor(HF)
%define C_BIOME  40
%define C_SLOPE  44     ; max dH per block
%define C_ENTR   48     ; 1 = cave entrance column
%define C_TOP    52     ; highest y that can be solid
%define COLP_SZ  32
%define COL_SZ   64

%define GRID_N   13     ; 13x13 grid points cover the 3x3 chunk area
%define COLS_N   18     ; columns -1..16 of the current chunk
%define OVH_NY   17     ; 3D overhang lattice: y step 8 -> 0..128
%define CAVE_NY  34     ; cave lattice: y step 4 -> 0..132
%define CAVE_FS  (CAVE_NY*25)

struc WG
    .chunk   resq 1
    .rng     resq 1     ; candidate stream
    .trng    resq 1     ; shape rolls
    .ox      resd 1
    .oz      resd 1
    .mode    resd 1     ; 0 = clip to .chunk, 1 = world_set_block
    .logid   resd 1
    .leafid  resd 1
    .maxtop  resd 1
    .ovhmax  resd 1
    .ncave   resd 1
    .cx      resd 1
    .cz      resd 1
    .tmp     resb 64
    .tmp2    resb 64
    .ends    resb 64    ; branch tips
    .grid    resb GRID_N*GRID_N*COLP_SZ
    .cols    resb COLS_N*COLS_N*COL_SZ
    .ovh     resd 5*OVH_NY*5
    .cave    resd 3*CAVE_FS
    .colv    resd 3*CAVE_NY
endstruc
%define WG_HDR 256      ; trees only touch this much of WG, a stack ctx is enough

%define K_LEAF   1      ; only into air / small plants
%define K_LOG    2      ; also replaces leaves and water
%define K_STONE  8
%define K_GROUND 16
%define K_FORCE  128    ; anything but bedrock

%define TR_OAK      1
%define TR_BIGOAK   2
%define TR_BIRCH    3
%define TR_PINE     4
%define TR_GIANT    5
%define TR_JTALL    6
%define TR_BUSH     7
%define TR_ACACIA   8
%define TR_SWAMP    9

%define S_BEDROCK   0x0B5D
%define S_SURF      0x5F2A
%define S_ORE       0x07E1
%define S_TREE      0x7EE5
%define S_SHAPE     0x5A9E
%define S_LEAF      0x1EAF
%define S_PLANT     0x91A7
%define S_FLOWER    0xF10E
%define S_GLOW      0x6C0A
%define S_RUIN      0x2D17
%define S_DROOP     0xD200
%define S_SAPLING   0x5AB1

%define TREE_CAND   20
%define BOULDER_CAND 2

section .rdata
align 16
; C -> base height
spl_cont:
    dd -1.40, 28.0
    dd -0.60, 33.0
    dd -0.32, 44.0
    dd -0.16, 53.0
    dd -0.07, 59.5
    dd  0.00, 63.2
    dd  0.12, 65.5
    dd  0.35, 69.0
    dd  0.75, 76.0
    dd  1.40, 84.0
%define SPL_N 10

align 16
k_absmask:   dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
k_spread:    dd 2.0         ; fbm2 sd is ~0.33, stretch to ~0.66
k_c_bias:    dd 0.22        ; shifts C so ~35% is ocean
k_pv_lo:     dd 0.30        ; ridged2 value where peaks start
k_pv_mul:    dd 1.9
k_e_hi:      dd 0.05        ; erosion: mountains fade in below e_hi ...
k_e_lo:      dd -0.45       ; ... and are at full strength below e_lo
k_riv_w:     dd 0.050       ; |RV| below this = river channel
k_riv_bank:  dd 0.17        ; |RV| below this = river valley
k_zero:      dd 0.0
k_quarter:   dd 0.25
k_half:      dd 0.5
k_eighth:    dd 0.125
k_tunnel:    dd 0.030       ; spaghetti tunnel radius^2 in noise units
k_cheese0:   dd 0.40        ; cavern threshold at y=0 ...
k_cheese_dy: dd 0.0035      ; ... rising by this per block (fewer caverns up high)

; climate table [temp band][humidity band]. the hottest+driest corner is badlands,
; with desert around it
climate_tbl:
    db BIOME_TUNDRA,  BIOME_TUNDRA,  BIOME_TAIGA,   BIOME_TAIGA
    db BIOME_PLAINS,  BIOME_BIRCH,   BIOME_BIRCH,   BIOME_TAIGA
    db BIOME_PLAINS,  BIOME_PLAINS,  BIOME_FOREST,  BIOME_FOREST
    db BIOME_DESERT,  BIOME_SAVANNA, BIOME_SAVANNA, BIOME_JUNGLE
    db BIOME_BADLANDS, BIOME_DESERT, BIOME_SAVANNA, BIOME_JUNGLE

align 4
; per biome: chance that a tree candidate becomes a tree
tree_density:
    dd 0.0, 0.0, 0.035, 0.50, 0.45, 0.42, 0.03, 0.0, 0.10, 0.20, 0.95, 0.06, 0.0
boulder_density:
    dd 0.0, 0.0, 0.04, 0.05, 0.05, 0.45, 0.15, 0.0, 0.25, 0.0, 0.0, 0.05, 0.0
; tall grass chance per column (x/65536)
grass_chance:
    dd 0, 0, 20000, 12000, 13000, 7000, 1500, 0, 6000, 16000, 26000, 28000, 0

; id, veins/chunk, ymin, ymax, min size, size range. min+range <= 16 (see wg_vein)
ore_tbl:
    db B_COAL_ORE,    20,  5, 120, 6, 9
    db B_IRON_ORE,    14,  5,  64, 4, 6
    db B_GOLD_ORE,     3,  5,  32, 4, 5
    db B_DIAMOND_ORE,  2,  4,  16, 3, 5
    db B_GRAVEL,       6,  5, 100, 9, 7
    db B_DIRT,         6, 20, 100, 9, 7
%define ORE_N 6

dirs8:
    db 1,0, 1,1, 0,1, -1,1, -1,0, -1,-1, 0,-1, 1,-1

; badlands layers by (y + shift) & 31. mostly plain with thin coloured stripes
%define TC B_TERRACOTTA
band_tbl:
    db TC+0, TC+0, TC+1, TC+0, TC+2, TC+0, TC+0, TC+5
    db TC+0, TC+1, TC+1, TC+0, TC+3, TC+0, TC+0, TC+4
    db TC+0, TC+0, TC+2, TC+0, TC+0, TC+1, TC+0, TC+0
    db TC+3, TC+3, TC+0, TC+5, TC+0, TC+4, TC+0, TC+0

pine_pat:
    db 1,1,2,1,2,2,3,2,3,2,3,3,2,3,3,3,3,3,3,3

; which write kinds may overwrite each block id
align 16
wg_repl:
%assign id 0
%rep 256
  %if id == B_AIR || id == B_TALL_GRASS || id == B_FLOWER_RED || id == B_FLOWER_YELLOW || id == B_MUSHROOM_RED || id == B_MUSHROOM_BROWN || id == B_DEAD_BUSH || id == B_SAPLING
    db K_LEAF | K_LOG
  %elif id == B_LEAVES || id == B_BIRCH_LEAVES || id == B_PINE_LEAVES || (id >= B_WATER && id <= B_WATER_LAST)
    db K_LOG                            ; trunks push through leaves / swamp water
  %elif id == B_STONE
    db K_STONE
  %elif id == B_GRASS || id == B_SNOWY_GRASS
    db K_GROUND
  %else
    db 0
  %endif
  %assign id id+1
%endrep

section .text


; smoothstep, e0 > e1 works too (inverted)
align 16
wg_ss:
    subss  xmm1, xmm0
    subss  xmm2, xmm0
    divss  xmm2, xmm1
    xorps  xmm3, xmm3
    maxss  xmm2, xmm3
    FCONST xmm3, 1.0
    minss  xmm2, xmm3
    movaps xmm0, xmm2
    mulss  xmm0, xmm2
    addss  xmm2, xmm2
    FCONST xmm3, 3.0
    subss  xmm3, xmm2
    mulss  xmm0, xmm3
    ret

; piecewise linear over (x,y) pairs at rcx, edx = count. clamped at both ends
align 16
wg_spline:
    comiss xmm0, [rcx]
    jbe    .first
    mov    r8d, 1
.l:
    cmp    r8d, edx
    jae    .last
    comiss xmm0, [rcx+r8*8]
    jb     .seg
    inc    r8d
    jmp    .l
.seg:
    movss  xmm1, [rcx+r8*8-8]
    movss  xmm2, [rcx+r8*8]
    subss  xmm2, xmm1
    subss  xmm0, xmm1
    divss  xmm0, xmm2
    movss  xmm1, [rcx+r8*8-4]
    movss  xmm2, [rcx+r8*8+4]
    subss  xmm2, xmm1
    mulss  xmm0, xmm2
    addss  xmm0, xmm1
    ret
.first:
    movss  xmm0, [rcx+4]
    ret
.last:
    lea    r8d, [rdx-1]
    movss  xmm0, [rcx+r8*8+4]
    ret

; hash(ecx, edx, r8d) salted with r9d + seed. trashes rcx rdx r8 r9
align 16
wg_hash:
    imul   ecx, ecx, 0x27D4EB2F
    imul   edx, edx, 0x165667B1
    imul   r8d, r8d, 0x9E3779B1
    imul   r9d, r9d, 0x85EBCA77
    mov    eax, [rel g_seed]
    xor    eax, [rel g_seed+4]
    xor    eax, r9d
    add    eax, ecx
    rol    eax, 13
    xor    eax, edx
    rol    eax, 11
    add    eax, r8d
    mov    ecx, eax
    shr    ecx, 16
    xor    eax, ecx
    imul   eax, eax, 0x85EBCA6B
    mov    ecx, eax
    shr    ecx, 13
    xor    eax, ecx
    imul   eax, eax, 0xC2B2AE35
    mov    ecx, eax
    shr    ecx, 16
    xor    eax, ecx
    ret

; xorshift64*, clobbers rdx
%macro XS64 0
    mov    rdx, rax
    shr    rdx, 12
    xor    rax, rdx
    mov    rdx, rax
    shl    rdx, 25
    xor    rax, rdx
    mov    rdx, rax
    shr    rdx, 27
    xor    rax, rdx
%endmacro

; rand = candidate stream, trand = shape stream. both clobber rdx
align 16
wg_rand:
    mov    rax, [rbx+WG.rng]
    XS64
    mov    [rbx+WG.rng], rax
    mov    rdx, 0x2545F4914F6CDD1D
    imul   rax, rdx
    shr    rax, 32
    ret
align 16
wg_trand:
    mov    rax, [rbx+WG.trng]
    XS64
    mov    [rbx+WG.trng], rax
    mov    rdx, 0x2545F4914F6CDD1D
    imul   rax, rdx
    shr    rax, 32
    ret
; ecx n -> [0,n)
align 16
wg_trandn:
    push   rcx
    call   wg_trand
    pop    rcx
    imul   rax, rcx
    shr    rax, 32
    ret
align 16
wg_randn:
    push   rcx
    call   wg_rand
    pop    rcx
    imul   rax, rcx
    shr    rax, 32
    ret

; two hashes glued into a 64-bit rng state. the or 1 keeps xorshift off zero
FN wg_seed64, 16
    mov    esi, ecx
    mov    edi, edx
    mov    r12d, r8d
    mov    r9d, 0x51ED
    call   wg_hash
    mov    r13d, eax
    mov    ecx, edi
    mov    edx, esi
    mov    r8d, r12d
    mov    r9d, 0xC0FE
    call   wg_hash
    shl    r13, 32
    or     rax, r13
    or     rax, 1
ENDP

; climate/shape model, pure in (x, z, seed). sampled every 4 blocks and lerped.
; T only gets 2 octaves, climate should be smooth
FNX wg_point, 64
    mov    rbx, r8
    cvtsi2ss xmm6, ecx
    cvtsi2ss xmm7, edx
    NOISE2AT fbm2, 0.0019, 1000.3, -777.7, 5
    mulss  xmm0, [rel k_spread]
    addss  xmm0, [rel k_c_bias]
    movss  LOC(0), xmm0                 ; C
    NOISE2AT fbm2, 0.0028, -3300.1, 1200.9, 4
    mulss  xmm0, [rel k_spread]
    movss  LOC(4), xmm0                 ; E
    NOISE2AT fbm2, 0.0015, 5100.7, 2400.2, 2
    mulss  xmm0, [rel k_spread]
    movss  LOC(8), xmm0                 ; T
    NOISE2AT fbm2, 0.0021, -9100.3, -6600.5, 3
    mulss  xmm0, [rel k_spread]
    movss  LOC(12), xmm0                ; W
    NOISE2AT ridged2, 0.0042, 200.1, 450.6, 5
    movss  LOC(16), xmm0                ; PV
    NOISE2AT fbm2, 0.012, 70.2, -33.3, 4
    mulss  xmm0, [rel k_spread]
    movss  LOC(20), xmm0                ; HL

    ; pk -> xmm11
    movss  xmm0, LOC(16)
    subss  xmm0, [rel k_pv_lo]
    mulss  xmm0, [rel k_pv_mul]
    xorps  xmm1, xmm1
    maxss  xmm0, xmm1
    FCONST xmm1, 1.0
    minss  xmm0, xmm1
    movaps xmm11, xmm0
    ; mnt (low erosion + inland) -> xmm9
    movss  xmm2, LOC(4)
    movss  xmm0, [rel k_e_hi]
    movss  xmm1, [rel k_e_lo]
    call   wg_ss
    movaps xmm9, xmm0
    movss  xmm2, LOC(0)
    SSTEP  -0.02, 0.30
    mulss  xmm9, xmm0
    lea    rcx, [rel spl_cont]
    mov    edx, SPL_N
    movss  xmm0, LOC(0)
    call   wg_spline
    movaps xmm8, xmm0
    ; land weight L -> xmm10
    movss  xmm2, LOC(0)
    SSTEP  -0.12, 0.18
    movaps xmm10, xmm0
    ; hills, amp 2.5..10 by erosion
    movss  xmm2, LOC(4)
    SSTEP  0.5, -0.5
    FCONST xmm1, 7.5
    mulss  xmm0, xmm1
    FCONST xmm1, 2.5
    addss  xmm0, xmm1
    mulss  xmm0, xmm10
    FCONST xmm1, 1.0
    subss  xmm1, xmm10
    FCONST xmm2, 3.0
    mulss  xmm1, xmm2                   ; (1-L) * 3  (gentle sea floor)
    addss  xmm0, xmm1
    mulss  xmm0, LOC(20)
    addss  xmm8, xmm0
    ; mountains, peaks end up around y120
    sqrtss xmm0, xmm11
    mulss  xmm0, xmm11
    FCONST xmm1, 54.0
    mulss  xmm0, xmm1
    FCONST xmm1, 6.0
    addss  xmm0, xmm1
    mulss  xmm0, xmm9
    addss  xmm8, xmm0
    ; swamp weight -> xmm13
    movss  xmm2, LOC(8)
    SSTEP  0.05, 0.40
    movaps xmm13, xmm0
    movss  xmm2, LOC(12)
    SSTEP  0.30, 0.75
    mulss  xmm13, xmm0
    FCONST xmm1, 1.0
    subss  xmm1, xmm9
    mulss  xmm13, xmm1
    mulss  xmm13, xmm10
    ; swamps get squashed to ~sea level, shallow pools for free
    movss  xmm0, LOC(20)
    FCONST xmm1, 1.8
    mulss  xmm0, xmm1
    FCONST xmm1, 61.7
    addss  xmm0, xmm1
    subss  xmm0, xmm8
    mulss  xmm0, xmm13
    addss  xmm8, xmm0
    ; badlands mesas. hot + dry + inland weight, continuous so it fades out into
    ; the desert around it. two flat tiers off one low freq noise, the narrow
    ; smoothstep windows are what make the sides steep
    movss  xmm2, LOC(8)
    SSTEP  0.50, 0.70
    movaps xmm14, xmm0
    movss  xmm2, LOC(12)
    SSTEP  -0.15, -0.40
    mulss  xmm14, xmm0
    mulss  xmm14, xmm10
    FCONST xmm1, 1.0
    subss  xmm1, xmm9
    mulss  xmm14, xmm1
    xorps  xmm0, xmm0
    comiss xmm14, xmm0
    jbe    .nomesa                      ; no point sampling it
    NOISE2AT fbm2, 0.0085, 2200.5, -4100.3, 3
    mulss  xmm0, [rel k_spread]
    movss  LOC(24), xmm0
    movaps xmm2, xmm0
    SSTEP  0.0, 0.08
    FCONST xmm1, 9.0
    mulss  xmm0, xmm1
    movss  LOC(28), xmm0
    movss  xmm2, LOC(24)
    SSTEP  0.45, 0.52
    FCONST xmm1, 8.0
    mulss  xmm0, xmm1
    addss  xmm0, LOC(28)
    mulss  xmm0, xmm14
    addss  xmm8, xmm0
.nomesa:
    ; overhang amp, in blocks
    movaps xmm2, xmm11
    SSTEP  0.35, 0.80
    mulss  xmm0, xmm9
    FCONST xmm1, 10.0
    mulss  xmm0, xmm1
    movaps xmm12, xmm0
    FCONST xmm0, 3.0
    maxss  xmm8, xmm0
    FCONST xmm0, 123.0
    minss  xmm8, xmm0
    movss  [rbx+P_H], xmm8
    movss  xmm0, LOC(8)
    movss  [rbx+P_T], xmm0
    movss  xmm0, LOC(12)
    movss  [rbx+P_W], xmm0
    movss  xmm0, LOC(0)
    movss  [rbx+P_C], xmm0
    movss  [rbx+P_MNT], xmm9
    xorps  xmm0, xmm0
    movss  [rbx+P_RIV], xmm0            ; filled per column in wg_finish
    movss  [rbx+P_OVH], xmm12
    movss  [rbx+P_SW], xmm13
ENDPX

; bilinear lerp of 4 COLP records: rcx p00, rdx p10, r8 p01, r9 p11, xmm0 fx, xmm1 fz, r10 out.
; don't reorder the math, height_at/biome_at have to match real chunks bit for bit
align 16
wg_interp:
    shufps xmm0, xmm0, 0
    shufps xmm1, xmm1, 0
%assign half 0
%rep 2
    movups xmm2, [rcx+half]
    movups xmm3, [rdx+half]
    subps  xmm3, xmm2
    mulps  xmm3, xmm0
    addps  xmm2, xmm3
    movups xmm4, [r8+half]
    movups xmm5, [r9+half]
    subps  xmm5, xmm4
    mulps  xmm5, xmm0
    addps  xmm4, xmm5
    subps  xmm4, xmm2
    mulps  xmm4, xmm1
    addps  xmm2, xmm4
    movups [r10+half], xmm2
%assign half half+16
%endrep
    ret

; per column detail + biome pick
FNX wg_finish, 32
    mov    rbx, rcx
    cvtsi2ss xmm6, edx
    cvtsi2ss xmm7, r8d
    ; rivers run along RV = 0, full res since they're thinner than the grid.
    ; channel digs to ~57, the bank band pulls land down -> gorges in mountains
    NOISE2AT fbm2, 0.0018, 1700.4, -2900.8, 3
    mulss  xmm0, [rel k_spread]
    andps  xmm0, [rel k_absmask]
    movaps xmm9, xmm0
    movss  xmm2, [rbx+P_C]
    SSTEP  -0.08, 0.08
    movaps xmm10, xmm0                  ; Lr: rivers fade out into the sea
    movaps xmm2, xmm9
    movss  xmm0, [rel k_zero]
    movss  xmm1, [rel k_riv_w]
    call   wg_ss
    FCONST xmm1, 1.0
    subss  xmm1, xmm0
    mulss  xmm1, xmm10
    movaps xmm11, xmm1                  ; chan
    movaps xmm2, xmm9
    movss  xmm0, [rel k_riv_w]
    movss  xmm1, [rel k_riv_bank]
    call   wg_ss
    FCONST xmm1, 1.0
    subss  xmm1, xmm0
    mulss  xmm1, xmm10
    movaps xmm12, xmm1                  ; bank
    movaps xmm2, xmm9
    movss  xmm0, [rel k_zero]
    FCONST xmm1, 0.075
    call   wg_ss
    FCONST xmm1, 1.0
    subss  xmm1, xmm0
    mulss  xmm1, xmm10
    movss  [rbx+P_RIV], xmm1            ; banks/trees/biomes read this
    movss  xmm8, [rbx+P_H]
    ; valley: pull towards 63.5 + (H-63.5)*0.35
    FCONST xmm1, 63.5
    movaps xmm0, xmm8
    subss  xmm0, xmm1
    FCONST xmm2, 0.35
    mulss  xmm0, xmm2
    addss  xmm0, xmm1
    comiss xmm8, xmm0
    jbe    .novalley
    subss  xmm0, xmm8
    mulss  xmm0, xmm12
    addss  xmm8, xmm0
.novalley:
    FCONST xmm0, 57.0
    subss  xmm0, xmm8
    mulss  xmm0, xmm11
    addss  xmm0, xmm8
    minss  xmm8, xmm0
    movss  [rbx+P_H], xmm8
    ; small detail noise, damped on rivers and swamps
    FCONST xmm2, 0.07
    movaps xmm0, xmm6
    mulss  xmm0, xmm2
    mulss  xmm2, xmm7
    movaps xmm1, xmm2
    FCONST xmm2, 11.1
    addss  xmm0, xmm2
    FCONST xmm2, -7.3
    addss  xmm1, xmm2
    call   noise2
    FCONST xmm1, 1.6
    mulss  xmm0, xmm1
    FCONST xmm1, 1.0
    subss  xmm1, [rbx+P_RIV]
    mulss  xmm0, xmm1
    movss  xmm1, [rbx+P_SW]
    FCONST xmm2, -0.7
    mulss  xmm1, xmm2
    FCONST xmm2, 1.0
    addss  xmm1, xmm2
    mulss  xmm0, xmm1
    addss  xmm0, [rbx+P_H]
    movaps xmm8, xmm0
    movss  [rbx+C_HF], xmm8
    roundss xmm0, xmm8, 1
    cvttss2si r12d, xmm0
    cmp    r12d, 1
    jge    .h1
    mov    r12d, 1
.h1:
    cmp    r12d, 124
    jle    .h2
    mov    r12d, 124
.h2:
    mov    [rbx+C_HS], r12d
    ; rare columns where caves get to break the surface
    FCONST xmm2, 0.021
    movaps xmm0, xmm6
    mulss  xmm0, xmm2
    mulss  xmm2, xmm7
    movaps xmm1, xmm2
    FCONST xmm2, -51.7
    addss  xmm0, xmm2
    FCONST xmm2, 93.1
    addss  xmm1, xmm2
    call   noise2
    FCONST xmm1, 0.80                   ; FCONST eats eax, so before the xor
    xor    eax, eax
    comiss xmm0, xmm1
    seta   al
    mov    [rbx+C_ENTR], eax

    ; ocean: below sea level, seaward continentalness, not a river channel
    cmp    r12d, SEA_LEVEL
    jge    .not_ocean
    movss  xmm0, [rbx+P_C]
    FCONST xmm1, -0.02
    comiss xmm0, xmm1
    jae    .not_ocean
    movss  xmm0, [rbx+P_RIV]
    FCONST xmm1, 0.5
    comiss xmm0, xmm1
    jae    .not_ocean
    mov    eax, BIOME_OCEAN
    jmp    .set
.not_ocean:
    movss  xmm0, [rbx+P_MNT]
    FCONST xmm1, 0.45
    comiss xmm0, xmm1
    jbe    .not_mnt
    FCONST xmm1, 86.0
    comiss xmm8, xmm1
    jbe    .not_mnt
    mov    eax, BIOME_MOUNTAINS
    jmp    .set
.not_mnt:
    movss  xmm0, [rbx+P_SW]
    FCONST xmm1, 0.45
    comiss xmm0, xmm1
    jbe    .not_swamp
    mov    eax, BIOME_SWAMP
    jmp    .set
.not_swamp:
    ; beach: shore band, warm enough, not a river bank
    cmp    r12d, SEA_LEVEL+2
    jg     .climate
    cmp    r12d, SEA_LEVEL-3
    jl     .climate
    movss  xmm0, [rbx+P_C]
    FCONST xmm1, 0.08
    comiss xmm0, xmm1
    jae    .climate
    movss  xmm0, [rbx+P_RIV]
    FCONST xmm1, 0.3
    comiss xmm0, xmm1
    jae    .climate
    movss  xmm0, [rbx+P_T]
    FCONST xmm1, -0.45
    comiss xmm0, xmm1
    jbe    .climate
    mov    eax, BIOME_BEACH
    jmp    .set
.climate:
    movss  xmm0, [rbx+P_T]
    xor    ecx, ecx
    FCONST xmm1, -0.55
    comiss xmm0, xmm1
    jb     .tb
    inc    ecx
    FCONST xmm1, -0.10
    comiss xmm0, xmm1
    jb     .tb
    inc    ecx
    FCONST xmm1, 0.30
    comiss xmm0, xmm1
    jb     .tb
    inc    ecx
    FCONST xmm1, 0.65
    comiss xmm0, xmm1
    jb     .tb
    inc    ecx
.tb:
    movss  xmm0, [rbx+P_W]
    xor    edx, edx
    FCONST xmm1, -0.30
    comiss xmm0, xmm1
    jb     .wb
    inc    edx
    FCONST xmm1, 0.0
    comiss xmm0, xmm1
    jb     .wb
    inc    edx
    FCONST xmm1, 0.30
    comiss xmm0, xmm1
    jb     .wb
    inc    edx
.wb:
    lea    ecx, [rdx+rcx*4]
    lea    rdx, [rel climate_tbl]
    movzx  eax, byte [rdx+rcx]
.set:
    mov    [rbx+C_BIOME], eax
ENDPX

; standalone column, no ctx
FN wg_col_direct, 4*COLP_SZ
    mov    esi, ecx
    mov    edi, edx
    mov    r12, r8
    and    ecx, ~3
    and    edx, ~3
    mov    r13d, ecx                    ; x0
    mov    r14d, edx                    ; z0
    lea    r8, LOC(0)
    call   wg_point
    lea    ecx, [r13+4]
    mov    edx, r14d
    lea    r8, LOC(32)
    call   wg_point
    mov    ecx, r13d
    lea    edx, [r14+4]
    lea    r8, LOC(64)
    call   wg_point
    lea    ecx, [r13+4]
    lea    edx, [r14+4]
    lea    r8, LOC(96)
    call   wg_point
    mov    eax, esi
    and    eax, 3
    cvtsi2ss xmm0, eax
    mulss  xmm0, [rel k_quarter]
    mov    eax, edi
    and    eax, 3
    cvtsi2ss xmm1, eax
    mulss  xmm1, [rel k_quarter]
    lea    rcx, LOC(0)
    lea    rdx, LOC(32)
    lea    r8, LOC(64)
    lea    r9, LOC(96)
    mov    r10, r12
    call   wg_interp
    mov    rcx, r12
    mov    edx, esi
    mov    r8d, edi
    call   wg_finish
ENDP

; column at chunk-relative (rx, rz) in [-16, 31], lerped off the 13x13 grid
FN wg_col_grid, 0
    mov    esi, ecx
    mov    edi, edx
    mov    r12, r8
    lea    eax, [rcx+16]
    mov    r13d, eax
    shr    r13d, 2
    and    eax, 3
    cvtsi2ss xmm0, eax
    mulss  xmm0, [rel k_quarter]
    lea    eax, [rdx+16]
    mov    r14d, eax
    shr    r14d, 2
    and    eax, 3
    cvtsi2ss xmm1, eax
    mulss  xmm1, [rel k_quarter]
    imul   eax, r14d, GRID_N
    add    eax, r13d
    shl    eax, 5
    lea    rcx, [rbx+WG.grid]
    add    rcx, rax
    lea    rdx, [rcx+COLP_SZ]
    lea    r8, [rcx+GRID_N*COLP_SZ]
    lea    r9, [r8+COLP_SZ]
    mov    r10, r12
    call   wg_interp
    mov    rcx, r12
    mov    edx, [rbx+WG.ox]
    add    edx, esi
    mov    r8d, [rbx+WG.oz]
    add    r8d, edi
    call   wg_finish
ENDP

PROC worldgen_biome_at, COL_SZ
    lea    r8, LOC(0)
    call   wg_col_direct
    mov    eax, LOC(C_BIOME)
ENDP

PROC worldgen_height_at, COL_SZ
    lea    r8, LOC(0)
    call   wg_col_direct
    mov    eax, LOC(C_HS)
ENDP

; chunk phases, all of them expect rbx = WG ctx

; COL_PTR : rsi = &cols[lz+1][lx+1]   for r12d = lx, r13d = lz
; COL_BASE: rdi = &blocks[lx + lz*16]  (y stride 256)
%macro COL_PTR 0
    lea    eax, [r13+1]
    imul   eax, eax, COLS_N
    lea    eax, [rax+r12+1]
    shl    eax, 6
    lea    rsi, [rbx+WG.cols]
    add    rsi, rax
%endmacro
%macro COL_BASE 0
    mov    eax, r13d
    shl    eax, 4
    add    eax, r12d
    mov    rdi, [rbx+WG.chunk]
    lea    rdi, [rdi+rax+CHUNK_BLOCKS]
%endmacro

; 3D overhang lattice 5x17x5, steps 4/8/4
FNX wg_ovh_grid, 0
    xor    r14d, r14d
.yl:
    xor    r13d, r13d
.zl:
    xor    r12d, r12d
.xl:
    mov    eax, r12d
    shl    eax, 2
    add    eax, [rbx+WG.ox]
    cvtsi2ss xmm0, eax
    mov    eax, r14d
    shl    eax, 3
    cvtsi2ss xmm1, eax
    mov    eax, r13d
    shl    eax, 2
    add    eax, [rbx+WG.oz]
    cvtsi2ss xmm2, eax
    FCONST xmm3, 0.028
    mulss  xmm0, xmm3
    mulss  xmm2, xmm3
    FCONST xmm3, 0.045
    mulss  xmm1, xmm3
    FCONST xmm3, 500.5
    addss  xmm0, xmm3
    mov    r9d, 2
    call   fbm3
    imul   eax, r14d, 25
    imul   ecx, r13d, 5
    add    eax, ecx
    add    eax, r12d
    lea    rcx, [rbx+WG.ovh]
    movss  [rcx+rax*4], xmm0
    inc    r12d
    cmp    r12d, 5
    jb     .xl
    inc    r13d
    cmp    r13d, 5
    jb     .zl
    inc    r14d
    cmp    r14d, OVH_NY
    jb     .yl
ENDPX

; wg_ovh_sample (leaf): rbx ctx | ecx lx, edx y, r8d lz -> xmm0, trilinear.
; trashes rax rcx rdx r8-r10, xmm0-xmm5
%macro OVH_LEVEL 2      ; dst, byte offset of the y level
    movss  %1, [rcx+%2]
    movss  xmm2, [rcx+%2+4]
    subss  xmm2, %1
    mulss  xmm2, xmm4
    addss  %1, xmm2
    movss  xmm3, [rcx+%2+20]
    movss  xmm2, [rcx+%2+24]
    subss  xmm2, xmm3
    mulss  xmm2, xmm4
    addss  xmm3, xmm2
    subss  xmm3, %1
    mulss  xmm3, xmm5
    addss  %1, xmm3
%endmacro
align 16
wg_ovh_sample:
    mov    eax, ecx
    shr    eax, 2
    and    ecx, 3
    cvtsi2ss xmm4, ecx
    mulss  xmm4, [rel k_quarter]
    mov    r9d, r8d
    shr    r9d, 2
    and    r8d, 3
    cvtsi2ss xmm5, r8d
    mulss  xmm5, [rel k_quarter]
    mov    r10d, edx
    shr    r10d, 3
    and    edx, 7
    imul   r10d, r10d, 25
    imul   r9d, r9d, 5
    add    r10d, r9d
    add    r10d, eax
    lea    rcx, [rbx+WG.ovh]
    lea    rcx, [rcx+r10*4]
    OVH_LEVEL xmm0, 0
    OVH_LEVEL xmm1, 100
    cvtsi2ss xmm2, edx
    mulss  xmm2, [rel k_eighth]
    subss  xmm1, xmm0
    mulss  xmm1, xmm2
    addss  xmm0, xmm1
    ret

; stone/water/air + the 3D overhang band + bedrock. also sets C_TOP / maxtop
FNX wg_fill, 32
    mov    dword [rbx+WG.maxtop], SEA_LEVEL
    xor    r13d, r13d
.zl:
    xor    r12d, r12d
.xl:
    COL_PTR
    COL_BASE
    mov    r14d, [rsi+C_HS]
    movss  xmm6, [rsi+P_OVH]
    movss  xmm7, [rsi+C_HF]
    FCONST xmm0, 0.5
    comiss xmm6, xmm0
    jae    .complex
    xor    ecx, ecx
.sl:
    mov    al, B_STONE
    cmp    ecx, r14d
    jle    .sw
    mov    al, B_WATER
    cmp    ecx, SEA_LEVEL
    jle    .sw
    xor    eax, eax
.sw:
    mov    edx, ecx
    shl    edx, 8
    mov    [rdi+rdx], al
    inc    ecx
    cmp    ecx, CHUNK_H
    jb     .sl
    mov    r15d, r14d
    jmp    .bed
.complex:
    ; the 3D noise can only flip solid/air inside [lo, hi], rest is plain
    cvttss2si eax, xmm6
    add    eax, 2
    mov    ecx, r14d ; trace probe #32 hook
    sub    ecx, eax ; trace probe #32 hook
    cmp    ecx, 1 ; trace probe #32 hook
    jge    .lo_ok ; trace probe #32 hook
    mov    ecx, 1 ; trace probe #32 hook
.lo_ok: ; trace probe #32 hook
    mov    LOC(0), ecx ; trace probe #32 hook
    mov    edx, r14d ; trace probe #32 hook
    add    edx, eax ; trace probe #32 hook
    cmp    edx, 126
    jle    .hi_ok
    mov    edx, 126
.hi_ok:
    mov    LOC(4), edx                  ; hi
    mov    r15d, edx
    mov    dword LOC(8), 0              ; y
.cl:
    mov    ecx, LOC(8)
    mov    al, B_STONE
    cmp    ecx, LOC(0)
    jle    .cw
    cmp    ecx, LOC(4)
    jg     .empty
    ; density = Hf - y + ovh * n3(x,y,z)
    mov    edx, ecx
    mov    ecx, r12d
    mov    r8d, r13d
    call   wg_ovh_sample
    mulss  xmm0, xmm6
    addss  xmm0, xmm7
    cvtsi2ss xmm1, dword LOC(8)
    subss  xmm0, xmm1
    mov    ecx, LOC(8)
    mov    al, B_STONE
    xorps  xmm1, xmm1
; --- temporary diagnostic probe #32 (worldgen) ---
; TODO: strip dbg_worldgen_probe_32 once frame/state invariants hold
dbg_worldgen_probe_32:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    mov     [rsp+32], rcx
    mov     [rsp+40], rdx
    mov     [rsp+48], r8
    mov     [rsp+56], r9
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    mov     r10, rax
    test    rcx, rcx
    jz      .dbg_null_32
    mov     eax, dword [rcx+0] ; sample worldgen state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_32_0
.dbg_skip_32_0:
    mov     ecx, dword [rcx+4] ; sample worldgen state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_32_1
.dbg_skip_32_1:
    mov     edx, dword [rcx+8] ; sample worldgen state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_32_2
.dbg_skip_32_2:
    mov     r8d, dword [rcx+12] ; sample worldgen state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_32_3
.dbg_skip_32_3:
    mov     r9d, dword [rcx+16] ; sample worldgen state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_32_4
.dbg_skip_32_4:
    mov     r11d, dword [rcx+20] ; sample worldgen state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_32_5
.dbg_skip_32_5:
    mov     eax, dword [rcx+24] ; sample worldgen state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_32_6
.dbg_skip_32_6:
    mov     ecx, dword [rcx+28] ; sample worldgen state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_32_7
.dbg_skip_32_7:
    mov     edx, dword [rcx+32] ; sample worldgen state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_32_8
.dbg_skip_32_8:
    mov     r8d, dword [rcx+36] ; sample worldgen state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_32_9
.dbg_skip_32_9:
    mov     r9d, dword [rcx+40] ; sample worldgen state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_32_10
.dbg_skip_32_10:
    mov     r11d, dword [rcx+44] ; sample worldgen state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_32_11
.dbg_skip_32_11:
    mov     eax, dword [rcx+48] ; sample worldgen state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_32_12
.dbg_skip_32_12:
    mov     ecx, dword [rcx+52] ; sample worldgen state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_32_13
.dbg_skip_32_13:
    mov     edx, dword [rcx+56] ; sample worldgen state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_32_14
.dbg_skip_32_14:
    mov     r8d, dword [rcx+60] ; sample worldgen state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_32_15
.dbg_skip_32_15:
    mov     r9d, dword [rcx+64] ; sample worldgen state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_32_16
.dbg_skip_32_16:
    mov     r11d, dword [rcx+68] ; sample worldgen state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_32_17
.dbg_skip_32_17:
    mov     eax, dword [rcx+72] ; sample worldgen state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_32_18
.dbg_skip_32_18:
    mov     ecx, dword [rcx+76] ; sample worldgen state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_32_19
.dbg_skip_32_19:
    mov     edx, dword [rcx+80] ; sample worldgen state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_32_20
.dbg_skip_32_20:
    mov     r8d, dword [rcx+84] ; sample worldgen state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_32_21
.dbg_skip_32_21:
.dbg_null_32:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
