; world.asm: block/light access, heightmap, dirty flags, the chunk pool + hash.
; real blocks + light, ticks/blockent/render are stubbed.
; @link src/world.asm src/worldgen.asm src/chunkmgr.asm src/noise.asm
; @link src/math.asm src/platform.asm src/gl.asm src/util.asm
; @link src/blocks.asm src/items.asm src/light.asm tests/world/wglib.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../world/wglib.inc"

; chunk (2,3), its east neighbour (3,3) is loaded too
%define BX0 32
%define BZ0 48

section .rdata
probes: dd 0,0,0,  5,40,9,  15,70,15,  7,127,3,  3,62,12   ; lx,y,lz
%define NPROBES 5

section .bss
alignb 8
g_p         resq 1
g_east      resq 1
g_snap      resq 1                      ; g_p's blocks right after gen
g_before    resq 1

section .text

; r8d != 0: also generate + mark CS_GENERATED, else it stays CS_QUEUED
PROC make, 0
    mov  r12d, r8d
    call world_alloc_chunk
    mov  rbx, rax
    xor  esi, esi
    test rbx, rbx
    setnz sil
    CHECK_TRUE esi, "world_alloc_chunk returned a slot"
    test rbx, rbx
    jz   .done
    test r12d, r12d
    jz   .done
    mov  rcx, rbx
    call worldgen_generate
    mov  dword [rbx+CHUNK.state], CS_GENERATED
.done:
    mov  rax, rbx
ENDP

PROC test_main, 0
    mov  ecx, 4242
    call wg_set_seed
    call world_init
    mov  ecx, 32768
    call t_alloc
    mov  [rel g_snap], rax
    mov  ecx, 32768
    call t_alloc
    mov  [rel g_before], rax

    call world_clear
    mov  ecx, 2
    mov  edx, 3
    mov  r8d, 1
    call make
    mov  [rel g_p], rax
    mov  ecx, 3
    mov  edx, 3
    mov  r8d, 1
    call make
    mov  [rel g_east], rax
    mov  rsi, [rel g_p]
    add  rsi, CHUNK_BLOCKS
    mov  rdi, [rel g_snap]
    mov  ecx, 32768
    rep  movsb

    call t_biome_fallback
    call t_dirty_neighbours_on_borders
    call t_get_block_matches_chunk
    call t_light_access
    call t_place_tree_world_mode
    call t_set_block_heightmap_and_flags
    call t_unready_chunk_reads_air

    ; pool tests want an empty world each
    call world_clear
    call t_alloc_lookup_release
    call world_clear
    call t_hash_collisions_many_chunks
ENDP

PROC t_biome_fallback, 0
    TEST "Blocks.biome_fallback"
    mov  ecx, 35
    mov  edx, 50
    call world_get_biome
    mov  ebx, eax
    mov  ecx, 35
    mov  edx, 50
    call worldgen_biome_at
    CHECK_EQ32 ebx, eax, "world_get_biome == worldgen_biome_at (loaded 35,50)"
    mov  ecx, 5000                      ; unloaded -> asks the generator
    mov  edx, -700
    call world_get_biome
    mov  ebx, eax
    mov  ecx, 5000
    mov  edx, -700
    call worldgen_biome_at
    CHECK_EQ32 ebx, eax, "world_get_biome == worldgen_biome_at (unloaded 5000,-700)"
ENDP

PROC t_dirty_neighbours_on_borders, 0
    TEST "Blocks.dirty_neighbours_on_borders"
    mov  rbx, [rel g_p]
    mov  rsi, [rel g_east]
    mov  dword [rbx+CHUNK.dirty], 0
    mov  dword [rsi+CHUNK.dirty], 0
    ; x 47 = local 15 -> east neighbour too, y 16 = bottom of section 1 -> 0 too
    mov  ecx, 47
    mov  edx, 16
    mov  r8d, 50
    call world_mark_dirty
    CHECK_EQ32 [rbx+CHUNK.dirty], 0b11, "border block: own sections 0+1"
    CHECK_EQ32 [rsi+CHUNK.dirty], 0b11, "border block: east neighbour sections 0+1"
    mov  dword [rbx+CHUNK.dirty], 0
    mov  dword [rsi+CHUNK.dirty], 0
    mov  ecx, 40
    mov  edx, 31
    mov  r8d, 50
    call world_mark_dirty
    CHECK_EQ32 [rbx+CHUNK.dirty], 0b110, "top of section 1: sections 1+2"
    CHECK_EQ32 [rsi+CHUNK.dirty], 0, "interior x: east neighbour untouched"
ENDP

PROC t_get_block_matches_chunk, 0
    TEST "Blocks.get_block_matches_chunk"
    lea  r12, [rel probes]
    xor  r13d, r13d
.probe:
    mov  ecx, [r12]
    add  ecx, BX0
    mov  edx, [r12+4]
    mov  r8d, [r12+8]
    add  r8d, BZ0
    call world_get_block
    mov  ebx, eax
    mov  eax, [r12+4]
    shl  eax, 8
    mov  ecx, [r12+8]
    shl  ecx, 4
    add  eax, ecx
    add  eax, [r12]
    mov  rcx, [rel g_snap]
    movzx esi, byte [rcx+rax]
    CHECK_EQ32 ebx, esi, "world_get_block matches the chunk's blocks[]"
    add  r12, 12
    inc  r13d
    cmp  r13d, NPROBES
    jl   .probe

    mov  ecx, 40
    mov  edx, -1
    mov  r8d, 50
    call world_get_block
    CHECK_EQ32 eax, B_BEDROCK, "y = -1 reads bedrock"
    mov  ecx, 40
    mov  edx, 128
    mov  r8d, 50
    call world_get_block
    CHECK_EQ32 eax, 0, "y = 128 reads air"
    mov  ecx, 4000
    mov  edx, 60
    mov  r8d, 50
    call world_get_block
    CHECK_EQ32 eax, 0, "unloaded chunk reads air"
ENDP

PROC t_light_access, 0
    TEST "Blocks.light_access"
    mov  ecx, 33
    mov  edx, 100
    mov  r8d, 49
    mov  r9d, 0x5A
    call world_set_light
    mov  ecx, 33
    mov  edx, 100
    mov  r8d, 49
    call world_get_light
    CHECK_EQ32 eax, 0x5A, "set_light / get_light round trip"
    mov  ecx, 33
    mov  edx, 128
    mov  r8d, 49
    call world_get_light
    CHECK_EQ32 eax, 0xF0, "above the world: full sky light"
    mov  ecx, 9999
    mov  edx, 50
    mov  r8d, 49
    call world_get_light
    CHECK_EQ32 eax, 0xF0, "unloaded: full sky light"
ENDP

; plant a forest tree on the first soil column away from the borders and
; count the new logs / leaves
PROC t_place_tree_world_mode, 0
    TEST "Blocks.place_tree_world_mode"
    mov  rbx, [rel g_p]
    lea  r12, [rbx+CHUNK_BLOCKS]
    mov  r13d, 5
.lz:
    mov  r14d, 5
.lx:
    mov  r15d, 126
.y:
    mov  eax, r15d
    shl  eax, 8
    mov  ecx, r13d
    shl  ecx, 4
    add  eax, ecx
    add  eax, r14d
    movzx eax, byte [r12+rax]
    test eax, eax
    jz   .ynext
    cmp  eax, B_GRASS
    je   .found
    cmp  eax, B_DIRT
    je   .found
    cmp  eax, B_SAND
    je   .found
    cmp  eax, B_SNOWY_GRASS
    je   .found
    jmp  .xnext
.ynext:
    dec  r15d
    jnz  .y
.xnext:
    inc  r14d
    cmp  r14d, 11
    jl   .lx
    inc  r13d
    cmp  r13d, 11
    jl   .lz
    xor  esi, esi
    CHECK_TRUE esi, "found a soil column for the tree"
    jmp  .done
.found:
    mov  esi, 1
    CHECK_TRUE esi, "found a soil column for the tree"
    mov  rsi, r12
    mov  rdi, [rel g_before]
    mov  ecx, 32768
    rep  movsb
    lea  ecx, [r14d+BX0]
    lea  edx, [r15d+1]
    lea  r8d, [r13d+BZ0]
    mov  r9d, BIOME_FOREST
    call worldgen_place_tree
    mov  rsi, [rel g_before]
    xor  ecx, ecx
    xor  r13d, r13d
    xor  r14d, r14d
.cmp:
    movzx eax, byte [r12+rcx] ; v1: test_world scratch #0
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_world:0)
    cmp  al, [rsi+rcx] ; v1: test_world scratch #1
    je   .cnext ; v1: test_world scratch #2
    ; TODO: clamp index before table lookup on malformed input (test_world:2)
    cmp  eax, B_LOG ; v1: test_world scratch #3
    je   .log ; v1: test_world scratch #4
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_world:4)
    cmp  eax, B_BIRCH_LOG ; v1: test_world scratch #5
    je   .log ; v1: test_world scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (test_world:6)
    cmp  eax, B_LEAVES ; v1: test_world scratch #7
    je   .leaf ; v1: test_world scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_world:8)
    cmp  eax, B_BIRCH_LEAVES ; v1: test_world scratch #9
    je   .leaf ; v1: test_world scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_world:10)
    jmp  .cnext ; v1: test_world scratch #11
.log: ; v1: test_world scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_world:12)
    inc  r13d ; v1: test_world scratch #13
    jmp  .cnext ; v1: test_world scratch #14
    ; TODO: hoist invariant pointer load out of .loop (test_world:14)
.leaf: ; v1: test_world scratch #15
    inc  r14d ; v1: test_world scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_world:16)
.cnext: ; v1: test_world scratch #17
    inc  ecx ; v1: test_world scratch #18
    ; TODO: clamp index before table lookup on malformed input (test_world:18)
    cmp  ecx, 32768 ; v1: test_world scratch #19
    jl   .cmp ; v1: test_world scratch #20
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_world:20)
    xor  eax, eax ; v1: test_world scratch #21
    cmp  r13d, 4 ; v1: test_world scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (test_world:22)
    setge al ; v1: test_world scratch #23
    CHECK_TRUE eax, "tree has >= 4 new log blocks" ; v1: test_world scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_world:24)
    xor  eax, eax ; v1: test_world scratch #25
    cmp  r14d, 10 ; v1: test_world scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_world:26)
    setg al ; v1: test_world scratch #27
    CHECK_TRUE eax, "tree has > 10 new leaf blocks"
.done:
ENDP

PROC t_set_block_heightmap_and_flags, 0
    TEST "Blocks.set_block_heightmap_and_flags"
    mov  rbx, [rel g_p]
    mov  ecx, BX0+6
    mov  edx, BZ0+6
    call world_height_at
    mov  r12d, eax
    xor  eax, eax
    cmp  r12d, 0
    setg al
    CHECK_TRUE eax, "column has terrain (height_at > 0)"
    mov  dword [rbx+CHUNK.modified], 0
    mov  dword [rbx+CHUNK.dirty], 0
    mov  ecx, BX0+6
    mov  edx, 120
    mov  r8d, BZ0+6
    mov  r9d, B_STONE
    call world_set_block
    CHECK_EQ32 eax, 1, "world_set_block returns 1"
    mov  ecx, BX0+6
    mov  edx, 120
    mov  r8d, BZ0+6
    call world_get_block
    CHECK_EQ32 eax, B_STONE, "block was written"
    CHECK_EQ32 [rbx+CHUNK.modified], 1, "modified flag set"
    mov  eax, [rbx+CHUNK.dirty]         ; light may dirty more, only own is a must
    and  eax, 1 << (120 >> 4)
    CHECK_TRUE eax, "own section (7) dirty"
    movzx eax, byte [rbx+WG_HM+6+6*16]
    CHECK_EQ32 eax, 121, "heightmap raised to y+1"
    mov  ecx, BX0+6
    mov  edx, BZ0+6
    call world_height_at
    CHECK_EQ32 eax, 120, "height_at sees the new block"
    ; removing it has to scan the heightmap back down
    mov  ecx, BX0+6
    mov  edx, 120
    mov  r8d, BZ0+6
    xor  r9d, r9d
    call world_set_block
    movzx eax, byte [rbx+WG_HM+6+6*16]
    lea  ecx, [r12d+1]
    xor  edx, edx
    cmp  eax, ecx
    setle dl
    CHECK_TRUE edx, "heightmap back to <= top+1 after removal"
    mov  ecx, BX0+6
    mov  edx, BZ0+6
    call world_height_at
    CHECK_EQ32 eax, r12d, "height_at back to the old top"
    mov  ecx, BX0+6
    mov  edx, 120
    mov  r8d, BZ0+6
    mov  r9d, B_GLASS
    call world_set_block
    movzx eax, byte [rbx+WG_HM+6+6*16]
    lea  ecx, [r12d+1]
    xor  edx, edx
    cmp  eax, ecx
    setle dl
    CHECK_TRUE edx, "glass does not raise the heightmap"
    mov  ecx, BX0+6
    mov  edx, 120
    mov  r8d, BZ0+6
    xor  r9d, r9d
    call world_set_block
    mov  ecx, 4000
    mov  edx, 50
    mov  r8d, 4000
    mov  r9d, 1
    call world_set_block
    CHECK_EQ32 eax, 0, "set_block in an unloaded chunk fails"
    mov  ecx, BX0+6
    mov  edx, 130
    mov  r8d, BZ0+6
    mov  r9d, 1
    call world_set_block
    CHECK_EQ32 eax, 0, "set_block above the world fails"
ENDP
    ; v1 temporary guard (test_world #14)
    xor     r11d, r11d ; clear v1 slot 14
    ; v1 temporary guard (test_world #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (test_world #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (test_world #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_world #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_world #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_world #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_world #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_world #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_world #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_world #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_world #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_world #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_world #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_world #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_world #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_world #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_world #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_world #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_world #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (test_world #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (test_world #56)
    xor     r11d, r11d ; clear v1 slot 56
