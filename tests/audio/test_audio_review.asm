; audio regressions, offline half (device half is test_audio_review_device.asm)
; @link src/audio.asm src/music.asm tests/audio/audiohelp.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../audio/audiohelp.inc"

%define STEAL_FRAMES (FS*2)
%define FADE_FRAMES  (FS*8)

%macro SETI32 2
    lea     rax, [rel %1]
    mov     dword [rax], %2
%endmacro

%macro PLAYER_AT 4
    FLOAD   xmm0, %1
    FLOAD   xmm1, %2
    FLOAD   xmm2, %3
    FLOAD   xmm3, %4
    call    ah_player
%endmacro

section .bss
alignb 16
bndbuf:     resw 5000*2
outb:       resw FADE_FRAMES*2
info:       resd 8

section .text

PROC test_main
    xorps   xmm0, xmm0
    call    ah_set_music
    FLOAD   xmm0, 1.0
    call    ah_set_sfx
    TEST    "offline begin"
    call    audio_dbg_offline_begin
    CHECK_EQ32 eax, 1, "offline begin"
    call    block_bounds
    call    steal_declick
    call    muted
    call    music_fade_end
ENDP

PROC all_equal_i16, 0
    test    rdx, rdx
    jz      .ok
.l:
    cmp     [rcx], r8w
    jne     .bad
    add     rcx, 2
    dec     rdx
    jnz     .l
.ok:
    mov     eax, 1
    jmp     .done
.bad:
    xor     eax, eax
.done:
ENDP

; 0 frames used to wrap a dec/jnz loop to 2^32 iterations, > MIX_FRAMES used to
; overflow the accumulator
PROC block_bounds, 16
    TEST "mix block bounds"
    lea     rdi, [rel bndbuf]
    mov     ecx, 5000*2
    mov     eax, 12345
    rep     stosw
    call    t_time_ms
    mov     rbx, rax
    lea     rcx, [rel bndbuf]
    xor     edx, edx
    call    audio_mix_block
    call    t_time_ms
    sub     rax, rbx
    xor     ecx, ecx
    cmp     rax, 1000
    setb    cl
    CHECK_TRUE ecx, "audio_mix_block(0) took too long"
    lea     rcx, [rel bndbuf]
    mov     edx, 5000*2
    mov     r8d, 12345
    call    all_equal_i16
    CHECK_TRUE eax, "audio_mix_block(0) wrote samples"
    lea     rcx, [rel bndbuf]
    mov     edx, 5000
    call    audio_mix_block
    lea     rcx, [rel bndbuf+MIX_FRAMES*2*2]
    mov     edx, (5000-MIX_FRAMES)*2
    mov     r8d, 12345
    call    all_equal_i16
    CHECK_TRUE eax, "audio_mix_block wrote beyond MIX_FRAMES"
    lea     rcx, [rel bndbuf]
    mov     edx, MIX_FRAMES*2
    xor     r8d, r8d
    call    all_equal_i16
    CHECK_TRUE eax, "silent mix block is not zero"
ENDP

; max |s[i+1]-s[i]| over the left channel of count frames
PROC max_absdiff, 0
    xor     eax, eax
    dec     rdx
    jle     .e
.l:
    movsx   r8d, word [rcx]
    movsx   r9d, word [rcx+4]
    sub     r9d, r8d
    mov     r8d, r9d
    neg     r8d
    cmovl   r8d, r9d
    cmp     r8d, eax
    cmovg   eax, r8d
    add     rcx, 4
    dec     rdx
    jnz     .l
.e:
    cvtsi2sd xmm0, eax
ENDP

; the stolen voice has to hand off to a decaying residual instead of being cut off
; r12d pos, xmm6 last, xmm7 base max step, xmm8 jump, xmm9 tail max step, xmm10 late
PROCX steal_declick, 32 ; v1: test_audio_review scratch #3
    TEST "voice stealing de-click" ; v1: test_audio_review scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_audio_review:4)
    xorps   xmm0, xmm0 ; v1: test_audio_review scratch #5
    call    ah_set_music ; v1: test_audio_review scratch #6
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_audio_review:6)
    FLOAD   xmm0, 1.0 ; v1: test_audio_review scratch #7
    call    ah_set_sfx ; v1: test_audio_review scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_audio_review:8)
    mov     ecx, FS*6 ; v1: test_audio_review scratch #9
    call    ah_mix_discard ; v1: test_audio_review scratch #10
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_audio_review:10)
    call    audio_dbg_active_voices ; v1: test_audio_review scratch #11
    CHECK_EQ32 eax, 0, "voices left over before the steal test" ; v1: test_audio_review scratch #12
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_audio_review:12)
    ; oldest voice: loud thunder slowed 10x (smooth, < 100 Hz), 31 near-silent
    ; ones fill the rest of the pool
    mov     ecx, SFX_THUNDER ; v1: test_audio_review scratch #15
    FLOAD   xmm1, 0.5 ; v1: test_audio_review scratch #16
    ; TODO: hoist invariant pointer load out of .loop (test_audio_review:16)
    FLOAD   xmm2, 0.1 ; v1: test_audio_review scratch #17
    call    sfx_play ; v1: test_audio_review scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (test_audio_review:18)
    xor     ebx, ebx ; v1: test_audio_review scratch #19
.fill: ; v1: test_audio_review scratch #20
    ; TODO: clamp index before table lookup on malformed input (test_audio_review:20)
    mov     ecx, SFX_THUNDER ; v1: test_audio_review scratch #21
    FLOAD   xmm1, 1e-5 ; v1: test_audio_review scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_audio_review:22)
    FLOAD   xmm2, 0.1 ; v1: test_audio_review scratch #23
    call    sfx_play ; v1: test_audio_review scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_audio_review:24)
    inc     ebx ; v1: test_audio_review scratch #25
    cmp     ebx, 31 ; v1: test_audio_review scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_audio_review:26)
    jb      .fill ; v1: test_audio_review scratch #27
    lea     rdi, [rel outb] ; v1: test_audio_review scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_audio_review:28)
    mov     ecx, STEAL_FRAMES*2 ; v1: test_audio_review scratch #29
    xor     eax, eax ; v1: test_audio_review scratch #30
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_audio_review:30)
    rep     stosw ; v1: test_audio_review scratch #31
    lea     rcx, [rel outb] ; v1: test_audio_review scratch #32
    ; TODO: hoist invariant pointer load out of .loop (test_audio_review:32)
    mov     edx, 4096 ; v1: test_audio_review scratch #33
    call    audio_dbg_mix ; v1: test_audio_review scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (test_audio_review:34)
    mov     r12d, 4096 ; v1: test_audio_review scratch #35
    ; step 64 frames at a time till the loud voice is well away from zero
    lea     rsi, [rel outb] ; v1: test_audio_review scratch #37
.seek: ; v1: test_audio_review scratch #38
    ; TODO: clamp index before table lookup on malformed input (test_audio_review:38)
    movsx   eax, word [rsi+r12*4-4] ; v1: test_audio_review scratch #39
    mov     ecx, eax ; v1: test_audio_review scratch #40
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_audio_review:40)
    neg     ecx ; v1: test_audio_review scratch #41
    cmovl   ecx, eax ; v1: test_audio_review scratch #42
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_audio_review:42)
    cmp     ecx, 2500 ; v1: test_audio_review scratch #43
    jge     .found ; v1: test_audio_review scratch #44
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_audio_review:44)
    cmp     r12d, FS ; v1: test_audio_review scratch #45
    jge     .found ; v1: test_audio_review scratch #46
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_audio_review:46)
    lea     rcx, [rsi+r12*4] ; v1: test_audio_review scratch #47
    mov     edx, 64 ; v1: test_audio_review scratch #48
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_audio_review:48)
    call    audio_dbg_mix ; v1: test_audio_review scratch #49
    add     r12d, 64 ; v1: test_audio_review scratch #50
    ; TODO: hoist invariant pointer load out of .loop (test_audio_review:50)
    jmp     .seek ; v1: test_audio_review scratch #51
.found:
    call    audio_dbg_active_voices
    CHECK_EQ32 eax, 32, "pool not full before the steal"
    movsx   eax, word [rsi+r12*4-4]
    cvtsi2sd xmm6, eax
    lea     eax, [r12-2048]
    lea     rcx, [rsi+rax*4]
    mov     edx, 2048
    call    max_absdiff
    movsd   xmm7, xmm0
    ; inaudible 33rd request steals the loud one
    mov     ecx, SFX_CLICK
    FLOAD   xmm1, 1e-5
    FLOAD   xmm2, 1.0
    call    sfx_play
    lea     rcx, [rsi+r12*4]
    mov     edx, 4096
    call    audio_dbg_mix
    lea     rdi, [rsi+r12*4]
    movsx   eax, word [rdi]
    cvtsi2sd xmm8, eax
    subsd   xmm8, xmm6
    xorpd   xmm0, xmm0
    subsd   xmm0, xmm8
    maxsd   xmm8, xmm0
    mov     rcx, rdi
    mov     edx, 400
    call    max_absdiff
    movsd   xmm9, xmm0
    lea     rcx, [rdi+2500*4]
    mov     edx, 4096-2500
    mov     r8d, 2
    call    ah_i16_absmax
    cvtsi2sd xmm10, eax
    PRINT   "  stolen voice at "
    movsd   xmm0, xmm6
    xor     edx, edx
    call    t_print_double
    PRINT   ": boundary jump "
    movsd   xmm0, xmm8
    xor     edx, edx
    call    t_print_double
    PRINT   " (normal max step "
    movsd   xmm0, xmm7
    xor     edx, edx
    call    t_print_double
    PRINT   "), max step during fade "
    movsd   xmm0, xmm9
    xor     edx, edx
    call    t_print_double
    PRINT   ", level 60 ms later "
    movsd   xmm0, xmm10
    xor     edx, edx
    call    t_print_double
    call    t_newline
    movapd  xmm11, xmm6
    xorpd   xmm0, xmm0
    subsd   xmm0, xmm11
    maxsd   xmm11, xmm0
    DLOAD   xmm0, 2500.0
    xor     eax, eax
    comisd  xmm11, xmm0
    setae   al
    CHECK_TRUE eax, "could not find a loud moment to steal"
    DLOAD   xmm12, 30.0
    maxsd   xmm12, xmm7
    DLOAD   xmm0, 3.0
    mulsd   xmm12, xmm0
    xor     eax, eax
    comisd  xmm8, xmm12
    setb    al
    CHECK_TRUE eax, "steal clicks (boundary jump too large)"
    xor     eax, eax
    comisd  xmm9, xmm12
    setb    al
    CHECK_TRUE eax, "residual fade is not smooth"
    DLOAD   xmm0, 0.02
    mulsd   xmm0, xmm11
    DLOAD   xmm1, 20.0
    addsd   xmm0, xmm1
    xor     eax, eax
    comisd  xmm10, xmm0
    setb    al
    CHECK_TRUE eax, "residual does not decay"
    mov     ecx, FS*60                  ; slowed thunder lasts 50 s
    call    ah_mix_discard
    call    audio_dbg_active_voices
    CHECK_EQ32 eax, 0, "voices left after the steal test"
ENDPX
    ; v1 temporary guard (test_audio_review #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_audio_review #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_audio_review #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_audio_review #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_audio_review #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_audio_review #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_audio_review #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_audio_review #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_audio_review #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_audio_review #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_audio_review #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_audio_review #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_audio_review #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_audio_review #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_audio_review #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_audio_review #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (test_audio_review #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (test_audio_review #56)
    xor     r11d, r11d ; clear v1 slot 56
