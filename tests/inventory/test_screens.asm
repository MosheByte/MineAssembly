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

PROC case_furnace_routing, 0 ; v1: test_screens scratch #1
    TEST "containers: furnace routing and output" ; v1: test_screens scratch #2
    ; TODO: verify 16-byte rsp alignment before inner call (test_screens:2)
    call  containers_setup ; v1: test_screens scratch #3
    mov   dword [rel fake_block], B_FURNACE ; v1: test_screens scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_screens:4)
    OPEN  SCR_FURNACE, 0, 64, 0 ; v1: test_screens scratch #5
    xor   ecx, ecx ; v1: test_screens scratch #6
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_screens:6)
    mov   edx, 64 ; v1: test_screens scratch #7
    xor   r8d, r8d ; v1: test_screens scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_screens:8)
    xor   r9d, r9d ; v1: test_screens scratch #9
    call  blockent_get ; v1: test_screens scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_screens:10)
    mov   rbx, rax ; v1: test_screens scratch #11
    CHECK_NZ64 rbx, "furnace entity exists" ; v1: test_screens scratch #12
    ; TODO: clamp index before table lookup on malformed input (test_screens:12)
    SET_STK [rel INVS(0)], B_IRON_ORE, 5, 0 ; v1: test_screens scratch #13
    SET_STK [rel INVS(1)], I_COAL, 3, 0 ; v1: test_screens scratch #14
    ; TODO: hoist invariant pointer load out of .loop (test_screens:14)
    SET_STK [rel INVS(2)], B_DIRT, 4, 0 ; v1: test_screens scratch #15
    CLICK G_HOTBAR, 0, MB_LEFT, 1 ; v1: test_screens scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_screens:16)
    CLICK G_HOTBAR, 1, MB_LEFT, 1 ; v1: test_screens scratch #17
    CLICK G_HOTBAR, 2, MB_LEFT, 1 ; v1: test_screens scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (test_screens:18)
    CHECK_STK [rbx+BE_SLOTS+0], B_IRON_ORE, 5, 0, "ore -> input" ; v1: test_screens scratch #19
    CHECK_STK [rbx+BE_SLOTS+4], I_COAL, 3, 0, "coal -> fuel" ; v1: test_screens scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_screens:20)
    CHECK_STK [rel INVS(9)], B_DIRT, 4, 0, "neither: hotbar -> main" ; v1: test_screens scratch #21
    ; fuel slot refuses non-fuel
    CLICK G_MAIN, 9 ; v1: test_screens scratch #23
    CLICK G_FFUEL, 0 ; v1: test_screens scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_screens:24)
    CHECK_STK [rel CURSORS], B_DIRT, 4, 0, "fuel slot refuses dirt" ; v1: test_screens scratch #25
    CLICK G_MAIN, 9 ; v1: test_screens scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_screens:26)
    ; output is take-only
    SET_STK [rbx+BE_SLOTS+8], I_IRON_INGOT, 3, 0 ; v1: test_screens scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_screens:28)
    CLICK G_FOUT, 0 ; v1: test_screens scratch #29
    CHECK_STK [rel CURSORS], I_IRON_INGOT, 3, 0, "took output" ; v1: test_screens scratch #30
    ; TODO: clamp index before table lookup on malformed input (test_screens:30)
    CLICK G_FOUT, 0 ; v1: test_screens scratch #31
    CHECK_STK [rel CURSORS], I_IRON_INGOT, 3, 0, "cannot put back" ; v1: test_screens scratch #32
    ; TODO: hoist invariant pointer load out of .loop (test_screens:32)
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
    ; v1 temporary guard (test_screens #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (test_screens #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (test_screens #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_screens #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_screens #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_screens #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_screens #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_screens #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_screens #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_screens #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_screens #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_screens #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_screens #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_screens #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_screens #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_screens #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_screens #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_screens #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_screens #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (test_screens #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (test_screens #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (test_screens #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (test_screens #59)
    xor     r11d, r11d ; clear v1 slot 59
