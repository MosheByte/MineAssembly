; real waveOut device, silent. two rounds of init, 1.2 s for the bank, 10 sfx+ticks,
; shutdown. a box with no audio device still has to init/shutdown cleanly.
; @link src/audio.asm src/music.asm tests/audio/audiohelp.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../audio/audiohelp.inc"

section .text

PROC test_main, 16
    TEST "waveOut device: init / shutdown twice"
    xorps   xmm0, xmm0
    call    ah_set_music
    xorps   xmm0, xmm0
    call    ah_set_sfx
    call    t_time_ms
    mov     r14, rax
    xor     r12d, r12d
.round:
    call    audio_init
    mov     r13d, eax
    call    music_init
    mov     ecx, 1200                   ; bank synthesis + streaming
    call    Sleep
    xor     ebx, ebx
.snd:
    mov     ecx, ebx
    mov     eax, __?float32?__(1.0)
    movd    xmm1, eax
    movd    xmm2, eax
    call    sfx_play
    call    music_tick
    mov     ecx, 50
    call    Sleep
    inc     ebx
    cmp     ebx, 10
    jb      .snd
    call    audio_shutdown
    PRINT   "  round "
    mov     ecx, r12d
    call    t_print_int
    PRINT   " init "
    mov     ecx, r13d
    call    t_print_int
    call    t_newline
    inc     r12d
    cmp     r12d, 2
    jb      .round
    call    t_time_ms
    sub     rax, r14
    mov     rbx, rax
    PRINT   "  DEVICE OK ("
    mov     rcx, rbx
    call    t_print_int
    PRINT   " ms)"
    call    t_newline
    CHECK_EQ32 r12d, 2, "device init/shutdown rounds completed"
ENDP
