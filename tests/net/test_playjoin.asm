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

PROC setup_conn, 0                  ; (rcx conn, edx index, r8 name)
    mov  rbx, rcx
    mov  dword [rbx+MCCONN.state], CN_PLAY
    mov  [rbx+MCCONN.index], edx
    mov  dword [rbx+MCCONN.view], 10
    lea  rcx, [rbx+MCCONN.name]
    mov  rdx, r8
    call str_copy
    lea  rcx, [rbx+MCCONN.name]
    lea  rdx, [rbx+MCCONN.uuid]
    call mc_offline_uuid
ENDP

PROC write_frames, 32
    lea  rcx, [rel s_frames]
    mov  edx, GENERIC_WRITE
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], CREATE_ALWAYS
    mov  qword [rsp+40], 0
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .done
    mov  rbx, rax
    mov  rcx, rbx
    mov  rdx, [rel cap]
    mov  r8d, [rel cap_len]
    lea  r9, [rel dummy]
    mov  qword [rsp+32], 0
    call WriteFile
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

    TEST "chat"
    mov  r14d, [rel fr_n]
    mov  rcx, rbx
    lea  rdx, [rel p_chat]
    lea  r8, [rel p_chat_end]
    call feed
    STEP r14d, e_chat, e_chat_n, "chat to both"
    mov  r14d, [rel fr_n]
    mov  rcx, rbx
    lea  rdx, [rel p_cmd]
    lea  r8, [rel p_cmd_end]
    call feed
    STEP r14d, e_cmd, e_cmd_n, "/list answers the sender"

    TEST "inventory"
    mov  rcx, rbx
    lea  rdx, [rel p_slot]
    lea  r8, [rel p_slot_end]
    call feed
    CHECK_EQ32 [rbx+MCCONN.hotbar], 5, "hotbar 0 from slot 36"
    mov  rcx, rbx
    lea  rdx, [rel p_held]
    lea  r8, [rel p_held_end]
    call feed
    CHECK_EQ32 [rbx+MCCONN.held_slot], 0, "held"

    TEST "blocks (world not loaded)"
    mov  r14d, [rel fr_n]
    mov  rcx, rbx
    lea  rdx, [rel p_place]
    lea  r8, [rel p_place_end]
    call feed
    STEP r14d, e_place, e_place_n, "place -> resync both + ack"
    mov  r14d, [rel fr_n]
    mov  rcx, rbx
    lea  rdx, [rel p_dig]
    lea  r8, [rel p_dig_end]
    call feed
    STEP r14d, e_dig, e_dig_n, "dig below 0 -> resync + ack"

    TEST "keepalive + swing"
    mov  qword [rbx+MCCONN.ka_time], 123
    mov  rcx, rbx
    lea  rdx, [rel p_ka]
    lea  r8, [rel p_ka_end]
    call feed
    CHECK_EQ32 [rbx+MCCONN.ka_time], 0, "answered"
    mov  r14d, [rel fr_n]
    mov  rcx, rbx
    lea  rdx, [rel p_swing]
    lea  r8, [rel p_swing_end]
    call feed
    STEP r14d, e_swing, e_swing_n, "swing goes to the other one"

    TEST "tick"
    mov  r14d, [rel fr_n]
    call mcplay_tick                ; alex walked into chunk 0,-1, steve hears about it
    STEP r14d, e_tick, e_tick_n, "new centre + movement broadcast"
    CHECK_EQ32 [rbx+MCCONN.ccz], -1, "centre z"

    TEST "leave"
    mov  r14d, [rel fr_n]
    mov  rcx, r12
    call mcplay_left
    mov  dword [r12+MCCONN.state], CN_FREE
    STEP r14d, e_left, e_left_n, "despawn + tab removal + message"
    call mcplay_count
    CHECK_EQ32 eax, 1, "count"
    CHECK_EQ32 [rel closes], 0, "nobody kicked"

    call write_frames
ENDP
