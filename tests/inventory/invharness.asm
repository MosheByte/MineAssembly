; invharness.asm - test env for the inventory tests: reset everything the
; modules read, rebuild the slot layout, and fake mouse/key input on slots.
%define IMPL_INVHARNESS
%include "common.inc"
%include "testlib.inc"
%include "../inventory/invtest.inc"   ; via the tests/lib/ include path

section .rdata
align 8
d_one:      dq 1.0
d_hundred:  dq 100.0
f_half:     dd 0.5
f_64:       dd 64.0
s_notfound: db "h_find: slot (group, idx) not in the layout", 0
s_harness:  db "invharness.asm", 0

section .bss
alignb 16
dummy_slot: resb SD_SIZE

section .text

; known state: 64-stacks with tools at 1, no fuel/smelt/durability, 427x240 ui,
; clock at 100 s, player at (0.5, 64, 0.5)
PROC h_reset, 0
    call  screens_close
    lea   rdi, [rel g_player]
    xor   eax, eax
    mov   ecx, 512
    rep   stosb
    lea   rdi, [rel item_max_stack]
    mov   al, 64
    mov   ecx, 256
    rep   stosb
    lea   rdi, [rel item_max_stack]
    mov   byte [rdi], 0
    lea   rdi, [rdi+I_PICK_WOOD]
    mov   al, 1
    mov   ecx, 20                       ; the 20 tool ids
    rep   stosb
    xor   eax, eax
    lea   rdi, [rel item_fuel]
    mov   ecx, 512
    rep   stosb
    lea   rdi, [rel item_durability]
    mov   ecx, 512
    rep   stosb
    lea   rdi, [rel item_smelt]
    mov   ecx, 256
    rep   stosb
    lea   rdi, [rel item_creative_list]
    mov   ecx, 256
    rep   stosb
    lea   rdi, [rel g_keys]
    mov   ecx, 256
    rep   stosb
    lea   rdi, [rel g_keys_pressed]
    mov   ecx, 256
    rep   stosb
    mov   dword [rel g_ui_scale], 0       ; 0 = take g_ui_mx/my as the tests set them
    call  blockent_clear
    mov   dword [rel g_gamemode], GM_SURVIVAL
    mov   dword [rel g_ui_w], 427
    mov   dword [rel g_ui_h], 240
    mov   dword [rel g_mouse_buttons], 0
    mov   dword [rel g_char_count], 0
    mov   dword [rel fake_setraw_count], 0
    mov   dword [rel fake_light_count], 0
    mov   dword [rel fake_spawn_count], 0
    mov   dword [rel fake_spawn_items], 0
    mov   dword [rel fake_block], 0
    movsd xmm0, [rel d_hundred]
    movsd [rel g_time_total], xmm0
    movss xmm0, [rel f_half]
    movss xmm1, [rel f_64]
    movss xmm2, [rel f_half]
    call  h_set_pos
ENDP

LEAF h_set_pos
    lea   rax, [rel g_player]
    movss [rax+P_X], xmm0
    movss [rax+P_Y], xmm1
    movss [rax+P_Z], xmm2
    ret

PROC h_layout, 0
    call  screens_render
    mov   eax, [rel scr_nslots]
ENDP

; missing slot = test failure, but hand back a zeroed dummy so the caller
; doesn't fault on the way to reporting it
PROC h_find, 0
    mov   ebx, ecx
    mov   esi, edx
    call  screens_render
    mov   ecx, [rel scr_nslots]
    lea   rax, [rel scr_slots]
    test  ecx, ecx
    jle   .miss
.loop:
    movzx edx, byte [rax+SD_GROUP]
    cmp   edx, ebx
    jne   .next
    movzx edx, word [rax+SD_IDX]
    cmp   edx, esi
    je    .done
.next:
    add   rax, SD_SIZE
    dec   ecx
    jnz   .loop
.miss:
    lea   rcx, [rel s_notfound]
    lea   rdx, [rel s_harness]
    mov   r8d, __?LINE?__
    call  t_fail
    lea   rax, [rel dummy_slot]
.done:
ENDP

PROC h_hover, 0
    call  h_find
    movsx ecx, word [rax+SD_X]
    movsx edx, word [rax+SD_Y]
    add   ecx, 9
    add   edx, 9
    mov   [rel g_ui_mx], ecx
    mov   [rel g_ui_my], edx
ENDP

LEAF h_mouse_at
    mov   [rel g_ui_mx], ecx
    mov   [rel g_ui_my], edx
    ret

; bumps the clock 1 s first so two clicks never read as a double-click
PROC h_click, 0
    mov   r12d, r8d
    mov   r13d, r9d
    call  h_hover
    xor   eax, eax
    test  r13d, r13d
    setnz al
    lea   rcx, [rel g_keys]
    mov   [rcx+VK_SHIFT_], al
    movsd xmm0, [rel g_time_total]
    addsd xmm0, [rel d_one]
    movsd [rel g_time_total], xmm0
    mov   [rel g_mouse_buttons], r12d
    mov   ecx, r12d
    mov   edx, 1
    call  screens_on_mouse
    mov   dword [rel g_mouse_buttons], 0
    mov   ecx, r12d
    xor   edx, edx
    call  screens_on_mouse
    lea   rcx, [rel g_keys]
    mov   byte [rcx+VK_SHIFT_], 0
ENDP

PROC h_press, 0
    mov   [rel g_mouse_buttons], ecx
    mov   edx, 1
    call  screens_on_mouse
ENDP

PROC h_release, 0
    mov   dword [rel g_mouse_buttons], 0
    xor   edx, edx
    call  screens_on_mouse
ENDP

PROC h_move, 0
    call  h_hover
    call  screens_render
ENDP

; same shape as game_on_key forwards a WM_KEYDOWN
PROC h_key, 0
    mov   ebx, ecx
    xor   eax, eax
    test  edx, edx
    sete  al                            ; auto-repeat isn't "pressed this frame"
    lea   rsi, [rel g_keys_pressed]
    mov   [rsi+rbx], al
    call  screens_on_key
    mov   byte [rsi+rbx], 0
ENDP

PROC h_count_group, 0
    mov   ebx, ecx
    call  screens_render
    mov   ecx, [rel scr_nslots]
    lea   rdx, [rel scr_slots]
    xor   eax, eax
    test  ecx, ecx
    jle   .done
.loop:
    movzx r8d, byte [rdx+SD_GROUP]
    cmp   r8d, ebx
    jne   .next
    inc   eax
.next:
    add   rdx, SD_SIZE
    dec   ecx
    jnz   .loop
.done:
ENDP

PROC h_cells, 0
    mov   rbx, rcx
    call  screens_render
    mov   ecx, [rel scr_nslots]
    lea   rdx, [rel scr_slots]
    xor   eax, eax
    test  ecx, ecx
    jle   .done
.loop:
    cmp   byte [rdx+SD_GROUP], G_CGRID
    jne   .next
    movzx r8d, word [rdx+SD_IDX]
    mov   [rbx+rax*2], r8w
    inc   eax
.next:
    add   rdx, SD_SIZE
    dec   ecx
    jnz   .loop
.done:
ENDP

PROC h_panel, 192
    lea   rcx, LOC(0)
    call  h_cells
    movzx edx, word LOC(0)
    mov   ecx, G_CGRID
    call  h_find
    movsx ecx, word [rax+SD_X]
    movsx edx, word [rax+SD_Y]
    lea   eax, [rcx-8]
    sub   edx, 17
ENDP

LEAF h_set_name
    movzx ecx, cl
    lea   rax, [rel item_name]
    mov   [rax+rcx*8], rdx
    ret
