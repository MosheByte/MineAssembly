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
%define T_MOSS           89
%define T_DESTROY_0      96     ; 96..105 crack stages
%define T_WHITE          110
%define T_SELECTION      111    ; unused
%define T_STICK          112
%define T_COAL           113
%define T_IRON_INGOT     114
%define T_GOLD_INGOT     115
%define T_DIAMOND        116
%define T_APPLE          117
%define T_RAW_MEAT       118
%define T_COOKED_MEAT    119
%define T_ROTTEN_FLESH   120
%define T_FLINT          121
%define T_BREAD          122
%define T_STRING         123
%define T_BUCKET         124
%define T_WATER_BUCKET   125
%define T_LAVA_BUCKET    126
%define T_FLINT_STEEL    127
%define T_PICK           128    ; +tier
%define T_AXE            132
%define T_SHOVEL         136
%define T_SWORD          140
%define T_HEART_FULL     160
%define T_HEART_HALF     161
%define T_HEART_EMPTY    162
%define T_FOOD_FULL      163
%define T_FOOD_HALF      164
%define T_FOOD_EMPTY     165
%define T_BUBBLE         166
%define T_BUBBLE_POP     167
%define T_SLOT           168
%define T_SLOT_SELECTED  169
%define T_SUN            176
%define T_MOON           177
%define T_PARTICLE_SMOKE 178
%define T_PARTICLE_FLAME 179
%define T_PARTICLE_SPLASH 180
%define T_RAIN           181
%define T_SNOWFLAKE      182
%define T_EXPLOSION      183    ; 4 frames
%define T_BOAR_SKIN      192
%define T_BOAR_FACE      193
%define T_BOAR_SNOUT     194
%define T_WOOLLY_WOOL    195
%define T_WOOLLY_FACE    196
%define T_WOOLLY_SKIN    197
%define T_SHAMBLER_SKIN  198
%define T_SHAMBLER_FACE  199
%define T_SHAMBLER_SHIRT 200
%define T_SHAMBLER_PANTS 201
%define T_PLAYER_SKIN    202
%define T_PLAYER_FACE    203
%define T_PLAYER_SHIRT   204
%define T_PLAYER_PANTS   205
%define T_PLAYER_HAIR    206
%define T_GLOWBUG        207
%define T_BLOCKS2        208    ; block faces carry on here, past the hud/mob tiles
%define T_RED_SAND       208
%define T_TERRACOTTA     209    ; 209..214, same order as B_TERRACOTTA
%define T_BED_SIDE       215
%define T_BED_TOP        216    ; 216..219 pillow S W N E
%define TILE_COUNT       256

%define SFX_DIG_STONE    0
%define SFX_DIG_DIRT     1
%define SFX_DIG_GRASS    2
%define SFX_DIG_WOOD     3
%define SFX_DIG_SAND     4
%define SFX_DIG_GRAVEL   5
%define SFX_GLASS_BREAK  6
%define SFX_DIG_SNOW     7
%define SFX_DIG_WOOL     8
%define SFX_PLACE        9
%define SFX_STEP         10     ; pitched per material
%define SFX_EXPLODE      11
%define SFX_HURT         12
%define SFX_POP          13
%define SFX_CLICK        14
%define SFX_SPLASH       15
%define SFX_SWIM         16
%define SFX_BOAR         17
%define SFX_WOOLLY       18
%define SFX_SHAMBLER     19
%define SFX_FUSE         20
%define SFX_EAT          21
%define SFX_FIZZ         22
%define SFX_DEATH        23
%define SFX_LEVELUP      24
%define SFX_CHEST        25
%define SFX_THUNDER      26
%define SFX_COUNT        27

%define SND_STONE        0
%define SND_DIRT         1
%define SND_GRASS        2
%define SND_WOOD         3
%define SND_SAND         4
%define SND_GRAVEL       5
%define SND_GLASS        6
%define SND_SNOW         7
%define SND_WOOL         8

%define BIOME_OCEAN      0
%define BIOME_BEACH      1
%define BIOME_PLAINS     2
%define BIOME_FOREST     3
%define BIOME_BIRCH      4
%define BIOME_TAIGA      5
%define BIOME_TUNDRA     6
%define BIOME_DESERT     7
%define BIOME_MOUNTAINS  8
%define BIOME_SWAMP      9
%define BIOME_JUNGLE     10
%define BIOME_SAVANNA    11
%define BIOME_BADLANDS   12
%define BIOME_COUNT      13

%define ENT_NONE         0
%define ENT_ITEM         1
%define ENT_TNT          2
%define ENT_FALLING      3
%define ENT_BOAR         4
%define ENT_WOOLLY       5
%define ENT_SHAMBLER     6      ; burns in daylight
%define ENT_GLOWBUG      7
%define ENT_TYPES        8
; a java player (net bridge). past ENT_TYPES on purpose: no ai, no damage,
; never saved. mcplay moves it, variant = connection index
%define ENT_REMOTE       8

%define PT_BLOCK         0
%define PT_SMOKE         1
%define PT_FLAME         2
%define PT_SPLASH        3
%define PT_EXPLOSION     4
%define PT_RAIN          5
%define PT_SNOW          6
%define PT_BUBBLE        7
%define PT_CRIT          8
%define PT_SPARK         9

%define DMG_GENERIC      0
%define DMG_FALL         1
%define DMG_LAVA         2
%define DMG_DROWN        3
%define DMG_MOB          4
%define DMG_EXPLOSION    5
%define DMG_STARVE       6
%define DMG_VOID         7
%define DMG_PLAYER       8
%define DMG_SUN          9

%endif
