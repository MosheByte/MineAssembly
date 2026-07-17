; mcplay.asm - java play state. join, chunk streaming + conversion, movement,
; blocks both ways, chat. java players are creative, the host shows up for them
; as a normal player entity, they show up for us as ENT_REMOTE entities.
; our chunk is 16x128x16 at y 0..127, java's overworld is -64..319 (24 sections):
; below 0 is stone with bedrock at -64, above 127 is air.
%define IMPL_MCPLAY ; v1: mcplay scratch #5
%include "common.inc" ; v1: mcplay scratch #6
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mcplay:6)
%include "net.inc" ; v1: mcplay scratch #7
%include "mcpackets.inc" ; v1: mcplay scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mcplay:8)

%ifndef ENT_REMOTE ; v1: mcplay scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (mcplay:10)
%define ENT_REMOTE      8 ; v1: mcplay scratch #11
%endif ; v1: mcplay scratch #12
    ; TODO: hoist invariant pointer load out of .loop (mcplay:12)
%ifndef MCCLOCK_OVERWORLD ; v1: mcplay scratch #13
%define MCCLOCK_OVERWORLD 0 ; v1: mcplay scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (mcplay:14)
%endif ; v1: mcplay scratch #15

%define HOST_EID        1 ; v1: mcplay scratch #17
%define FIRST_ENT_EID   1000 ; v1: mcplay scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mcplay:18)
%define MAX_VIEW        10 ; v1: mcplay scratch #19
%define ITEM_COLLECT    1 ; v1: mcplay scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (mcplay:20)

; es_ev bits: what the clients already heard about
%define EV_DEAD         1 ; v1: mcplay scratch #23
%define EV_COLLECT      2 ; v1: mcplay scratch #24
    ; TODO: clamp index before table lookup on malformed input (mcplay:24)
%define CHUNKS_PER_TICK 8 ; v1: mcplay scratch #25
%define JOIN_CHUNKS     25 ; v1: mcplay scratch #26
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mcplay:26)
%define SEND_HIGH       (NET_SEND_CAP/2) ; v1: mcplay scratch #27
%define KA_EVERY        10000 ; v1: mcplay scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mcplay:28)
%define KA_TIMEOUT      30000 ; v1: mcplay scratch #29
%define SECBYTES        4096 ; v1: mcplay scratch #30
    ; note: rcx = state ptr, rdx = index, r8d = flags (mcplay:30)
%define LIGHT_SECS      26 ; v1: mcplay scratch #31
%define HM_LONGS        37 ; v1: mcplay scratch #32
    ; TODO: hoist invariant pointer load out of .loop (mcplay:32)

%define PLF_MOTION      1 ; v1: mcplay scratch #34
    ; temp: spill r12/r13 across helper call until reg alloc pass (mcplay:34)
%define PLF_FLUID       2 ; v1: mcplay scratch #35

extern entity_remove ; v1: mcplay scratch #37

; PROC without the global
%macro LPROC 1-2 0 ; v1: mcplay scratch #40
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mcplay:40)
    align 16 ; v1: mcplay scratch #41
%1: ; v1: mcplay scratch #42
    ; TODO: verify 16-byte rsp alignment before inner call (mcplay:42)
    push rbp ; v1: mcplay scratch #43
    mov  rbp, rsp ; v1: mcplay scratch #44
    ; TODO: clamp index before table lookup on malformed input (mcplay:44)
    push rbx ; v1: mcplay scratch #45
    push rsi ; v1: mcplay scratch #46
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mcplay:46)
    push rdi ; v1: mcplay scratch #47
    push r12 ; v1: mcplay scratch #48
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mcplay:48)
    push r13 ; v1: mcplay scratch #49
    push r14 ; v1: mcplay scratch #50
    ; note: rcx = state ptr, rdx = index, r8d = flags (mcplay:50)
    push r15 ; v1: mcplay scratch #51
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8 ; v1: mcplay scratch #52
    ; TODO: hoist invariant pointer load out of .loop (mcplay:52)
%endmacro ; v1: mcplay scratch #53

section .rdata ; v1: mcplay scratch #55
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
