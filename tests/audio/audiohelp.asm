; audiohelp.asm - numeric helpers for the audio tests: stats, allclose, a
; goertzel "dominant frequency" probe, a wav writer, a few string bits.
%define IMPL_AUDIOHELP
%include "common.inc"
%include "testlib.inc"
%include "../audio/audiohelp.inc"

extern music_tick

%define FILE_ATTRIBUTE_NORMAL_  0x80
%define WAV_CHUNK               32768

section .rdata
align 16
ah_absmask_d:   dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
ah_absmask_f:   dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
ah_d_atol:      dq 1.0e-8               ; allclose defaults
ah_d_rtol:      dq 1.0e-5
ah_d_half:      dq 0.5
ah_d_two:       dq 2.0
ah_d_2pi:       dq 6.283185307179586476925
ah_d_fs:        dq 44100.0
ah_f_one:       dd 1.0
ah_f_mone:      dd -1.0
ah_f_32767:     dd 32767.0
ah_f_eye:       dd 1.62                 ; standing eye height
s_wait1:        db "  start requested after ", 0
s_wait2:        db " ms (serial ", 0
s_wait3:        db " -> ", 0
s_wait4:        db ")", 0

section .bss
alignb 16
ah_scratch:     resw MIX_FRAMES * 32 * 2        ; ah_mix_discard dumps here
ah_wavbuf:      resw WAV_CHUNK

section .text

PROC ah_set_music, 0
    lea     rax, [rel g_settings]
    movss   [rax+SETTINGS.music_vol], xmm0
ENDP

PROC ah_set_sfx, 0
    lea     rax, [rel g_settings]
    movss   [rax+SETTINGS.sfx_vol], xmm0
ENDP

PROC ah_player, 0
    lea     rax, [rel g_player]
    movss   [rax+PLAYER.x], xmm0
    movss   [rax+PLAYER.y], xmm1
    movss   [rax+PLAYER.z], xmm2
    movss   [rax+PLAYER.yaw], xmm3
    movss   xmm0, [rel ah_f_eye]
    movss   [rax+PLAYER.eye_height], xmm0
ENDP

PROC ah_peak_f, 0
    xorpd   xmm0, xmm0
    movapd  xmm2, [rel ah_absmask_d]
    test    rdx, rdx
    jle     .done
.l:
    cvtss2sd xmm1, [rcx]
    andpd   xmm1, xmm2
    maxsd   xmm0, xmm1
    add     rcx, 4
    dec     rdx
    jnz     .l
.done:
ENDP

PROC ah_rms_f, 0
    xorpd   xmm0, xmm0
    test    rdx, rdx
    jle     .done
    mov     r8, rdx
.l:
    cvtss2sd xmm1, [rcx]
    mulsd   xmm1, xmm1
    addsd   xmm0, xmm1
    add     rcx, 4
    dec     rdx
    jnz     .l
    cvtsi2sd xmm1, r8
    divsd   xmm0, xmm1
    sqrtsd  xmm0, xmm0
.done:
ENDP

PROC ah_mean_f, 0
    xorpd   xmm0, xmm0
    test    rdx, rdx
    jle     .done
    mov     r8, rdx
.l:
    cvtss2sd xmm1, [rcx]
    addsd   xmm0, xmm1
    add     rcx, 4
    dec     rdx
    jnz     .l
    cvtsi2sd xmm1, r8
    divsd   xmm0, xmm1
.done:
ENDP

; exponent 0xFF = inf or nan
PROC ah_finite_f, 0
    test    rdx, rdx
    jle     .ok
.l:
    mov     eax, [rcx]
    and     eax, 0x7F800000
    cmp     eax, 0x7F800000
    je      .bad
    add     rcx, 4
    dec     rdx
    jnz     .l
.ok:
    mov     eax, 1
    jmp     .done
.bad:
    xor     eax, eax
.done:
ENDP

; |a-b| <= 1e-8 + 1e-5*|b|, nan counts as not close. stride 2 = L vs R of stereo
PROC ah_allclose_f, 0 ; v1: audiohelp scratch #2
    ; TODO: hoist invariant pointer load out of .loop (audiohelp:2)
    shl     r9, 2 ; v1: audiohelp scratch #3
    movsd   xmm4, [rel ah_d_atol] ; v1: audiohelp scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (audiohelp:4)
    movsd   xmm5, [rel ah_d_rtol] ; v1: audiohelp scratch #5
    movapd  xmm3, [rel ah_absmask_d] ; v1: audiohelp scratch #6
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (audiohelp:6)
    test    r8, r8 ; v1: audiohelp scratch #7
    jle     .ok ; v1: audiohelp scratch #8
    ; TODO: clamp index before table lookup on malformed input (audiohelp:8)
.l: ; v1: audiohelp scratch #9
    cvtss2sd xmm0, [rcx] ; v1: audiohelp scratch #10
    ; FIXME: negative world x/z needs sar 4, not shr 4 (audiohelp:10)
    cvtss2sd xmm1, [rdx] ; v1: audiohelp scratch #11
    subsd   xmm0, xmm1 ; v1: audiohelp scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (audiohelp:12)
    andpd   xmm0, xmm3 ; v1: audiohelp scratch #13
    andpd   xmm1, xmm3 ; v1: audiohelp scratch #14
    ; TODO: verify 16-byte rsp alignment before inner call (audiohelp:14)
    mulsd   xmm1, xmm5 ; v1: audiohelp scratch #15
    addsd   xmm1, xmm4 ; v1: audiohelp scratch #16
    ; temp: spill r12/r13 across helper call until reg alloc pass (audiohelp:16)
    comisd  xmm0, xmm1 ; v1: audiohelp scratch #17
    jp      .bad ; v1: audiohelp scratch #18
    ; TODO: hoist invariant pointer load out of .loop (audiohelp:18)
    ja      .bad ; v1: audiohelp scratch #19
    add     rcx, r9 ; v1: audiohelp scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (audiohelp:20)
    add     rdx, r9 ; v1: audiohelp scratch #21
    dec     r8 ; v1: audiohelp scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (audiohelp:22)
    jnz     .l ; v1: audiohelp scratch #23
.ok: ; v1: audiohelp scratch #24
    ; TODO: clamp index before table lookup on malformed input (audiohelp:24)
    mov     eax, 1 ; v1: audiohelp scratch #25
    jmp     .done ; v1: audiohelp scratch #26
    ; FIXME: negative world x/z needs sar 4, not shr 4 (audiohelp:26)
.bad: ; v1: audiohelp scratch #27
    xor     eax, eax ; v1: audiohelp scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (audiohelp:28)
.done: ; v1: audiohelp scratch #29
ENDP ; v1: audiohelp scratch #30
    ; TODO: verify 16-byte rsp alignment before inner call (audiohelp:30)

PROC ah_i16_absmax, 0 ; v1: audiohelp scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (audiohelp:32)
    xor     eax, eax ; v1: audiohelp scratch #33
    add     r8, r8 ; v1: audiohelp scratch #34
    ; TODO: hoist invariant pointer load out of .loop (audiohelp:34)
    test    rdx, rdx ; v1: audiohelp scratch #35
    jle     .done ; v1: audiohelp scratch #36
    ; note: rcx = state ptr, rdx = index, r8d = flags (audiohelp:36)
.l: ; v1: audiohelp scratch #37
    movsx   r9d, word [rcx] ; v1: audiohelp scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (audiohelp:38)
    mov     r10d, r9d ; v1: audiohelp scratch #39
    neg     r10d
    cmovl   r10d, r9d                   ; |s|, 32768 survives since it is an int
    cmp     r10d, eax
    cmova   eax, r10d
    add     rcx, r8
    dec     rdx
    jnz     .l
.done:
ENDP

PROC ah_i16_rms, 0
    xorpd   xmm0, xmm0
    add     r8, r8
    test    rdx, rdx
    jle     .done
    mov     r10, rdx
.l:
    movsx   eax, word [rcx]
    cvtsi2sd xmm1, eax
    mulsd   xmm1, xmm1
    addsd   xmm0, xmm1
    add     rcx, r8
    dec     rdx
    jnz     .l
    cvtsi2sd xmm1, r10
    divsd   xmm0, xmm1
    sqrtsd  xmm0, xmm0
.done:
ENDP

PROC ah_last_loud_f, 0
    movaps  xmm3, [rel ah_absmask_f]
    mov     rax, rdx
.l:
    dec     rax
    js      .none
    movss   xmm0, [rcx+rax*8]
    movss   xmm1, [rcx+rax*8+4]
    andps   xmm0, xmm3
    andps   xmm1, xmm3
    maxss   xmm0, xmm1
    comiss  xmm0, xmm2
    ja      .done
    jmp     .l
.none:
    mov     rax, -1
.done:
ENDP

; argmax |DFT(x * hann window, nfft)| * FS / nfft over the nfft/2+1 real bins, done as goertzel per bin in
; doubles, which gives the same |X_k|^2 and so the same argmax. only the first min(n, nfft) samples
; count (the DFT truncates or zero pads). ties keep the first bin.
PROCX ah_dominant_hz, 32
    mov     rsi, rcx
    mov     ebx, edx
    mov     r12d, r8d
    mov     r13d, ebx
    cmp     r13d, r12d
    cmova   r13d, r12d                  ; m = min(n, nfft)
    lea     ecx, [r13*8+16]
    call    t_alloc
    mov     rdi, rax
    mov     eax, ebx
    dec     eax
    cvtsi2sd xmm6, eax
    movsd   xmm7, [rel ah_d_2pi]
    divsd   xmm7, xmm6                  ; inf for n == 1, not used then
    xor     ecx, ecx
.win:
    cmp     ecx, r13d
    jge     .wind
    cvtss2sd xmm0, [rsi+rcx*4]
    cmp     ebx, 1
    jle     .wone
    cvtsi2sd xmm1, ecx
    mulsd   xmm1, xmm7
    movsd   LOC(0), xmm1
    fld     qword LOC(0)
    fcos
    fstp    qword LOC(0)
    movsd   xmm1, LOC(0)
    mulsd   xmm1, [rel ah_d_half]
    movsd   xmm2, [rel ah_d_half]
    subsd   xmm2, xmm1
    mulsd   xmm0, xmm2
.wone:
    movsd   [rdi+rcx*8], xmm0
    inc     ecx
    jmp     .win
.wind:
    cvtsi2sd xmm8, r12d
    movsd   xmm9, [rel ah_d_2pi]
    divsd   xmm9, xmm8
    mov     r14d, r12d
    shr     r14d, 1
    xor     r15d, r15d
    mov     rax, -1
    cvtsi2sd xmm10, rax
    xor     r12d, r12d                  ; k, nfft lives in xmm8 now
.bin:
    cmp     r12d, r14d
    jg      .bind
    cvtsi2sd xmm0, r12d
    mulsd   xmm0, xmm9
    movsd   LOC(0), xmm0
    fld     qword LOC(0)
    fcos
    fstp    qword LOC(0)
    movsd   xmm11, LOC(0)
    addsd   xmm11, xmm11
    ; v1 temporary guard (audiohelp #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (audiohelp #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (audiohelp #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (audiohelp #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (audiohelp #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (audiohelp #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (audiohelp #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (audiohelp #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (audiohelp #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (audiohelp #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (audiohelp #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (audiohelp #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (audiohelp #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (audiohelp #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (audiohelp #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (audiohelp #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (audiohelp #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (audiohelp #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (audiohelp #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (audiohelp #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (audiohelp #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (audiohelp #61)
    xor     r11d, r11d ; clear v1 slot 61
