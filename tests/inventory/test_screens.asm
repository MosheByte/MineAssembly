; test_screens.asm - screens.asm driven through its public api like the game
; does. ui_* are zero stubs so render still runs layout + drag logic.
; @link src/inventory.asm src/screens.asm src/blockent.asm
; @link tests/inventory/fakes.asm tests/inventory/invharness.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../inventory/invtest.inc"   ; via the tests/lib/ include path

section .rdata
align 8
d_tenth:    dq 0.1
f_20:       dd 20.0
f_64b:      dd 64.0
f_half:     dd 0.5
f_55:       dd 5.5
s_item:     db "Item ", 0
s_stone:    db "Stone", 0
s_grass:    db "Grass Block", 0
s_dirt:     db "Dirt", 0
s_pine:     db "Pine_Planks", 0
s_gra:      db "gRa", 0
s_pine_p:   db 8, 8, 8, "pine p", 0     ; three backspaces, then "pine p"

section .bss
alignb 16
cells:      resw 96                     ; creative cell idx list (h_cells)
ncells:     resd 1
name_buf:   resb 16*64                  ; "Item N" strings for ids 1..60

section .text

PROC load_cells, 0
    lea   rcx, [rel cells]
    call  h_cells
    mov   [rel ncells], eax
ENDP

; k = reg or const
%macro CELL 1
    lea   rax, [rel cells]
    movzx eax, word [rax+2*(%1)]
%endmacro

; whole string arrives as one frame of WM_CHAR
PROC feed_chars, 0
    lea   rdx, [rel g_char_queue]
    xor   eax, eax
.cp:
    mov   r8b, [rcx+rax]
    test  r8b, r8b
    jz    .end
    mov   [rdx+rax], r8b
    inc   eax
    jmp   .cp
.end:
    mov   [rel g_char_count], eax
    call  screens_render
    mov   dword [rel g_char_count], 0
ENDP

LEAF all_inv_dirt
    lea   rax, [rel INVS(0)]
    mov   ecx, 36
.f: mov   dword [rax], STK(B_DIRT, 64, 0)
    add   rax, 4
    dec   ecx
    jnz   .f
    ret

LEAF add_time
    addsd xmm0, [rel g_time_total]
    movsd [rel g_time_total], xmm0
    ret

PROC containers_setup, 0
    call  h_reset
    lea   rax, [rel item_smelt]
    mov   byte [rax+B_IRON_ORE], I_IRON_INGOT
    lea   rax, [rel item_fuel]
    mov   word [rax+2*I_COAL], 1600
ENDP

PROC case_chest_quick_move, 0
    TEST "containers: chest quick move"
    call  containers_setup
    mov   dword [rel fake_block], B_CHEST
    OPEN  SCR_CHEST, 5, 64, 0
    movss xmm0, [rel f_55]
    movss xmm1, [rel f_64b]
    movss xmm2, [rel f_half]
    call  h_set_pos
    mov   ecx, 5
    mov   edx, 64
    xor   r8d, r8d
    xor   r9d, r9d
    call  blockent_get
    mov   rbx, rax
    mov   ecx, G_CHEST
    call  h_count_group
    CHECK_EQ32 eax, 27, "27 chest slots"
    SET_STK [rel INVS(0)], 1, 30, 0
    CLICK G_HOTBAR, 0, MB_LEFT, 1
    CHECK_STK [rbx+BE_SLOTS], 1, 30, 0, "moved into chest"
    CLICK G_CHEST, 0, MB_LEFT, 1
    CHECK_STK [rbx+BE_SLOTS], 0, 0, 0, "chest slot emptied"
    CHECK_STK [rel INVS(0)], 1, 30, 0, "back in hotbar"
    mov   ecx, 5
    mov   edx, 64
    xor   r8d, r8d
    call  blockent_remove               ; chest broken while open
    SET_STK [rel CURSORS], B_DIRT, 1, 0
    call  screens_render
    CHECK_STK [rel CURSORS], 0, 0, 0, "closed, cursor returned"
    CHECK_STK [rel INVS(1)], B_DIRT, 1, 0, "cursor went to slot 1"
ENDP

PROC case_furnace_routing, 0
    TEST "containers: furnace routing and output"
    call  containers_setup
    mov   dword [rel fake_block], B_FURNACE
    OPEN  SCR_FURNACE, 0, 64, 0
    xor   ecx, ecx
    mov   edx, 64
    xor   r8d, r8d
    xor   r9d, r9d
    call  blockent_get
    mov   rbx, rax
    CHECK_NZ64 rbx, "furnace entity exists"
    SET_STK [rel INVS(0)], B_IRON_ORE, 5, 0
    SET_STK [rel INVS(1)], I_COAL, 3, 0
    SET_STK [rel INVS(2)], B_DIRT, 4, 0
    CLICK G_HOTBAR, 0, MB_LEFT, 1
    CLICK G_HOTBAR, 1, MB_LEFT, 1
    CLICK G_HOTBAR, 2, MB_LEFT, 1
    CHECK_STK [rbx+BE_SLOTS+0], B_IRON_ORE, 5, 0, "ore -> input"
    CHECK_STK [rbx+BE_SLOTS+4], I_COAL, 3, 0, "coal -> fuel"
    CHECK_STK [rel INVS(9)], B_DIRT, 4, 0, "neither: hotbar -> main"
    ; fuel slot refuses non-fuel
    CLICK G_MAIN, 9
    CLICK G_FFUEL, 0
    CHECK_STK [rel CURSORS], B_DIRT, 4, 0, "fuel slot refuses dirt"
    CLICK G_MAIN, 9
    ; output is take-only
    SET_STK [rbx+BE_SLOTS+8], I_IRON_INGOT, 3, 0
    CLICK G_FOUT, 0
    CHECK_STK [rel CURSORS], I_IRON_INGOT, 3, 0, "took output"
    CLICK G_FOUT, 0                     ; cannot put back
    CHECK_STK [rel CURSORS], I_IRON_INGOT, 3, 0, "cannot put back"
    SET_STK [rbx+BE_SLOTS+8], I_IRON_INGOT, 2, 0
    CLICK G_FOUT, 0                     ; merges onto the cursor
    CHECK_STK [rel CURSORS], I_IRON_INGOT, 5, 0, "merged onto cursor"
    SET_STK [rbx+BE_SLOTS+8], I_IRON_INGOT, 2, 0
    CLICK G_FOUT, 0, MB_LEFT, 1
    CHECK_STK [rbx+BE_SLOTS+8], 0, 0, 0, "shift: output emptied"
    CHECK_STK [rel INVS(0)], I_IRON_INGOT, 2, 0, "shift: to slot 0"
    ; furnace switching to lit keeps the screen open
    mov   dword [rel fake_block], B_FURNACE_LIT
    CLICK G_FIN, 0                      ; different item: swap
    CHECK_STK [rel CURSORS], B_IRON_ORE, 5, 0, "swap: ore on cursor"
    CHECK_STK [rbx+BE_SLOTS+0], I_IRON_INGOT, 5, 0, "swap: ingots in input"
ENDP

PROC crafting_setup, 0
    call  h_reset
    mov   dword [rel fake_block], B_CRAFT_TABLE
    OPEN  SCR_CRAFTING
    CHECK_EQ32 [rel g_screen_kind], SCR_CRAFTING, "crafting screen open"
ENDP

PROC case_block_destroyed_closes, 0
    TEST "crafting: block destroyed closes"
    call  crafting_setup
    SET_STK [rel CURSORS], B_DIRT, 5, 0
    mov   dword [rel fake_block], 0
    call  screens_render
    CHECK_STK [rel INVS(0)], B_DIRT, 5, 0, "cursor returned"
    SET_STK [rel INVS(9)], 1, 1, 0
    CLICK G_MAIN, 9                     ; screen is closed: no effect
    CHECK_STK [rel CURSORS], 0, 0, 0, "closed screen ignores clicks"
ENDP

PROC case_close_full_throws, 0
    TEST "crafting: close with full inventory throws"
    call  crafting_setup
    call  all_inv_dirt
    SET_STK [rel CURSORS], B_LOG, 5, 0
    call  screens_close
    CHECK_EQ32 [rel fake_spawn_count], 1, "one entity thrown"
    CHECK_EQ32 [rel fake_spawn_items], 5, "five logs thrown"
ENDP

PROC case_close_returns, 0
    TEST "crafting: close returns everything"
    call  crafting_setup
    SET_STK [rel CRAFTS(0)], B_LOG, 2, 0
    SET_STK [rel CRAFTS(8)], B_PLANKS, 3, 0
    SET_STK [rel CURSORS], B_DIRT, 5, 0
    call  screens_close
    CHECK_STK [rel INVS(0)], B_LOG, 2, 0, "logs"
    CHECK_STK [rel INVS(1)], B_PLANKS, 3, 0, "planks"
    CHECK_STK [rel INVS(2)], B_DIRT, 5, 0, "dirt"
    CHECK_STK [rel CURSORS], 0, 0, 0, "cursor empty"
    CHECK_STK [rel CROUTS], 0, 0, 0, "result empty"
ENDP

PROC case_crafting_layout, 0
    TEST "crafting: layout"
    call  crafting_setup
    mov   ecx, G_CRAFT
    call  h_count_group
    CHECK_EQ32 eax, 9, "9 grid slots"
    mov   ecx, G_RESULT
    call  h_count_group
    CHECK_EQ32 eax, 1, "1 result slot"
    mov   ecx, G_MAIN
    call  h_count_group
    CHECK_EQ32 eax, 27, "27 main slots"
    mov   ecx, G_HOTBAR
    call  h_count_group
    CHECK_EQ32 eax, 9, "9 hotbar slots"
    mov   ecx, G_RESULT
    xor   edx, edx
    call  h_find
    movzx eax, byte [rax+SD_FLAGS]
    and   eax, 1
    CHECK_EQ32 eax, 1, "big result slot"
    mov   ecx, G_HOTBAR
    xor   edx, edx
    call  h_find
    mov   rbx, [rax+SD_PTR]
    movsx esi, word [rax+SD_Y]
    mov   ecx, G_MAIN
    mov   edx, 9
    call  h_find
    mov   rdi, [rax+SD_PTR]
    movsx r12d, word [rax+SD_Y]
    lea   rdx, [rel INVS(0)]
    CHECK_EQ rbx, rdx, "hotbar 0 shows inv[0]"
    lea   rdx, [rel INVS(9)]
    CHECK_EQ rdi, rdx, "main 9 shows inv[9]"
    xor   eax, eax
    cmp   esi, r12d
    setg  al
    CHECK_TRUE eax, "hotbar row below the main grid"
ENDP

PROC case_place_take_result, 0
    TEST "crafting: place / take result"
    call  crafting_setup
    SET_STK [rel INVS(0)], B_LOG, 3, 0
    CLICK G_HOTBAR, 0
    CHECK_STK [rel CURSORS], B_LOG, 3, 0, "picked logs"
    CLICK G_CRAFT, 4
    CHECK_STK [rel CRAFTS(4)], B_LOG, 3, 0, "logs in grid"
    CHECK_STK [rel CROUTS], B_PLANKS, 4, 0, "preview planks"
    CLICK G_RESULT, 0
    CHECK_STK [rel CURSORS], B_PLANKS, 4, 0, "took 4 planks"
    CHECK_STK [rel CRAFTS(4)], B_LOG, 2, 0, "one log used"
    CLICK G_RESULT, 0                   ; cursor accumulates
    CHECK_STK [rel CURSORS], B_PLANKS, 8, 0, "8 planks"
    CLICK G_RESULT, 0, MB_RIGHT
    CHECK_STK [rel CURSORS], B_PLANKS, 12, 0, "12 planks"
    CHECK_STK [rel CRAFTS(4)], 0, 0, 0, "grid empty"
    CHECK_STK [rel CROUTS], 0, 0, 0, "no preview"
ENDP

PROC case_result_blocked, 0
    TEST "crafting: result blocked when cursor cannot hold"
    call  crafting_setup
    SET_STK [rel CRAFTS(0)], B_LOG, 1, 0
    SET_STK [rel CURSORS], B_PLANKS, 62, 0
    CLICK G_RESULT, 0
    CHECK_STK [rel CURSORS], B_PLANKS, 62, 0, "cursor unchanged"
    CHECK_STK [rel CRAFTS(0)], B_LOG, 1, 0, "log kept"
    SET_STK [rel CURSORS], B_DIRT, 1, 0   ; different item: no craft
    CLICK G_RESULT, 0
    CHECK_STK [rel CURSORS], B_DIRT, 1, 0, "different item: no craft"
ENDP

PROC case_shift_craft_all, 0
    TEST "crafting: shift craft all"
    call  crafting_setup
    SET_STK [rel CRAFTS(2)], B_LOG, 5, 0
    SET_STK [rel INVS(0)], B_DIRT, 1, 0
    call  h_layout
    CLICK G_RESULT, 0, MB_LEFT, 1
    CHECK_STK [rel CRAFTS(2)], 0, 0, 0, "all logs used"
    CHECK_STK [rel INVS(1)], B_PLANKS, 20, 0, "20 planks"
    CHECK_STK [rel CURSORS], 0, 0, 0, "cursor empty"
ENDP

PROC case_shift_craft_full, 0
    TEST "crafting: shift craft stops when full"
    call  crafting_setup
    call  all_inv_dirt
    SET_STK [rel INVS(7)], B_PLANKS, 58, 0  ; room for 6 planks only
    SET_STK [rel CRAFTS(0)], B_LOG, 5, 0
    CLICK G_RESULT, 0, MB_LEFT, 1
    CHECK_STK [rel INVS(7)], B_PLANKS, 62, 0, "one craft fit"
    CHECK_STK [rel CRAFTS(0)], B_LOG, 4, 0, "one log used"
ENDP

PROC case_two_by_two_on_3x3, 0
    TEST "crafting: 2x2 recipe on 3x3"
    call  crafting_setup
    SET_STK [rel CRAFTS(0)], B_PLANKS, 1, 0
    SET_STK [rel CRAFTS(1)], B_PLANKS, 1, 0
    SET_STK [rel CRAFTS(3)], B_PLANKS, 1, 0
    SET_STK [rel CRAFTS(4)], B_PLANKS, 1, 0
    call  h_layout
    CHECK_STK [rel CROUTS], B_CRAFT_TABLE, 1, 0, "preview table"
    CLICK G_RESULT, 0
    CHECK_STK [rel CURSORS], B_CRAFT_TABLE, 1, 0, "took table"
    lea   rax, [rel CRAFTS(0)]
    xor   edx, edx
    mov   ecx, 9
.or: or   edx, [rax]
    add   rax, 4
    dec   ecx
    jnz   .or
    CHECK_EQ32 edx, 0, "grid empty"
ENDP

PROC case_walking_away, 0
    TEST "crafting: walking away closes"
    call  crafting_setup
    SET_STK [rel CURSORS], B_DIRT, 5, 0
    movss xmm0, [rel f_20]
    movss xmm1, [rel f_64b]
    movss xmm2, [rel f_half]
    call  h_set_pos
    call  screens_render
    CHECK_STK [rel INVS(0)], B_DIRT, 5, 0, "cursor returned"
ENDP

; creative, ids 1..60 named "Item N" (1..4 get real names), screen open
PROC creative_setup, 0
    call  h_reset
    mov   dword [rel g_gamemode], GM_CREATIVE
    lea   rax, [rel item_creative_list]
    xor   ecx, ecx
.list:
    lea   edx, [rcx+1]
    mov   [rax+rcx], dl
    inc   ecx
    cmp   ecx, 60
    jb    .list
    mov   ebx, 1
.nm:
    lea   rdi, [rel name_buf]
    mov   eax, ebx
    shl   eax, 4
    add   rdi, rax
    mov   r12, rdi
    lea   rsi, [rel s_item]
    mov   ecx, 5
    rep   movsb
    mov   eax, ebx
    cmp   eax, 10
    jb    .one
    xor   edx, edx
    mov   ecx, 10
    div   ecx                           ; eax tens, edx units
    add   al, '0'
    stosb
    mov   eax, edx
.one:
    add   al, '0'
    stosb
    mov   byte [rdi], 0
    mov   ecx, ebx
    mov   rdx, r12
    call  h_set_name
    inc   ebx
    cmp   ebx, 60
    jbe   .nm
    mov   ecx, 1
    lea   rdx, [rel s_stone]
    call  h_set_name
    mov   ecx, 2
    lea   rdx, [rel s_grass]
    call  h_set_name
    mov   ecx, 3
    lea   rdx, [rel s_dirt]
    call  h_set_name
    mov   ecx, 4
    lea   rdx, [rel s_pine]
    call  h_set_name
    OPEN  SCR_PLAYER
ENDP

PROC case_opens_creative_scrolls, 0
    TEST "creative: opens creative and scrolls"
    call  creative_setup
    CHECK_EQ32 [rel g_screen_kind], SCR_CREATIVE, "creative screen"
    call  load_cells
    CELL  0
    CHECK_EQ32 eax, 1, "cell 0"
    CELL  1
    CHECK_EQ32 eax, 2, "cell 1"
    CELL  2
    CHECK_EQ32 eax, 3, "cell 2"
    CHECK_EQ32 [rel ncells], 45, "45 cells"
    mov   ecx, -1
    call  screens_on_wheel
    call  load_cells
    CELL  0
    CHECK_EQ32 eax, 10, "scrolled one row"
    mov   ecx, -10
    call  screens_on_wheel              ; 60 items = 7 rows -> max scroll 2
    call  load_cells
    CELL  0
    CHECK_EQ32 eax, 19, "clamped at max scroll"
    mov   ebx, [rel ncells]
    CELL  rbx-4
    CHECK_EQ32 eax, 60, "last item"
    CELL  rbx-3
    CHECK_EQ32 eax, 0, "padding 1"
    CELL  rbx-2
    CHECK_EQ32 eax, 0, "padding 2"
    CELL  rbx-1
    CHECK_EQ32 eax, 0, "padding 3"
    mov   ecx, 5
    call  screens_on_wheel
    call  load_cells
    CELL  0
    CHECK_EQ32 eax, 1, "back to top"
ENDP

PROC case_pick_fill_delete, 0
    TEST "creative: pick / fill / delete"
    call  creative_setup
    CLICK G_CGRID, 1
    CHECK_STK [rel CURSORS], 1, 64, 0, "full stack picked"
    SET_STK [rel CURSORS], 1, 3, 0
    CLICK G_CGRID, 1, MB_RIGHT
    CHECK_STK [rel CURSORS], 1, 4, 0, "right adds one"
    CLICK G_CGRID, 1
    CHECK_STK [rel CURSORS], 1, 64, 0, "left fills"
    CLICK G_CGRID, 2                    ; different item: destroyed
    CHECK_STK [rel CURSORS], 0, 0, 0, "different item destroyed"
    CLICK G_CGRID, 5, MB_RIGHT
    CHECK_STK [rel CURSORS], 5, 1, 0, "right picks one"
    CLICK G_TRASH, 0
    CHECK_STK [rel CURSORS], 0, 0, 0, "trash"
ENDP

PROC case_search, 0
    TEST "creative: search"
    call  creative_setup
    call  h_panel
    mov   ebx, eax
    mov   esi, edx
    lea   ecx, [rbx+85]
    lea   edx, [rsi+8]
    call  h_mouse_at                    ; search box
    PRESS MB_LEFT
    RELEASE MB_LEFT
    lea   rcx, [rel s_gra]
    call  feed_chars
    call  load_cells
    CELL  0
    CHECK_EQ32 eax, 2, "gRa -> Grass Block"
    CELL  1
    CHECK_EQ32 eax, 0, "only one match"
    KEY   'E'                           ; typing: E must not close
    lea   rcx, [rel s_pine_p]
    call  feed_chars
    call  load_cells
    CELL  0
    CHECK_EQ32 eax, 4, "'_' matches ' '"
    CELL  1
    CHECK_EQ32 eax, 0, "only Pine_Planks"
    KEY   VK_ESCAPE_                    ; leaves the box only
    CLICK G_CGRID, 4
    CHECK_STK [rel CURSORS], 4, 64, 0, "still open after Esc"
    lea   ecx, [rbx+85]
    lea   edx, [rsi+8]
    call  h_mouse_at
    PRESS MB_RIGHT
    RELEASE MB_RIGHT                    ; right click clears the search
    call  load_cells
    CELL  0
    CHECK_EQ32 eax, 1, "cleared: cell 0"
    CELL  1
    CHECK_EQ32 eax, 2, "cleared: cell 1"
    CELL  2
    CHECK_EQ32 eax, 3, "cleared: cell 2"
ENDP

PROC case_shift_hotbar_middle, 0
    TEST "creative: shift to hotbar and middle clone"
    call  creative_setup
    CLICK G_CGRID, 3, MB_LEFT, 1
    CHECK_STK [rel INVS(0)], 3, 64, 0, "shift: stack to hotbar"
    HOVER G_HOTBAR, 0
    PRESS MB_MIDDLE
    RELEASE MB_MIDDLE
    CHECK_STK [rel CURSORS], 3, 64, 0, "middle clone"
    SET_STK [rel CURSORS], 0, 0, 0
    CLICK G_TRASH, 0, MB_LEFT, 1        ; wipe inventory
    CHECK_STK [rel INVS(0)], 0, 0, 0, "inventory wiped"
ENDP

PROC case_tab_origin_short_ui, 0 ; v1: test_screens scratch #1
    TEST "creative: tab origin keeps survival panel on screen" ; v1: test_screens scratch #2
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_screens:2)
    call  creative_setup ; v1: test_screens scratch #3
    mov   dword [rel g_ui_h], 200 ; v1: test_screens scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_screens:4)
    xor   ecx, ecx ; v1: test_screens scratch #5
    xor   edx, edx ; v1: test_screens scratch #6
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_screens:6)
    call  h_mouse_at ; v1: test_screens scratch #7
    call  h_layout ; v1: test_screens scratch #8
    ; TODO: clamp index before table lookup on malformed input (test_screens:8)
    call  h_panel ; v1: test_screens scratch #9
    mov   ebx, eax ; v1: test_screens scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_screens:10)
    mov   esi, edx ; v1: test_screens scratch #11
    CHECK_EQ32 esi, 200-166, "raised to fit" ; v1: test_screens scratch #12
    ; TODO: hoist invariant pointer load out of .loop (test_screens:12)
    mov   dword [rel g_screen_kind], SCR_PLAYER ; v1: test_screens scratch #13
    mov   ecx, G_CRAFT ; v1: test_screens scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_screens:14)
    xor   edx, edx ; v1: test_screens scratch #15
    call  h_find ; v1: test_screens scratch #16
    ; TODO: verify 16-byte rsp alignment before inner call (test_screens:16)
    movsx edi, word [rax+SD_X] ; v1: test_screens scratch #17
    movsx r12d, word [rax+SD_Y] ; v1: test_screens scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_screens:18)
    sub   edi, 87 ; v1: test_screens scratch #19
    sub   r12d, 17 ; v1: test_screens scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_screens:20)
    CHECK_EQ32 edi, ebx, "survival panel x" ; v1: test_screens scratch #21
    CHECK_EQ32 r12d, esi, "survival panel y" ; v1: test_screens scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_screens:22)
ENDP ; v1: test_screens scratch #23

PROC case_tabs, 0 ; v1: test_screens scratch #25
    TEST "creative: tabs" ; v1: test_screens scratch #26
    ; TODO: clamp index before table lookup on malformed input (test_screens:26)
    call  creative_setup ; v1: test_screens scratch #27
    call  h_panel ; v1: test_screens scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_screens:28)
    lea   ecx, [rax+2+30+10] ; v1: test_screens scratch #29
    lea   edx, [rdx-10] ; v1: test_screens scratch #30
    ; TODO: hoist invariant pointer load out of .loop (test_screens:30)
    call  h_mouse_at ; v1: test_screens scratch #31
    PRESS MB_LEFT ; v1: test_screens scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_screens:32)
    RELEASE MB_LEFT ; v1: test_screens scratch #33
    CHECK_EQ32 [rel g_screen_kind], SCR_PLAYER, "survival tab" ; v1: test_screens scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (test_screens:34)
    mov   ecx, G_CRAFT ; v1: test_screens scratch #35
    xor   edx, edx ; v1: test_screens scratch #36
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_screens:36)
    call  h_find ; v1: test_screens scratch #37
    movsx ecx, word [rax+SD_X] ; v1: test_screens scratch #38
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_screens:38)
    movsx edx, word [rax+SD_Y] ; v1: test_screens scratch #39
    sub   ecx, 87-2-10 ; v1: test_screens scratch #40
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_screens:40)
    sub   edx, 17+10 ; v1: test_screens scratch #41
    call  h_mouse_at ; v1: test_screens scratch #42
    ; TODO: clamp index before table lookup on malformed input (test_screens:42)
    PRESS MB_LEFT ; v1: test_screens scratch #43
    RELEASE MB_LEFT ; v1: test_screens scratch #44
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_screens:44)
    CHECK_EQ32 [rel g_screen_kind], SCR_CREATIVE, "items tab" ; v1: test_screens scratch #45
ENDP ; v1: test_screens scratch #46
    ; TODO: hoist invariant pointer load out of .loop (test_screens:46)

PROC case_tabs_stay_put, 0
    TEST "creative: tabs stay put"
    ; both tabbed screens share one panel origin, so the tab row does not
    ; move and clicking the same spots toggles back and forth
    call  creative_setup
    call  h_panel
    mov   ebx, eax
    mov   esi, edx
    CHECK_EQ32 ebx, (427-195)/2, "panel x"
    CHECK_EQ32 esi, (240-136)/2+11, "panel y"
    mov   r13d, 2
.round:
    lea   ecx, [rbx+2+30+10]            ; survival tab
    lea   edx, [rsi-10]
    call  h_mouse_at
    PRESS MB_LEFT
    RELEASE MB_LEFT
    CHECK_EQ32 [rel g_screen_kind], SCR_PLAYER, "survival tab"
    mov   ecx, G_CRAFT                  ; player grid at (87,17)
    xor   edx, edx
    call  h_find
    movsx edi, word [rax+SD_X]
    movsx r12d, word [rax+SD_Y]
    sub   edi, 87
    sub   r12d, 17
    CHECK_EQ32 edi, ebx, "player panel x"
    CHECK_EQ32 r12d, esi, "player panel y"
    lea   ecx, [rbx+2+10]               ; items tab
    lea   edx, [rsi-10]
    call  h_mouse_at
    PRESS MB_LEFT
    RELEASE MB_LEFT
    CHECK_EQ32 [rel g_screen_kind], SCR_CREATIVE, "items tab"
    call  h_panel
    mov   edi, eax
    mov   r12d, edx
    CHECK_EQ32 edi, ebx, "creative panel x unchanged"
    CHECK_EQ32 r12d, esi, "creative panel y unchanged"
    dec   r13d
    jnz   .round
ENDP

PROC player_setup, 0
    call  h_reset
    OPEN  SCR_PLAYER
ENDP

PROC case_autorepeat_digits, 0
    TEST "review: auto-repeat digits ignored, Q repeats"
    call  player_setup
    SET_STK [rel INVS(9)], 1, 5, 0
    SET_STK [rel INVS(2)], 2, 3, 0
    HOVER G_MAIN, 9
    KEY   '3', 1
    CHECK_STK [rel INVS(9)], 1, 5, 0, "repeat digit ignored"
    KEY   '3'
    CHECK_STK [rel INVS(9)], 2, 3, 0, "digit swaps"
    KEY   'Q'
    KEY   'Q', 1
    CHECK_STK [rel INVS(9)], 2, 1, 0, "Q honours repeat"
    CHECK_EQ32 [rel fake_spawn_count], 2, "two throws"
ENDP
    ; v1 temporary guard (test_screens #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_screens #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_screens #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_screens #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_screens #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_screens #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_screens #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_screens #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_screens #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_screens #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_screens #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_screens #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_screens #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_screens #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_screens #50)
    xor     r11d, r11d ; clear v1 slot 50
