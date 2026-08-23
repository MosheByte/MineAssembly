; max render distance must never run the chunk pool dry. load disc (R=18) is
; 1085 chunks, unload disc d2 <= (R+2)^2+(R+2) caps residents at 1313 < 1600
; no matter where you walk. (a square unload rule would allow 41x41 = 1681.)
; @link src/world.asm src/worldgen.asm src/chunkmgr.asm src/noise.asm
; @link src/math.asm src/platform.asm src/gl.asm src/util.asm
; @link src/blocks.asm src/items.asm src/light.asm tests/world/wglib.asm
; @timeout 600
%include "common.inc"
%include "testlib.inc"
%include "../world/wglib.inc"

%define RD          16
%define R           (RD+2)
%define UNLOAD_D2   ((R+2)*(R+2) + (R+2))
%define SETTLE_MS   30000

section .rdata
; spawn, a 40x40-chunk square in 4-chunk steps, back to spawn
path:   dd 0,0, 4,0, 8,0, 12,0, 16,0, 20,0, 20,4, 20,8
        dd 20,12, 20,16, 20,20, 16,20, 12,20, 8,20, 4,20, 0,20
        dd -4,20, -8,20, -12,20, -16,20, -20,20, -20,16, -20,12, -20,8
        dd -20,4, -20,0, -20,-4, -20,-8, -20,-12, -20,-16, -20,-20, -16,-20
        dd -12,-20, -8,-20, -4,-20, 0,-20, 4,-20, 8,-20, 12,-20, 16,-20
        dd 20,-20, 20,-16, 20,-12, 20,-8, 20,-4, 20,0, 0,0
%define NPATH 47

section .bss
alignb 8
grid    resb 128*128

section .text

PROC busy, 0
    call wg_chunk_count
    mov  esi, eax
    xor  ebx, ebx
.ch:
    cmp  ebx, esi
    jge  .no
    mov  ecx, ebx
    call wg_chunk_ptr
    mov  eax, [rax+CHUNK.state]
    cmp  eax, CS_QUEUED
    je   .yes
    cmp  eax, CS_GENERATING
    je   .yes
    inc  ebx
    jmp  .ch
.yes:
    mov  eax, 1
    jmp  .done
.no:
    xor  eax, eax
.done:
ENDP

; pump until the disc around the player is done (idle, > 900 chunks). eax = peak
PROC settle, 0
    xor  r12d, r12d                     ; peak
    call t_time_ms
    lea  r13, [rax+SETTLE_MS]
.loop:
    call t_time_ms
    cmp  rax, r13
    jge  .done
    call chunkmgr_update
    call wg_chunk_count
    cmp  eax, r12d
    cmovg r12d, eax
    mov  r14d, eax
    call busy
    test eax, eax
    jnz  .sleep
    cmp  r14d, 900
    jle  .sleep
    call chunkmgr_update
    call busy
    test eax, eax
    jz   .done
.sleep:
    mov  ecx, 2
    call sleep_ms
    jmp  .loop
.done:
    mov  eax, r12d
ENDP

PROC test_main, 0
    mov  ecx, 4242
    call wg_set_seed
    lea  rax, [rel g_settings]
    mov  dword [rax+SETTINGS.render_dist], RD
    FCONST xmm0, 8.0
    FCONST xmm1, 8.0
    call wg_set_player
    call chunkmgr_init
    call t_wander_loop
    call chunkmgr_shutdown
    call world_clear
ENDP

PROC t_wander_loop, 32
    TEST "PoolPressure.wander_loop"
    mov  dword LOC(0), 0                ; worst
    mov  dword LOC(4), 0                ; missing, over all stops
    mov  dword LOC(8), 0                ; should have been unloaded
    xor  r15d, r15d
.stop:
    lea  rax, [rel path]
    mov  r12d, [rax+r15*8]
    mov  r13d, [rax+r15*8+4]
    mov  eax, r12d
    shl  eax, 4
    add  eax, 8
    cvtsi2ss xmm0, eax
    mov  eax, r13d
    shl  eax, 4
    add  eax, 8
    cvtsi2ss xmm1, eax
    call wg_set_player
    call settle
    cmp  eax, LOC(0)
    jle  .w
    mov  LOC(0), eax
.w:
    lea  rcx, [rel grid]
    mov  edx, r12d
    mov  r8d, r13d
    call wg_grid
    mov  r14d, -R
.dx:
    mov  ebx, -R
.dz:
    mov  eax, r14d
    imul eax, eax
    mov  ecx, ebx
    imul ecx, ecx
    add  eax, ecx
    cmp  eax, R*R+R
    jg   .dnext
    lea  rcx, [rel grid]
    mov  edx, r14d
    mov  r8d, ebx
    call wg_grid_get
    and  eax, 0x7F
    cmp  eax, CS_GENERATED
    jge  .dnext
    cmp  dword LOC(4), 0
    jne  .mcnt
    lea  eax, [r12d+r14d]
    lea  ecx, [r13d+ebx]
    WG_SAY3 "first missing chunk (cx cz stop):", eax, ecx, r15d
.mcnt:
    inc  dword LOC(4)
.dnext:
    inc  ebx
    cmp  ebx, R
    jle  .dz
    inc  r14d
    cmp  r14d, R
    jle  .dx
    ; nothing outside the unload disc survives
    call wg_chunk_count
    mov  edi, eax
    xor  esi, esi
.ch:
    cmp  esi, edi
    jge  .chdone
    mov  ecx, esi
    call wg_chunk_ptr
    mov  ecx, [rax+CHUNK.cx]
    sub  ecx, r12d
    imul ecx, ecx
    mov  edx, [rax+CHUNK.cz]
    sub  edx, r13d
    imul edx, edx
    add  ecx, edx
    cmp  ecx, UNLOAD_D2
    jle  .chnext
    cmp  dword LOC(8), 0
    jne  .ucnt
    mov  ecx, [rax+CHUNK.cx]
    mov  edx, [rax+CHUNK.cz]
    WG_SAY3 "first chunk that should have been unloaded (cx cz stop):", ecx, edx, r15d
.ucnt:
    inc  dword LOC(8)
.chnext:
    inc  esi
    jmp  .ch
.chdone:
    inc  r15d
    cmp  r15d, NPATH
    jl   .stop

    CHECK_EQ32 LOC(4), 0, "load disc complete at every stop"
    CHECK_EQ32 LOC(8), 0, "every chunk outside the unload disc was unloaded"
    xor  eax, eax
    cmp  dword LOC(0), MAX_CHUNKS-64
    setl al
    CHECK_TRUE eax, "chunk pool came close to exhaustion"
    WG_SAY3 "stops / peak chunks resident / pool:", NPATH, LOC(0), MAX_CHUNKS
ENDP
