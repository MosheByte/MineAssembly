; mcplay entity + weather sync: a fake g_entities and a fake socket, mcplay_tick
; diffs one against the other. checks which packets go to which client and a few
; fields, writes frames.bin (u8 conn, u32 len, body) for decoding offline.
; @link src/mcplay.asm src/mcproto.asm src/blocks.asm src/items.asm
; @link src/util.asm src/math.asm
; @timeout 30
%define IMPL_NET
%define IMPL_MCMAP
%define IMPL_PLATFORM
%define IMPL_ENTITY
%define IMPL_WEATHER
%include "common.inc"
%include "net.inc"
%include "mcpackets.inc"
%include "testlib.inc"

%define MAXF 2048

section .rdata
s_alex:     db "Alex", 0
s_steve:    db "Steve", 0
s_frames:   db "frames.bin", 0
; packets that only exist because of entities
ent_ids:    db MCP_PLAY_S2C_SPAWN_ENTITY, MCP_PLAY_S2C_ENTITY_METADATA, MCP_PLAY_S2C_REL_ENTITY_MOVE
            db MCP_PLAY_S2C_ENTITY_MOVE_LOOK, MCP_PLAY_S2C_ENTITY_LOOK, MCP_PLAY_S2C_SYNC_ENTITY_POSITION
            db MCP_PLAY_S2C_ENTITY_VELOCITY, MCP_PLAY_S2C_ENTITY_DESTROY, MCP_PLAY_S2C_ENTITY_STATUS
            db MCP_PLAY_S2C_COLLECT, MCP_PLAY_S2C_HURT_ANIMATION, MCP_PLAY_S2C_GAME_STATE_CHANGE, 0
want_types: dd MCE_PIG, MCE_SHEEP, MCE_ZOMBIE, MCE_ITEM, MCE_TNT, MCE_FALLING_BLOCK

section .bss
alignb 16
global g_net_conns, g_net_host_name, g_entities, g_entity_count, g_weather
g_net_conns:    resb MCCONN_size*MAX_NET_CONNS
g_net_host_name: resb 20
g_entities:     resb ENTITY_size*MAX_ENTITIES
g_entity_count: resd 1
g_weather:      resd 1
cap:            resq 1
cap_len:        resd 1
fr_off:         resd MAXF
fr_n:           resd 1
dummy:          resd 1

section .text

global mcmap_block_state, mcmap_biome, mcmap_item_to_block, mcmap_from_state
global mcmap_block_to_item, mcmap_send_registries, mcmap_send_known_packs
global net_close, net_send_frame, net_conn_name, entity_remove, mem_alloc, mem_free

mcmap_block_state:
    lea  eax, [rcx*4+1]
    ret
mcmap_block_to_item:                ; block n is item 1000+n
    movzx eax, cl
    add  eax, 1000
    ret
mcmap_biome:
mcmap_item_to_block:
mcmap_from_state:
mcmap_send_registries:
mcmap_send_known_packs:
net_conn_name:
entity_remove:
mem_free:
net_close:
    xor  eax, eax
    ret

PROC mem_alloc, 0
    call t_alloc
ENDP

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

; ecx frame -> rax body (packet id first), edx conn
PROC frame_ptr, 0
    mov  rax, [rel cap]
    lea  rdx, [rel fr_off]
    mov  edx, [rdx+rcx*4]
    add  rax, rdx
    movzx edx, byte [rax]
    add  rax, 5
ENDP

; (ecx first frame, edx packet id, r8d conn or -1) -> eax how many since first
PROC count_id, 0
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    xor  r12d, r12d
.l:
    cmp  ebx, [rel fr_n]
    jae  .done
    mov  ecx, ebx
    call frame_ptr
    inc  ebx
    movzx eax, byte [rax]
    cmp  eax, esi
    jne  .l
    cmp  edi, -1
    je   .hit
    cmp  edx, edi
    jne  .l
.hit:
    inc  r12d
    jmp  .l
.done:
    mov  eax, r12d
ENDP

; (ecx first frame, edx packet id, r8d nth) -> rax body of the nth such frame or 0
PROC find_id, 0
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
.l:
    xor  eax, eax
    cmp  ebx, [rel fr_n]
    jae  .done
    mov  ecx, ebx
    call frame_ptr
    inc  ebx
    movzx ecx, byte [rax]
    cmp  ecx, esi
    jne  .l
    dec  edi
    jns  .l
.done:
ENDP

; ecx first frame -> eax how many entity/weather packets, any client
PROC count_ent, 0
    mov  r12d, ecx
    xor  r13d, r13d
    lea  r14, [rel ent_ids]
.l:
    movzx edx, byte [r14]
    test edx, edx
    jz   .done
    mov  ecx, r12d
    mov  r8d, -1
    call count_id
    add  r13d, eax
    inc  r14
    jmp  .l
.done:
    mov  eax, r13d
ENDP

; rsi cursor -> eax varint, rsi past it
align 16
rdvar:
    xor  eax, eax
    xor  ecx, ecx
.l: movzx edx, byte [rsi]
    inc  rsi
    mov  r8d, edx
    and  r8d, 0x7F
    shl  r8d, cl
    or   eax, r8d
    add  ecx, 7
    test edx, 0x80
    jnz  .l
    ret

; (ecx slot, edx type, xmm1 x, xmm2 y, xmm3 z) -> rax ENTITY*, age 1
PROC put_ent, 0
    mov  eax, ecx
    shl  eax, 7
    lea  rbx, [rel g_entities]
    add  rbx, rax
    mov  rdi, rbx
    xor  eax, eax
    mov  ecx, ENTITY_size/8
    rep  stosq
    mov  [rbx+ENTITY.type], dl
    movss [rbx+ENTITY.x], xmm1
    movss [rbx+ENTITY.y], xmm2
    movss [rbx+ENTITY.z], xmm3
    mov  dword [rbx+ENTITY.age], 1
    mov  rax, rbx
ENDP

; rcx conn: it has every chunk
PROC all_chunks, 0
    mov  rdi, [rcx+MCCONN.sent]
    mov  eax, -1
    mov  ecx, 128
    rep  stosd
ENDP

PROC setup_conn, 0
    mov  rbx, rcx
    mov  dword [rbx+MCCONN.state], CN_PLAY
    mov  [rbx+MCCONN.index], edx
    mov  dword [rbx+MCCONN.view], 12
    lea  rcx, [rbx+MCCONN.name]
    mov  rdx, r8
    call str_copy
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

%macro CNT 3.nolist                 ; packet id, conn, want
    mov  ecx, r14d
    mov  edx, %1
    mov  r8d, %2
    call count_id
    mov  r15d, eax
    CHECK_EQ32 r15d, %3, %str(%1)
%endmacro

%macro TICK 0.nolist
    mov  r14d, [rel fr_n]
    call mcplay_tick
%endmacro

PROC test_main, 64
    call blocks_init
    mov  ecx, 8*1024*1024
    call t_alloc
    mov  [rel cap], rax
    mov  dword [rel g_world_active], 1
    lea  rbx, [rel g_net_conns]

    mov  rcx, rbx
    xor  edx, edx
    lea  r8, [rel s_alex]
    call setup_conn
    mov  rcx, rbx
    call mcplay_join
    CHECK_EQ32 [rbx+MCCONN.view], 10, "view capped at 10"
    mov  rcx, rbx
    call all_chunks

    ; feet at 0.5 70 0.5 like the join puts them (no world here)
    FCONST xmm1, 4.5
    FCONST xmm2, 70.0
    FCONST xmm3, 4.5
    xor  ecx, ecx
    mov  edx, ENT_BOAR
    call put_ent
    mov  dword [rax+ENTITY.yaw], __float32__(90.0)
    mov  dword [rax+ENTITY.head_yaw], __float32__(90.0)
    FCONST xmm1, 6.0
    FCONST xmm2, 70.0
    FCONST xmm3, -3.0
    mov  ecx, 1
    mov  edx, ENT_WOOLLY
    call put_ent
    mov  byte [rax+ENTITY.variant], 15
    FCONST xmm1, -8.0
    FCONST xmm2, 70.0
    FCONST xmm3, 2.0
    mov  ecx, 2
    mov  edx, ENT_SHAMBLER
    call put_ent
    FCONST xmm1, 1.0
    FCONST xmm2, 71.0
    FCONST xmm3, 1.0
    mov  ecx, 3
    mov  edx, ENT_ITEM
    call put_ent
    mov  byte [rax+ENTITY.item+STACK.id], B_STONE
    mov  byte [rax+ENTITY.item+STACK.count], 5
    mov  dword [rax+ENTITY.vy], __float32__(0.2)
    mov  dword [rax+ENTITY.vx], __float32__(-0.05)
    FCONST xmm1, 2.5
    FCONST xmm2, 70.0
    FCONST xmm3, 2.5
    mov  ecx, 4
    mov  edx, ENT_TNT
    call put_ent
    mov  dword [rax+ENTITY.timer], 80
    FCONST xmm1, 3.5
    FCONST xmm2, 75.0
    FCONST xmm3, 3.5
    mov  ecx, 5
    mov  edx, ENT_FALLING
    call put_ent
    mov  byte [rax+ENTITY.variant], B_GRAVEL
    FCONST xmm1, 0.0
    FCONST xmm2, 72.0
    FCONST xmm3, 0.0
    mov  ecx, 6
    mov  edx, ENT_GLOWBUG
    call put_ent
    FCONST xmm1, 1000.0             ; 62 chunks out, nobody sees it
    FCONST xmm2, 70.0
    FCONST xmm3, 0.0
    mov  ecx, 7
    mov  edx, ENT_BOAR
    call put_ent
    FCONST xmm1, 30.0               ; item range is 6 chunks
    FCONST xmm2, 70.0
    FCONST xmm3, 120.0
    mov  ecx, 8
    mov  edx, ENT_ITEM
    call put_ent
    mov  byte [rax+ENTITY.item+STACK.id], B_DIRT
    mov  byte [rax+ENTITY.item+STACK.count], 1

    TEST "spawn on the first tick"
    TICK
    CNT MCP_PLAY_S2C_SPAWN_ENTITY, 0, 6
    CNT MCP_PLAY_S2C_ENTITY_METADATA, 0, 5
    ; each wanted java type exactly once
    xor  r12d, r12d                 ; nth spawn
    xor  r13d, r13d                 ; bits of want_types seen
.sp:
    mov  ecx, r14d
    mov  edx, MCP_PLAY_S2C_SPAWN_ENTITY
    mov  r8d, r12d
    call find_id
    test rax, rax
    jz   .spd
    lea  rsi, [rax+1]
    call rdvar                      ; eid
    add  rsi, 16                    ; uuid
    call rdvar
    lea  rdx, [rel want_types]
    xor  ecx, ecx
.wt:
    cmp  [rdx+rcx*4], eax
    je   .wf
    inc  ecx
    cmp  ecx, 6
    jb   .wt
    jmp  .wn
.wf:
    bts  r13d, ecx
.wn:
    inc  r12d
    jmp  .sp
.spd:
    CHECK_EQ32 r13d, 0x3F, "pig sheep zombie item tnt falling_block"
    ; sheep metadata: wool 15 at index 18
    mov  ecx, r14d
    mov  edx, MCP_PLAY_S2C_ENTITY_METADATA
    mov  r8d, 1
    call find_id
    mov  rsi, rax
    inc  rsi
    call rdvar
    movzx r12d, byte [rsi+3]        ; 0 byte flags, then 18
    movzx r13d, byte [rsi+5]
    CHECK_EQ32 r12d, 18, "wool index"
    CHECK_EQ32 r13d, 15, "wool colour"
    ; item metadata: index 8, slot type 7, count 5, item 1000+stone
    mov  ecx, r14d
    mov  edx, MCP_PLAY_S2C_ENTITY_METADATA
    mov  r8d, 3
    call find_id
    lea  rsi, [rax+1]
    call rdvar
    movzx r12d, byte [rsi]
    CHECK_EQ32 r12d, 8, "item index"
    movzx r12d, byte [rsi+1]
    CHECK_EQ32 r12d, 7, "item_stack type"
    add  rsi, 2
    call rdvar
    mov  r12d, eax
    CHECK_EQ32 r12d, 5, "item count"
    call rdvar
    mov  r12d, eax
    CHECK_EQ32 r12d, 1000+B_STONE, "item id"

    TEST "nothing moved, nothing sent"
    TICK
    mov  ecx, r14d
    call count_ent
    mov  r15d, eax
    CHECK_EQ32 r15d, 0, "entity packets on a quiet tick"

    TEST "relative move"
    lea  rbx, [rel g_entities]
    movss xmm0, [rbx+ENTITY.x]
    addss xmm0, [rel c_half_t]
    movss [rbx+ENTITY.x], xmm0
    TICK
    CNT MCP_PLAY_S2C_REL_ENTITY_MOVE, 0, 1
    mov  ecx, r14d
    mov  edx, MCP_PLAY_S2C_REL_ENTITY_MOVE
    xor  r8d, r8d
    call find_id
    lea  rsi, [rax+1]
    call rdvar
    movzx r12d, word [rsi]
    rol  r12w, 8
    movzx r13d, word [rsi+2]
    CHECK_EQ32 r12d, 2048, "dx in 1/4096"
    CHECK_EQ32 r13d, 0, "dy"

    TEST "look + head"
    lea  rbx, [rel g_entities]
    mov  dword [rbx+ENTITY.yaw], __float32__(180.0)
    TICK
    CNT MCP_PLAY_S2C_ENTITY_LOOK, 0, 1
    CNT MCP_PLAY_S2C_ENTITY_HEAD_ROTATION, 0, 0
    mov  dword [rbx+ENTITY.head_yaw], __float32__(180.0)
    movss xmm0, [rbx+ENTITY.z]
    addss xmm0, [rel c_half_t]
    movss [rbx+ENTITY.z], xmm0
    TICK
    CNT MCP_PLAY_S2C_ENTITY_HEAD_ROTATION, 0, 1
    CNT MCP_PLAY_S2C_REL_ENTITY_MOVE, 0, 1

    TEST "far jump syncs the position"
    lea  rbx, [rel g_entities]
    movss xmm0, [rbx+ENTITY.x]
    addss xmm0, [rel c_20_t]
    movss [rbx+ENTITY.x], xmm0
    mov  dword [rbx+ENTITY.yaw], __float32__(0.0)
    TICK
    CNT MCP_PLAY_S2C_SYNC_ENTITY_POSITION, 0, 1
    CNT MCP_PLAY_S2C_REL_ENTITY_MOVE, 0, 0
    CNT MCP_PLAY_S2C_ENTITY_MOVE_LOOK, 0, 0

    TEST "metadata changes"
    lea  rbx, [rel g_entities]
    mov  byte [rbx+3*ENTITY_size+ENTITY.item+STACK.count], 7
    mov  dword [rbx+1*ENTITY_size+ENTITY.fire], 100
    TICK
    CNT MCP_PLAY_S2C_ENTITY_METADATA, 0, 2

    TEST "item velocity"
    lea  rbx, [rel g_entities]
    mov  dword [rbx+3*ENTITY_size+ENTITY.vy], __float32__(-0.3)
    TICK
    CNT MCP_PLAY_S2C_ENTITY_VELOCITY, 0, 1

    TEST "death, hurt, pickup"
    lea  rbx, [rel g_entities]
    or   byte [rbx+2*ENTITY_size+ENTITY.flags], EF_DEAD
    mov  dword [rbx+0*ENTITY_size+ENTITY.hurt_time], 10
    mov  byte [rbx+3*ENTITY_size+ENTITY.ai_state], 1
    TICK
    CNT MCP_PLAY_S2C_ENTITY_STATUS, 0, 1
    CNT MCP_PLAY_S2C_HURT_ANIMATION, 0, 1
    CNT MCP_PLAY_S2C_COLLECT, 0, 1
    lea  rbx, [rel g_entities]
    mov  dword [rbx+0*ENTITY_size+ENTITY.hurt_time], 9
    TICK
    mov  ecx, r14d
    call count_ent
    mov  r15d, eax
    CHECK_EQ32 r15d, 0, "events go out once"

    TEST "removed, then the slot reused"
    lea  rbx, [rel g_entities]
    mov  byte [rbx+3*ENTITY_size+ENTITY.type], 0
    TICK
    CNT MCP_PLAY_S2C_ENTITY_DESTROY, 0, 1
    FCONST xmm1, 2.0
    FCONST xmm2, 70.0
    FCONST xmm3, 2.0
    mov  ecx, 3
    mov  edx, ENT_ITEM
    call put_ent
    mov  byte [rax+ENTITY.item+STACK.id], B_SAND
    mov  byte [rax+ENTITY.item+STACK.count], 2
    mov  dword [rax+ENTITY.age], 50
    TICK
    CNT MCP_PLAY_S2C_SPAWN_ENTITY, 0, 1
    lea  rbx, [rel g_entities]
    mov  dword [rbx+3*ENTITY_size+ENTITY.age], 1     ; same type, younger: a new one
    TICK
    CNT MCP_PLAY_S2C_ENTITY_DESTROY, 0, 1
    CNT MCP_PLAY_S2C_SPAWN_ENTITY, 0, 1

