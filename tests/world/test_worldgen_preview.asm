; eyeball test for worldgen: 32x32 chunks -> map.bmp (hill shaded top-down),
; biomes.bmp and slice.bmp (z = 0 cross section, 2x), plus timing and stats.
; @link src/world.asm src/worldgen.asm src/chunkmgr.asm src/noise.asm
; @link src/math.asm src/platform.asm src/gl.asm src/util.asm
; @link src/blocks.asm src/items.asm src/light.asm tests/world/wglib.asm
; @preview
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../world/wglib.inc"

%define SEED    12345
%define NCH     32
%define CX0     (-NCH/2)
%define CZ0     (-NCH/2)
%define SIZE    (NCH*16)
%define SLICE_J (NCH/2)                 ; slice runs along cz = 0
%define NBIOME  13

section .rdata
; RGB0 per block id. 80..87 all water, 88..91 all lava, unknown = magenta
col_tab:
        db 0,0,0,0,  125,125,125,0,  98,160,60,0,  134,96,67,0,  110,110,110,0,  255,0,255,0,  40,40,40,0,  219,207,163,0   ; 0..7
        db 136,126,126,0,  102,81,51,0,  60,120,40,0,  255,0,255,0,  60,60,60,0,  190,150,120,0,  240,210,70,0,  100,230,230,0   ; 8..15
        db 210,195,150,0,  245,250,255,0,  160,200,255,0,  60,130,50,0,  160,165,180,0,  220,220,210,0,  110,160,70,0,  60,45,30,0   ; 16..23
        db 50,90,60,0,  255,0,255,0,  120,120,120,0,  90,120,90,0,  150,110,60,0,  150,110,60,0,  255,0,255,0,  255,0,255,0   ; 24..31
        db 255,240,150,0,  255,0,255,0,  255,200,80,0,  90,150,50,0,  220,40,40,0,  240,220,40,0,  200,50,50,0,  150,110,80,0   ; 32..39
        db 140,110,60,0,  150,200,100,0,  230,140,30,0,  120,170,40,0,  255,0,255,0,  255,0,255,0,  255,0,255,0,  255,0,255,0   ; 40..47
        times 16 db 255,0,255,0                                                                                              ; 48..63
        db 235,245,250,0,  255,0,255,0,  255,0,255,0,  255,220,120,0,  255,0,255,0,  255,0,255,0,  255,0,255,0,  255,0,255,0   ; 64..71
        times 8 db 255,0,255,0                                                                                               ; 72..79
        times 8 db 50,90,200,0                                                                                               ; 80..87
        times 4 db 230,90,20,0                                                                                               ; 88..91
        times (118-92) db 255,0,255,0                                                                                        ; 92..117
        db 190,104,48,0,  150,92,66,0,  164,86,40,0,  184,132,38,0,  142,62,46,0,  84,56,38,0,  206,176,158,0                ; 118..124 red sand, terracotta
        times (256-125) db 255,0,255,0                                                                                       ; 125..255
biome_col:
        db 30,60,160,0,  230,220,160,0,  140,200,90,0,  40,120,40,0,  150,210,130,0,  50,110,90,0
        db 235,240,250,0,  240,210,110,0,  130,130,130,0,  80,90,50,0,  20,170,30,0,  190,170,80,0
        db 200,100,50,0
; grass + leaf tint per biome, roughly biome_grass_color
grass_tint:
        db 142,185,113,0,  150,190,92,0,  141,189,84,0,  103,173,70,0,  140,192,104,0,  120,170,124,0
        db 170,200,180,0,  191,183,85,0,  132,168,128,0,  100,108,58,0,  78,196,44,0,  176,170,82,0
        db 144,129,77,0

; 0 = just print the id
block_names:
        dq bn_AIR, bn_STONE, bn_GRASS, bn_DIRT, bn_COBBLE, 0, bn_BEDROCK, bn_SAND
        dq bn_GRAVEL, bn_LOG, bn_LEAVES, 0, bn_COAL, bn_IRON, bn_GOLD, bn_DIAMOND
        dq bn_SANDSTONE, bn_SNOW, bn_ICE, bn_CACTUS, bn_CLAY, bn_BIRCH_LOG, bn_BIRCH_LEAVES, bn_PINE_LOG
        dq bn_PINE_LEAVES, 0, bn_STONE_BRICKS, bn_MOSSY, bn_BOOKSHELF, bn_CRAFT, 0, 0
        dq bn_GLOW, 0, bn_TORCH, bn_TALL_GRASS, bn_FLOWER_RED, bn_FLOWER_YELLOW, bn_MUSH_RED, bn_MUSH_BROWN
        dq bn_DEAD_BUSH, bn_REEDS, bn_PUMPKIN, bn_MELON, 0, 0, 0, 0
        dq 0, 0, 0, 0, 0, 0, 0, 0
        dq 0, 0, 0, 0, 0, 0, 0, 0
        dq bn_SNOWY_GRASS, bn_SAPLING, 0, bn_LANTERN, 0, 0, 0, 0
        dq 0, 0, 0, 0, 0, 0, 0, 0
        dq bn_WATER, 0, 0, 0, 0, 0, 0, 0
        dq bn_LAVA, 0, 0, 0, 0, 0, 0, 0
        times (256-96) dq 0
bn_AIR: db "AIR", 0
bn_STONE: db "STONE", 0
bn_GRASS: db "GRASS", 0
bn_DIRT: db "DIRT", 0
bn_COBBLE: db "COBBLE", 0
bn_BEDROCK: db "BEDROCK", 0
bn_SAND: db "SAND", 0
bn_GRAVEL: db "GRAVEL", 0
bn_LOG: db "LOG", 0
bn_LEAVES: db "LEAVES", 0
bn_COAL: db "COAL", 0
bn_IRON: db "IRON", 0
bn_GOLD: db "GOLD", 0
bn_DIAMOND: db "DIAMOND", 0
bn_SANDSTONE: db "SANDSTONE", 0
bn_SNOW: db "SNOW", 0
bn_ICE: db "ICE", 0
bn_CACTUS: db "CACTUS", 0
bn_CLAY: db "CLAY", 0
bn_BIRCH_LOG: db "BIRCH_LOG", 0
bn_BIRCH_LEAVES: db "BIRCH_LEAVES", 0
bn_PINE_LOG: db "PINE_LOG", 0
bn_PINE_LEAVES: db "PINE_LEAVES", 0
bn_STONE_BRICKS: db "STONE_BRICKS", 0
bn_MOSSY: db "MOSSY", 0
bn_BOOKSHELF: db "BOOKSHELF", 0
bn_CRAFT: db "CRAFT", 0
bn_GLOW: db "GLOW", 0
bn_TORCH: db "TORCH", 0
bn_TALL_GRASS: db "TALL_GRASS", 0
bn_FLOWER_RED: db "FLOWER_RED", 0
bn_FLOWER_YELLOW: db "FLOWER_YELLOW", 0
bn_MUSH_RED: db "MUSH_RED", 0
bn_MUSH_BROWN: db "MUSH_BROWN", 0
bn_DEAD_BUSH: db "DEAD_BUSH", 0
bn_REEDS: db "REEDS", 0
bn_PUMPKIN: db "PUMPKIN", 0
bn_MELON: db "MELON", 0
bn_SNOWY_GRASS: db "SNOWY_GRASS", 0
bn_SAPLING: db "SAPLING", 0
bn_LANTERN: db "LANTERN", 0
bn_WATER: db "WATER", 0
bn_LAVA: db "LAVA", 0
biome_names:
        dq bi0, bi1, bi2, bi3, bi4, bi5, bi6, bi7, bi8, bi9, bi10, bi11, bi12
bi0:  db "ocean", 0
bi1:  db "beach", 0
bi2:  db "plains", 0
bi3:  db "forest", 0
bi4:  db "birch", 0
bi5:  db "taiga", 0
bi6:  db "tundra", 0
bi7:  db "desert", 0
bi8:  db "mountains", 0
bi9:  db "swamp", 0
bi10: db "jungle", 0
bi11: db "savanna", 0
bi12: db "badlands", 0

p_map    db "map.bmp", 0
p_biomes db "biomes.bmp", 0
p_slice  db "slice.bmp", 0

align 8
d_1      dq 1.0
d_14     dq 14.0
d_055    dq 0.55
d_006    dq 0.06
d_40     dq 40.0
d_88     dq 88.0
d_04     dq 0.4
d_075    dq 0.75
d_045    dq 0.45
d_135    dq 1.35
d_100    dq 100.0
d_1000   dq 1000.0

section .bss
alignb 16
px_top    resb SIZE*SIZE                ; top block per pixel
px_under  resb SIZE*SIZE                ; ground under water, if top is water
px_bio    resb SIZE*SIZE
px_h      resb SIZE*SIZE
px_dep    resb SIZE*SIZE                ; water+ice depth
sl_blk    resb SIZE*128                 ; row 0 = y 127
sl_bio    resb SIZE
stats     resd 256
bcount    resd 16                       ; slot 15 = bad biome id
order     resd 256
img       resq 1                        ; sized for the bigger of the images

section .text

; -> 0x00BBGGRR. leaf, only touches rax rcx rdx r8 r9
LEAF col_of
    cmp  edx, NBIOME
    jb   .bok
    mov  eax, 0x00FF00FF
    ret
.bok:
    cmp  ecx, B_GRASS
    je   .grass
    cmp  ecx, B_TALL_GRASS
    je   .grass
    cmp  ecx, B_LEAVES
    je   .leaves
    lea  rax, [rel col_tab]
    mov  eax, [rax+rcx*4]
    ret
.grass:
    lea  rax, [rel grass_tint]
    mov  eax, [rax+rdx*4]
    ret
.leaves:                                ; tint * (.6, .7, .6)
    lea  rax, [rel grass_tint]
    mov  r8d, [rax+rdx*4]
    mov  r9d, 10
    movzx eax, r8b
    imul eax, eax, 6
    xor  edx, edx
    div  r9d
    mov  ecx, eax
    mov  eax, r8d
    shr  eax, 8
    movzx eax, al
    imul eax, eax, 7
    xor  edx, edx
    div  r9d
    shl  eax, 8
    or   ecx, eax
    mov  eax, r8d
    shr  eax, 16
    movzx eax, al
    imul eax, eax, 6
    xor  edx, edx
    div  r9d
    shl  eax, 16
    or   eax, ecx
    ret

; jumps to %2 unless %1 is water (any level) or ice
%macro IS_WATERISH 2
    cmp  %1, B_ICE
    je   %%yes
    cmp  %1, B_WATER
    jb   %2
    cmp  %1, B_WATER_LAST
    ja   %2
%%yes:
%endmacro

; worker thread. chunk (CX0 + i % 32, CZ0 + i / 32), fills the px_* maps,
; histograms go to the stack first and get lock added at the end
PROC map_job, 256*4 + 16*4
    mov  rbx, rdx
    mov  eax, ecx
    xor  edx, edx
    mov  ecx, NCH
    div  ecx
    mov  r12d, edx
    mov  r13d, eax
    mov  rcx, rbx
    lea  edx, [r12d+CX0]
    lea  r8d, [r13d+CZ0]
    call wg_gen
    lea  rdi, LOC(0)
    xor  eax, eax
    mov  ecx, 256+16
    rep  stosd
    xor  ecx, ecx
.hist:
    movzx eax, byte [rbx+WG_BLOCKS+rcx]
    inc  dword LOC(rax*4)
    inc  ecx
    cmp  ecx, 32768
    jl   .hist
    lea  r15, [rbx+WG_BLOCKS]
    xor  r14d, r14d
.col:
    movzx eax, byte [rbx+WG_BIOME+r14]
    mov  ecx, 15
    cmp  eax, NBIOME
    cmovae eax, ecx
    inc  dword LOC(1024+rax*4)
    mov  edi, r13d
    shl  edi, 4
    mov  ecx, r14d
    shr  ecx, 4
    add  edi, ecx
    imul edi, edi, SIZE
    mov  ecx, r12d
    shl  ecx, 4
    add  edi, ecx
    mov  ecx, r14d
    and  ecx, 15
    add  edi, ecx
    movzx eax, byte [rbx+WG_BIOME+r14]
    lea  rcx, [rel px_bio]
    mov  [rcx+rdi], al
    mov  esi, 127
.down:
    mov  eax, esi
    shl  eax, 8
    add  eax, r14d
    cmp  byte [r15+rax], 0
    jne  .top
    dec  esi
    jnz  .down
.top:
    mov  eax, esi ; v1: test_worldgen_preview scratch #0
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_worldgen_preview:0)
    shl  eax, 8 ; v1: test_worldgen_preview scratch #1
    add  eax, r14d ; v1: test_worldgen_preview scratch #2
    ; TODO: hoist invariant pointer load out of .loop (test_worldgen_preview:2)
    movzx eax, byte [r15+rax] ; v1: test_worldgen_preview scratch #3
    xor  r8d, r8d ; v1: test_worldgen_preview scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (test_worldgen_preview:4)
    xor  r9d, r9d ; v1: test_worldgen_preview scratch #5
    IS_WATERISH eax, .store ; v1: test_worldgen_preview scratch #6
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_worldgen_preview:6)
    mov  r10d, esi ; v1: test_worldgen_preview scratch #7
.wdown: ; v1: test_worldgen_preview scratch #8
    ; TODO: clamp index before table lookup on malformed input (test_worldgen_preview:8)
    test r10d, r10d ; v1: test_worldgen_preview scratch #9
    jz   .wdone ; v1: test_worldgen_preview scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_worldgen_preview:10)
    mov  ecx, r10d ; v1: test_worldgen_preview scratch #11
    shl  ecx, 8 ; v1: test_worldgen_preview scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_worldgen_preview:12)
    add  ecx, r14d ; v1: test_worldgen_preview scratch #13
    movzx ecx, byte [r15+rcx] ; v1: test_worldgen_preview scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_worldgen_preview:14)
    IS_WATERISH ecx, .wdone ; v1: test_worldgen_preview scratch #15
    dec  r10d ; v1: test_worldgen_preview scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_worldgen_preview:16)
    jmp  .wdown ; v1: test_worldgen_preview scratch #17
.wdone: ; v1: test_worldgen_preview scratch #18
    ; TODO: hoist invariant pointer load out of .loop (test_worldgen_preview:18)
    mov  r8d, esi ; v1: test_worldgen_preview scratch #19
    sub  r8d, r10d ; v1: test_worldgen_preview scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (test_worldgen_preview:20)
    cmp  eax, B_WATER ; v1: test_worldgen_preview scratch #21
    jne  .store ; v1: test_worldgen_preview scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_worldgen_preview:22)
    mov  ecx, r10d ; v1: test_worldgen_preview scratch #23
    shl  ecx, 8 ; v1: test_worldgen_preview scratch #24
    ; TODO: clamp index before table lookup on malformed input (test_worldgen_preview:24)
    add  ecx, r14d ; v1: test_worldgen_preview scratch #25
    movzx r9d, byte [r15+rcx] ; v1: test_worldgen_preview scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_worldgen_preview:26)
.store: ; v1: test_worldgen_preview scratch #27
    lea  rcx, [rel px_top] ; v1: test_worldgen_preview scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_worldgen_preview:28)
    mov  [rcx+rdi], al ; v1: test_worldgen_preview scratch #29
    lea  rcx, [rel px_under] ; v1: test_worldgen_preview scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_worldgen_preview:30)
    mov  [rcx+rdi], r9b
    lea  rcx, [rel px_h]
    mov  [rcx+rdi], sil
    lea  rcx, [rel px_dep]
    mov  [rcx+rdi], r8b
    inc  r14d
    cmp  r14d, 256
    jl   .col
    cmp  r13d, SLICE_J
    jne  .merge
    xor  esi, esi
.sx:
    movzx eax, byte [rbx+WG_BIOME+rsi]
    mov  ecx, r12d
    shl  ecx, 4
    add  ecx, esi
    lea  rdx, [rel sl_bio]
    mov  [rdx+rcx], al
    xor  edi, edi
.sy:
    mov  eax, edi
    shl  eax, 8
    add  eax, esi
    movzx eax, byte [r15+rax]
    mov  edx, 127
    sub  edx, edi
    imul edx, edx, SIZE
    add  edx, ecx
    lea  r8, [rel sl_blk]
    mov  [r8+rdx], al
    inc  edi
    cmp  edi, 128
    jl   .sy
    inc  esi
    cmp  esi, 16
    jl   .sx
.merge:
    lea  rdx, [rel stats]
    xor  ecx, ecx
.m1:
    mov  eax, LOC(rcx*4)
    lock add [rdx+rcx*4], eax
    inc  ecx
    cmp  ecx, 256+16                    ; stats + bcount, relies on them being adjacent
    jl   .m1
ENDP

; hill shading + water blend, doubles and truncating converts throughout
PROCX render_map, 0
    mov  r12, [rel img]
    xor  r13d, r13d
.z:
    xor  r14d, r14d
.x:
    mov  r15d, r13d
    imul r15d, r15d, SIZE
    add  r15d, r14d
    lea  rax, [rel px_top]
    movzx esi, byte [rax+r15]
    lea  rax, [rel px_bio]
    movzx edi, byte [rax+r15]
    lea  rax, [rel px_h]
    movzx ebx, byte [rax+r15]
    cmp  esi, B_WATER
    jne  .land
    ; water: fade from the ground colour to water colour with depth
    lea  rax, [rel px_under]
    movzx ecx, byte [rax+r15]
    mov  edx, edi
    call col_of
    mov  r8d, eax
    lea  rax, [rel px_dep]
    movzx eax, byte [rax+r15]
    cvtsi2sd xmm7, eax
    divsd xmm7, [rel d_14]
    movsd xmm6, [rel d_1]
    subsd xmm6, xmm7
    xorpd xmm7, xmm7
    maxsd xmm6, xmm7                    ; k = max(0, 1 - dep/14)
    movsd xmm8, xmm6
    mulsd xmm8, [rel d_055]
    movsd xmm9, [rel d_1]
    subsd xmm9, xmm8
    mov  r9d, 0x00BE5028
    mov  eax, 0x00465A3C                ; murkier in swamps
    cmp  edi, BIOME_SWAMP
    cmove r9d, eax
    xor  r10d, r10d
    xor  ecx, ecx
.wch:
    mov  eax, r9d
    shr  eax, cl
    movzx eax, al
    cvtsi2sd xmm10, eax
    mulsd xmm10, xmm9
    mov  eax, r8d
    shr  eax, cl
    movzx eax, al
    cvtsi2sd xmm11, eax
    mulsd xmm11, xmm6
    mulsd xmm11, [rel d_055]
    addsd xmm10, xmm11
    cvttsd2si eax, xmm10
    shl  eax, cl
    or   r10d, eax
    add  ecx, 8
    cmp  ecx, 24
    jl   .wch
    jmp  .put
.land:
    mov  ecx, esi
    mov  edx, edi
    call col_of
    mov  r8d, eax
    mov  ecx, ebx                       ; height to the left, own h on the edge
    test r14d, r14d
    jz   .hl
    lea  rax, [rel px_h]
    movzx ecx, byte [rax+r15-1]
    ; v1 temporary guard (test_worldgen_preview #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (test_worldgen_preview #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (test_worldgen_preview #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_worldgen_preview #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_worldgen_preview #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_worldgen_preview #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_worldgen_preview #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_worldgen_preview #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_worldgen_preview #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_worldgen_preview #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_worldgen_preview #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_worldgen_preview #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_worldgen_preview #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_worldgen_preview #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_worldgen_preview #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_worldgen_preview #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_worldgen_preview #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_worldgen_preview #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_worldgen_preview #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (test_worldgen_preview #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (test_worldgen_preview #56)
    xor     r11d, r11d ; clear v1 slot 56
