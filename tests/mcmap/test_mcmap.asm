; java 26.1 id mapping: state ids straight out of blocks.json, round trips, the
; full state sweep, items, biomes, and the known packs / registry / tags stream
; through a fake writer, both with full nbt and for a client that has the core pack
; @link src/mcmap.asm src/mcdata.asm
; @timeout 60
%define IMPL_MCPROTO            ; the pw_* below stand in for mcproto
%include "common.inc"
%include "net.inc"
%include "mcpackets.inc"
%include "testlib.inc"

%define MAXPKT 64

section .rdata
kp_want:    db 1, 9, "minecraft", 4, "core", 4, "26.1"
kp_want_len equ $ - kp_want
s_biomereg: db "minecraft:worldgen/biome", 0
s_plains:   db "minecraft:plains", 0
s_snowy:    db "minecraft:snowy_plains", 0
s_fluid:    db "minecraft:fluid", 0
s_water:    db "minecraft:water", 0
; update_tags spot checks: registry i (1 based) <-> tag i
tg_reg_list: db "minecraft:item", 0, "minecraft:enchantment", 0, "minecraft:dialog", 0
             db "minecraft:timeline", 0, "minecraft:fluid", 0, 0
tg_tag_list: db "minecraft:enchantable/head_armor", 0, "minecraft:exclusive_set/armor", 0
             db "minecraft:pause_screen_additions", 0, "minecraft:in_overworld", 0
             db "minecraft:water", 0, 0
abi_noargs: dq 0, 0, 0, 0, 0, 0,0,0,0,0,0,0,0
abi_state:  dq 5330, 0, 0, 0, 0, 0,0,0,0,0,0,0,0

section .bss
alignb 16
cur_buf:    resb 524288
log_buf:    resb 1048576
cur_len:    resd 1
log_len:    resd 1
pkt_count:  resd 1
pkt_ids:    resd MAXPKT
pkt_off:    resd MAXPKT
pkt_len:    resd MAXPKT
cursor:     resq 1
nbt_lim:    resq 1                  ; end of the packet being read
tg_regs:    resd 1                  ; tags_scan results
tg_total:   resd 1
tg_end:     resd 1
tg_found:   resd 5                  ; id count + 1, 0 = not there
ent_full:   resd 1                  ; registry entries seen with full nbt

section .text

; fake writer: payload into cur_buf, pw_send files it into log_buf
PROC pw_begin
    mov  dword [rel cur_len], 0
    mov  eax, [rel pkt_count]
    cmp  eax, MAXPKT
    jae  .done
    lea  rdx, [rel pkt_ids]
    mov  [rdx+rax*4], ecx
.done:
ENDP

PROC pw_varint
    lea  rdi, [rel cur_buf]
    mov  eax, [rel cur_len]
    add  rdi, rax
    mov  eax, ecx
.l: mov  edx, eax
    and  edx, 0x7F
    shr  eax, 7
    jz   .last
    or   edx, 0x80
    mov  [rdi], dl
    inc  rdi
    inc  dword [rel cur_len]
    jmp  .l
.last:
    mov  [rdi], dl
    inc  dword [rel cur_len]
ENDP

PROC pw_bool
    lea  rdi, [rel cur_buf]
    mov  eax, [rel cur_len]
    mov  [rdi+rax], cl
    inc  dword [rel cur_len]
ENDP

PROC pw_bytes
    lea  rdi, [rel cur_buf]
    mov  eax, [rel cur_len]
    add  rdi, rax
    mov  rsi, rcx
    mov  ecx, edx
    add  [rel cur_len], edx
    rep  movsb
ENDP

PROC pw_string
    mov  r12, rcx
    xor  ebx, ebx
.len:
    cmp  byte [r12+rbx], 0
    je   .got
    inc  ebx
    jmp  .len
.got:
    mov  ecx, ebx
    call pw_varint
    lea  rdi, [rel cur_buf]
    mov  eax, [rel cur_len]
    add  rdi, rax
    mov  rsi, r12
    mov  ecx, ebx
    rep  movsb
    add  [rel cur_len], ebx
ENDP

PROC pw_send
    mov  eax, [rel pkt_count]
    inc  dword [rel pkt_count]
    cmp  eax, MAXPKT
    jae  .done
    mov  ebx, [rel log_len]
    mov  ecx, [rel cur_len]
    lea  rdx, [rel pkt_off]
    mov  [rdx+rax*4], ebx
    lea  rdx, [rel pkt_len]
    mov  [rdx+rax*4], ecx
    lea  rdi, [rel log_buf]
    add  rdi, rbx
    lea  rsi, [rel cur_buf]
    rep  movsb
    mov  ecx, [rel cur_len]
    add  [rel log_len], ecx
.done:
ENDP

; reading back. cursor is a global qword
; -> eax varint at cursor, cursor moves on
align 16
rd_varint:
    mov  r8, [rel cursor]
    xor  eax, eax
    xor  ecx, ecx
.l: movzx r9d, byte [r8]
    inc  r8
    mov  r10d, r9d
    and  r10d, 0x7F
    shl  r10d, cl
    or   eax, r10d
    add  ecx, 7
    test r9d, 0x80
    jnz  .l
    mov  [rel cursor], r8
    ret

; rcx zstr -> eax 1 if the string at cursor equals it. cursor moves past it
; registry entry tail at the cursor: has-data byte (must be 1) + a nameless
; network nbt root. -> eax 0 when it parses inside the packet
PROC rd_entry_nbt
    mov  rax, [rel cursor]
    cmp  byte [rax], 1
    jne  .bad
    movzx ecx, byte [rax+1]
    cmp  ecx, 10
    jne  .bad                               ; roots are compounds
    add  rax, 2
    mov  [rel cursor], rax
    call nbt_skip_pl
    jmp  .done
.bad:
    mov  eax, 1
.done:
ENDP

PROC nbt_skip_pl
    mov  ebx, ecx
    mov  rsi, [rel cursor]
    cmp  ebx, 1
    je   .b1
    cmp  ebx, 2
    je   .b2
    cmp  ebx, 3
    je   .b4
    cmp  ebx, 5
    je   .b4
    cmp  ebx, 4
    je   .b8
    cmp  ebx, 6
    je   .b8
    cmp  ebx, 8
    je   .str
    cmp  ebx, 7
    je   .arr1
    cmp  ebx, 11
    je   .arr4
    cmp  ebx, 12
    je   .arr8
    cmp  ebx, 9
    je   .list
    cmp  ebx, 10
    je   .comp
    jmp  .bad
.b1: inc  rsi
    jmp  .ok
.b2: add  rsi, 2
    jmp  .ok
.b4: add  rsi, 4
    jmp  .ok
.b8: add  rsi, 8
    jmp  .ok
.str:
    movzx eax, word [rsi]
    rol  ax, 8
    lea  rsi, [rsi+rax+2]
    jmp  .ok
.arr1:
    mov  edx, 1
    jmp  .arr
.arr4:
    mov  edx, 4
    jmp  .arr
.arr8:
    mov  edx, 8
.arr:
    mov  eax, [rsi]
    bswap eax
    cmp  eax, 0x100000
    ja   .bad
    imul eax, edx
    lea  rsi, [rsi+rax+4]
    jmp  .ok
.list:
    movzx edi, byte [rsi]
    mov  r12d, [rsi+1]
    bswap r12d
    cmp  r12d, 0x100000
    ja   .bad
    add  rsi, 5
    mov  [rel cursor], rsi
.li:
    test r12d, r12d
    jz   .chk
    mov  ecx, edi
    call nbt_skip_pl
    test eax, eax
    jnz  .bad
    dec  r12d
    jmp  .li
.comp:
    cmp  rsi, [rel nbt_lim]
    jae  .bad
    movzx edi, byte [rsi]
    inc  rsi
    test edi, edi
    jz   .ok
    movzx eax, word [rsi]
    rol  ax, 8
    lea  rsi, [rsi+rax+2]
    mov  [rel cursor], rsi
    mov  ecx, edi
    call nbt_skip_pl
    test eax, eax
    jnz  .bad
    mov  rsi, [rel cursor]
    jmp  .comp
.ok:
    mov  [rel cursor], rsi
.chk:
    mov  rax, [rel cursor]
    cmp  rax, [rel nbt_lim]
    ja   .bad
    xor  eax, eax
    jmp  .done
.bad:
    mov  eax, 1
.done:
ENDP

PROC rd_str_eq
    mov  rdi, rcx
    call rd_varint
    mov  r8, [rel cursor]
    add  [rel cursor], rax
    xor  r9d, r9d
    xor  ecx, ecx
.c: cmp  ecx, eax
    jae  .end
    mov  dl, [rdi+rcx]
    cmp  dl, [r8+rcx]
    jne  .done
    inc  ecx
    jmp  .c
.end:
    cmp  byte [rdi+rcx], 0
    jne  .done
    mov  r9d, 1
.done:
    mov  eax, r9d
ENDP

; cursor past one string
align 16
rd_skip_str:
    sub  rsp, 8
    call rd_varint
    add  [rel cursor], rax
    add  rsp, 8
    ret

; rcx list of zstrs ending in an empty one -> eax 1 based index of the one the
; string at the cursor equals, 0 = none. cursor moves past it either way
PROC rd_which
    mov  rdi, rcx
    mov  r12, [rel cursor]
    mov  r13d, 1
.l: cmp  byte [rdi], 0
    je   .none
    mov  [rel cursor], r12
    mov  rcx, rdi
    call rd_str_eq
    test eax, eax
    jnz  .hit
.skip:
    inc  rdi
    cmp  byte [rdi-1], 0
    jne  .skip
    inc  r13d
    jmp  .l
.hit:
    mov  eax, r13d
    jmp  .done
.none:
    mov  [rel cursor], r12
    call rd_skip_str
    xor  eax, eax
.done:
ENDP

; ecx packet index of an update_tags -> eax registry count. walks all of it:
; tg_total tags, tg_found[] for the spot checks, tg_end 1 = used up exactly
PROC tags_scan
    call rd_open
    mov  r15, rax
    mov  dword [rel tg_total], 0
    lea  rdi, [rel tg_found]
    xor  eax, eax
    mov  ecx, 5
    rep  stosd
    call rd_varint
    mov  [rel tg_regs], eax
    mov  r12d, eax
.reg:
    test r12d, r12d
    jz   .end
    cmp  [rel cursor], r15
    jae  .end
    lea  rcx, [rel tg_reg_list]
    call rd_which
    mov  r13d, eax
    call rd_varint
    mov  r14d, eax
    add  [rel tg_total], eax
.tag:
    test r14d, r14d
    jz   .reg_next
    cmp  [rel cursor], r15
    jae  .end
    lea  rcx, [rel tg_tag_list]
    call rd_which
    mov  esi, eax
    call rd_varint
    mov  ebx, eax
    test r13d, r13d
    jz   .ids
    cmp  esi, r13d
    jne  .ids
    lea  rcx, [rel tg_found]
    lea  edx, [rbx+1]
    mov  [rcx+rsi*4-4], edx
.ids:
    test ebx, ebx
    jz   .tag_next
    call rd_varint
    dec  ebx
    jmp  .ids
.tag_next:
    dec  r14d
    jmp  .tag
.reg_next:
    dec  r12d
    jmp  .reg
.end:
    xor  eax, eax
    cmp  [rel cursor], r15
    sete al
    mov  [rel tg_end], eax
    mov  eax, [rel tg_regs]
ENDP

; the update_tags checks, %1 = its packet index
%macro TAGS_OK 1.nolist
    mov  ecx, %1
    call tags_scan
    mov  ebx, eax
    CHECK_EQ32 ebx, MC_TAG_REGISTRY_COUNT, "tag registries"
    mov  ebx, [rel tg_total]
    CHECK_EQ32 ebx, MC_TAG_COUNT, "tags in all registries"
    mov  ebx, [rel tg_end]
    CHECK_EQ32 ebx, 1, "tags packet fully used"
    lea  r12, [rel tg_found]
    mov  ebx, [r12]
    CHECK_EQ32 ebx, 8+1, "item #enchantable/head_armor, 8 items"
    lea  r12, [rel tg_found]
    mov  ebx, [r12+4]
    CHECK_EQ32 ebx, 4+1, "enchantment #exclusive_set/armor, 4 entries"
    lea  r12, [rel tg_found]
    mov  ebx, [r12+8]
    CHECK_EQ32 ebx, 0+1, "dialog #pause_screen_additions there, empty"
    lea  r12, [rel tg_found]
    mov  ebx, [r12+12]
    CHECK_EQ32 ebx, 4+1, "timeline #in_overworld, 4 entries"
    lea  r12, [rel tg_found]
    mov  ebx, [r12+16]
    CHECK_EQ32 ebx, 2+1, "fluid #water, water + flowing_water"
%endmacro

; ecx packet index -> cursor at its payload, rax = end
align 16
rd_open:
    lea  rdx, [rel pkt_off]
    mov  eax, [rdx+rcx*4]
    lea  r8, [rel log_buf]
    add  rax, r8
    mov  [rel cursor], rax
    lea  rdx, [rel pkt_len]
    mov  edx, [rdx+rcx*4]
    add  rax, rdx
    ret

%macro STATE_IS 2.nolist          ; java state, our block
    %defstr %%a %1
    %strcat %%m "from_state(", %%a, ")"
    mov  ecx, %1
    call mcmap_from_state
    mov  ebx, eax
    CHECK_EQ32 ebx, %2, %%m
%endmacro
%macro FWD_IS 2.nolist            ; our block, java state
    %defstr %%a %1
    %strcat %%m "block_state(", %%a, ")"
    mov  ecx, %1
    call mcmap_block_state
    mov  ebx, eax
    CHECK_EQ32 ebx, %2, %%m
%endmacro

PROC test_main, 64
    TEST "our block -> java state"
    FWD_IS B_AIR, 0
    FWD_IS B_STONE, 1
    FWD_IS B_GRASS, 9                       ; grass_block[snowy=false]
    FWD_IS B_SNOWY_GRASS, 8
    FWD_IS B_LOG, 137                       ; oak_log[axis=y]
    FWD_IS B_BIRCH_LOG, 143
    FWD_IS B_LEAVES, 255                    ; oak_leaves[distance=1,persistent=false,waterlogged=false]
    FWD_IS B_PINE_LEAVES, 283
    FWD_IS B_WATER, 86
    FWD_IS B_WATER+3, 89                    ; water[level=3]
    FWD_IS B_LAVA, 102
    FWD_IS B_LAVA+1, 104                    ; lava[level=2]
    FWD_IS B_LAVA+3, 108
    FWD_IS B_FURNACE, 5330                  ; furnace[facing=south,lit=false]
    FWD_IS B_FURNACE_LIT, 5329
    FWD_IS B_CHEST, 3994                    ; chest[facing=south,type=single,waterlogged=false]
    FWD_IS B_PUMPKIN, 7020                  ; carved_pumpkin[facing=south]
    FWD_IS B_LANTERN, 20840
    FWD_IS B_REEDS, 6947
    FWD_IS B_SAPLING, 29
    FWD_IS B_MOSS, 27862
    FWD_IS B_GLOWCRYSTAL, 7016
    FWD_IS B_TORCH, 3370
    FWD_IS B_CRAFT_TABLE, 5310
    FWD_IS B_TNT, 2342
    FWD_IS B_TALL_GRASS, 2248
    FWD_IS B_FLOWER_RED, 2324
    FWD_IS B_WOOL, 2293
    FWD_IS B_WOOL+14, 2307
    FWD_IS B_WOOL_LAST, 2308
    FWD_IS B_FURNACE_W, 5332                ; furnace[facing=west,lit=false]
    FWD_IS B_FURNACE_LIT_N, 5327
    FWD_IS B_CHEST_E, 4006
    FWD_IS B_CRAFT_TABLE_N, 5310            ; java's doesn't turn
    FWD_IS B_PUMPKIN_W, 7021
    FWD_IS B_LEAVES_P, 253                  ; oak_leaves[persistent=true]
    FWD_IS B_PINE_LEAVES_P, 281
    FWD_IS B_BED, 2161                      ; red_bed[facing=south,part=head]
    FWD_IS B_BED+3, 2169
    FWD_IS B_RED_SAND, 123
    FWD_IS B_TERRACOTTA, 12912
    FWD_IS B_TERRACOTTA+2, 11448            ; yellow_terracotta
    FWD_IS B_TERRACOTTA_LAST, 11444         ; white_terracotta
    FWD_IS 92, 0                            ; unused id
    FWD_IS 125, 0
    FWD_IS 0x1234, 0                        ; junk

    TEST "java state -> our block"
    STATE_IS 0, B_AIR
    STATE_IS 1, B_STONE
    STATE_IS 8, B_SNOWY_GRASS
    STATE_IS 19, B_PLANKS                   ; acacia_planks
    STATE_IS 15044, B_WOOL+14               ; red_concrete
    STATE_IS 7754, B_STONE_BRICKS
    STATE_IS 3907, B_PLANKS                 ; oak_stairs first..last
    STATE_IS 3986, B_PLANKS
    STATE_IS 27923, B_STONE                 ; deepslate
    STATE_IS 12533, B_GLASS                 ; barrier
    STATE_IS 13247, B_SANDSTONE             ; red_sandstone
    STATE_IS 10304, B_COBBLE                ; cobblestone_wall
    STATE_IS 15163, B_TALL_GRASS            ; fire_coral
    STATE_IS 3375, B_AIR                    ; fire
    STATE_IS 5730, B_AIR                    ; rail
    STATE_IS 20762, B_FURNACE_LIT_N         ; blast_furnace[facing=north,lit=true]
    STATE_IS 20763, B_FURNACE_N
    STATE_IS 5327, B_FURNACE_LIT_N          ; furnace north lit
    STATE_IS 5330, B_FURNACE
    STATE_IS 7023, B_PUMPKIN_N              ; jack_o_lantern north
    STATE_IS 7024, B_PUMPKIN
    STATE_IS 9576, B_CHEST_N                ; ender_chest
    STATE_IS 1934, B_BED+2                  ; white_bed[facing=north,part=foot]
    STATE_IS 253, B_LEAVES_P
    STATE_IS 255, B_LEAVES
    STATE_IS 123, B_RED_SAND
    STATE_IS 11452, B_TERRACOTTA            ; light_gray_terracotta
    STATE_IS 11445, B_TERRACOTTA+1          ; orange
    STATE_IS 15010, B_WOOL+11               ; blue_glazed_terracotta stays wool
    STATE_IS 15062, B_WATER                 ; kelp
    STATE_IS 95, B_WATER_FLOW               ; water[level=9], falling
    STATE_IS 101, B_WATER_FLOW
    STATE_IS 103, B_LAVA_FLOW               ; lava[level=1]
    STATE_IS 107, B_LAVA_LAST               ; lava[level=5]
    STATE_IS 5352, B_AIR                    ; oak_sign
    STATE_IS MC_STATE_COUNT, B_AIR
    STATE_IS -1, B_AIR

    TEST "round trip every block id" ; v1: test_mcmap scratch #0
    ; TODO: hoist invariant pointer load out of .loop (test_mcmap:0)
    xor  esi, esi ; v1: test_mcmap scratch #1
    xor  r12d, r12d ; v1: test_mcmap scratch #2
    ; TODO: clamp index before table lookup on malformed input (test_mcmap:2)
    mov  r13d, -1 ; v1: test_mcmap scratch #3
.rt: ; v1: test_mcmap scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_mcmap:4)
    cmp  esi, B_FARMLAND ; v1: test_mcmap scratch #5
    jbe  .rt_do ; v1: test_mcmap scratch #6
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_mcmap:6)
    cmp  esi, B_WATER ; v1: test_mcmap scratch #7
    jb   .rt_next ; v1: test_mcmap scratch #8
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_mcmap:8)
    cmp  esi, B_LAVA_LAST ; v1: test_mcmap scratch #9
    jbe  .rt_do ; v1: test_mcmap scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_mcmap:10)
    cmp  esi, B_DIR_FIRST ; v1: test_mcmap scratch #11
    jb   .rt_next ; v1: test_mcmap scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (test_mcmap:12)
    cmp  esi, B_TERRACOTTA_LAST ; v1: test_mcmap scratch #13
    ja   .rt_next ; v1: test_mcmap scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_mcmap:14)
.rt_do: ; v1: test_mcmap scratch #15
    mov  ecx, esi ; v1: test_mcmap scratch #16
    ; TODO: hoist invariant pointer load out of .loop (test_mcmap:16)
    call mcmap_block_state ; v1: test_mcmap scratch #17
    mov  ecx, eax ; v1: test_mcmap scratch #18
    ; TODO: clamp index before table lookup on malformed input (test_mcmap:18)
    call mcmap_from_state ; v1: test_mcmap scratch #19
    cmp  eax, esi ; v1: test_mcmap scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_mcmap:20)
    je   .rt_next ; v1: test_mcmap scratch #21
    lea  ecx, [rsi-B_CRAFT_TABLE_W] ; v1: test_mcmap scratch #22
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_mcmap:22)
    cmp  ecx, B_CRAFT_TABLE_E-B_CRAFT_TABLE_W ; v1: test_mcmap scratch #23
    ja   .rt_bad ; v1: test_mcmap scratch #24
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_mcmap:24)
    cmp  eax, B_CRAFT_TABLE ; v1: test_mcmap scratch #25
    je   .rt_next ; v1: test_mcmap scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_mcmap:26)
.rt_bad: ; v1: test_mcmap scratch #27
    inc  r12d ; v1: test_mcmap scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (test_mcmap:28)
    cmp  r13d, -1 ; v1: test_mcmap scratch #29
    jne  .rt_next ; v1: test_mcmap scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_mcmap:30)
    mov  r13d, esi ; v1: test_mcmap scratch #31
.rt_next: ; v1: test_mcmap scratch #32
    ; TODO: hoist invariant pointer load out of .loop (test_mcmap:32)
    inc  esi ; v1: test_mcmap scratch #33
    cmp  esi, BLOCK_COUNT ; v1: test_mcmap scratch #34
    ; TODO: clamp index before table lookup on malformed input (test_mcmap:34)
    jb   .rt ; v1: test_mcmap scratch #35
    CHECK_EQ32 r12d, 0, "from_state(block_state(b)) == b" ; v1: test_mcmap scratch #36
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_mcmap:36)
    CHECK_EQ32 r13d, -1, "first id that didn't round trip" ; v1: test_mcmap scratch #37

    TEST "every java state lands on a real block" ; v1: test_mcmap scratch #39
    xor  esi, esi ; v1: test_mcmap scratch #40
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_mcmap:40)
    xor  r12d, r12d ; v1: test_mcmap scratch #41
    mov  r13d, -1
.sw:
    mov  ecx, esi
    call mcmap_from_state
    cmp  eax, B_FARMLAND
    jbe  .sw_next
    cmp  eax, B_WATER
    jb   .sw_bad
    cmp  eax, B_LAVA_LAST
    jbe  .sw_next
    cmp  eax, B_DIR_FIRST
    jb   .sw_bad
    cmp  eax, B_TERRACOTTA_LAST
    jbe  .sw_next
.sw_bad:
    inc  r12d
    cmp  r13d, -1
    jne  .sw_next
    mov  r13d, esi
.sw_next:
    inc  esi
    cmp  esi, MC_STATE_COUNT
    jb   .sw
    CHECK_EQ32 r12d, 0, "states mapping to unused ids"
    CHECK_EQ32 r13d, -1, "first such state"

    TEST "items"
    mov  ecx, B_STONE
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 1, "stone item"
    mov  ecx, B_WATER+3
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, MCI_WATER_BUCKET, "flowing water -> water_bucket"
    mov  ecx, B_LOG
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 134, "oak_log item"
    mov  ecx, B_FURNACE_LIT
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 335, "lit furnace -> furnace item"
    mov  ecx, B_SNOWY_GRASS
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 27, "snowy grass -> grass_block item"
    mov  ecx, I_STICK
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 947, "stick"
    mov  ecx, I_PICK_DIAMOND
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 939, "diamond_pickaxe"
    mov  ecx, I_FLINT_STEEL
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 892, "flint_and_steel"
    xor  ecx, ecx
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 0, "air"
    mov  ecx, B_FURNACE_LIT_E
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 335, "turned lit furnace -> furnace item"
    mov  ecx, B_BED+1
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 1101, "bed -> red_bed"
    mov  ecx, B_LEAVES_P
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 182, "placed leaves -> oak_leaves"
    mov  ecx, B_TERRACOTTA+1
    call mcmap_block_to_item
    mov  ebx, eax
    CHECK_EQ32 ebx, 488, "orange_terracotta"

    ; v1 temporary guard (test_mcmap #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_mcmap #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_mcmap #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_mcmap #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_mcmap #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_mcmap #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_mcmap #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_mcmap #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_mcmap #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_mcmap #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_mcmap #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_mcmap #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_mcmap #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_mcmap #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_mcmap #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_mcmap #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_mcmap #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (test_mcmap #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (test_mcmap #56)
    xor     r11d, r11d ; clear v1 slot 56
