; mcplay join + serverbound handling with the real packet writer/reader
; (mcproto) and a fake socket that records every frame. checks the packet id
; sequences, the conn state it leaves behind, and writes frames.bin
; (u8 conn, u32 len, body) so every field can be decoded and checked
; against the 26.1 wire layout.
; @link src/mcplay.asm src/mcproto.asm src/blocks.asm src/items.asm
; @link src/util.asm src/math.asm
; @timeout 30
%define IMPL_NET
%define IMPL_MCMAP
%define IMPL_PLATFORM               ; we provide mem_alloc/mem_free, the rest gets stubbed
%include "common.inc"
%include "net.inc"
%include "mcpackets.inc"
%include "testlib.inc"

%define MAXF 256

section .rdata
s_alex:     db "Alex", 0
s_steve:    db "Steve", 0
s_host:     db "Notch", 0
s_frames:   db "frames.bin", 0

; serverbound bodies, id first
p_tpc:      db MCP_PLAY_C2S_TELEPORT_CONFIRM, 1
p_tpc_end:
p_poslook:  db MCP_PLAY_C2S_POSITION_LOOK
            db 0x40,0x25,0,0,0,0,0,0        ; 10.5
            db 0x40,0x51,0x80,0,0,0,0,0     ; 70
            db 0xC0,0x0A,0,0,0,0,0,0        ; -3.25
            db 0x42,0xB4,0,0, 0x41,0x20,0,0 ; yaw 90 pitch 10
            db 1
p_poslook_end:
p_chat:     db MCP_PLAY_C2S_CHAT_MESSAGE, 2, "hi"
            dq 0, 0
            db 0, 0, 0,0,0, 0
p_chat_end:
p_cmd:      db MCP_PLAY_C2S_CHAT_COMMAND, 4, "list"
p_cmd_end:
p_slot:     db MCP_PLAY_C2S_SET_CREATIVE_SLOT, 0, 36, 1, 5, 0, 0
p_slot_end:
p_held:     db MCP_PLAY_C2S_HELD_ITEM_SLOT, 0, 0
p_held_end:
p_place:    db MCP_PLAY_C2S_BLOCK_PLACE, 0
            db 0,0,0,0,0,0,0,0x40           ; 0,64,0
            db 1
            db 0x3F,0,0,0, 0x3F,0,0,0, 0x3F,0,0,0
            db 0, 0, 7
p_place_end:
p_dig:      db MCP_PLAY_C2S_BLOCK_DIG, 0
            db 0,0,0,0x40,0,0,0x1F,0xF6     ; 1,-10,1
            db 1, 8
p_dig_end:
p_ka:       db MCP_PLAY_C2S_KEEP_ALIVE, 0,0,0,0,0,0,0,0
p_ka_end:
p_swing:    db MCP_PLAY_C2S_ARM_ANIMATION, 0
p_swing_end:

; expected (conn, id) per step
e_join0:    db 0, MCP_PLAY_S2C_LOGIN, 0, MCP_PLAY_S2C_ABILITIES, 0, MCP_PLAY_S2C_UPDATE_HEALTH, 0, MCP_PLAY_S2C_PLAYER_INFO
            db 0, MCP_PLAY_S2C_POSITION, 0, MCP_PLAY_S2C_UPDATE_VIEW_POSITION
            db 0, MCP_PLAY_S2C_SPAWN_POSITION, 0, MCP_PLAY_S2C_UPDATE_TIME
            db 0, MCP_PLAY_S2C_GAME_STATE_CHANGE, 0, MCP_PLAY_S2C_SPAWN_ENTITY
            db 0, MCP_PLAY_S2C_SYSTEM_CHAT
e_join0_n   equ ($-e_join0)/2
e_join1:    db 1, MCP_PLAY_S2C_LOGIN, 1, MCP_PLAY_S2C_ABILITIES, 1, MCP_PLAY_S2C_UPDATE_HEALTH, 1, MCP_PLAY_S2C_PLAYER_INFO
            db 0, MCP_PLAY_S2C_PLAYER_INFO
            db 1, MCP_PLAY_S2C_POSITION, 1, MCP_PLAY_S2C_UPDATE_VIEW_POSITION
            db 1, MCP_PLAY_S2C_SPAWN_POSITION, 1, MCP_PLAY_S2C_UPDATE_TIME
            db 1, MCP_PLAY_S2C_GAME_STATE_CHANGE, 1, MCP_PLAY_S2C_SPAWN_ENTITY
            db 1, MCP_PLAY_S2C_SPAWN_ENTITY, 0, MCP_PLAY_S2C_SPAWN_ENTITY
            db 0, MCP_PLAY_S2C_SYSTEM_CHAT, 1, MCP_PLAY_S2C_SYSTEM_CHAT
e_join1_n   equ ($-e_join1)/2
e_chat:     db 0, MCP_PLAY_S2C_SYSTEM_CHAT, 1, MCP_PLAY_S2C_SYSTEM_CHAT
e_chat_n    equ ($-e_chat)/2
e_cmd:      db 0, MCP_PLAY_S2C_SYSTEM_CHAT
e_cmd_n     equ ($-e_cmd)/2
e_place:    db 0, MCP_PLAY_S2C_BLOCK_CHANGE, 0, MCP_PLAY_S2C_BLOCK_CHANGE
            db 0, MCP_PLAY_S2C_ACKNOWLEDGE_PLAYER_DIGGING
e_place_n   equ ($-e_place)/2
e_dig:      db 0, MCP_PLAY_S2C_BLOCK_CHANGE, 0, MCP_PLAY_S2C_ACKNOWLEDGE_PLAYER_DIGGING
e_dig_n     equ ($-e_dig)/2
e_swing:    db 1, MCP_PLAY_S2C_ANIMATION
e_swing_n   equ ($-e_swing)/2
e_tick:     db 0, MCP_PLAY_S2C_UPDATE_VIEW_POSITION
            db 1, MCP_PLAY_S2C_ENTITY_TELEPORT, 1, MCP_PLAY_S2C_ENTITY_HEAD_ROTATION
e_tick_n    equ ($-e_tick)/2
e_left:     db 0, MCP_PLAY_S2C_ENTITY_DESTROY, 0, MCP_PLAY_S2C_PLAYER_REMOVE
            db 0, MCP_PLAY_S2C_SYSTEM_CHAT
e_left_n    equ ($-e_left)/2

section .bss
alignb 16
global g_net_conns, g_net_host_name
g_net_conns:    resb MCCONN_size*MAX_NET_CONNS
g_net_host_name: resb 20
cap:            resq 1
cap_len:        resd 1
fr_off:         resd MAXF           ; frame -> offset of its conn byte in cap
fr_n:           resd 1
closes:         resd 1
dummy:          resd 1

section .text

global mcmap_block_state, mcmap_biome, mcmap_item_to_block, mcmap_from_state
global mcmap_block_to_item, mcmap_send_registries, mcmap_send_known_packs
global net_close, net_send_frame, net_conn_name, entity_remove, mem_alloc, mem_free

mcmap_block_state:
    xor  eax, eax
    test ecx, ecx
    jz   .r
    mov  eax, ecx
    shl  eax, 4
    inc  eax
.r: ret
mcmap_biome:
    lea  eax, [rcx+40]
    ret
mcmap_item_to_block:                ; item n places block n
    mov  eax, ecx
    ret
mcmap_from_state:
mcmap_block_to_item:
mcmap_send_registries:
mcmap_send_known_packs:
net_conn_name:
entity_remove:
mem_free:
    xor  eax, eax
    ret
net_close:
    inc  dword [rel closes]
    ret

PROC mem_alloc, 0
    call t_alloc
ENDP

; (rcx conn, rdx payload, r8d len) -> cap: u8 conn, u32 len, bytes
PROC net_send_frame, 0
    mov  eax, [rel fr_n]
    cmp  eax, MAXF
    jae  .done
    mov  rdi, [rel cap]
    mov  r9d, [rel cap_len]
    lea  r10, [rel fr_off]
    mov  [r10+rax*4], r9d
    inc  dword [rel fr_n]
    add  rdi, r9
    mov  eax, [rcx+MCCONN.index]
    mov  [rdi], al
    mov  [rdi+1], r8d
    add  rdi, 5
    mov  rsi, rdx
    mov  ecx, r8d
    rep  movsb
    lea  r9d, [r9+r8+5]
    mov  [rel cap_len], r9d
.done:
ENDP

; (ecx frame) -> eax conn, edx packet id (ids here are all one byte varints)
PROC frame_info, 0
    mov  rax, [rel cap]
    lea  rdx, [rel fr_off]
    mov  edx, [rdx+rcx*4]
    add  rax, rdx
    movzx edx, byte [rax+5]
    movzx eax, byte [rax]
ENDP

; (ecx first frame, rdx expected pairs, r8d n) -> eax mismatches (count difference counts)
PROC frames_match, 0
    mov  ebx, ecx
    mov  rsi, rdx
    mov  r12d, r8d
    xor  r13d, r13d
    mov  eax, [rel fr_n]
    sub  eax, ebx
    cmp  eax, r12d
    je   .cnt_ok
    inc  r13d
    cmp  eax, r12d
    cmovb r12d, eax
.cnt_ok:
    xor  r14d, r14d
.l:
    cmp  r14d, r12d
    jae  .done
    lea  ecx, [rbx+r14]
    call frame_info
    movzx ecx, byte [rsi+r14*2]
    cmp  eax, ecx
    jne  .bad
    movzx ecx, byte [rsi+r14*2+1]
    cmp  edx, ecx
    je   .ok
.bad:
    inc  r13d
.ok:
    inc  r14d
    jmp  .l
.done:
    mov  eax, r13d
ENDP

; (rcx conn, rdx data, r8 end)
PROC feed, 0
    sub  r8, rdx
    call mc_handle_packet
ENDP

%macro STEP 4.nolist             ; first frame reg, expected list, count, "msg"
    mov  ecx, %1
    lea  rdx, [rel %2]
    mov  r8d, %3
    call frames_match
    mov  r15d, eax
    CHECK_EQ32 r15d, 0, %4
%endmacro

PROC setup_conn, 0 ; v1: test_playjoin scratch #0
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_playjoin:0)
    mov  rbx, rcx ; v1: test_playjoin scratch #1
    mov  dword [rbx+MCCONN.state], CN_PLAY ; v1: test_playjoin scratch #2
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_playjoin:2)
    mov  [rbx+MCCONN.index], edx ; v1: test_playjoin scratch #3
    mov  dword [rbx+MCCONN.view], 10 ; v1: test_playjoin scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (test_playjoin:4)
    lea  rcx, [rbx+MCCONN.name] ; v1: test_playjoin scratch #5
    mov  rdx, r8 ; v1: test_playjoin scratch #6
    ; TODO: clamp index before table lookup on malformed input (test_playjoin:6)
    call str_copy ; v1: test_playjoin scratch #7
    lea  rcx, [rbx+MCCONN.name] ; v1: test_playjoin scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_playjoin:8)
    lea  rdx, [rbx+MCCONN.uuid] ; v1: test_playjoin scratch #9
    call mc_offline_uuid ; v1: test_playjoin scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_playjoin:10)
ENDP ; v1: test_playjoin scratch #11

PROC write_frames, 32 ; v1: test_playjoin scratch #13
    lea  rcx, [rel s_frames] ; v1: test_playjoin scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_playjoin:14)
    mov  edx, GENERIC_WRITE ; v1: test_playjoin scratch #15
    xor  r8d, r8d ; v1: test_playjoin scratch #16
    ; TODO: hoist invariant pointer load out of .loop (test_playjoin:16)
    xor  r9d, r9d ; v1: test_playjoin scratch #17
    mov  qword [rsp+32], CREATE_ALWAYS ; v1: test_playjoin scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_playjoin:18)
    mov  qword [rsp+40], 0 ; v1: test_playjoin scratch #19
    mov  qword [rsp+48], 0 ; v1: test_playjoin scratch #20
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_playjoin:20)
    call CreateFileA ; v1: test_playjoin scratch #21
    cmp  rax, -1 ; v1: test_playjoin scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (test_playjoin:22)
    je   .done ; v1: test_playjoin scratch #23
    mov  rbx, rax ; v1: test_playjoin scratch #24
    ; TODO: clamp index before table lookup on malformed input (test_playjoin:24)
    mov  rcx, rbx ; v1: test_playjoin scratch #25
    mov  rdx, [rel cap] ; v1: test_playjoin scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_playjoin:26)
    mov  r8d, [rel cap_len] ; v1: test_playjoin scratch #27
    lea  r9, [rel dummy] ; v1: test_playjoin scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_playjoin:28)
    mov  qword [rsp+32], 0 ; v1: test_playjoin scratch #29
    call WriteFile ; v1: test_playjoin scratch #30
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_playjoin:30)
    mov  rcx, rbx
    call CloseHandle
.done:
ENDP

PROC test_main, 64
    call blocks_init
    mov  ecx, 4*1024*1024
    call t_alloc
    mov  [rel cap], rax
    lea  rcx, [rel g_net_host_name]
    lea  rdx, [rel s_host]
    call str_copy
    mov  dword [rel g_world_active], 1
    mov  dword [rel g_gamemode], GM_SURVIVAL

    lea  rbx, [rel g_net_conns]
    lea  r12, [rbx+MCCONN_size]
    mov  rcx, rbx
    xor  edx, edx
    lea  r8, [rel s_alex]
    call setup_conn
    mov  rcx, r12
    mov  edx, 1
    lea  r8, [rel s_steve]
    call setup_conn

    TEST "join first"
    mov  r14d, [rel fr_n]
    mov  rcx, rbx
    call mcplay_join
    STEP r14d, e_join0, e_join0_n, "login sequence"
    mov  eax, [rbx+MCCONN.flags]
    and  eax, CF_JOINED|CF_SPAWNED
    CHECK_EQ32 eax, CF_JOINED|CF_SPAWNED, "flags"
    CHECK_EQ32 [rbx+MCCONN.eid], 2, "eid"
    CHECK_EQ32 [rbx+MCCONN.tp_id], 1, "teleport id"
    mov  rax, [rbx+MCCONN.sent]
    xor  ecx, ecx
    test rax, rax
    setnz cl
    CHECK_TRUE ecx, "sent bitset"
    call mcplay_count
    CHECK_EQ32 eax, 1, "count"

    TEST "join second"
    mov  r14d, [rel fr_n]
    mov  rcx, r12
    call mcplay_join
    STEP r14d, e_join1, e_join1_n, "second login + broadcast"
    call mcplay_count
    CHECK_EQ32 eax, 2, "count"

    TEST "movement"
    mov  rcx, rbx
    lea  rdx, [rel p_poslook]
    lea  r8, [rel p_poslook_end]
    call feed                       ; ignored, teleport not confirmed yet
    movsd xmm0, [rbx+MCCONN.x]
    cvtsd2ss xmm0, xmm0
    CHECK_NEAR xmm0, 0.5, 0.001, "x before confirm"
    mov  rcx, rbx
    lea  rdx, [rel p_tpc]
    lea  r8, [rel p_tpc_end]
    call feed
    CHECK_EQ32 [rbx+MCCONN.tp_id], 0, "confirmed"
    mov  rcx, rbx
    lea  rdx, [rel p_poslook]
    lea  r8, [rel p_poslook_end]
    call feed
    movsd xmm0, [rbx+MCCONN.x]
    cvtsd2ss xmm0, xmm0
    CHECK_NEAR xmm0, 10.5, 0.001, "x"
    movsd xmm0, [rbx+MCCONN.z]
    cvtsd2ss xmm0, xmm0
    CHECK_NEAR xmm0, -3.25, 0.001, "z"
    movss xmm0, [rbx+MCCONN.yaw]
    CHECK_NEAR xmm0, 90.0, 0.001, "yaw"
    CHECK_EQ32 [rbx+MCCONN.on_ground], 1, "on ground"

    ; v1 temporary guard (test_playjoin #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (test_playjoin #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (test_playjoin #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_playjoin #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_playjoin #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_playjoin #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_playjoin #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_playjoin #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_playjoin #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_playjoin #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_playjoin #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_playjoin #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_playjoin #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_playjoin #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_playjoin #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_playjoin #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_playjoin #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_playjoin #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_playjoin #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (test_playjoin #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (test_playjoin #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (test_playjoin #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (test_playjoin #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (test_playjoin #61)
    xor     r11d, r11d ; clear v1 slot 61
