; light test world (3x3 chunks in the fakeworld pool) + a dumb reference solver.
; the solver only reads the shadow lt_blocks[y][z][x], never the chunks. least fixpoint
; by in-place sweeps, forward then backward, until a pair changes nothing. outside = 0.
%define IMPL_LIGHTLIB
%include "common.inc"
%include "testlib.inc"
%include "../light/lightlib.inc"  ; via -I tests/lib/

extern fw_pool, fw_misaligned, abi_probe
extern light_stat_overflow

%define FW_R     3
%define FW_DIM   7
%define WS       48  ; 3 chunks
%define WPLANE   (WS*WS)
%define WCELLS   (WPLANE*128)
%define OPACITY_15 15

section .rdata
; (id, value) pairs, 0 terminated. anything not listed is transparent and dark
op_pairs:   db T_STONE,15, T_LEAVES,1, T_ICE,3, T_GLOW,15, T_FURNACE_LIT,15, T_WATER,2, T_LAVA,15, 0,0
em_pairs:   db T_GLOW,15, T_TORCH,14, T_LANTERN,15, T_FURNACE_LIT,13, T_LAVA,15, 0,0

s_hm:       db "heightmap mismatch at ", 0
s_sky:      db "sky light mismatch at ", 0
s_blk:      db "block light mismatch at ", 0
s_cells:    db " cells, first x=", 0
s_y:        db " y=", 0
s_z:        db " z=", 0
s_got:      db ": got ", 0
s_want:     db " want ", 0
s_ovf:      db "light queue overflow count = ", 0
s_clob:     db "clobbered non-volatile registers: ", 0
s_edit:     db "after edit ", 0
s_at:       db " at (", 0
s_comma:    db ", ", 0
s_arrow:    db ") -> block id ", 0
s_mis:      db "world_get_chunk entered with a misaligned stack, times: ", 0

section .bss
global lt_c0
lt_c0:          resd 1
lt_x0:          resd 1  ; 16*c0
lt_shuf_seed:   resd 1
alignb 8
lt_qpf:         resq 1
lt_prop_ms:     resq 9  ; ms per light_propagate_chunk, last lt_generate
lt_fb_pos:      resq 1
lt_fb:          resb 512
alignb 64
lt_blocks:      resb WCELLS  ; shadow blocks [y][z][x]
ref_o:          resb WCELLS
ref_sky:        resb WCELLS
ref_blk:        resb WCELLS
ref_hm:         resb WPLANE  ; [z][x]

section .text

PROC fb_reset, 0
    mov  qword [rel lt_fb_pos], 0
    lea  rax, [rel lt_fb]
    mov  byte [rax], 0
ENDP

PROC fb_str, 0
    lea  rdi, [rel lt_fb]
    mov  rax, [rel lt_fb_pos]
.loop:
    cmp  rax, 500
    jae  .end
    mov  dl, [rcx]
    test dl, dl
    jz   .end
    mov  [rdi + rax], dl
    inc  rax
    inc  rcx
    jmp  .loop
.end:
    mov  byte [rdi + rax], 0
    mov  [rel lt_fb_pos], rax
ENDP

PROC fb_int, 32
    mov  rax, rcx
    lea  rsi, LOC(31)
    mov  byte [rsi], 0
    xor  ebx, ebx
    test rax, rax
    jns  .digits
    neg  rax
    mov  ebx, 1
.digits:
    mov  r8d, 10
.dl:
    xor  edx, edx
    div  r8
    add  dl, '0'
    dec  rsi
    mov  [rsi], dl
    test rax, rax
    jnz  .dl
    test ebx, ebx
    jz   .out
    dec  rsi
    mov  byte [rsi], '-'
.out:
    mov  rcx, rsi
    call fb_str
ENDP

PROC lt_setup_tables, 0
    lea  rdi, [rel blk_opacity]
    lea  rsi, [rel blk_light]
    xor  eax, eax
.clr:
    mov  byte [rdi + rax], 0
    mov  byte [rsi + rax], 0
    inc  eax
    cmp  eax, 256
    jb   .clr
    lea  rcx, [rel op_pairs]
.op:
    movzx eax, byte [rcx]
    movzx edx, byte [rcx + 1]
    test edx, edx
    jz   .em0
    mov  [rdi + rax], dl
    add  rcx, 2
    jmp  .op
.em0:
    lea  rcx, [rel em_pairs]
.em:
    movzx eax, byte [rcx]
    movzx edx, byte [rcx + 1]
    test edx, edx
    jz   .done
    mov  [rsi + rax], dl
    add  rcx, 2
    jmp  .em
.done:
ENDP

PROC lt_slot, 0
    add  ecx, FW_R
    add  edx, FW_R
    imul edx, edx, FW_DIM
    add  ecx, edx
    movsxd rcx, ecx
    imul rcx, rcx, CHUNK_BYTES
    lea  rax, [rel fw_pool]
    add  rax, rcx
ENDP

; world coords -> block byte. light sits at +LIGHT_OFS
%define LIGHT_OFS (CHUNK_LIGHT - CHUNK_BLOCKS)
PROC cell_ptr, 0
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    sar  ecx, 4
    mov  edx, edi
    sar  edx, 4
    call lt_slot
    mov  ecx, ebx
    and  ecx, 15
    mov  edx, edi
    and  edx, 15
    shl  edx, 4
    add  ecx, edx
    shl  esi, 8
    add  ecx, esi
    lea  rax, [rax + rcx + CHUNK_BLOCKS]
ENDP

PROC shadow_ptr, 0
    sub  ecx, [rel lt_x0]
    sub  r8d, [rel lt_x0]
    imul edx, edx, WPLANE
    imul r8d, r8d, WS
    add  ecx, edx
    add  ecx, r8d
    movsxd rcx, ecx
    lea  rax, [rel lt_blocks]
    add  rax, rcx
ENDP

PROC lt_world_new, 0
    mov  [rel lt_c0], ecx
    shl  ecx, 4
    mov  [rel lt_x0], ecx
    lea  rdi, [rel fw_pool]
    mov  rcx, FW_DIM*FW_DIM*CHUNK_BYTES
    xor  eax, eax
    rep  stosb
    lea  rdi, [rel lt_blocks]
    mov  rcx, WCELLS
    rep  stosb
ENDP

PROC lt_fill, 0
    mov  r10d, ARG5
    mov  r11d, ARG6
    mov  eax,  ARG7
    lea  rdi, [rel lt_blocks]
    mov  ebx, ecx
.y:
    cmp  ebx, edx
    jge  .done
    mov  esi, r8d
.z:
    cmp  esi, r9d
    jge  .ny
    imul r12d, ebx, WPLANE
    imul r13d, esi, WS
    add  r12d, r13d
    mov  r13d, r10d
.x:
    cmp  r13d, r11d
    jge  .nz
    lea  r14d, [r12 + r13]
    mov  [rdi + r14], al
    inc  r13d
    jmp  .x
.nz:
    inc  esi
    jmp  .z
.ny:
    inc  ebx
    jmp  .y
.done:
ENDP

PROC lt_fill_random, 0
    mov  r12d, edx
    mov  r13d, r8d
    mov  r14d, r9d
    imul ebx, ecx, WPLANE
    imul r12d, r12d, WPLANE
.cell:
    cmp  ebx, r12d
    jge  .done
    call t_rng_next
    xor  edx, edx
    mov  ecx, 1000
    div  rcx
    cmp  edx, r13d
    jae  .next
    lea  rax, [rel lt_blocks]
    mov  [rax + rbx], r14b
.next:
    inc  ebx
    jmp  .cell
.done:
ENDP

PROC lt_scatter, 0
    mov  ebx, ecx
    imul r12d, edx, WPLANE
    mov  r13d, r8d
.one:
    test ebx, ebx
    jz   .done
    call t_rng_next
    xor  edx, edx
    mov  ecx, WS
    div  rcx
    mov  esi, edx
    call t_rng_next
    xor  edx, edx
    mov  ecx, WS
    div  rcx
    imul edx, edx, WS
    add  edx, esi
    add  edx, r12d
    lea  rax, [rel lt_blocks]
    mov  [rax + rdx], r13b
    dec  ebx
    jmp  .one
.done:
ENDP

; do_init also runs light_init_chunk_sky on each chunk
PROC lt_load_chunks, 0
    mov  r15d, ecx
    xor  r12d, r12d  ; z outer
.chunk:
    cmp  r12d, 9
    jge  .done
    mov  eax, r12d
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    mov  r13d, edx
    mov  r14d, eax
    mov  ecx, [rel lt_c0]
    add  ecx, r13d
    mov  edx, [rel lt_c0]
    add  edx, r14d
    mov  esi, ecx
    mov  edi, edx
    call lt_slot
    mov  rbx, rax
    mov  [rbx + CHUNK.cx], esi
    mov  [rbx + CHUNK.cz], edi
    mov  dword [rbx + CHUNK.state], CS_GENERATED
    lea  r8, [rel lt_blocks]
    imul eax, r14d, 16*WS
    add  r8, rax
    imul eax, r13d, 16
    add  r8, rax
    lea  r9, [rbx + CHUNK_BLOCKS]
    xor  ecx, ecx
.y:
    xor  edx, edx
.z:
    imul eax, ecx, WPLANE
    imul r10d, edx, WS
    add  eax, r10d
    movdqu xmm0, [r8 + rax]
    mov  eax, ecx
    shl  eax, 8
    mov  r10d, edx
    shl  r10d, 4
    add  eax, r10d
    movdqu [r9 + rax], xmm0
    inc  edx
    cmp  edx, 16
    jb   .z
    inc  ecx
    cmp  ecx, 128
    jb   .y
    test r15d, r15d
    jz   .next
    mov  rcx, rbx
    call light_init_chunk_sky
.next:
    inc  r12d
    jmp  .chunk
.done:
ENDP

PROC lt_now_ms, 16
    cmp  qword [rel lt_qpf], 0
    jne  .have
    lea  rcx, [rel lt_qpf]
    call QueryPerformanceFrequency
.have:
    lea  rcx, LOC(0)
    call QueryPerformanceCounter
    cvtsi2sd xmm0, qword LOC(0)
    cvtsi2sd xmm1, qword [rel lt_qpf]
    divsd xmm0, xmm1
    mov  rax, __?float64?__(1000.0)
    movq xmm1, rax
    mulsd xmm0, xmm1
ENDP

; 0 rows, 1 reverse, 2 shuffled. every light_propagate_chunk is timed into lt_prop_ms
PROC lt_generate, 64
    mov  r15d, ecx
    mov  ecx, 1
    call lt_load_chunks
    xor  eax, eax
.init:
    mov  edx, eax
    cmp  r15d, 1
    jne  .fwd
    mov  edx, 8
    sub  edx, eax
.fwd:
    mov  LOC(rax), dl
    inc  eax
    cmp  eax, 9
    jb   .init
    cmp  r15d, 2
    jne  .run
    ; own lcg + fixed seed so the shuffle is the same every run
    mov  dword [rel lt_shuf_seed], 7
    mov  ebx, 8
.sh:
    imul eax, [rel lt_shuf_seed], 1103515245
    add  eax, 12345
    mov  [rel lt_shuf_seed], eax
    shr  eax, 8
    xor  edx, edx
    lea  ecx, [rbx + 1]
    div  ecx
    lea  rsi, LOC(0)
    mov  al, [rsi + rbx]
    mov  cl, [rsi + rdx]
    mov  [rsi + rbx], cl
    mov  [rsi + rdx], al
    dec  ebx
    jnz  .sh
.run:
    xor  r12d, r12d
.chunk:
    lea  rsi, LOC(0)
    movzx eax, byte [rsi + r12]
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    mov  ecx, [rel lt_c0]
    add  ecx, edx
    mov  edx, [rel lt_c0]
    add  edx, eax
    call lt_slot
    mov  rbx, rax
    call lt_now_ms
    movsd LOC(16), xmm0
    mov  rcx, rbx
    call light_propagate_chunk
    call lt_now_ms
    subsd xmm0, LOC(16)
    lea  rax, [rel lt_prop_ms]
    movsd [rax + r12*8], xmm0
    inc  r12d
    cmp  r12d, 9
    jb   .chunk
ENDP

PROC lt_prop_stats, 80
    mov  rbx, rcx
    lea  rsi, [rel lt_prop_ms]
    xor  eax, eax
.cp:
    movsd xmm0, [rsi + rax*8]
    movsd LOC(rax*8), xmm0
    inc  eax
    cmp  eax, 9
    jb   .cp
    mov  ecx, 1
.outer:
    cmp  ecx, 9
    jge  .sorted
    movsd xmm0, LOC(rcx*8)
    mov  edx, ecx
.inner:
    test edx, edx
    jz   .place
    movsd xmm1, LOC(rdx*8 - 8)
    comisd xmm1, xmm0
    jbe  .place
    movsd LOC(rdx*8), xmm1
    dec  edx
    jmp  .inner
.place:
    movsd LOC(rdx*8), xmm0
    inc  ecx
    jmp  .outer
.sorted:
    movsd xmm0, LOC(4*8)
    movsd [rbx], xmm0
    movsd xmm0, LOC(8*8)
    movsd [rbx + 8], xmm0
ENDP

PROC lt_flat_world, 0
    mov  ebx, ecx
    mov  ecx, -1
    call lt_world_new
    FILL 0, ebx, 0, LT_WS, 0, LT_WS, T_STONE
ENDP

PROC lt_dark_room, 0
    mov  ecx, -1
    call lt_world_new
    FILL 0, 100, 0, WS, 0, WS, T_STONE
    FILL 64, 72, 6, 42, 6, 42, T_AIR
    xor  ecx, ecx
    call lt_generate
ENDP

PROC lt_get_block, 0
    call cell_ptr
    movzx eax, byte [rax]
ENDP

PROC lt_set_block, 0
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12d, r9d
    call cell_ptr
    movzx r13d, byte [rax]
    mov  [rax], r12b
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call shadow_ptr
    mov  [rax], r12b
    test dword ARG5, LT_WORLD_HM
    jz   .notify
    ; what world_set_block does to CHUNK.heightmap
    mov  ecx, ebx
    xor  edx, edx
    mov  r8d, edi
    call shadow_ptr
    lea  r9, [rel blk_opacity]
    mov  ecx, 127
.col:
    imul edx, ecx, WPLANE
    movzx edx, byte [rax + rdx]
    cmp  byte [r9 + rdx], 0
    jne  .found
    dec  ecx
    jns  .col
.found:
    inc  ecx  ; -1+1 = 0 for an open column
    mov  r14d, ecx
    mov  ecx, ebx
    sar  ecx, 4
    mov  edx, edi
    sar  edx, 4
    call lt_slot
    mov  ecx, ebx
    and  ecx, 15
    mov  edx, edi
    and  edx, 15
    shl  edx, 4
    add  ecx, edx
    mov  [rax + CHUNK.heightmap + rcx], r14b
.notify:
    test dword ARG5, LT_NOTIFY
    jz   .done
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, r13d
    call light_on_block_changed
.done:
    mov  eax, r13d
ENDP

PROC lt_sky, 0
    call cell_ptr
    movzx eax, byte [rax + LIGHT_OFS]
    shr  eax, 4
ENDP

PROC lt_blk, 0
    call cell_ptr
    movzx eax, byte [rax + LIGHT_OFS]
    and  eax, 15
ENDP

PROC lt_hm, 0
    mov  ebx, ecx
    mov  esi, edx
    sar  ecx, 4
    sar  edx, 4
    call lt_slot
    and  ebx, 15
    and  esi, 15
    shl  esi, 4
    add  ebx, esi
    movzx eax, byte [rax + CHUNK.heightmap + rbx]
ENDP

PROC lt_header, 0
    mov  ebx, r8d
    call lt_slot
    mov  eax, [rax + rbx]
ENDP

PROC lt_set_header, 0
    mov  ebx, r8d
    mov  esi, r9d
    call lt_slot
    mov  [rax + rbx], esi
ENDP

PROC chunk_n, 0
    mov  eax, ecx
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    mov  ecx, [rel lt_c0]
    add  ecx, edx
    mov  edx, [rel lt_c0]
    add  edx, eax
    call lt_slot
ENDP

PROC lt_snapshot, 0
    mov  r12, rcx
    xor  ebx, ebx
.c:
    mov  ecx, ebx
    call chunk_n
    lea  rsi, [rax + CHUNK_LIGHT]
    mov  rdi, r12
    mov  ecx, 32768
    rep  movsb
    add  r12, 32768
    inc  ebx
    cmp  ebx, 9
    jb   .c
ENDP

PROC lt_all_sky, 0
    mov  r12d, ecx
    mov  r13d, edx
    mov  r14d, r8d
    xor  ebx, ebx
    mov  r15d, 1
.c:
    mov  ecx, ebx
    call chunk_n
    lea  rsi, [rax + CHUNK_LIGHT]
    mov  ecx, r12d
    shl  ecx, 8
    mov  edx, r13d
    shl  edx, 8
.cell:
    cmp  ecx, edx
    jge  .nc
    movzx eax, byte [rsi + rcx]
    shr  eax, 4
    cmp  eax, r14d
    je   .ok
    xor  r15d, r15d
.ok:
    inc  ecx
    jmp  .cell
.nc:
    inc  ebx
    cmp  ebx, 9
    jb   .c
    mov  eax, r15d
ENDP

PROC lt_all_blk_zero, 0
    xor  ebx, ebx
    mov  r15d, 1
.c:
    mov  ecx, ebx
    call chunk_n
    lea  rsi, [rax + CHUNK_LIGHT]
    xor  ecx, ecx
.cell:
    test byte [rsi + rcx], 15
    jz   .ok
    xor  r15d, r15d
.ok:
    inc  ecx
    cmp  ecx, 32768
    jb   .cell
    inc  ebx
    cmp  ebx, 9
    jb   .c
    mov  eax, r15d
ENDP

PROC lt_all_hm, 0
    mov  r12d, ecx
    xor  ebx, ebx
    mov  r15d, 1
.c:
    mov  ecx, ebx
    call chunk_n
    xor  ecx, ecx
.col:
    movzx edx, byte [rax + CHUNK.heightmap + rcx]
    cmp  edx, r12d
    je   .ok
    xor  r15d, r15d
.ok:
    inc  ecx
    cmp  ecx, 256
    jb   .col
    inc  ebx
    cmp  ebx, 9
    jb   .c
    mov  eax, r15d
ENDP

; one in-place gauss-seidel pass, dir +1/-1. eax = anything changed
PROC relax_sweep, 16
    mov  r12, rcx
    lea  r13, [rel ref_o]
    mov  LOC(0), edx
    mov  LOC(4), r8d
    mov  dword LOC(8), 0
    xor  r14d, r14d
.yl:
    mov  r9d, r14d
    cmp  dword LOC(4), 0
    jg   .yf
    mov  r9d, 127
    sub  r9d, r14d
.yf:
    xor  r15d, r15d
.zl:
    mov  r10d, r15d
    cmp  dword LOC(4), 0
    jg   .zf
    mov  r10d, WS-1
    sub  r10d, r15d
.zf:
    xor  ebx, ebx
.xl:
    mov  r11d, ebx
    cmp  dword LOC(4), 0
    jg   .xf
    mov  r11d, WS-1
    sub  r11d, ebx
.xf:
    imul esi, r9d, WPLANE
    imul edi, r10d, WS
    add  esi, edi
    add  esi, r11d
    xor  eax, eax  ; m = max of the 4 sides + below
    test r11d, r11d
    jz   .nx0
    movzx edx, byte [r12 + rsi - 1]
    cmp  edx, eax
    cmova eax, edx
.nx0:
    cmp  r11d, WS-1
    je   .nx1
    movzx edx, byte [r12 + rsi + 1]
    cmp  edx, eax
    cmova eax, edx
.nx1:
    test r10d, r10d
    jz   .nz0
    movzx edx, byte [r12 + rsi - WS]
    cmp  edx, eax
    cmova eax, edx
.nz0:
    cmp  r10d, WS-1
    je   .nz1
    movzx edx, byte [r12 + rsi + WS]
    cmp  edx, eax
    cmova eax, edx
.nz1:
    test r9d, r9d
    jz   .ny0
    movzx edx, byte [r12 + rsi - WPLANE]
    cmp  edx, eax
    cmova eax, edx
.ny0:
    xor  edi, edi  ; above, 0 at the top
    cmp  r9d, 127
    je   .ny1
    movzx edi, byte [r12 + rsi + WPLANE]
    cmp  edi, eax
    cmova eax, edi
.ny1:
    movzx ecx, byte [r13 + rsi]
    sub  eax, 1
    sub  eax, ecx  ; can go negative, fine
    cmp  dword LOC(0), 0
    je   .cmp
    cmp  edi, 15
    jne  .cmp
    mov  eax, 15
    sub  eax, ecx  ; sky straight down out of a 15
.cmp:
    movzx edx, byte [r12 + rsi]
    cmp  eax, edx
    jle  .keep
    mov  [r12 + rsi], al
    mov  dword LOC(8), 1
.keep:
    inc  ebx
    cmp  ebx, WS
    jb   .xl
    inc  r15d
    cmp  r15d, WS
    jb   .zl
    inc  r14d
    cmp  r14d, 128
    jb   .yl
    mov  eax, LOC(8)
ENDP

PROC relax, 0
    mov  rbx, rcx
    mov  esi, edx
.again:
    mov  rcx, rbx
    mov  edx, esi
    mov  r8d, 1
    call relax_sweep
    mov  edi, eax
    mov  rcx, rbx
    mov  edx, esi
    mov  r8d, -1
    call relax_sweep
    or   eax, edi
    jnz  .again
ENDP

PROC ref_solve, 0
    lea  rsi, [rel lt_blocks]
    lea  rdi, [rel ref_o]
    lea  r8,  [rel blk_opacity]
    lea  r9,  [rel blk_light]
    lea  r10, [rel ref_blk]
    xor  ecx, ecx
.o:
    movzx eax, byte [rsi + rcx]
    movzx edx, byte [r8 + rax]
    mov  [rdi + rcx], dl
    movzx edx, byte [r9 + rax]
    mov  [r10 + rcx], dl
    inc  ecx
    cmp  ecx, WCELLS
    jb   .o
    lea  r11, [rel ref_hm]
    lea  r10, [rel ref_sky]
    xor  ecx, ecx
.col:
    mov  edx, 127
.down:
    imul eax, edx, WPLANE
    add  eax, ecx
    cmp  byte [rdi + rax], 0
    jne  .top
    dec  edx
    jns  .down
.top:
    inc  edx
    mov  [r11 + rcx], dl
    xor  r8d, r8d
.sy:
    imul eax, r8d, WPLANE
    add  eax, ecx
    xor  r9d, r9d
    cmp  r8d, edx
    jl   .dark
    mov  r9d, 15
.dark:
    mov  [r10 + rax], r9b
    inc  r8d
    cmp  r8d, 128
    jb   .sy
    inc  ecx
    cmp  ecx, WPLANE
    jb   .col
    lea  rcx, [rel ref_sky]
    mov  edx, 1
    call relax
    lea  rcx, [rel ref_blk]
    xor  edx, edx
    call relax
ENDP

PROC engine_light_ptr, 0
    add  ecx, [rel lt_x0]
    add  r8d, [rel lt_x0]
    call cell_ptr
    add  rax, LIGHT_OFS
ENDP

PROC report_mismatch, 0
    mov  ebx, edx
    mov  esi, r8d
    mov  edi, r9d
    mov  r12, rcx
    call fb_reset
    mov  rcx, r12
    call fb_str
    movsxd rcx, ebx
    call fb_int
    lea  rcx, [rel s_cells]
    call fb_str
    ; first bad cell index -> world x, y, z
    mov  eax, esi
    xor  edx, edx
    mov  ecx, WPLANE
    div  ecx
    mov  r13d, eax
    mov  eax, edx
    xor  edx, edx
    mov  ecx, WS
    div  ecx
    mov  r14d, eax
    mov  r15d, edx
    movsxd rcx, r15d
    movsxd rax, dword [rel lt_x0]
    add  rcx, rax
    call fb_int
    cmp  dword ARG6, 0
    jne  .noy
    lea  rcx, [rel s_y]
    call fb_str
    movsxd rcx, r13d
    call fb_int
.noy:
    lea  rcx, [rel s_z]
    call fb_str
    movsxd rcx, r14d
    movsxd rax, dword [rel lt_x0]
    add  rcx, rax
    call fb_int
    lea  rcx, [rel s_got]
    call fb_str
    movsxd rcx, edi
    call fb_int
    lea  rcx, [rel s_want]
    call fb_str
    movsxd rcx, dword ARG5
    call fb_int
    lea  rcx, [rel lt_fb]
    call t_fail_detail
ENDP

; one check: hm + sky + blk of all 9 chunks match the reference and the queue never
; overflowed. eax 1 = passed
PROC lt_check_ref, 64
    mov  LOC(0), rcx
    mov  LOC(8), rdx
    mov  LOC(16), r8d
    call ref_solve
    xor  r12d, r12d
    mov  r13d, -1
    xor  ebx, ebx
.hm:
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, WS
    div  ecx
    mov  esi, eax
    mov  edi, edx
    mov  ecx, edi
    add  ecx, [rel lt_x0]
    mov  edx, esi
    add  edx, [rel lt_x0]
    call lt_hm
    lea  rcx, [rel ref_hm]
    movzx edx, byte [rcx + rbx]
    cmp  eax, edx
    je   .hm_ok
    inc  r12d
    cmp  r13d, -1
    jne  .hm_ok
    mov  r13d, ebx
    mov  LOC(24), eax
    mov  LOC(28), edx
.hm_ok:
    inc  ebx
    cmp  ebx, WPLANE
    jb   .hm
    mov  LOC(32), r12d  ; hm mismatches
    mov  LOC(56), r13d  ; first bad column
.light:
    xor  r12d, r12d  ; sky mismatches
    mov  r13d, -1
    xor  r14d, r14d  ; blk mismatches
    mov  r15d, -1
    xor  ebx, ebx
.cells:
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, WPLANE
    div  ecx
    mov  esi, eax
    mov  eax, edx
    xor  edx, edx
    mov  ecx, WS
    div  ecx
    mov  ecx, edx
    mov  edx, esi
    mov  r8d, eax
    call engine_light_ptr
    movzx eax, byte [rax]
    mov  edi, eax
    shr  edi, 4
    and  eax, 15
    lea  rcx, [rel ref_sky]
    movzx ecx, byte [rcx + rbx]
    cmp  edi, ecx
    je   .sky_ok
    inc  r12d
    cmp  r13d, -1
    jne  .sky_ok
    mov  r13d, ebx
    mov  LOC(40), edi
    mov  LOC(44), ecx
.sky_ok:
    lea  rcx, [rel ref_blk]
    movzx ecx, byte [rcx + rbx]
    cmp  eax, ecx
    je   .blk_ok
    inc  r14d
    cmp  r15d, -1
    jne  .blk_ok
    mov  r15d, ebx
    mov  LOC(48), eax
    mov  LOC(52), ecx
.blk_ok:
    inc  ebx
    cmp  ebx, WCELLS
    jb   .cells
    mov  eax, LOC(32)
    or   eax, r12d
    or   eax, r14d
    or   eax, [rel light_stat_overflow]
    jnz  .fail
    call t_pass
    mov  eax, 1
    jmp  .ret
.fail:
    mov  rcx, LOC(0)
    mov  rdx, LOC(8)
    mov  r8d, LOC(16)
    call t_fail
    cmp  dword LOC(32), 0
    je   .d_sky
    ; a column index z*48+x is also the cell index of (x, 0, z)
    lea  rcx, [rel s_hm]
    mov  edx, LOC(32)
    mov  r8d, LOC(56)
    mov  r9d, LOC(24)
    mov  eax, LOC(28)
    mov  [rsp+32], rax
    mov  qword [rsp+40], 1
    call report_mismatch
.d_sky:
    test r12d, r12d
    jz   .d_blk
    lea  rcx, [rel s_sky]
    mov  edx, r12d
    mov  r8d, r13d
    mov  r9d, LOC(40)
    mov  eax, LOC(44)
    mov  [rsp+32], rax
    mov  qword [rsp+40], 0
    call report_mismatch
.d_blk:
    test r14d, r14d
    jz   .d_ovf
    lea  rcx, [rel s_blk]
    mov  edx, r14d
    mov  r8d, r15d
    mov  r9d, LOC(48)
    mov  eax, LOC(52)
    mov  [rsp+32], rax
    mov  qword [rsp+40], 0
    call report_mismatch
.d_ovf:
    cmp  dword [rel light_stat_overflow], 0
    je   .done
    call fb_reset
    lea  rcx, [rel s_ovf]
    call fb_str
    mov  ecx, [rel light_stat_overflow]
    call fb_int
    lea  rcx, [rel lt_fb]
    call t_fail_detail
.done:
    xor  eax, eax
.ret:
ENDP

PROC lt_probe, 160
    mov  dword [rel fw_misaligned], 0
    mov  rax, ARG5
    mov  [rsp+32], rax
    call abi_probe
    mov  ebx, eax
    mov  esi, [rel fw_misaligned]
    mov  eax, ebx
    or   eax, esi
    jnz  .fail
    call t_pass
    jmp  .done
.fail:
    mov  rcx, ARG6
    mov  rdx, ARG7
    mov  r8d, ARG8
    call t_fail
    test ebx, ebx
    jz   .mis
    call fb_reset
    lea  rcx, [rel s_clob]
    call fb_str
    mov  ecx, ebx
    lea  rdx, LOC(0)
    call t_abi_mask_name
    lea  rcx, LOC(0)
    call fb_str
    lea  rcx, [rel lt_fb]
    call t_fail_detail
.mis:
    test esi, esi
    jz   .done
    call fb_reset
    lea  rcx, [rel s_mis]
    call fb_str
    mov  ecx, esi
    call fb_int
    lea  rcx, [rel lt_fb]
    call t_fail_detail
.done:
ENDP

PROC lt_print_edit, 0
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12d, r9d
    call fb_reset
    lea  rcx, [rel s_edit]
    call fb_str
    movsxd rcx, ebx
    call fb_int
    lea  rcx, [rel s_at]
    call fb_str
    movsxd rcx, esi
    call fb_int
    lea  rcx, [rel s_comma]
    call fb_str
    movsxd rcx, edi
    call fb_int
    lea  rcx, [rel s_comma]
    call fb_str
    movsxd rcx, r12d
    call fb_int
    lea  rcx, [rel s_arrow]
    call fb_str
    movsxd rcx, dword ARG5
    call fb_int
    lea  rcx, [rel lt_fb]
    call t_fail_detail
ENDP
