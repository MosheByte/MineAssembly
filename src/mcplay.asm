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

; (rcx conn, edx sequence)
LPROC pl_ack
    mov  rbx, rcx
    mov  esi, edx
    mov  ecx, MCP_PLAY_S2C_ACKNOWLEDGE_PLAYER_DIGGING
    call pw_begin
    mov  ecx, esi
    call pw_varint
    mov  rcx, rbx
    call pw_send
ENDP

; (rcx conn or 0 = all) world time + the overworld clock
LPROC pl_send_time
    mov  rbx, rcx
    mov  ecx, MCP_PLAY_S2C_UPDATE_TIME
    call pw_begin
    mov  rcx, [rel g_world_time]
    call pw_i64
    mov  ecx, 1
    call pw_varint
    mov  ecx, MCCLOCK_OVERWORLD
    call pw_varint
    mov  rax, [rel g_world_time]    ; whole days so far + our time of day, our 0 = sunrise = java 0
    xor  edx, edx
    mov  ecx, DAY_LENGTH
    div  rcx
    mov  rax, [rel g_world_time]
    sub  rax, rdx
    mov  ecx, [rel g_time_of_day]
    add  rcx, rax
    call pw_varlong
    xorps xmm0, xmm0
    call pw_f32
    movss xmm0, [rel c_one]
    call pw_f32
    test rbx, rbx
    jz   .all
    mov  rcx, rbx
    call pw_send
    jmp  .done
.all:
    xor  ecx, ecx
    call pl_bcast
.done:
ENDP

; (rcx text, rdx colour name or 0, r8 conn or 0 = everyone) system chat
LPROC pl_say
    mov  rbx, r8
    test rdx, rdx
    jnz  .col
    mov  rsi, rcx
    mov  ecx, MCP_PLAY_S2C_SYSTEM_CHAT
    call pw_begin
    mov  rcx, rsi
    call pw_text
    jmp  .tail
.col:
    mov  rsi, rcx
    mov  rdi, rdx
    mov  ecx, MCP_PLAY_S2C_SYSTEM_CHAT
    call pw_begin
    mov  rcx, rsi
    mov  rdx, rdi
    call pw_text_color
.tail:
    xor  ecx, ecx
    call pw_bool
    test rbx, rbx
    jz   .all
    mov  rcx, rbx
    call pw_send
    jmp  .done
.all:
    xor  ecx, ecx
    call pl_bcast
.done:
ENDP

; (rcx dst 256, rdx src) copy dropping control chars and our \f colour codes
LPROC pl_clean
    mov  r8d, 255
.l:
    movzx eax, byte [rdx]
    test eax, eax
    jz   .end
    inc  rdx
    cmp  eax, 12
    jne  .nf
    cmp  byte [rdx], 0
    je   .end
    inc  rdx                        ; skip the colour digit
    jmp  .l
.nf:
    cmp  eax, 32
    jb   .l
    mov  [rcx], al
    inc  rcx
    dec  r8d
    jnz  .l
.end:
    mov  byte [rcx], 0
ENDP

; chunk streaming

; (rcx conn, rdx CHUNK*)
LPROC pl_send_chunk
    mov  rbx, rcx
    mov  rsi, rdx
    lea  rdi, [rel pl_pkt]
    mov  ecx, MCP_PLAY_S2C_MAP_CHUNK
    call pl_wvar
    lea  r12, [rel pl_pkt]
    mov  r13, rdi
    sub  r13, r12                   ; id length
    mov  rcx, rsi
    mov  rdx, rdi
    call mcplay_encode_chunk
    add  eax, r13d
    mov  rcx, rbx
    mov  rdx, r12
    mov  r8d, eax
    call net_send_frame
ENDP

; (rcx conn, edx budget) move the centre, drop what fell out, send what's
; missing nearest first
LPROC pl_stream, 48
    mov  rbx, rcx
    mov  r15d, edx
    mov  rcx, rbx
    call pl_conn_chunk
    mov  r12d, eax
    mov  r13d, edx
    cmp  r12d, [rbx+MCCONN.ccx]
    jne  .moved
    cmp  r13d, [rbx+MCCONN.ccz]
    je   .send
.moved:
    mov  ecx, MCP_PLAY_S2C_UPDATE_VIEW_POSITION
    call pw_begin
    mov  ecx, r12d
    call pw_varint
    mov  ecx, r13d
    call pw_varint
    mov  rcx, rbx
    call pw_send
    mov  esi, [rbx+MCCONN.view]
    neg  esi                        ; dz
.uz:
    mov  edi, [rbx+MCCONN.view]
    neg  edi                        ; dx
.ux:
    mov  eax, [rbx+MCCONN.ccx]
    add  eax, edi
    mov  LOC(0), eax                ; old chunk x
    mov  eax, [rbx+MCCONN.ccz]
    add  eax, esi
    mov  LOC(4), eax
    mov  eax, LOC(0)
    sub  eax, r12d
    cdq
    xor  eax, edx
    sub  eax, edx
    cmp  eax, [rbx+MCCONN.view]
    ja   .drop
    mov  eax, LOC(4)
    sub  eax, r13d
    cdq
    xor  eax, edx
    sub  eax, edx
    cmp  eax, [rbx+MCCONN.view]
    jbe  .keep
.drop:
    mov  rcx, rbx
    mov  edx, LOC(0)
    mov  r8d, LOC(4)
    call pl_bitp
    test [rax], cl
    jz   .keep
    not  ecx
    and  [rax], cl
    mov  ecx, MCP_PLAY_S2C_UNLOAD_CHUNK
    call pw_begin
    mov  ecx, LOC(4)                ; z first on this one
    call pw_i32
    mov  ecx, LOC(0)
    call pw_i32
    mov  rcx, rbx
    call pw_send
.keep:
    inc  edi
    cmp  edi, [rbx+MCCONN.view]
    jle  .ux
    inc  esi
    cmp  esi, [rbx+MCCONN.view]
    jle  .uz
    mov  [rbx+MCCONN.ccx], r12d
    mov  [rbx+MCCONN.ccz], r13d

.send:
    xor  r14d, r14d                 ; sent
    mov  dword LOC(8), 0            ; batch started
    mov  dword LOC(12), 0           ; ring
.ring:
    mov  esi, LOC(12)
    neg  esi
.rz:
    mov  edi, LOC(12)
    neg  edi
.rx:
    mov  eax, edi                   ; only the ring itself: max(|dx|,|dz|) == d
    cdq
    xor  eax, edx
    sub  eax, edx
    mov  ecx, eax
    mov  eax, esi
    cdq
    xor  eax, edx
    sub  eax, edx
    cmp  eax, ecx
    cmovl eax, ecx
    cmp  eax, LOC(12)
    jne  .next
    cmp  r14d, r15d
    jae  .fin
    mov  eax, [rbx+MCCONN.slen]     ; still queued, net kills us if it overflows
    sub  eax, [rbx+MCCONN.soff]
    cmp  eax, SEND_HIGH
    ja   .fin
    lea  eax, [r12d+edi]
    mov  LOC(0), eax
    lea  eax, [r13d+esi]
    mov  LOC(4), eax
    mov  rcx, rbx
    mov  edx, LOC(0)
    mov  r8d, LOC(4)
    call pl_bitp
    test [rax], cl
    jnz  .next
    mov  LOC(16), rax
    mov  LOC(24), ecx
    mov  ecx, LOC(0)
    mov  edx, LOC(4)
    call world_get_chunk
    test rax, rax
    jz   .next
    cmp  dword [rax+CHUNK.state], CS_LIT
    jb   .next
    mov  LOC(32), rax
    cmp  dword LOC(8), 0
    jne  .started
    mov  dword LOC(8), 1
    mov  ecx, MCP_PLAY_S2C_CHUNK_BATCH_START
    call pw_begin
    mov  rcx, rbx
    call pw_send
.started:
    mov  rcx, rbx
    mov  rdx, LOC(32)
    call pl_send_chunk
    mov  rax, LOC(16)
    mov  ecx, LOC(24)
    or   [rax], cl
    inc  r14d
.next:
    inc  edi
    cmp  edi, LOC(12)
    jle  .rx
    inc  esi
    cmp  esi, LOC(12)
    jle  .rz
    inc  dword LOC(12)
    mov  eax, LOC(12)
    cmp  eax, [rbx+MCCONN.view]
    jle  .ring
.fin:
    cmp  dword LOC(8), 0
    je   .done
    mov  ecx, MCP_PLAY_S2C_CHUNK_BATCH_FINISHED
    call pw_begin
    mov  ecx, r14d
    call pw_varint
    mov  rcx, rbx
    call pw_send
.done:
ENDP

; join / leave

; (rcx MCCONN*) config is done, put them in the world
PROC mcplay_join, 320
    mov  rbx, rcx
    call pl_init_luts
    cmp  qword [rbx+MCCONN.sent], 0
    jne  .hasbits
    mov  ecx, 512
    call mem_alloc
    test rax, rax
    jz   .nomem
    mov  [rbx+MCCONN.sent], rax
    jmp  .bitsok
.hasbits:
    mov  rdi, [rbx+MCCONN.sent]
    xor  eax, eax
    mov  ecx, 64
    rep  stosq
.bitsok:
    cmp  dword [rbx+MCCONN.eid], 0
    jne  .haseid
    mov  eax, [rbx+MCCONN.index]
    add  eax, 2
    mov  [rbx+MCCONN.eid], eax
.haseid:
    mov  eax, [rbx+MCCONN.view]
    test eax, eax
    jnz  .hv
    mov  eax, 8
.hv:
    mov  ecx, 2
    cmp  eax, ecx
    cmovl eax, ecx
    mov  ecx, MAX_VIEW
    cmp  eax, ecx
    cmovg eax, ecx
    mov  [rbx+MCCONN.view], eax
    mov  r12d, eax                  ; view
    mov  eax, [rbx+MCCONN.index]
    lea  rcx, [rel pl_moved]
    mov  byte [rcx+rax], 0
    mov  ecx, eax                   ; a fresh client has none of our entities
    call pl_es_unsee
    mov  qword [rbx+MCCONN.ent], 0
    mov  dword [rbx+MCCONN.held_slot], 0
    lea  rdi, [rbx+MCCONN.hotbar]
    xor  eax, eax
    mov  ecx, 9
    rep  stosd
    call pl_host_name
    mov  rcx, rax
    lea  rdx, [rel pl_host_uuid]
    call mc_offline_uuid
    call pl_host_refresh

    ; spawn on the host's column, on top of whatever is there
    movss xmm0, [rel g_player+PLAYER.x]
    call math_floor
    mov  esi, eax
    movss xmm0, [rel g_player+PLAYER.z]
    call math_floor
    mov  edi, eax
    mov  LOC(256), esi
    mov  LOC(260), edi
    mov  ecx, esi
    mov  edx, edi
    call world_height_at
    cvtsi2sd xmm0, esi
    addsd xmm0, [rel c_half]
    movsd [rbx+MCCONN.x], xmm0
    cvtsi2sd xmm0, edi
    addsd xmm0, [rel c_half]
    movsd [rbx+MCCONN.z], xmm0
    cmp  eax, -1
    je   .noground
    inc  eax
    cvtsi2sd xmm0, eax
    jmp  .sety
.noground:
    cvtss2sd xmm0, [rel g_player+PLAYER.y]
.sety:
    movsd [rbx+MCCONN.y], xmm0
    mov  dword [rbx+MCCONN.yaw], 0
    mov  dword [rbx+MCCONN.pitch], 0
    mov  dword [rbx+MCCONN.on_ground], 0
    mov  rcx, rbx
    call pl_conn_chunk
    mov  [rbx+MCCONN.ccx], eax
    mov  [rbx+MCCONN.ccz], edx

    ; login (play)
    mov  ecx, MCP_PLAY_S2C_LOGIN
    call pw_begin
    mov  ecx, [rbx+MCCONN.eid]
    call pw_i32
    xor  ecx, ecx                   ; hardcore
    call pw_bool
    mov  ecx, 1
    call pw_varint
    lea  rcx, [rel s_overworld]
    call pw_string
    mov  ecx, MAX_NET_CONNS+1
    call pw_varint
    mov  ecx, r12d
    call pw_varint                  ; view distance
    mov  ecx, r12d
    call pw_varint                  ; simulation distance
    xor  ecx, ecx                   ; reduced debug info
    call pw_bool
    mov  ecx, 1                     ; respawn screen
    call pw_bool
    xor  ecx, ecx                   ; limited crafting
    call pw_bool
    mov  ecx, MCDIM_OVERWORLD
    call pw_varint
    lea  rcx, [rel s_overworld]
    call pw_string
    mov  rcx, [rel g_seed]
    call pw_i64
    mov  ecx, GM_CREATIVE
    call pw_u8
    mov  ecx, 0xFF                  ; previous gamemode, none
    call pw_u8
    xor  ecx, ecx                   ; debug
    call pw_bool
    xor  ecx, ecx                   ; flat
    call pw_bool
    xor  ecx, ecx                   ; no death location
    call pw_bool
    xor  ecx, ecx                   ; portal cooldown
    call pw_varint
    mov  ecx, SEA_LEVEL
    call pw_varint
    xor  ecx, ecx                   ; secure chat
    call pw_bool
    mov  rcx, rbx
    call pw_send

    ; creative: invulnerable, may fly, instabreak
    mov  ecx, MCP_PLAY_S2C_ABILITIES
    call pw_begin
    mov  ecx, 0x0D
    call pw_u8
    movss xmm0, [rel c_fly]
    call pw_f32
    movss xmm0, [rel c_walk]
    call pw_f32
    mov  rcx, rbx
    call pw_send

    ; full health + food. vanilla sends it on join, some clients wait for it
    mov  ecx, MCP_PLAY_S2C_UPDATE_HEALTH
    call pw_begin
    movss xmm0, [rel c_20]
    call pw_f32
    mov  ecx, 20
    call pw_varint
    movss xmm0, [rel c_5]
    call pw_f32
    mov  rcx, rbx
    call pw_send

    ; tab list for them: host, everyone already here, themselves
    mov  ecx, MCP_PLAY_S2C_PLAYER_INFO
    call pw_begin
    mov  ecx, 0x0D                  ; add_player | update_game_mode | update_listed
    call pw_u8
    mov  rcx, rbx
    call pl_count_others
    lea  ecx, [rax+2]
    call pw_varint
    lea  rcx, [rel pl_host_uuid]
    mov  r13, rcx
    call pl_host_name
    mov  rdx, rax
    mov  rcx, r13
    mov  r8d, [rel g_gamemode]
    call pl_pw_info_entry
    lea  rsi, [rel g_net_conns]
    xor  r14d, r14d
.tl:
    cmp  rsi, rbx
    je   .tn
    mov  rcx, rsi
    call pl_ready
    test eax, eax
    jz   .tn
    lea  rcx, [rsi+MCCONN.uuid]
    lea  rdx, [rsi+MCCONN.name]
    mov  r8d, GM_CREATIVE
    call pl_pw_info_entry
.tn:
    add  rsi, MCCONN_size
    inc  r14d
    cmp  r14d, MAX_NET_CONNS
    jb   .tl
    lea  rcx, [rbx+MCCONN.uuid]
    lea  rdx, [rbx+MCCONN.name]
    mov  r8d, GM_CREATIVE
    call pl_pw_info_entry
    mov  rcx, rbx
    call pw_send

    ; and them for everyone else
    mov  ecx, MCP_PLAY_S2C_PLAYER_INFO
    call pw_begin
    mov  ecx, 0x0D
    call pw_u8
    mov  ecx, 1
    call pw_varint
    lea  rcx, [rbx+MCCONN.uuid]
    lea  rdx, [rbx+MCCONN.name]
    mov  r8d, GM_CREATIVE
    call pl_pw_info_entry
    mov  rcx, rbx
    call pl_bcast

    mov  rcx, rbx
    call pl_send_pos

    mov  ecx, MCP_PLAY_S2C_UPDATE_VIEW_POSITION
    call pw_begin
    mov  ecx, [rbx+MCCONN.ccx]
    call pw_varint
    mov  ecx, [rbx+MCCONN.ccz]
    call pw_varint
    mov  rcx, rbx
    call pw_send

    ; spawn point (respawn data: global pos + angles)
    mov  ecx, MCP_PLAY_S2C_SPAWN_POSITION
    call pw_begin
    lea  rcx, [rel s_overworld]
    call pw_string
    movsd xmm0, [rbx+MCCONN.y]
    cvttsd2si edx, xmm0
    mov  ecx, LOC(256)
    mov  r8d, LOC(260)
    call pw_position
    xorps xmm0, xmm0
    call pw_f32
    xorps xmm0, xmm0
    call pw_f32
    mov  rcx, rbx
    call pw_send

    mov  rcx, rbx
    call pl_send_time

    ; already raining? vanilla sends start + both levels on join
    cmp  dword [rel g_weather], 1
    jb   .dry
    xorps xmm1, xmm1
    mov  ecx, 1
    mov  rdx, rbx
    call pl_game_event
    movss xmm1, [rel g_rain]
    mov  ecx, 7
    mov  rdx, rbx
    call pl_game_event
    movss xmm1, [rel g_thunder]
    mov  ecx, 8
    mov  rdx, rbx
    call pl_game_event
.dry:

    mov  ecx, MCP_PLAY_S2C_GAME_STATE_CHANGE
    call pw_begin
    mov  ecx, 13                    ; start waiting for level chunks
    call pw_u8
    xorps xmm0, xmm0
    call pw_f32
    mov  rcx, rbx
    call pw_send

    ; the host's body
    mov  ecx, HOST_EID
    lea  rdx, [rel pl_host_uuid]
    lea  r8, [rel pl_hpos]
    lea  r9, [rel pl_hrot]
    call pl_pw_spawn
    mov  rcx, rbx
    call pw_send

    ; everyone else's, and theirs for everyone else
    lea  rsi, [rel g_net_conns]
    xor  r14d, r14d
.sl:
    cmp  rsi, rbx
    je   .sn
    mov  rcx, rsi
    call pl_ready
    test eax, eax
    jz   .sn
    mov  rcx, rsi
    call pl_pw_spawn_conn
    mov  rcx, rbx
    call pw_send
.sn:
    add  rsi, MCCONN_size
    inc  r14d
    cmp  r14d, MAX_NET_CONNS
    jb   .sl
    mov  rcx, rbx
    call pl_pw_spawn_conn
    mov  rcx, rbx
    call pl_bcast

    call time_ms
    mov  [rbx+MCCONN.ka_id], rax
    mov  qword [rbx+MCCONN.ka_time], 0
    mov  [rbx+MCCONN.last_rx], rax
    or   dword [rbx+MCCONN.flags], CF_JOINED

    mov  rcx, rbx
    mov  edx, JOIN_CHUNKS
    call pl_stream
    or   dword [rbx+MCCONN.flags], CF_SPAWNED

    lea  rcx, [rel s_log_join]
    lea  rdx, [rbx+MCCONN.name]
    mov  r8d, [rbx+MCCONN.eid]
    mov  r9d, [rbx+MCCONN.view]
    call log_printf
    lea  rcx, LOC(0)
    lea  rdx, [rel s_joined]
    lea  r8, [rbx+MCCONN.name]
    call str_format
    lea  rcx, LOC(0)
    lea  rdx, [rel s_yellow]
    xor  r8d, r8d
    call pl_say
    lea  rcx, LOC(0)
    mov  edx, 0xFFFFFF55
    call chat_add
    jmp  .done
.nomem:
    mov  rcx, rbx
    xor  edx, edx
    call net_close
.done:
ENDP

; rcx conn -> eax how many other joined java players there are
align 16
pl_count_others:
    push rbx
    push rsi
    lea  rdx, [rel g_net_conns]
    xor  eax, eax
    xor  esi, esi
    mov  r8, rcx
.l:
    cmp  rdx, r8
    je   .n
    cmp  dword [rdx+MCCONN.state], CN_PLAY
    jne  .n
    test dword [rdx+MCCONN.flags], CF_JOINED
    jz   .n
    inc  eax
.n:
    add  rdx, MCCONN_size
    inc  esi
    cmp  esi, MAX_NET_CONNS
    jb   .l
    pop  rsi
    pop  rbx
    ret

; (rcx conn) absolute player_position, they answer with accept_teleportation
LPROC pl_send_pos
    mov  rbx, rcx
    mov  eax, [rel pl_tp_next]
    inc  eax
    mov  [rel pl_tp_next], eax
    mov  [rbx+MCCONN.tp_id], eax
    mov  ecx, MCP_PLAY_S2C_POSITION
    call pw_begin
    mov  ecx, [rbx+MCCONN.tp_id]
    call pw_varint
    movsd xmm0, [rbx+MCCONN.x]
    call pw_f64
    movsd xmm0, [rbx+MCCONN.y]
    call pw_f64
    movsd xmm0, [rbx+MCCONN.z]
    call pw_f64
    mov  esi, 3
.vel:
    xorps xmm0, xmm0
    call pw_f64
    dec  esi
    jnz  .vel
    movss xmm0, [rbx+MCCONN.yaw]
    call pw_f32
    movss xmm0, [rbx+MCCONN.pitch]
    call pw_f32
    xor  ecx, ecx
    call pw_i32
    mov  rcx, rbx
    call pw_send
ENDP

; (rcx MCCONN*) the connection is going away
PROC mcplay_left, 320
    mov  rbx, rcx
    test rbx, rbx
    jz   .done
    mov  ecx, [rbx+MCCONN.index]
    call pl_es_unsee
    mov  rcx, [rbx+MCCONN.ent]
    mov  edx, [rbx+MCCONN.index]
    call pl_own_ent
    test rax, rax
    jz   .noent
    mov  rcx, rax
    call entity_remove
.noent:
    mov  qword [rbx+MCCONN.ent], 0
    test dword [rbx+MCCONN.flags], CF_JOINED
    jz   .free
    and  dword [rbx+MCCONN.flags], ~(CF_JOINED|CF_SPAWNED)
    mov  ecx, MCP_PLAY_S2C_ENTITY_DESTROY
    call pw_begin
    mov  ecx, 1
    call pw_varint
    mov  ecx, [rbx+MCCONN.eid]
    call pw_varint
    mov  rcx, rbx
    call pl_bcast
    mov  ecx, MCP_PLAY_S2C_PLAYER_REMOVE
    call pw_begin
    mov  ecx, 1
    call pw_varint
    lea  rcx, [rbx+MCCONN.uuid]
    call pw_uuid
    mov  rcx, rbx
    call pl_bcast
    lea  rcx, LOC(0)
    lea  rdx, [rel s_left]
    lea  r8, [rbx+MCCONN.name]
    call str_format
    lea  rcx, LOC(0)
    lea  rdx, [rel s_yellow]
    xor  r8d, r8d
    call pl_say
    lea  rcx, LOC(0)
    mov  edx, 0xFFFFFF55
    call chat_add
.free:
    ; .sent stays: net.asm owns it (part of the slot block), mcplay_join only
    ; allocates one when nobody did
.done:
ENDP

; (rcx ENTITY* or 0, edx conn index) -> rax the same if it's still that remote
; player, else 0. entity_clear on world exit can recycle the slot under us
align 16
pl_own_ent:
    xor  eax, eax
    test rcx, rcx
    jz   .r
    cmp  byte [rcx+ENTITY.type], ENT_REMOTE
    jne  .r
    movzx r8d, byte [rcx+ENTITY.variant]
    cmp  r8d, edx
    jne  .r
    mov  rax, rcx
.r: ret

; serverbound

; (rcx MCCONN*, edx packet id, r8 PKTR*)
; movement field readers for mcplay_handle, results in LOC(0..)
%macro RD_XYZ 0
    mov  dword LOC(64), 1
    mov  rcx, rdi
    call pr_f64
    movsd LOC(0), xmm0
    mov  rcx, rdi
    call pr_f64
    movsd LOC(8), xmm0
    mov  rcx, rdi
    call pr_f64
    movsd LOC(16), xmm0
%endmacro
%macro RD_ROT 0
    mov  dword LOC(68), 1
    mov  rcx, rdi
    call pr_f32
    movss LOC(24), xmm0
    mov  rcx, rdi
    call pr_f32
    movss LOC(28), xmm0
%endmacro
%macro RD_FLAGS 0
    mov  rcx, rdi
    call pr_u8
    and  eax, 1
    mov  LOC(32), eax
%endmacro

PROC mcplay_handle, 896
    mov  rbx, rcx
    mov  esi, edx
    mov  rdi, r8
    mov  qword LOC(64), 0
    test dword [rbx+MCCONN.flags], CF_JOINED
    jz   .done
    call time_ms
    mov  [rbx+MCCONN.last_rx], rax
    cmp  esi, MCP_PLAY_C2S_POSITION
    je   .pos
    cmp  esi, MCP_PLAY_C2S_POSITION_LOOK
    je   .poslook
    cmp  esi, MCP_PLAY_C2S_LOOK
    je   .look
    cmp  esi, MCP_PLAY_C2S_FLYING
    je   .flying
    cmp  esi, MCP_PLAY_C2S_TELEPORT_CONFIRM
    je   .tpconfirm
    cmp  esi, MCP_PLAY_C2S_KEEP_ALIVE
    je   .ka
    cmp  esi, MCP_PLAY_C2S_CHAT_MESSAGE
    je   .chat
    cmp  esi, MCP_PLAY_C2S_CHAT_COMMAND
    je   .command
    cmp  esi, MCP_PLAY_C2S_BLOCK_DIG
    je   .dig
    cmp  esi, MCP_PLAY_C2S_BLOCK_PLACE
    je   .place
    cmp  esi, MCP_PLAY_C2S_SET_CREATIVE_SLOT
    je   .creative
    cmp  esi, MCP_PLAY_C2S_HELD_ITEM_SLOT
    je   .held
    cmp  esi, MCP_PLAY_C2S_ARM_ANIMATION
    je   .swing
    jmp  .done                      ; tick_end, player_loaded, settings, batch acks...

.pos:
    RD_XYZ
    RD_FLAGS
    jmp  .apply
.poslook:
    RD_XYZ
    RD_ROT
    RD_FLAGS
    jmp  .apply
.look:
    RD_ROT
    RD_FLAGS
    jmp  .apply
.flying:
    RD_FLAGS

.apply:
    cmp  dword [rdi+PKTR.err], 0
    jne  .done
    mov  eax, LOC(32)
    mov  [rbx+MCCONN.on_ground], eax
    cmp  dword LOC(64), 0
    je   .norot0
    cmp  dword [rbx+MCCONN.tp_id], 0
    jne  .norot0                    ; still flying to where we put them
    movsd xmm0, LOC(0)              ; drop nans and silly heights
    movsd xmm1, LOC(8)
    movsd xmm2, LOC(16)
    ucomisd xmm0, xmm0
    jp   .norot0
    ucomisd xmm1, xmm1
    jp   .norot0
    ucomisd xmm2, xmm2
    jp   .norot0
    movsd xmm3, [rel c_big]
    movapd xmm4, xmm0
    andpd xmm4, [rel c_absmask]
    comisd xmm4, xmm3
    ja   .norot0
    movapd xmm4, xmm2
    andpd xmm4, [rel c_absmask]
    comisd xmm4, xmm3
    ja   .norot0
    movsd [rbx+MCCONN.x], xmm0
    movsd [rbx+MCCONN.y], xmm1
    movsd [rbx+MCCONN.z], xmm2
.norot0:
    cmp  dword LOC(68), 0
    je   .moved
    movss xmm0, LOC(24)
    ucomiss xmm0, xmm0
    jp   .moved
    movss xmm1, LOC(28)
    ucomiss xmm1, xmm1
    jp   .moved
    movss [rbx+MCCONN.yaw], xmm0
    movss [rbx+MCCONN.pitch], xmm1
.moved:
    mov  eax, [rbx+MCCONN.index]
    lea  rcx, [rel pl_moved]
    mov  byte [rcx+rax], 1
    jmp  .done

.tpconfirm:
    mov  rcx, rdi
    call pr_varint
    cmp  dword [rdi+PKTR.err], 0
    jne  .done
    cmp  eax, [rbx+MCCONN.tp_id]
    jne  .done
    mov  dword [rbx+MCCONN.tp_id], 0
    jmp  .done

.ka:
    mov  rcx, rdi
    call pr_i64
    cmp  dword [rdi+PKTR.err], 0
    jne  .done
    cmp  rax, [rbx+MCCONN.ka_id]
    jne  .done
    mov  qword [rbx+MCCONN.ka_time], 0
    jmp  .done

.chat:
    mov  rcx, rdi
    lea  rdx, LOC(0)
    mov  r8d, 257
    call pr_string                  ; the signature stuff after it doesn't matter offline
    lea  rcx, LOC(272)
    lea  rdx, LOC(0)
    call pl_clean
    cmp  byte LOC(272), 0
    je   .done
    lea  rcx, LOC(544)
    lea  rdx, [rel s_chatfmt]
    lea  r8, [rbx+MCCONN.name]
    lea  r9, LOC(272)
    call str_format
    lea  rcx, LOC(544)
    xor  edx, edx
    xor  r8d, r8d
    call pl_say
    lea  rcx, LOC(544)
    mov  edx, 0xFFFFFFFF
    call chat_add
    jmp  .done

.command:
    mov  rcx, rdi
    lea  rdx, LOC(0)
    mov  r8d, 257
    call pr_string
    lea  rcx, LOC(272)
    lea  rdx, LOC(0)
    call pl_clean
    lea  rcx, LOC(272)
    lea  rdx, [rel s_cmd_help]
    call str_eq_nocase
    test eax, eax
    jnz  .c_help
    lea  rcx, LOC(272)
    lea  rdx, [rel s_cmd_list]
    call str_eq_nocase
    test eax, eax
    jnz  .c_list
    lea  rcx, LOC(544)
    lea  rdx, [rel s_unknown]
    lea  r8, LOC(272)
    call str_format
    lea  rcx, LOC(544)
    lea  rdx, [rel s_gray]
    mov  r8, rbx
    call pl_say
    jmp  .done
.c_help:
    lea  rcx, [rel s_help]
    lea  rdx, [rel s_gray]
    mov  r8, rbx
    call pl_say
    jmp  .done
.c_list:                            ; 9 + 17 names of 16 + ", " fits in 344
    lea  rcx, LOC(544)
    lea  rdx, [rel s_list]
    call str_copy
    call pl_host_name
    mov  rdx, rax
    lea  rcx, LOC(544)
    call str_cat
    lea  r12, [rel g_net_conns]
    xor  r13d, r13d
.cl:
    mov  rcx, r12
    call pl_ready
    test eax, eax
    jz   .cn
    lea  rcx, LOC(544)
    lea  rdx, [rel s_comma]
    call str_cat
    lea  rcx, LOC(544)
    lea  rdx, [r12+MCCONN.name]
    call str_cat
.cn:
    add  r12, MCCONN_size
    inc  r13d
    cmp  r13d, MAX_NET_CONNS
    jb   .cl
    lea  rcx, LOC(544)
    lea  rdx, [rel s_gray]
    mov  r8, rbx
    call pl_say
    jmp  .done

.dig:
    mov  rcx, rdi
    call pr_varint
    mov  r12d, eax                  ; status
    mov  rcx, rdi
    lea  rdx, LOC(0)
    call pr_position
    mov  rcx, rdi
    call pr_u8                      ; face
    mov  rcx, rdi
    call pr_varint
    mov  r13d, eax                  ; sequence
    cmp  dword [rdi+PKTR.err], 0
    jne  .done
    cmp  r12d, 2
    ja   .done                      ; drop item, swap hands, release use: nothing for us
    cmp  r12d, 1
    je   .dig_ack                   ; cancelled
    ; creative: starting to dig is the whole break
    mov  ecx, LOC(0)
    mov  edx, LOC(4)
    mov  r8d, LOC(8)
    call pl_editable
    test eax, eax
    jz   .dig_fix
    mov  ecx, LOC(0)
    mov  edx, LOC(4)
    mov  r8d, LOC(8)
    call world_get_block
    movzx r14d, al
    test r14d, r14d
    jz   .dig_ack
    mov  ecx, LOC(0)
    mov  edx, LOC(4)
    mov  r8d, LOC(8)
    xor  r9d, r9d
    call world_set_block
    mov  ecx, LOC(0)
    mov  edx, LOC(4)
    mov  r8d, LOC(8)
    call world_get_block
    test eax, eax
    jnz  .dig_fix
    ; break effect for the other java players, ours get particles + sound here
    lea  rax, [rel pl_lut_state]
    mov  eax, [rax+r14*4]
    mov  LOC(16), eax
    mov  ecx, MCP_PLAY_S2C_WORLD_EVENT
    call pw_begin
    mov  ecx, 2001
    call pw_i32
    mov  ecx, LOC(0)
    mov  edx, LOC(4)
    mov  r8d, LOC(8)
    call pw_position
    mov  ecx, LOC(16)
    call pw_i32
    xor  ecx, ecx
    call pw_bool
    mov  rcx, rbx
    call pl_bcast
    mov  ecx, LOC(0)
    mov  edx, LOC(4)
    mov  r8d, LOC(8)
    mov  r9d, r14d
    call particles_spawn_block_break
    mov  ecx, r14d
    xor  edx, edx
    mov  r8d, LOC(0)
    mov  r9d, LOC(4)
    mov  eax, LOC(8)
    mov  [rsp+32], rax
    call sfx_play_block
    jmp  .dig_ack
.dig_fix:
    mov  rcx, rbx
    mov  edx, LOC(0)
    mov  r8d, LOC(4)
    mov  r9d, LOC(8)
    call pl_resync
.dig_ack:
    mov  rcx, rbx
    mov  edx, r13d
    call pl_ack
    jmp  .done

.place:
    mov  rcx, rdi
    call pr_varint
    mov  r12d, eax                  ; hand
    mov  rcx, rdi
    lea  rdx, LOC(0)
    call pr_position
    mov  rcx, rdi
    call pr_varint
    mov  r14d, eax                  ; face
    mov  rcx, rdi
    mov  edx, 14                    ; cursor xyz, inside, world border
    call pr_skip
    mov  rcx, rdi
    call pr_varint
    mov  r13d, eax                  ; sequence
    cmp  dword [rdi+PKTR.err], 0
    jne  .done
    test r12d, r12d
    jnz  .place_ack                 ; off hand, we only track the hotbar
    cmp  r14d, 5
    ja   .place_ack
    ; clicked something replaceable (tall grass, water)? it goes right there
    mov  eax, LOC(0)
    mov  LOC(16), eax
    mov  eax, LOC(4)
    mov  LOC(20), eax
    mov  eax, LOC(8)
    mov  LOC(24), eax
    mov  ecx, LOC(0)
    mov  edx, LOC(4)
    mov  r8d, LOC(8)
    call pl_editable
    test eax, eax
    jz   .adjacent
    mov  ecx, LOC(0)
    mov  edx, LOC(4)
    mov  r8d, LOC(8)
    call world_get_block
    movzx eax, al
    lea  rdx, [rel blk_flags]
    test word [rdx+rax*2], BF_REPLACEABLE
    jnz  .target
.adjacent:
    lea  rax, [rel face_dx]
    mov  ecx, [rax+r14*4]
    add  LOC(16), ecx
    lea  rax, [rel face_dy]
    mov  ecx, [rax+r14*4]
    add  LOC(20), ecx
    lea  rax, [rel face_dz]
    mov  ecx, [rax+r14*4]
    add  LOC(24), ecx
.target:
    mov  eax, [rbx+MCCONN.held_slot]
    cmp  eax, 8
    ja   .place_fix
    mov  ecx, [rbx+MCCONN.hotbar+rax*4]
    test ecx, ecx
    jz   .place_fix
    call mcmap_item_to_block
    test eax, eax
    jz   .place_fix
    mov  r12d, eax                  ; block to place
    mov  LOC(28), eax               ; its base, what world_get_block reads back
    ; furnaces & co face the placer like ours do. java yaw 0 looks +z, so
    ; looking s w n e = FACE_N E S W, the bed's pillow goes the other way
    lea  rdx, [rel pl_turn]
    movzx r8d, byte [rdx+rax]
    test r8d, r8d
    jz   .place_go
    movss xmm0, [rbx+MCCONN.yaw]
    addss xmm0, [rel c_45]
    mulss xmm0, [rel c_inv90]
    roundss xmm0, xmm0, 1
    cvttss2si edx, xmm0
    add  edx, 2
    cmp  eax, B_BED
    jne  .place_face
    add  edx, 2
.place_face:
    and  edx, 3
    jz   .place_go
    lea  r12d, [r8+rdx-1]
.place_go:
    mov  ecx, LOC(16)
    mov  edx, LOC(20)
    mov  r8d, LOC(24)
    call pl_editable
    test eax, eax
    jz   .place_fix
    mov  ecx, LOC(16)
    mov  edx, LOC(20)
    mov  r8d, LOC(24)
    call world_get_block
    movzx eax, al
    lea  rdx, [rel blk_flags]
    test word [rdx+rax*2], BF_REPLACEABLE
    jz   .place_fix
    mov  ecx, LOC(16)
    mov  edx, LOC(20)
    mov  r8d, LOC(24)
    mov  r9d, r12d
    call world_set_block
    mov  ecx, LOC(16)
    mov  edx, LOC(20)
    mov  r8d, LOC(24)
    call world_get_block
    cmp  eax, LOC(28)
    jne  .place_fix
    mov  ecx, LOC(28)
    mov  edx, 1
    mov  r8d, LOC(16)
    mov  r9d, LOC(20)
    mov  eax, LOC(24)
    mov  [rsp+32], rax
    call sfx_play_block
    jmp  .place_ack
.place_fix:                         ; the client guessed, tell it what's really there
    mov  rcx, rbx
    mov  edx, LOC(0)
    mov  r8d, LOC(4)
    mov  r9d, LOC(8)
    call pl_resync
    mov  rcx, rbx
    mov  edx, LOC(16)
    mov  r8d, LOC(20)
    mov  r9d, LOC(24)
    call pl_resync
.place_ack:
    mov  rcx, rbx
    mov  edx, r13d
    call pl_ack
    jmp  .done

.creative:
    mov  rcx, rdi
    call pr_u16
    movsx r12d, ax                  ; slot
    mov  rcx, rdi
    call pr_varint
    mov  r13d, eax                  ; count
    xor  r14d, r14d
    test eax, eax
    jle  .cr_set
    mov  rcx, rdi
    call pr_varint
    mov  r14d, eax                  ; item, components after it don't matter
.cr_set:
    cmp  dword [rdi+PKTR.err], 0
    jne  .done
    sub  r12d, 36                   ; 36..44 is the hotbar
    cmp  r12d, 8
    ja   .done
    mov  [rbx+MCCONN.hotbar+r12*4], r14d
    jmp  .done

.held:
    mov  rcx, rdi
    call pr_u16
    movsx eax, ax
    cmp  dword [rdi+PKTR.err], 0
    jne  .done
    cmp  eax, 8
    ja   .done
    mov  [rbx+MCCONN.held_slot], eax
    jmp  .done

.swing:
    mov  rcx, rdi
    call pr_varint
    mov  r12d, eax
    cmp  dword [rdi+PKTR.err], 0
    jne  .done
    mov  ecx, MCP_PLAY_S2C_ANIMATION
    call pw_begin
    mov  ecx, [rbx+MCCONN.eid]
    call pw_varint
    xor  ecx, ecx                   ; main arm
    test r12d, r12d
    jz   .sw
    mov  ecx, 3                     ; off hand
.sw:
    call pw_u8
    mov  rcx, rbx
    call pl_bcast
.done:
ENDP

LPROC pl_editable
    xor  eax, eax
    cmp  edx, 0
    jl   .done
    cmp  edx, CHUNK_H
    jge  .done
    mov  edx, r8d
    call world_is_loaded
.done:
ENDP

; weather

; (ecx reason, xmm1 value, rdx conn or 0 = everyone) game_event
LPROC pl_game_event, 16
    mov  rbx, rdx
    mov  esi, ecx
    movss LOC(0), xmm1
    mov  ecx, MCP_PLAY_S2C_GAME_STATE_CHANGE
    call pw_begin
    mov  ecx, esi
    call pw_u8
    movss xmm0, LOC(0)
    call pw_f32
    test rbx, rbx
    jz   .all
    mov  rcx, rbx
    call pw_send
    jmp  .done
.all:
    xor  ecx, ecx
    call pl_bcast
.done:
ENDP

; (xmm0 now, xmm1 last sent) -> eax 1 when it's worth a packet. the end
; values 0 and 1 always go out so clients don't get stuck at 0.99
align 16
pl_lvl_moved:
    xor  eax, eax
    ucomiss xmm0, xmm1
    je   .r
    xorps xmm2, xmm2
    ucomiss xmm0, xmm2
    je   .yes
    ucomiss xmm0, [rel c_one]
    je   .yes
    subss xmm0, xmm1
    andps xmm0, [rel c_fabs]
    comiss xmm0, [rel c_lvl_eps]
    jb   .r
.yes:
    mov  eax, 1
.r: ret

LPROC pl_weather_tick
    xor  esi, esi                   ; 1 = levels go out regardless
    xor  eax, eax
    cmp  dword [rel g_weather], 1
    setae al
    cmp  eax, [rel pl_w_state]
    je   .rain
    mov  [rel pl_w_state], eax
    mov  esi, 1
    mov  ecx, 2                     ; stop_raining, 1 = start_raining
    sub  ecx, eax
    xorps xmm1, xmm1
    xor  edx, edx
    call pl_game_event
.rain:
    movss xmm0, [rel g_rain]
    movss xmm1, [rel pl_w_rain]
    call pl_lvl_moved
    or   eax, esi
    jz   .thunder
    movss xmm1, [rel g_rain]
    movss [rel pl_w_rain], xmm1
    mov  ecx, 7
    xor  edx, edx
    call pl_game_event
.thunder:
    movss xmm0, [rel g_thunder]
    movss xmm1, [rel pl_w_thunder]
    call pl_lvl_moved
    or   eax, esi
    jz   .done
    movss xmm1, [rel g_thunder]
    movss [rel pl_w_thunder], xmm1
    mov  ecx, 8
    xor  edx, edx
    call pl_game_event
.done:
ENDP

; entities
; polled, not hooked: every tick g_entities gets diffed against pl_es_*.
; a slot whose type changed or whose age went backwards is a new entity

; ecx conn index: that client has none of our entities (yet)
align 16
pl_es_unsee:
    mov  eax, 1
    shl  eax, cl
    not  eax
    lea  rdx, [rel pl_es_seen]
    mov  ecx, MAX_ENTITIES
.l: and  [rdx], eax
    add  rdx, 4
    dec  ecx
    jnz  .l
    ret

; rcx ENTITY* -> eax metadata fingerprint: item id|count<<8 or wool, 0x10000 burning
align 16
pl_ent_fp:
    movzx edx, byte [rcx+ENTITY.type]
    xor  eax, eax
    cmp  edx, ENT_ITEM
    jne  .mob
    movzx eax, word [rcx+ENTITY.item]
    ret
.mob:
    cmp  edx, ENT_BOAR
    jb   .r
    cmp  edx, ENT_WOOLLY
    jne  .fire
    movzx eax, byte [rcx+ENTITY.variant]
.fire:
    cmp  dword [rcx+ENTITY.fire], 0
    jle  .r
    or   eax, 0x10000
.r: ret

; rcx ENTITY* -> eax java angle bytes yaw | pitch<<8 | head<<16, 0 for non mobs.
; mobs use the remote player convention: java yaw = ours + 180, pitch flipped
align 16
pl_ent_rot:
    xor  eax, eax
    cmp  byte [rcx+ENTITY.type], ENT_BOAR
    jb   .r
    movss xmm0, [rcx+ENTITY.head_yaw]
    addss xmm0, [rel c_180]
    call pl_angle
    mov  edx, eax
    shl  edx, 16
    xorps xmm0, xmm0
    subss xmm0, [rcx+ENTITY.pitch]
    call pl_angle
    shl  eax, 8
    or   edx, eax
    movss xmm0, [rcx+ENTITY.yaw]
    addss xmm0, [rel c_180]
    call pl_angle
    or   eax, edx
.r: ret

; rcx ENTITY* -> eax EV_* | hurt_time<<8, the one-shot things clients get told about
align 16
pl_ent_ev:
    xor  eax, eax
    test byte [rcx+ENTITY.flags], EF_DEAD
    jz   .nd
    or   eax, EV_DEAD
.nd:
    cmp  byte [rcx+ENTITY.type], ENT_ITEM
    jne  .nc
    cmp  byte [rcx+ENTITY.ai_state], ITEM_COLLECT
    jne  .nc
    or   eax, EV_COLLECT
.nc:
    mov  edx, [rcx+ENTITY.hurt_time]
    test edx, edx
    jle  .r
    cmp  edx, 255
    jbe  .h
    mov  edx, 255
.h: shl  edx, 8
    or   eax, edx
.r: ret

; (rcx ENTITY*, rdx out qword[3]) feet in 1/4096 blocks
align 16
pl_ent_fix:
    cvtss2sd xmm0, [rcx+ENTITY.x]
    mulsd xmm0, [rel c_fix]
    cvtsd2si rax, xmm0
    mov  [rdx], rax
    cvtss2sd xmm0, [rcx+ENTITY.y]
    mulsd xmm0, [rel c_fix]
    cvtsd2si rax, xmm0
    mov  [rdx+8], rax
    cvtss2sd xmm0, [rcx+ENTITY.z]
    mulsd xmm0, [rel c_fix]
    cvtsd2si rax, xmm0
    mov  [rdx+16], rax
    ret

LPROC pl_send_mask
    mov  r12d, ecx
    lea  rbx, [rel g_net_conns]
.l:
    test r12d, r12d
    jz   .done
    bsf  eax, r12d
    btr  r12d, eax
    imul rcx, rax, MCCONN_size
    add  rcx, rbx
    call pw_send
    jmp  .l
.done:
ENDP

; ecx eid -> remove_entities for just that one in g_pw
LPROC pl_pw_destroy
    mov  ebx, ecx
    mov  ecx, MCP_PLAY_S2C_ENTITY_DESTROY
    call pw_begin
    mov  ecx, 1
    call pw_varint
    mov  ecx, ebx
    call pw_varint
ENDP

; rcx float[3] blocks per tick -> lpvec3 into g_pw. clamped to +-3 so the
; scale fits the marker bits
LPROC pl_pw_lpvec, 32
    mov  rbx, rcx
    lea  rdi, LOC(0)
    xorps xmm3, xmm3                ; max |v|
    xor  esi, esi
.c:
    movss xmm0, [rbx+rsi*4]
    ucomiss xmm0, xmm0
    jnp  .num
    xorps xmm0, xmm0
.num:
    minss xmm0, [rel c_vel_max]
    xorps xmm1, xmm1
    subss xmm1, [rel c_vel_max]
    maxss xmm0, xmm1
    movss [rdi+rsi*4], xmm0
    andps xmm0, [rel c_fabs]
    maxss xmm3, xmm0
    inc  esi
    cmp  esi, 3
    jb   .c
    comiss xmm3, [rel c_vel_min]
    jae  .some
    xor  ecx, ecx
    call pw_u8
    jmp  .done
.some:
    roundss xmm3, xmm3, 2           ; ceil
    cvttss2si r12d, xmm3            ; scale 1..3, doubles as the marker bits
    mov  r13d, r12d
    xor  esi, esi
.q:                                 ; round((v/scale + 1) * 16383), 15 bits at 3 + 15*i
    movss xmm0, [rdi+rsi*4]
    divss xmm0, xmm3
    addss xmm0, [rel c_one]
    mulss xmm0, [rel c_quant]
    cvtss2si eax, xmm0
    xor  edx, edx
    test eax, eax
    cmovs eax, edx
    mov  edx, 32766
    cmp  eax, edx
    cmova eax, edx
    imul ecx, esi, 15
    add  ecx, 3
    shl  rax, cl
    or   r13, rax
    inc  esi
    cmp  esi, 3
    jb   .q
    movzx ecx, r13b
    call pw_u8
    mov  rcx, r13
    shr  rcx, 8
    movzx ecx, cl
    call pw_u8
    mov  rcx, r13
    shr  rcx, 16
    call pw_i32
.done:
ENDP

; (ecx slot, rdx ENTITY*, r8d java type + 1) spawn_entity into g_pw
LPROC pl_pw_ent_spawn
    mov  r12d, ecx
    mov  rbx, rdx
    lea  r13d, [r8-1]
    lea  rax, [rel pl_es_eid]
    mov  esi, [rax+r12*4]
    lea  rdi, [rel pl_uuid]         ; made up, v4 shaped, eid in the low bytes
    mov  rax, 0x004000004D53414D
    mov  [rdi], rax
    mov  dword [rdi+8], 0x80
    mov  eax, esi
    bswap eax
    mov  [rdi+12], eax
    mov  ecx, MCP_PLAY_S2C_SPAWN_ENTITY
    call pw_begin
    mov  ecx, esi
    call pw_varint
    mov  rcx, rdi
    call pw_uuid
    mov  ecx, r13d
    call pw_varint
    cvtss2sd xmm0, [rbx+ENTITY.x]
    call pw_f64
    cvtss2sd xmm0, [rbx+ENTITY.y]
    call pw_f64
    cvtss2sd xmm0, [rbx+ENTITY.z]
    call pw_f64
    ; items, tnt and sand fly client side too, they want their velocity
    cmp  byte [rbx+ENTITY.type], ENT_BOAR
    jae  .still
    lea  rcx, [rbx+ENTITY.vx]
    call pl_pw_lpvec
    jmp  .rot
.still:
    xor  ecx, ecx
    call pw_u8
.rot:
    mov  rcx, rbx
    call pl_ent_rot
    mov  r14d, eax
    movzx ecx, ah
    call pw_u8                      ; pitch
    movzx ecx, r14b
    call pw_u8                      ; yaw
    mov  ecx, r14d
    shr  ecx, 16
    call pw_u8                      ; head
    xor  ecx, ecx                   ; object data, sand says which block
    cmp  byte [rbx+ENTITY.type], ENT_FALLING
    jne  .od
    movzx eax, byte [rbx+ENTITY.variant]
    mov  ecx, B_SAND
    test eax, eax
    cmovz eax, ecx
    lea  rcx, [rel pl_lut_state]
    mov  ecx, [rcx+rax*4]
.od:
    call pw_varint
ENDP

; (ecx slot, rdx ENTITY*) set_entity_data into g_pw -> eax 0 when there's nothing to say
LPROC pl_pw_ent_meta
    mov  r12d, ecx
    mov  rbx, rdx
    movzx r13d, byte [rbx+ENTITY.type]
    xor  eax, eax
    cmp  r13d, ENT_FALLING
    je   .done
    mov  ecx, MCP_PLAY_S2C_ENTITY_METADATA
    call pw_begin
    lea  rax, [rel pl_es_eid]
    mov  ecx, [rax+r12*4]
    call pw_varint
    cmp  r13d, ENT_ITEM
    je   .item
    cmp  r13d, ENT_TNT
    je   .tnt
    xor  ecx, ecx                   ; 0 shared flags (byte): 1 = on fire
    call pw_u8
    xor  ecx, ecx
    call pw_varint
    xor  ecx, ecx
    cmp  dword [rbx+ENTITY.fire], 0
    setg cl
    call pw_u8
    cmp  r13d, ENT_WOOLLY
    jne  .end
    mov  ecx, 18                    ; sheep wool (byte), our variant is already the dye id
    call pw_u8
    xor  ecx, ecx
    call pw_varint
    movzx ecx, byte [rbx+ENTITY.variant]
    and  ecx, 15
    call pw_u8
    jmp  .end
.item:
    mov  ecx, 8                     ; the stack (slot)
    call pw_u8
    mov  ecx, 7
    call pw_varint
    movzx ecx, byte [rbx+ENTITY.item+STACK.count]
    mov  eax, 1
    test ecx, ecx
    cmovz ecx, eax
    call pw_varint
    movzx ecx, byte [rbx+ENTITY.item+STACK.id]
    call mcmap_block_to_item
    mov  ecx, eax
    call pw_varint
    xor  ecx, ecx                   ; no components either way
    call pw_varint
    xor  ecx, ecx
    call pw_varint
    jmp  .end
.tnt:
    mov  ecx, 8                     ; fuse (varint int)
    call pw_u8
    mov  ecx, 1
    call pw_varint
    mov  ecx, [rbx+ENTITY.timer]
    xor  eax, eax
    test ecx, ecx
    cmovs ecx, eax
    call pw_varint
.end:
    mov  ecx, 0xFF
    call pw_u8
    mov  eax, 1
.done:
ENDP

; (ecx slot, rdx ENTITY*, r8d java type + 1) start tracking, nobody has it yet
LPROC pl_ent_track
    mov  r12d, ecx
    mov  rbx, rdx
    lea  rax, [rel pl_es_jt]
    mov  [rax+r12*4], r8d
    mov  eax, [rel pl_next_eid]
    cmp  eax, FIRST_ENT_EID
    jge  .e
    mov  eax, FIRST_ENT_EID ; trace probe #107 hook
.e: ; trace probe #107 hook
    lea  ecx, [rax+1] ; trace probe #107 hook
    mov  [rel pl_next_eid], ecx ; trace probe #107 hook
    lea  rcx, [rel pl_es_eid] ; trace probe #107 hook
    mov  [rcx+r12*4], eax ; trace probe #107 hook
    lea  rax, [rel pl_es_seen] ; trace probe #107 hook
    mov  dword [rax+r12*4], 0 ; trace probe #107 hook
    lea  rax, [r12+r12*2] ; trace probe #107 hook
    lea  rdx, [rel pl_es_pos]
    lea  rdx, [rdx+rax*8]
    mov  rcx, rbx
    call pl_ent_fix
    lea  rax, [r12+r12*2]
    lea  rdx, [rel pl_es_vel]
    lea  rdx, [rdx+rax*4]
    mov  eax, [rbx+ENTITY.vx]
    mov  [rdx], eax
    mov  eax, [rbx+ENTITY.vy]
    mov  [rdx+4], eax
    mov  eax, [rbx+ENTITY.vz]
    mov  [rdx+8], eax
    mov  rcx, rbx
    call pl_ent_rot
    lea  rcx, [rel pl_es_rot]
    mov  [rcx+r12*4], eax
    mov  rcx, rbx
    call pl_ent_fp
    lea  rcx, [rel pl_es_meta]
    mov  [rcx+r12*4], eax
    mov  rcx, rbx
    call pl_ent_ev
    lea  rcx, [rel pl_es_ev]
    mov  [rcx+r12*4], eax
ENDP
; --- temporary diagnostic probe #107 (mcplay) ---
; TODO: strip dbg_mcplay_probe_107 once frame/state invariants hold
dbg_mcplay_probe_107:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    mov     [rsp+32], rcx
    mov     [rsp+40], rdx
    mov     [rsp+48], r8
    mov     [rsp+56], r9
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    mov     r10, rax
    test    rcx, rcx
    jz      .dbg_null_107
    mov     eax, dword [rcx+0] ; sample mcplay state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_107_0
.dbg_skip_107_0:
    mov     ecx, dword [rcx+4] ; sample mcplay state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_107_1
.dbg_skip_107_1:
    mov     edx, dword [rcx+8] ; sample mcplay state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_107_2
.dbg_skip_107_2:
    mov     r8d, dword [rcx+12] ; sample mcplay state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_107_3
.dbg_skip_107_3:
    mov     r9d, dword [rcx+16] ; sample mcplay state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_107_4
.dbg_skip_107_4:
    mov     r11d, dword [rcx+20] ; sample mcplay state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_107_5
.dbg_skip_107_5:
    mov     eax, dword [rcx+24] ; sample mcplay state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_107_6
.dbg_skip_107_6:
    mov     ecx, dword [rcx+28] ; sample mcplay state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_107_7
.dbg_skip_107_7:
    mov     edx, dword [rcx+32] ; sample mcplay state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_107_8
.dbg_skip_107_8:
    mov     r8d, dword [rcx+36] ; sample mcplay state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_107_9
.dbg_skip_107_9:
    mov     r9d, dword [rcx+40] ; sample mcplay state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_107_10
.dbg_skip_107_10:
    mov     r11d, dword [rcx+44] ; sample mcplay state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_107_11
.dbg_skip_107_11:
    mov     eax, dword [rcx+48] ; sample mcplay state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_107_12
.dbg_skip_107_12:
    mov     ecx, dword [rcx+52] ; sample mcplay state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_107_13
.dbg_skip_107_13:
    mov     edx, dword [rcx+56] ; sample mcplay state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_107_14
.dbg_skip_107_14:
    mov     r8d, dword [rcx+60] ; sample mcplay state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_107_15
.dbg_skip_107_15:
    mov     r9d, dword [rcx+64] ; sample mcplay state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_107_16
.dbg_skip_107_16:
    mov     r11d, dword [rcx+68] ; sample mcplay state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_107_17
.dbg_skip_107_17:
    mov     eax, dword [rcx+72] ; sample mcplay state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_107_18
.dbg_skip_107_18:
    mov     ecx, dword [rcx+76] ; sample mcplay state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_107_19
.dbg_skip_107_19:
    mov     edx, dword [rcx+80] ; sample mcplay state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_107_20
.dbg_skip_107_20:
    mov     r8d, dword [rcx+84] ; sample mcplay state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_107_21
.dbg_skip_107_21:
.dbg_null_107:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
