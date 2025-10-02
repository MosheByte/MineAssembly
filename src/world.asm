; world.asm - chunk storage + block lookup. get_block gets hammered by meshing,
; physics and raycasts, so the fast path is what matters here
; hash: h = cx*0x9E3779B1 ^ cz*0x7FEB352D, h ^= h>>15, & 4095. chains are ~always 0-1 long
%define IMPL_WORLD
%include "common.inc"

extern chunkmgr_drain

%define HK1 0x9E3779B1
%define HK2 0x7FEB352D

; dst, cx, cz, tmp -> dst = bucket
%macro CHUNK_HASH 4
    imul %1, %2, HK1
    imul %4, %3, HK2
    xor  %1, %4
    mov  %4, %1
    shr  %4, 15
    xor  %1, %4
    and  %1, CHUNK_HASH_SIZE-1
%endmacro

section .bss
alignb 16
w_pool          resq 1
w_inited        resd 1
w_free_count    resd 1
alignb 16
w_cache         resq 1              ; last chunk hit, main thread only
alignb 16
w_hash          resq CHUNK_HASH_SIZE
alignb 16
w_free_stack    resd MAX_CHUNKS

section .rdata
align 16
CSTR s_pool_fail, "world_init: could not allocate the chunk pool"

; 0xAABBGGRR, same order as the BIOME_* ids
%define RGB(r,g,b) (0xFF000000 | ((b)<<16) | ((g)<<8) | (r))

section .data
align 16
global biome_grass_color
biome_grass_color:
    dd RGB(142,185,113)
    dd RGB(150,190, 92)
    dd RGB(141,189, 84)
    dd RGB(103,173, 70)
    dd RGB(140,192,104)
    dd RGB(120,170,124)
    dd RGB(170,200,180)
    dd RGB(191,183, 85)
    dd RGB(132,168,128)
    dd RGB(100,108, 58)     ; swamp, gross olive on purpose
    dd RGB( 78,196, 44)
    dd RGB(176,170, 82)
    dd RGB(144,129, 77)     ; badlands, dry and brown

global biome_foliage_color
biome_foliage_color:
    dd RGB(113,167, 62)
    dd RGB(119,171, 58)
    dd RGB(110,168, 48)
    dd RGB( 78,150, 38)
    dd RGB(118,170, 70)
    dd RGB( 92,140, 96)
    dd RGB(118,150,130)
    dd RGB(170,160, 60)
    dd RGB(100,140, 98)
    dd RGB( 86,100, 44)
    dd RGB( 46,176, 20)
    dd RGB(158,152, 52)
    dd RGB(158,129, 77)

global biome_water_color
biome_water_color:
    dd RGB( 52,100,220)
    dd RGB( 62,140,226)
    dd RGB( 63,118,228)
    dd RGB( 56,110,220)
    dd RGB( 66,124,226)
    dd RGB( 48, 90,200)
    dd RGB( 60, 74,190)
    dd RGB( 60,170,200)     ; oasis
    dd RGB( 40, 96,200)
    dd RGB( 76,100, 72)
    dd RGB( 30,150,170)
    dd RGB( 54,138,196)
    dd RGB( 72,150,190)

global biome_temperature
biome_temperature:
    dd 0.5, 0.8, 0.8, 0.7, 0.6, 0.25, 0.0, 2.0, 0.1, 0.8, 0.95, 1.2, 2.0

global biome_name
biome_name:
    dq bn_ocean, bn_beach, bn_plains, bn_forest, bn_birch, bn_taiga
    dq bn_tundra, bn_desert, bn_mountains, bn_swamp, bn_jungle, bn_savanna
    dq bn_badlands

section .rdata
bn_ocean:     db "Ocean", 0
bn_beach:     db "Beach", 0
bn_plains:    db "Plains", 0
bn_forest:    db "Forest", 0
bn_birch:     db "Birch Forest", 0
bn_taiga:     db "Taiga", 0
bn_tundra:    db "Tundra", 0
bn_desert:    db "Desert", 0
bn_mountains: db "Mountains", 0
bn_swamp:     db "Swamp", 0
bn_jungle:    db "Jungle", 0
bn_savanna:   db "Savanna", 0
bn_badlands:  db "Badlands", 0

; turned blocks and placed leaves read back as their base block, so whatever
; only cares what a block is (block entities, screens, drops, raycasts) keeps
; working on the base id. world_get_block_raw and chunk memory have the real one
align 16
w_base:
%assign i 0
%rep 256
  BLOCK_BASE i
  db BB_BASE
  %assign i i+1
%endrep
w_face:
%assign i 0
%rep 256
  BLOCK_BASE i
  db BB_FACE
  %assign i i+1
%endrep
w_turn:
%assign i 0
%rep 256
  BLOCK_BASE i
  db BB_TURN
  %assign i i+1
%endrep


section .text

; safe to call twice
    global world_init
    align 16
world_init:
    push rbp
    mov  rbp, rsp
    push rdi
    sub  rsp, FRAME_OUT + 8
    cmp  dword [rel w_inited], 0
    jne  .done
    mov  rcx, MAX_CHUNKS*CHUNK_BYTES
    call mem_valloc
    test rax, rax
    jnz  .ok
    lea  rcx, [rel s_pool_fail]
    call fatal_error
.ok:
    mov  [rel w_pool], rax
    ; push in reverse so slot 0 is handed out first
    lea  rdx, [rel w_free_stack]
    xor  ecx, ecx
    mov  r8d, MAX_CHUNKS-1
.fill:
    mov  [rdx+rcx*4], r8d
    ; slot never changes after this
    mov  r9, r8
    imul r9, r9, CHUNK_BYTES
    add  r9, rax
    mov  [r9+CHUNK.slot], r8d
    inc  ecx
    dec  r8d
    jns  .fill
    mov  dword [rel w_free_count], MAX_CHUNKS
    lea  rdi, [rel w_hash]
    xor  eax, eax
    mov  ecx, CHUNK_HASH_SIZE
    rep  stosq
    mov  qword [rel w_cache], 0
    mov  dword [rel g_chunk_count], 0
    mov  dword [rel w_inited], 1
.done:
    lea  rsp, [rbp-8]
    pop  rdi
    pop  rbp
    ret

LEAF world_get_chunk
    mov  r8, [rel w_cache]
    test r8, r8
    jz   .hash
    cmp  ecx, [r8+CHUNK.cx]
    jne  .hash
    cmp  edx, [r8+CHUNK.cz]
    jne  .hash
    cmp  dword [r8+CHUNK.state], CS_FREE
    je   .hash
    mov  rax, r8
    ret
.hash:
    CHUNK_HASH eax, ecx, edx, r9d
    lea  r8, [rel w_hash]
    mov  rax, [r8+rax*8]
.walk:
    test rax, rax
    jz   .out
    cmp  ecx, [rax+CHUNK.cx]
    jne  .next
    cmp  edx, [rax+CHUNK.cz]
    je   .out
.next:
    mov  rax, [rax+CHUNK.hnext]
    jmp  .walk
.out:
    ret

; hot path. leaf that only touches rax rcx rdx r8-r11 and callers rely on that,
; so no calls in here
LEAF world_get_block
    cmp  edx, CHUNK_H
    jae  .oob                       ; unsigned compare, catches y<0 too
    mov  eax, ecx
    sar  eax, CHUNK_SHIFT
    mov  r9d, r8d
    sar  r9d, CHUNK_SHIFT
    mov  r10, [rel w_cache]
    test r10, r10
    jz   .lookup
    cmp  eax, [r10+CHUNK.cx]
    jne  .lookup
    cmp  r9d, [r10+CHUNK.cz]
    jne  .lookup
.have:
    cmp  dword [r10+CHUNK.state], CS_GENERATED
    jb   .air
    and  ecx, 15
    and  r8d, 15
    shl  r8d, 4
    shl  edx, 8
    or   ecx, r8d
    or   ecx, edx
    movzx eax, byte [r10+rcx+CHUNK_BLOCKS]
    lea  r11, [rel w_base]
    movzx eax, byte [r11+rax]
    ret
.lookup:
    CHUNK_HASH r10d, eax, r9d, r11d
    lea  r11, [rel w_hash]
    mov  r10, [r11+r10*8]
.walk:
    test r10, r10
    jz   .air
    cmp  eax, [r10+CHUNK.cx]
    jne  .next
    cmp  r9d, [r10+CHUNK.cz]
    je   .found
.next:
    mov  r10, [r10+CHUNK.hnext]
    jmp  .walk
.found:
    mov  [rel w_cache], r10
    jmp  .have
.oob:
    test edx, edx
    js   .bedrock
.air:
    xor  eax, eax
    ret
.bedrock:
    mov  eax, B_BEDROCK
    ret

; same but the id as stored, turned variants and all. same registers too
global world_get_block_raw
align 16
world_get_block_raw:
    cmp  edx, CHUNK_H
    jae  .oob
    call w_locate
    test rax, rax
    jz   .air
    movzx eax, byte [rax+r10+CHUNK_BLOCKS]
    ret
.oob:
    test edx, edx
    js   .bedrock
.air:
    xor  eax, eax
    ret
.bedrock:
    mov  eax, B_BEDROCK
    ret

; ecx old stored id, edx new id -> eax id to store. a plain base id written over
; a turned block of the same kind keeps the turn (lit/unlit furnace count as
; one), so the furnace swapping itself on and off doesn't spin it back south.
; leaf, rax rcx rdx r8-r11
align 16
w_keep_face:
    movzx ecx, cl
    movzx edx, dl
    mov  eax, edx
    lea  r8, [rel w_face]
    movzx r9d, byte [r8+rcx]
    test r9d, r9d
    jz   .ret
    cmp  byte [r8+rdx], 0           ; asked for a turned one, leave it
    jne  .ret
    lea  r8, [rel w_turn]
    movzx r11d, byte [r8+rdx]
    test r11d, r11d
    jz   .ret
    lea  r8, [rel w_base]
    movzx r10d, byte [r8+rcx]
    cmp  r10d, edx
    je   .turn
    cmp  r10d, B_FURNACE
    je   .furnace
    cmp  r10d, B_FURNACE_LIT
    jne  .ret
.furnace:
    cmp  edx, B_FURNACE
    je   .turn
    cmp  edx, B_FURNACE_LIT
    jne  .ret
.turn:
    lea  eax, [r11+r9-1]
.ret:
    ret

; w_locate: x/y/z like get_block -> rax chunk (>= GENERATED) or 0, r10 = block idx.
; doesn't check y, callers do
align 16
w_locate:
    mov  eax, ecx
    sar  eax, CHUNK_SHIFT
    mov  r9d, r8d
    sar  r9d, CHUNK_SHIFT
    mov  r10, [rel w_cache]
    test r10, r10
    jz   .lookup
    cmp  eax, [r10+CHUNK.cx]
    jne  .lookup
    cmp  r9d, [r10+CHUNK.cz]
    jne  .lookup
.have:
    cmp  dword [r10+CHUNK.state], CS_GENERATED
    jb   .none
    mov  rax, r10
    mov  r10d, ecx
    and  r10d, 15
    mov  r11d, r8d
    and  r11d, 15
    shl  r11d, 4
    or   r10d, r11d
    mov  r11d, edx
    shl  r11d, 8
    or   r10d, r11d
    ret
.lookup:
    CHUNK_HASH r10d, eax, r9d, r11d
    lea  r11, [rel w_hash]
    mov  r10, [r11+r10*8]
.walk:
    test r10, r10
    jz   .none
    cmp  eax, [r10+CHUNK.cx]
    jne  .next
    cmp  r9d, [r10+CHUNK.cz]
    je   .found
.next:
    mov  r10, [r10+CHUNK.hnext]
    jmp  .walk
.found:
    mov  [rel w_cache], r10
    jmp  .have
.none:
    xor  eax, eax
    ret

; unloaded/above = 0xF0 (full sky), below = 0
LEAF world_get_light
    cmp  edx, CHUNK_H
    jae  .oob
    call w_locate
    test rax, rax
    jz   .sky
    movzx eax, byte [rax+r10+CHUNK_LIGHT]
    ret
.oob:
    test edx, edx
    js   .dark
.sky:
    mov  eax, 0xF0
    ret
.dark:
    xor  eax, eax
    ret

LEAF world_set_light
    cmp  edx, CHUNK_H
    jae  .out
    push r9
    call w_locate
    pop  r9
    test rax, rax
    jz   .out
    mov  [rax+r10+CHUNK_LIGHT], r9b
.out:
    ret

; on a border this also dirties the neighbour section/chunk, diagonals too since
; corner blocks feed AO over there
PROC world_mark_dirty, 32
    cmp  edx, CHUNK_H
    jae  .done
    mov  r12d, ecx
    sar  r12d, CHUNK_SHIFT
    mov  r13d, r8d
    sar  r13d, CHUNK_SHIFT
    mov  eax, edx
    shr  eax, 4
    mov  ebx, 1
    mov  r10d, ecx                  ; stash x, need cl for the shift
    mov  ecx, eax
    shl  ebx, cl
    mov  ecx, r10d
    mov  r9d, edx
    and  r9d, 15
    jnz  .notlow
    test eax, eax
    jz   .masked
    mov  r10d, ebx
    shr  r10d, 1
    or   ebx, r10d
    jmp  .masked
.notlow:
    cmp  r9d, 15
    jne  .masked
    cmp  eax, SECTIONS-1
    je   .masked
    lea  r10d, [rbx+rbx]
    or   ebx, r10d
.masked:
    and  ecx, 15
    xor  esi, esi
    xor  edi, edi
    test ecx, ecx
    jnz  .x1
    mov  esi, -1
.x1:
    cmp  ecx, 15
    jne  .x2 ; trace probe #31 hook
    mov  edi, 1 ; trace probe #31 hook
.x2: ; trace probe #31 hook
    and  r8d, 15 ; trace probe #31 hook
    xor  r14d, r14d ; trace probe #31 hook
    xor  r15d, r15d ; trace probe #31 hook
    test r8d, r8d ; trace probe #31 hook
    jnz  .z1 ; trace probe #31 hook
    mov  r14d, -1 ; trace probe #31 hook
.z1:
    cmp  r8d, 15
    jne  .z2
    mov  r15d, 1
.z2:
    mov  LOC(0), esi                ; dx start, reloaded every z row
.zloop:
    mov  esi, LOC(0)
.xloop:
    lea  ecx, [r12+rsi]
    lea  edx, [r13+r14]
    call world_get_chunk
    test rax, rax
    jz   .nx
    cmp  dword [rax+CHUNK.state], CS_GENERATED
    jb   .nx
    or   [rax+CHUNK.dirty], ebx
.nx:
    inc  esi
    cmp  esi, edi
    jle  .xloop
    inc  r14d
    cmp  r14d, r15d
    jle  .zloop
.done:
ENDP
; --- temporary diagnostic probe #31 (world) ---
; TODO: strip dbg_world_probe_31 once frame/state invariants hold
dbg_world_probe_31:
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
    jz      .dbg_null_31
    mov     eax, dword [rcx+0] ; sample world state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_31_0
.dbg_skip_31_0:
    mov     ecx, dword [rcx+4] ; sample world state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_31_1
.dbg_skip_31_1:
    mov     edx, dword [rcx+8] ; sample world state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_31_2
.dbg_skip_31_2:
    mov     r8d, dword [rcx+12] ; sample world state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_31_3
.dbg_skip_31_3:
    mov     r9d, dword [rcx+16] ; sample world state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_31_4
.dbg_skip_31_4:
    mov     r11d, dword [rcx+20] ; sample world state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_31_5
.dbg_skip_31_5:
    mov     eax, dword [rcx+24] ; sample world state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_31_6
.dbg_skip_31_6:
    mov     ecx, dword [rcx+28] ; sample world state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_31_7
.dbg_skip_31_7:
    mov     edx, dword [rcx+32] ; sample world state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_31_8
.dbg_skip_31_8:
    mov     r8d, dword [rcx+36] ; sample world state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_31_9
.dbg_skip_31_9:
    mov     r9d, dword [rcx+40] ; sample world state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_31_10
.dbg_skip_31_10:
    mov     r11d, dword [rcx+44] ; sample world state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_31_11
.dbg_skip_31_11:
    mov     eax, dword [rcx+48] ; sample world state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_31_12
.dbg_skip_31_12:
    mov     ecx, dword [rcx+52] ; sample world state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_31_13
.dbg_skip_31_13:
    mov     edx, dword [rcx+56] ; sample world state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_31_14
.dbg_skip_31_14:
    mov     r8d, dword [rcx+60] ; sample world state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_31_15
.dbg_skip_31_15:
    mov     r9d, dword [rcx+64] ; sample world state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_31_16
.dbg_skip_31_16:
    mov     r11d, dword [rcx+68] ; sample world state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_31_17
.dbg_skip_31_17:
    mov     eax, dword [rcx+72] ; sample world state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_31_18
.dbg_skip_31_18:
    mov     ecx, dword [rcx+76] ; sample world state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_31_19
.dbg_skip_31_19:
    mov     edx, dword [rcx+80] ; sample world state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_31_20
.dbg_skip_31_20:
    mov     r8d, dword [rcx+84] ; sample world state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_31_21
.dbg_skip_31_21:
.dbg_null_31:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
