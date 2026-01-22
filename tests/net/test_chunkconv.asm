; mcplay_encode_chunk: our 16x128x16 chunk -> java 26.1 map_chunk body. synthetic
; chunk (ground, water, tall grass, a tree, a wool band with 21 ids for 5 bit
; palettes, block light in one section) checked byte for byte against
; chunkconv_gold.inc, written by the reference encoder in build/.
; regenerate it after changing either side.
; @link src/mcplay.asm src/blocks.asm src/items.asm
; @timeout 30
%define IMPL_NET
%define IMPL_MCPROTO
%define IMPL_MCMAP
%include "common.inc"
%include "net.inc"
%include "testlib.inc"
%include "../net/chunkconv_gold.inc"

extern mcplay_encode_chunk

section .bss
alignb 16
global g_net_conns, g_net_host_name
g_net_conns:    resb MCCONN_size*MAX_NET_CONNS
g_net_host_name: resb 20
chunk:          resq 1
out1:           resq 1
out2:           resq 1

section .text

; the play module needs these, nothing here talks to a socket
global mcmap_block_state, mcmap_biome, mcmap_item_to_block, mcmap_from_state
global mcmap_block_to_item, mcmap_send_registries
global net_close, net_send_frame, net_conn_name, mc_offline_uuid, entity_remove
global pw_begin, pw_send, pw_varint, pw_varlong, pw_u8, pw_u16, pw_i32, pw_i64
global pw_f32, pw_f64, pw_bool, pw_string, pw_bytes, pw_uuid, pw_position
global pw_text, pw_text_color
global pr_init, pr_varint, pr_varlong, pr_u8, pr_u16, pr_i32, pr_i64, pr_f32
global pr_f64, pr_bool, pr_string, pr_uuid, pr_position, pr_skip

; state = id*16+1, air stays 0. biome = ours+40. same as the reference encoder
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
mcmap_item_to_block:
mcmap_from_state:
mcmap_block_to_item:
mcmap_send_registries:
net_close:
net_send_frame:
net_conn_name:
mc_offline_uuid:
entity_remove:
pw_begin:
pw_send:
pw_varint:
pw_varlong:
pw_u8:
pw_u16:
pw_i32:
pw_i64:
pw_f32:
pw_f64:
pw_bool:
pw_string:
pw_bytes:
pw_uuid:
pw_position:
pw_text:
pw_text_color:
pr_init:
pr_varint:
pr_varlong:
pr_u8:
pr_u16:
pr_i32:
pr_i64:
pr_f32:
pr_f64:
pr_bool:
pr_string:
pr_uuid:
pr_position:
pr_skip:
    xor  eax, eax
    xorps xmm0, xmm0
    ret

; (ecx x, edx z) -> eax surface height 60 + (3x+5z) % 9
PROC surf, 0
    lea  eax, [rcx+rcx*2]
    lea  r8d, [rdx+rdx*4]
    add  eax, r8d
    xor  edx, edx
    mov  r8d, 9
    div  r8d
    lea  eax, [rdx+60]
ENDP

; (ecx x, edx y, r8d z) -> eax our block id, must match the reference encoder
PROC blk_at, 0
    mov  esi, ecx
    mov  edi, edx
    mov  r12d, r8d
    mov  ecx, esi
    mov  edx, r12d
    call surf
    mov  r13d, eax                  ; h
    lea  eax, [r13-3]
    cmp  edi, eax
    jge  .notrock
    lea  eax, [rsi+r12]
    add  eax, edi
    xor  edx, edx
    mov  ecx, 23
    div  ecx
    mov  ebx, B_STONE
    test edx, edx
    jnz  .over
    mov  ebx, B_COAL_ORE
    jmp  .over
.notrock:
    mov  ebx, B_DIRT
    cmp  edi, r13d
    jl   .over
    jne  .above
    mov  ebx, B_GRASS
    cmp  esi, 3
    jge  .over
    mov  ebx, B_WATER
    jmp  .over
.above:
    xor  ebx, ebx
    lea  eax, [r13+1]
    cmp  edi, eax
    jne  .over
    imul eax, esi, 7
    add  eax, r12d
    xor  edx, edx
    mov  ecx, 5
    div  ecx
    test edx, edx
    jnz  .over
    mov  ebx, B_TALL_GRASS
.over:
    cmp  esi, 4                     ; the trunk
    jne  .noleaf0
    cmp  r12d, 4
    jne  .noleaf0
    cmp  edi, r13d
    jle  .noleaf0
    lea  eax, [r13+5]
    cmp  edi, eax
    jg   .noleaf0
    mov  ebx, B_LOG
.noleaf0:
    cmp  edi, 71                    ; leaves on top of it
    jne  .noleaf
    test ebx, ebx
    jnz  .noleaf
    cmp  esi, 3
    jl   .noleaf
    cmp  esi, 5
    jg   .noleaf
    cmp  r12d, 3
    jl   .noleaf
    cmp  r12d, 5
    jg   .noleaf
    mov  ebx, B_LEAVES
.noleaf:
    cmp  edi, 96                    ; wool band
    jl   .nowool
    cmp  edi, 99
    jg   .nowool
    imul eax, r12d, 3
    add  eax, esi
    add  eax, edi
    and  eax, 15
    lea  ebx, [rax+B_WOOL]
.nowool:
    cmp  edi, 100
    jne  .done
    mov  eax, esi
    and  eax, 3
    lea  ebx, [rax+B_GOLD_BLOCK]
.done:
    mov  eax, ebx
ENDP

PROC light_at, 0
    mov  esi, ecx
    mov  edi, edx
    mov  r12d, r8d
    mov  ecx, esi
    mov  edx, r12d
    call surf
    xor  ebx, ebx
    cmp  edi, eax
    jle  .low
    mov  ebx, 15
    jmp  .blk
.low:
    cmp  edi, 40
    jl   .blk
    mov  ebx, edi
    and  ebx, 7
.blk:
    shl  ebx, 4
    cmp  edi, 32
    jl   .done
    cmp  edi, 48
    jge  .done
    mov  eax, esi
    xor  eax, r12d
    xor  eax, edi
    and  eax, 15
    or   ebx, eax
.done:
    mov  eax, ebx
ENDP

PROC build_chunk, 16
    mov  ecx, CHUNK_BYTES
    call t_alloc
    mov  [rel chunk], rax
    mov  rbx, rax
    mov  dword [rbx+CHUNK.cx], -3
    mov  dword [rbx+CHUNK.cz], 5
    mov  dword [rbx+CHUNK.state], CS_READY
    lea  rdi, [rbx+CHUNK.biome]
    mov  al, BIOME_PLAINS
    mov  ecx, 256
    rep  stosb
    xor  r14d, r14d                 ; idx = x + z*16 + y*256
.l:
    mov  ecx, r14d
    and  ecx, 15
    mov  edx, r14d
    shr  edx, 8
    mov  r8d, r14d
    shr  r8d, 4
    and  r8d, 15
    call blk_at
    mov  [rbx+r14+CHUNK_BLOCKS], al
    mov  ecx, r14d
    and  ecx, 15
    mov  edx, r14d
    shr  edx, 8
    mov  r8d, r14d
    shr  r8d, 4
    and  r8d, 15
    call light_at
    mov  [rbx+r14+CHUNK_LIGHT], al
    inc  r14d
    cmp  r14d, CHUNK_VOL
    jb   .l
ENDP

PROC test_main, 64
    call blocks_init
    call build_chunk
    mov  ecx, 256*1024
    call t_alloc
    mov  [rel out1], rax
    mov  ecx, 256*1024
    call t_alloc
    mov  [rel out2], rax

    TEST "synthetic chunk"
    mov  rbx, [rel chunk]
    mov  rcx, [rel chunk]
    movzx eax, byte [rcx+CHUNK_BLOCKS + 4 + 4*16 + 66*256]
    CHECK_EQ32 eax, B_LOG, "trunk at 4,66,4"
    mov  rcx, [rel chunk]
    movzx eax, byte [rcx+CHUNK_BLOCKS + 0 + 0*16 + 60*256]
    CHECK_EQ32 eax, B_WATER, "water at 0,60,0"

    TEST "encode vs reference"
    mov  rcx, [rel chunk]
    mov  rdx, [rel out1]
    call mcplay_encode_chunk
    mov  r12d, eax
    CHECK_EQ32 r12d, GOLD_LEN, "body length"
    mov  rsi, [rel out1]
    lea  rdi, [rel gold]
    CHECK_MEM rsi, rdi, GOLD_HM_END, "position + heightmaps"
    mov  rsi, [rel out1]
    add  rsi, GOLD_HM_END
    lea  rdi, [rel gold]
    add  rdi, GOLD_HM_END
    CHECK_MEM rsi, rdi, GOLD_SEC_START-GOLD_HM_END, "section data length"
    mov  rsi, [rel out1]
    add  rsi, GOLD_SEC_START
    lea  rdi, [rel gold]
    add  rdi, GOLD_SEC_START
    CHECK_MEM rsi, rdi, GOLD_LIGHT_START-GOLD_SEC_START, "sections: counts, palettes, longs, biomes"
    mov  rsi, [rel out1]
    add  rsi, GOLD_LIGHT_START
    lea  rdi, [rel gold]
    add  rdi, GOLD_LIGHT_START
    CHECK_MEM rsi, rdi, GOLD_LEN-GOLD_LIGHT_START, "light masks + nibbles"

    TEST "encode twice"                 ; per-section palette state must reset
    mov  rcx, [rel chunk]
    mov  rdx, [rel out2]
    call mcplay_encode_chunk
    mov  r12d, eax
    CHECK_EQ32 r12d, GOLD_LEN, "length again"
    mov  rsi, [rel out1]
    mov  rdi, [rel out2]
    CHECK_MEM rsi, rdi, GOLD_LEN, "same bytes"

    TEST "no players"
    call mcplay_count
    mov  ebx, eax
    CHECK_EQ32 ebx, 0, "count with every slot free"
    mov  ecx, 1
    mov  edx, 64
    mov  r8d, 1
    mov  r9d, B_STONE
    call mcplay_block_changed       ; nobody to tell, must not touch anything
    call mcplay_tick
    CHECK_EQ32 ebx, 0, "survived block_changed + tick"
ENDP
