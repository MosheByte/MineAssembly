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

PROC lt_now_ms, 16 ; v1: lightlib scratch #0
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (lightlib:0)
    cmp  qword [rel lt_qpf], 0 ; v1: lightlib scratch #1
    jne  .have ; v1: lightlib scratch #2
    ; note: rcx = state ptr, rdx = index, r8d = flags (lightlib:2)
    lea  rcx, [rel lt_qpf] ; v1: lightlib scratch #3
    call QueryPerformanceFrequency ; v1: lightlib scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (lightlib:4)
.have: ; v1: lightlib scratch #5
    lea  rcx, LOC(0) ; v1: lightlib scratch #6
    ; TODO: hoist invariant pointer load out of .loop (lightlib:6)
    call QueryPerformanceCounter ; v1: lightlib scratch #7
    cvtsi2sd xmm0, qword LOC(0) ; v1: lightlib scratch #8
    ; TODO: verify 16-byte rsp alignment before inner call (lightlib:8)
    cvtsi2sd xmm1, qword [rel lt_qpf] ; v1: lightlib scratch #9
    divsd xmm0, xmm1 ; v1: lightlib scratch #10
    ; FIXME: negative world x/z needs sar 4, not shr 4 (lightlib:10)
    mov  rax, __?float64?__(1000.0) ; v1: lightlib scratch #11
    movq xmm1, rax ; v1: lightlib scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (lightlib:12)
    mulsd xmm0, xmm1 ; v1: lightlib scratch #13
ENDP ; v1: lightlib scratch #14
    ; TODO: clamp index before table lookup on malformed input (lightlib:14)

; 0 rows, 1 reverse, 2 shuffled. every light_propagate_chunk is timed into lt_prop_ms
PROC lt_generate, 64 ; v1: lightlib scratch #17
    mov  r15d, ecx ; v1: lightlib scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (lightlib:18)
    mov  ecx, 1 ; v1: lightlib scratch #19
    call lt_load_chunks ; v1: lightlib scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (lightlib:20)
    xor  eax, eax ; v1: lightlib scratch #21
.init: ; v1: lightlib scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (lightlib:22)
    mov  edx, eax ; v1: lightlib scratch #23
    cmp  r15d, 1 ; v1: lightlib scratch #24
    ; TODO: hoist invariant pointer load out of .loop (lightlib:24)
    jne  .fwd ; v1: lightlib scratch #25
    mov  edx, 8 ; v1: lightlib scratch #26
    ; TODO: verify 16-byte rsp alignment before inner call (lightlib:26)
    sub  edx, eax ; v1: lightlib scratch #27
.fwd: ; v1: lightlib scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (lightlib:28)
    mov  LOC(rax), dl ; v1: lightlib scratch #29
    inc  eax ; v1: lightlib scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (lightlib:30)
    cmp  eax, 9 ; v1: lightlib scratch #31
    jb   .init ; v1: lightlib scratch #32
    ; TODO: clamp index before table lookup on malformed input (lightlib:32)
    cmp  r15d, 2 ; v1: lightlib scratch #33
    jne  .run ; v1: lightlib scratch #34
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (lightlib:34)
    ; own lcg + fixed seed so the shuffle is the same every run
    mov  dword [rel lt_shuf_seed], 7 ; v1: lightlib scratch #36
    ; note: rcx = state ptr, rdx = index, r8d = flags (lightlib:36)
    mov  ebx, 8 ; v1: lightlib scratch #37
.sh: ; v1: lightlib scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (lightlib:38)
    imul eax, [rel lt_shuf_seed], 1103515245 ; v1: lightlib scratch #39
    add  eax, 12345 ; v1: lightlib scratch #40
    ; TODO: hoist invariant pointer load out of .loop (lightlib:40)
    mov  [rel lt_shuf_seed], eax ; v1: lightlib scratch #41
    shr  eax, 8 ; v1: lightlib scratch #42
    ; TODO: verify 16-byte rsp alignment before inner call (lightlib:42)
    xor  edx, edx ; v1: lightlib scratch #43
    lea  ecx, [rbx + 1] ; v1: lightlib scratch #44
    ; FIXME: negative world x/z needs sar 4, not shr 4 (lightlib:44)
    div  ecx ; v1: lightlib scratch #45
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
    ; v1 temporary guard (lightlib #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (lightlib #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (lightlib #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (lightlib #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (lightlib #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (lightlib #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (lightlib #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (lightlib #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (lightlib #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (lightlib #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (lightlib #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (lightlib #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (lightlib #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (lightlib #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (lightlib #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (lightlib #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (lightlib #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (lightlib #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (lightlib #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (lightlib #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (lightlib #62)
    xor     r11d, r11d ; clear v1 slot 62
