; chunkmgr keeps chunks around java players too (ENT_REMOTE bodies, view in
; .timer), not just around the host. real worker threads, the renderer is
; stubbed so chunks stop at LIT, which is all mcplay needs to send them.
; @link src/world.asm src/worldgen.asm src/chunkmgr.asm src/noise.asm
; @link src/math.asm src/platform.asm src/gl.asm src/util.asm
; @link src/blocks.asm src/items.asm src/light.asm tests/world/wglib.asm
; @timeout 120
%define IMPL_ENTITY
%include "common.inc"
%include "testlib.inc"
%include "../world/wglib.inc"

%define RD          4
%define HR          (RD+2)              ; host load radius
%define SETTLE_MS   20000

section .bss
alignb 16
global g_entities, g_entity_count
g_entities:     resb ENTITY_size*MAX_ENTITIES
g_entity_count: resd 1

section .text

; (ecx cx, edx cz, r8d d2 max, r9d min state) -> eax chunks in that disc that
; are missing or below the state
PROC missing, 0
    mov  r12d, ecx
    mov  r13d, edx
    mov  r14d, r8d
    mov  r15d, r9d
    xor  ebx, ebx
    mov  esi, -16
.dz:
    mov  edi, -16
.dx:
    mov  eax, edi
    imul eax, edi
    mov  ecx, esi
    imul ecx, esi
    add  eax, ecx
    cmp  eax, r14d
    jg   .n
    lea  ecx, [r12+rdi]
    lea  edx, [r13+rsi]
    call world_get_chunk
    test rax, rax
    jz   .miss
    cmp  [rax+CHUNK.state], r15d
    jae  .n
.miss:
    inc  ebx
.n:
    inc  edi
    cmp  edi, 16
    jle  .dx
    inc  esi
    cmp  esi, 16
    jle  .dz
    mov  eax, ebx
ENDP

; (ecx cx, edx cz) -> eax 1 if that chunk is in the world at all
PROC loaded, 0
    call world_get_chunk
    test rax, rax
    setnz al
    movzx eax, al
ENDP

PROC settle, 0
    call t_time_ms
    lea  r13, [rax+SETTLE_MS]
    xor  r12d, r12d                     ; quiet rounds
.loop:
    call t_time_ms
    cmp  rax, r13
    jge  .done
    call chunkmgr_update
    call wg_chunk_count
    mov  esi, eax
    xor  ebx, ebx
    xor  edi, edi                       ; busy or GENERATED (light pending)
.ch:
    cmp  ebx, esi
    jge  .chd
    mov  ecx, ebx
    call wg_chunk_ptr
    mov  eax, [rax+CHUNK.state]
    cmp  eax, CS_QUEUED
    je   .b
    cmp  eax, CS_GENERATING
    jne  .nb
.b: inc  edi
.nb:
    inc  ebx
    jmp  .ch
.chd:
    test edi, edi
    jnz  .busy
    inc  r12d
    cmp  r12d, 200                      ; light promotions are budgeted per call
    jge  .done
    jmp  .sleep
.busy:
    xor  r12d, r12d
.sleep:
    mov  ecx, 2
    call sleep_ms
    jmp  .loop
.done:
ENDP

; (ecx slot, xmm1 x, xmm2 z, edx view) a java player's body
PROC put_remote, 0
    mov  eax, ecx
    shl  eax, 7
    lea  rbx, [rel g_entities]
    add  rbx, rax
    mov  byte [rbx+ENTITY.type], ENT_REMOTE
    movss [rbx+ENTITY.x], xmm1
    mov  dword [rbx+ENTITY.y], __float32__(80.0)
    movss [rbx+ENTITY.z], xmm2
    mov  [rbx+ENTITY.timer], edx
ENDP

%macro MISSING 5.nolist             ; cx, cz, d2, state, msg
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    call missing
    mov  r15d, eax
    CHECK_EQ32 r15d, 0, %5
%endmacro

%macro LOADED 3.nolist              ; cx, cz, want
    mov  ecx, %1
    mov  edx, %2
    call loaded
    mov  r15d, eax
    CHECK_EQ32 r15d, %3, %str(loaded %1 %2)
%endmacro

PROC test_main, 0
    mov  ecx, 777
    call wg_set_seed
    lea  rax, [rel g_settings]
    mov  dword [rax+SETTINGS.render_dist], RD
    FCONST xmm0, 8.0
    FCONST xmm1, 8.0
    call wg_set_player
    call chunkmgr_init

    TEST "host + java player 30 chunks away"
    FCONST xmm1, 488.0                  ; chunk 30, 5
    FCONST xmm2, 88.0
    xor  ecx, ecx
    mov  edx, 5
    call put_remote
    call settle
    MISSING 0, 0, HR*HR+HR, CS_GENERATED, "host load disc generated"
    MISSING 0, 0, RD*RD+RD, CS_LIT, "host view lit"
    MISSING 30, 5, 7*7+7, CS_GENERATED, "remote load disc (view 5 + 2) generated"
    MISSING 30, 5, 5*5+5, CS_LIT, "remote view lit"
    LOADED 15, 2, 0
    LOADED 30, 13, 0

    TEST "java player moves on, old area unloads"
    FCONST xmm1, 488.0                  ; chunk 30, 40
    FCONST xmm2, 648.0
    xor  ecx, ecx
    mov  edx, 5
    call put_remote
    call settle
    MISSING 30, 40, 5*5+5, CS_LIT, "new view lit"
    LOADED 30, 5, 0
    LOADED 33, 5, 0
    MISSING 0, 0, RD*RD+RD, CS_LIT, "host still fine"

    TEST "same spot twice, second one bigger"
    FCONST xmm1, 488.0
    FCONST xmm2, 648.0
    mov  ecx, 1
    mov  edx, 50                        ; capped at 10, disc 12
    call put_remote
    call settle
    MISSING 30, 40, 10*10+10, CS_LIT, "capped view 10 lit"
    LOADED 42, 40, 1
    LOADED 43, 40, 0                    ; 13*13 > 12*12+12, never asked for

    TEST "java players gone"
    lea  rbx, [rel g_entities]
    mov  byte [rbx+ENTITY.type], 0
    mov  byte [rbx+ENTITY_size+ENTITY.type], 0
    call settle
    LOADED 30, 40, 0
    call wg_chunk_count
    mov  r15d, eax
    xor  eax, eax
    cmp  r15d, 260                      ; host unload disc d2 <= 72 is ~230
    setl al
    CHECK_TRUE eax, "only the host's chunks are left"

    call chunkmgr_shutdown
    call world_clear
ENDP
