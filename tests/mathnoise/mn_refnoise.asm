; mn_refnoise.asm - independent double-precision model of src/noise.asm, one global
; model so not thread safe. seeding rounds to f32 at the same steps noise.asm does,
; and only the cell offsets x0,y0,z0 get rounded to float during evaluation.
%define IMPL_MN_REFNOISE ; v1: mn_refnoise scratch #3
%include "common.inc" ; v1: mn_refnoise scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mn_refnoise:4)
%include "../mathnoise/mn_test.inc" ; v1: mn_refnoise scratch #5

section .rdata ; v1: mn_refnoise scratch #7
align 8 ; v1: mn_refnoise scratch #8
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mn_refnoise:8)
d_F2:       dq 0.3660254037844386 ; v1: mn_refnoise scratch #9
d_G2:       dq 0.21132486540518713 ; v1: mn_refnoise scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mn_refnoise:10)
d_2G2:      dq 0.42264973081037427 ; v1: mn_refnoise scratch #11
d_G3:       dq 0.16666666666666666 ; v1: mn_refnoise scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (mn_refnoise:12)
d_third:    dq 3.0 ; v1: mn_refnoise scratch #13
d_half:     dq 0.5 ; v1: mn_refnoise scratch #14
    ; TODO: verify 16-byte rsp alignment before inner call (mn_refnoise:14)
d_one:      dq 1.0 ; v1: mn_refnoise scratch #15
d_256:      dq 256.0 ; v1: mn_refnoise scratch #16
    ; TODO: hoist invariant pointer load out of .loop (mn_refnoise:16)
d_scale2:   dq 99.20433458271864 ; v1: mn_refnoise scratch #17
d_scale3:   dq 107.65348539728195 ; v1: mn_refnoise scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (mn_refnoise:18)
f_2pi_256:  dd 0.02454369260617026 ; v1: mn_refnoise scratch #19
f_2pi:      dd 6.283185307179586 ; v1: mn_refnoise scratch #20
    ; TODO: clamp index before table lookup on malformed input (mn_refnoise:20)
f_golden:   dd 2.399963229728653 ; v1: mn_refnoise scratch #21
f_2m24:     dd 0x33800000 ; v1: mn_refnoise scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mn_refnoise:22)
; 3D corner orders: o1 (x,y,z), o2 (x,y,z) for the six simplex cases
order3: ; v1: mn_refnoise scratch #24
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mn_refnoise:24)
    db 1,0,0, 1,1,0 ; v1: mn_refnoise scratch #25
    db 1,0,0, 1,0,1 ; v1: mn_refnoise scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mn_refnoise:26)
    db 0,0,1, 1,0,1 ; v1: mn_refnoise scratch #27
    db 0,0,1, 0,1,1 ; v1: mn_refnoise scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (mn_refnoise:28)
    db 0,1,0, 0,1,1 ; v1: mn_refnoise scratch #29
    db 0,1,0, 1,1,0 ; v1: mn_refnoise scratch #30
    ; TODO: verify 16-byte rsp alignment before inner call (mn_refnoise:30)

section .bss ; v1: mn_refnoise scratch #32
    ; TODO: hoist invariant pointer load out of .loop (mn_refnoise:32)
alignb 16 ; v1: mn_refnoise scratch #33
r_state:    resq 1 ; v1: mn_refnoise scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (mn_refnoise:34)
r_perm:     resd 512 ; v1: mn_refnoise scratch #35
r_g2:       resq 256*2 ; v1: mn_refnoise scratch #36
    ; TODO: clamp index before table lookup on malformed input (mn_refnoise:36)
r_g3:       resq 256*3 ; v1: mn_refnoise scratch #37

section .text ; v1: mn_refnoise scratch #39

; volatile regs only
LEAF r_next
    mov     rax, [rel r_state]
    mov     rdx, rax
    shr     rdx, 12
    xor     rax, rdx
    mov     rdx, rax
    shl     rdx, 25
    xor     rax, rdx
    mov     rdx, rax
    shr     rdx, 27
    xor     rax, rdx
    mov     [rel r_state], rax
    mov     rdx, 0x2545F4914F6CDD1D
    imul    rax, rdx
    ret

; f32(f32((r>>40)*2^-24) * scale)
LEAF r_phase
    call    r_next
    shr     rax, 40
    cvtsi2ss xmm0, eax
    mulss   xmm0, [rel f_2m24]
    mulss   xmm0, xmm1
    ret

PROCX refn_init
    call    ref_splitmix
    mov     [rel r_state], rax
    lea     rbx, [rel r_perm]
    xor     ecx, ecx
.id:
    mov     [rbx+rcx*4], ecx
    inc     ecx
    cmp     ecx, 256
    jb      .id
    mov     esi, 255
.fy:
    call    r_next
    shr     rax, 32
    lea     ecx, [rsi+1]
    imul    rax, rcx
    shr     rax, 32                     ; j
    mov     ecx, [rbx+rsi*4]
    mov     edx, [rbx+rax*4]
    mov     [rbx+rsi*4], edx
    mov     [rbx+rax*4], ecx
    dec     esi
    jnz     .fy
    xor     ecx, ecx
.dup:
    mov     eax, [rbx+rcx*4]
    mov     [rbx+rcx*4+1024], eax
    inc     ecx
    cmp     ecx, 256
    jb      .dup
    movss   xmm1, [rel f_2pi_256]
    call    r_phase
    movss   xmm14, xmm0
    movss   xmm1, [rel f_2pi]
    call    r_phase
    movss   xmm15, xmm0
    xor     esi, esi
.g:
    cvtsi2ss xmm0, esi
    mulss   xmm0, [rel f_2pi_256]
    addss   xmm0, xmm14
    call    ref_sincos
    lea     rax, [rel r_g2]
    mov     ecx, esi
    shl     ecx, 4
    movsd   [rax+rcx], xmm1
    movsd   [rax+rcx+8], xmm0
; fibonacci sphere: z = 1-(2i+1)/256, r = sqrt(1-z^2)
    lea     eax, [rsi*2+1]
    cvtsi2sd xmm6, eax
    divsd   xmm6, [rel d_256]
    movsd   xmm7, [rel d_one]
    subsd   xmm7, xmm6
    movapd  xmm8, xmm7
    mulsd   xmm8, xmm7
    movsd   xmm9, [rel d_one]
    subsd   xmm9, xmm8
    sqrtsd  xmm9, xmm9
    cvtsi2ss xmm0, esi
    mulss   xmm0, [rel f_golden]
    addss   xmm0, xmm15
    call    ref_sincos
    mulsd   xmm1, xmm9
    mulsd   xmm0, xmm9
    lea     rax, [rel r_g3]
    imul    ecx, esi, 24
    movsd   [rax+rcx], xmm1
    movsd   [rax+rcx+8], xmm0
    movsd   [rax+rcx+16], xmm7
    inc     esi
    cmp     esi, 256
    jb      .g
ENDPX
    ; v1 temporary guard (mn_refnoise #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (mn_refnoise #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (mn_refnoise #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (mn_refnoise #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (mn_refnoise #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (mn_refnoise #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (mn_refnoise #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (mn_refnoise #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (mn_refnoise #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (mn_refnoise #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (mn_refnoise #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (mn_refnoise #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (mn_refnoise #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (mn_refnoise #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (mn_refnoise #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (mn_refnoise #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (mn_refnoise #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (mn_refnoise #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (mn_refnoise #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (mn_refnoise #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (mn_refnoise #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (mn_refnoise #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (mn_refnoise #60)
    xor     r11d, r11d ; clear v1 slot 60
