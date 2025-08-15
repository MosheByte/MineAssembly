; texgen.asm - the texture atlas, painted procedurally at startup. no image files
; 256x256, 16x16 tiles of 16px. everything has to tile or walls show the block grid
; mips: tiles are 16-aligned so a 2x2 box never mixes two tiles until 1x1
%define IMPL_TEXGEN
%include "common.inc"

global texgen_build_cpu
global texgen_animate_cpu
global texgen_build_clouds_cpu
; texgen_mip_down is exported down next to mip_down

%define RGB(r,g,b)     (0xFF000000 | ((b) << 16) | ((g) << 8) | (r))
%define RGBA(r,g,b,a)  ((((a) & 255) << 24) | ((b) << 16) | ((g) << 8) | (r))
%define SH(sx,sy)      ((sx) | ((sy) << 8))  ; log2 cell size

; PROC but the label stays local
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

; one sprite row, nasm errors out if it isn't 16 chars
%macro SROW 1
    %strlen %%l %1
    %if %%l != 16
        %error "sprite row must be exactly 16 characters"
    %endif
    db %1
%endmacro

; tile, painter, param (note the order in memory)
%macro TILE 3
    dq %2, %3
    dd %1, 0
%endmacro

%define NB_BASE    0
%define NB_BASE2   4
%define NB_AMP     8
%define NB_SHIFT   12
%define NB_SEED    16
%define NB_SPECK   20
%define NB_SDELTA  24
%define NB_MIXSH   28
%macro NB 8         ; base, base2, amp, shift, seed, speck, sdelta, mixshift
    dd %1, %2, %3, %4, %5, %6, %7, %8
%endmacro

%define ATLAS_BYTES (256*256*4)
%define CLOUD_THRESHOLD 146         ; fbm value where clouds start, lower = more cloud

section .bss
alignb 16
s_atlas     resq 1
s_tp        resq 1
s_rng       resd 1  ; xorshift32, reseeded per tile
s_period    resd 1  ; 16, or 256 while doing clouds
s_seed      resd 1
s_tmpi      resd 1
s_vn        resd 1
s_vd1       resd 1  ; F1
s_vd2       resd 1  ; F2
s_vdx       resd 1
s_vdy       resd 1
s_cdx       resd 1
s_cdy       resd 1
s_ncrack    resd 1
alignb 16
s_vx        resd 64
s_vy        resd 64
s_mask      resb 256
s_crackx    resb 256
s_cracky    resb 256
s_branch    resd 6*4
alignb 16
s_sin       resd 256  ; sin*256
s_tilecol   resd 256
s_t16       resb 16*16*4
s_tmips     resb (8*8 + 4*4 + 2*2 + 1)*4
alignb 16
s_mip       resb (128*128 + 64*64 + 32*32 + 16*16)*4
s_cloud     resb 256*256*4
s_fallback  resb ATLAS_BYTES  ; if mem_alloc fails

section .rdata
align 16
c_half      dd 0.5
c_7_5       dd 7.5
c_big       dd 1.0e9
c_8         dd 8.0
c_m8        dd -8.0
c_16        dd 16.0
c_0_9       dd 0.9
c_0_7       dd 0.7
c_0_15      dd 0.15
c_1_8       dd 1.8
c_m5        dd -5.0
c_m8f       dd -8.0
c_inv24     dd 5.9604645e-8  ; 1/2^24
align 8
c_2pi_256   dq 0.02454369260617026
c_256d      dq 256.0

dir8        db 1,0, 1,1, 0,1, -1,1, -1,0, -1,-1, 0,-1, 1,-1

section .text

; eax = hash(ecx, edx, r8d), only trashes ecx/edx. murmur-ish, plenty for textures
hash32:
    imul    eax, r8d, 0x61C88647
    imul    ecx, ecx, 0x27D4EB2D
    xor     eax, ecx
    rol     eax, 13
    imul    edx, edx, 0x165667B1
    xor     eax, edx
    mov     ecx, eax
    shr     ecx, 15
    xor     eax, ecx
    imul    eax, eax, 0x2C1B3C6D
    mov     ecx, eax
    shr     ecx, 12
    xor     eax, ecx
    imul    eax, eax, 0x297A2D39
    mov     ecx, eax
    shr     ecx, 15
    xor     eax, ecx
    ret

rng_set:
    mov     edx, 0x2545
    mov     r8d, 0xF491
    call    hash32
    or      eax, 1
    mov     [rel s_rng], eax
    ret

; xorshift32, trashes ecx
rnd:
    mov     eax, [rel s_rng]
    mov     ecx, eax
    shl     ecx, 13
    xor     eax, ecx
    mov     ecx, eax
    shr     ecx, 17
    xor     eax, ecx
    mov     ecx, eax
    shl     ecx, 5
    xor     eax, ecx
    mov     [rel s_rng], eax
    ret

; [0, ecx), trashes ecx edx r8
rndn:
    mov     r8d, ecx
    call    rnd
    mul     r8d
    mov     eax, edx
    ret

; value noise. x/y are 8.8 fixed px, r8d = SH(sx,sy), lattice wraps every s_period px
LPROC vnoise, 32
    mov     r12d, r9d
    mov     r10d, ecx
    mov     r11d, edx
    movzx   ecx, r8b
    mov     r13d, r8d
    shr     r13d, 8
    and     r13d, 255
    mov     eax, r10d
    sar     eax, cl
    mov     edx, eax
    and     edx, 255
    mov     LOC(0), edx
    sar     eax, 8
    mov     edx, [rel s_period]
    shr     edx, cl
    dec     edx                         ; period mask
    mov     ebx, eax
    and     ebx, edx
    lea     esi, [rax+1]
    and     esi, edx
    mov     ecx, r13d
    mov     eax, r11d
    sar     eax, cl
    mov     edx, eax
    and     edx, 255
    mov     LOC(4), edx
    sar     eax, 8
    mov     edx, [rel s_period]
    shr     edx, cl
    dec     edx
    mov     edi, eax
    and     edi, edx
    lea     r14d, [rax+1]
    and     r14d, edx
    mov     ecx, ebx
    mov     edx, edi
    mov     r8d, r12d
    call    hash32
    and     eax, 255
    mov     LOC(8), eax
    mov     ecx, esi
    mov     edx, edi
    mov     r8d, r12d
    call    hash32
    and     eax, 255
    mov     LOC(12), eax
    mov     ecx, ebx
    mov     edx, r14d
    mov     r8d, r12d
    call    hash32
    and     eax, 255
    mov     LOC(16), eax
    mov     ecx, esi
    mov     edx, r14d
    mov     r8d, r12d
    call    hash32
    and     eax, 255
    mov     LOC(20), eax
    ; w = f*f*(768-2f) >> 16, smoothstep in 8 bit fixed
    mov     eax, LOC(0)
    mov     ecx, eax
    imul    ecx, eax
    mov     edx, 768
    sub     edx, eax
    sub     edx, eax
    imul    ecx, edx
    shr     ecx, 16
    mov     r15d, ecx
    mov     eax, LOC(4)
    mov     ecx, eax
    imul    ecx, eax
    mov     edx, 768
    sub     edx, eax
    sub     edx, eax
    imul    ecx, edx
    shr     ecx, 16
    mov     r13d, ecx
    mov     eax, LOC(12)
    sub     eax, LOC(8)
    imul    eax, r15d
    sar     eax, 8
    add     eax, LOC(8)
    mov     ebx, eax
    mov     eax, LOC(20)
    sub     eax, LOC(16)
    imul    eax, r15d
    sar     eax, 8
    add     eax, LOC(16)
    sub     eax, ebx
    imul    eax, r13d
    sar     eax, 8
    add     eax, ebx
ENDP

; 4 octaves, weights 8,4,2,1, normalised by what actually got used
LPROC fbm, 16
    mov     ebx, ecx
    mov     esi, edx
    movzx   edi, r8b
    mov     r12d, r8d
    shr     r12d, 8
    and     r12d, 255
    mov     r13d, r9d
    xor     r14d, r14d
    xor     r15d, r15d
    mov     dword LOC(0), 8
.oct:
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, r12d
    shl     r8d, 8
    or      r8d, edi
    mov     r9d, r13d
    call    vnoise
    imul    eax, LOC(0)
    add     r14d, eax
    add     r15d, LOC(0)
    mov     eax, edi
    or      eax, r12d
    jz      .fin  ; 1px cells, done
    test    edi, edi
    jz      .a
    dec     edi
.a: test    r12d, r12d
    jz      .b
    dec     r12d
.b: add     r13d, 0x9E37
    shr     dword LOC(0), 1
    jnz     .oct
.fin:
    mov     eax, r14d
    xor     edx, edx
    div     r15d
ENDP

; colours are packed 0xAABBGGRR. leaf funcs, volatile regs only
col_add:
    movd    xmm0, ecx
    mov     eax, edx
    test    eax, eax
    js      .neg
    cmp     eax, 255
    jbe     .p1
    mov     eax, 255
.p1:
    imul    eax, eax, 0x010101
    movd    xmm1, eax
    paddusb xmm0, xmm1
    movd    eax, xmm0
    ret
.neg:
    neg     eax
    cmp     eax, 255
    jbe     .n1
    mov     eax, 255
.n1:
    imul    eax, eax, 0x010101
    movd    xmm1, eax
    psubusb xmm0, xmm1
    movd    eax, xmm0
    ret

; rgb * f/256, alpha untouched
col_mul:
    movd      xmm0, ecx
    pxor      xmm2, xmm2
    punpcklbw xmm0, xmm2
    psllw     xmm0, 8
    and       edx, 0xFFFF
    movd      xmm1, edx
    pshuflw   xmm1, xmm1, 0
    mov       eax, 256
    pinsrw    xmm1, eax, 3
    pmulhuw   xmm0, xmm1
    packuswb  xmm0, xmm0
    movd      eax, xmm0
    ret

col_mix:
    test      r8d, r8d
    jns       .c1
    xor       r8d, r8d
.c1:
    cmp       r8d, 256
    jbe       .c2
    mov       r8d, 256
.c2:
    movd      xmm0, ecx
    movd      xmm1, edx
    pxor      xmm5, xmm5
    punpcklbw xmm0, xmm5
    punpcklbw xmm1, xmm5
    mov       eax, 256
    sub       eax, r8d
    movd      xmm2, eax
    pshuflw   xmm2, xmm2, 0
    movd      xmm3, r8d
    pshuflw   xmm3, xmm3, 0
    pmullw    xmm0, xmm2
    pmullw    xmm1, xmm3
    paddw     xmm0, xmm1
    psrlw     xmm0, 8
    packuswb  xmm0, xmm0
    movd      eax, xmm0
    ret

; 5 stop piecewise linear, edx 0..255
ramp:
    test    edx, edx
    jns     .r1
    xor     edx, edx
.r1:
    cmp     edx, 255
    jbe     .r2
    mov     edx, 255
.r2:
    mov     r9, rcx
    mov     eax, edx
    shr     eax, 6
    and     edx, 63
    shl     edx, 2
    mov     r8d, edx
    mov     ecx, [r9+rax*4]
    mov     edx, [r9+rax*4+4]
    jmp     col_mix

; coords wrap (& 15) on purpose, so you can draw across the edge and it still tiles
; trashes ecx, edx
paddr:
    and     ecx, 15
    and     edx, 15
    shl     edx, 8
    add     edx, ecx
    mov     rax, [rel s_tp]
    lea     rax, [rax+rdx*4]
    ret

pset:
    call    paddr
    mov     [rax], r8d
    ret

pget:
    call    paddr
    mov     eax, [rax]
    ret

pshade:
    call    paddr
    mov     r10, rax
    mov     ecx, [r10]
    mov     edx, r8d
    call    col_add
    mov     [r10], eax
    ret

; src over dst
pblend:
    call    paddr
    mov     r10, rax
    mov     r9d, r8d
    shr     r9d, 24
    jz      .done
    cmp     r9d, 255
    je      .opaque
    mov     r11d, [r10]
    test    r11d, 0xFF000000
    jz      .opaque  ; dst empty, just store
    mov     ecx, r11d
    mov     edx, r8d
    mov     eax, r9d
    shr     eax, 7
    add     eax, r9d
    mov     r8d, eax
    call    col_mix
    mov     ecx, r11d
    shr     ecx, 24
    mov     edx, 255
    sub     edx, r9d
    imul    ecx, edx
    imul    ecx, ecx, 257
    add     ecx, 257
    shr     ecx, 16  ; da*(255-a)/255
    add     ecx, r9d
    cmp     ecx, 255
    jbe     .a_ok
    mov     ecx, 255
.a_ok:
    and     eax, 0x00FFFFFF
    shl     ecx, 24
    or      eax, ecx
    mov     [r10], eax
.done:
    ret
.opaque:
    mov     [r10], r8d
    ret

tile_sel:
    mov     eax, ecx
    and     eax, 255
    shr     eax, 4
    shl     eax, 12  ; 16 rows * 256 px per tile row
    and     ecx, 15
    shl     ecx, 4
    add     eax, ecx
    mov     rdx, [rel s_atlas]
    lea     rax, [rdx+rax*4]
    mov     [rel s_tp], rax
    ret

cdist:
    cvtsi2ss xmm0, ecx
    subss   xmm0, [rel c_7_5]
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, edx
    subss   xmm1, [rel c_7_5]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    ret

; max(|2x-15|, |2y-15|), 15 = border. also leaves r8d/r9d = the two abs values
cheb:
    lea     eax, [rcx*2-15]
    mov     r8d, eax
    neg     r8d
    cmovs   r8d, eax
    lea     eax, [rdx*2-15]
    mov     r9d, eax
    neg     r9d
    cmovs   r9d, eax
    mov     eax, r8d
    cmp     eax, r9d
    cmovb   eax, r9d
    ret

; shader(ecx x, edx y, r8 param, r9d old) -> eax, run on every pixel of the tile
LPROC tile_shade
    mov     r12, rcx
    mov     r13, rdx
    xor     esi, esi
.y: xor     ebx, ebx
.x: mov     rdi, [rel s_tp]
    mov     eax, esi
    shl     eax, 8
    add     eax, ebx
    lea     rdi, [rdi+rax*4]
    mov     ecx, ebx
    mov     edx, esi
    mov     r8, r13
    mov     r9d, [rdi]
    call    r12
    mov     [rdi], eax
    inc     ebx
    cmp     ebx, 16
    jb      .x
    inc     esi
    cmp     esi, 16
    jb      .y
ENDP

tile_fill:
    mov     rax, [rel s_tp]
    xor     edx, edx
.row:
    mov     r8d, 16
    mov     r9, rax
.px:
    mov     [r9], ecx
    add     r9, 4
    dec     r8d
    jnz     .px
    add     rax, 1024
    inc     edx
    cmp     edx, 16
    jb      .row
    ret

; water/ice get looked at over huge areas at grazing angles. if row or column means differ
; even a bit, filtering turns that into stripes with exactly one block period = a grid toward
; the horizon. so add (mean-rowmean)+(mean-colmean) everywhere, only the noise is left.
; depends only on tile contents, anim loops stay exact
LPROC tile_flatten, 128
    lea     rdi, [rsp+FRAME_OUT]  ; [0..15] row sums, [16..31] col sums
    xor     eax, eax
    mov     ecx, 32
.z: mov     [rdi+rcx*4-4], eax
    dec     ecx
    jnz     .z
    mov     r13, [rel s_tp]
    xor     r12d, r12d
    xor     esi, esi
.y1:
    xor     ebx, ebx
.x1:
    mov     eax, esi
    shl     eax, 8
    add     eax, ebx
    mov     eax, [r13+rax*4]
    movzx   ecx, al
    movzx   edx, ah
    lea     ecx, [rcx+rdx*2]
    shr     eax, 16
    movzx   eax, al
    add     ecx, eax  ; 4*l = r + 2g + b
    add     [rdi+rsi*4], ecx
    add     [rdi+rbx*4+64], ecx
    add     r12d, ecx
    inc     ebx
    cmp     ebx, 16
    jb      .x1
    inc     esi
    cmp     esi, 16
    jb      .y1
    ; delta = (2*total - 16*(rowsum+colsum)) / 1024, rounded
    xor     esi, esi
.y2:
    xor     ebx, ebx
.x2:
    lea     edx, [r12+r12]
    mov     eax, [rdi+rsi*4]
    add     eax, [rdi+rbx*4+64]
    shl     eax, 4
    sub     edx, eax
    add     edx, 512
    sar     edx, 10
    mov     eax, esi
    shl     eax, 8
    add     eax, ebx
    lea     r14, [r13+rax*4]
    mov     ecx, [r14]
    call    col_add
    mov     [r14], eax
    inc     ebx
    cmp     ebx, 16
    jb      .x2
    inc     esi
    cmp     esi, 16
    jb      .y2
ENDP

snapshot_mask:
    mov     rax, [rel s_tp]
    lea     r9, [rel s_mask]
    xor     edx, edx
.row:
    xor     ecx, ecx
.px:
    mov     r8d, edx
    shl     r8d, 8
    add     r8d, ecx
    mov     r10d, [rax+r8*4]
    shr     r10d, 24
    setnz   r10b
    mov     r8d, edx
    shl     r8d, 4
    add     r8d, ecx
    mov     [r9+r8], r10b
    inc     ecx
    cmp     ecx, 16
    jb      .px
    inc     edx
    cmp     edx, 16
    jb      .row
    ret

; '.' skips, '0'..'9' 'a'..'f' index the palette
LPROC blit_map
    mov     r12, rcx
    mov     r13, rdx
    xor     ebx, ebx
.px:
    movzx   eax, byte [r12+rbx]
    cmp     al, '.'
    je      .next
    sub     eax, '0'
    cmp     eax, 9
    jbe     .idx
    sub     eax, 'a' - '0' - 10
.idx:
    mov     r8d, [r13+rax*4]
    mov     ecx, ebx
    and     ecx, 15
    mov     edx, ebx
    shr     edx, 4
    call    pset
.next:
    inc     ebx
    cmp     ebx, 256
    jb      .px
ENDP

; transparent px next to an opaque one gets neighbour * factor/256. outline follows the
; icon colour instead of being flat black
LPROC outline_pass
    mov     r15d, ecx
    call    snapshot_mask
    lea     r12, [rel s_mask]
    xor     esi, esi
.y: xor     ebx, ebx
.x: mov     eax, esi
    shl     eax, 4
    add     eax, ebx
    cmp     byte [r12+rax], 0
    jne     .next
    mov     ecx, ebx
    mov     edx, esi
    test    ebx, ebx
    jz      .r
    cmp     byte [r12+rax-1], 0
    je      .r
    dec     ecx
    jmp     .hit
.r: cmp     ebx, 15
    je      .u
    cmp     byte [r12+rax+1], 0
    je      .u
    inc     ecx
    jmp     .hit
.u: test    esi, esi
    jz      .d
    cmp     byte [r12+rax-16], 0
    je      .d
    dec     edx
    jmp     .hit
.d: cmp     esi, 15
    je      .next
    cmp     byte [r12+rax+16], 0
    je      .next
    inc     edx
.hit:
    call    pget
    mov     ecx, eax
    mov     edx, r15d
    call    col_mul
    or      eax, 0xFF000000
    mov     r8d, eax
    mov     ecx, ebx
    mov     edx, esi
    call    pset
.next:
    inc     ebx
    cmp     ebx, 16
    jb      .x
    inc     esi
    cmp     esi, 16
    jb      .y
ENDP

; leaves: hole above/left -> lit, below/right -> shadow. hacky but the clumps look 3D
LPROC edge_light
    mov     r14d, ecx
    mov     r15d, edx
    call    snapshot_mask
    lea     r12, [rel s_mask]
    xor     esi, esi
.y: xor     ebx, ebx
.x: mov     eax, esi
    shl     eax, 4
    add     eax, ebx
    cmp     byte [r12+rax], 0
    je      .next
    lea     ecx, [rbx-1]
    and     ecx, 15
    mov     edx, esi
    shl     edx, 4
    add     edx, ecx
    cmp     byte [r12+rdx], 0
    je      .lit
    lea     edx, [rsi-1]
    and     edx, 15
    shl     edx, 4
    add     edx, ebx
    cmp     byte [r12+rdx], 0
    je      .lit
    lea     ecx, [rbx+1]
    and     ecx, 15
    mov     edx, esi
    shl     edx, 4
    add     edx, ecx
    cmp     byte [r12+rdx], 0
    je      .shadow
    lea     edx, [rsi+1]
    and     edx, 15
    shl     edx, 4
    add     edx, ebx
    cmp     byte [r12+rdx], 0
    je      .shadow
    jmp     .next
.lit:
    mov     r8d, r14d
    jmp     .apply
.shadow:
    mov     r8d, r15d
.apply:
    mov     ecx, ebx
    mov     edx, esi
    call    pshade
.next:
    inc     ebx
    cmp     ebx, 16
    jb      .x
    inc     esi
    cmp     esi, 16
    jb      .y
ENDP

; bresenham, blended. colour is the 5th arg
LPROC pline, 16
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    mov     r13d, r9d
    mov     eax, r12d
    sub     eax, ebx
    mov     edi, 1
    jns     .sx
    neg     eax
    neg     edi
.sx:
    mov     r14d, eax
    mov     LOC(0), edi
    mov     eax, r13d
    sub     eax, esi
    mov     edi, 1
    jns     .sy
    neg     eax
    neg     edi
.sy:
    neg     eax
    mov     r15d, eax  ; dy is negative
    mov     LOC(4), edi
    mov     edi, r14d
    add     edi, r15d
.loop:
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, ARG5
    call    pblend
    cmp     ebx, r12d
    jne     .step
    cmp     esi, r13d
    je      .done
.step:
    lea     eax, [rdi+rdi]
    cmp     eax, r15d
    jl      .noy
    add     edi, r15d
    add     ebx, LOC(0)
.noy:
    cmp     eax, r14d
    jg      .loop
    add     edi, r14d
    add     esi, LOC(4)
    jmp     .loop
.done:
ENDP

LPROC prect
    mov     r12d, ecx
    mov     r13d, edx
    mov     r14d, r8d
    mov     r15d, r9d
    xor     esi, esi
.y: xor     ebx, ebx
.x: lea     ecx, [r12+rbx]
    lea     edx, [r13+rsi]
    mov     r8d, ARG5
    call    pset
    inc     ebx
    cmp     ebx, r14d
    jb      .x
    inc     esi
    cmp     esi, r15d
    jb      .y
ENDP

; cracks: random walk of shaded px, turns +-45 deg now and then
LPROC crack_walk
    mov     ebx, ecx
    mov     esi, edx
    mov     edi, r8d
    mov     r12d, r9d
    mov     ecx, 8
    call    rndn
    mov     r13d, eax
.loop:
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, r12d
    call    pshade
    lea     rax, [rel dir8]
    movsx   ecx, byte [rax+r13*2]
    add     ebx, ecx
    movsx   ecx, byte [rax+r13*2+1]
    add     esi, ecx
    mov     ecx, 5
    call    rndn
    cmp     eax, 0
    jne     .t2
    inc     r13d
.t2:
    cmp     eax, 1
    jne     .t3
    dec     r13d
.t3:
    and     r13d, 7
    dec     edi
    jnz     .loop
ENDP

; voronoi on the 16x16 torus, one jittered point per grid cell
; vor_query -> eax nearest, s_vd1/s_vd2 = F1/F2, s_vdx/s_vdy = px - nearest. leaf, sse
LPROC vor_setup, 16
    mov     r12d, ecx
    mov     eax, r12d
    imul    eax, r12d
    mov     [rel s_vn], eax
    cvtsi2ss xmm0, r12d
    movss   xmm1, [rel c_16]
    divss   xmm1, xmm0
    movss   LOC(0), xmm1
    xor     esi, esi
    xor     edi, edi
.j: xor     ebx, ebx
.i: call    rnd
    shr     eax, 8
    cvtsi2ss xmm0, eax
    mulss   xmm0, [rel c_inv24]
    mulss   xmm0, [rel c_0_7]
    addss   xmm0, [rel c_0_15]
    cvtsi2ss xmm1, ebx
    addss   xmm0, xmm1
    mulss   xmm0, LOC(0)
    lea     rax, [rel s_vx]
    movss   [rax+rdi*4], xmm0
    call    rnd
    shr     eax, 8
    cvtsi2ss xmm0, eax
    mulss   xmm0, [rel c_inv24]
    mulss   xmm0, [rel c_0_7]
    addss   xmm0, [rel c_0_15]
    cvtsi2ss xmm1, esi
    addss   xmm0, xmm1
    mulss   xmm0, LOC(0)
    lea     rax, [rel s_vy]
    movss   [rax+rdi*4], xmm0
    inc     edi
    inc     ebx
    cmp     ebx, r12d
    jb      .i
    inc     esi
    cmp     esi, r12d
    jb      .j
ENDP

vor_query:
    cvtsi2ss xmm0, ecx
    addss   xmm0, [rel c_half]
    cvtsi2ss xmm1, edx
    addss   xmm1, [rel c_half]
    movss   xmm4, [rel c_big]  ; squared
    movss   xmm5, [rel c_big]
    xor     eax, eax
    xor     r8d, r8d
    mov     r9d, [rel s_vn]
    lea     r10, [rel s_vx]
    lea     r11, [rel s_vy]
.loop:
    movss   xmm2, xmm0
    subss   xmm2, [r10+r8*4]
    comiss  xmm2, [rel c_8]
    jbe     .a
    subss   xmm2, [rel c_16]
.a: comiss  xmm2, [rel c_m8]
    jae     .b
    addss   xmm2, [rel c_16]
.b: movss   xmm3, xmm1
    subss   xmm3, [r11+r8*4]
    comiss  xmm3, [rel c_8]
    jbe     .c
    subss   xmm3, [rel c_16]
.c: comiss  xmm3, [rel c_m8]
    jae     .d
    addss   xmm3, [rel c_16]
.d: movss   [rel s_cdx], xmm2
    movss   [rel s_cdy], xmm3
    mulss   xmm2, xmm2
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    comiss  xmm2, xmm4
    jae     .notbest
    movss   xmm5, xmm4
    movss   xmm4, xmm2
    mov     eax, r8d
    mov     ecx, [rel s_cdx]
    mov     [rel s_vdx], ecx
    mov     ecx, [rel s_cdy]
    mov     [rel s_vdy], ecx
    jmp     .next
.notbest:
    comiss  xmm2, xmm5
    jae     .next
    movss   xmm5, xmm2
.next:
    inc     r8d
    cmp     r8d, r9d
    jb      .loop
    sqrtss  xmm4, xmm4
    sqrtss  xmm5, xmm5
    movss   [rel s_vd1], xmm4
    movss   [rel s_vd2], xmm5
    ret

; F2-F1, 0 right on a border
vor_edge:
    movss   xmm0, [rel s_vd2]
    subss   xmm0, [rel s_vd1]
    ret

; fake per-cell light
vor_shade:
    movss   xmm0, [rel s_vdx]
    addss   xmm0, [rel s_vdy]
    mulss   xmm0, xmm1
    cvtss2si eax, xmm0
    ret

LPROC sh_noise
    mov     ebx, ecx
    mov     esi, edx
    mov     r12, r8
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, [r12+NB_MIXSH]
    mov     r9d, [r12+NB_SEED]
    add     r9d, 101
    call    vnoise
    mov     r8d, eax
    mov     ecx, [r12+NB_BASE]
    mov     edx, [r12+NB_BASE2]
    call    col_mix
    mov     edi, eax
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, [r12+NB_SHIFT]
    mov     r9d, [r12+NB_SEED]
    call    fbm
    sub     eax, 128
    imul    eax, [r12+NB_AMP]
    sar     eax, 6
    mov     ecx, edi
    mov     edx, eax
    call    col_add
    mov     edi, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [r12+NB_SEED]
    add     r8d, 2
    call    hash32
    mov     r13d, eax
    movzx   eax, r13b
    cmp     eax, [r12+NB_SPECK]
    jae     .grain
    mov     ecx, edi
    mov     edx, [r12+NB_SDELTA]
    call    col_add
    jmp     .done
.grain:
    mov     eax, r13d
    shr     eax, 8
    and     eax, 15
    sub     eax, 8
    imul    eax, [r12+NB_AMP]
    sar     eax, 5
    mov     ecx, edi
    mov     edx, eax
    call    col_add
.done:
ENDP

LPROC gen_noise
    mov     rdx, rcx
    lea     rcx, [rel sh_noise]
    call    tile_shade
ENDP

LPROC gen_stone
    call    gen_noise
    mov     r12d, 3
.c: mov     ecx, 16
    call    rndn
    mov     ebx, eax
    mov     ecx, 16
    call    rndn
    mov     esi, eax
    mov     ecx, 3
    call    rndn
    lea     r8d, [rax+3]
    mov     ecx, ebx
    mov     edx, esi
    mov     r9d, -16
    call    crack_walk
    dec     r12d
    jnz     .c
ENDP

LPROC gen_ore, 16
    mov     r12, rcx
    mov     rcx, [r12]
    call    gen_stone
    mov     r13d, [r12+20]
.spot:
    mov     ecx, 13
    call    rndn
    mov     ebx, eax
    mov     ecx, 13
    call    rndn
    mov     esi, eax
    mov     ecx, 4
    call    rndn
    shl     eax, 4
    lea     rdi, [rel ore_shapes]
    add     rdi, rax
    xor     r14d, r14d
.px:
    movzx   eax, byte [rdi+r14]
    cmp     al, '.'
    je      .nx
    mov     r15d, [r12+8]
    cmp     al, 'L'
    je      .put
    mov     r15d, [r12+12]
    cmp     al, 'M'
    je      .put
    mov     r15d, [r12+16]
.put:
    mov     ecx, 13
    call    rndn
    sub     eax, 6
    mov     ecx, r15d
    mov     edx, eax
    call    col_add
    mov     r8d, eax
    mov     ecx, r14d
    and     ecx, 3
    add     ecx, ebx
    mov     edx, r14d
    shr     edx, 2
    add     edx, esi
    call    pset
.nx:
    inc     r14d
    cmp     r14d, 16
    jb      .px
    dec     r13d
    jnz     .spot
ENDP

; grey, the mesher tints it per biome
LPROC gen_grass_top
    call    gen_noise
    mov     r12d, 28
.blade:
    mov     ecx, 16
    call    rndn
    mov     ebx, eax
    mov     ecx, 16
    call    rndn
    mov     esi, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, 26
    call    pshade
    lea     edx, [rsi+1]
    mov     ecx, ebx
    mov     r8d, -18
    call    pshade
    dec     r12d
    jnz     .blade
ENDP

; per column: turf depth 2..5 from a hash, sometimes a 1-2px drip, shadow px under it
LPROC gen_grass_side, 16
    mov     r12, rcx
    mov     rcx, [r12]
    call    gen_noise
    call    rnd
    mov     r15d, eax
    xor     ebx, ebx
.col:
    mov     ecx, ebx
    xor     edx, edx
    mov     r8d, r15d
    call    hash32
    mov     r13d, eax
    mov     edi, eax
    and     edi, 3
    cmp     edi, 3
    jne     .d1
    mov     edi, 1  ; depth distribution 0,1,2,1
.d1:
    add     edi, [r12+16]
    xor     r14d, r14d
    mov     eax, r13d
    shr     eax, 4
    test    eax, 3
    jnz     .nodrip
    mov     r14d, r13d
    shr     r14d, 8
    and     r14d, 1
    inc     r14d
.nodrip:
    xor     esi, esi
.fy:
    cmp     esi, edi
    jae     .drip
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(1,1)
    mov     r9d, r15d
    call    vnoise
    mov     LOC(0), eax
    mov     ecx, ebx
    mov     edx, esi
    lea     r8d, [r15+7]
    call    hash32
    and     eax, 127
    add     eax, LOC(0)
    imul    eax, eax, 171
    shr     eax, 8
    mov     r8d, eax
    mov     ecx, [r12+12]
    mov     edx, [r12+8]
    call    col_mix
    lea     ecx, [rsi+1]
    cmp     ecx, edi
    jne     .put
    mov     ecx, eax
    mov     edx, -20
    call    col_add
.put:
    mov     r8d, eax
    mov     ecx, ebx
    mov     edx, esi
    call    pset
    inc     esi
    jmp     .fy
.drip:
    lea     eax, [rdi+r14]
    cmp     esi, eax
    jae     .shadow
    mov     ecx, [r12+12]
    mov     edx, -14
    call    col_add
    mov     r8d, eax
    mov     ecx, ebx
    mov     edx, esi
    call    pset
    inc     esi
    jmp     .drip
.shadow:
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, -18
    call    pshade
    inc     ebx
    cmp     ebx, 16
    jb      .col
ENDP

LPROC gen_cobble
    mov     r12, rcx
    mov     ecx, [r12+20]
    call    vor_setup
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_cobble]
    mov     rdx, r12
    call    tile_shade
ENDP

LPROC sh_cobble, 16
    mov     ebx, ecx
    mov     esi, edx
    mov     r12, r8
    call    vor_query
    mov     edi, eax
    call    vor_edge
    movss   LOC(0), xmm0
    comiss  xmm0, [rel c_0_9]
    jae     .stone
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 15
    sub     eax, 8
    mov     edx, eax
    mov     ecx, [r12+4]
    call    col_add
    mov     r13d, eax
    jmp     .moss
.stone:
    mov     ecx, edi
    mov     edx, 77
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 63
    sub     eax, 32
    imul    eax, [r12+8]
    sar     eax, 5
    mov     r14d, eax
    movss   xmm1, [rel c_m5]
    call    vor_shade
    add     r14d, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    add     r8d, 3
    call    hash32
    and     eax, 15
    sub     eax, 8
    add     r14d, eax
    movss   xmm0, LOC(0)
    comiss  xmm0, [rel c_1_8]
    jae     .norim
    sub     r14d, 16
.norim:
    mov     ecx, [r12]
    mov     edx, r14d
    call    col_add
    mov     r13d, eax
.moss:
    cmp     dword [r12+12], 0
    je      .done
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(2,2)
    mov     r9d, [rel s_seed]
    add     r9d, 99
    call    fbm
    movss   xmm0, LOC(0)
    comiss  xmm0, [rel c_1_8]
    jae     .nb
    add     eax, 28
.nb:
    sub     eax, 162
    jle     .done
    imul    eax, eax, 10
    mov     LOC(4), eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    add     r8d, 5
    call    hash32
    and     eax, 31
    sub     eax, 16
    mov     edx, eax
    mov     ecx, [r12+16]
    call    col_add
    mov     edx, eax
    mov     ecx, r13d
    mov     r8d, LOC(4)
    call    col_mix
    mov     r13d, eax
.done:
    mov     eax, r13d
ENDP

; 4 boards of 3px + 1px gap, grain is vnoise stretched 4x along x
LPROC gen_planks
    mov     r12, rcx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_planks]
    mov     rdx, r12
    call    tile_shade
ENDP

LPROC sh_planks, 16
    mov     ebx, ecx
    mov     esi, edx
    mov     r12, r8
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(2,0)
    mov     r9d, [rel s_seed]
    call    vnoise
    sub     eax, 128
    sar     eax, 2
    mov     edi, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    inc     r8d
    call    hash32
    and     eax, 7
    sub     eax, 4
    add     edi, eax
    mov     r13d, esi
    and     r13d, 3
    mov     r14d, esi
    shr     r14d, 2
    cmp     r13d, 0
    jne     .n0
    add     edi, 12
.n0:
    cmp     r13d, 3
    jne     .n3
    sub     edi, 40
    jmp     .col
.n3:
    mov     ecx, r14d
    mov     edx, 5
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 15
    mov     r15d, eax
    cmp     ebx, r15d
    jne     .j1
    sub     edi, 34
    jmp     .col
.j1:
    lea     eax, [r15+1]
    and     eax, 15
    cmp     ebx, eax
    jne     .j2
    add     edi, 8
.j2:
    cmp     r13d, 1
    jne     .col
    lea     eax, [r15+2]
    and     eax, 15
    cmp     ebx, eax
    je      .nail
    lea     eax, [r15-2]
    and     eax, 15
    cmp     ebx, eax
    jne     .col
.nail:
    sub     edi, 46
.col:
    mov     ecx, [r12]
    mov     edx, edi
    call    col_add
ENDP

; 1x4 px noise cells -> vertical fissures
LPROC gen_bark
    mov     r12, rcx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_bark]
    mov     rdx, r12
    call    tile_shade
ENDP

LPROC sh_bark, 16
    mov     ebx, ecx
    mov     esi, edx
    mov     r12, r8
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(0,2)
    mov     r9d, [rel s_seed]
    call    vnoise
    mov     edi, eax
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(1,3)
    mov     r9d, [rel s_seed]
    inc     r9d
    call    vnoise
    lea     eax, [rax+rdi*2]
    mov     ecx, 3
    xor     edx, edx
    div     ecx
    mov     edi, eax
    mov     ecx, [r12]
    cmp     edi, 92
    jae     .l
    mov     ecx, [r12+4]
    jmp     .c
.l: cmp     edi, 172
    jb      .c
    mov     ecx, [r12+8]
.c: mov     LOC(0), ecx
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    add     r8d, 9
    call    hash32
    and     eax, 15
    sub     eax, 8
    mov     edx, eax
    mov     ecx, LOC(0)
    call    col_add
ENDP

LPROC gen_birch_side
    call    gen_noise
    mov     r12d, 7
.mark:
    mov     ecx, 16
    call    rndn
    mov     ebx, eax
    mov     ecx, 16
    call    rndn
    mov     esi, eax
    mov     ecx, 4
    call    rndn
    lea     edi, [rax+2]
    xor     r13d, r13d
.mx:
    lea     ecx, [rbx+r13]
    mov     edx, esi
    mov     r8d, RGB(42,40,38)
    call    pset
    lea     eax, [r13+1]
    cmp     eax, edi
    jae     .mn
    lea     ecx, [rbx+r13+1]
    lea     edx, [rsi+1]
    mov     r8d, RGB(92,90,84)
    call    pset
.mn:
    inc     r13d
    cmp     r13d, edi
    jb      .mx
    dec     r12d
    jnz     .mark
    mov     r12d, 6
.len:
    mov     ecx, 16
    call    rndn
    mov     ebx, eax
    mov     ecx, 16
    call    rndn
    mov     esi, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, RGB(168,166,156)
    call    pset
    lea     ecx, [rbx+1]
    mov     edx, esi
    mov     r8d, RGB(180,178,168)
    call    pset
    dec     r12d
    jnz     .len
ENDP

LPROC gen_logtop
    mov     r12, rcx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_logtop]
    mov     rdx, r12
    call    tile_shade
ENDP

LPROC sh_logtop, 16
    mov     ebx, ecx
    mov     esi, edx
    mov     r12, r8
    call    cheb
    mov     edi, eax
    cmp     edi, 15
    jne     .inner
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 255
    mov     r8d, eax
    mov     ecx, [r12+8]
    mov     edx, [r12+12]
    call    col_mix
    jmp     .done
.inner:
    cvtsi2ss xmm0, r8d
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, r9d
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    cvtsi2ss xmm1, edi
    addss   xmm0, xmm1
    mulss   xmm0, [rel c_half]
    cvttss2si r13d, xmm0  ; half pixels
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(2,2)
    mov     r9d, [rel s_seed]
    call    vnoise
    sub     eax, 128
    sar     eax, 6
    add     r13d, eax
    mov     eax, r13d
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    mov     ecx, [r12]
    test    eax, 1
    jz      .ring
    mov     ecx, [r12+4]
.ring:
    cmp     edi, 1
    ja      .np
    mov     edx, -16
    call    col_add
    mov     ecx, eax
.np:
    cmp     edi, 13
    jne     .nb
    mov     edx, -12
    call    col_add
    mov     ecx, eax
.nb:
    mov     LOC(0), ecx
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    add     r8d, 3
    call    hash32
    and     eax, 7
    sub     eax, 4
    mov     edx, eax
    mov     ecx, LOC(0)
    call    col_add
.done:
ENDP

; ~30% holes, clumped
LPROC gen_leaves
    mov     r12, rcx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_leaves]
    mov     rdx, r12
    call    tile_shade
    mov     ecx, 16
    mov     edx, -22
    call    edge_light
ENDP

LPROC sh_leaves, 16
    mov     ebx, ecx
    mov     esi, edx
    mov     r12, r8
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(1,1)
    mov     r9d, [rel s_seed]
    call    vnoise
    mov     edi, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    add     r8d, 5
    call    hash32
    mov     r13d, eax
    movzx   eax, r13b
    cmp     eax, [r12+8]
    jb      .hole
    cmp     eax, [r12+4]
    jae     .leaf
    cmp     edi, 140
    jb      .hole
.leaf:
    lea     eax, [rdi-128]
    sar     eax, 2
    mov     edx, r13d
    shr     edx, 8
    and     edx, 31
    sub     edx, 16
    add     edx, eax
    mov     ecx, [r12]
    call    col_add
    jmp     .done
.hole:
    mov     eax, [r12]
    and     eax, 0x00FFFFFF
.done:
ENDP

LPROC gen_glass
    mov     ecx, RGBA(200,225,235,0)
    call    tile_fill
    xor     ebx, ebx
.f: mov     ecx, ebx
    xor     edx, edx
    mov     r8d, RGB(222,240,246)
    call    pset
    xor     ecx, ecx
    mov     edx, ebx
    mov     r8d, RGB(222,240,246)
    call    pset
    mov     ecx, ebx
    mov     edx, 15
    mov     r8d, RGB(164,196,208)
    call    pset
    mov     ecx, 15
    mov     edx, ebx
    mov     r8d, RGB(164,196,208)
    call    pset
    inc     ebx
    cmp     ebx, 16
    jb      .f
    mov     ecx, 15
    xor     edx, edx
    mov     r8d, RGB(196,220,228)
    call    pset
    xor     ecx, ecx
    mov     edx, 15
    mov     r8d, RGB(196,220,228)
    call    pset
    mov     dword [rsp+32], RGBA(255,255,255,170)
    mov     ecx, 3
    mov     edx, 8
    mov     r8d, 8
    mov     r9d, 3
    call    pline
    mov     dword [rsp+32], RGBA(255,255,255,120)
    mov     ecx, 4
    mov     edx, 10
    mov     r8d, 6
    mov     r9d, 8
    call    pline
    mov     dword [rsp+32], RGBA(255,255,255,140)
    mov     ecx, 10
    mov     edx, 13
    mov     r8d, 13
    mov     r9d, 10
    call    pline
ENDP

LPROC gen_sandstone_side
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_sandstone]
    xor     edx, edx
    call    tile_shade
ENDP

LPROC sh_sandstone
    mov     ebx, ecx
    mov     esi, edx
    shl     ecx, 8
    shl     edx, 8
    mov     r8d, SH(2,1)
    mov     r9d, [rel s_seed]
    call    fbm
    sub     eax, 128
    sar     eax, 3
    mov     edi, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    mov     r12d, eax
    and     eax, 7
    sub     eax, 4
    add     edi, eax
    cmp     esi, 2
    ja      .b1
    sar     edi, 1
    add     edi, 10
    jmp     .c
.b1:
    cmp     esi, 3
    jne     .b2
    sub     edi, 24
    jmp     .c
.b2:
    cmp     esi, 4
    jne     .b3
    sub     edi, 6
.b3:
    cmp     esi, 9
    jne     .b4
    sub     edi, 9
.b4:
    cmp     esi, 13
    jb      .c
    sub     edi, 10
    shr     r12d, 8
    and     r12d, 255
    cmp     r12d, 50
    jae     .c
    sub     edi, 14
.c: mov     ecx, RGB(216,203,156)
    mov     edx, edi
    call    col_add
ENDP

; this sits on every block of a frozen sea, anything strong or regular becomes a grid.
; so faint cracks, shaded glints
LPROC gen_ice
    call    gen_noise
    mov     r12d, 2
.c: mov     ecx, 16
    call    rndn
    mov     ebx, eax
    mov     ecx, 16
    call    rndn
    mov     esi, eax
    mov     ecx, 4
    call    rndn
    lea     r8d, [rax+4]  ; 4..7 px
    mov     ecx, ebx
    mov     edx, esi
    mov     r9d, 20
    call    crack_walk
    dec     r12d
    jnz     .c
    mov     r12d, 3
.sp:
    mov     ecx, 16
    call    rndn
    mov     ebx, eax
    mov     ecx, 16
    call    rndn
    mov     edx, eax
    mov     ecx, ebx
    mov     r8d, 30
    call    pshade
    dec     r12d
    jnz     .sp
    call    tile_flatten
ENDP

LPROC gen_cactus_side
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_cactus_side]
    xor     edx, edx
    call    tile_shade
    mov     r12d, 9
.sp:
    mov     ecx, 4
    call    rndn
    lea     rdx, [rel cactus_spine_x]
    movzx   ebx, byte [rdx+rax]
    mov     ecx, 16
    call    rndn
    mov     esi, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, RGB(222,226,170)
    call    pset
    mov     ecx, ebx
    lea     edx, [rsi+1]
    mov     r8d, -34
    call    pshade
    dec     r12d
    jnz     .sp
ENDP

LPROC sh_cactus_side
    mov     ebx, ecx
    mov     esi, edx
    lea     rax, [rel cactus_profile]
    movsx   edi, byte [rax+rbx]
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(0,2)
    mov     r9d, [rel s_seed]
    call    vnoise
    sub     eax, 128
    sar     eax, 3
    add     edi, eax
    mov     ecx, RGB(84,140,44)
    mov     edx, edi
    call    col_add
ENDP

LPROC gen_cactus_top
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_cactus_top]
    xor     edx, edx
    call    tile_shade
ENDP

LPROC sh_cactus_top
    mov     ebx, ecx
    mov     esi, edx
    call    cheb
    mov     edi, eax
    mov     r12d, RGB(84,140,44)
    cmp     edi, 15
    jne     .a
    mov     r12d, RGB(48,92,28)
    jmp     .n
.a: cmp     edi, 13
    jne     .b
    mov     r12d, RGB(112,172,62)
    jmp     .n
.b: cmp     edi, 5
    ja      .n
    mov     r12d, RGB(128,186,72)
    cmp     edi, 1
    ja      .n
    mov     r12d, RGB(70,120,36)
.n: mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 15
    sub     eax, 8
    mov     edx, eax
    mov     ecx, r12d
    call    col_add
ENDP

LPROC gen_gravel
    mov     ecx, 5
    call    vor_setup
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_gravel]
    xor     edx, edx
    call    tile_shade
ENDP

LPROC sh_gravel
    mov     ebx, ecx
    mov     esi, edx
    call    vor_query
    mov     edi, eax
    call    vor_edge
    comiss  xmm0, [rel c_0_7]
    jae     .peb
    mov     eax, RGB(72,68,66)
    jmp     .done
.peb:
    mov     ecx, edi
    mov     edx, 3
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 3
    lea     rdx, [rel gravel_cols]
    mov     r12d, [rdx+rax*4]
    movss   xmm1, [rel c_m8f]
    call    vor_shade
    mov     r13d, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 15
    sub     eax, 8
    lea     edx, [rax+r13]
    mov     ecx, r12d
    call    col_add
.done:
ENDP

LPROC gen_bedrock
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_bedrock]
    xor     edx, edx
    call    tile_shade
ENDP

LPROC sh_bedrock
    mov     ebx, ecx
    mov     esi, edx
    shl     ecx, 8
    shl     edx, 8
    mov     r8d, SH(1,1)
    mov     r9d, [rel s_seed]
    call    vnoise
    mov     edi, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    mov     r12d, eax
    and     eax, 63
    add     edi, eax
    sub     edi, 32
    mov     ecx, RGB(38,38,40)
    cmp     edi, 100
    jb      .c
    mov     ecx, RGB(84,84,86)
    cmp     edi, 160
    jb      .c
    mov     ecx, RGB(128,128,130)
.c: shr     r12d, 8
    and     r12d, 15
    lea     edx, [r12-8]
    call    col_add
ENDP

LPROC gen_obsidian
    call    gen_noise
    mov     r12d, 6
.s: mov     ecx, 16
    call    rndn
    mov     ebx, eax
    mov     ecx, 16
    call    rndn
    mov     esi, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, RGB(122,96,172)
    call    pset
    lea     ecx, [rbx+1]
    lea     edx, [rsi-1]
    mov     r8d, RGB(86,62,128)
    call    pset
    lea     ecx, [rbx-1]
    lea     edx, [rsi+1]
    mov     r8d, RGB(64,44,98)
    call    pset
    dec     r12d
    jnz     .s
ENDP

LPROC gen_glowcrystal
    mov     ecx, 3
    call    vor_setup
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_glow]
    xor     edx, edx
    call    tile_shade
    mov     r12d, 5
.s: mov     ecx, 16
    call    rndn
    mov     ebx, eax
    mov     ecx, 16
    call    rndn
    mov     edx, eax
    mov     ecx, ebx
    mov     r8d, RGB(255,255,255)
    call    pset
    dec     r12d
    jnz     .s
ENDP

LPROC sh_glow
    mov     ebx, ecx
    mov     esi, edx
    call    vor_query
    mov     edi, eax
    call    vor_edge
    comiss  xmm0, [rel c_0_9]
    jae     .facet
    mov     eax, RGB(204,128,40)
    jmp     .done
.facet:
    mov     ecx, edi
    mov     edx, 11
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 255
    mov     r8d, eax
    mov     ecx, RGB(250,186,70)
    mov     edx, RGB(255,250,214)
    call    col_mix
    mov     r12d, eax
    movss   xmm1, [rel c_m8f]
    call    vor_shade
    mov     edx, eax
    mov     ecx, r12d
    call    col_add
.done:
ENDP

LPROC gen_bricks
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_bricks]
    xor     edx, edx
    call    tile_shade
ENDP

LPROC sh_bricks
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, esi
    shr     r12d, 2
    mov     r13d, esi
    and     r13d, 3
    mov     eax, r12d
    and     eax, 1
    shl     eax, 2
    add     eax, ebx
    and     eax, 15
    mov     r14d, eax
    cmp     r13d, 3
    je      .mortar
    mov     eax, r14d
    and     eax, 7
    cmp     eax, 7
    je      .mortar
    mov     ecx, r14d
    shr     ecx, 3
    lea     ecx, [rcx+r12*2]
    mov     edx, 9
    mov     r8d, [rel s_seed]
    call    hash32
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    lea     rax, [rel brick_cols]
    mov     edi, [rax+rdx*4]
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 15
    sub     eax, 8
    mov     r15d, eax
    cmp     r13d, 0
    jne     .r2
    add     r15d, 14
.r2:
    cmp     r13d, 2
    jne     .r3
    sub     r15d, 9
.r3:
    mov     eax, r14d
    and     eax, 7
    jnz     .r4
    add     r15d, 6
.r4:
    mov     ecx, edi
    mov     edx, r15d
    call    col_add
    jmp     .done
.mortar:
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    inc     r8d
    call    hash32
    and     eax, 15
    sub     eax, 8
    mov     edx, eax
    mov     ecx, RGB(176,166,154)
    call    col_add
.done:
ENDP

LPROC gen_stone_bricks
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_stone_bricks]
    xor     edx, edx
    call    tile_shade
    mov     ecx, 4
    call    rndn
    lea     ecx, [rax+2]
    mov     edx, 9
    mov     r8d, 4
    mov     r9d, -18
    call    crack_walk
ENDP

LPROC sh_stone_bricks
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, esi
    shr     r12d, 3
    mov     r13d, esi
    and     r13d, 7
    mov     eax, r12d
    shl     eax, 2
    add     eax, ebx
    and     eax, 15
    mov     r14d, eax
    and     eax, 7
    mov     r15d, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 15
    sub     eax, 8
    mov     edi, eax
    cmp     r13d, 7
    je      .mortar
    cmp     r15d, 7
    je      .mortar
    mov     ecx, r14d
    shr     ecx, 3
    lea     ecx, [rcx+r12*2]
    mov     edx, 4
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 15
    sub     eax, 8
    add     edi, eax
    test    r13d, r13d
    jz      .hi
    test    r15d, r15d
    jnz     .h2
.hi:
    add     edi, 16
    jmp     .c
.h2:
    cmp     r13d, 6
    je      .lo
    cmp     r15d, 6
    jne     .c
.lo:
    sub     edi, 16
.c: mov     ecx, RGB(124,124,126)
    mov     edx, edi
    call    col_add
    jmp     .done
.mortar:
    mov     ecx, RGB(76,76,78)
    mov     edx, edi
    call    col_add
.done:
ENDP

LPROC gen_bookshelf
    lea     rcx, [rel plk_oak]
    call    gen_planks
    mov     ecx, 6
    call    shelf_books
    mov     ecx, 14
    call    shelf_books
    mov     esi, 1
.fr:
    xor     ecx, ecx
    mov     edx, esi
    mov     r8d, -22
    call    pshade
    mov     ecx, 15
    mov     edx, esi
    mov     r8d, -22
    call    pshade
    inc     esi
    cmp     esi, 15
    jb      .fr
ENDP

; ecx = bottom row, fills 6 rows, x 1..14
LPROC shelf_books, 32
    mov     r12d, ecx
    lea     r13d, [r12-5]
    mov     esi, r13d
.by:
    mov     ebx, 1
.bx:
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, RGB(46,30,18)
    call    pset
    inc     ebx
    cmp     ebx, 15
    jb      .bx
    inc     esi
    cmp     esi, r12d
    jbe     .by
    mov     ebx, 1
.book:
    cmp     ebx, 14
    ja      .done
    mov     ecx, 3
    call    rndn
    mov     r14d, 1
    test    eax, eax
    jz      .w
    mov     r14d, 2
.w: lea     eax, [rbx+r14]
    cmp     eax, 15
    jbe     .w2
    mov     r14d, 1
.w2:
    mov     ecx, 3
    call    rndn
    add     eax, 4
    mov     r15d, eax  ; 4..6
    mov     ecx, 8
    call    rndn
    lea     rdx, [rel book_cols]
    mov     edi, [rdx+rax*4]
    mov     ecx, 3
    call    rndn
    mov     LOC(0), eax  ; 0 = gilt band
    mov     eax, r12d
    sub     eax, r15d
    inc     eax
    mov     LOC(4), eax
    xor     esi, esi
.bc:
    mov     eax, LOC(4)
    mov     LOC(8), eax
.br:
    mov     eax, edi
    mov     LOC(12), eax
    mov     eax, LOC(8)
    cmp     eax, LOC(4)
    jne     .nt
    mov     ecx, LOC(12)
    mov     edx, 30
    call    col_add
    mov     LOC(12), eax
.nt:
    cmp     dword LOC(0), 0
    jne     .ng
    mov     eax, LOC(4)
    inc     eax
    cmp     eax, LOC(8)
    je      .gild
    lea     eax, [r12-1]
    cmp     eax, LOC(8)
    jne     .ng
.gild:
    mov     dword LOC(12), RGB(214,184,88)
.ng:
    cmp     r14d, 2
    jne     .put
    cmp     esi, 1
    jne     .put
    mov     ecx, LOC(12)
    mov     edx, -24
    call    col_add
    mov     LOC(12), eax
.put:
    lea     ecx, [rbx+rsi]
    mov     edx, LOC(8)
    mov     r8d, LOC(12)
    call    pset
    inc     dword LOC(8)
    cmp     LOC(8), r12d
    jbe     .br
    inc     esi
    cmp     esi, r14d
    jb      .bc
    add     ebx, r14d
    mov     ecx, 5
    call    rndn
    test    eax, eax
    jnz     .book
    inc     ebx
    jmp     .book
.done:
ENDP

LPROC gen_craft_top
    lea     rcx, [rel plk_craft]
    call    gen_planks
    lea     rcx, [rel sh_craft_top]
    xor     edx, edx
    call    tile_shade
    lea     rcx, [rel map_craft_corner]
    lea     rdx, [rel pal_tools_ovl]
    call    blit_map
ENDP

LPROC sh_craft_top
    mov     ebx, ecx
    mov     esi, edx
    mov     edi, r9d
    call    cheb
    cmp     eax, 15
    jne     .g
    mov     ecx, RGB(86,58,30)
    mov     edx, 0
    jmp     .add
.g: mov     ecx, edi
    xor     edx, edx
    cmp     ebx, 5
    je      .line
    cmp     ebx, 10
    je      .line
    cmp     esi, 5
    je      .line
    cmp     esi, 10
    je      .line
    cmp     ebx, 6
    je      .bev
    cmp     ebx, 11
    je      .bev
    cmp     esi, 6
    je      .bev
    cmp     esi, 11
    jne     .add
.bev:
    mov     edx, 10
    jmp     .add
.line:
    mov     edx, -30
.add:
    call    col_add
ENDP

LPROC gen_craft_face
    mov     r12, rcx
    lea     rcx, [rel plk_craft]
    call    gen_planks
    xor     ebx, ebx
.t: mov     ecx, ebx
    xor     edx, edx
    mov     r8d, 18
    call    pshade
    mov     ecx, ebx
    mov     edx, 1
    mov     r8d, 18
    call    pshade
    mov     ecx, ebx
    mov     edx, 2
    mov     r8d, RGB(80,52,26)
    call    pset
    inc     ebx
    cmp     ebx, 16
    jb      .t
    mov     esi, 3
.e: xor     ecx, ecx
    mov     edx, esi
    mov     r8d, -24
    call    pshade
    mov     ecx, 15
    mov     edx, esi
    mov     r8d, -24
    call    pshade
    inc     esi
    cmp     esi, 16
    jb      .e
    mov     rcx, r12
    lea     rdx, [rel pal_tools_ovl]
    call    blit_map
ENDP

; furnace param: 0 front, 1 lit front, 2 side, 3 top
LPROC gen_furnace, 16
    mov     r12d, ecx
    lea     rcx, [rel nb_furnace]
    call    gen_noise
    mov     LOC(0), r12d
    lea     rcx, [rel sh_furnace]
    mov     edx, r12d
    call    tile_shade
ENDP

LPROC sh_furnace, 16
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    mov     edi, r9d
    call    cheb
    mov     r13d, eax
    xor     r14d, r14d
    cmp     r13d, 15
    jne     .f1
    mov     r14d, -32
    jmp     .kind
.f1:
    cmp     ebx, 1
    je      .hl
    cmp     esi, 1
    jne     .f2
.hl:
    mov     r14d, 12
    jmp     .kind
.f2:
    cmp     ebx, 14
    je      .sh
    cmp     esi, 14
    jne     .kind
.sh:
    mov     r14d, -10
.kind:
    cmp     r12d, 3
    jne     .side
    cmp     r13d, 9
    jne     .apply
    sub     r14d, 14
    jmp     .apply
.side:
    cmp     r12d, 2
    jne     .front
    cmp     esi, 7
    jne     .s2
    cmp     r13d, 15
    je      .apply
    sub     r14d, 20
.s2:
    cmp     esi, 8
    jne     .apply
    add     r14d, 8
    jmp     .apply
.front:
    cmp     ebx, 4
    jb      .box
    cmp     ebx, 11
    ja      .box
    cmp     esi, 3
    jne     .v2
    mov     eax, RGB(38,38,40)
    cmp     r12d, 1
    jne     .ret
    mov     eax, RGB(128,58,20)
    jmp     .ret
.v2:
    cmp     esi, 4
    jne     .box
    sub     r14d, 14
.box:
    cmp     ebx, 3
    jb      .apply
    cmp     ebx, 12
    ja      .apply
    cmp     esi, 7
    jb      .glow
    cmp     esi, 13
    ja      .apply
    cmp     ebx, 3
    je      .rim
    cmp     ebx, 12
    je      .rim
    cmp     esi, 7
    je      .rim
    cmp     esi, 13
    je      .rim
    cmp     r12d, 1
    je      .fire
    cmp     esi, 12
    jne     .dark
    test    ebx, 1
    jnz     .dark
    mov     eax, RGB(92,92,94)
    jmp     .ret
.dark:
    lea     eax, [rsi-8]
    imul    eax, eax, -3
    mov     ecx, RGB(36,32,32)
    mov     edx, eax
    call    col_add
    jmp     .ret
.fire:
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(1,1)
    mov     r9d, 4711
    call    vnoise
    sub     eax, 128
    sar     eax, 1
    lea     edx, [rsi-8]
    imul    edx, edx, 44
    add     edx, eax
    add     edx, 40
    lea     rcx, [rel ramp_fire]
    call    ramp
    jmp     .ret
.rim:
    mov     eax, RGB(62,62,64)
    cmp     r12d, 1
    jne     .ret
    mov     ecx, eax
    mov     edx, RGB(255,150,40)
    mov     r8d, 130
    call    col_mix
    jmp     .ret
.glow:
    cmp     r12d, 1
    jne     .apply
    cmp     esi, 6
    jne     .apply
    mov     ecx, edi
    mov     edx, r14d
    call    col_add
    mov     ecx, eax
    mov     edx, RGB(255,140,40)
    mov     r8d, 60
    call    col_mix
    jmp     .ret
.apply:
    mov     ecx, edi
    mov     edx, r14d
    call    col_add
.ret:
ENDP

LPROC gen_tnt, 16
    mov     r12d, ecx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_tnt]
    mov     edx, r12d
    call    tile_shade
    test    r12d, r12d
    jnz     .done
    ; 12x5 stencil at (2,6)
    lea     r13, [rel tnt_letters]
    xor     ebx, ebx
.l: movzx   eax, byte [r13+rbx]
    cmp     al, '#'
    jne     .nl
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 12
    div     ecx
    lea     ecx, [rdx+2]
    lea     edx, [rax+6]
    mov     r8d, RGB(44,32,30)
    call    pset
.nl:
    inc     ebx
    cmp     ebx, 60
    jb      .l
.done:
ENDP

LPROC sh_tnt
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 15
    sub     eax, 8
    mov     edi, eax
    test    r12d, r12d
    jnz     .top
    cmp     esi, 5
    jb      .red
    cmp     esi, 10
    ja      .red
    mov     ecx, RGB(234,228,214)
    mov     edx, edi
    call    col_add
    jmp     .done
.red:
    cmp     esi, 4
    je      .band
    cmp     esi, 11
    jne     .stick
.band:
    sub     edi, 50
.stick:
    mov     eax, ebx
    and     eax, 3
    cmp     eax, 3
    jne     .s1
    sub     edi, 40
.s1:
    test    eax, eax
    jnz     .s2
    add     edi, 14
.s2:
    mov     ecx, RGB(206,46,30)
    mov     edx, edi
    call    col_add
    jmp     .done
.top:
    mov     eax, ebx
    and     eax, 3
    mov     ecx, esi
    and     ecx, 3
    mov     edx, 0
    cmp     eax, 0
    je      .ex
    cmp     eax, 3
    jne     .mid
.ex:
    inc     edx
.mid:
    cmp     ecx, 0
    je      .ey
    cmp     ecx, 3
    jne     .cl
.ey:
    inc     edx
.cl:
    mov     ecx, RGB(216,62,40)
    cmp     edx, 1
    jne     .c2
    mov     ecx, RGB(170,38,24)
.c2:
    cmp     edx, 2
    jne     .c3
    mov     ecx, RGB(104,24,14)
.c3:
    cmp     r12d, 2
    jne     .fuse
    mov     edx, -30
    add     edx, edi
    call    col_add
    jmp     .done
.fuse:
    cmp     ebx, 7
    jb      .nf
    cmp     ebx, 8
    ja      .nf
    cmp     esi, 7
    jb      .nf
    cmp     esi, 8
    ja      .nf
    mov     ecx, RGB(56,50,44)
    cmp     ebx, 7
    jne     .nf
    cmp     esi, 7
    jne     .nf
    mov     ecx, RGB(150,140,120)
.nf:
    mov     edx, edi
    call    col_add
.done:
ENDP

LPROC gen_torch
    mov     ecx, RGBA(120,90,50,0)
    call    tile_fill
    mov     esi, 9
.st:
    mov     ecx, 7
    mov     edx, esi
    mov     r8d, RGB(138,100,54)
    call    pset
    mov     ecx, 8
    mov     edx, esi
    mov     r8d, RGB(96,66,34)
    call    pset
    inc     esi
    cmp     esi, 16
    jb      .st
    lea     rcx, [rel map_torch_top]
    lea     rdx, [rel pal_torch]
    call    blit_map
ENDP

; pumpkin: 0 side, 1 top, 2 carved face
LPROC gen_pumpkin
    mov     r12d, ecx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_pumpkin]
    mov     edx, r12d
    call    tile_shade
    cmp     r12d, 2
    jne     .done
    lea     rcx, [rel map_pumpkin_face]
    lea     rdx, [rel pal_pumpkin_face]
    call    blit_map
.done:
ENDP

LPROC sh_pumpkin
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(2,2)
    mov     r9d, [rel s_seed]
    call    fbm
    sub     eax, 128
    sar     eax, 3
    mov     edi, eax
    cmp     r12d, 1
    je      .top
    lea     rax, [rel pumpkin_ribs]
    movsx   eax, byte [rax+rbx]
    add     edi, eax
    test    esi, esi
    jz      .edge
    cmp     esi, 15
    jne     .c
.edge:
    sub     edi, 18
.c: mov     ecx, RGB(226,134,30)
    mov     edx, edi
    call    col_add
    jmp     .done
.top:
    mov     ecx, ebx
    mov     edx, esi
    call    cheb
    cmp     eax, 3
    ja      .rib
    mov     ecx, RGB(112,94,38)
    cmp     eax, 3
    jne     .stem
    mov     ecx, RGB(78,64,24)
.stem:
    mov     edx, edi
    call    col_add
    jmp     .done
.rib:
    cmp     eax, 15
    jne     .r1
    sub     edi, 22
.r1:
    cmp     r8d, 1
    jbe     .r2
    cmp     r9d, 1
    ja      .r3
.r2:
    sub     edi, 18
.r3:
    mov     ecx, RGB(220,128,28)
    mov     edx, edi
    call    col_add
.done:
ENDP

; melon: 0 side, 1 top
LPROC gen_melon
    mov     r12d, ecx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_melon]
    mov     edx, r12d
    call    tile_shade
ENDP

LPROC sh_melon
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 15
    sub     eax, 8
    mov     edi, eax
    test    r12d, r12d
    jnz     .top
    xor     ecx, ecx
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(0,2)
    mov     r9d, [rel s_seed]
    call    vnoise
    shr     eax, 6
    add     eax, ebx
    xor     edx, edx
    mov     ecx, 5
    div     ecx
    mov     ecx, RGB(114,170,46)
    cmp     edx, 2
    jae     .c
    mov     ecx, RGB(66,116,26)
.c: mov     edx, edi
    call    col_add
    jmp     .done
.top:
    mov     ecx, ebx
    mov     edx, esi
    call    cheb
    mov     ecx, RGB(114,170,46)
    cmp     eax, 15
    jne     .t1
    mov     ecx, RGB(66,116,26)
.t1:
    cmp     eax, 9
    jne     .t2
    mov     ecx, RGB(80,134,32)
.t2:
    cmp     eax, 3
    ja      .t3
    mov     ecx, RGB(150,192,82)
.t3:
    mov     edx, edi
    call    col_add
.done:
ENDP

LPROC gen_wool
    mov     r12, rcx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_wool]
    mov     rdx, r12
    call    tile_shade
ENDP

LPROC sh_wool
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    ; rows shift by 2 every other pair of columns -> zig-zag
    mov     eax, ebx
    shr     eax, 1
    and     eax, 1
    add     eax, eax
    add     eax, esi
    and     eax, 3
    lea     rcx, [rel knit_tab]
    movsx   edi, byte [rcx+rax]
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(2,2)
    mov     r9d, [rel s_seed]
    call    fbm
    sub     eax, 128
    sar     eax, 3
    add     edi, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 7
    sub     eax, 4
    lea     edx, [rdi+rax]
    mov     ecx, r12d
    call    col_add
ENDP

LPROC gen_metal
    mov     r12, rcx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_metal]
    mov     rdx, r12
    call    tile_shade
ENDP

LPROC sh_metal, 16
    mov     ebx, ecx
    mov     esi, edx
    mov     r12, r8
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 7
    sub     eax, 4
    mov     edi, eax
    mov     r13d, [r12+12]
    cmp     r13d, 2
    jne     .notcoal
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    add     r8d, 3
    call    hash32
    and     eax, 255
    cmp     eax, 30
    jae     .cn
    add     edi, 30
.cn:
    sub     eax, 128
    sar     eax, 5
    add     edi, eax
.notcoal:
    test    ebx, ebx
    jz      .light
    test    esi, esi
    jz      .light
    cmp     ebx, 15
    je      .dark
    cmp     esi, 15
    je      .dark
    mov     r14d, [r12]
    cmp     ebx, 1
    je      .bl
    cmp     esi, 1
    jne     .b2
.bl:
    add     edi, 10
.b2:
    cmp     ebx, 14
    je      .bd
    cmp     esi, 14
    jne     .shine
.bd:
    sub     edi, 10
.shine:
    lea     eax, [rbx+rsi]
    cmp     eax, 6
    jb      .s3
    cmp     eax, 8
    ja      .s2
    add     edi, 22
    jmp     .s3
.s2:
    cmp     eax, 9
    jne     .s4
    add     edi, 10
.s4:
    cmp     eax, 20
    jb      .s3
    cmp     eax, 21
    ja      .s3
    add     edi, 12
.s3:
    cmp     r13d, 1
    jne     .plates
    cmp     ebx, esi
    je      .facet
    lea     eax, [rbx+rsi]
    cmp     eax, 15
    jne     .c
.facet:
    add     edi, 14
    jmp     .c
.plates:
    test    r13d, r13d
    jnz     .c
    cmp     esi, 7
    jne     .p2
    sub     edi, 16
.p2:
    cmp     esi, 8
    jne     .p3
    add     edi, 6
.p3:
    cmp     ebx, 3
    je      .rx
    cmp     ebx, 12
    jne     .c
.rx:
    cmp     esi, 3
    je      .rv
    cmp     esi, 12
    jne     .c
.rv:
    add     edi, 30
    jmp     .c
.light:
    mov     r14d, [r12+4]
    jmp     .c
.dark:
    mov     r14d, [r12+8]
.c: mov     ecx, r14d
    mov     edx, edi
    call    col_add
ENDP

; chest: 0 front, 1 side, 2 top
LPROC gen_chest
    mov     r12d, ecx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_chest]
    mov     edx, r12d
    call    tile_shade
    test    r12d, r12d
    jnz     .done
    mov     dword [rsp+32], RGB(52,52,58)
    mov     ecx, 6
    mov     edx, 3
    mov     r8d, 4
    mov     r9d, 6
    call    prect
    mov     dword [rsp+32], RGB(196,196,204)
    mov     ecx, 7
    mov     edx, 4
    mov     r8d, 2
    mov     r9d, 4
    call    prect
    mov     ecx, 7
    mov     edx, 4
    mov     r8d, RGB(244,244,250)
    call    pset
    mov     ecx, 8
    mov     edx, 7
    mov     r8d, RGB(140,140,150)
    call    pset
.done:
ENDP

LPROC sh_chest
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(2,0)
    mov     r9d, [rel s_seed]
    call    vnoise
    sub     eax, 128
    sar     eax, 2
    mov     edi, eax
    mov     ecx, ebx
    mov     edx, esi
    call    cheb
    cmp     eax, 15
    jne     .in
    mov     ecx, RGB(76,48,20)
    jmp     .add
.in:
    mov     ecx, RGB(162,108,48)
    cmp     eax, 13
    jne     .s
    add     edi, 8
.s: cmp     r12d, 2
    je      .add
    cmp     esi, 5
    jne     .s1
    mov     ecx, RGB(64,40,16)
    jmp     .add
.s1:
    cmp     esi, 4
    jne     .s2
    sub     edi, 12
.s2:
    cmp     esi, 6
    jne     .add
    add     edi, 10
.add:
    mov     edx, edi
    call    col_add
ENDP

; flat clay colour with soft horizontal streaks, the bands come from stacking them
LPROC gen_terracotta
    mov     r12d, ecx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_terracotta]
    mov     edx, r12d
    call    tile_shade
ENDP

LPROC sh_terracotta
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    shl     ecx, 8
    shl     edx, 8
    mov     r8d, SH(3,1)
    mov     r9d, [rel s_seed]
    call    vnoise
    sub     eax, 128
    sar     eax, 3
    mov     edi, eax
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, [rel s_seed]
    call    hash32
    mov     r13d, eax
    and     eax, 7
    sub     eax, 4
    add     edi, eax
    shr     r13d, 8
    and     r13d, 63
    jnz     .c
    sub     edi, 14                     ; odd darker grain
.c: mov     ecx, r12d
    mov     edx, edi
    call    col_add
ENDP

; ecx colour, edx x, r8d y -> eax with a bit of per pixel grain
bed_px:
    mov     r10d, ecx
    mov     ecx, edx
    mov     edx, r8d
    mov     r8d, [rel s_seed]
    call    hash32
    and     eax, 7
    sub     eax, 4
    mov     ecx, r10d
    mov     edx, eax
    jmp     col_add

LPROC gen_bed
    mov     r12d, ecx
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_bed_side]
    test    r12d, r12d
    jz      .go
    lea     rcx, [rel sh_bed_top]
.go:
    lea     edx, [r12-1]
    call    tile_shade
ENDP

; blanket hanging over the frame, legs in the corners
LPROC sh_bed_side
    mov     ebx, ecx
    mov     esi, edx
    mov     ecx, RGB(204,70,60)
    test    esi, esi
    jz      .px
    cmp     esi, 6
    ja      .hem
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, RGB(162,42,36)
    call    sh_wool
    jmp     .done
.hem:
    mov     ecx, RGB(110,24,20)
    cmp     esi, 7
    je      .px
    cmp     esi, 11
    ja      .legs
    mov     ecx, ebx
    mov     edx, esi
    lea     r8, [rel plk_oak]
    call    sh_planks
    jmp     .done
.legs:
    mov     ecx, RGB(112,80,44)
    cmp     ebx, 2
    jbe     .px
    cmp     ebx, 13
    jae     .px
    mov     ecx, RGB(46,32,22)
.px:
    mov     edx, ebx
    mov     r8d, esi
    call    bed_px
.done:
ENDP

; r13d = u (0 at the head end), r14d = v across
LPROC sh_bed_top
    mov     ebx, ecx
    mov     esi, edx
    mov     r13d, 15
    sub     r13d, esi
    mov     r14d, ebx
    test    r8d, r8d
    jz      .uv
    mov     r13d, ebx
    mov     r14d, esi
    cmp     r8d, 1
    je      .uv
    mov     r13d, esi
    mov     r14d, ebx
    cmp     r8d, 2
    je      .uv
    mov     r13d, 15
    sub     r13d, ebx
    mov     r14d, esi
.uv:
    mov     ecx, RGB(124,90,50)         ; frame at the head
    test    r13d, r13d
    jz      .px
    cmp     r13d, 4
    ja      .blanket
    mov     ecx, RGB(206,200,192)       ; sheet
    cmp     r14d, 2
    jb      .px
    cmp     r14d, 13
    ja      .px
    mov     ecx, RGB(238,236,230)       ; pillow, rim a bit darker
    cmp     r13d, 1
    je      .rim
    cmp     r13d, 4
    je      .rim
    cmp     r14d, 2
    je      .rim
    cmp     r14d, 13
    jne     .px
.rim:
    mov     ecx, RGB(214,212,206)
    jmp     .px
.blanket:
    mov     ecx, RGB(206,72,62)         ; folded edge
    cmp     r13d, 5
    je      .px
    mov     ecx, RGB(124,30,26)
    test    r14d, r14d
    jz      .px
    cmp     r14d, 15
    je      .px
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, RGB(162,42,36)
    call    sh_wool
    jmp     .done
.px:
    mov     edx, ebx
    mov     r8d, esi
    call    bed_px
.done:
ENDP

; one crack network shared by all 10 stages, recorded step-major so it grows outward.
; stage s shows the first 10%..100% of it
LPROC crack_build
    mov     ecx, 0xC0FFEE
    call    rng_set
    lea     r12, [rel s_branch]  ; 6 x {x, y, dir, len}
    xor     ebx, ebx
.init:
    mov     r14d, ebx
    shl     r14d, 4
    add     r14, r12
    mov     eax, ebx
    and     eax, 1
    add     eax, 7
    mov     [r14], eax  ; x = 7/8
    mov     eax, ebx
    shr     eax, 1
    and     eax, 1
    add     eax, 7
    mov     [r14+4], eax
    mov     eax, ebx
    imul    eax, eax, 4
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    mov     r13d, eax
    mov     ecx, 2
    call    rndn
    add     eax, r13d
    and     eax, 7
    mov     [r14+8], eax
    mov     ecx, 6
    call    rndn
    add     eax, 6
    mov     [r14+12], eax  ; 6..11
    inc     ebx
    cmp     ebx, 6
    jb      .init
    xor     edi, edi
    xor     esi, esi
.step:
    xor     ebx, ebx
.br:
    mov     r13d, ebx
    shl     r13d, 4
    add     r13, r12
    cmp     esi, [r13+12]
    jae     .nextb
    mov     eax, [r13]
    cmp     eax, 15
    ja      .nextb  ; off the tile
    mov     ecx, [r13+4]
    cmp     ecx, 15
    ja      .nextb
    lea     rdx, [rel s_crackx]
    mov     [rdx+rdi], al
    lea     rdx, [rel s_cracky]
    mov     [rdx+rdi], cl
    inc     edi
    mov     eax, [r13+8]
    lea     rdx, [rel dir8]
    movsx   ecx, byte [rdx+rax*2]
    add     [r13], ecx
    movsx   ecx, byte [rdx+rax*2+1]
    add     [r13+4], ecx
    mov     ecx, 4
    call    rndn
    mov     ecx, [r13+8]
    cmp     eax, 0
    jne     .t1
    inc     ecx
.t1:
    cmp     eax, 1
    jne     .t2
    dec     ecx
.t2:
    and     ecx, 7
    mov     [r13+8], ecx
.nextb:
    inc     ebx
    cmp     ebx, 6
    jb      .br
    inc     esi
    cmp     esi, 12
    jb      .step
    mov     [rel s_ncrack], edi
ENDP

LPROC gen_destroy
    mov     r12d, ecx
    mov     ecx, RGBA(0,0,0,0)
    call    tile_fill
    ; n = 3 + (stage+1)*(total-3)/10
    mov     eax, [rel s_ncrack]
    sub     eax, 3
    lea     ecx, [r12+1]
    imul    eax, ecx
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    add     eax, 3
    mov     r13d, eax
    xor     ebx, ebx
.px:
    cmp     ebx, r13d
    jae     .done
    lea     rax, [rel s_crackx]
    movzx   esi, byte [rax+rbx]
    lea     rax, [rel s_cracky]
    movzx   edi, byte [rax+rbx]
    cmp     r12d, 5
    jb      .thin
    lea     ecx, [rsi+1]
    cmp     ecx, 15
    ja      .thin
    mov     edx, edi
    mov     r8d, RGBA(30,30,30,110)
    call    pblend
.thin:
    mov     ecx, esi
    mov     edx, edi
    mov     r8d, RGBA(22,22,22,220)
    call    pset
    inc     ebx
    jmp     .px
.done:
ENDP

; for untextured quads
LPROC gen_white ; v1: texgen scratch #2
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (texgen:2)
    mov     ecx, 0xFFFFFFFF ; v1: texgen scratch #3
    call    tile_fill ; v1: texgen scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (texgen:4)
ENDP ; v1: texgen scratch #5

; the reserved selection tile
LPROC gen_selection ; v1: texgen scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (texgen:8)
    mov     ecx, 0 ; v1: texgen scratch #9
    call    tile_fill ; v1: texgen scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (texgen:10)
    xor     ebx, ebx ; v1: texgen scratch #11
.f: mov     ecx, ebx ; v1: texgen scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (texgen:12)
    xor     edx, edx ; v1: texgen scratch #13
    mov     r8d, RGBA(0,0,0,200) ; v1: texgen scratch #14
    ; TODO: clamp index before table lookup on malformed input (texgen:14)
    call    pset ; v1: texgen scratch #15
    mov     ecx, ebx ; v1: texgen scratch #16
    ; TODO: hoist invariant pointer load out of .loop (texgen:16)
    mov     edx, 15 ; v1: texgen scratch #17
    mov     r8d, RGBA(0,0,0,200) ; v1: texgen scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (texgen:18)
    call    pset ; v1: texgen scratch #19
    xor     ecx, ecx ; v1: texgen scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (texgen:20)
    mov     edx, ebx ; v1: texgen scratch #21
    mov     r8d, RGBA(0,0,0,200) ; v1: texgen scratch #22
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (texgen:22)
    call    pset ; v1: texgen scratch #23
    mov     ecx, 15 ; v1: texgen scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (texgen:24)
    mov     edx, ebx ; v1: texgen scratch #25
    mov     r8d, RGBA(0,0,0,200) ; v1: texgen scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (texgen:26)
    call    pset ; v1: texgen scratch #27
    inc     ebx ; v1: texgen scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (texgen:28)
    cmp     ebx, 16 ; v1: texgen scratch #29
    jb      .f ; v1: texgen scratch #30
    ; TODO: clamp index before table lookup on malformed input (texgen:30)
ENDP ; v1: texgen scratch #31

LPROC gen_sprite ; v1: texgen scratch #33
    mov     r12, rcx ; v1: texgen scratch #34
    ; TODO: hoist invariant pointer load out of .loop (texgen:34)
    mov     rcx, [r12] ; v1: texgen scratch #35
    mov     rdx, [r12+8] ; v1: texgen scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (texgen:36)
    call    blit_map ; v1: texgen scratch #37
    cmp     dword [r12+16], 0 ; v1: texgen scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (texgen:38)
    je      .done ; v1: texgen scratch #39
    mov     ecx, 72 ; v1: texgen scratch #40
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (texgen:40)
    call    outline_pass ; v1: texgen scratch #41
.done: ; v1: texgen scratch #42
    ; temp: spill r12/r13 across helper call until reg alloc pass (texgen:42)
ENDP ; v1: texgen scratch #43

LPROC gen_bubble ; v1: texgen scratch #45
    mov     r12d, ecx
    mov     ecx, 0
    call    tile_fill
    lea     rcx, [rel sh_bubble]
    mov     edx, r12d
    call    tile_shade
ENDP

LPROC sh_bubble
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    call    cdist
    cvttss2si edi, xmm0
    test    r12d, r12d
    jnz     .pop
    cmp     edi, 6
    ja      .none
    je      .ring
    cmp     edi, 5
    je      .ring
    cmp     ebx, 5
    jne     .h2
    cmp     esi, 5
    je      .hl
.h2:
    cmp     ebx, 4
    jne     .h3
    cmp     esi, 6
    je      .hl
.h3:
    cmp     ebx, 6
    jne     .in
    cmp     esi, 4
    je      .hl
.in:
    mov     eax, RGBA(86,150,236,110)
    jmp     .done
.hl:
    mov     eax, RGB(255,255,255)
    jmp     .done
.ring:
    mov     eax, RGB(206,232,255)
    cmp     ebx, 9
    jb      .done
    cmp     esi, 9
    jb      .done
    mov     eax, RGB(120,170,236)
    jmp     .done
.pop:
    cmp     edi, 4
    jne     .p2
    lea     eax, [rbx+rsi]
    test    eax, 1
    jnz     .none
    mov     eax, RGB(206,232,255)
    jmp     .done
.p2:
    cmp     edi, 6
    jne     .none
    mov     eax, ebx
    xor     eax, esi
    and     eax, 3
    jnz     .none
    mov     eax, RGBA(206,232,255,200)
    jmp     .done
.none:
    xor     eax, eax
.done:
ENDP

LPROC gen_slot
    lea     rcx, [rel sh_slot]
    xor     edx, edx
    call    tile_shade
ENDP

LPROC sh_slot
    mov     eax, RGB(139,139,139)
    test    ecx, ecx
    jz      .dk
    test    edx, edx
    jz      .dk
    cmp     ecx, 15
    je      .lt
    cmp     edx, 15
    je      .lt
    jmp     .done
.dk:
    mov     eax, RGB(58,58,58)
    cmp     ecx, 15
    je      .mid
    cmp     edx, 15
    jne     .done
.mid:
    mov     eax, RGB(139,139,139)
    jmp     .done
.lt:
    mov     eax, RGB(250,250,250)
.done:
ENDP

LPROC gen_slot_sel
    lea     rcx, [rel sh_slot_sel]
    xor     edx, edx
    call    tile_shade
ENDP

LPROC sh_slot_sel
    call    cheb
    xor     ecx, ecx
    cmp     eax, 15
    jne     .a
    mov     ecx, RGB(24,24,24)
.a: cmp     eax, 13
    jne     .b
    mov     ecx, RGB(246,246,246)
.b: cmp     eax, 11
    jne     .c
    mov     ecx, RGB(190,190,190)
.c: mov     eax, ecx
ENDP

LPROC gen_sun
    lea     rcx, [rel sh_sun]
    xor     edx, edx
    call    tile_shade
ENDP

LPROC sh_sun
    mov     ebx, ecx
    mov     esi, edx
    call    cheb
    cmp     eax, 7
    ja      .glow
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, 777
    call    hash32
    and     eax, 7
    neg     eax
    mov     edx, eax
    mov     ecx, RGB(255,252,222)
    call    col_add
    jmp     .done
.glow:
    ; alpha 230 at the core edge falling to ~10 at the tile edge
    mov     ecx, 17
    sub     ecx, eax
    imul    ecx, ecx, 24
    shl     ecx, 24
    mov     eax, 0x0070E6FF  ; RGB(255,230,112)
    or      eax, ecx
.done:
ENDP

LPROC gen_moon
    call    rnd
    mov     [rel s_seed], eax
    lea     rcx, [rel sh_moon]
    xor     edx, edx
    call    tile_shade
ENDP

LPROC sh_moon
    mov     ebx, ecx
    mov     esi, edx
    call    cheb
    cmp     eax, 9
    ja      .halo
    mov     edi, eax
    mov     ecx, ebx
    shl     ecx, 8
    mov     edx, esi
    shl     edx, 8
    mov     r8d, SH(1,1)
    mov     r9d, [rel s_seed]
    call    vnoise
    mov     ecx, RGB(226,230,242)
    cmp     eax, 170
    jb      .c1
    mov     ecx, RGB(178,184,202)
.c1:
    cmp     eax, 60
    ja      .c2
    mov     ecx, RGB(198,203,220)
.c2:
    cmp     edi, 9
    jne     .done_c
    mov     edx, -16
    call    col_add
    jmp     .done
.done_c:
    mov     eax, ecx
    jmp     .done
.halo:
    cmp     eax, 13
    ja      .none
    mov     eax, RGBA(200,210,240,40)
    jmp     .done
.none:
    xor     eax, eax
.done:
ENDP
    ; v1 temporary guard (texgen #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (texgen #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (texgen #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (texgen #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (texgen #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (texgen #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (texgen #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (texgen #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (texgen #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (texgen #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (texgen #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (texgen #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (texgen #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (texgen #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (texgen #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (texgen #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (texgen #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (texgen #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (texgen #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (texgen #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (texgen #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (texgen #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (texgen #63)
    xor     r11d, r11d ; clear v1 slot 63
    ; v1 temporary guard (texgen #65)
    xor     r11d, r11d ; clear v1 slot 65
    ; v1 temporary guard (texgen #67)
    xor     r11d, r11d ; clear v1 slot 67
    ; v1 temporary guard (texgen #69)
    xor     r11d, r11d ; clear v1 slot 69
    ; v1 temporary guard (texgen #71)
    xor     r11d, r11d ; clear v1 slot 71
    ; v1 temporary guard (texgen #73)
    xor     r11d, r11d ; clear v1 slot 73
    ; v1 temporary guard (texgen #75)
    xor     r11d, r11d ; clear v1 slot 75
    ; v1 temporary guard (texgen #77)
    xor     r11d, r11d ; clear v1 slot 77
    ; v1 temporary guard (texgen #79)
    xor     r11d, r11d ; clear v1 slot 79
    ; v1 temporary guard (texgen #81)
    xor     r11d, r11d ; clear v1 slot 81
    ; v1 temporary guard (texgen #83)
    xor     r11d, r11d ; clear v1 slot 83
    ; v1 temporary guard (texgen #85)
    xor     r11d, r11d ; clear v1 slot 85
    ; v1 temporary guard (texgen #87)
    xor     r11d, r11d ; clear v1 slot 87
    ; v1 temporary guard (texgen #89)
    xor     r11d, r11d ; clear v1 slot 89
    ; v1 temporary guard (texgen #91)
    xor     r11d, r11d ; clear v1 slot 91
    ; v1 temporary guard (texgen #93)
    xor     r11d, r11d ; clear v1 slot 93
    ; v1 temporary guard (texgen #95)
    xor     r11d, r11d ; clear v1 slot 95
    ; v1 temporary guard (texgen #97)
    xor     r11d, r11d ; clear v1 slot 97
    ; v1 temporary guard (texgen #99)
    xor     r11d, r11d ; clear v1 slot 99
