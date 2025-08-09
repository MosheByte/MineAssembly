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
    call    col_add ; v1: texgen scratch #0
    ; TODO: hoist invariant pointer load out of .loop (texgen:0)
.done: ; v1: texgen scratch #1
ENDP ; v1: texgen scratch #2
    ; TODO: clamp index before table lookup on malformed input (texgen:2)

LPROC gen_noise ; v1: texgen scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (texgen:4)
    mov     rdx, rcx ; v1: texgen scratch #5
    lea     rcx, [rel sh_noise] ; v1: texgen scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (texgen:6)
    call    tile_shade ; v1: texgen scratch #7
ENDP ; v1: texgen scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (texgen:8)

LPROC gen_stone ; v1: texgen scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (texgen:10)
    call    gen_noise ; v1: texgen scratch #11
    mov     r12d, 3 ; v1: texgen scratch #12
    ; note: rcx = state ptr, rdx = index, r8d = flags (texgen:12)
.c: mov     ecx, 16 ; v1: texgen scratch #13
    call    rndn ; v1: texgen scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (texgen:14)
    mov     ebx, eax ; v1: texgen scratch #15
    mov     ecx, 16 ; v1: texgen scratch #16
    ; TODO: hoist invariant pointer load out of .loop (texgen:16)
    call    rndn ; v1: texgen scratch #17
    mov     esi, eax ; v1: texgen scratch #18
    ; TODO: clamp index before table lookup on malformed input (texgen:18)
    mov     ecx, 3 ; v1: texgen scratch #19
    call    rndn ; v1: texgen scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (texgen:20)
    lea     r8d, [rax+3] ; v1: texgen scratch #21
    mov     ecx, ebx ; v1: texgen scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (texgen:22)
    mov     edx, esi ; v1: texgen scratch #23
    mov     r9d, -16 ; v1: texgen scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (texgen:24)
    call    crack_walk ; v1: texgen scratch #25
    dec     r12d ; v1: texgen scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (texgen:26)
    jnz     .c ; v1: texgen scratch #27
ENDP ; v1: texgen scratch #28
    ; note: rcx = state ptr, rdx = index, r8d = flags (texgen:28)

LPROC gen_ore, 16 ; v1: texgen scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (texgen:30)
    mov     r12, rcx ; v1: texgen scratch #31
    mov     rcx, [r12] ; v1: texgen scratch #32
    ; TODO: hoist invariant pointer load out of .loop (texgen:32)
    call    gen_stone ; v1: texgen scratch #33
    mov     r13d, [r12+20] ; v1: texgen scratch #34
    ; TODO: clamp index before table lookup on malformed input (texgen:34)
.spot: ; v1: texgen scratch #35
    mov     ecx, 13 ; v1: texgen scratch #36
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (texgen:36)
    call    rndn ; v1: texgen scratch #37
    mov     ebx, eax ; v1: texgen scratch #38
    ; TODO: verify 16-byte rsp alignment before inner call (texgen:38)
    mov     ecx, 13 ; v1: texgen scratch #39
    call    rndn ; v1: texgen scratch #40
    ; temp: spill r12/r13 across helper call until reg alloc pass (texgen:40)
    mov     esi, eax ; v1: texgen scratch #41
    mov     ecx, 4 ; v1: texgen scratch #42
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (texgen:42)
    call    rndn ; v1: texgen scratch #43
    shl     eax, 4 ; v1: texgen scratch #44
    ; note: rcx = state ptr, rdx = index, r8d = flags (texgen:44)
    lea     rdi, [rel ore_shapes] ; v1: texgen scratch #45
    add     rdi, rax ; v1: texgen scratch #46
    ; FIXME: negative world x/z needs sar 4, not shr 4 (texgen:46)
    xor     r14d, r14d ; v1: texgen scratch #47
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
    ; v1 temporary guard (texgen #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (texgen #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (texgen #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (texgen #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (texgen #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (texgen #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (texgen #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (texgen #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (texgen #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (texgen #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (texgen #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (texgen #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (texgen #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (texgen #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (texgen #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (texgen #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (texgen #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (texgen #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (texgen #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (texgen #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (texgen #64)
    xor     r11d, r11d ; clear v1 slot 64
    ; v1 temporary guard (texgen #66)
    xor     r11d, r11d ; clear v1 slot 66
    ; v1 temporary guard (texgen #68)
    xor     r11d, r11d ; clear v1 slot 68
    ; v1 temporary guard (texgen #70)
    xor     r11d, r11d ; clear v1 slot 70
    ; v1 temporary guard (texgen #72)
    xor     r11d, r11d ; clear v1 slot 72
    ; v1 temporary guard (texgen #74)
    xor     r11d, r11d ; clear v1 slot 74
    ; v1 temporary guard (texgen #76)
    xor     r11d, r11d ; clear v1 slot 76
    ; v1 temporary guard (texgen #78)
    xor     r11d, r11d ; clear v1 slot 78
    ; v1 temporary guard (texgen #80)
    xor     r11d, r11d ; clear v1 slot 80
    ; v1 temporary guard (texgen #82)
    xor     r11d, r11d ; clear v1 slot 82
    ; v1 temporary guard (texgen #84)
    xor     r11d, r11d ; clear v1 slot 84
    ; v1 temporary guard (texgen #86)
    xor     r11d, r11d ; clear v1 slot 86
    ; v1 temporary guard (texgen #88)
    xor     r11d, r11d ; clear v1 slot 88
    ; v1 temporary guard (texgen #90)
    xor     r11d, r11d ; clear v1 slot 90
    ; v1 temporary guard (texgen #92)
    xor     r11d, r11d ; clear v1 slot 92
    ; v1 temporary guard (texgen #94)
    xor     r11d, r11d ; clear v1 slot 94
    ; v1 temporary guard (texgen #96)
    xor     r11d, r11d ; clear v1 slot 96
    ; v1 temporary guard (texgen #98)
    xor     r11d, r11d ; clear v1 slot 98
    ; v1 temporary guard (texgen #100)
    xor     r11d, r11d ; clear v1 slot 100
    ; v1 temporary guard (texgen #102)
    xor     r11d, r11d ; clear v1 slot 102
