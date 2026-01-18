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

    TEST "round trip every block id"
    xor  esi, esi                           ; id
    xor  r12d, r12d                         ; mismatches
    mov  r13d, -1                           ; first bad id
.rt:
    cmp  esi, B_FARMLAND
    jbe  .rt_do
    cmp  esi, B_WATER
    jb   .rt_next
    cmp  esi, B_LAVA_LAST
    jbe  .rt_do
    cmp  esi, B_DIR_FIRST
    jb   .rt_next
    cmp  esi, B_TERRACOTTA_LAST
    ja   .rt_next
.rt_do:
    mov  ecx, esi
    call mcmap_block_state
    mov  ecx, eax
    call mcmap_from_state
    cmp  eax, esi
    je   .rt_next
    lea  ecx, [rsi-B_CRAFT_TABLE_W]          ; java's table can't turn
    cmp  ecx, B_CRAFT_TABLE_E-B_CRAFT_TABLE_W
    ja   .rt_bad
    cmp  eax, B_CRAFT_TABLE
    je   .rt_next
.rt_bad:
    inc  r12d
    cmp  r13d, -1
    jne  .rt_next
    mov  r13d, esi
.rt_next:
    inc  esi
    cmp  esi, BLOCK_COUNT
    jb   .rt
    CHECK_EQ32 r12d, 0, "from_state(block_state(b)) == b"
    CHECK_EQ32 r13d, -1, "first id that didn't round trip"

    TEST "every java state lands on a real block"
    xor  esi, esi
    xor  r12d, r12d
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

    mov  ecx, 1087
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, B_BED, "any bed places our bed, unturned"
    mov  ecx, 332
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, B_CHEST, "chest item places the base chest"
    mov  ecx, 182
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, B_LEAVES, "leaves item -> natural id, ticks makes it placed"
    mov  ecx, 62
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, B_RED_SAND, "red_sand"

    mov  ecx, 1
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, B_STONE, "stone places stone"
    mov  ecx, MCI_WATER_BUCKET
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, B_WATER, "water_bucket"
    mov  ecx, MCI_LAVA_BUCKET
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, B_LAVA, "lava_bucket"
    mov  ecx, 947
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, 0, "stick places nothing"
    mov  ecx, 953
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, 0, "wheat places nothing"
    mov  ecx, 258
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, 0, "kelp doesn't pour water"
    mov  ecx, 629
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, B_WOOL+14, "red_concrete"
    mov  ecx, 442
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, B_PLANKS, "oak_stairs"
    mov  ecx, 335
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, B_FURNACE, "furnace"
    mov  ecx, MC_ITEM_COUNT
    call mcmap_item_to_block
    mov  ebx, eax
    CHECK_EQ32 ebx, 0, "out of range item"

    TEST "biomes"
    mov  ecx, BIOME_PLAINS
    call mcmap_biome
    mov  ebx, eax
    CHECK_EQ32 ebx, MCB_PLAINS, "plains"
    mov  ecx, BIOME_TUNDRA
    call mcmap_biome
    mov  ebx, eax
    CHECK_EQ32 ebx, MCB_SNOWY_PLAINS, "tundra"
    mov  ecx, BIOME_MOUNTAINS
    call mcmap_biome
    mov  ebx, eax
    CHECK_EQ32 ebx, MCB_WINDSWEPT_HILLS, "mountains"
    mov  ecx, 99
    call mcmap_biome
    mov  ebx, eax
    CHECK_EQ32 ebx, MCB_PLAINS, "junk biome"

    TEST "abi"
    lea  rcx, [rel mcmap_from_state]
    lea  rdx, [rel abi_state]
    call t_abi_call
    mov  ebx, ecx
    mov  esi, eax
    CHECK_EQ32 ebx, 0, "from_state preserves nonvolatiles"
    CHECK_EQ32 esi, B_FURNACE, "from_state via abi call"
    lea  rcx, [rel mcmap_send_registries]
    lea  rdx, [rel abi_noargs]
    call t_abi_call
    mov  ebx, ecx
    CHECK_EQ32 ebx, 0, "send_registries preserves nonvolatiles"

    TEST "known packs"
    mov  dword [rel pkt_count], 0
    mov  dword [rel log_len], 0
    xor  ecx, ecx
    call mcmap_send_known_packs
    mov  ebx, [rel pkt_count]
    CHECK_EQ32 ebx, 1, "one packet"
    mov  ebx, [rel pkt_ids]
    CHECK_EQ32 ebx, MCP_CONFIGURATION_S2C_SELECT_KNOWN_PACKS, "select_known_packs"
    xor  ecx, ecx
    call rd_open
    mov  rbx, [rel cursor]
    lea  rsi, [rel kp_want]
    CHECK_MEM rbx, rsi, kp_want_len, "known packs body"
    lea  rdx, [rel pkt_len]
    mov  ebx, [rdx]
    CHECK_EQ32 ebx, kp_want_len, "known packs length"

    TEST "config stream, full nbt"
    mov  dword [rel pkt_count], 0
    mov  dword [rel log_len], 0
    xor  ecx, ecx
    xor  edx, edx
    call mcmap_send_registries
    mov  ebx, [rel pkt_count]
    CHECK_EQ32 ebx, MC_REGISTRY_COUNT+1, "packets sent"
    lea  r12, [rel pkt_ids]
    mov  ebx, [r12+MC_REGISTRY_COUNT*4]
    CHECK_EQ32 ebx, MCP_CONFIGURATION_S2C_TAGS, "tags last"
    lea  r12, [rel pkt_ids]
    xor  esi, esi
    xor  edi, edi
.ids:
    cmp  dword [r12+rdi*4], MCP_CONFIGURATION_S2C_REGISTRY_DATA
    je   .ids_ok
    inc  esi
.ids_ok:
    inc  edi
    cmp  edi, MC_REGISTRY_COUNT
    jb   .ids
    CHECK_EQ32 esi, 0, "registry_data before it"

    ; biome registry: plains has to sit where MCB_PLAINS says
    xor  ecx, ecx
    call rd_open
    mov  r15, rax
    lea  rcx, [rel s_biomereg]
    call rd_str_eq
    mov  ebx, eax
    CHECK_EQ32 ebx, 1, "first registry is worldgen/biome"
    call rd_varint
    mov  r12d, eax
    CHECK_EQ32 r12d, MC_BIOME_COUNT, "biome count"
    xor  r13d, r13d                         ; index
    mov  r14d, -1                           ; plains at
    mov  esi, -1                            ; snowy_plains at
    mov  [rel nbt_lim], r15
    mov  dword LOC(0), 0                    ; entries whose nbt doesn't parse
.bio:
    cmp  r13d, r12d
    jae  .bio_done
    mov  rdi, [rel cursor]
    lea  rcx, [rel s_plains]
    call rd_str_eq
    test eax, eax
    jz   .bio_2
    mov  r14d, r13d
.bio_2:
    mov  [rel cursor], rdi
    lea  rcx, [rel s_snowy]
    call rd_str_eq
    test eax, eax
    jz   .bio_3
    mov  esi, r13d
.bio_3:
    call rd_entry_nbt
    add  LOC(0), eax
    inc  r13d
    jmp  .bio
.bio_done:
    mov  ebx, LOC(0)
    CHECK_EQ32 ebx, 0, "biome entries with bad nbt"
    CHECK_EQ32 r14d, MCB_PLAINS, "plains index"
    CHECK_EQ32 esi, MCB_SNOWY_PLAINS, "snowy_plains index"
    mov  rbx, [rel cursor]
    CHECK_EQ rbx, r15, "biome packet fully used"

    ; every registry_data parses exactly, every entry carries its nbt
    xor  r12d, r12d
    xor  r13d, r13d                         ; bad packets
    mov  dword [rel ent_full], 0
.rp:
    mov  ecx, r12d
    call rd_open
    mov  r15, rax
    mov  [rel nbt_lim], r15
    call rd_skip_str
    call rd_varint
    mov  r14d, eax
    add  [rel ent_full], eax
    test r14d, r14d
    jz   .rp_bad
.rp_ent:
    test r14d, r14d
    jz   .rp_end
    call rd_skip_str
    call rd_entry_nbt
    test eax, eax
    jnz  .rp_bad
    dec  r14d
    jmp  .rp_ent
.rp_end:
    cmp  [rel cursor], r15
    je   .rp_next
.rp_bad:
    inc  r13d
.rp_next:
    inc  r12d
    cmp  r12d, MC_REGISTRY_COUNT
    jb   .rp
    CHECK_EQ32 r13d, 0, "registry packets that don't parse"
    TAGS_OK MC_REGISTRY_COUNT

    TEST "config stream, client has the core pack"
    mov  dword [rel pkt_count], 0
    mov  dword [rel log_len], 0
    xor  ecx, ecx
    mov  edx, 1
    call mcmap_send_registries
    mov  ebx, [rel pkt_count]
    CHECK_EQ32 ebx, MC_REGISTRY_COUNT+1, "packets sent"
    lea  r12, [rel pkt_ids]
    mov  ebx, [r12+MC_REGISTRY_COUNT*4]
    CHECK_EQ32 ebx, MCP_CONFIGURATION_S2C_TAGS, "tags last"
    xor  ecx, ecx
    call rd_open
    lea  rcx, [rel s_biomereg]
    call rd_str_eq
    mov  ebx, eax
    CHECK_EQ32 ebx, 1, "first registry is worldgen/biome"
    ; same registries and entries, each one just the name + has_data 0
    xor  r12d, r12d
    xor  r13d, r13d                         ; bad packets
    xor  esi, esi                           ; entries
.kp:
    mov  ecx, r12d
    call rd_open
    mov  r15, rax
    lea  rdx, [rel pkt_ids]
    cmp  dword [rdx+r12*4], MCP_CONFIGURATION_S2C_REGISTRY_DATA
    jne  .kp_bad
    call rd_skip_str
    call rd_varint
    mov  r14d, eax
    add  esi, eax
    test r14d, r14d
    jz   .kp_bad
.kp_ent:
    test r14d, r14d
    jz   .kp_end
    call rd_skip_str
    mov  rax, [rel cursor]
    cmp  byte [rax], 0
    jne  .kp_bad
    inc  qword [rel cursor]
    dec  r14d
    jmp  .kp_ent
.kp_end:
    cmp  [rel cursor], r15
    je   .kp_next
.kp_bad:
    inc  r13d
.kp_next:
    inc  r12d
    cmp  r12d, MC_REGISTRY_COUNT
    jb   .kp
    CHECK_EQ32 r13d, 0, "registry packets with data or junk"
    mov  ebx, [rel ent_full]
    CHECK_EQ32 esi, ebx, "same entry count as with nbt"
    TAGS_OK MC_REGISTRY_COUNT
ENDP
