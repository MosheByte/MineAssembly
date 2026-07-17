; block/item/biome id translation (internal u8 <-> java 26.1 protocol ids)
%define IMPL_MCMAP
%include "common.inc"
%include "net.inc"
%include "mcpackets.inc"

extern mcd_block_state
extern mcd_block_item
extern mcd_run_count
extern mcd_run_start
extern mcd_run_block
extern mcd_item_block
extern mcd_biome
extern mcd_registries
extern mcd_tags

section .rdata
s_pack_ns:      db "minecraft", 0
s_pack_id:      db "core", 0
s_pack_ver:     db MC_VERSION_NAME, 0

section .text

; ecx our block id -> eax java block state. junk ids are air
LEAF mcmap_block_state
    mov  ecx, ecx
    xor  eax, eax
    cmp  ecx, BLOCK_COUNT
    jae  .done
    lea  rax, [rel mcd_block_state]
    mov  eax, [rax+rcx*4]
.done:
    ret

; ecx java block state -> eax our block. binary search over the runs,
; start[0] is 0 so lo always holds a run that starts <= state
LEAF mcmap_from_state
    mov  ecx, ecx
    xor  eax, eax
    cmp  ecx, MC_STATE_COUNT
    jae  .done
    lea  r8, [rel mcd_run_start]
    xor  edx, edx                   ; lo
    mov  r9d, [rel mcd_run_count]   ; hi, exclusive
.loop:
    mov  r10d, r9d
    sub  r10d, edx
    cmp  r10d, 1
    jbe  .found
    lea  r10d, [rdx+r9]
    shr  r10d, 1
    cmp  [r8+r10*4], ecx
    ja   .upper
    mov  edx, r10d
    jmp  .loop
.upper:
    mov  r9d, r10d
    jmp  .loop
.found:
    lea  r8, [rel mcd_run_block]
    movzx eax, byte [r8+rdx]
.done:
    ret

; ecx java item id -> eax our block it places, 0 = not a block
LEAF mcmap_item_to_block
    mov  ecx, ecx
    xor  eax, eax
    cmp  ecx, MC_ITEM_COUNT
    jae  .done
    lea  rax, [rel mcd_item_block]
    movzx eax, byte [rax+rcx]
.done:
    ret

; ecx our block/item id (0..255, slots share the byte) -> eax java item id
LEAF mcmap_block_to_item
    movzx ecx, cl
    lea  rax, [rel mcd_block_item]
    movzx eax, word [rax+rcx*2]
    ret

; ecx our biome -> eax java biome index. unknown ones get plains
LEAF mcmap_biome
    mov  ecx, ecx
    mov  eax, MCB_PLAINS
    cmp  ecx, BIOME_COUNT
    jae  .done
    lea  rax, [rel mcd_biome]
    movzx eax, byte [rax+rcx]
.done:
    ret

; rcx zstr -> rax one past its nul
align 16
mcmap_zskip:
.l: inc  rcx
    cmp  byte [rcx-1], 0
    jne  .l
    mov  rax, rcx
    ret

; pw_string(rsi), rsi past it
%macro PW_ZSTR 0
    mov  rcx, rsi
    call pw_string
    mov  rcx, rsi
    call mcmap_zskip
    mov  rsi, rax
%endmacro

; rcx MCCONN*. asks which data packs the client already has. a vanilla 26.1
; client answers minecraft:core 26.1, mineflayer & co answer with nothing
    global mcmap_send_known_packs
    align 16
mcmap_send_known_packs:
    push rbp
    mov  rbp, rsp
    push rsi
    push r12
    sub  rsp, FRAME_OUT
    mov  r12, rcx
    mov  ecx, MCP_CONFIGURATION_S2C_SELECT_KNOWN_PACKS
    call pw_begin
    mov  ecx, 1
    call pw_varint
    lea  rcx, [rel s_pack_ns]
    call pw_string
    lea  rcx, [rel s_pack_id]
    call pw_string
    lea  rcx, [rel s_pack_ver]
    call pw_string
    mov  rcx, r12
    call pw_send
    lea  rsp, [rbp-16]
    pop  r12
    pop  rsi
    pop  rbp
    ret

; (rcx MCCONN*, edx 1 = the client has minecraft:core 26.1) every registry_data,
; then the vanilla tag set. like vanilla: with the core pack every entry goes
; without data and the client uses its own copy, otherwise each carries its nbt.
; the entry order is the same either way, ids don't change.
; feature flags + finish_configuration are the caller's job
PROC mcmap_send_registries
    mov  r12, rcx
    mov  r15d, edx

    ; one registry_data per registry
    lea  rsi, [rel mcd_registries]
.reg:
    cmp  byte [rsi], 0
    je   .tags
    mov  ecx, MCP_CONFIGURATION_S2C_REGISTRY_DATA
    call pw_begin
    PW_ZSTR
    movzx ebx, word [rsi]
    add  rsi, 2
    mov  ecx, ebx
    call pw_varint
.ent:
    test ebx, ebx
    jz   .reg_send
    PW_ZSTR
    mov  edi, [rsi]                 ; nbt length
    add  rsi, 4
    add  rsi, rdi                   ; past the nbt, rsi-rdi is its start
    xor  ecx, ecx
    test r15d, r15d
    jnz  .ent_flag                  ; known pack: has_data = false
    test edi, edi
    setnz cl
.ent_flag:
    mov  r14d, ecx
    call pw_bool
    test r14d, r14d
    jz   .ent_next
    mov  rcx, rsi
    sub  rcx, rdi
    mov  edx, edi
    call pw_bytes
.ent_next:
    dec  ebx
    jmp  .ent
.reg_send:
    mov  rcx, r12
    call pw_send
    jmp  .reg

    ; update_tags: registry -> tags -> varint ids
.tags:
    mov  ecx, MCP_CONFIGURATION_S2C_TAGS
    call pw_begin
    lea  rsi, [rel mcd_tags]
    movzx r13d, word [rsi]
    add  rsi, 2
    mov  ecx, r13d
    call pw_varint
.treg:
    test r13d, r13d
    jz   .tags_send
    PW_ZSTR
    movzx r14d, word [rsi]
    add  rsi, 2
    mov  ecx, r14d
    call pw_varint
.tag:
    test r14d, r14d
    jz   .treg_next
    PW_ZSTR
    movzx ebx, word [rsi]
    add  rsi, 2
    mov  ecx, ebx
    call pw_varint
.tid:
    test ebx, ebx
    jz   .tag_next
    movzx ecx, word [rsi]
    add  rsi, 2
    call pw_varint
    dec  ebx
    jmp  .tid
.tag_next:
    dec  r14d
    jmp  .tag
.treg_next:
    dec  r13d
    jmp  .treg
.tags_send:
    mov  rcx, r12
    call pw_send
ENDP
