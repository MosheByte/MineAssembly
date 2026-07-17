; mcplay.asm - java play state. join, chunk streaming + conversion, movement,
; blocks both ways, chat. java players are creative, the host shows up for them
; as a normal player entity, they show up for us as ENT_REMOTE entities.
; our chunk is 16x128x16 at y 0..127, java's overworld is -64..319 (24 sections):
; below 0 is stone with bedrock at -64, above 127 is air.
%define IMPL_MCPLAY
%include "common.inc"
%include "net.inc"
%include "mcpackets.inc"

%ifndef ENT_REMOTE
%define ENT_REMOTE      8
%endif
%ifndef MCCLOCK_OVERWORLD
%define MCCLOCK_OVERWORLD 0             ; world_clock registry, alphabetical like the rest
%endif

%define HOST_EID        1               ; java players get index+2
%define FIRST_ENT_EID   1000            ; our mobs/items/tnt from here up
%define MAX_VIEW        10              ; chunkmgr loads view+2 around each java player, pool is 1600
%define ITEM_COLLECT    1               ; entity.asm ai_state, item flying into the host

; es_ev bits: what the clients already heard about
%define EV_DEAD         1
%define EV_COLLECT      2
%define CHUNKS_PER_TICK 8
%define JOIN_CHUNKS     25
%define SEND_HIGH       (NET_SEND_CAP/2) ; stop streaming chunks while this much is queued
%define KA_EVERY        10000
%define KA_TIMEOUT      30000
%define SECBYTES        4096
%define LIGHT_SECS      26              ; sections -5..20, one extra each side
%define HM_LONGS        37              ; 256 entries, 9 bits, 7 a long

%define PLF_MOTION      1               ; blocks motion or is fluid (MOTION_BLOCKING)
%define PLF_FLUID       2

extern entity_remove

; PROC without the global
%macro LPROC 1-2 0
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

section .rdata
align 8
c_ang:          dd 0.71111111            ; 256/360
c_one:          dd 1.0
c_20:           dd 20.0
c_5:            dd 5.0
c_180:          dd 180.0
c_fly:          dd 0.05
c_walk:         dd 0.1
c_half:         dq 0.5
c_big:          dq 16777216.0
c_fix:          dq 4096.0               ; relative moves are in 1/4096 block
c_lvl_eps:      dd 0.01
c_vel_eps:      dd 0.000001             ; squared, per tick
c_vel_max:      dd 3.0                  ; lpvec3 scale stays <= 3, no varint tail
c_vel_min:      dd 0.0000305            ; below this lpvec3 is the zero byte
c_quant:        dd 16383.0              ; 32766/2
; our ENT_* -> java entity type + 1 (0 = not sent), tracking range in chunks
pl_jtype:       dd 0, MCE_ITEM+1, MCE_TNT+1, MCE_FALLING_BLOCK+1, MCE_PIG+1
                dd MCE_SHEEP+1, MCE_ZOMBIE+1, 0, 0
pl_jrange:      dd 0, 6, 10, 10, 10, 10, 8, 0, 0
align 16
c_absmask:      dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
c_fabs:         dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
c_deg:          dd 1.40625              ; 360/256
s_overworld:    db "minecraft:overworld", 0
s_yellow:       db "yellow", 0
s_gray:         db "gray", 0
s_hostdef:      db "Host", 0
s_joined:       db "%s joined the game", 0
s_left:         db "%s left the game", 0
s_chatfmt:      db "<%s> %s", 0
s_timeout:      db "Timed out", 0
s_help:         db "commands: /help, /list", 0
s_list:         db "players: ", 0
s_comma:        db ", ", 0
s_unknown:      db "unknown command: /%s", 0
s_cmd_help:     db "help", 0
s_cmd_list:     db "list", 0
s_log_join:     db "net: %s joined, eid %d, view %d", 0

; java face -> offset (down up north south west east)
face_dx:        dd 0, 0, 0, 0, -1, 1
face_dy:        dd -1, 1, 0, 0, 0, 0
face_dz:        dd 0, 0, -1, 1, 0, 0
c_45:           dd 45.0
c_inv90:        dd 0.011111111
; base id -> first turned id, 0 = doesn't turn (BLOCK_BASE in ids.inc)
pl_turn:
%assign i 0
%rep 256
  BLOCK_BASE i
  db BB_TURN
  %assign i i+1
%endrep

section .bss
alignb 16
pl_lut_state:   resd 256                ; our id -> java state
pl_lut_fl:      resb 256                ; PLF_*
pl_pidx:        resw 256                ; our id -> palette index, per section
pl_luts_ok:     resd 1
pl_cur_biome:   resd 1
pl_ticks:       resd 1
pl_tp_next:     resd 1
pl_moved:       resb MAX_NET_CONNS
pl_host_uuid:   resb 16
pl_hraw:        resd 5                  ; host x y z yaw pitch as last broadcast
pl_hpos:        resq 3                  ; host feet, doubles
pl_hrot:        resd 2                  ; host java yaw, pitch
pl_hground:     resd 1
pl_hvalid:      resd 1
; per g_entities slot, what the java clients were told about it
pl_es_jt:       resd MAX_ENTITIES       ; java type + 1, 0 = not tracked
pl_es_eid:      resd MAX_ENTITIES
pl_es_age:      resd MAX_ENTITIES       ; age going down = slot got reused
pl_es_meta:     resd MAX_ENTITIES       ; pl_ent_fp of the last metadata
pl_es_seen:     resd MAX_ENTITIES       ; conn bit = that client has it spawned
pl_es_rot:      resd MAX_ENTITIES       ; yaw | pitch<<8 | head<<16 angle bytes
pl_es_ev:       resd MAX_ENTITIES       ; EV_* | last hurt_time<<8
pl_es_pos:      resq MAX_ENTITIES*3     ; position as sent, 1/4096 blocks
pl_es_vel:      resd MAX_ENTITIES*3     ; velocity as sent, items/tnt/sand only
pl_next_eid:    resd 1
pl_w_state:     resd 1                  ; raining as last broadcast
pl_w_rain:      resd 1
pl_w_thunder:   resd 1
pl_uuid:        resb 16
alignb 16
pl_stone_sec:   resb SECBYTES
pl_bedrock_sec: resb SECBYTES
pl_air_sec:     resb SECBYTES
pl_lsky:        resb 8*2048
pl_lblk:        resb 8*2048
pl_secbuf:      resb 128*1024
pl_pkt:         resb 256*1024

section .text

; little writers, cursor in rdi. trash rax rcx only

align 16
pl_wvar:
    mov  eax, ecx
    and  eax, 0x7F
    shr  ecx, 7
    jz   .last
    or   al, 0x80
    mov  [rdi], al
    inc  rdi
    jmp  pl_wvar
.last:
    mov  [rdi], al
    inc  rdi
    ret

align 16
pl_w8:
    mov  [rdi], cl
    inc  rdi
    ret

align 16
pl_w16:
    mov  eax, ecx
    xchg al, ah
    mov  [rdi], ax
    add  rdi, 2
    ret

align 16
pl_w32:
    mov  eax, ecx
    bswap eax
    mov  [rdi], eax
    add  rdi, 4
    ret

align 16
pl_w64:
    mov  rax, rcx
    bswap rax
    mov  [rdi], rax
    add  rdi, 8
    ret

; bitset as java wants it: no longs when empty
align 16
pl_wmask:
    test rcx, rcx
    jnz  .some
    mov  byte [rdi], 0
    inc  rdi
    ret
.some:
    mov  byte [rdi], 1
    inc  rdi
    jmp  pl_w64

; chunk conversion

LPROC pl_init_luts
    cmp  dword [rel pl_luts_ok], 0
    jne  .done
    xor  ebx, ebx
.l:
    mov  ecx, ebx
    call mcmap_block_state
    lea  rdx, [rel pl_lut_state]
    mov  [rdx+rbx*4], eax
    lea  rdx, [rel blk_flags]
    movzx eax, word [rdx+rbx*2]
    xor  ecx, ecx
    test eax, BF_SOLID|BF_LIQUID
    jz   .nm
    or   ecx, PLF_MOTION
.nm:
    test eax, BF_LIQUID
    jz   .nf
    or   ecx, PLF_FLUID
.nf:
    lea  rdx, [rel pl_lut_fl]
    mov  [rdx+rbx], cl
    inc  ebx
    cmp  ebx, 256
    jb   .l
    lea  rdi, [rel pl_stone_sec]
    mov  al, B_STONE
    mov  ecx, SECBYTES
    rep  stosb
    lea  rdi, [rel pl_bedrock_sec]
    mov  al, B_BEDROCK
    mov  ecx, 256
    rep  stosb
    mov  al, B_STONE
    mov  ecx, SECBYTES-256
    rep  stosb
    mov  dword [rel pl_luts_ok], 1
.done:
ENDP

; (rcx 4096 of our ids, rdx out) -> rax out end. one section: block count,
; fluid count, block states, biomes
LPROC pl_enc_sec, 1056
    mov  rsi, rcx
    mov  rdi, rdx
    lea  rax, [rel pl_pidx]
    mov  ecx, 64
.clr:
    mov  qword [rax], -1
    add  rax, 8
    dec  ecx
    jnz  .clr
    xor  r12d, r12d                 ; non-air
    xor  r13d, r13d                 ; fluid
    xor  r14d, r14d                 ; palette size
    lea  r8, [rel pl_lut_state]
    lea  r9, [rel pl_lut_fl]
    lea  r10, [rel pl_pidx]
    lea  rbx, LOC(0)                ; palette, java states
    xor  r11d, r11d
.p:
    movzx eax, byte [rsi+r11]
    cmp  dword [r8+rax*4], 0
    je   .p1
    inc  r12d
.p1:
    test byte [r9+rax], PLF_FLUID
    jz   .p2
    inc  r13d
.p2:
    cmp  word [r10+rax*2], 0xFFFF
    jne  .p3
    mov  [r10+rax*2], r14w
    mov  edx, [r8+rax*4]
    mov  [rbx+r14*4], edx
    inc  r14d
.p3:
    inc  r11d
    cmp  r11d, SECBYTES
    jb   .p
    mov  ecx, r12d
    call pl_w16
    mov  ecx, r13d
    call pl_w16
    cmp  r14d, 1
    ja   .multi
    xor  ecx, ecx                   ; single value
    call pl_w8
    mov  ecx, [rbx]
    call pl_wvar
    jmp  .biome
.multi:
    mov  r15d, 4
.bits:
    mov  eax, 1
    mov  ecx, r15d
    shl  eax, cl
    cmp  eax, r14d
    jae  .bitsok
    inc  r15d
    jmp  .bits
.bitsok:
    mov  dword LOC(1024), 0
    cmp  r15d, 8
    jbe  .indirect
    mov  r15d, MC_STATE_BITS        ; can't happen with byte ids, but be correct
    mov  dword LOC(1024), 1
    mov  ecx, r15d
    call pl_w8
    jmp  .pack
.indirect:
    mov  ecx, r15d
    call pl_w8
    mov  ecx, r14d
    call pl_wvar
    xor  r12d, r12d
.pal:
    mov  ecx, [rbx+r12*4]
    call pl_wvar
    inc  r12d
    cmp  r12d, r14d
    jb   .pal
.pack:
    mov  eax, 64                    ; entries don't straddle longs
    xor  edx, edx
    div  r15d
    mov  LOC(1028), eax
    xor  r12d, r12d                 ; current long
    xor  r13d, r13d                 ; entries in it
    xor  r11d, r11d
.e:
    movzx eax, byte [rsi+r11]
    cmp  dword LOC(1024), 0
    jne  .direct
    movzx eax, word [r10+rax*2]
    jmp  .put
.direct:
    mov  eax, [r8+rax*4]
.put:
    mov  ecx, r13d
    imul ecx, r15d
    shl  rax, cl
    or   r12, rax
    inc  r13d
    cmp  r13d, LOC(1028)
    jb   .en
    mov  rcx, r12
    call pl_w64
    xor  r12d, r12d
    xor  r13d, r13d
.en:
    inc  r11d
    cmp  r11d, SECBYTES
    jb   .e
    test r13d, r13d
    jz   .biome
    mov  rcx, r12
    call pl_w64
.biome:
    xor  ecx, ecx                   ; one biome for the whole section
    call pl_w8
    mov  ecx, [rel pl_cur_biome]
    call pl_wvar
    mov  rax, rdi
ENDP

; (rcx 4096 light bytes, edx 4 sky / 0 block, r8 out 2048) -> eax 1 if anything nonzero.
; java nibbles: x + z*16 + y*256 like ours, low nibble first
LPROC pl_pack_nib
    mov  rsi, rcx
    mov  ecx, edx
    xor  r9d, r9d
    mov  r10d, 2048
.l:
    movzx eax, byte [rsi]
    shr  eax, cl
    and  eax, 15
    movzx edx, byte [rsi+1]
    shr  edx, cl
    and  edx, 15
    shl  edx, 4
    or   eax, edx
    mov  [r8], al
    or   r9d, eax
    add  rsi, 2
    inc  r8
    dec  r10d
    jnz  .l
    xor  eax, eax
    test r9d, r9d
    setnz al
ENDP

; (rcx CHUNK*, rdx out) -> eax bytes. map_chunk body without the packet id.
; the chunk needs blocks + light (>= CS_LIT)
PROC mcplay_encode_chunk, 640
    mov  rbx, rcx
    mov  r15, rdx
    mov  rdi, rdx
    call pl_init_luts
    mov  ecx, [rbx+CHUNK.cx]
    call pl_w32
    mov  ecx, [rbx+CHUNK.cz]
    call pl_w32

    ; heightmaps. LOC(0) world_surface, LOC(296) motion_blocking, value = top+1 - min y
    lea  rdx, LOC(0)
    xor  eax, eax
    mov  ecx, HM_LONGS*2
.hz:
    mov  [rdx], rax
    add  rdx, 8
    dec  ecx
    jnz  .hz
    lea  r10, [rel pl_lut_fl]
    xor  r12d, r12d                 ; column
    xor  r13d, r13d                 ; long
    xor  r14d, r14d                 ; shift
.hcol:
    lea  rsi, [rbx+CHUNK_BLOCKS+127*256]
    add  rsi, r12
    mov  r8d, -1
    mov  r9d, -1
    mov  r11d, 127
.hy:
    movzx eax, byte [rsi]
    test eax, eax
    jz   .hnext
    cmp  r8d, -1
    jne  .hmb
    mov  r8d, r11d
.hmb:
    test byte [r10+rax], PLF_MOTION
    jz   .hnext
    mov  r9d, r11d                  ; ws is set by now too
    jmp  .hput
.hnext:
    sub  rsi, 256
    dec  r11d
    jns  .hy
.hput:
    sub  r8d, MC_WORLD_MIN_Y-1
    sub  r9d, MC_WORLD_MIN_Y-1
    mov  ecx, r14d
    shl  r8, cl
    shl  r9, cl
    lea  rax, LOC(0)
    or   [rax+r13*8], r8
    or   [rax+r13*8+HM_LONGS*8], r9
    add  r14d, 9
    cmp  r14d, 63
    jb   .hsame
    xor  r14d, r14d
    inc  r13d
.hsame:
    inc  r12d
    cmp  r12d, 256
    jb   .hcol
    mov  ecx, 2
    call pl_wvar
    mov  ecx, 1                     ; WORLD_SURFACE
    call pl_wvar
    lea  rsi, LOC(0)
    call .hm_out
    mov  ecx, 4                     ; MOTION_BLOCKING
    call pl_wvar
    lea  rsi, LOC(HM_LONGS*8)
    call .hm_out
    jmp  .sections
.hm_out:                            ; rsi longs, own little sub, stack stays aligned enough
    mov  ecx, HM_LONGS
    call pl_wvar
    mov  r12d, HM_LONGS
.hmo:
    mov  rcx, [rsi]
    call pl_w64
    add  rsi, 8
    dec  r12d
    jnz  .hmo
    ret

.sections:
    movzx ecx, byte [rbx+CHUNK.biome+8+8*16]
    call mcmap_biome
    mov  [rel pl_cur_biome], eax
    mov  r14, rdi                   ; park the packet cursor, sections need their length first
    lea  rdx, [rel pl_secbuf]
    lea  rcx, [rel pl_bedrock_sec]  ; y -64
    call pl_enc_sec
    mov  r12d, 3
.stone:
    lea  rcx, [rel pl_stone_sec]
    mov  rdx, rax
    call pl_enc_sec
    dec  r12d
    jnz  .stone
    xor  r12d, r12d
.ours:
    mov  ecx, r12d
    shl  ecx, 12
    lea  rcx, [rbx+rcx+CHUNK_BLOCKS]
    mov  rdx, rax
    call pl_enc_sec
    inc  r12d
    cmp  r12d, SECTIONS
    jb   .ours
    mov  r12d, (MC_WORLD_HEIGHT/16) - SECTIONS - 4
.air:
    lea  rcx, [rel pl_air_sec]
    mov  rdx, rax
    call pl_enc_sec
    dec  r12d
    jnz  .air
    lea  rsi, [rel pl_secbuf]
    sub  rax, rsi
    mov  r12, rax
    mov  rdi, r14
    mov  ecx, r12d
    call pl_wvar
    mov  rcx, r12
    rep  movsb
    xor  ecx, ecx                   ; no block entities
    call pl_wvar

    ; light. bit i = section i-5
    xor  r12d, r12d
    xor  r13d, r13d                 ; sky nonzero, bit per our section
    xor  r14d, r14d                 ; block nonzero
.lsec:
    mov  ecx, r12d
    shl  ecx, 12
    lea  rcx, [rbx+rcx+CHUNK_LIGHT]
    mov  edx, 4
    mov  r8d, r12d
    shl  r8d, 11
    lea  rax, [rel pl_lsky]
    add  r8, rax
    call pl_pack_nib
    test eax, eax
    jz   .lsz
    bts  r13d, r12d
.lsz:
    mov  ecx, r12d
    shl  ecx, 12
    lea  rcx, [rbx+rcx+CHUNK_LIGHT]
    xor  edx, edx
    mov  r8d, r12d
    shl  r8d, 11
    lea  rax, [rel pl_lblk]
    add  r8, rax
    call pl_pack_nib
    test eax, eax
    jz   .lbz
    bts  r14d, r12d
.lbz:
    inc  r12d
    cmp  r12d, SECTIONS
    jb   .lsec
    ; above our top it's open sky, below 0 it's dark rock
    mov  eax, r13d
    shl  eax, 5
    or   eax, ((1 << (LIGHT_SECS-5-SECTIONS)) - 1) << (5+SECTIONS)
    mov  LOC(600), rax              ; sky mask
    not  eax
    and  eax, (1 << LIGHT_SECS) - 1
    mov  LOC(608), rax              ; empty sky
    mov  eax, r14d
    shl  eax, 5
    mov  LOC(616), rax              ; block mask
    not  eax
    and  eax, (1 << LIGHT_SECS) - 1
    mov  LOC(624), rax              ; empty block
    mov  rcx, LOC(600)
    call pl_wmask
    mov  rcx, LOC(616)
    call pl_wmask
    mov  rcx, LOC(608)
    call pl_wmask
    mov  rcx, LOC(624)
    call pl_wmask

    ; sky arrays
    mov  rax, LOC(600)
    xor  ecx, ecx
.cnt:
    test rax, rax
    jz   .cntd
    lea  rdx, [rax-1]
    and  rax, rdx
    inc  ecx
    jmp  .cnt
.cntd:
    call pl_wvar
    xor  r12d, r12d
.sky:
    bt   qword LOC(600), r12
    jnc  .skyn
    mov  ecx, 2048
    call pl_wvar
    lea  eax, [r12-5]
    cmp  eax, SECTIONS
    jae  .skyfull
    shl  eax, 11
    lea  rsi, [rel pl_lsky]
    add  rsi, rax
    mov  ecx, 2048
    rep  movsb
    jmp  .skyn
.skyfull:
    mov  al, 0xFF
    mov  ecx, 2048
    rep  stosb
.skyn:
    inc  r12d
    cmp  r12d, LIGHT_SECS
    jb   .sky

    ; block arrays
    mov  eax, r14d
    xor  ecx, ecx
.bcnt:
    test eax, eax
    jz   .bcntd
    lea  edx, [rax-1]
    and  eax, edx
    inc  ecx
    jmp  .bcnt
.bcntd:
    call pl_wvar
    xor  r12d, r12d
.blk:
    bt   r14d, r12d
    jnc  .blkn
    mov  ecx, 2048
    call pl_wvar
    mov  eax, r12d
    shl  eax, 11
    lea  rsi, [rel pl_lblk]
    add  rsi, rax
    mov  ecx, 2048
    rep  movsb
.blkn:
    inc  r12d
    cmp  r12d, SECTIONS
    jb   .blk

    mov  rax, rdi
    sub  rax, r15
ENDP

; helpers

; rcx conn -> eax 1 when it's in play and joined
align 16
pl_ready:
    xor  eax, eax
    cmp  dword [rcx+MCCONN.state], CN_PLAY
    jne  .r
    test dword [rcx+MCCONN.flags], CF_JOINED
    setnz al
.r: ret

align 16
pl_angle:
    mulss xmm0, [rel c_ang]
    cvtss2si eax, xmm0
    and  eax, 255
    ret

; (rcx conn, edx cx, r8d cz) -> rax byte in the sent bitset, ecx bit mask
align 16
pl_bitp:
    mov  rax, [rcx+MCCONN.sent]
    and  edx, 63
    and  r8d, 63
    shl  r8d, 6
    or   edx, r8d
    mov  ecx, edx
    and  ecx, 7
    shr  edx, 3
    add  rax, rdx
    mov  edx, 1
    shl  edx, cl
    mov  ecx, edx
    ret

; (rcx conn, edx cx, r8d cz) -> eax 1 if that client has the chunk
LPROC pl_has_chunk
    mov  rbx, rcx
    mov  esi, edx
    mov  edi, r8d
    xor  r12d, r12d
    mov  eax, esi
    sub  eax, [rbx+MCCONN.ccx]
    cdq
    xor  eax, edx
    sub  eax, edx
    cmp  eax, [rbx+MCCONN.view]
    ja   .done
    mov  eax, edi
    sub  eax, [rbx+MCCONN.ccz]
    cdq
    xor  eax, edx
    sub  eax, edx
    cmp  eax, [rbx+MCCONN.view]
    ja   .done
    mov  rcx, rbx
    mov  edx, esi
    mov  r8d, edi
    call pl_bitp
    test [rax], cl
    setnz r12b
.done:
    mov  eax, r12d
ENDP

; rcx conn -> eax chunk x, edx chunk z of its feet
align 16
pl_conn_chunk:
    movsd xmm0, [rcx+MCCONN.x]
    roundsd xmm0, xmm0, 1
    cvttsd2si eax, xmm0
    sar  eax, 4
    movsd xmm1, [rcx+MCCONN.z]
    roundsd xmm1, xmm1, 1
    cvttsd2si edx, xmm1
    sar  edx, 4
    ret

; send g_pw to every joined java player except rcx (0 = nobody)
LPROC pl_bcast
    mov  r12, rcx
    lea  rbx, [rel g_net_conns]
    xor  esi, esi
.l:
    cmp  rbx, r12
    je   .n
    mov  rcx, rbx
    call pl_ready
    test eax, eax
    jz   .n
    mov  rcx, rbx
    call pw_send
.n:
    add  rbx, MCCONN_size
    inc  esi
    cmp  esi, MAX_NET_CONNS
    jb   .l
ENDP

; -> rax host display name
align 16
pl_host_name:
    lea  rax, [rel g_net_host_name]
    cmp  byte [rax], 0
    jne  .r
    lea  rax, [rel s_hostdef]
.r: ret

LPROC pl_host_refresh
    lea  rsi, [rel g_player]
    lea  rdi, [rel pl_hraw]
    xor  ebx, ebx
    mov  eax, [rsi+PLAYER.x]
    cmp  eax, [rdi]
    setne cl
    or   bl, cl
    mov  [rdi], eax
    mov  eax, [rsi+PLAYER.y]
    cmp  eax, [rdi+4]
    setne cl
    or   bl, cl
    mov  [rdi+4], eax
    mov  eax, [rsi+PLAYER.z]
    cmp  eax, [rdi+8]
    setne cl
    or   bl, cl
    mov  [rdi+8], eax
    mov  eax, [rsi+PLAYER.yaw]
    cmp  eax, [rdi+12]
    setne cl
    or   bl, cl
    mov  [rdi+12], eax
    mov  eax, [rsi+PLAYER.pitch]
    cmp  eax, [rdi+16]
    setne cl
    or   bl, cl
    mov  [rdi+16], eax
    cvtss2sd xmm0, [rsi+PLAYER.x]
    movsd [rel pl_hpos], xmm0
    cvtss2sd xmm0, [rsi+PLAYER.y]
    movsd [rel pl_hpos+8], xmm0
    cvtss2sd xmm0, [rsi+PLAYER.z]
    movsd [rel pl_hpos+16], xmm0
    movss xmm0, [rsi+PLAYER.yaw]    ; ours looks -z at 0, java +z
    addss xmm0, [rel c_180]
    movss [rel pl_hrot], xmm0
    xorps xmm0, xmm0
    subss xmm0, [rsi+PLAYER.pitch]  ; ours + is up
    movss [rel pl_hrot+4], xmm0
    mov  eax, [rsi+PLAYER.on_ground]
    mov  [rel pl_hground], eax
    mov  dword [rel pl_hvalid], 1
    mov  eax, ebx
ENDP

; (ecx eid, rdx uuid, r8 double[3], r9 java yaw/pitch) -> spawn_entity in g_pw
LPROC pl_pw_spawn
    mov  ebx, ecx
    mov  rsi, rdx
    mov  rdi, r8
    mov  r12, r9
    mov  ecx, MCP_PLAY_S2C_SPAWN_ENTITY
    call pw_begin
    mov  ecx, ebx
    call pw_varint
    mov  rcx, rsi
    call pw_uuid
    mov  ecx, MCE_PLAYER
    call pw_varint
    movsd xmm0, [rdi]
    call pw_f64
    movsd xmm0, [rdi+8]
    call pw_f64
    movsd xmm0, [rdi+16]
    call pw_f64
    xor  ecx, ecx                   ; velocity, lpvec3 zero is one byte
    call pw_u8
    movss xmm0, [r12+4]
    call pl_angle
    mov  ecx, eax
    call pw_u8
    movss xmm0, [r12]
    call pl_angle
    mov  ecx, eax
    call pw_u8
    movss xmm0, [r12]               ; head
    call pl_angle
    mov  ecx, eax
    call pw_u8
    xor  ecx, ecx
    call pw_varint
ENDP

; (ecx eid, rdx except conn, r8 double[3], r9 java yaw/pitch, ARG5 on ground)
; teleport + head rotation to everyone but except
LPROC pl_send_move
    mov  ebx, ecx
    mov  r13, rdx
    mov  rdi, r8
    mov  r12, r9
    mov  ecx, MCP_PLAY_S2C_ENTITY_TELEPORT
    call pw_begin
    mov  ecx, ebx
    call pw_varint
    movsd xmm0, [rdi]
    call pw_f64
    movsd xmm0, [rdi+8]
    call pw_f64
    movsd xmm0, [rdi+16]
    call pw_f64
    mov  esi, 3
.vel:
    xorps xmm0, xmm0
    call pw_f64
    dec  esi
    jnz  .vel
    movss xmm0, [r12]
    call pw_f32
    movss xmm0, [r12+4]
    call pw_f32
    xor  ecx, ecx                   ; all absolute
    call pw_i32
    mov  ecx, ARG5
    call pw_bool
    mov  rcx, r13
    call pl_bcast
    mov  ecx, MCP_PLAY_S2C_ENTITY_HEAD_ROTATION
    call pw_begin
    mov  ecx, ebx
    call pw_varint
    movss xmm0, [r12]
    call pl_angle
    mov  ecx, eax
    call pw_u8
    mov  rcx, r13
    call pl_bcast
ENDP

; (rcx uuid, rdx name, r8d gamemode) one player_info entry for actions add|gamemode|listed
LPROC pl_pw_info_entry
    mov  rbx, rdx
    mov  esi, r8d
    call pw_uuid
    mov  rcx, rbx
    call pw_string
    xor  ecx, ecx                   ; no properties
    call pw_varint
    mov  ecx, esi
    call pw_varint
    mov  ecx, 1
    call pw_bool
ENDP

; (rcx conn) entity view of a java player for pl_pw_spawn: eid, uuid, pos, rot
LPROC pl_pw_spawn_conn
    mov  rbx, rcx
    mov  ecx, [rbx+MCCONN.eid]
    lea  rdx, [rbx+MCCONN.uuid]
    lea  r8, [rbx+MCCONN.x]
    lea  r9, [rbx+MCCONN.yaw]
    call pl_pw_spawn
ENDP

; (rcx conn, edx x, r8d y, r9d z) block_change with whatever is really there
LPROC pl_resync, 16
    mov  rbx, rcx
    mov  esi, edx
    mov  edi, r8d
    mov  r12d, r9d
    mov  ecx, esi
    mov  edx, edi
    mov  r8d, r12d
    call pl_state_at
    mov  r13d, eax
    mov  ecx, MCP_PLAY_S2C_BLOCK_CHANGE
    call pw_begin
    mov  ecx, esi
    mov  edx, edi
    mov  r8d, r12d
    call pw_position
    mov  ecx, r13d
    call pw_varint
    mov  rcx, rbx
    call pw_send
ENDP

LPROC pl_state_at
    call pl_init_luts
    cmp  edx, 0
    jl   .rock
    cmp  edx, CHUNK_H
    jge  .air
    call world_get_block
    movzx eax, al
    lea  rdx, [rel pl_lut_state]
    mov  eax, [rdx+rax*4]
    jmp  .done
.rock:
    mov  eax, [rel pl_lut_state + B_STONE*4]
    cmp  edx, MC_WORLD_MIN_Y
    jne  .done
    mov  eax, [rel pl_lut_state + B_BEDROCK*4]
    jmp  .done
.air:
    xor  eax, eax
.done:
ENDP
