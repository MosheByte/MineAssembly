; renders one whole piece per mood through the real music_render path, no device.
; seed 1234+mood. drops audio_wav/music_<mood>.wav to listen to.
; @link src/audio.asm src/music.asm tests/audio/audiohelp.asm
; @timeout 300
%include "common.inc"
%include "testlib.inc"
%include "../audio/audiohelp.inc"

%define MAX_SECS    120

; eax = (xmm cc literal), cc is a/ae/b/be
%macro DCMP 3
    DLOAD xmm5, %3
    xor     eax, eax
    comisd  %1, xmm5
    set%2   al
%endmacro

section .rdata
align 8
mood_secs:  dd 110, 120, 70, 110      ; day night menu cave
mood_name:  dq n_day, n_night, n_menu, n_cave
n_day:      db "day", 0
n_night:    db "night", 0
n_menu:     db "menu", 0
n_cave:     db "cave", 0
s_dir:      db "audio_wav", 0
s_pre:      db "audio_wav\music_", 0
s_wav:      db ".wav", 0
s_mood:     db "mood ", 0

section .bss
alignb 16
info:       resd 8
path:       resb 64
bufa:       resq 1
bufb:       resq 1

section .text

PROC test_main
    lea     rcx, [rel s_dir]
    call    ah_mkdir
    mov     ecx, MAX_SECS*FS*2*4
    call    t_alloc
    mov     [rel bufa], rax
    mov     ecx, 10*FS*2*4
    call    t_alloc
    mov     [rel bufb], rax
    call    music_moods
    call    music_seeds
ENDP

; r12d mood, r13d frames, r15 name, xmm6 peak, xmm7 rms, xmm8 audible-until s,
; LOC(0) state, LOC(4) failure count before this mood
PROCX music_moods, 64
    TEST "music"
    FLOAD   xmm0, 1.0
    call    ah_set_music
    mov     rsi, [rel bufa]
    xor     r12d, r12d
.mood:
    cmp     r12d, 4
    jge     .done
    mov     eax, [rel t_failures]
    mov     LOC(4), eax
    lea     rax, [rel mood_secs]
    imul    r13d, [rax+r12*4], FS
    lea     rax, [rel mood_name]
    mov     r15, [rax+r12*8]
    call    t_time_ms
    mov     rbx, rax
    mov     ecx, r12d
    lea     edx, [r12+1234]
    mov     r8, rsi
    mov     r9d, r13d
    call    music_dbg_render
    call    t_time_ms
    sub     rbx, rax
    neg     rbx                         ; elapsed ms
    lea     rcx, [rel info]
    call    music_dbg_info

    mov     rcx, rsi
    lea     edx, [r13+r13]
    call    ah_finite_f
    CHECK_TRUE eax, "music has NaN/Inf"
    mov     rcx, rsi
    lea     edx, [r13+r13]
    call    ah_peak_f
    movsd   xmm6, xmm0
    mov     rcx, rsi
    lea     edx, [r13+r13]
    call    ah_rms_f
    movsd   xmm7, xmm0
    mov     rcx, rsi
    mov     edx, r13d
    FLOAD   xmm2, 0.002
    call    ah_last_loud_f
    ; when does it go quiet for good
    xorpd   xmm8, xmm8
    test    rax, rax
    js      .q
    cvtsi2sd xmm8, rax
    DLOAD   xmm0, 44100.0
    divsd   xmm8, xmm0
.q:
    call    music_dbg_state
    mov     LOC(0), eax
    PRINT   "  "
    mov     rcx, r15
    call    t_print
    PRINT   ": steps "
    movsxd  rcx, dword [rel info+8]
    call    t_print_int
    PRINT   " x "
    cvtsi2sd xmm0, dword [rel info+12]
    DLOAD   xmm1, 44100.0
    divsd   xmm0, xmm1
    mov     edx, 2
    call    t_print_double
    PRINT   "s root "
    movsxd  rcx, dword [rel info+16]
    call    t_print_int
    PRINT   ", peak "
    movsd   xmm0, xmm6
    mov     edx, 3
    call    t_print_double
    PRINT   " rms "
    movsd   xmm0, xmm7
    mov     edx, 4
    call    t_print_double
    PRINT   ", audible until "
    movsd   xmm0, xmm8
    mov     edx, 1
    call    t_print_double
    PRINT   "s, state "
    movsxd  rcx, dword LOC(0)
    call    t_print_int
    PRINT   ", rendered in "
    mov     rcx, rbx
    call    t_print_int
    PRINT   " ms"
    call    t_newline

    DCMP    xmm6, a, 0.05
    CHECK_TRUE eax, "music silent (peak <= 0.05)"
    DCMP    xmm6, b, 0.98
    CHECK_TRUE eax, "music clips (peak >= 0.98)"
    DCMP    xmm7, a, 0.004
    CHECK_TRUE eax, "music too quiet (rms <= 0.004)"
    CHECK_EQ32 LOC(0), 0, "music piece did not finish within the render length"
    DCMP    xmm8, a, 25.0
    CHECK_TRUE eax, "music piece too short (audible <= 25 s)"
    mov     rcx, rsi
    lea     rdx, [rsi+4]
    mov     r8d, r13d
    mov     r9d, 2
    call    ah_allclose_f
    xor     eax, 1
    CHECK_TRUE eax, "music has no stereo (L == R)"
    ; tag failures with the mood name
    mov     eax, [rel t_failures]
    cmp     eax, LOC(4)
    je      .wav
    lea     rcx, [rel path]
    lea     rdx, [rel s_mood]
    call    ah_scpy
    mov     rcx, rax
    mov     rdx, r15
    call    ah_scpy
    lea     rcx, [rel path]
    call    t_fail_detail
.wav:
    lea     rcx, [rel path]
    lea     rdx, [rel s_pre]
    call    ah_scpy
    mov     rcx, rax
    mov     rdx, r15
    call    ah_scpy
    mov     rcx, rax
    lea     rdx, [rel s_wav]
    call    ah_scpy
    lea     rcx, [rel path]
    mov     rdx, rsi
    lea     r8d, [r13+r13]
    mov     r9d, 2
    mov     qword [rsp+32], 1
    call    ah_write_wav
    inc     r12d
    jmp     .mood
.done:
ENDPX

PROC music_seeds, 0
    TEST "music seeds and volume"
    mov     rsi, [rel bufa]
    mov     rdi, [rel bufb]
    xor     ecx, ecx
    mov     edx, 77
    mov     r8, rsi
    mov     r9d, FS*10
    call    music_dbg_render
    xor     ecx, ecx
    mov     edx, 77
    mov     r8, rdi
    mov     r9d, FS*10
    call    music_dbg_render
    CHECK_MEM rsi, rdi, FS*10*2*4, "music not deterministic for a seed"
    xor     ecx, ecx
    mov     edx, 78
    mov     r8, rdi
    mov     r9d, FS*10
    call    music_dbg_render
    mov     rcx, rsi
    mov     rdx, rdi
    mov     r8d, FS*10*2
    mov     r9d, 1
    call    ah_allclose_f
    xor     eax, 1
    CHECK_TRUE eax, "different seeds give the same piece"
    xorps   xmm0, xmm0
    call    ah_set_music
    mov     ecx, 2
    mov     edx, 5
    mov     r8, rsi
    mov     r9d, FS*5
    call    music_dbg_render
    mov     rcx, rsi
    mov     edx, FS*5*2
    call    ah_peak_f
    xorpd   xmm1, xmm1
    xor     eax, eax
    comisd  xmm0, xmm1
    sete    al
    jnp     .c                      ; nan is not silence
    xor     eax, eax
.c:
    CHECK_TRUE eax, "music_vol 0 is not silent"
ENDP
