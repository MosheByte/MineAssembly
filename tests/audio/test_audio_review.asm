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
PROCX steal_declick, 32
    TEST "voice stealing de-click"
    xorps   xmm0, xmm0
    call    ah_set_music
    FLOAD   xmm0, 1.0
    call    ah_set_sfx
    mov     ecx, FS*6
    call    ah_mix_discard
    call    audio_dbg_active_voices
    CHECK_EQ32 eax, 0, "voices left over before the steal test"
    ; oldest voice: loud thunder slowed 10x (smooth, < 100 Hz), 31 near-silent
    ; ones fill the rest of the pool
    mov     ecx, SFX_THUNDER
    FLOAD   xmm1, 0.5
    FLOAD   xmm2, 0.1
    call    sfx_play
    xor     ebx, ebx
.fill:
    mov     ecx, SFX_THUNDER
    FLOAD   xmm1, 1e-5
    FLOAD   xmm2, 0.1
    call    sfx_play
    inc     ebx
    cmp     ebx, 31
    jb      .fill
    lea     rdi, [rel outb]
    mov     ecx, STEAL_FRAMES*2
    xor     eax, eax
    rep     stosw
    lea     rcx, [rel outb]
    mov     edx, 4096
    call    audio_dbg_mix
    mov     r12d, 4096
    ; step 64 frames at a time till the loud voice is well away from zero
    lea     rsi, [rel outb]
.seek:
    movsx   eax, word [rsi+r12*4-4]
    mov     ecx, eax
    neg     ecx
    cmovl   ecx, eax
    cmp     ecx, 2500
    jge     .found
    cmp     r12d, FS
    jge     .found
    lea     rcx, [rsi+r12*4]
    mov     edx, 64
    call    audio_dbg_mix
    add     r12d, 64
    jmp     .seek
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

PROC muted, 0
    TEST "muted requests use no voice"
    xorps   xmm0, xmm0
    call    ah_set_music
    xorps   xmm0, xmm0
    call    ah_set_sfx
    PLAYER_AT 0.0, 0.0, 0.0, 0.0
    mov     ecx, SFX_EXPLODE
    FLOAD   xmm1, 1.0
    FLOAD   xmm2, 1.0
    call    sfx_play
    mov     ecx, SFX_EXPLODE
    FLOAD   xmm1, 3.0
    FLOAD   xmm2, 1.62
    xorps   xmm3, xmm3
    call    sfx_play_at
    lea     rcx, [rel outb]
    mov     edx, 1024
    call    audio_dbg_mix
    call    audio_dbg_active_voices
    CHECK_EQ32 eax, 0, "muted sounds started voices"
    FLOAD   xmm0, 1.0
    call    ah_set_sfx
    mov     ecx, SFX_EXPLODE
    xorps   xmm1, xmm1
    FLOAD   xmm2, 1.0
    call    sfx_play
    lea     rcx, [rel outb]
    mov     edx, 1024
    call    audio_dbg_mix
    call    audio_dbg_active_voices
    CHECK_EQ32 eax, 0, "volume 0 sfx_play started a voice"
ENDP

; voices used to get killed while the smoothed level was still ~3% of full scale
PROCX music_fade_end, 32
    TEST "music fade-out ends silently"
    FLOAD   xmm0, 1.0
    call    ah_set_music
    FLOAD   xmm0, 1.0
    call    ah_set_sfx
    SETI32  g_world_active, 0
    call    music_init
    lea     rcx, [rel info]
    call    music_dbg_info
    mov     ebx, [rel info+20]
    lea     rcx, [rel info]
    mov     edx, ebx
    call    ah_wait_music_start
    lea     r10d, [rbx+1]
    CHECK_EQ32 [rel info+20], r10d, "title theme not requested"
    lea     rdi, [rel outb]
    mov     ecx, FADE_FRAMES*2
    xor     eax, eax
    rep     stosw
    lea     rcx, [rel outb]
    mov     edx, FS*3
    call    audio_dbg_mix
    call    music_dbg_state
    CHECK_EQ32 eax, 1, "title theme not playing"
    lea     rcx, [rel outb]
    mov     edx, FS*3*2
    mov     r8d, 1
    call    ah_i16_absmax
    cvtsi2sd xmm6, eax
    SETI32  g_world_active, 1
    SETI32  g_state, ST_PLAYING
    SETI32  g_time_of_day, 6000
    PLAYER_AT 0.0, 80.0, 0.0, 0.0
    call    music_tick
    lea     rdi, [rel outb]
    mov     ecx, FADE_FRAMES*2
    xor     eax, eax
    rep     stosw
    lea     rcx, [rel outb]
    mov     edx, FS*4
    call    audio_dbg_mix
    call    music_dbg_state
    CHECK_EQ32 eax, 0, "fade did not finish in 4 s"
    ; end level = max(|L|,|R|) over the last 5 ms (221 frames) up to the last
    ; non-zero frame
    lea     rsi, [rel outb]
    mov     r12d, FS*4
.back:
    dec     r12d
    js      .none
    mov     eax, [rsi+r12*4]
    test    eax, eax                    ; both channels zero
    jz      .back
    lea     eax, [r12-220]
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    lea     rcx, [rsi+rax*4]
    mov     edx, r12d
    sub     edx, eax
    inc     edx
    lea     r8d, [rdx+rdx]
    mov     edx, r8d
    mov     r8d, 1
    call    ah_i16_absmax
    cvtsi2sd xmm7, eax
    jmp     .rep
.none:
    xor     r12d, r12d
    xorpd   xmm7, xmm7
.rep:
    PRINT   "  title peak "
    movsd   xmm0, xmm6
    xor     edx, edx
    call    t_print_double
    PRINT   ", fade ended after "
    cvtsi2sd xmm0, r12d
    DLOAD   xmm1, 44100.0
    divsd   xmm0, xmm1
    mov     edx, 2
    call    t_print_double
    PRINT   " s, level in the last 5 ms "
    movsd   xmm0, xmm7
    xor     edx, edx
    call    t_print_double
    call    t_newline
    DLOAD   xmm0, 3000.0
    xor     eax, eax
    comisd  xmm6, xmm0
    seta    al
    CHECK_TRUE eax, "title theme too quiet for the fade test"
    DLOAD   xmm0, 40.0
    xor     eax, eax
    comisd  xmm7, xmm0
    setbe   al
    CHECK_TRUE eax, "fade ends with an audible step (> 40)"
    SETI32  g_world_active, 0
ENDPX
