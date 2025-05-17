; common.inc - win64 frame macros and shared constants
%ifndef COMMON_INC
%define COMMON_INC

bits 64
default rel

; win64 abi: rcx rdx r8 r9 / xmm0-3, shadow 32B, rsp 16B aligned before call
%define FRAME_OUT 96 ; shadow + 8 arg slots

%macro PROC 1-2 0
    global %1
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

%macro ENDP 0
    lea  rsp, [rbp-56]
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret
%endmacro

%macro PROCX 1-2 0
    global %1
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

%macro ENDPX 0
    movdqa xmm6,  [rbp-224+0]
    movdqa xmm7,  [rbp-224+16]
    movdqa xmm8,  [rbp-224+32]
    movdqa xmm9,  [rbp-224+48]
    movdqa xmm10, [rbp-224+64]
    movdqa xmm11, [rbp-224+80]
    movdqa xmm12, [rbp-224+96]
    movdqa xmm13, [rbp-224+112]
    movdqa xmm14, [rbp-224+128]
    movdqa xmm15, [rbp-224+144]
    lea  rsp, [rbp-56]
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret
%endmacro

%define LOC(n) [rsp+FRAME_OUT+(n)]
%define ARG5 [rbp+48]
%define ARG6 [rbp+56]
%define ARG7 [rbp+64]
%define ARG8 [rbp+72]
%define ARG9 [rbp+80]
%define ARG10 [rbp+88]

; no frame, don't touch nonvolatiles
%macro LEAF 1
    global %1
    align 16
%1:
%endmacro

; FCONST xmm0, 1.5 - trashes eax
%macro FCONST 2
    mov  eax, __float32__(%2)
    movd %1, eax
%endmacro

%macro CSTR 2
    section .rdata
    %1: db %2, 0
    section .text
%endmacro

; rip-relative addressing only (default rel)

%define CHUNK_W         16
%define CHUNK_H         128
%define CHUNK_SHIFT     4
%define CHUNK_MASK      15
%define CHUNK_VOL       (CHUNK_W*CHUNK_W*CHUNK_H)
%define SECTION_H       16
%define SECTIONS        (CHUNK_H/SECTION_H)
%define SEA_LEVEL       62
; idx = x + (z<<4) + (y<<8)

%define MAX_RENDER_DIST 16
%define LOAD_MARGIN     2               ; extra ring so light/mesh have neighbours
%define MAX_CHUNKS      1600            ; >= (2*(16+2)+1)^2 = 1369
%define CHUNK_HASH_SIZE 4096            ; pow2!

%define CS_FREE         0
%define CS_QUEUED       1
%define CS_GENERATING   2
%define CS_GENERATED    3               ; blocks + column skylight
%define CS_LIT          4               ; needs all 8 neighbours >= GENERATED first
%define CS_READY        5

%define TICKS_PER_SEC   20
%define DAY_LENGTH      24000           ; 0 sunrise, 6000 noon, 12000 sunset

%define ST_TITLE        0
%define ST_WORLDSELECT  1
%define ST_CREATEWORLD  2
%define ST_LOADING      3
%define ST_PLAYING      4
%define ST_PAUSED       5
%define ST_INVENTORY    6               ; any container, see g_screen_kind
%define ST_CHAT         7
%define ST_DEAD         8
%define ST_SETTINGS     9
%define ST_QUIT         10

%define SCR_PLAYER      0
%define SCR_CRAFTING    1
%define SCR_FURNACE     2
%define SCR_CHEST       3
%define SCR_CREATIVE    4

%define GM_SURVIVAL     0
%define GM_CREATIVE     1

%define MB_LEFT         1
%define MB_RIGHT        2
%define MB_MIDDLE       4

; face order is shared by mesher, blk_tex and raycast, don't reorder
%define FACE_PX         0
%define FACE_NX         1
%define FACE_PY         2
%define FACE_NY         3
%define FACE_PZ         4
%define FACE_NZ         5               ; -z is north

%define INV_SLOTS       36              ; 0-8 = hotbar
%define HOTBAR_SLOTS    9

%define MAX_ENTITIES    512
%define MAX_PARTICLES   4096
%define MAX_BLOCKENTS   1024

; blocks
%define PLAYER_WIDTH    0.6
%define PLAYER_HEIGHT   1.8
%define PLAYER_EYE      1.62
%define REACH_SURVIVAL  4.5
%define REACH_CREATIVE  6.0

%include "win32.inc"
; --- inline ids draft before module split ---
; all the ids. blocks 0..127 and items 128..255 share one byte so a slot holds either
%ifndef IDS_INC
%define IDS_INC

%define B_AIR            0
%define B_STONE          1
%define B_GRASS          2
%define B_DIRT           3
%define B_COBBLE         4
%define B_PLANKS         5
%define B_BEDROCK        6
%define B_SAND           7
%define B_GRAVEL         8
%define B_LOG            9
%define B_LEAVES         10
%define B_GLASS          11
%define B_COAL_ORE       12
%define B_IRON_ORE       13
%define B_GOLD_ORE       14
%define B_DIAMOND_ORE    15
%define B_SANDSTONE      16
%define B_SNOW           17
%define B_ICE            18
%define B_CACTUS         19
%define B_CLAY           20
%define B_BIRCH_LOG      21
%define B_BIRCH_LEAVES   22
%define B_PINE_LOG       23
%define B_PINE_LEAVES    24
%define B_BRICKS         25
%define B_STONE_BRICKS   26
%define B_MOSSY_COBBLE   27
%define B_BOOKSHELF      28
%define B_CRAFT_TABLE    29
%define B_FURNACE        30
%define B_TNT            31
%define B_GLOWCRYSTAL    32     ; light 15
%define B_OBSIDIAN       33
%define B_TORCH          34     ; light 14
%define B_TALL_GRASS     35
%define B_FLOWER_RED     36
%define B_FLOWER_YELLOW  37
%define B_MUSHROOM_RED   38
%define B_MUSHROOM_BROWN 39
%define B_DEAD_BUSH      40
%define B_REEDS          41
%define B_PUMPKIN        42
%define B_MELON          43
%define B_WOOL           44     ; 44..59: white orange magenta ltblue yellow lime pink gray
                                ; ltgray cyan purple blue brown green red black
%define B_WOOL_LAST      59
%define B_GOLD_BLOCK     60
%define B_IRON_BLOCK     61
%define B_DIAMOND_BLOCK  62
%define B_COAL_BLOCK     63
%define B_SNOWY_GRASS    64
%define B_SAPLING        65
%define B_CHEST          66
%define B_LANTERN        67     ; light 15
%define B_FURNACE_LIT    68     ; light 13
%define B_PINE_PLANKS    69
%define B_BIRCH_PLANKS   70
%define B_MOSS           71
%define B_FARMLAND       72     ; unused for now
%define B_WATER          80
%define B_WATER_FLOW     81     ; 81..87, level = id-80, 1 strongest
%define B_WATER_LAST     87
%define B_LAVA           88     ; light 15
%define B_LAVA_FLOW      89     ; 89..91, level = id-88
%define B_LAVA_LAST      91
; turned blocks. the old id faces south (+z), the others sit in triples from
; B_DIR_FIRST in yaw order: west, north, east. same block otherwise, they drop
; the base and world_get_block folds them back to it
%define FACE_S           0
%define FACE_W           1
%define FACE_N           2
%define FACE_E           3
%define B_DIR_FIRST      96
%define B_FURNACE_W      96
%define B_FURNACE_N      97
%define B_FURNACE_E      98
%define B_FURNACE_LIT_W  99
%define B_FURNACE_LIT_N  100
%define B_FURNACE_LIT_E  101
%define B_CHEST_W        102
%define B_CHEST_N        103
%define B_CHEST_E        104
%define B_CRAFT_TABLE_W  105
%define B_CRAFT_TABLE_N  106
%define B_CRAFT_TABLE_E  107
%define B_PUMPKIN_W      108
%define B_PUMPKIN_N      109
%define B_PUMPKIN_E      110
%define B_DIR_LAST       110
%define DIR_BASE_0       B_FURNACE
%define DIR_BASE_1       B_FURNACE_LIT
%define DIR_BASE_2       B_CHEST
%define DIR_BASE_3       B_CRAFT_TABLE
%define DIR_BASE_4       B_PUMPKIN
%define DIR_FAMILIES     5
; leaves the player put down. same look, never decay
%define B_LEAVES_P       111
%define B_BIRCH_LEAVES_P 112
%define B_PINE_LEAVES_P  113
%define B_BED            114    ; pillow end south, +1 west +2 north +3 east
%define B_BED_LAST       117
%define B_RED_SAND       118
%define B_TERRACOTTA     119    ; 119..124: plain orange yellow red brown white
%define B_TERRACOTTA_LAST 124
%define BLOCK_COUNT      128

; BLOCK_BASE id -> BB_BASE (what it drops / folds to), BB_FACE (FACE_*),
; BB_TURN (base ids only: first turned id, 0 = can't turn)
%macro BLOCK_BASE 1
  %assign %%i %1
  %assign BB_BASE %%i
  %assign BB_FACE 0
  %assign BB_TURN 0
  %if %%i >= B_DIR_FIRST && %%i <= B_DIR_LAST
    %assign %%k (%%i - B_DIR_FIRST) / 3
    %assign BB_BASE DIR_BASE_%[%%k]
    %assign BB_FACE (%%i - B_DIR_FIRST) % 3 + 1
  %elif %%i > B_BED && %%i <= B_BED_LAST
    %assign BB_BASE B_BED
    %assign BB_FACE %%i - B_BED
  %elif %%i == B_BED
    %assign BB_TURN B_BED + 1
  %elif %%i == B_LEAVES_P
    %assign BB_BASE B_LEAVES
  %elif %%i == B_BIRCH_LEAVES_P
    %assign BB_BASE B_BIRCH_LEAVES
  %elif %%i == B_PINE_LEAVES_P
    %assign BB_BASE B_PINE_LEAVES
  %else
    %assign %%k 0
    %rep DIR_FAMILIES
      %if %%i == DIR_BASE_%[%%k]
        %assign BB_TURN B_DIR_FIRST + 3*%%k
      %endif
      %assign %%k %%k+1
    %endrep
  %endif
%endmacro

%define I_STICK          128
%define I_COAL           129
%define I_IRON_INGOT     130
%define I_GOLD_INGOT     131
%define I_DIAMOND        132
%define I_APPLE          133
%define I_RAW_MEAT       134
%define I_COOKED_MEAT    135
%define I_ROTTEN_FLESH   136
%define I_FLINT          137
%define I_BREAD          138
%define I_STRING         139
; tools: base + tier (0 wood 1 stone 2 iron 3 diamond)
%define I_PICK_WOOD      140
%define I_PICK_STONE     141
%define I_PICK_IRON      142
%define I_PICK_DIAMOND   143
%define I_AXE_WOOD       144
%define I_AXE_STONE      145
%define I_AXE_IRON       146
%define I_AXE_DIAMOND    147
%define I_SHOVEL_WOOD    148
%define I_SHOVEL_STONE   149
%define I_SHOVEL_IRON    150
%define I_SHOVEL_DIAMOND 151
%define I_SWORD_WOOD     152
%define I_SWORD_STONE    153
%define I_SWORD_IRON     154
%define I_SWORD_DIAMOND  155
%define I_BUCKET         156
%define I_WATER_BUCKET   157
%define I_LAVA_BUCKET    158
%define I_FLINT_STEEL    159
%define ITEM_FIRST       128
%define ITEM_LAST        159

%define TOOL_NONE        0
%define TOOL_PICK        1
%define TOOL_AXE         2
%define TOOL_SHOVEL      3
%define TOOL_SWORD       4

; atlas is 16x16 tiles of 16px, u0 = (t&15)/16, v0 = (t>>4)/16
%define T_STONE          0
%define T_DIRT           1
%define T_GRASS_TOP      2      ; grey, gets tinted
%define T_GRASS_SIDE     3      ; fringe baked in, no tint
%define T_COBBLE         4
%define T_PLANKS         5
%define T_BEDROCK        6
%define T_SAND           7
%define T_GRAVEL         8
%define T_LOG_SIDE       9
%define T_LOG_TOP        10
%define T_LEAVES         11     ; grey + alpha holes
%define T_GLASS          12
%define T_COAL_ORE       13
%define T_IRON_ORE       14
%define T_GOLD_ORE       15
%define T_DIAMOND_ORE    16
%define T_SANDSTONE_SIDE 17
%define T_SANDSTONE_TOP  18
%define T_SNOW           19
%define T_ICE            20
%define T_CACTUS_SIDE    21
%define T_CACTUS_TOP     22
%define T_CLAY           23
%define T_BIRCH_SIDE     24
%define T_BIRCH_TOP      25
%define T_BIRCH_LEAVES   26
%define T_PINE_SIDE      27
%define T_PINE_TOP       28
%define T_PINE_LEAVES    29
%define T_BRICKS         30
%define T_STONE_BRICKS   31
%define T_MOSSY_COBBLE   32
%define T_BOOKSHELF      33
%define T_CRAFT_TOP      34
%define T_CRAFT_SIDE     35
%define T_CRAFT_FRONT    36
%define T_FURNACE_FRONT  37
%define T_FURNACE_SIDE   38
%define T_FURNACE_TOP    39
%define T_TNT_SIDE       40
%define T_TNT_TOP        41
%define T_TNT_BOTTOM     42
%define T_GLOWCRYSTAL    43
%define T_OBSIDIAN       44
%define T_TORCH          45
%define T_TALL_GRASS     46
%define T_FLOWER_RED     47
%define T_FLOWER_YELLOW  48
%define T_MUSHROOM_RED   49
%define T_MUSHROOM_BROWN 50
%define T_DEAD_BUSH      51
%define T_REEDS          52
%define T_PUMPKIN_SIDE   53
%define T_PUMPKIN_TOP    54
%define T_PUMPKIN_FACE   55
%define T_MELON_SIDE     56
%define T_MELON_TOP      57
%define T_WOOL           58     ; 58..73
%define T_GOLD_BLOCK     74
%define T_IRON_BLOCK     75
%define T_DIAMOND_BLOCK  76
%define T_COAL_BLOCK     77
%define T_SNOWY_GRASS_SIDE 78
%define T_WATER          79
%define T_LAVA           80
%define T_SAPLING        81
%define T_CHEST_FRONT    82
%define T_CHEST_SIDE     83
%define T_CHEST_TOP      84
%define T_LANTERN        85
%define T_FURNACE_FRONT_LIT 86
%define T_PINE_PLANKS    87
%define T_BIRCH_PLANKS   88
%include "gl.inc"
%include "ids.inc"
%include "structs.inc"
%include "api.inc"

%endif
