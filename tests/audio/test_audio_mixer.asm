; offline mixer + music scheduler. offline_begin builds the bank with no device,
; so audio_dbg_mix runs the real mixer. writes audio_wav\mixer_capture.wav
; @link src/audio.asm src/music.asm tests/audio/audiohelp.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../audio/audiohelp.inc"

%define OUT_FRAMES  (FS*2)

; eax = (xmm cc literal), cc is a/ae/b/be
%macro DCMP 3
    DLOAD xmm5, %3
    xor     eax, eax
    comisd  %1, xmm5
    set%2   al
%endmacro

%macro SFX 3
    mov     ecx, %1
    FLOAD   xmm1, %2
    FLOAD   xmm2, %3
    call    sfx_play
%endmacro

%macro MIXOUT 1
    lea     rcx, [rel outb]
    mov     edx, %1
    call    audio_dbg_mix
%endmacro

%macro PLAYER_AT 4
    FLOAD   xmm0, %1
    FLOAD   xmm1, %2
    FLOAD   xmm2, %3
    FLOAD   xmm3, %4
    call    ah_player
%endmacro

%macro SETI32 2
    lea     rax, [rel %1]
    mov     dword [rax], %2
%endmacro

section .rdata
s_dir:      db "audio_wav", 0
s_cap:      db "audio_wav\mixer_capture.wav", 0

section .bss
alignb 16
outb:       resw OUT_FRAMES*2
info:       resd 8

section .text

PROC test_main
    lea     rcx, [rel s_dir]
    call    ah_mkdir
    call    mixer_test
    call    scheduler_test
ENDP

PROCX rms_lr, 0
    mov     rbx, rcx
    lea     rcx, [rel outb]
    mov     rdx, rbx
    mov     r8d, 2
    call    ah_i16_rms
    movsd   xmm6, xmm0
    lea     rcx, [rel outb+2]
    mov     rdx, rbx
    mov     r8d, 2
    call    ah_i16_rms
    movapd  xmm1, xmm0
    movsd   xmm0, xmm6
ENDPX

PROCX mixer_test, 32
    TEST "offline mixer"
    xorps   xmm0, xmm0
    call    ah_set_music
    FLOAD   xmm0, 1.0
    call    ah_set_sfx
    call    audio_dbg_offline_begin
    CHECK_EQ32 eax, 1, "offline begin"

    SFX     SFX_EXPLODE, 1.0, 1.0
    SFX     SFX_LEVELUP, 0.8, 1.0
    SFX     SFX_DIG_STONE, 1.0, 1.0
    SFX     SFX_BOAR, 0.7, 1.0
    MIXOUT  OUT_FRAMES
    lea     rcx, [rel outb]
    mov     edx, OUT_FRAMES*2
    mov     r8d, 1
    call    ah_i16_absmax
    cvtsi2sd xmm6, eax
    DLOAD   xmm0, 32767.0
    divsd   xmm6, xmm0
    call    audio_dbg_active_voices
    mov     ebx, eax
    PRINT   "  4 overlapping sounds: peak "
    movsd   xmm0, xmm6
    mov     edx, 3
    call    t_print_double
    PRINT   ", voices still active "
    mov     ecx, ebx
    call    t_print_int
    call    t_newline
    DCMP    xmm6, a, 0.3
    CHECK_TRUE eax, "mixer output silent"
    DCMP    xmm6, be, 1.0
    CHECK_TRUE eax, "mixer overflow"
    ; allclose on L/32767 vs R/32767: two different int16s are >= 3.05e-5 apart,
    ; way over the tolerance, so it boils down to L == R exactly
    lea     rsi, [rel outb]
    mov     ecx, OUT_FRAMES
    xor     ebx, ebx
.cen:
    mov     ax, [rsi]
    cmp     ax, [rsi+2]
    jne     .cbad
    add     rsi, 4
    dec     ecx
    jnz     .cen
    mov     ebx, 1
.cbad:
    CHECK_TRUE ebx, "centred sfx_play is not centred"
    lea     rcx, [rel s_cap]
    lea     rdx, [rel outb]
    mov     r8d, OUT_FRAMES*2
    mov     r9d, 2
    mov     qword [rsp+32], 0
    call    ah_write_wav
    MIXOUT  FS*2                        ; explode is 3 s
    MIXOUT  FS*2
    call    audio_dbg_active_voices
    CHECK_EQ32 eax, 0, "voices never end"

    xor     ebx, ebx
.many:
    ; pitch 0.8 + 0.01*i in double, rounded to float once
    cvtsi2sd xmm2, ebx
    DLOAD   xmm0, 0.01
    mulsd   xmm2, xmm0
    DLOAD   xmm0, 0.8
    addsd   xmm2, xmm0
    cvtsd2ss xmm2, xmm2
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 27
    div     ecx
    mov     ecx, edx
    FLOAD   xmm1, 1.0
    call    sfx_play
    inc     ebx
    cmp     ebx, 40
    jb      .many
    MIXOUT  256
    call    audio_dbg_active_voices
    mov     ebx, eax
    PRINT   "  40 requests -> "
    mov     ecx, ebx
    call    t_print_int
    PRINT   " voices"
    call    t_newline
    CHECK_EQ32 ebx, 32, "voice stealing: active voices != 32"
    MIXOUT  FS*2
    MIXOUT  FS*2
    MIXOUT  FS*2

    ; yaw 0 faces north, so +x is on the right
    PLAYER_AT 0.0, 0.0, 0.0, 0.0
    mov     ecx, SFX_DIG_STONE
    FLOAD   xmm1, 5.0
    FLOAD   xmm2, 1.62
    xorps   xmm3, xmm3
    call    sfx_play_at
    MIXOUT  8192
    mov     ecx, 8192
    call    rms_lr
    movsd   xmm6, xmm0
    movsd   xmm7, xmm1
    PRINT   "  source east of a north-facing listener: L "
    movsd   xmm0, xmm6
    xor     edx, edx
    call    t_print_double
    PRINT   " R "
    movsd   xmm0, xmm7
    xor     edx, edx
    call    t_print_double
    call    t_newline
    DLOAD   xmm0, 1.5
    mulsd   xmm0, xmm6
    xor     ebx, ebx
    comisd  xmm7, xmm0
    seta    bl
    DCMP    xmm6, a, 0.0
    and     eax, ebx
    CHECK_TRUE eax, "pan right failed"
    MIXOUT  FS
    ; facing east the same source is dead ahead
    PLAYER_AT 0.0, 0.0, 0.0, 90.0
    mov     ecx, SFX_DIG_STONE
    FLOAD   xmm1, 5.0
    FLOAD   xmm2, 1.62
    xorps   xmm3, xmm3
    call    sfx_play_at
    MIXOUT  8192
    mov     ecx, 8192
    call    rms_lr
    movsd   xmm6, xmm0
    movsd   xmm7, xmm1
    PRINT   "  same source, listener facing east: L "
    movsd   xmm0, xmm6
    xor     edx, edx
    call    t_print_double
    PRINT   " R "
    movsd   xmm0, xmm7
    xor     edx, edx
    call    t_print_double
    call    t_newline
    movapd  xmm0, xmm6
    subsd   xmm0, xmm7
    xorpd   xmm1, xmm1
    subsd   xmm1, xmm0
    maxsd   xmm0, xmm1
    movapd  xmm1, xmm6
    addsd   xmm1, xmm7
    DLOAD   xmm2, 0.05
    mulsd   xmm1, xmm2
    xor     eax, eax
    comisd  xmm0, xmm1
    setb    al
    CHECK_TRUE eax, "front source not centred"
    MIXOUT  FS
    mov     ecx, SFX_DIG_STONE
    FLOAD   xmm1, 20.0
    FLOAD   xmm2, 1.62
    xorps   xmm3, xmm3
    call    sfx_play_at
    MIXOUT  1024
    call    audio_dbg_active_voices
    CHECK_EQ32 eax, 0, "sound beyond 16 blocks was played"

    mov     ecx, 1
    mov     edx, 1
    mov     r8d, 1
    xor     r9d, r9d
    mov     qword [rsp+32], 1
    call    sfx_play_block
    MIXOUT  1024
    call    audio_dbg_active_voices
    CHECK_EQ32 eax, 2, "place should start 2 voices"
    MIXOUT  FS
    xor     ebx, ebx
.kinds:
    mov     ecx, 1
    mov     edx, ebx
    xor     r8d, r8d
    xor     r9d, r9d
    mov     qword [rsp+32], 2
    call    sfx_play_block
    inc     ebx
    cmp     ebx, 4
    jb      .kinds
    MIXOUT  1024
    call    audio_dbg_active_voices
    CHECK_EQ32 eax, 5, "sfx_play_block kinds should start 5 voices"
    MIXOUT  FS*2

    xorps   xmm0, xmm0
    call    ah_set_sfx
    SFX     SFX_EXPLODE, 1.0, 1.0
    MIXOUT  8192
    lea     rcx, [rel outb]
    mov     edx, 16384
    mov     r8d, 1
    call    ah_i16_absmax
    CHECK_EQ32 eax, 0, "sfx_vol 0 not silent"
    MIXOUT  FS*2
    MIXOUT  FS*2
ENDPX

; info: +20 start serial, +24 finished serial, +28 main-thread mood
PROC scheduler_test, 16
    TEST "music scheduler: tick -> mixer -> finished"
    FLOAD   xmm0, 1.0
    call    ah_set_music
    FLOAD   xmm0, 1.0
    call    ah_set_sfx
    SETI32  g_world_active, 0
    call    music_init
    lea     rcx, [rel info]
    call    music_dbg_info
    mov     ebx, [rel info+20]
    CHECK_EQ32 [rel info+28], 2, "menu mood not detected"
    lea     rcx, [rel info]
    mov     edx, ebx
    call    ah_wait_music_start
    lea     r10d, [rbx+1]
    CHECK_EQ32 [rel info+20], r10d, "music_tick never requested the title theme"
    MIXOUT  2048
    call    music_dbg_state
    CHECK_EQ32 eax, 1, "mixer did not start the piece"
    lea     rcx, [rel info]
    call    music_dbg_info
    CHECK_EQ32 [rel info], 2, "piece is not the menu theme"
    SETI32  g_world_active, 1
    SETI32  g_state, ST_PLAYING
    PLAYER_AT 0.0, 80.0, 0.0, 0.0
    SETI32  g_time_of_day, 18000        ; midnight
    call    music_tick
    lea     rcx, [rel info]
    call    music_dbg_info
    CHECK_EQ32 [rel info+28], 1, "night mood not detected"
    MIXOUT  FS*2
    call    music_dbg_state
    CHECK_EQ32 eax, 0, "fade-out after leaving the menu did not finish"
    call    music_tick
    lea     rcx, [rel info]
    call    music_dbg_info
    mov     r10d, [rel info+20]
    CHECK_EQ32 [rel info+24], r10d, "finished serial not reported"
    ; world_get_light is stubbed to 0, so y 30 reads as underground
    PLAYER_AT 0.0, 30.0, 0.0, 0.0
    call    music_tick
    lea     rcx, [rel info]
    call    music_dbg_info
    CHECK_EQ32 [rel info+28], 3, "cave mood not detected"
    xor     ecx, ecx
    call    music_set_mood
    lea     rcx, [rel info]
    call    music_dbg_info
    CHECK_EQ32 [rel info+28], 0, "music_set_mood ignored"
ENDP
