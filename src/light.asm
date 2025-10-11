; packed light byte: (sky << 4) | block, 6-neighbour BFS queue
%define IMPL_LIGHT
%include "common.inc"

%define LQ_BITS     20
%define LQ_SIZE     (1 << LQ_BITS)  ; 4 MB each
%define LQ_MASK     (LQ_SIZE - 1)
%define LP_POSMASK  ((1 << 21) - 1)  ; wx | wz<<7 | y<<14, rem entries also carry value<<21
%define LP_X        1
%define LP_Z        128
%define LP_Y        16384
%define LP_YCLEAR   (~(127 << 14))
%define LW_DIM      5
%define LW_MAXC     79
%define LW_ORG      32  ; centre chunk starts at wx/wz 32
%define LIGHT_OFS   (CHUNK_LIGHT - CHUNK_BLOCKS)

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
; mesh sections (16 tall) a light change at y touches: own + the neighbour one on a section edge
align 16
secmask_tbl:
%assign yy 0
%rep 128
  %assign sec (yy >> 4)
  %assign m (1 << sec)
  %if ((yy & 15) == 0) && (sec > 0)
    %assign m (m | (1 << (sec - 1)))
  %endif
  %if ((yy & 15) == 15) && (sec < 7)
    %assign m (m | (1 << (sec + 1)))
  %endif
    db m
  %assign yy yy+1
%endrep

section .bss
alignb 16
lw_chunks:          resq 25  ; 5x5, z outer
lw_dirty:           resd 28
lq_prop_head:       resd 1
lq_prop_tail:       resd 1
lq_rem_head:        resd 1
lq_rem_tail:        resd 1
global light_stat_overflow, light_stat_cells
light_stat_overflow: resd 1
light_stat_cells:    resd 1
alignb 64
lq_prop:            resd LQ_SIZE  ; positions only. a popped cell rereads its value, so stale dupes are harmless
lq_rem:             resd LQ_SIZE  ; pos | old<<21

section .text

; worker threads. only touches this chunk + blk_opacity
    global light_init_chunk_sky
    align 16
light_init_chunk_sky:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, FRAME_OUT
    mov  rbx, rcx
    lea  rdi, [rel blk_opacity]
    xor  r12d, r12d  ; column x + z*16
.column:
    lea  rsi, [rbx + CHUNK_BLOCKS + 127*256]
    add  rsi, r12
    mov  ecx, 15
    xor  r10d, r10d  ; hm, 0 = open column
    xor  r11d, r11d
    mov  r9d, 127
.down:
    movzx eax, byte [rsi]
    movzx eax, byte [rdi + rax]
    test r11d, r11d
    jnz  .hm_known
    test eax, eax
    jz   .hm_known
    lea  r10d, [r9 + 1]  ; first blocker from the top
    mov  r11d, 1
.hm_known:
    ; 15 drops straight down, anything dimmer loses 1 too
    cmp  ecx, 15
    je   .full
    dec  ecx
.full:
    sub  ecx, eax
    jns  .store
    xor  ecx, ecx
.store:
    mov  edx, ecx
    shl  edx, 4
    mov  [rsi + LIGHT_OFS], dl
    sub  rsi, 256
    dec  r9d
    jns  .down
    mov  [rbx + CHUNK.heightmap + r12], r10b
    inc  r12d
    cmp  r12d, 256
    jb   .column
    lea  rsp, [rbp-32]
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; small leaf helpers, no frame, each has its own reg convention

; mark_cell(ecx packed): clobbers rax rcx rdx only. the 3x3x3 smooth light/AO
; sampling means a border cell has to dirty the neighbour chunk(s) too
align 16
mark_cell:
    push r8
    push r9
    push r10
    push r11
    inc  dword [rel light_stat_cells]
    mov  eax, ecx
    shr  eax, 14
    and  eax, 127
    lea  rdx, [rel secmask_tbl]
    movzx r8d, byte [rdx + rax]
    mov  r10d, ecx
    and  r10d, 127
    mov  r11d, ecx
    shr  r11d, 7
    and  r11d, 127
    mov  r9d, r10d
    shr  r9d, 4
    mov  eax, r11d
    shr  eax, 4
    lea  eax, [rax + rax*4]
    add  r9d, eax
    lea  rdx, [rel lw_dirty]
    or   [rdx + r9*4], r8d
    ; x neighbour chunk delta 0/-1/+1, z below is 0/-5/+5
    xor  eax, eax
    mov  ecx, r10d
    and  ecx, 15
    jnz  .x_hi
    cmp  r10d, 16  ; lx == 0 -> west chunk, if it's in the window
    jb   .x_done
    mov  eax, -1
    jmp  .x_done
.x_hi:
    cmp  ecx, 15
    jne  .x_done
    cmp  r10d, 64
    jae  .x_done
    mov  eax, 1
.x_done:
    xor  ecx, ecx
    mov  r10d, r11d
    and  r10d, 15
    jnz  .z_hi
    cmp  r11d, 16
    jb   .z_done
    mov  ecx, -LW_DIM
    jmp  .z_done
.z_hi:
    cmp  r10d, 15
    jne  .z_done
    cmp  r11d, 64
    jae  .z_done
    mov  ecx, LW_DIM
.z_done:
    test eax, eax
    jz   .no_x
    lea  r10d, [r9 + rax]
    or   [rdx + r10*4], r8d
    test ecx, ecx
    jz   .done
    add  r10d, ecx  ; corner -> diagonal chunk too
    or   [rdx + r10*4], r8d
.no_x:
    test ecx, ecx
    jz   .done
    lea  r10d, [r9 + rcx]
    or   [rdx + r10*4], r8d
.done:
    pop  r11
    pop  r10
    pop  r9
    pop  r8
    ret

; keeps every reg. full ring just drops the entry and counts it
%macro MEMQ_PUSH 3
    push r8
    push r9
    mov  r8d, [rel %3]
    lea  r9, [rel %1]
    mov  [r9 + r8*4], ecx
    inc  r8d
    and  r8d, LQ_MASK
    cmp  r8d, [rel %2]
    je   %%full
    mov  [rel %3], r8d
    pop  r9
    pop  r8
    ret
%%full:
    inc  dword [rel light_stat_overflow]
    pop  r9
    pop  r8
    ret
%endmacro

align 16
prop_push:
    MEMQ_PUSH lq_prop, lq_prop_head, lq_prop_tail
align 16
rem_push:
    MEMQ_PUSH lq_rem, lq_rem_head, lq_rem_tail

align 16
q_reset:
    mov  dword [rel lq_prop_head], 0
    mov  dword [rel lq_prop_tail], 0
    mov  dword [rel lq_rem_head], 0
    mov  dword [rel lq_rem_tail], 0
    ret

; cell_ptr: rax = chunk base + in-chunk offset, 0 if missing. clobbers rax rdx r8 r9
align 16
cell_ptr:
    mov  eax, ecx
    and  eax, 127
    mov  edx, ecx
    shr  edx, 7
    and  edx, 127
    mov  r8d, eax
    shr  r8d, 4
    mov  r9d, edx
    shr  r9d, 4
    lea  r9d, [r9 + r9*4]
    add  r8d, r9d
    lea  r9, [rel lw_chunks]
    mov  r8, [r9 + r8*8]
    test r8, r8
    jz   .null
    and  eax, 15
    and  edx, 15
    shl  edx, 4
    or   eax, edx
    mov  edx, ecx
    shr  edx, 14
    and  edx, 127
    shl  edx, 8
    or   eax, edx
    add  rax, r8
    ret
.null:
    xor  eax, eax
    ret

align 16
get_hm_w:
    cmp  ecx, LW_MAXC
    ja   .none
    cmp  edx, LW_MAXC
    ja   .none
    mov  r8d, ecx
    shr  r8d, 4
    mov  r9d, edx
    shr  r9d, 4
    lea  r9d, [r9 + r9*4]
    add  r8d, r9d
    lea  r9, [rel lw_chunks]
    mov  r8, [r9 + r8*8]
    test r8, r8
    jz   .none
    and  ecx, 15
    and  edx, 15
    shl  edx, 4
    or   ecx, edx
    movzx eax, byte [r8 + CHUNK.heightmap + rcx]
    ret
.none:
    xor  eax, eax
    ret

; cell + 6 neighbours. must not be on the window's outer ring
align 16
push_around:
    push rcx
    call prop_push
    add  ecx, LP_X
    call prop_push
    sub  ecx, 2*LP_X
    call prop_push
    add  ecx, LP_X + LP_Z
    call prop_push
    sub  ecx, 2*LP_Z
    call prop_push
    add  ecx, LP_Z
    mov  eax, ecx
    shr  eax, 14
    and  eax, 127
    cmp  eax, 127
    je   .no_up
    add  ecx, LP_Y
    call prop_push
    sub  ecx, LP_Y
.no_up:
    test eax, eax
    jz   .no_down
    sub  ecx, LP_Y
    call prop_push
.no_down:
    pop  rcx
    ret

align 16
flush_dirty:
    lea  r8, [rel lw_chunks]
    lea  r9, [rel lw_dirty]
    xor  ecx, ecx
.next:
    mov  eax, [r9 + rcx*4]
    test eax, eax
    jz   .skip
    mov  dword [r9 + rcx*4], 0
    mov  rdx, [r8 + rcx*8]
    test rdx, rdx
    jz   .skip
    lock or [rdx + CHUNK.dirty], eax
.skip:
    inc  ecx
    cmp  ecx, 25
    jb   .next
    ret

; anything below CS_GENERATED goes in as null, a worker may still be writing it
LPROC build_window, 0
    lea  r12d, [rcx - 2]
    lea  r13d, [rdx - 2]
    mov  r14, r8
    xor  r15d, r15d
    xor  esi, esi
.row:
    xor  edi, edi
.col:
    lea  ecx, [r12 + rdi]
    lea  edx, [r13 + rsi]
    call world_get_chunk
    test rax, rax
    jz   .store
    cmp  dword [rax + CHUNK.state], CS_GENERATED
    jae  .store
    xor  eax, eax
.store:
    lea  rcx, [rel lw_chunks]
    mov  [rcx + r15*8], rax
    lea  rcx, [rel lw_dirty]
    mov  dword [rcx + r15*4], 0
    inc  r15d
    inc  edi
    cmp  edi, LW_DIM
    jb   .col
    inc  esi
    cmp  esi, LW_DIM
    jb   .row
    lea  rcx, [rel lw_chunks]
    test r14, r14
    jz   .ret
    mov  [rcx + 12*8], r14  ; caller's pointer wins for the centre
.ret:
    mov  rax, [rcx + 12*8]
ENDP

; bfs kernels. regs: rbx lw_chunks, rsi queue, rdi table (opacity for prop,
; blk_light for removal!), r12d/r13d head/tail, r14d packed pos, r15 cell ptr,
; r8d value. head/tail only written back at the end

%macro QPUSH 0
    mov  [rsi + r13*4], ecx
    lea  eax, [r13 + 1]
    and  eax, LQ_MASK
    cmp  eax, r12d
    je   %%full
    mov  r13d, eax
    jmp  %%ok
%%full:
    inc  dword [rel light_stat_overflow]
%%ok:
%endmacro

%macro DECODE 1
    mov  r10d, r14d
    and  r10d, 127
    mov  r11d, r14d
    shr  r11d, 7
    and  r11d, 127
    mov  r9d, r10d
    shr  r9d, 4
    mov  ecx, r11d
    shr  ecx, 4
    lea  ecx, [rcx + rcx*4]
    add  r9d, ecx
    mov  r15, [rbx + r9*8]
    test r15, r15
    jz   %1
    mov  ecx, r10d
    and  ecx, 15
    mov  edx, r11d
    and  edx, 15
    shl  edx, 4
    or   ecx, edx
    mov  eax, r14d
    shr  eax, 14
    shl  eax, 8
    or   ecx, eax
    add  r15, rcx
%endmacro

%macro NB_TRY 3
 %if NB_MODE == 0
    movzx eax, byte [rdx + CHUNK_BLOCKS]
    movzx eax, byte [rdi + rax]
    mov  ecx, r8d
  %if CHAN_SKY && %2
    cmp  ecx, 15  ; full daylight going down, no falloff
    je   %%nodecay
    dec  ecx
%%nodecay:
    sub  ecx, eax
  %else
    dec  ecx
    sub  ecx, eax
  %endif
    jle  %3
    movzx eax, byte [rdx + CHUNK_LIGHT]
  %if CHAN_SKY
    shr  eax, 4
  %else
    and  eax, 15
  %endif
    cmp  ecx, eax
    jle  %3
  %if CHAN_SKY
    shl  ecx, 4
    and  byte [rdx + CHUNK_LIGHT], 0x0F
  %else
    and  byte [rdx + CHUNK_LIGHT], 0xF0
  %endif
    or   [rdx + CHUNK_LIGHT], cl
    lea  ecx, [r14 + (%1)]
    QPUSH
    lea  ecx, [r14 + (%1)]
    call mark_cell
 %else
    movzx eax, byte [rdx + CHUNK_LIGHT]
  %if CHAN_SKY
    shr  eax, 4
  %else
    and  eax, 15
  %endif
    test eax, eax
    jz   %3
    cmp  eax, r8d
    jae  %%border  ; lit from elsewhere, re-propagate it
  %if CHAN_SKY
    and  byte [rdx + CHUNK_LIGHT], 0x0F
  %else
    movzx ecx, byte [rdx + CHUNK_BLOCKS]
    movzx ecx, byte [rdi + rcx]
    cmp  ecx, eax
    jae  %%border
    and  byte [rdx + CHUNK_LIGHT], 0xF0
    or   [rdx + CHUNK_LIGHT], cl  ; drop to emission level, not 0
    mov  edx, ecx
  %endif
    shl  eax, 21
    lea  ecx, [r14 + (%1)]
    or   ecx, eax
    QPUSH
  %if CHAN_SKY == 0
    test edx, edx
    jz   %%no_emit
    lea  ecx, [r14 + (%1)]
    call prop_push  ; darkened emitter has to shine again
%%no_emit:
  %endif
    lea  ecx, [r14 + (%1)]
    call mark_cell
    jmp  %3
%%border:
    lea  ecx, [r14 + (%1)]
    call prop_push
 %endif
%endmacro

; x/z neighbour, hops to the next window chunk at a border
%macro NB_H 6
    mov  eax, %1
    and  eax, 15
  %if %2
    cmp  eax, 15
  %endif
    je   %%cross
    lea  rdx, [r15 + (%3)]
    jmp  %%have
%%cross:
  %if %2
    cmp  %1, LW_MAXC
    jae  %%skip
  %else
    test %1, %1
    jz   %%skip
  %endif
    mov  rdx, [rbx + r9*8 + (%4)*8]
    test rdx, rdx
    jz   %%skip
    sub  rdx, [rbx + r9*8]  ; same offset in the other chunk, wrapped to the opposite edge
    add  rdx, r15
    add  rdx, (%5)
%%have:
    NB_TRY %6, 0, %%skip
%%skip:
%endmacro

; vertical, never leaves the chunk
%macro NB_Y 2
    mov  eax, r14d
    shr  eax, 14
  %if %1
    cmp  eax, 127
    je   %%skip
    lea  rdx, [r15 + 256]
    NB_TRY %2, 0, %%skip
  %else
    test eax, eax
    jz   %%skip
    lea  rdx, [r15 - 256]
    NB_TRY %2, 1, %%skip
  %endif
%%skip:
%endmacro

%macro VISIT_NEIGHBOURS 0
    NB_Y 0, -LP_Y
    NB_H r10d, 1,   1,       1, -15,  LP_X
    NB_H r10d, 0,  -1,      -1,  15, -LP_X
    NB_H r11d, 1,  16,  LW_DIM, -240, LP_Z
    NB_H r11d, 0, -16, -LW_DIM,  240, -LP_Z
    NB_Y 1, LP_Y
%endmacro

%macro GEN_PROP 2
%assign CHAN_SKY %2
%assign NB_MODE 0
LPROC %1, 0
    lea  rbx, [rel lw_chunks]
    lea  rsi, [rel lq_prop]
    lea  rdi, [rel blk_opacity]
    mov  r12d, [rel lq_prop_head]
    mov  r13d, [rel lq_prop_tail]
.pop:
    cmp  r12d, r13d
    je   .done
    mov  r14d, [rsi + r12*4]
    inc  r12d
    and  r12d, LQ_MASK
    and  r14d, LP_POSMASK
    DECODE .pop
    movzx r8d, byte [r15 + CHUNK_LIGHT]
  %if CHAN_SKY
    shr  r8d, 4
  %else
    and  r8d, 15
  %endif
    cmp  r8d, 1
    jbe  .pop  ; 0/1 can't light anything
    VISIT_NEIGHBOURS
    jmp  .pop
.done:
    mov  [rel lq_prop_head], r12d
    mov  [rel lq_prop_tail], r13d
ENDP
%endmacro

; removal, borders end up on the prop queue
%macro GEN_REM 2
%assign CHAN_SKY %2
%assign NB_MODE 1
LPROC %1, 0
    lea  rbx, [rel lw_chunks]
    lea  rsi, [rel lq_rem]
    lea  rdi, [rel blk_light]
    mov  r12d, [rel lq_rem_head]
    mov  r13d, [rel lq_rem_tail]
.pop:
    cmp  r12d, r13d
    je   .done
    mov  r14d, [rsi + r12*4]
    inc  r12d
    and  r12d, LQ_MASK
    mov  r8d, r14d
    shr  r8d, 21
    and  r8d, 15
    and  r14d, LP_POSMASK
    DECODE .pop
    VISIT_NEIGHBOURS
    jmp  .pop
.done:
    mov  [rel lq_rem_head], r12d
    mov  [rel lq_rem_tail], r13d
ENDP
%endmacro

GEN_PROP bfs_prop_sky, 1
GEN_PROP bfs_prop_blk, 0
GEN_REM  bfs_rem_sky,  1
GEN_REM  bfs_rem_blk,  0

LPROC seed_column, 0
    mov  r12d, ecx
    mov  r13d, edx
    mov  r14d, r8d
    mov  r15d, r9d
    test r15d, r15d
    jz   .done
    mov  ecx, r13d
    shl  ecx, 7
    or   ecx, r12d
    mov  esi, ecx
    call cell_ptr
    test rax, rax
    jz   .done
    mov  rbx, rax
    xor  edi, edi
.loop:
    movzx eax, byte [rbx + CHUNK_LIGHT]
    mov  ecx, r14d
    shr  eax, cl
    and  eax, 15
    cmp  eax, 2
    jb   .next
    mov  ecx, edi
    shl  ecx, 14
    or   ecx, esi
    call prop_push
.next:
    add  rbx, 256
    inc  edi
    cmp  edi, r15d
    jb   .loop
.done:
ENDP

; let light that's already in the 4 side chunks flow in
LPROC seed_faces, 0
    mov  r12d, ecx
    xor  r13d, r13d
.k:
    lea  r14d, [r13 + LW_ORG]
    mov  ecx, LW_ORG - 1
    mov  edx, r14d
    mov  r8d, r12d
    mov  r9d, 128
    call seed_column
    mov  ecx, LW_ORG + 16
    mov  edx, r14d
    mov  r8d, r12d
    mov  r9d, 128
    call seed_column
    mov  ecx, r14d
    mov  edx, LW_ORG - 1
    mov  r8d, r12d
    mov  r9d, 128
    call seed_column
    mov  ecx, r14d
    mov  edx, LW_ORG + 16
    mov  r8d, r12d
    mov  r9d, 128
    call seed_column
    inc  r13d
    cmp  r13d, 16
    jb   .k
ENDP

PROC light_propagate_chunk, 32
    mov  rbx, rcx
    mov  ecx, [rbx + CHUNK.cx]
    mov  edx, [rbx + CHUNK.cz]
    mov  r8, rbx
    call build_window
    call q_reset

    ; a column cell can only spread if it's below its own hm or a side neighbour's,
    ; so only scan up to the max of those 5
    xor  r12d, r12d
.sky_z:
    xor  r13d, r13d
.sky_x:
    lea  r14d, [r13 + LW_ORG]
    lea  r15d, [r12 + LW_ORG]
    mov  ecx, r14d
    mov  edx, r15d
    call get_hm_w
    mov  esi, eax
    lea  ecx, [r14 - 1]
    mov  edx, r15d
    call get_hm_w
    cmp  eax, esi
    cmova esi, eax
    lea  ecx, [r14 + 1]
    mov  edx, r15d
    call get_hm_w
    cmp  eax, esi
    cmova esi, eax
    mov  ecx, r14d
    lea  edx, [r15 - 1]
    call get_hm_w
    cmp  eax, esi
    cmova esi, eax
    mov  ecx, r14d
    lea  edx, [r15 + 1]
    call get_hm_w
    cmp  eax, esi
    cmova esi, eax
    mov  ecx, r14d
    mov  edx, r15d
    mov  r8d, 4
    mov  r9d, esi
    call seed_column
    inc  r13d
    cmp  r13d, 16
    jb   .sky_x
    inc  r12d
    cmp  r12d, 16
    jb   .sky_z

    mov  ecx, 4 ; v1: light scratch #0
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (light:0)
    call seed_faces ; v1: light scratch #1
    call bfs_prop_sky ; v1: light scratch #2
    ; TODO: hoist invariant pointer load out of .loop (light:2)

    ; block light, every emitter
    call q_reset ; v1: light scratch #5
    lea  rsi, [rbx + CHUNK_BLOCKS] ; v1: light scratch #6
    ; FIXME: negative world x/z needs sar 4, not shr 4 (light:6)
    lea  rdi, [rel blk_light] ; v1: light scratch #7
    xor  r12d, r12d ; v1: light scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (light:8)
.emit: ; v1: light scratch #9
    movzx eax, byte [rsi + r12] ; v1: light scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (light:10)
    movzx eax, byte [rdi + rax] ; v1: light scratch #11
    test eax, eax ; v1: light scratch #12
    ; note: rcx = state ptr, rdx = index, r8d = flags (light:12)
    jz   .emit_next ; v1: light scratch #13
    mov  ecx, r12d ; v1: light scratch #14
    ; TODO: verify 16-byte rsp alignment before inner call (light:14)
    and  ecx, 15 ; v1: light scratch #15
    add  ecx, LW_ORG ; v1: light scratch #16
    ; TODO: clamp index before table lookup on malformed input (light:16)
    mov  edx, r12d ; v1: light scratch #17
    shr  edx, 4 ; v1: light scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (light:18)
    and  edx, 15 ; v1: light scratch #19
    add  edx, LW_ORG ; v1: light scratch #20
    ; TODO: hoist invariant pointer load out of .loop (light:20)
    shl  edx, 7 ; v1: light scratch #21
    or   ecx, edx ; v1: light scratch #22
    ; FIXME: negative world x/z needs sar 4, not shr 4 (light:22)
    mov  edx, r12d ; v1: light scratch #23
    shr  edx, 8 ; v1: light scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (light:24)
    shl  edx, 14 ; v1: light scratch #25
    or   ecx, edx ; v1: light scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (light:26)
    mov  r13d, ecx ; v1: light scratch #27
    movzx edx, byte [rsi + r12 + LIGHT_OFS] ; v1: light scratch #28
    ; note: rcx = state ptr, rdx = index, r8d = flags (light:28)
    and  edx, 15 ; v1: light scratch #29
    cmp  eax, edx ; v1: light scratch #30
    ; TODO: verify 16-byte rsp alignment before inner call (light:30)
    jbe  .emit_push ; v1: light scratch #31
    and  byte [rsi + r12 + LIGHT_OFS], 0xF0 ; v1: light scratch #32
    ; TODO: clamp index before table lookup on malformed input (light:32)
    or   [rsi + r12 + LIGHT_OFS], al ; v1: light scratch #33
    call mark_cell ; v1: light scratch #34
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (light:34)
.emit_push:
    mov  ecx, r13d
    call prop_push
.emit_next:
    inc  r12d
    cmp  r12d, CHUNK_VOL
    jb   .emit

    xor  ecx, ecx
    call seed_faces
    call bfs_prop_blk

    call flush_dirty
    ; chunk manager may have beaten us to it, then this is a no-op
    mov  eax, CS_GENERATED
    mov  ecx, CS_LIT
    lock cmpxchg [rbx + CHUNK.state], ecx
ENDP

; block is already swapped when we get here.
; LOC(0) old hm, LOC(4) new hm, LOC(8) scratch
PROC light_on_block_changed, 32
    mov  r12d, ecx
    mov  r13d, edx
    mov  r14d, r8d
    mov  r15d, r9d
    and  r15d, 255
    cmp  r13d, 127
    ja   .done  ; unsigned, so y < 0 lands here too
    mov  ecx, r12d
    sar  ecx, 4
    mov  edx, r14d
    sar  edx, 4
    xor  r8d, r8d
    call build_window
    test rax, rax
    jz   .done
    mov  rbx, rax

    and  r12d, 15
    and  r14d, 15
    lea  edi, [r12 + LW_ORG]  ; edi = packed pos
    lea  eax, [r14 + LW_ORG]
    shl  eax, 7
    or   edi, eax
    mov  eax, r13d
    shl  eax, 14
    or   edi, eax
    shl  r14d, 4
    or   r12d, r14d
    mov  eax, r13d
    shl  eax, 8
    add  eax, r12d
    lea  rsi, [rbx + rax]
    movzx r14d, byte [rsi + CHUNK_BLOCKS]  ; new block id

    ; same opacity and emission -> nothing can change
    lea  rax, [rel blk_opacity]
    movzx ecx, byte [rax + r14]
    movzx edx, byte [rax + r15]
    cmp  ecx, edx
    jne  .work
    lea  rax, [rel blk_light]
    movzx ecx, byte [rax + r14]
    movzx edx, byte [rax + r15]
    cmp  ecx, edx
    je   .done
.work:
    call q_reset

    ; don't read the old hm from CHUNK.heightmap, world_set_block may already
    ; have updated it. read it off the light instead (sky 15 <=> y >= hm)
    lea  rdx, [rbx + CHUNK_LIGHT + 127*256]
    add  rdx, r12
    mov  ecx, 127
.sky_scan:
    cmp  byte [rdx], 0xF0
    jb   .sky_found
    sub  rdx, 256
    dec  ecx
    jns  .sky_scan
.sky_found:
    inc  ecx
    mov  LOC(0), ecx
    lea  rdx, [rbx + CHUNK_BLOCKS + 127*256]
    add  rdx, r12
    lea  r8, [rel blk_opacity]
    mov  ecx, 127
.hm_scan:
    movzx eax, byte [rdx]
    cmp  byte [r8 + rax], 0
    jne  .hm_found
    sub  rdx, 256
    dec  ecx
    jns  .hm_scan
.hm_found:
    inc  ecx
    mov  [rbx + CHUNK.heightmap + r12], cl
    mov  LOC(4), ecx
    cmp  ecx, LOC(0)
    jbe  .hm_not_up

    ; v1 temporary guard (light #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (light #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (light #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (light #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (light #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (light #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (light #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (light #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (light #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (light #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (light #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (light #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (light #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (light #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (light #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (light #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (light #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (light #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (light #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (light #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (light #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (light #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (light #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (light #63)
    xor     r11d, r11d ; clear v1 slot 63
