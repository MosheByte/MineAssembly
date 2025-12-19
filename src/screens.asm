; screens.asm - container GUIs (inventory, crafting, furnace, chest, creative)
; a screen is just a slot table that scr_layout rebuilds every frame and on every
; input event. drawing and hit-testing walk the same table, so what you see and
; what you click can't drift apart
%define IMPL_SCREENS
%include "common.inc"

extern inv_stack_max, inv_put_core, inv_move_range, inv_capacity

; ptr 0 = no STACK. for creative cells idx is the item id
struc SLOTDEF
    .x      resw 1
    .y      resw 1
    .group  resb 1
    .flags  resb 1
    .idx    resw 1
    .ptr    resq 1
endstruc                                ; 16 bytes, scr_add/scr_sd shift by 4

%define MAX_SLOTS       96
%define SF_BIG          1

%define G_HOTBAR        1
%define G_MAIN          2
%define G_CRAFT         3
%define G_CHEST         4
%define G_FIN           5
%define G_FFUEL         6
%define G_LAST_NORMAL   6
%define G_RESULT        7
%define G_FOUT          8
%define G_CGRID         9
%define G_TRASH         10

%define COL_TITLE       0xFF404040
%define SEARCH_MAX      14
%define CR_COLS         9
%define CR_ROWS         5
%define TAB_SHIFT       11              ; panel moves down to make room for tabs

%define CR_SEARCH_X     80
%define CR_SEARCH_Y     4
%define CR_SEARCH_W     90
%define CR_SEARCH_H     11
%define CR_SB_X         174
%define CR_SB_Y         17
%define CR_SB_W         12
%define CR_SB_H         90
%define CR_THUMB_H      15

; same as PROC, just not global
%macro PPROC 1-2 0
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

; draw helpers relative to the panel, they expect r12d = px, r13d = py
%macro PRECT 5
    mov  dword [rsp+32], %5
    mov  r9d, %4
    mov  r8d, %3
    lea  edx, [r13+(%2)]
    lea  ecx, [r12+(%1)]
    call ui_rect
%endmacro
%macro PTEXT 4
    mov  r9d, %4
    lea  r8, [rel %3]
    lea  edx, [r13+(%2)]
    lea  ecx, [r12+(%1)]
    call ui_text
%endmacro
%macro ADDGRID 7                        ; x, y, cols, rows, group, first idx, [ptr]
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    mov  dword [rsp+32], %5
    mov  dword [rsp+40], %6
    lea  rax, %7
    mov  [rsp+48], rax
    call scr_add_grid
%endmacro
%macro ADDSLOT 4                        ; x, y, group|flags<<8|idx<<16, [ptr]
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    lea  r9, %4
    call scr_add
%endmacro
; lowercase it and treat '_' as ' ', for the search compare
%macro FOLD 1
    cmp  %1, 'A'
    jb   %%n
    cmp  %1, 'Z'
    ja   %%u
    add  %1, 32
    jmp  %%n
%%u:
    cmp  %1, '_'
    jne  %%n
    mov  %1, ' '
%%n:
%endmacro

section .bss
alignb 16
global scr_slots, scr_nslots            ; the tests poke at these
scr_slots:          resb SLOTDEF_size * MAX_SLOTS
scr_nslots:         resd 1
scr_open:           resd 1
scr_be:             resq 1              ; open furnace/chest
scr_bx:             resd 1
scr_by:             resd 1
scr_bz:             resd 1
scr_px:             resd 1              ; panel rectangle (UI px)
scr_py:             resd 1
scr_pw:             resd 1
scr_ph:             resd 1
scr_scroll:         resd 1              ; first visible row
scr_maxscroll:      resd 1
scr_nfilter:        resd 1
scr_scroll_drag:    resd 1
scr_search_len:     resd 1
scr_search_focus:   resd 1
scr_drag_mode:      resd 1              ; 0 none, 1 left spread, 2 right paint
scr_drag_n:         resd 1
scr_last_slot:      resd 1
scr_last_pickup:    resd 1
alignb 8
scr_last_time:      resq 1              ; double, time of the last left click
scr_look:           resd 4
scr_search:         resb 32
scr_filter:         resb 256
scr_drag_list:      resb MAX_SLOTS
scr_tip:            resb 192

section .rdata
align 4
scr_sizes:      dw 176,166, 176,166, 176,166, 176,168, 195,136   ; per SCR_*
f_half:         dd 0.5
f_one:          dd 1.0
f_maxdist2:     dd 64.0                 ; 8 blocks, squared
f_drop_off:     dd 0.3
f_drop_y:       dd 1.32
f_throw:        dd 0.32
f_throw_up:     dd 0.1
f_click_vol:    dd 0.5
f_chest_vol:    dd 0.7
align 8
d_dclick:       dq 0.3                  ; double-click window (seconds)
d_blink:        dq 2.5

; flame height per column, bottom aligned
flame_h:        db 3,6,9,11,12,13,14,14,13,12,11,9,6,3

; mini player: dx, dy, size, tile (from centre/top), size 0 ends the list
fig_parts:
    db -7,14,14,T_PLAYER_SHIRT,   -7,21,14,T_PLAYER_SHIRT
    db -14,14,7,T_PLAYER_SHIRT,  -14,21,7,T_PLAYER_SKIN,  -14,28,7,T_PLAYER_SKIN
    db   7,14,7,T_PLAYER_SHIRT,    7,21,7,T_PLAYER_SKIN,    7,28,7,T_PLAYER_SKIN
    db  -7,35,7,T_PLAYER_PANTS,   -7,42,7,T_PLAYER_PANTS,  -7,49,7,T_PLAYER_PANTS
    db   0,35,7,T_PLAYER_PANTS,    0,42,7,T_PLAYER_PANTS,   0,49,7,T_PLAYER_PANTS
    db   0,0,0,0

s_crafting:     db "Crafting",0
s_inventory:    db "Inventory",0
s_furnace:      db "Furnace",0
s_chest:        db "Chest",0
s_creative:     db "Creative",0
s_search_hint:  db "Search...",0
s_caret:        db "_",0
s_destroy:      db "Destroy Item",0
s_tab_items:    db "Creative Items",0
s_tab_inv:      db "Survival Inventory",0
fmt_dur:        db "%s ",12,"7(%d/%d)",0
fmt_burn:       db "Fuel: %d s",0
fmt_cook:       db "Smelting: %d%%",0

section .text

; r8d = group | flags<<8 | idx<<16
scr_add:
    mov   eax, [rel scr_nslots]
    cmp   eax, MAX_SLOTS
    jae   .full
    lea   r10, [rel scr_slots]
    mov   r11d, eax
    shl   r11, 4
    add   r10, r11
    add   ecx, [rel scr_px]
    add   edx, [rel scr_py]
    mov   [r10+SLOTDEF.x], cx
    mov   [r10+SLOTDEF.y], dx
    mov   [r10+SLOTDEF.group], r8b
    mov   r11d, r8d
    shr   r11d, 8
    mov   [r10+SLOTDEF.flags], r11b
    shr   r8d, 16
    mov   [r10+SLOTDEF.idx], r8w
    mov   [r10+SLOTDEF.ptr], r9
    inc   eax
    mov   [rel scr_nslots], eax
.full:
    ret

; ARG7 = STACK* of the first slot, the rest follow it
PPROC scr_add_grid, 16
    mov   r12d, ecx
    mov   r13d, edx
    mov   r14d, r8d
    mov   r15d, r9d
    mov   esi, ARG6
    mov   rbx, ARG7
    xor   edi, edi
.row:
    cmp   edi, r15d
    jge   .done
    mov   dword LOC(0), 0
.col:
    mov   eax, LOC(0)
    cmp   eax, r14d
    jge   .next_row
    imul  ecx, eax, 18
    add   ecx, r12d
    imul  edx, edi, 18
    add   edx, r13d
    mov   r8d, esi
    shl   r8d, 16
    or    r8d, ARG5
    mov   r9, rbx
    call  scr_add
    inc   esi
    add   rbx, 4
    inc   dword LOC(0)
    jmp   .col
.next_row:
    inc   edi
    jmp   .row
.done:
ENDP

PPROC scr_add_player_inv, 0
    mov   ebx, ecx
    mov   esi, edx
    lea   r12, [rel g_player]
    ADDGRID ebx, esi, 9, 3, G_MAIN, 9, [r12+PLAYER.inv+9*4]
    lea   eax, [rsi+58]
    ADDGRID ebx, eax, 9, 1, G_HOTBAR, 0, [r12+PLAYER.inv]
ENDP

scr_sd:
    mov   eax, ecx
    shl   rax, 4
    lea   rcx, [rel scr_slots]
    add   rax, rcx
    ret

scr_tabs_visible:
    xor   eax, eax
    cmp   dword [rel g_gamemode], GM_CREATIVE
    jne   .ret
    mov   ecx, [rel g_screen_kind]
    cmp   ecx, SCR_PLAYER
    je    .yes
    cmp   ecx, SCR_CREATIVE
    jne   .ret
.yes:
    mov   eax, 1
.ret:
    ret

scr_in_rect:
    mov   eax, [rel g_ui_mx]
    mov   r10d, [rel g_ui_my]
    cmp   eax, ecx
    jl    .no
    add   ecx, r8d
    cmp   eax, ecx
    jge   .no
    cmp   r10d, edx
    jl    .no
    add   edx, r9d
    cmp   r10d, edx
    jge   .no
    mov   eax, 1
    ret
.no:
    xor   eax, eax
    ret

scr_tab_at:
    call  scr_tabs_visible
    test  eax, eax
    jz    .none
    mov   ecx, [rel g_ui_mx]
    mov   edx, [rel g_ui_my]
    mov   r8d, [rel scr_py]
    cmp   edx, r8d
    jge   .none
    sub   r8d, 21
    cmp   edx, r8d
    jl    .none
    mov   r8d, [rel scr_px]
    add   r8d, 2
    sub   ecx, r8d
    jl    .none
    mov   eax, ecx
    xor   edx, edx
    mov   r9d, 30
    div   r9d                       ; eax = tab, edx = offset inside the 30 px pitch
    cmp   edx, 28
    jae   .none
    cmp   eax, 2
    jae   .none
    ret
.none:
    mov   eax, -1
    ret

scr_slot_at:
    lea   r8, [rel scr_slots]
    mov   r9d, [rel scr_nslots]
    xor   eax, eax
.loop:
    cmp   eax, r9d
    jge   .none
    movsx r10d, word [r8+SLOTDEF.x]
    movsx r11d, word [r8+SLOTDEF.y]
    test  byte [r8+SLOTDEF.flags], SF_BIG
    jnz   .big
    cmp   ecx, r10d
    jl    .next
    cmp   edx, r11d
    jl    .next
    add   r10d, 18
    add   r11d, 18
    jmp   .test_far
.big:
    sub   r10d, 4
    sub   r11d, 4
    cmp   ecx, r10d
    jl    .next
    cmp   edx, r11d
    jl    .next
    add   r10d, 26
    add   r11d, 26
.test_far:
    cmp   ecx, r10d
    jge   .next
    cmp   edx, r11d
    jge   .next
    ret
.next:
    add   r8, SLOTDEF_size
    inc   eax
    jmp   .loop
.none:
    mov   eax, -1
    ret

scr_shift:
    lea   rax, [rel g_keys]
    movzx ecx, byte [rax+VK_SHIFT]
    or    cl, [rax+VK_LSHIFT]
    or    cl, [rax+VK_LSHIFT+1]
    movzx eax, cl
    ret
scr_ctrl:
    lea   rax, [rel g_keys]
    movzx ecx, byte [rax+VK_CONTROL]
    or    cl, [rax+VK_LCONTROL]
    or    cl, [rax+VK_LCONTROL+1]
    movzx eax, cl
    ret

; case-insensitive, '_' matches ' '. dumb O(n*m) but the strings are tiny
scr_istr:
.outer:
    mov   r8, rcx
    mov   r9, rdx
.inner:
    movzx eax, byte [r9]
    test  eax, eax
    jz    .found
    movzx r10d, byte [r8]
    test  r10d, r10d
    jz    .nope
    FOLD  eax
    FOLD  r10d
    cmp   eax, r10d
    jne   .advance
    inc   r8
    inc   r9
    jmp   .inner
.advance:
    inc   rcx
    jmp   .outer
.found:
    mov   eax, 1
    ret
.nope:
    xor   eax, eax
    ret

; events come from platform_pump before ui_begin converts the mouse, so
; g_ui_mx/my are still last frame's here. redo the divide or a quick click
; lands on the slot you were over a frame ago. scale 0 = nothing drawn yet
scr_refresh_mouse:
    mov   ecx, [rel g_ui_scale]
    test  ecx, ecx
    jle   .ret
    mov   eax, [rel g_mouse_x]
    cdq
    idiv  ecx
    mov   [rel g_ui_mx], eax
    mov   eax, [rel g_mouse_y]
    cdq
    idiv  ecx
    mov   [rel g_ui_my], eax
.ret:
    ret

scr_clamp_scroll:
    mov   eax, [rel scr_scroll]
    mov   ecx, [rel scr_maxscroll]
    cmp   eax, ecx
    jle   .hi_ok
    mov   eax, ecx
.hi_ok:
    test  eax, eax
    jns   .lo_ok
    xor   eax, eax
.lo_ok:
    mov   [rel scr_scroll], eax
    ret

; thumb follows the mouse
scr_scroll_set:
    mov   eax, edx
    sub   eax, [rel scr_py]
    sub   eax, CR_SB_Y + CR_THUMB_H/2
    imul  eax, [rel scr_maxscroll]
    add   eax, (CR_SB_H - CR_THUMB_H)/2         ; round to nearest row
    cdq
    mov   ecx, CR_SB_H - CR_THUMB_H
    idiv  ecx
    mov   [rel scr_scroll], eax
    jmp   scr_clamp_scroll

PPROC scr_rebuild_filter, 0
    lea   rbx, [rel item_creative_list]
    xor   esi, esi
.loop:
    movzx edi, byte [rbx]
    test  edi, edi
    jz    .end
    inc   rbx
    cmp   dword [rel scr_search_len], 0
    je    .add
    lea   rax, [rel item_name]
    mov   rcx, [rax+rdi*8]
    test  rcx, rcx
    jz    .loop
    lea   rdx, [rel scr_search]
    call  scr_istr
    test  eax, eax
    jz    .loop
.add:
    lea   rax, [rel scr_filter]
    mov   [rax+rsi], dil
    inc   esi
    cmp   esi, 255
    jb    .loop
.end:
    mov   [rel scr_nfilter], esi
    lea   eax, [rsi+CR_COLS-1]
    xor   edx, edx
    mov   ecx, CR_COLS
    div   ecx
    sub   eax, CR_ROWS
    jge   .max_ok
    xor   eax, eax
.max_ok:
    mov   [rel scr_maxscroll], eax
    call  scr_clamp_scroll
ENDP

PPROC scr_layout, 0
    mov   dword [rel scr_nslots], 0
    mov   ebx, [rel g_screen_kind]
    cmp   ebx, SCR_CREATIVE
    jbe   .kind_ok
    xor   ebx, ebx
.kind_ok:
    lea   rcx, [rel scr_sizes]
    movzx edx, word [rcx+rbx*4]
    movzx r8d, word [rcx+rbx*4+2]
    mov   [rel scr_pw], edx
    mov   [rel scr_ph], r8d
    call  scr_tabs_visible          ; leaf: clobbers only eax/ecx
    test  eax, eax
    jnz   .tab_origin
    mov   eax, [rel g_ui_w]
    sub   eax, edx
    sar   eax, 1
    mov   [rel scr_px], eax
    mov   esi, [rel g_ui_h]
    sub   esi, r8d
    sar   esi, 1
    jmp   .origin_done
.tab_origin:
    ; item browser and survival inv share the SAME origin so the tab row
    ; doesn't jump when you switch. creative panel centred + TAB_SHIFT, raised
    ; if the taller survival panel wouldn't fit
    lea   rcx, [rel scr_sizes]
    mov   eax, [rel g_ui_w]
    movzx r9d, word [rcx+SCR_CREATIVE*4]
    sub   eax, r9d
    sar   eax, 1
    mov   [rel scr_px], eax
    mov   esi, [rel g_ui_h]
    movzx r9d, word [rcx+SCR_CREATIVE*4+2]
    sub   esi, r9d
    sar   esi, 1
    add   esi, TAB_SHIFT
    mov   eax, [rel g_ui_h]
    movzx r9d, word [rcx+SCR_PLAYER*4+2]
    sub   eax, r9d                  ; lowest y that keeps the survival panel on screen
    cmp   esi, eax
    cmovg esi, eax
.origin_done:
    mov   [rel scr_py], esi
    lea   r12, [rel g_player]
    mov   rdi, [rel scr_be]

    cmp   ebx, SCR_CRAFTING
    je    .crafting
    cmp   ebx, SCR_FURNACE
    je    .furnace
    cmp   ebx, SCR_CHEST
    je    .chest
    cmp   ebx, SCR_CREATIVE
    je    .creative

    ; player inv: the 2x2 grid is craft slots 0,1 / 3,4
    ADDGRID 87, 17, 2, 1, G_CRAFT, 0, [r12+PLAYER.craft]
    ADDGRID 87, 35, 2, 1, G_CRAFT, 3, [r12+PLAYER.craft+3*4]
    ADDSLOT 152, 26, G_RESULT, [r12+PLAYER.craft_out]
    mov   ecx, 7
    mov   edx, 83
    call  scr_add_player_inv
    jmp   .done

.crafting:
    ADDGRID 29, 16, 3, 3, G_CRAFT, 0, [r12+PLAYER.craft]
    ADDSLOT 123, 34, G_RESULT | (SF_BIG << 8), [r12+PLAYER.craft_out]
    mov   ecx, 7
    mov   edx, 83
    call  scr_add_player_inv
    jmp   .done

.furnace:
    test  rdi, rdi
    jz    .furnace_inv
    ADDSLOT 55, 16, G_FIN, [rdi+BLOCKENT.slots]
    ADDSLOT 55, 52, G_FFUEL, [rdi+BLOCKENT.slots+4]
    ADDSLOT 115, 34, G_FOUT | (SF_BIG << 8), [rdi+BLOCKENT.slots+8]
.furnace_inv:
    mov   ecx, 7
    mov   edx, 83
    call  scr_add_player_inv
    jmp   .done

.chest:
    test  rdi, rdi
    jz    .chest_inv
    ADDGRID 7, 17, 9, 3, G_CHEST, 0, [rdi+BLOCKENT.slots]
.chest_inv:
    mov   ecx, 7
    mov   edx, 85
    call  scr_add_player_inv
    jmp   .done

.creative: ; v1: screens scratch #0
    ; FIXME: negative world x/z needs sar 4, not shr 4 (screens:0)
    call  scr_rebuild_filter ; v1: screens scratch #1
    xor   esi, esi ; v1: screens scratch #2
    ; TODO: hoist invariant pointer load out of .loop (screens:2)
.cell: ; v1: screens scratch #3
    mov   eax, [rel scr_scroll] ; v1: screens scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (screens:4)
    imul  eax, eax, CR_COLS ; v1: screens scratch #5
    add   eax, esi ; v1: screens scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (screens:6)
    xor   r8d, r8d ; v1: screens scratch #7
    cmp   eax, [rel scr_nfilter] ; v1: screens scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (screens:8)
    jae   .cell_set ; v1: screens scratch #9
    lea   rcx, [rel scr_filter] ; v1: screens scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (screens:10)
    movzx r8d, byte [rcx+rax] ; v1: screens scratch #11
.cell_set: ; v1: screens scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (screens:12)
    shl   r8d, 16 ; v1: screens scratch #13
    or    r8d, G_CGRID ; v1: screens scratch #14
    ; TODO: clamp index before table lookup on malformed input (screens:14)
    mov   eax, esi ; v1: screens scratch #15
    xor   edx, edx ; v1: screens scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (screens:16)
    mov   ecx, CR_COLS ; v1: screens scratch #17
    div   ecx ; v1: screens scratch #18
    ; TODO: hoist invariant pointer load out of .loop (screens:18)
    imul  ecx, edx, 18 ; v1: screens scratch #19
    add   ecx, 8 ; v1: screens scratch #20
    ; temp: spill r12/r13 across helper call until reg alloc pass (screens:20)
    imul  edx, eax, 18 ; v1: screens scratch #21
    add   edx, 17 ; v1: screens scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (screens:22)
    xor   r9d, r9d ; v1: screens scratch #23
    call  scr_add ; v1: screens scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (screens:24)
    inc   esi ; v1: screens scratch #25
    cmp   esi, CR_COLS*CR_ROWS ; v1: screens scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (screens:26)
    jb    .cell ; v1: screens scratch #27
    ADDGRID 8, 111, 9, 1, G_HOTBAR, 0, [r12+PLAYER.inv] ; v1: screens scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (screens:28)
    mov   ecx, 173 ; v1: screens scratch #29
    mov   edx, 111 ; v1: screens scratch #30
    ; TODO: clamp index before table lookup on malformed input (screens:30)
    mov   r8d, G_TRASH ; v1: screens scratch #31
    xor   r9d, r9d ; v1: screens scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (screens:32)
    call  scr_add ; v1: screens scratch #33
.done: ; v1: screens scratch #34
    ; TODO: hoist invariant pointer load out of .loop (screens:34)
ENDP ; v1: screens scratch #35

PPROC scr_craft_update, 16 ; v1: screens scratch #37
    lea   rbx, [rel g_player] ; v1: screens scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (screens:38)
    mov   qword LOC(0), 0 ; v1: screens scratch #39
    mov   qword LOC(8), 0 ; v1: screens scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (screens:40)
    mov   eax, [rel g_screen_kind] ; v1: screens scratch #41
    mov   r12d, 0x1FF ; v1: screens scratch #42
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (screens:42)
    cmp   eax, SCR_CRAFTING ; v1: screens scratch #43
    je    .copy ; v1: screens scratch #44
    ; note: rcx = state ptr, rdx = index, r8d = flags (screens:44)
    mov   r12d, 0x1B ; v1: screens scratch #45
    cmp   eax, SCR_PLAYER ; v1: screens scratch #46
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (screens:46)
    jne   .none
.copy:
    xor   ecx, ecx
    xor   esi, esi
.cl:
    bt    r12d, ecx
    jnc   .cn
    movzx eax, byte [rbx+PLAYER.craft+rcx*4]
    mov   [rsp+FRAME_OUT+rcx], al
    or    esi, eax
.cn:
    inc   ecx
    cmp   ecx, 9
    jb    .cl
    test  esi, esi
    jz    .none
    lea   rcx, LOC(0)
    call  craft_match
    test  eax, eax
    jz    .none
    test  edx, edx
    jg    .cnt_pos
    mov   edx, 1
.cnt_pos:
    cmp   edx, 64
    jbe   .cnt_ok
    mov   edx, 64
.cnt_ok:
    mov   [rbx+PLAYER.craft_out+STACK.id], al
    mov   [rbx+PLAYER.craft_out+STACK.count], dl
    mov   word [rbx+PLAYER.craft_out+STACK.damage], 0
    jmp   .done
.none:
    mov   dword [rbx+PLAYER.craft_out], 0
.done:
ENDP

scr_consume_grid:
    mov   eax, [rel g_screen_kind]
    mov   r8d, 0x1FF
    cmp   eax, SCR_CRAFTING
    je    .go
    mov   r8d, 0x1B
    cmp   eax, SCR_PLAYER
    jne   .ret
.go:
    lea   rdx, [rel g_player+PLAYER.craft]
    xor   ecx, ecx
.loop:
    bt    r8d, ecx
    jnc   .next
    movzx eax, byte [rdx+rcx*4+STACK.id]
    test  eax, eax
    jz    .next
    dec   byte [rdx+rcx*4+STACK.count]
    jnz   .next
    cmp   eax, I_WATER_BUCKET
    je    .bucket
    cmp   eax, I_LAVA_BUCKET
    je    .bucket
    mov   dword [rdx+rcx*4], 0
    jmp   .next
.bucket:
    mov   dword [rdx+rcx*4], I_BUCKET | (1 << 8)
.next:
    inc   ecx
    cmp   ecx, 9
    jb    .loop
.ret:
    ret

PPROC scr_take_result, 0
    xor   r12d, r12d
    lea   rbx, [rel g_player]
    movzx esi, byte [rbx+PLAYER.craft_out+STACK.id]
    test  esi, esi
    jz    .done
    movzx ecx, byte [rbx+PLAYER.cursor+STACK.id]
    test  ecx, ecx
    jz    .take
    cmp   ecx, esi
    jne   .done
    call  inv_stack_max
    movzx edx, byte [rbx+PLAYER.cursor+STACK.count]
    movzx ecx, byte [rbx+PLAYER.craft_out+STACK.count]
    add   edx, ecx
    cmp   edx, eax
    ja    .done                     ; won't fit on the cursor
    mov   [rbx+PLAYER.cursor+STACK.count], dl
    jmp   .consume
.take:
    mov   eax, [rbx+PLAYER.craft_out]
    mov   [rbx+PLAYER.cursor], eax
.consume:
    call  scr_consume_grid
    call  scr_craft_update
    mov   r12d, 1
.done:
    mov   eax, r12d
ENDP
    ; v1 temporary guard (screens #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (screens #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (screens #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (screens #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (screens #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (screens #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (screens #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (screens #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (screens #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (screens #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (screens #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (screens #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (screens #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (screens #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (screens #51)
    xor     r11d, r11d ; clear v1 slot 51
