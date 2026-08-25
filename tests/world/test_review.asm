; worldgen regressions: no cactus with a solid block beside it, not even across
; a chunk border (it'd break on its first tick), and ore veins stay under their
; y limit (the random walk could drift ~7 up, diamonds at y 20+).
; @link src/world.asm src/worldgen.asm src/chunkmgr.asm src/noise.asm
; @link src/math.asm src/platform.asm src/gl.asm src/util.asm
; @link src/blocks.asm src/items.asm src/light.asm tests/world/wglib.asm
; @timeout 180
%include "common.inc"
%include "testlib.inc"
%include "../world/wglib.inc"

%define CN  7                           ; desert sample is cx0-7 .. cx0+7
%define CW  (2*CN+1)

section .rdata
set_nonsolid: db B_AIR, B_TALL_GRASS, B_FLOWER_RED, B_FLOWER_YELLOW, B_DEAD_BUSH
              db B_MUSHROOM_RED, B_MUSHROOM_BROWN, B_REEDS, B_SAPLING, B_TORCH, WG_SET_END
; first 4 double as the side neighbours of a cactus
dirs:         dd 1,0, -1,0, 0,1, 0,-1, 1,1, -1,-1, 1,-1, -1,1

section .bss
alignb 8
tab_nonsolid resb 256
sample       resq 1                     ; CW*CW chunks, cx-major
cx0          resd 1
cz0          resd 1

section .text

PROC test_main, 0
    mov  ecx, 12345
    call wg_set_seed
    lea  rcx, [rel tab_nonsolid]
    lea  rdx, [rel set_nonsolid]
    call wg_make_set
    call t_no_cactus_touches_solid
    call t_veins_respect_ymax
ENDP

; -1 outside the generated sample, callers skip those
PROC block_at, 0
    mov  eax, ecx
    sar  eax, 4
    sub  eax, [rel cx0]
    add  eax, CN
    cmp  eax, CW-1
    ja   .none
    mov  r9d, r8d
    sar  r9d, 4
    sub  r9d, [rel cz0]
    add  r9d, CN
    cmp  r9d, CW-1
    ja   .none
    imul eax, eax, CW
    add  eax, r9d
    imul rax, rax, CHUNK_BYTES
    add  rax, [rel sample]
    and  ecx, 15
    and  r8d, 15
    shl  edx, 8
    shl  r8d, 4
    add  edx, r8d
    add  edx, ecx
    movzx eax, byte [rax+WG_BLOCKS+rdx]
    jmp  .done
.none:
    mov  eax, -1
.done:
ENDP

PROC t_no_cactus_touches_solid, 32
    TEST "Cactus.no_cactus_touches_solid"
    ; walk out in 8 directions, 64 blocks a ring, biome fn only (no gen)
    xor  r12d, r12d
.r:
    xor  r13d, r13d
.d:
    lea  rax, [rel dirs]
    mov  esi, [rax+r13*8]
    imul esi, r12d
    mov  edi, [rax+r13*8+4]
    imul edi, r12d
    mov  ecx, esi
    mov  edx, edi
    call worldgen_biome_at
    cmp  eax, BIOME_DESERT
    je   .found
    inc  r13d
    cmp  r13d, 8
    jl   .d
    add  r12d, 64
    cmp  r12d, 4000
    jl   .r
    xor  eax, eax
    CHECK_TRUE eax, "no desert found"
    jmp  .done
.found:
    mov  eax, 1
    CHECK_TRUE eax, "no desert found"
    sar  esi, 4
    sar  edi, 4
    mov  [rel cx0], esi
    mov  [rel cz0], edi
    mov  ecx, CW*CW*CHUNK_BYTES
    call t_alloc
    mov  [rel sample], rax
    mov  rbx, rax
    mov  r12d, -CN
.gx:
    mov  r13d, -CN
.gz:
    mov  rcx, rbx
    mov  edx, [rel cx0]
    add  edx, r12d
    mov  r8d, [rel cz0]
    add  r8d, r13d
    call wg_gen
    add  rbx, CHUNK_BYTES
    inc  r13d
    cmp  r13d, CN
    jle  .gz
    inc  r12d
    cmp  r12d, CN
    jle  .gx

    mov  dword LOC(0), 0                ; cacti
    mov  dword LOC(4), 0                ; not on sand / cactus
    mov  dword LOC(8), 0                ; touching solid
    mov  rbx, [rel sample]
    xor  r15d, r15d
.ch:
    xor  r14d, r14d
.blk:
    cmp  byte [rbx+WG_BLOCKS+r14], B_CACTUS
    jne  .nblk
    inc  dword LOC(0)
    mov  eax, r15d
    xor  edx, edx
    mov  ecx, CW
    div  ecx
    add  eax, [rel cx0]
    sub  eax, CN
    shl  eax, 4
    mov  ecx, r14d
    and  ecx, 15
    add  eax, ecx
    mov  r12d, eax                      ; x
    add  edx, [rel cz0]
    sub  edx, CN
    shl  edx, 4
    mov  ecx, r14d
    shr  ecx, 4
    and  ecx, 15
    add  edx, ecx
    mov  r13d, edx                      ; z
    mov  esi, r14d
    shr  esi, 8                         ; y
    mov  ecx, r12d
    lea  edx, [esi-1]
    mov  r8d, r13d
    call block_at
    cmp  eax, B_RED_SAND
    je   .below_ok
    cmp  eax, B_SAND
    je   .below_ok
    cmp  eax, B_CACTUS
    je   .below_ok
    cmp  dword LOC(4), 0
    jne  .below_cnt
    WG_SAY3 "first cactus not on sand at", r12d, esi, r13d
.below_cnt:
    inc  dword LOC(4)
.below_ok:
    xor  edi, edi
.side:
    lea  rax, [rel dirs]
    mov  ecx, [rax+rdi*8]
    add  ecx, r12d
    mov  edx, esi
    mov  r8d, [rax+rdi*8+4]
    add  r8d, r13d
    call block_at
    cmp  eax, -1
    je   .side_ok
    lea  rcx, [rel tab_nonsolid]
    cmp  byte [rcx+rax], 0
    jne  .side_ok
    cmp  dword LOC(8), 0
    jne  .side_cnt
    mov  LOC(12), eax
    WG_SAY3 "first cactus touching a solid block at", r12d, esi, r13d
    mov  eax, LOC(12)
    WG_SAY "  ...the block id is", rax
.side_cnt:
    inc  dword LOC(8)
.side_ok:
    inc  edi
    cmp  edi, 4
    jl   .side
.nblk:
    inc  r14d
    cmp  r14d, 32768
    jl   .blk
    add  rbx, CHUNK_BYTES
    inc  r15d
    cmp  r15d, CW*CW
    jl   .ch

    CHECK_EQ32 LOC(4), 0, "every cactus stands on sand or cactus"
    CHECK_EQ32 LOC(8), 0, "no cactus touches a solid block on its sides"
    xor  eax, eax
    cmp  dword LOC(0), 0
    setg al
    CHECK_TRUE eax, "no cactus generated in the desert sample"
    mov  eax, LOC(0)
    WG_SAY3 "checked cactus blocks / around chunk:", eax, [rel cx0], [rel cz0]
.done:
ENDP

; top y of each ore over cx -12..11, cz -12..10 step 2
PROC t_veins_respect_ymax, 16
    TEST "OreDepth.veins_respect_ymax"
    call wg_chunk_new
    mov  r15, rax
    mov  dword LOC(0), 0                ; iron
    mov  dword LOC(4), 0                ; gold
    mov  dword LOC(8), 0                ; diamond
    mov  r12d, -12
.x:
    mov  r13d, -12
.z:
    mov  rcx, r15
    mov  edx, r12d
    mov  r8d, r13d
    call wg_gen
    xor  ecx, ecx
.b:
    movzx eax, byte [r15+WG_BLOCKS+rcx]
    mov  edx, ecx
    shr  edx, 8
    cmp  eax, B_IRON_ORE
    jne  .ng
    cmp  edx, LOC(0)
    jle  .nb
    mov  LOC(0), edx
    jmp  .nb
.ng:
    cmp  eax, B_GOLD_ORE
    jne  .nd
    cmp  edx, LOC(4)
    jle  .nb
    mov  LOC(4), edx
    jmp  .nb
.nd:
    cmp  eax, B_DIAMOND_ORE
    jne  .nb
    cmp  edx, LOC(8)
    jle  .nb
    mov  LOC(8), edx
.nb:
    inc  ecx
    cmp  ecx, 32768
    jl   .b
    add  r13d, 2
    cmp  r13d, 12
    jl   .z
    inc  r12d
    cmp  r12d, 12
    jl   .x
    ; all three must show up at all, else the y checks prove nothing
    xor  eax, eax
    cmp  dword LOC(0), 0
    setg al
    xor  ecx, ecx
    cmp  dword LOC(4), 0
    setg cl
    and  eax, ecx
    xor  ecx, ecx
    cmp  dword LOC(8), 0
    setg cl
    and  eax, ecx
    CHECK_TRUE eax, "iron, gold and diamond all generated"
    xor  eax, eax
    cmp  dword LOC(8), 16
    setle al
    CHECK_TRUE eax, "diamond veins stay at y <= 16"
    xor  eax, eax
    cmp  dword LOC(4), 32
    setle al
    CHECK_TRUE eax, "gold veins stay at y <= 32"
    xor  eax, eax
    cmp  dword LOC(0), 64
    setle al
    CHECK_TRUE eax, "iron veins stay at y <= 64"
    WG_SAY3 "top y of iron / gold / diamond:", LOC(0), LOC(4), LOC(8)
ENDP
