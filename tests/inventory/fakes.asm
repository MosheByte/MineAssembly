; fakes.asm - stand-ins for other modules, @linked into every inventory test.
; tiny recipe book, a one-value world, and call counters for light/spawn.
bits 64
default rel

global craft_match, world_get_block, world_is_loaded, world_set_block_raw
global light_on_block_changed, entity_spawn_item
global fake_block, fake_setraw_count, fake_light_count, fake_light_old
global fake_spawn_count, fake_spawn_items, fake_entity, fake_last_spawn_id

section .bss
alignb 16
fake_block:          resd 1
fake_setraw_count:   resd 1
fake_light_count:    resd 1
fake_light_old:      resd 1
fake_spawn_count:    resd 1
fake_spawn_items:    resd 1
fake_last_spawn_id:  resd 1
alignb 16
fake_entity:         resb 128

section .text
; knows exactly 3 recipes: 1 log -> 4 planks, 2 planks -> 4 sticks, 4 planks -> table
craft_match:
    xor   r8d, r8d              ; occupied cells
    xor   r9d, r9d              ; logs
    xor   r10d, r10d            ; planks
    xor   r11d, r11d
.loop:
    movzx eax, byte [rcx+r11]
    test  eax, eax
    jz    .next
    inc   r8d
    cmp   eax, 9
    jne   .np
    inc   r9d
.np:
    cmp   eax, 5
    jne   .next
    inc   r10d
.next:
    inc   r11d
    cmp   r11d, 9
    jb    .loop
    cmp   r8d, 1
    jne   .two
    cmp   r9d, 1
    jne   .none
    mov   eax, 5
    mov   edx, 4
    ret
.two:
    cmp   r8d, 2
    jne   .four
    cmp   r10d, 2
    jne   .none
    mov   eax, 128
    mov   edx, 4
    ret
.four:
    cmp   r8d, 4
    jne   .none
    cmp   r10d, 4
    jne   .none
    mov   eax, 29
    mov   edx, 1
    ret
.none:
    xor   eax, eax
    xor   edx, edx
    ret

world_get_block:
    mov   eax, [rel fake_block]
    ret
world_is_loaded:
    mov   eax, 1
    ret
world_set_block_raw:
    mov   [rel fake_block], r9d
    inc   dword [rel fake_setraw_count]
    mov   eax, 1
    ret
light_on_block_changed:
    inc   dword [rel fake_light_count]
    mov   [rel fake_light_old], r9d
    ret
entity_spawn_item:
    inc   dword [rel fake_spawn_count]
    add   [rel fake_spawn_items], edx
    mov   [rel fake_last_spawn_id], ecx
    lea   rax, [rel fake_entity]
    ret
