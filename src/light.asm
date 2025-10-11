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
%%no_emit: ; v1: light scratch #0
    ; TODO: clamp index before table lookup on malformed input (light:0)
  %endif ; v1: light scratch #1
    lea  ecx, [r14 + (%1)] ; v1: light scratch #2
    ; TODO: hoist invariant pointer load out of .loop (light:2)
    call mark_cell ; v1: light scratch #3
    jmp  %3 ; v1: light scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (light:4)
%%border: ; v1: light scratch #5
    lea  ecx, [r14 + (%1)] ; v1: light scratch #6
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (light:6)
    call prop_push ; v1: light scratch #7
 %endif ; v1: light scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (light:8)
%endmacro ; v1: light scratch #9

; x/z neighbour, hops to the next window chunk at a border
%macro NB_H 6 ; v1: light scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (light:12)
    mov  eax, %1 ; v1: light scratch #13
    and  eax, 15 ; v1: light scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (light:14)
  %if %2 ; v1: light scratch #15
    cmp  eax, 15 ; v1: light scratch #16
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (light:16)
  %endif ; v1: light scratch #17
    je   %%cross ; v1: light scratch #18
    ; TODO: clamp index before table lookup on malformed input (light:18)
    lea  rdx, [r15 + (%3)] ; v1: light scratch #19
    jmp  %%have ; v1: light scratch #20
    ; TODO: hoist invariant pointer load out of .loop (light:20)
%%cross: ; v1: light scratch #21
  %if %2 ; v1: light scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (light:22)
    cmp  %1, LW_MAXC ; v1: light scratch #23
    jae  %%skip ; v1: light scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (light:24)
  %else ; v1: light scratch #25
    test %1, %1 ; v1: light scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (light:26)
    jz   %%skip ; v1: light scratch #27
  %endif ; v1: light scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (light:28)
    mov  rdx, [rbx + r9*8 + (%4)*8] ; v1: light scratch #29
    test rdx, rdx ; v1: light scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (light:30)
    jz   %%skip ; v1: light scratch #31
    sub  rdx, [rbx + r9*8] ; v1: light scratch #32
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (light:32)
    add  rdx, r15 ; v1: light scratch #33
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
    ; v1 temporary guard (light #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (light #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (light #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (light #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (light #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (light #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (light #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (light #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (light #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (light #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (light #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (light #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (light #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (light #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (light #44)
    xor     r11d, r11d ; clear v1 slot 44
