; chunkmgr with real worker threads. we play the renderer (LIT -> READY by
; hand), then teleport and check the old area unloads, then shutdown/re-init.
; @link src/world.asm src/worldgen.asm src/chunkmgr.asm src/noise.asm
; @link src/math.asm src/platform.asm src/gl.asm src/util.asm
; @link src/blocks.asm src/items.asm src/light.asm tests/world/wglib.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../world/wglib.inc"

%define RD      4
%define R       (RD+2)                  ; load radius

section .bss
alignb 8
grid    resb 128*128

section .text

; ecx ms of chunkmgr_update every ~5 ms. edx != 0: also fake the mesher
PROC pump, 0
    mov  r12d, ecx
    mov  r13d, edx
    call t_time_ms
    mov  r14, rax
    add  r14, r12
.loop:
    call t_time_ms
    cmp  rax, r14
    jge  .done
    call chunkmgr_update
    test r13d, r13d
    jz   .sleep
    call wg_chunk_count
    mov  esi, eax
    xor  ebx, ebx
.ch:
    cmp  ebx, esi
    jge  .sleep
    mov  ecx, ebx
    call wg_chunk_ptr
    cmp  dword [rax+CHUNK.state], CS_LIT
    jne  .next
    mov  dword [rax+CHUNK.state], CS_READY
.next:
    inc  ebx
    jmp  .ch
.sleep:
    mov  ecx, 5
    call sleep_ms
    jmp  .loop
.done:
ENDP

PROC set_player_i, 0
    cvtsi2ss xmm0, ecx
    cvtsi2ss xmm1, edx
    call wg_set_player
ENDP

PROC test_main, 0
    mov  ecx, 777
    call wg_set_seed
    lea  rax, [rel g_settings]
    mov  dword [rax+SETTINGS.render_dist], RD
    mov  ecx, 8
    mov  edx, 8
    call set_player_i
    call chunkmgr_init
    call chunkmgr_init                  ; twice on purpose, must be idempotent
    call t_stream_in
    call t_teleport_unloads
    call t_restart
    call chunkmgr_shutdown
ENDP

PROC t_stream_in, 16
    TEST "ChunkManager.1_stream_in"
    call t_time_ms
    mov  r12, rax
.wait:
    call t_time_ms
    sub  rax, r12
    cmp  rax, 20000
    jge  .waited
    call chunkmgr_spawn_ready
    test eax, eax
    jnz  .waited
    mov  ecx, 50
    mov  edx, 1
    call pump
    jmp  .wait
.waited:
    call chunkmgr_spawn_ready
    CHECK_EQ32 eax, 1, "spawn area never became ready"
    call chunkmgr_progress
    CHECK_NEAR xmm0, 1.0, 0.0005, "progress == 1.0 (3 places)"
    mov  ecx, 1000
    mov  edx, 1
    call pump

    lea  rcx, [rel grid]
    xor  edx, edx
    xor  r8d, r8d
    call wg_grid
    mov  r15d, eax
    ; whole load disc (dx^2+dz^2 <= R^2+R) present and >= GENERATED
    xor  r14d, r14d                     ; missing
    xor  edi, edi                       ; not generated
    mov  r12d, -R
.dx:
    mov  r13d, -R
.dz:
    mov  eax, r12d
    imul eax, eax
    mov  ecx, r13d
    imul ecx, ecx
    add  eax, ecx
    cmp  eax, R*R+R
    jg   .dnext
    lea  rcx, [rel grid]
    mov  edx, r12d
    mov  r8d, r13d
    call wg_grid_get
    test eax, eax
    jnz  .have
    inc  r14d
    jmp  .dnext
.have:
    and  eax, 0x7F
    cmp  eax, CS_GENERATED
    jge  .dnext
    inc  edi
.dnext:
    inc  r13d
    cmp  r13d, R
    jle  .dz
    inc  r12d
    cmp  r12d, R
    jle  .dx
    CHECK_EQ32 r14d, 0, "missing chunk inside the load radius"
    CHECK_EQ32 edi, 0, "load disc chunks are >= CS_GENERATED"
    ; inner ones (R-2 disc and R-2 square) must be all the way to READY
    xor  r14d, r14d
    xor  ebx, ebx
.inner:
    cmp  ebx, r15d
    jge  .inner_done
    mov  ecx, ebx
    call wg_chunk_ptr
    mov  ecx, [rax+CHUNK.cx]
    mov  edx, [rax+CHUNK.cz]
    mov  r8d, ecx
    imul r8d, ecx
    mov  r9d, edx
    imul r9d, edx
    add  r8d, r9d
    cmp  r8d, (R-2)*(R-2)
    jg   .inext
    mov  r9d, ecx
    neg  r9d
    cmovl r9d, ecx
    cmp  r9d, R-2
    jg   .inext
    mov  r9d, edx
    neg  r9d
    cmovl r9d, edx
    cmp  r9d, R-2
    jg   .inext
    cmp  dword [rax+CHUNK.state], CS_READY
    je   .inext
    test r14d, r14d
    jnz  .icnt
    mov  esi, [rax+CHUNK.state]
    WG_SAY3 "first inner chunk not lit/ready (cx cz state):", ecx, edx, esi
.icnt:
    inc  r14d
.inext:
    inc  ebx
    jmp  .inner
.inner_done:
    CHECK_EQ32 r14d, 0, "inner chunks are CS_READY"
    mov  eax, [rel g_stat_chunks_generated]
    xor  ecx, ecx
    cmp  eax, r15d
    setge cl
    CHECK_TRUE ecx, "g_stat_chunks_generated >= resident chunks"
    mov  eax, [rel g_stat_chunks_generated]
    WG_SAY3 "streamed chunks / generated / 0:", r15d, eax, 0
ENDP

PROC t_teleport_unloads, 0
    TEST "ChunkManager.2_teleport_unloads"
    mov  ecx, 5000
    mov  edx, -3000
    call set_player_i
    mov  ecx, 3000
    mov  edx, 1
    call pump
    ; player chunk is (312, -188), floor div
    call wg_chunk_count
    mov  r15d, eax
    xor  r14d, r14d                     ; stale
    xor  r13d, r13d                     ; >= GENERATED
    xor  ebx, ebx
.ch:
    cmp  ebx, r15d
    jge  .done_list
    mov  ecx, ebx
    call wg_chunk_ptr
    cmp  dword [rax+CHUNK.state], CS_GENERATED
    jl   .gen_no
    inc  r13d
.gen_no:
    mov  ecx, [rax+CHUNK.cx]
    sub  ecx, 312
    mov  edx, ecx
    neg  edx
    cmovl edx, ecx
    cmp  edx, RD+2+2
    jg   .stale
    mov  ecx, [rax+CHUNK.cz]
    add  ecx, 188
    mov  edx, ecx
    neg  edx
    cmovl edx, ecx
    cmp  edx, RD+2+2
    jle  .next
.stale:
    test r14d, r14d
    jnz  .scnt
    mov  ecx, [rax+CHUNK.cx]
    mov  edx, [rax+CHUNK.cz]
    WG_SAY3 "first stale chunk (cx cz 0):", ecx, edx, 0
.scnt:
    inc  r14d
.next:
    inc  ebx
    jmp  .ch
.done_list:
    CHECK_EQ32 r14d, 0, "stale chunks not unloaded"
    xor  eax, eax
    test r13d, r13d
    setnz al
    CHECK_TRUE eax, "some chunk around the new position is generated"
ENDP

PROC t_restart, 0
    TEST "ChunkManager.3_restart"
    call chunkmgr_shutdown
    call world_clear
    call wg_chunk_count
    CHECK_EQ32 eax, 0, "world_clear after shutdown empties the list"
    call chunkmgr_init
    mov  ecx, 8
    mov  edx, 8
    call set_player_i
    mov  ecx, 2000
    mov  edx, 1
    call pump
    call wg_chunk_count
    xor  ecx, ecx
    cmp  eax, 20
    setg cl
    CHECK_TRUE ecx, "streaming resumes after re-init (> 20 chunks)"
    call world_clear                    ; with workers live, it drains them first
    call wg_chunk_count
    CHECK_EQ32 eax, 0, "world_clear while running empties the list"
ENDP
