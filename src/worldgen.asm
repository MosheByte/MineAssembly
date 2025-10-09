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
    mov    ecx, r14d
    sub    ecx, eax
    cmp    ecx, 1
    jge    .lo_ok
    mov    ecx, 1
.lo_ok:
    mov    LOC(0), ecx                  ; lo
    mov    edx, r14d
    add    edx, eax
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
    comiss xmm0, xmm1
    ja     .cw
.empty:
    mov    al, B_WATER
    cmp    ecx, SEA_LEVEL
    jle    .cw
    xor    eax, eax
.cw:
    mov    edx, ecx
    shl    edx, 8
    mov    [rdi+rdx], al
    inc    ecx
    mov    LOC(8), ecx
    cmp    ecx, CHUNK_H
    jb     .cl
.bed:
    cmp    r15d, r14d
    jge    .t1
    mov    r15d, r14d
.t1:
    mov    [rsi+C_TOP], r15d
    cmp    r15d, [rbx+WG.maxtop]
    jle    .t2
    mov    [rbx+WG.maxtop], r15d
.t2:
    ; bedrock: y=0 always, y=1..4 at 80/60/40/20 % so the top is ragged
    mov    byte [rdi], B_BEDROCK
    mov    r15d, 1
.br:
    mov    ecx, [rbx+WG.ox]
    add    ecx, r12d
    mov    edx, r15d
    mov    r8d, [rbx+WG.oz]
    add    r8d, r13d
    mov    r9d, S_BEDROCK
    call   wg_hash
    and    eax, 0xFFFF
    imul   eax, eax, 5
    shr    eax, 16
    cmp    eax, r15d
    jb     .nobr
    mov    eax, r15d
    shl    eax, 8
    mov    byte [rdi+rax], B_BEDROCK
.nobr:
    inc    r15d
    cmp    r15d, 4
    jbe    .br
    inc    r12d
    cmp    r12d, 16
    jb     .xl
    inc    r13d
    cmp    r13d, 16
    jb     .zl
ENDPX

; BAND in a layer slot = pick the badlands layer for this y (ecx) instead
%define BAND 0xFF
%macro BANDED 0
    cmp    eax, BAND
    jne    %%keep
    mov    eax, ecx
    add    eax, LOC(36)
    and    eax, 31
    lea    r10, [rel band_tbl]
    movzx  eax, byte [r10+rax]
%%keep:
%endmacro

; walks each column top-down and re-types the stone from wg_fill.
; locals: 0 top, 4 filler, 8 filler depth, 12 under, 16 under depth,
;         20 underwater top, 24 depth, 28 underwater flag, 32 hash, 36 band shift
FN wg_surface, 48
    xor    r13d, r13d
.zl:
    xor    r12d, r12d
.xl:
    COL_PTR
    COL_BASE
    mov    ecx, [rbx+WG.ox]
    add    ecx, r12d
    mov    edx, [rbx+WG.oz]
    add    edx, r13d
    xor    r8d, r8d
    mov    r9d, S_SURF
    call   wg_hash
    mov    LOC(32), eax
    mov    r14d, [rsi+C_HS]
    mov    r15d, [rsi+C_BIOME]
    ; defaults: grass over 3-4 dirt over stone
    mov    dword LOC(0), B_GRASS
    mov    dword LOC(4), B_DIRT
    and    eax, 1
    add    eax, 3
    mov    LOC(8), eax
    mov    dword LOC(12), B_STONE
    mov    dword LOC(16), 0
    movss  xmm4, [rsi+C_SLOPE]
    cmp    r15d, BIOME_BADLANDS
    jne    .nbad
    ; 1-2 red sand over ~28 layers of banded terracotta. cliffs show the bands
    mov    dword LOC(0), B_RED_SAND
    mov    dword LOC(4), B_RED_SAND
    and    eax, 1
    inc    eax
    mov    LOC(8), eax
    mov    dword LOC(12), BAND
    mov    dword LOC(16), 28
    ; slow wobble on the band index so the layers tilt a little across a region
    movss  xmm0, [rsi+P_W]
    FCONST xmm1, 10.0
    mulss  xmm0, xmm1
    cvttss2si eax, xmm0
    mov    LOC(36), eax
    FCONST xmm0, 1.4
    comiss xmm4, xmm0
    jbe    .decided
    mov    dword LOC(0), BAND
    mov    dword LOC(4), BAND
    jmp    .decided
.nbad:
    cmp    r15d, BIOME_DESERT
    jne    .nd
    mov    dword LOC(0), B_SAND
    mov    dword LOC(4), B_SAND
    mov    dword LOC(12), B_SANDSTONE
    mov    eax, LOC(32)
    shr    eax, 1
    and    eax, 1
    add    eax, 3
    mov    LOC(16), eax
    FCONST xmm0, 1.7
    comiss xmm4, xmm0
    jbe    .decided
    mov    dword LOC(0), B_SANDSTONE
    mov    dword LOC(4), B_SANDSTONE
    jmp    .decided
.nd:
    cmp    r15d, BIOME_BEACH
    jne    .nb
    mov    dword LOC(0), B_SAND
    mov    dword LOC(4), B_SAND
    mov    dword LOC(8), 3
    mov    dword LOC(12), B_SANDSTONE
    mov    dword LOC(16), 2
    jmp    .decided
.nb:
    cmp    r15d, BIOME_TUNDRA
    jne    .nt
    mov    dword LOC(0), B_SNOWY_GRASS
    jmp    .generic
.nt:
    cmp    r15d, BIOME_TAIGA
    jne    .nta
    cmp    r14d, 84
    jle    .generic
    mov    dword LOC(0), B_SNOWY_GRASS
    jmp    .generic
.nta:
    cmp    r15d, BIOME_MOUNTAINS
    jne    .generic
    cmp    r14d, 98
    jg     .bare
    FCONST xmm0, 1.0
    comiss xmm4, xmm0
    jbe    .generic
.bare:
    mov    dword LOC(0), B_STONE
    mov    dword LOC(4), B_STONE
.generic:
    FCONST xmm0, 1.7
    comiss xmm4, xmm0
    jbe    .notcliff
    mov    dword LOC(0), B_STONE
    mov    dword LOC(4), B_STONE
.notcliff:
    ; sandy river banks
    movss  xmm0, [rsi+P_RIV]
    FCONST xmm1, 0.06
    comiss xmm0, xmm1
    jbe    .nobank
    cmp    r14d, SEA_LEVEL+1
    jg     .nobank
    cmp    dword LOC(4), B_DIRT
    jne    .nobank
    mov    dword LOC(0), B_SAND
    mov    dword LOC(4), B_SAND
    mov    dword LOC(8), 2
.nobank:
    movss  xmm0, [rsi+P_T]
    FCONST xmm1, -0.6
    comiss xmm0, xmm1
    jae    .decided
    cmp    dword LOC(0), B_GRASS
    jne    .decided
    mov    dword LOC(0), B_SNOWY_GRASS
.decided:
    cmp    r15d, BIOME_BADLANDS          ; mesa tops stay red
    je     .nosnow
    ; snow caps: snowline = 104 + (h>>4 & 3) - T*8
    movss  xmm0, [rsi+P_T]
    FCONST xmm1, 8.0
    mulss  xmm0, xmm1
    cvttss2si eax, xmm0
    mov    ecx, LOC(32)
    shr    ecx, 4
    and    ecx, 3
    add    ecx, 104
    sub    ecx, eax
    cmp    r14d, ecx
    jl     .nosnow
    mov    dword LOC(0), B_SNOW
    mov    dword LOC(8), 1
    mov    dword LOC(4), B_SNOW
    FCONST xmm0, 1.7
    comiss xmm4, xmm0
    jbe    .nosnow
    mov    dword LOC(4), B_STONE
.nosnow:
    mov    eax, LOC(32)
    shr    eax, 8
    and    eax, 15
    cmp    r15d, BIOME_OCEAN
    jne    .uw_ns
    cmp    r14d, 48
    jge    .uw_shallow
    mov    ecx, B_GRAVEL
    cmp    eax, 3
    jae    .uw_set
    mov    ecx, B_CLAY
    jmp    .uw_set
.uw_shallow:
    mov    ecx, B_SAND
    cmp    eax, 4
    jae    .uw_set
    mov    ecx, B_GRAVEL
    cmp    eax, 2
    jae    .uw_set
    mov    ecx, B_CLAY
    jmp    .uw_set
.uw_ns:
    cmp    r15d, BIOME_SWAMP
    jne    .uw_river
    mov    ecx, B_DIRT
    cmp    eax, 4
    jae    .uw_set
    mov    ecx, B_CLAY
    jmp    .uw_set
.uw_river:
    mov    ecx, B_SAND
    cmp    eax, 5
    jae    .uw_set
    mov    ecx, B_GRAVEL
    cmp    eax, 2
    jae    .uw_set
    mov    ecx, B_CLAY
.uw_set:
    mov    LOC(20), ecx

    mov    ecx, [rsi+C_TOP]
    mov    dword LOC(24), -1
    mov    dword LOC(28), 0
.scan:
    test   ecx, ecx
    jle    .scan_done
    mov    edx, ecx
    shl    edx, 8
    movzx  eax, byte [rdi+rdx]
    cmp    eax, B_STONE
    jne    .notstone
    mov    r8d, LOC(24)
    test   r8d, r8d
    jns    .deeper
    ; first solid below air/water
    movzx  eax, byte [rdi+rdx+256]
    xor    r9d, r9d
    cmp    eax, B_WATER
    sete   r9b
    mov    LOC(28), r9d
    mov    eax, LOC(0)
    test   r9d, r9d
    jz     .wtop
    mov    eax, LOC(20)
.wtop:
    BANDED
    mov    [rdi+rdx], al
    mov    dword LOC(24), 1
    jmp    .next
.deeper:
    cmp    dword LOC(28), 0
    je     .landfill
    cmp    r8d, LOC(8)
    jge    .inc
    mov    eax, LOC(20)
    mov    [rdi+rdx], al
    jmp    .inc
.landfill:
    cmp    r8d, LOC(8)
    jge    .under
    mov    eax, LOC(4)
    BANDED
    mov    [rdi+rdx], al
    jmp    .inc
.under:
    mov    eax, LOC(8)
    add    eax, LOC(16)
    cmp    r8d, eax
    jge    .inc
    mov    eax, LOC(12)
    BANDED
    mov    [rdi+rdx], al
.inc:
    inc    dword LOC(24)
    jmp    .next
.notstone:
    cmp    eax, B_BEDROCK
    je     .scan_done
    mov    dword LOC(24), -1
.next:
    dec    ecx
    jmp    .scan
.scan_done:
    cmp    byte [rdi+SEA_LEVEL*256], B_WATER
    jne    .noice
    mov    eax, LOC(32)
    shr    eax, 12
    and    eax, 255
    cvtsi2ss xmm0, eax
    FCONST xmm1, 0.0006
    mulss  xmm0, xmm1
    addss  xmm0, [rsi+P_T]
    FCONST xmm1, -0.62
    comiss xmm0, xmm1
    jae    .noice
    mov    byte [rdi+SEA_LEVEL*256], B_ICE
.noice:
    inc    r12d
    cmp    r12d, 16
    jb     .xl
    inc    r13d
    cmp    r13d, 16
    jb     .zl
ENDP

; spaghetti = A and B both near 0, cheese = Q over a threshold that rises with y.
; the fields are sampled on a 5 x ny x 5 lattice and squashed into a per column
; profile, so a voxel is one lerp. real 3D noise per voxel would be way too slow
FNX wg_caves, 32
    mov    eax, [rbx+WG.maxtop]
    shr    eax, 2
    add    eax, 2
    cmp    eax, CAVE_NY-1
    jbe    .ny_ok
    mov    eax, CAVE_NY-1
.ny_ok:
    mov    [rbx+WG.ncave], eax
    xor    r14d, r14d
.gy:
    xor    r13d, r13d
.gz:
    xor    r12d, r12d
.gx:
    mov    eax, r12d
    shl    eax, 2
    add    eax, [rbx+WG.ox]
    cvtsi2ss xmm6, eax
    mov    eax, r14d
    shl    eax, 2
    cvtsi2ss xmm7, eax
    mov    eax, r13d
    shl    eax, 2
    add    eax, [rbx+WG.oz]
    cvtsi2ss xmm8, eax
    imul   r15d, r14d, 25
    imul   eax, r13d, 5
    add    r15d, eax
    add    r15d, r12d
    ; A
    FCONST xmm3, 0.021
    movaps xmm0, xmm6
    mulss  xmm0, xmm3
    movaps xmm2, xmm8
    mulss  xmm2, xmm3
    FCONST xmm3, 0.032
    movaps xmm1, xmm7
    mulss  xmm1, xmm3
    call   noise3
    lea    rax, [rbx+WG.cave]
    movss  [rax+r15*4], xmm0
    ; B
    FCONST xmm3, 0.021
    movaps xmm0, xmm6
    mulss  xmm0, xmm3
    movaps xmm2, xmm8
    mulss  xmm2, xmm3
    FCONST xmm3, 0.032
    movaps xmm1, xmm7
    mulss  xmm1, xmm3
    FCONST xmm3, 71.3
    addss  xmm0, xmm3
    FCONST xmm3, -33.1
    addss  xmm1, xmm3
    FCONST xmm3, 19.7
    addss  xmm2, xmm3
    call   noise3
    lea    rax, [rbx+WG.cave+CAVE_FS*4]
    movss  [rax+r15*4], xmm0
    ; Q (caverns)
    FCONST xmm3, 0.011
    movaps xmm0, xmm6
    mulss  xmm0, xmm3
    movaps xmm2, xmm8
    mulss  xmm2, xmm3
    FCONST xmm3, 0.019
    movaps xmm1, xmm7
    mulss  xmm1, xmm3
    FCONST xmm3, -300.3
    addss  xmm0, xmm3
    FCONST xmm3, 700.7
    addss  xmm2, xmm3
    mov    r9d, 2
    call   fbm3
    lea    rax, [rbx+WG.cave+CAVE_FS*8]
    movss  [rax+r15*4], xmm0
    inc    r12d
    cmp    r12d, 5
    jb     .gx
    inc    r13d
    cmp    r13d, 5
    jb     .gz
    inc    r14d
    cmp    r14d, [rbx+WG.ncave]
    jb     .gy

    movss  xmm12, [rel k_tunnel]
    movss  xmm13, [rel k_cheese0]
    movss  xmm14, [rel k_cheese_dy]
    xor    r13d, r13d
.zl:
    xor    r12d, r12d
.xl:
    COL_PTR
    COL_BASE
    mov    eax, r12d
    and    eax, 3
    cvtsi2ss xmm6, eax
    mulss  xmm6, [rel k_quarter]
    mov    eax, r13d
    and    eax, 3
    cvtsi2ss xmm7, eax
    mulss  xmm7, [rel k_quarter]
    mov    eax, r13d
    shr    eax, 2
    imul   eax, eax, 5
    mov    ecx, r12d
    shr    ecx, 2
    add    eax, ecx
    mov    LOC(0), eax
    ; colv[f*CAVE_NY + gy]
    xor    r14d, r14d
    xor    r15d, r15d
.pf:
    xor    ecx, ecx
.pg:
    imul   eax, ecx, 25
    add    eax, LOC(0)
    add    eax, r14d
    lea    rdx, [rbx+WG.cave]
    lea    rdx, [rdx+rax*4]
    movss  xmm0, [rdx]
    movss  xmm1, [rdx+4]
    subss  xmm1, xmm0
    mulss  xmm1, xmm6
    addss  xmm0, xmm1
    movss  xmm2, [rdx+20]
    movss  xmm1, [rdx+24]
    subss  xmm1, xmm2
    mulss  xmm1, xmm6
    addss  xmm2, xmm1
    subss  xmm2, xmm0
    mulss  xmm2, xmm7
    addss  xmm0, xmm2
    imul   eax, r15d, CAVE_NY
    add    eax, ecx
    lea    rdx, [rbx+WG.colv]
    movss  [rdx+rax*4], xmm0
    inc    ecx
    cmp    ecx, [rbx+WG.ncave]
    jb     .pg
    add    r14d, CAVE_FS
    inc    r15d
    cmp    r15d, 3
    jb     .pf
    ; voxel range 1 .. min(top, (ncave-1)*4-1, 125)
    mov    eax, [rbx+WG.ncave]
    dec    eax
    shl    eax, 2
    dec    eax
    mov    ecx, [rsi+C_TOP]
    cmp    ecx, eax
    jle    .ym
    mov    ecx, eax
.ym:
    cmp    ecx, 125
    jle    .ym2
    mov    ecx, 125
.ym2:
    mov    LOC(4), ecx
    mov    r14d, 1
.vy:
    cmp    r14d, LOC(4)
    jg     .colnext
    mov    edx, r14d
    shl    edx, 8
    movzx  eax, byte [rdi+rdx]
    test   eax, eax
    jz     .vnext
    cmp    eax, B_BEDROCK
    je     .vnext
    cmp    eax, B_ICE
    je     .vnext
    cmp    eax, B_WATER
    jae    .vnext                       ; liquids (80..91)
    movzx  eax, byte [rdi+rdx+256]
    cmp    eax, B_WATER
    jae    .vnext                       ; never carve right under a liquid
    mov    r15d, [rsi+C_HS]
    sub    r15d, r14d
    cmp    dword [rsi+C_HS], SEA_LEVEL
    jge    .dry
    cmp    r15d, 8
    jl     .vnext                       ; keep sea / river beds sealed
.dry:
    mov    eax, r14d
    shr    eax, 2
    mov    ecx, r14d
    and    ecx, 3
    cvtsi2ss xmm8, ecx
    mulss  xmm8, [rel k_quarter]
    lea    rdx, [rbx+WG.colv]
    lea    rdx, [rdx+rax*4]
    movss  xmm0, [rdx]
    movss  xmm1, [rdx+4]
    subss  xmm1, xmm0
    mulss  xmm1, xmm8
    addss  xmm0, xmm1
    movss  xmm2, [rdx+CAVE_NY*4]
    movss  xmm1, [rdx+CAVE_NY*4+4]
    subss  xmm1, xmm2
    mulss  xmm1, xmm8
    addss  xmm2, xmm1
    mulss  xmm0, xmm0
    mulss  xmm2, xmm2
    addss  xmm0, xmm2
    xor    r9d, r9d
    comiss xmm0, xmm12
    setb   r9b
    cmp    r15d, 10
    jge    .deep
    ; near the surface: tunnels only, and only at entrance spots
    test   r9d, r9d
    jz     .vnext
    cmp    dword [rsi+C_ENTR], 0
    je     .vnext
    jmp    .carve
.deep:
    test   r9d, r9d
    jnz    .carve
    movss  xmm0, [rdx+CAVE_NY*8]        ; Q
    movss  xmm1, [rdx+CAVE_NY*8+4]
    subss  xmm1, xmm0
    mulss  xmm1, xmm8
    addss  xmm0, xmm1
    cvtsi2ss xmm1, r14d
    mulss  xmm1, xmm14
    addss  xmm1, xmm13
    comiss xmm0, xmm1
    jbe    .vnext
.carve:
    mov    edx, r14d
    shl    edx, 8
    xor    eax, eax
    cmp    r14d, 10
    ja     .air
    mov    eax, B_LAVA
.air:
    mov    [rdi+rdx], al
.vnext:
    inc    r14d
    jmp    .vy
.colnext:
    inc    r12d
    cmp    r12d, 16
    jb     .xl
    inc    r13d
    cmp    r13d, 16
    jb     .zl
ENDPX

; world coords, r9d = id | kind<<8. clip mode only writes inside ctx.chunk,
; world mode (world_set_block) is for saplings on the main thread
FN wg_put, 0
    cmp    edx, CHUNK_H-1
    ja     .out
    cmp    dword [rbx+WG.mode], 0
    jne    .world
    sub    ecx, [rbx+WG.ox]
    cmp    ecx, 15
    ja     .out
    sub    r8d, [rbx+WG.oz]
    cmp    r8d, 15
    ja     .out
    shl    r8d, 4
    or     ecx, r8d
    shl    edx, 8
    or     ecx, edx
    mov    rax, [rbx+WG.chunk]
    lea    rax, [rax+rcx+CHUNK_BLOCKS]
    movzx  edx, byte [rax]
    mov    r10d, r9d
    shr    r10d, 8
    test   r10d, K_FORCE
    jnz    .force
    lea    r11, [rel wg_repl]
    test   [r11+rdx], r10b
    jz     .out
    mov    [rax], r9b
    jmp    .out
.force:
    cmp    edx, B_BEDROCK
    je     .out
    mov    [rax], r9b
    jmp    .out
.world:
    mov    esi, ecx
    mov    edi, edx
    mov    r12d, r8d
    mov    r13d, r9d
    call   world_get_block
    mov    r10d, r13d
    shr    r10d, 8
    test   r10d, K_FORCE
    jnz    .wforce
    lea    r11, [rel wg_repl]
    test   [r11+rax], r10b
    jz     .out
    jmp    .wset
.wforce:
    cmp    eax, B_BEDROCK
    je     .out
.wset:
    mov    ecx, esi
    mov    edx, edi
    mov    r8d, r12d
    movzx  r9d, r13b
    call   world_set_block
.out:
ENDP

; random walk ore blob. n <= 16 keeps it within 16 blocks of the start, that's
; why the 3x3 replay catches every vein touching this chunk. y gets capped at
; ymax-1 so the +1 branch can't leak either (diamonds stay <= 16)
FN wg_vein, 0
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    r15d, r9d
    or     r15d, K_STONE<<8
    mov    esi, ARG5
.step:
    mov    eax, ARG6
    dec    eax
    cmp    r13d, eax
    jle    .ycap
    mov    r13d, eax
.ycap:
    mov    ecx, r12d
    mov    edx, r13d
    mov    r8d, r14d
    mov    r9d, r15d
    call   wg_put
    call   wg_rand
    mov    edi, eax
    test   edi, 1
    jz     .b1
    lea    ecx, [r12+1]
    mov    edx, r13d
    mov    r8d, r14d
    mov    r9d, r15d
    call   wg_put
.b1:
    test   edi, 2
    jz     .b2
    mov    ecx, r12d
    lea    edx, [r13+1]
    mov    r8d, r14d
    mov    r9d, r15d
    call   wg_put
.b2:
    test   edi, 4
    jz     .b3
    mov    ecx, r12d
    mov    edx, r13d
    lea    r8d, [r14+1]
    mov    r9d, r15d
    call   wg_put
.b3:
    shr    edi, 8
    and    edi, 0xFFFF
    imul   edi, edi, 6
    shr    edi, 16
    cmp    edi, 0
    jne    .d1
    inc    r12d
.d1:
    cmp    edi, 1
    jne    .d2
    dec    r12d
.d2:
    cmp    edi, 2
    jne    .d3
    inc    r13d
.d3:
    cmp    edi, 3
    jne    .d4
    dec    r13d
.d4:
    cmp    edi, 4
    jne    .d5
    inc    r14d
.d5:
    cmp    edi, 5
    jne    .d6
    dec    r14d
.d6:
    dec    esi
    jg     .step
ENDP

; replay the ore veins of the 3x3 neighbours
FN wg_ores, 32
    mov    dword LOC(0), -1
.nz:
    mov    dword LOC(4), -1
.nx:
    mov    ecx, [rbx+WG.cx]
    add    ecx, LOC(4)
    mov    LOC(8), ecx
    mov    edx, [rbx+WG.cz]
    add    edx, LOC(0)
    mov    LOC(12), edx
    mov    r8d, S_ORE
    call   wg_seed64
    mov    [rbx+WG.rng], rax
    xor    r12d, r12d
.ot:
    lea    rax, [rel ore_tbl]
    imul   ecx, r12d, 6
    add    rax, rcx
    mov    r13, rax
    movzx  r14d, byte [r13+1]
.vn:
    test   r14d, r14d
    jz     .otnext
    dec    r14d
    mov    ecx, 16
    call   wg_randn
    mov    esi, LOC(8)
    shl    esi, 4
    add    esi, eax                     ; x
    mov    ecx, 16
    call   wg_randn
    mov    edi, LOC(12)
    shl    edi, 4
    add    edi, eax                     ; z
    movzx  ecx, byte [r13+3]
    movzx  eax, byte [r13+2]
    sub    ecx, eax
    inc    ecx
    call   wg_randn
    movzx  ecx, byte [r13+2]
    add    eax, ecx
    mov    r15d, eax                    ; y
    movzx  ecx, byte [r13+5]
    call   wg_randn
    movzx  ecx, byte [r13+4]
    add    eax, ecx                     ; size
    mov    [rsp+32], rax                ; ARG5 n
    movzx  eax, byte [r13+3]
    mov    [rsp+40], rax                ; ARG6 ymax
    mov    ecx, esi
    mov    edx, r15d
    mov    r8d, edi
    movzx  r9d, byte [r13]
    call   wg_vein
    jmp    .vn
.otnext:
    inc    r12d
    cmp    r12d, ORE_N
    jb     .ot
    inc    dword LOC(4)
    cmp    dword LOC(4), 1
    jle    .nx
    inc    dword LOC(0)
    cmp    dword LOC(0), 1
    jle    .nz
ENDP

; wg_get (leaf): rbx | ecx lx, edx y, r8d lz -> eax block in our own chunk,
; 0 if out of range. clobbers rcx rdx r8
align 16
wg_get:
    xor    eax, eax
    cmp    ecx, 15
    ja     .o
    cmp    r8d, 15
    ja     .o
    cmp    edx, CHUNK_H-1
    ja     .o
    shl    r8d, 4
    or     ecx, r8d
    shl    edx, 8
    or     ecx, edx
    mov    rax, [rbx+WG.chunk]
    movzx  eax, byte [rax+rcx+CHUNK_BLOCKS]
.o:
    ret

; glowcrystals on deep cave ceilings + the odd mossy ruin. both stay inside
; this chunk so no replay needed
FN wg_structures, 32
    mov    ecx, [rbx+WG.cx]
    mov    edx, [rbx+WG.cz]
    mov    r8d, S_GLOW
    call   wg_seed64
    mov    [rbx+WG.rng], rax
    mov    r15d, 5
.ga:
    mov    ecx, 12
    call   wg_randn
    lea    r12d, [rax+2]
    mov    ecx, 12
    call   wg_randn
    lea    r13d, [rax+2]
    mov    ecx, 40
    call   wg_randn
    lea    r14d, [rax+6]
    call   wg_rand
    mov    LOC(0), eax
    ; climb looking for air with stone above
    mov    esi, 12
.climb:
    mov    ecx, r12d
    mov    edx, r14d
    mov    r8d, r13d
    call   wg_get
    test   eax, eax
    jnz    .cnext
    mov    ecx, r12d
    lea    edx, [r14+1]
    mov    r8d, r13d
    call   wg_get
    cmp    eax, B_STONE
    je     .found
.cnext:
    inc    r14d
    dec    esi
    jnz    .climb
    jmp    .gnext
.found:
    ; 4..11 crystals drifting down
    mov    edi, LOC(0)
    mov    esi, edi
    and    esi, 7
    add    esi, 4
.hang:
    mov    ecx, [rbx+WG.ox]
    add    ecx, r12d
    mov    edx, r14d
    mov    r8d, [rbx+WG.oz]
    add    r8d, r13d
    mov    r9d, B_GLOWCRYSTAL | (K_LEAF<<8)
    call   wg_put
    shr    edi, 3
    mov    eax, edi
    and    eax, 3
    cmp    eax, 2
    jae    .down
    test   eax, eax
    jz     .xm
    inc    r12d
    jmp    .zz
.xm:
    dec    r12d
.zz:
    test   edi, 4
    jz     .zm
    inc    r13d
    jmp    .down
.zm:
    dec    r13d
.down:
    dec    r14d
    test   edi, edi
    jnz    .hn
    call   wg_rand
    mov    edi, eax
.hn:
    dec    esi
    jnz    .hang
.gnext:
    dec    r15d
    jnz    .ga

    mov    ecx, [rbx+WG.cx]
    mov    edx, [rbx+WG.cz]
    xor    r8d, r8d
    mov    r9d, S_RUIN
    call   wg_hash
    and    eax, 0xFFFF
    cmp    eax, 65536/14                ; ~1 chunk in 14
    jae    .done
    mov    ecx, [rbx+WG.cx]
    mov    edx, [rbx+WG.cz]
    mov    r8d, S_RUIN+1
    call   wg_seed64
    mov    [rbx+WG.rng], rax
    mov    ecx, 7
    call   wg_randn
    lea    r12d, [rax+1]
    mov    ecx, 7
    call   wg_randn
    lea    r13d, [rax+1]
    mov    ecx, 26
    call   wg_randn
    lea    r14d, [rax+12]
    ; must be well underground: centre column surface > y0 + 12
    lea    eax, [r13+3+1]
    imul   eax, eax, COLS_N
    lea    eax, [rax+r12+3+1]
    shl    eax, 6
    lea    rsi, [rbx+WG.cols]
    mov    eax, [rsi+rax+C_HS]
    lea    ecx, [r14+12]
    cmp    eax, ecx
    jle    .done
    add    r12d, [rbx+WG.ox]
    add    r13d, [rbx+WG.oz]
    mov    dword LOC(0), 0              ; dy
.ry:
    mov    dword LOC(4), 0              ; dz
.rz:
    mov    dword LOC(8), 0              ; dx
.rx:
    mov    ecx, r12d
    add    ecx, LOC(8)
    mov    edx, r14d
    add    edx, LOC(0)
    mov    r8d, r13d
    add    r8d, LOC(4)
    mov    LOC(12), ecx
    mov    LOC(16), edx
    mov    LOC(20), r8d
    mov    r9d, S_RUIN+2
    call   wg_hash
    mov    esi, eax
    ; on the shell?
    mov    eax, LOC(8)
    test   eax, eax
    jz     .shell
    cmp    eax, 6
    je     .shell
    mov    eax, LOC(4)
    test   eax, eax
    jz     .shell
    cmp    eax, 6
    je     .shell
    mov    eax, LOC(0)
    test   eax, eax
    jz     .shell
    cmp    eax, 5
    je     .shell
    xor    r9d, r9d
    jmp    .rput
.shell:
    mov    r9d, B_COBBLE
    mov    eax, esi
    and    eax, 255
    cmp    eax, 110                     ; ~43 % moss
    jae    .nomoss
    mov    r9d, B_MOSSY_COBBLE
.nomoss:
    cmp    dword LOC(0), 0
    jne    .notfloor
    mov    r9d, B_MOSSY_COBBLE
    test   esi, 0x300
    jnz    .notfloor
    mov    r9d, B_COBBLE
.notfloor:
    ; ~12% holes in the walls
    mov    eax, LOC(0)
    test   eax, eax
    jz     .rput
    cmp    eax, 5
    je     .rput
    mov    eax, esi
    shr    eax, 12
    and    eax, 15
    cmp    eax, 2
    jae    .rput
    xor    r9d, r9d
.rput:
    or     r9d, K_FORCE<<8
    mov    ecx, LOC(12)
    mov    edx, LOC(16)
    mov    r8d, LOC(20)
    call   wg_put
    inc    dword LOC(8)
    cmp    dword LOC(8), 6
    jle    .rx
    inc    dword LOC(4)
    cmp    dword LOC(4), 6
    jle    .rz
    inc    dword LOC(0)
    cmp    dword LOC(0), 5
    jle    .ry
%macro RUIN_PUT 4
    lea    ecx, [r12+%1]
    lea    edx, [r14+%2]
    lea    r8d, [r13+%3]
    mov    r9d, %4 | (K_FORCE<<8)
    call   wg_put
%endmacro
    RUIN_PUT 3, 4, 3, B_LANTERN
    RUIN_PUT 1, 1, 2, B_BOOKSHELF
    RUIN_PUT 1, 2, 2, B_BOOKSHELF
    RUIN_PUT 1, 1, 3, B_BOOKSHELF
    RUIN_PUT 1, 1, 4, B_BOOKSHELF
    RUIN_PUT 5, 1, 1, B_CRAFT_TABLE
    RUIN_PUT 5, 1, 5, B_STONE_BRICKS
    RUIN_PUT 5, 2, 5, B_TORCH
.done:
ENDP

; trees. rbx ctx with log/leaf ids set, ecx x, edx first trunk y, r8d z, world coords.
; everything goes through wg_put so saplings reuse the same shapes. shape rolls only from trng

; leaf ellipsoid, xmm0 rxz, xmm1 ry. hashed fuzzy edge, otherwise every canopy is a perfect ball
FNX wg_blob, 32
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    FCONST xmm3, 1.0
    movaps xmm2, xmm0
    mulss  xmm2, xmm0
    movaps xmm6, xmm3
    divss  xmm6, xmm2
    movaps xmm2, xmm1
    mulss  xmm2, xmm1
    movaps xmm7, xmm3
    divss  xmm7, xmm2
    FCONST xmm2, 0.99
    addss  xmm0, xmm2
    cvttss2si eax, xmm0
    mov    LOC(0), eax
    addss  xmm1, xmm2
    cvttss2si eax, xmm1
    mov    LOC(4), eax
    mov    esi, LOC(4)
    neg    esi
.yl:
    mov    edi, LOC(0)
    neg    edi
.zl:
    mov    r15d, LOC(0)
    neg    r15d
.xl:
    mov    eax, r15d
    imul   eax, eax
    mov    ecx, edi
    imul   ecx, ecx
    add    eax, ecx
    cvtsi2ss xmm8, eax
    mulss  xmm8, xmm6
    mov    eax, esi
    imul   eax, eax
    cvtsi2ss xmm0, eax
    mulss  xmm0, xmm7
    addss  xmm8, xmm0
    FCONST xmm0, 1.17
    comiss xmm8, xmm0
    ja     .next
    lea    ecx, [r12+r15]
    lea    edx, [r13+rsi]
    lea    r8d, [r14+rdi]
    mov    r9d, S_LEAF
    call   wg_hash
    and    eax, 255
    cvtsi2ss xmm0, eax
    FCONST xmm1, 0.002157               ; 0.55 / 255
    mulss  xmm0, xmm1
    FCONST xmm1, 0.62
    addss  xmm0, xmm1                   ; threshold 0.62 .. 1.17
    comiss xmm8, xmm0
    ja     .next
    lea    ecx, [r12+r15]
    lea    edx, [r13+rsi]
    lea    r8d, [r14+rdi]
    mov    r9d, [rbx+WG.leafid]
    or     r9d, K_LEAF<<8
    call   wg_put
.next:
    inc    r15d
    cmp    r15d, LOC(0)
    jle    .xl
    inc    edi
    cmp    edi, LOC(0)
    jle    .zl
    inc    esi
    cmp    esi, LOC(4)
    jle    .yl
ENDPX

; flat leaf layer of radius r9d, outer ring thinned out
FN wg_disc, 16
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    r15d, r9d
    mov    eax, r9d
    imul   eax, eax
    imul   ecx, r9d, 6
    push   rax
    mov    eax, ecx
    xor    edx, edx
    mov    ecx, 10
    div    ecx
    pop    rcx
    add    eax, ecx
    mov    LOC(0), eax                  ; r^2 + 0.6 r
    lea    eax, [r15-1]
    imul   eax, eax
    mov    LOC(4), eax
    mov    edi, r15d
    neg    edi
.zl:
    mov    esi, r15d
    neg    esi
.xl:
    mov    eax, esi
    imul   eax, eax
    mov    ecx, edi
    imul   ecx, ecx
    add    eax, ecx
    cmp    eax, LOC(0)
    jg     .next
    cmp    r15d, 1
    jle    .put
    cmp    eax, LOC(4)
    jle    .put
    lea    ecx, [r12+rsi]
    mov    edx, r13d
    lea    r8d, [r14+rdi]
    mov    r9d, S_LEAF+1
    call   wg_hash
    test   eax, 7
    jz     .next                        ; 1 in 8 outer leaves missing
.put:
    lea    ecx, [r12+rsi]
    mov    edx, r13d
    lea    r8d, [r14+rdi]
    mov    r9d, [rbx+WG.leafid]
    or     r9d, K_LEAF<<8
    call   wg_put
.next:
    inc    esi
    cmp    esi, r15d
    jle    .xl
    inc    edi
    cmp    edi, r15d
    jle    .zl
ENDP

; h logs up, grass under the root -> dirt
FN wg_trunk, 0
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    r15d, r9d
    lea    edx, [r13-1]
    mov    r9d, B_DIRT | (K_GROUND<<8)
    call   wg_put
    xor    esi, esi
.l:
    cmp    esi, r15d
    jge    .done
    mov    ecx, r12d
    lea    edx, [r13+rsi]
    mov    r8d, r14d
    mov    r9d, [rbx+WG.logid]
    or     r9d, K_LOG<<8
    call   wg_put
    inc    esi
    jmp    .l
.done:
ENDP

FN wg_log, 0
    mov    r9d, [rbx+WG.logid]
    or     r9d, K_LOG<<8
    call   wg_put
ENDP

; xmm0 = base + trandn(n) * step
%macro RANDF 3
    mov    ecx, %1
    call   wg_trandn
    cvtsi2ss xmm0, eax
    FCONST xmm1, %3
    mulss  xmm0, xmm1
    FCONST xmm1, %2
    addss  xmm0, xmm1
%endmacro

FN tr_oak, 0
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    ecx, 3
    call   wg_trandn
    lea    r15d, [rax+4]
    mov    ecx, r12d
    mov    edx, r13d
    mov    r8d, r14d
    mov    r9d, r15d
    call   wg_trunk
    RANDF  4, 2.35, 0.15
    FCONST xmm1, 1.9
    mov    ecx, r12d
    lea    edx, [r13+r15-1]
    mov    r8d, r14d
    call   wg_blob
ENDP

FN tr_birch, 0
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    ecx, 3
    call   wg_trandn
    lea    r15d, [rax+5]
    mov    ecx, r12d
    mov    edx, r13d
    mov    r8d, r14d
    mov    r9d, r15d
    call   wg_trunk
    RANDF  3, 1.95, 0.15
    FCONST xmm1, 2.3
    mov    ecx, r12d
    lea    edx, [r13+r15-1]
    mov    r8d, r14d
    call   wg_blob
ENDP

FN tr_bush, 0
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    r9d, 1
    call   wg_trunk
    RANDF  3, 1.9, 0.2
    FCONST xmm1, 1.25
    mov    ecx, r12d
    lea    edx, [r13+1]
    mov    r8d, r14d
    call   wg_blob
ENDP

; big oak: 2-4 rising branches, a blob on each tip
FN tr_bigoak, 48
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    ecx, 4
    call   wg_trandn
    lea    r15d, [rax+8]
    mov    ecx, r12d
    mov    edx, r13d
    mov    r8d, r14d
    mov    r9d, r15d
    call   wg_trunk
    mov    ecx, 3
    call   wg_trandn
    add    eax, 2
    mov    LOC(0), eax
    xor    edi, edi
.br:
    mov    ecx, r15d
    shr    ecx, 1
    dec    ecx
    call   wg_trandn
    mov    edx, r15d
    shr    edx, 1
    add    eax, edx
    add    eax, r13d
    mov    LOC(4), eax
    mov    ecx, 8
    call   wg_trandn
    lea    rcx, [rel dirs8]
    movsx  edx, byte [rcx+rax*2]
    mov    LOC(8), edx
    movsx  edx, byte [rcx+rax*2+1]
    mov    LOC(12), edx
    mov    ecx, 2
    call   wg_trandn
    add    eax, 2
    mov    LOC(16), eax
    mov    esi, 1
.bl:
    mov    eax, LOC(8)
    imul   eax, esi
    lea    ecx, [r12+rax]
    mov    edx, LOC(4)
    add    edx, esi
    mov    eax, LOC(12)
    imul   eax, esi
    lea    r8d, [r14+rax]
    call   wg_log
    inc    esi
    cmp    esi, LOC(16)
    jle    .bl
    imul   eax, edi, 12
    lea    r10, [rbx+WG.ends]
    add    r10, rax
    mov    eax, LOC(8)
    imul   eax, LOC(16)
    add    eax, r12d
    mov    [r10], eax
    mov    eax, LOC(4)
    add    eax, LOC(16)
    mov    [r10+4], eax
    mov    eax, LOC(12)
    imul   eax, LOC(16)
    add    eax, r14d
    mov    [r10+8], eax
    inc    edi
    cmp    edi, LOC(0)
    jb     .br
    ; leaves last so they never displace logs
    xor    edi, edi
.bb:
    imul   eax, edi, 12
    lea    r10, [rbx+WG.ends]
    add    r10, rax
    mov    ecx, [r10]
    mov    edx, [r10+4]
    mov    r8d, [r10+8]
    FCONST xmm0, 2.3
    FCONST xmm1, 1.6
    call   wg_blob
    inc    edi
    cmp    edi, LOC(0)
    jb     .bb
    mov    ecx, r12d
    lea    edx, [r13+r15]
    mov    r8d, r14d
    FCONST xmm0, 3.0
    FCONST xmm1, 2.2
    call   wg_blob
ENDP

; pine: layered cone
FN tr_pine, 16
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    ecx, 6
    call   wg_trandn
    lea    r15d, [rax+7]
    mov    ecx, r12d
    mov    edx, r13d
    mov    r8d, r14d
    mov    r9d, r15d
    call   wg_trunk
    mov    ecx, r12d
    lea    edx, [r13+r15]
    mov    r8d, r14d
    mov    r9d, [rbx+WG.leafid]
    or     r9d, K_LEAF<<8
    call   wg_put
    mov    ecx, r12d
    lea    edx, [r13+r15+1]
    mov    r8d, r14d
    mov    r9d, [rbx+WG.leafid]
    or     r9d, K_LEAF<<8
    call   wg_put
    mov    eax, 2
    cmp    r15d, 10
    jl     .rm
    mov    eax, 3
.rm:
    mov    LOC(0), eax
    xor    eax, eax
    cmp    r15d, 9
    setg   al
    lea    eax, [r13+rax+2]
    mov    LOC(4), eax
    mov    ecx, 2
    call   wg_trandn
    mov    esi, eax                     ; start 0/1 for variety
    lea    edi, [r13+r15-1]
.layer:
    cmp    edi, LOC(4)
    jl     .done
    mov    eax, esi
    cmp    eax, 19
    jbe    .pi
    mov    eax, 19
.pi:
    lea    rcx, [rel pine_pat]
    movzx  r9d, byte [rcx+rax]
    cmp    r9d, LOC(0)
    jle    .ri
    mov    r9d, LOC(0)
.ri:
    mov    ecx, r12d
    mov    edx, edi
    mov    r8d, r14d
    call   wg_disc
    inc    esi
    dec    edi
    jmp    .layer
.done:
ENDP

; jungle giant, 2x2 trunk
FN tr_giant, 48
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    ecx, 8
    call   wg_trandn
    lea    r15d, [rax+16]
    mov    eax, 116
    sub    eax, r13d
    cmp    r15d, eax
    jle    .hok
    mov    r15d, eax
.hok:
    cmp    r15d, 8
    jge    .hok2
    mov    r15d, 8
.hok2:
    xor    esi, esi
.tk:
    mov    ecx, esi
    and    ecx, 1
    add    ecx, r12d
    mov    r8d, esi
    shr    r8d, 1
    add    r8d, r14d
    mov    edx, r13d
    mov    r9d, r15d
    call   wg_trunk
    inc    esi
    cmp    esi, 4
    jb     .tk
    mov    ecx, 2
    call   wg_trandn
    add    eax, 2
    mov    LOC(0), eax
    xor    edi, edi
.br:
    mov    eax, r15d
    xor    edx, edx
    mov    ecx, 3
    div    ecx
    mov    ecx, eax
    call   wg_trandn
    mov    edx, r15d
    shr    edx, 1
    add    eax, edx
    add    eax, r13d
    mov    LOC(4), eax
    mov    ecx, 8
    call   wg_trandn
    lea    rcx, [rel dirs8]
    movsx  edx, byte [rcx+rax*2]
    mov    LOC(8), edx
    movsx  edx, byte [rcx+rax*2+1]
    mov    LOC(12), edx
    mov    ecx, 2
    call   wg_trandn
    add    eax, 3
    mov    LOC(16), eax
    ; start at the trunk face the branch points to
    xor    eax, eax
    cmp    dword LOC(8), 0
    setg   al
    add    eax, r12d
    mov    LOC(20), eax
    xor    eax, eax
    cmp    dword LOC(12), 0
    setg   al
    add    eax, r14d
    mov    LOC(24), eax
    mov    esi, 1
.bl:
    mov    eax, LOC(8)
    imul   eax, esi
    mov    ecx, LOC(20)
    add    ecx, eax
    mov    edx, LOC(4)
    cmp    esi, LOC(16)
    jne    .flat
    inc    edx                          ; tip rises one block
.flat:
    mov    eax, LOC(12)
    imul   eax, esi
    mov    r8d, LOC(24)
    add    r8d, eax
    call   wg_log
    inc    esi
    cmp    esi, LOC(16)
    jle    .bl
    imul   eax, edi, 12
    lea    r10, [rbx+WG.ends]
    add    r10, rax
    mov    eax, LOC(8)
    imul   eax, LOC(16)
    add    eax, LOC(20)
    mov    [r10], eax
    mov    eax, LOC(4)
    add    eax, 2
    mov    [r10+4], eax
    mov    eax, LOC(12)
    imul   eax, LOC(16)
    add    eax, LOC(24)
    mov    [r10+8], eax
    inc    edi
    cmp    edi, LOC(0)
    jb     .br
    mov    ecx, r12d
    lea    edx, [r13+r15]
    mov    r8d, r14d
    FCONST xmm0, 4.4
    FCONST xmm1, 1.7
    call   wg_blob
    lea    ecx, [r12+1]
    lea    edx, [r13+r15+1]
    lea    r8d, [r14+1]
    FCONST xmm0, 3.0
    FCONST xmm1, 1.4
    call   wg_blob
    xor    edi, edi
.bb:
    imul   eax, edi, 12
    lea    r10, [rbx+WG.ends]
    add    r10, rax
    mov    ecx, [r10]
    mov    edx, [r10+4]
    mov    r8d, [r10+8]
    FCONST xmm0, 2.4
    FCONST xmm1, 1.3
    call   wg_blob
    inc    edi
    cmp    edi, LOC(0)
    jb     .bb
ENDP

FN tr_jtall, 0
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    ecx, 5
    call   wg_trandn
    lea    r15d, [rax+9]
    mov    ecx, r12d
    mov    edx, r13d
    mov    r8d, r14d
    mov    r9d, r15d
    call   wg_trunk
    mov    ecx, r12d
    lea    edx, [r13+r15]
    mov    r8d, r14d
    FCONST xmm0, 3.1
    FCONST xmm1, 1.7
    call   wg_blob
    call   wg_trand
    test   eax, 1
    jz     .done
    mov    ecx, r12d
    lea    edx, [r13+r15-4]
    mov    r8d, r14d
    FCONST xmm0, 1.8
    FCONST xmm1, 1.0
    call   wg_blob
.done:
ENDP

; acacia: trunk bends sideways into a flat umbrella
FN tr_acacia, 32
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    ecx, 2
    call   wg_trandn
    lea    r15d, [rax+3]
    mov    ecx, r12d
    mov    edx, r13d
    mov    r8d, r14d
    mov    r9d, r15d
    call   wg_trunk
    mov    ecx, 8
    call   wg_trandn
    mov    LOC(16), eax
    lea    rcx, [rel dirs8]
    movsx  edx, byte [rcx+rax*2]
    mov    LOC(0), edx
    movsx  edx, byte [rcx+rax*2+1]
    mov    LOC(4), edx
    mov    ecx, 2
    call   wg_trandn
    lea    esi, [rax+2]
    mov    LOC(20), r12d
    lea    eax, [r13+r15-1]
    mov    LOC(24), eax
    mov    LOC(28), r14d
.bend:
    mov    eax, LOC(0)
    add    LOC(20), eax
    mov    eax, LOC(4)
    add    LOC(28), eax
    inc    dword LOC(24)
    mov    ecx, LOC(20)
    mov    edx, LOC(24)
    mov    r8d, LOC(28)
    call   wg_log
    dec    esi
    jnz    .bend
    mov    ecx, LOC(20)
    mov    edx, LOC(24)
    inc    edx
    mov    r8d, LOC(28)
    mov    r9d, 3
    call   wg_disc
    mov    ecx, LOC(20)
    mov    edx, LOC(24)
    add    edx, 2
    mov    r8d, LOC(28)
    mov    r9d, 1
    call   wg_disc
    ; sometimes a second shorter branch the other way
    call   wg_trand
    test   eax, 1
    jz     .done
    mov    eax, LOC(16)
    add    eax, 4
    and    eax, 7
    lea    rcx, [rel dirs8]
    movsx  edx, byte [rcx+rax*2]
    mov    LOC(0), edx
    movsx  edx, byte [rcx+rax*2+1]
    mov    LOC(4), edx
    mov    ecx, 2
    call   wg_trandn
    lea    esi, [rax+1]
    mov    LOC(20), r12d
    lea    eax, [r13+r15-2]
    mov    LOC(24), eax
    mov    LOC(28), r14d
.bend2:
    mov    eax, LOC(0)
    add    LOC(20), eax
    mov    eax, LOC(4)
    add    LOC(28), eax
    inc    dword LOC(24)
    mov    ecx, LOC(20)
    mov    edx, LOC(24)
    mov    r8d, LOC(28)
    call   wg_log
    dec    esi
    jnz    .bend2
    mov    ecx, LOC(20)
    mov    edx, LOC(24)
    inc    edx
    mov    r8d, LOC(28)
    mov    r9d, 2
    call   wg_disc
.done:
ENDP

; swamp tree, leaves hanging off the crown like moss
FN tr_swamp, 16
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    mov    ecx, 3
    call   wg_trandn
    lea    r15d, [rax+5]
    mov    ecx, r12d
    mov    edx, r13d
    mov    r8d, r14d
    mov    r9d, r15d
    call   wg_trunk
    mov    ecx, r12d
    lea    edx, [r13+r15-1]
    mov    r8d, r14d
    FCONST xmm0, 3.3
    FCONST xmm1, 1.35
    call   wg_blob
    mov    edi, -3
.zl:
    mov    esi, -3
.xl:
    mov    eax, esi
    imul   eax, eax
    mov    ecx, edi
    imul   ecx, ecx
    add    eax, ecx
    cmp    eax, 5
    jl     .next
    cmp    eax, 10
    jg     .next
    lea    ecx, [r12+rsi]
    xor    edx, edx
    lea    r8d, [r14+rdi]
    mov    r9d, S_DROOP
    call   wg_hash
    test   eax, 3
    jnz    .next
    shr    eax, 2
    and    eax, 3
    cmp    eax, 3
    jb     .lenok
    mov    eax, 1
.lenok:
    inc    eax
    mov    LOC(0), eax
    mov    dword LOC(4), 0
.strand:
    lea    ecx, [r12+rsi]
    lea    edx, [r13+r15-2]
    sub    edx, LOC(4)
    lea    r8d, [r14+rdi]
    mov    r9d, [rbx+WG.leafid]
    or     r9d, K_LEAF<<8
    call   wg_put
    inc    dword LOC(4)
    mov    eax, LOC(4)
    cmp    eax, LOC(0)
    jl     .strand
.next:
    inc    esi
    cmp    esi, 3
    jle    .xl
    inc    edi
    cmp    edi, 3
    jle    .zl
ENDP

; half buried mossy cobble lump
FNX tr_boulder, 16
    mov    r12d, ecx
    mov    r13d, edx
    mov    r14d, r8d
    RANDF  3, 1.2, 0.45
    movaps xmm6, xmm0
    mulss  xmm0, xmm0
    FCONST xmm7, 1.0
    divss  xmm7, xmm0
    FCONST xmm0, 0.99
    addss  xmm0, xmm6
    cvttss2si eax, xmm0
    mov    LOC(0), eax
    mov    esi, eax
    neg    esi
.yl:
    mov    edi, LOC(0)
    neg    edi
.zl:
    mov    r15d, LOC(0)
    neg    r15d
.xl:
    mov    eax, r15d
    imul   eax, eax
    mov    ecx, edi
    imul   ecx, ecx
    add    eax, ecx
    mov    ecx, esi
    imul   ecx, ecx
    add    eax, ecx
    cvtsi2ss xmm8, eax
    mulss  xmm8, xmm7
    lea    ecx, [r12+r15]
    lea    edx, [r13+rsi]
    lea    r8d, [r14+rdi]
    mov    r9d, S_LEAF+7
    call   wg_hash
    mov    LOC(4), eax
    and    eax, 255
    cvtsi2ss xmm0, eax
    FCONST xmm1, 0.00196                ; 0.5 / 255
    mulss  xmm0, xmm1
    FCONST xmm1, 0.7
    addss  xmm0, xmm1
    comiss xmm8, xmm0
    ja     .next
    mov    r9d, B_MOSSY_COBBLE | (K_FORCE<<8)
    mov    eax, LOC(4)
    shr    eax, 8
    and    eax, 7
    cmp    eax, 5
    jb     .mossy
    mov    r9d, B_COBBLE | (K_FORCE<<8)
.mossy:
    lea    ecx, [r12+r15]
    lea    edx, [r13+rsi]
    lea    r8d, [r14+rdi]
    call   wg_put
.next:
    inc    r15d
    cmp    r15d, LOC(0)
    jle    .xl
    inc    edi
    cmp    edi, LOC(0)
    jle    .zl
    inc    esi
