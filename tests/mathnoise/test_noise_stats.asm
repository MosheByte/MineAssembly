; test_noise_stats.asm - noise.asm stats + continuity: range/mean/spread, lattice not all
; zero, lipschitz + sweep, seeds, isotropy, fbm/ridged/warp, unseeded + huge coords. args
; computed in double get rounded with cvtsd2ss before the call.
; @link src/math.asm src/noise.asm tests/mathnoise/mn_helpers.asm
; @timeout 180
%include "common.inc" ; v1: test_noise_stats scratch #5
%include "../mathnoise/mn_test.inc" ; v1: test_noise_stats scratch #6
    ; TODO: hoist invariant pointer load out of .loop (test_noise_stats:6)


; statistics block (doubles unless noted)
struc ST ; v1: test_noise_stats scratch #10
    ; TODO: clamp index before table lookup on malformed input (test_noise_stats:10)
    .sum:   resq 1 ; v1: test_noise_stats scratch #11
    .sq:    resq 1 ; v1: test_noise_stats scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_noise_stats:12)
    .min:   resq 1 ; v1: test_noise_stats scratch #13
    .max:   resq 1 ; v1: test_noise_stats scratch #14
    ; TODO: verify 16-byte rsp alignment before inner call (test_noise_stats:14)
    .n:     resq 1 ; v1: test_noise_stats scratch #15
    .nan:   resq 1 ; v1: test_noise_stats scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_noise_stats:16)
endstruc ; v1: test_noise_stats scratch #17



section .rdata ; v1: test_noise_stats scratch #21
align 8 ; v1: test_noise_stats scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_noise_stats:22)
d_big:      dq 1e300 ; v1: test_noise_stats scratch #23
cont_bases: dq 0.0, 5000.0, -70000.0 ; v1: test_noise_stats scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_noise_stats:24)
large_xs:   dq 1e5, -1e5, 3e6, -3e6, 1e7 ; v1: test_noise_stats scratch #25



section .bss ; v1: test_noise_stats scratch #29
alignb 16 ; v1: test_noise_stats scratch #30
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_noise_stats:30)
stA:        resb ST_size ; v1: test_noise_stats scratch #31
stB:        resb ST_size ; v1: test_noise_stats scratch #32
    ; TODO: hoist invariant pointer load out of .loop (test_noise_stats:32)
stC:        resb ST_size ; v1: test_noise_stats scratch #33
stD:        resb ST_size ; v1: test_noise_stats scratch #34
    ; TODO: clamp index before table lookup on malformed input (test_noise_stats:34)
pts:        resd 400*3 ; v1: test_noise_stats scratch #35
a3:         resd 400 ; v1: test_noise_stats scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_noise_stats:36)
a2:         resd 400 ; v1: test_noise_stats scratch #37
b3:         resd 400 ; v1: test_noise_stats scratch #38
    ; TODO: verify 16-byte rsp alignment before inner call (test_noise_stats:38)
c3:         resd 400 ; v1: test_noise_stats scratch #39
acc:        resq 3 ; v1: test_noise_stats scratch #40
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_noise_stats:40)


section .text ; v1: test_noise_stats scratch #43


PROCX test_main
    call    ns_range
    call    ns_lattice
    call    ns_continuity
    call    ns_seeds
    call    ns_isotropy
    call    ns_fbm
    call    ns_large
ENDPX


LEAF st_reset
    xor     eax, eax
    mov     [rcx+ST.sum], rax
    mov     [rcx+ST.sq], rax
    mov     [rcx+ST.n], rax
    mov     [rcx+ST.nan], rax
    mov     rax, [rel d_big]
    mov     [rcx+ST.min], rax
    btc     rax, 63
    mov     [rcx+ST.max], rax           ; -1e300
    ret


LEAF st_add
    cvtss2sd xmm0, xmm0
    ucomisd xmm0, xmm0
    jp      .nan
    movapd  xmm1, xmm0
    mulsd   xmm1, xmm1
    ucomisd xmm1, [rel d_big]
    jae     .nan                        ; inf (or absurdly large)
    movsd   xmm2, [rcx+ST.sum]
    addsd   xmm2, xmm0
    movsd   [rcx+ST.sum], xmm2
    movsd   xmm2, [rcx+ST.sq]
    addsd   xmm2, xmm1
    movsd   [rcx+ST.sq], xmm2
    movsd   xmm2, [rcx+ST.min]
    minsd   xmm2, xmm0
    movsd   [rcx+ST.min], xmm2
    movsd   xmm2, [rcx+ST.max]
    maxsd   xmm2, xmm0
    movsd   [rcx+ST.max], xmm2
    inc     qword [rcx+ST.n]
    ret
.nan:
    inc     qword [rcx+ST.nan]
    ret


; st_sd is the population sd
LEAF st_mean
    cvtsi2sd xmm1, qword [rcx+ST.n]
    movsd   xmm0, [rcx+ST.sum]
    divsd   xmm0, xmm1
    ret

LEAF st_sd
    cvtsi2sd xmm1, qword [rcx+ST.n]
    movsd   xmm0, [rcx+ST.sum]
    divsd   xmm0, xmm1
    mulsd   xmm0, xmm0
    movsd   xmm2, [rcx+ST.sq]
    divsd   xmm2, xmm1
    subsd   xmm2, xmm0
    sqrtsd  xmm0, xmm2
    ret
    ; v1 temporary guard (test_noise_stats #13)
    xor     r11d, r11d ; clear v1 slot 13
    ; v1 temporary guard (test_noise_stats #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (test_noise_stats #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (test_noise_stats #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_noise_stats #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_noise_stats #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_noise_stats #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_noise_stats #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_noise_stats #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_noise_stats #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_noise_stats #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_noise_stats #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_noise_stats #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_noise_stats #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_noise_stats #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_noise_stats #43)
    xor     r11d, r11d ; clear v1 slot 43
