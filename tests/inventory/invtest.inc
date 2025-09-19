; invtest.inc - shared bits for the inventory tests. every test links the real
; inventory/screens/blockent plus fakes.asm + invharness.asm; ui_* gets
; auto-stubbed to return 0 so screens_render does layout + drag headless.
%ifndef INVTEST_INC
%define INVTEST_INC

; ids copied from include/ids.inc on purpose, keep literal
%define B_DIRT          3
%define B_PLANKS        5
%define B_LOG           9
%define B_COAL_ORE      12
%define B_IRON_ORE      13
%define B_CRAFT_TABLE   29
%define B_FURNACE       30
%define B_CHEST         66
%define B_FURNACE_LIT   68
%define I_STICK         128
%define I_COAL          129
%define I_IRON_INGOT    130
%define I_PICK_WOOD     140
%define I_BUCKET        156
%define I_LAVA_BUCKET   158

%define P_X             0
%define P_Y             4
%define P_Z             8
%define P_SELECTED      92
%define P_INV           256
%define P_CURSOR        400
%define P_CRAFT         404
%define P_CRAFT_OUT     440

; slot groups, must match screens.asm
%define G_HOTBAR        1
%define G_MAIN          2
%define G_CRAFT         3
%define G_CHEST         4
%define G_FIN           5
%define G_FFUEL         6
%define G_RESULT        7
%define G_FOUT          8
%define G_CGRID         9
%define G_TRASH         10

%define SD_X            0
%define SD_Y            2
%define SD_GROUP        4
%define SD_FLAGS        5
%define SD_IDX          6
%define SD_PTR          8
%define SD_SIZE         16

%define BE_KIND         0
%define BE_X            4
%define BE_Y            8
%define BE_Z            12
%define BE_BURN         16
%define BE_BURN_MAX     20
%define BE_COOK         24
%define BE_SLOTS        32
%define BLOCKENT_BYTES  160

%define VK_SHIFT_       0x10
%define VK_CONTROL_     0x11
%define VK_ESCAPE_      0x1B

; stack dword: id | count<<8 | damage<<16
%define STK(id, cnt, dmg) ((id) | ((cnt) << 8) | ((dmg) << 16))
%define INVS(i)   (g_player + P_INV + 4*(i))
%define CRAFTS(i) (g_player + P_CRAFT + 4*(i))
%define CURSORS   (g_player + P_CURSOR)
%define CROUTS    (g_player + P_CRAFT_OUT)

extern fake_block, fake_setraw_count, fake_light_count, fake_light_old
extern fake_spawn_count, fake_spawn_items, fake_entity, fake_last_spawn_id
extern scr_slots, scr_nslots
extern inv_stack_max, inv_put_core, inv_move_range, inv_capacity
%ifndef IMPL_INVHARNESS
extern h_reset
extern h_set_pos        ; xmm0..2 = feet pos
extern h_layout
extern h_find           ; (group, idx) -> SLOTDEF*, fails the test if missing
extern h_hover
extern h_click          ; (group, idx, button, shift)
extern h_key            ; (vk, repeat)
extern h_press
extern h_release
extern h_move           ; hover + one render = a drag step
extern h_count_group
extern h_cells          ; (out word[96]) -> count of creative cell idx
extern h_panel
extern h_set_name
extern h_mouse_at
%endif

%macro CHECK_STK 5
    CHECK_EQ32 %1, STK(%2, %3, %4), %5
%endmacro

%macro CHECK_NZ64 2
    mov  rax, %1
    test rax, rax
    setnz al
    movzx eax, al
    CHECK_TRUE eax, %2
%endmacro

%macro SET_STK 4
    mov  dword %1, STK(%2, %3, %4)
%endmacro

; CLICK group, idx [, button [, shift]]
%macro CLICK 2-4 MB_LEFT, 0
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    call h_click
%endmacro

%macro HOVER 2
    mov  ecx, %1
    mov  edx, %2
    call h_hover
%endmacro

%macro MOVE 2
    mov  ecx, %1
    mov  edx, %2
    call h_move
%endmacro

%macro PRESS 1
    mov  ecx, %1
    call h_press
%endmacro

%macro RELEASE 1
    mov  ecx, %1
    call h_release
%endmacro

%macro KEY 1-2 0
    mov  ecx, %1
    mov  edx, %2
    call h_key
%endmacro

; OPEN kind [, x, y, z]
%macro OPEN 1-4 0, 64, 0
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    call screens_open
%endmacro

%endif
