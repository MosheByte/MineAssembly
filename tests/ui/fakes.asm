; fakes for test_review only: record what ui asked for so the test can look at it.
; terrain is flat, stone below fake_ground and air above.
bits 64
default rel

extern g_state
global game_set_state, world_get_block, entity_spawn, world_is_loaded
global fake_last_state, fake_state_calls, fake_spawn_y, fake_spawn_count, fake_ground
global fake_loaded

section .data
align 4
fake_ground:        dd 70
fake_loaded:        dd 1

section .bss
alignb 16
fake_last_state:    resd 1
fake_state_calls:   resd 1
fake_spawn_y:       resd 1
fake_spawn_count:   resd 1
fake_ent:           resb 128

section .text
game_set_state:
    mov  [rel fake_last_state], ecx
    mov  [rel g_state], ecx
    inc  dword [rel fake_state_calls]
    ret

world_get_block:
    xor  eax, eax
    cmp  edx, [rel fake_ground]
    jge  .r
    mov  eax, 1                         ; B_STONE
.r: ret

entity_spawn:                           ; y comes in xmm2
    movss [rel fake_spawn_y], xmm2
    inc  dword [rel fake_spawn_count]
    lea  rax, [rel fake_ent]
    ret

world_is_loaded:
    mov  eax, [rel fake_loaded]
    ret
