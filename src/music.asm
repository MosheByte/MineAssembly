; music.asm - generative ambient music, synthesized live on the mixer thread
; short pieces then long silences (30-120 s). fm ep/bells, saw pads, cave drone, freeverb-ish reverb.
; main thread only decides when a piece starts/stops (bumps serials), music_render polls them. no locks.
%define IMPL_MUSIC ; v1: music scratch #3
%include "common.inc" ; v1: music scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (music:4)

extern audio_sin01 ; v1: music scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (music:6)
extern audio_exp ; v1: music scratch #7

%define FS_HZ       44100 ; v1: music scratch #9
%define SUB         64 ; v1: music scratch #10
    ; TODO: clamp index before table lookup on malformed input (music:10)
%define NMV         16 ; v1: music scratch #11
%define MOOD_DAY    0 ; v1: music scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (music:12)
%define MOOD_NIGHT  1 ; v1: music scratch #13
%define MOOD_MENU   2 ; v1: music scratch #14
    ; TODO: hoist invariant pointer load out of .loop (music:14)
%define MOOD_CAVE   3 ; v1: music scratch #15
%define I_EP        0 ; v1: music scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (music:16)
%define I_BELL      1 ; v1: music scratch #17
%define I_PAD       2 ; v1: music scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (music:18)
%define I_DRONE     3 ; v1: music scratch #19
%define I_BASS      4 ; v1: music scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (music:20)
%define SQ_IDLE     0 ; v1: music scratch #21
%define SQ_PLAY     1 ; v1: music scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (music:22)
%define SQ_TAIL     2 ; v1: music scratch #23
%define SQ_FADE     3 ; v1: music scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (music:24)
%define NCOMB       8 ; v1: music scratch #25
%define NAP         4 ; v1: music scratch #26
    ; TODO: clamp index before table lookup on malformed input (music:26)
%define REVMEM      12288 ; v1: music scratch #27

struc MV ; v1: music scratch #29
    .active  resd 1 ; v1: music scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (music:30)
    .inst    resd 1 ; v1: music scratch #31
    .stage   resd 1 ; v1: music scratch #32
    ; TODO: hoist invariant pointer load out of .loop (music:32)
    .age     resd 1 ; v1: music scratch #33
    .len     resd 1 ; v1: music scratch #34
    ; FIXME: negative world x/z needs sar 4, not shr 4 (music:34)
    .phase   resd 1 ; v1: music scratch #35
    .phase2  resd 1
    .phase3  resd 1
    .mphase  resd 1
    .inc     resd 1  ; cycles/sample
    .minc    resd 1
    .env     resd 1
    .att_inc resd 1
    .dec_k   resd 1
    .sus     resd 1
    .rel_k   resd 1
    .idx     resd 1  ; cycles
    .idx_k   resd 1
    .idx_fl  resd 1
    .gain    resd 1
    .pl      resd 1
    .pr      resd 1
    .send    resd 1
    .lp1     resd 1
    .lp2     resd 1
    .lp_a    resd 1
    .lfo     resd 1
    .lfo_inc resd 1
    .det     resd 1
    .last    resd 1  ; post env*gain, pre pan. for the steal de-click
    .pad     resd 2
endstruc

struc INS  ; 40 bytes
    .att    resd 1
    .dec    resd 1
    .sus    resd 1
    .rel    resd 1
    .ratio  resd 1
    .idx0   resd 1
    .idxdec resd 1
    .idxfl  resd 1
    .gain   resd 1
    .send   resd 1
endstruc

struc MOODP  ; 64 bytes, index = mood << 6
    .step_sec  resd 1
    .rest_p    resd 1
    .mel_inst  resd 1
    .pad_cut   resd 1  ; Hz
    .bright    resd 1  ; fm index mult
    .steps_min resd 1
    .steps_max resd 1
    .chord_len resd 1
    .scale     resd 1  ; offset into scales
    .scale_len resd 1
    .roots     resb 4  ; pick one of 4
    .mel_oct   resd 1  ; semitones above root
    .bass      resd 1
    .drone     resd 1
    .pad       resd 1
    .note_p    resd 1  ; chance a slot plays
endstruc

struc COMB
    .buf    resq 1
    .len    resd 1
    .idx    resd 1
    .filt   resd 1
    .pad    resd 3
endstruc

struc APF
    .buf    resq 1
    .len    resd 1
    .idx    resd 1
endstruc

section .rdata
align 16
m_absmask:  dd 0x7FFFFFFF, 0, 0, 0
m_zero:     dd 0.0
m_one:      dd 1.0
m_half:     dd 0.5
m_fs:       dd 44100.0
m_inv_fs:   dd 0.0000226757369615
m_ln2_12:   dd 0.0577622650467          ; ln 2 / 12
m_a4:       dd 440.0
m_mone:     dd -1.0
m_twopi:    dd 6.28318530718
m_inv_twopi: dd 0.159154943092
m_sqrt2:    dd 1.41421356
m_eighth:   dd 0.125
m_two3:     dd 0.666666667
m_padgain:  dd 1.5
m_det:      dd 0.0045
m_drone_lfo: dd 0.07
m_drone_i:  dd 0.05  ; cycles, * (1+lfo)
m_fifth:    dd 1.5
m_fifthamt: dd 0.45
m_dr_base:  dd 0.8
m_dr_amt:   dd 0.2
m_silence:  dd 0.0001
m_vel_lo:   dd 0.6
m_vel_hi:   dd 0.4
m_mel_v0:   dd 0.5
m_mel_v1:   dd 0.35
m_panw:     dd 0.7
m_padpan:   dd 0.5
m_harm_p:   dd 0.15
m_harm_v:   dd 0.55
m_bass_p:   dd 0.85
m_bass_v:   dd 0.7
m_pad_v:    dd 0.75
m_pad_vr:   dd 0.1
m_dur_mul:  dd 0.9
m_thm_dur:  dd 0.92
m_inv127:   dd 0.00787401575
m_ctr_p:    dd 0.15
m_ctr_v:    dd 0.35
m_tempo_lo: dd 0.94
m_tempo_r:  dd 0.12
m_drone_v:  dd 0.8
m_drone_pan: dd 0.3
m_bellpan:  dd 0.4
m_eppan:    dd -0.1
m_rev_in:   dd 0.045
m_rev_fb:   dd 0.84
m_rev_damp: dd 0.25
m_rev_1md:  dd 0.75
m_rev_wet:  dd 0.9
m_ap_fb:    dd 0.5
m_base_vol: dd 0.7
m_lvl_k:    dd 0.03
m_fade_step: dd 0.000967  ; SUB / (1.5 s * fs)
m_lvl_end:  dd 0.0005  ; smoothed level below this = silent
m_resdecay: dd 0.9965  ; ~6.5 ms
m_cave_y:   dd 52.0
m_eye:      dd 1.62

; instrument table:      att    dec   sus   rel   ratio  idx0  idxdec  floor  gain  send
ins_tab:
    dd 0.004, 1.5, 0.0,  0.3, 1.0, 1.4, 0.4, 0.12, 0.30, 0.35      ; EPIANO
    dd 0.002, 2.6, 0.0,  1.0, 3.5, 1.6, 0.8, 0.08, 0.22, 0.55      ; BELL
    dd 1.6,   2.5, 0.7,  2.0, 0.0, 0.0, 1.0, 0.0,  0.10, 0.50      ; PAD
    dd 4.0,   6.0, 0.85, 4.0, 2.0, 0.0, 1.0, 0.0,  0.20, 0.60      ; DRONE
    dd 0.006, 2.0, 0.0,  0.4, 1.0, 0.7, 0.3, 0.05, 0.30, 0.15      ; BASS

mood_tab:
    ; day
    dd 0.42, 0.30, I_EP, 1400.0, 1.0, 96, 160, 16, 0, 5
    db 53, 55, 57, 60
    dd 12, 1, 0, 1, 1.0
    ; night
    dd 0.62, 0.42, I_BELL, 800.0, 0.6, 72, 112, 16, 5, 7
    db 50, 52, 55, 57
    dd 12, 1, 0, 1, 1.0
    ; menu, the counter-melody is pentatonic
    dd 0.36, 0.0, I_EP, 1600.0, 1.0, 128, 128, 16, 0, 5
    db 62, 62, 62, 62
    dd 12, 1, 0, 1, 1.0
    ; cave
    dd 1.0, 0.55, I_BELL, 500.0, 0.5, 40, 64, 16, 12, 6
    db 38, 40, 41, 43
    dd 24, 0, 1, 0, 0.45

; pentatonic @0, dorian @5, cave (phrygian + tritone) @12
scales:     db 0, 2, 4, 7, 9
            db 0, 2, 3, 5, 7, 9, 10
            db 0, 1, 5, 6, 7, 10
; chord roots as scale degrees, 4 progressions per mood
progs:      db 0,3,4,1,  0,4,3,1,  0,1,3,2,  3,0,4,0         ; day
            db 0,6,2,3,  0,3,0,6,  0,4,2,6,  0,2,6,3         ; night
            db 0,0,0,0,  0,0,0,0,  0,0,0,0,  0,0,0,0  ; menu, unused (theme is hardcoded)
            db 0,0,0,0,  0,0,0,0,  0,0,0,0,  0,0,0,0         ; cave, always degree 0
walk_tab:   db -3, -2, -1, -1, 1, 1, 2, 3  ; +-1 twice so small steps win
dur_tab:    db 1, 2, 2, 2, 3, 4, 4, 6  ; steps
shift_tab:  db 0, 0, 2, -2, 1  ; 0 twice so it often comes back as-is

; samples, L then R
comb_len:   dd 1116, 1188, 1277, 1356, 1139, 1211, 1300, 1379
ap_len:     dd 556, 441, 579, 464

; title theme in D: step, inst, midi, len (steps), vel. 0xFF ends
theme:
    ; D Bm Gmaj7 A
    db  0, I_PAD, 57, 16, 90,   0, I_PAD, 62, 16, 85,   0, I_PAD, 66, 16, 80
    db 16, I_PAD, 59, 16, 90,  16, I_PAD, 62, 16, 85,  16, I_PAD, 66, 16, 80
    db 32, I_PAD, 55, 16, 90,  32, I_PAD, 59, 16, 85,  32, I_PAD, 62, 16, 80,  32, I_PAD, 66, 16, 70
    db 48, I_PAD, 57, 16, 90,  48, I_PAD, 61, 16, 85,  48, I_PAD, 64, 16, 80
    db  0, I_BASS, 38, 12, 100,   8, I_BASS, 45, 6, 70
    db 16, I_BASS, 35, 12, 100,  24, I_BASS, 42, 6, 70
    db 32, I_BASS, 43, 12, 100,  40, I_BASS, 50, 6, 70
    db 48, I_BASS, 45, 12, 100,  56, I_BASS, 52, 6, 70
    db  0, I_EP, 69, 2, 100,   2, I_EP, 66, 2, 90,   4, I_EP, 64, 1, 85,   5, I_EP, 66, 1, 85
    db  6, I_EP, 69, 4, 100,  10, I_EP, 74, 4, 105
    db 16, I_EP, 71, 3, 100,  19, I_EP, 69, 1, 85,  20, I_EP, 66, 2, 90,  22, I_EP, 64, 2, 85
    db 24, I_EP, 62, 6, 95
    db 32, I_EP, 74, 2, 100,  34, I_EP, 71, 2, 90,  36, I_EP, 69, 1, 85,  37, I_EP, 71, 1, 85
    db 38, I_EP, 74, 2, 95,   40, I_EP, 76, 4, 105, 44, I_EP, 78, 2, 100, 46, I_EP, 76, 2, 90
    db 48, I_EP, 69, 3, 100,  51, I_EP, 71, 1, 85,  52, I_EP, 69, 2, 90,  54, I_EP, 66, 2, 85
    db 56, I_EP, 64, 8, 95
    db 10, I_BELL, 86, 4, 50,  26, I_BELL, 81, 4, 45,  40, I_BELL, 88, 4, 45,  58, I_BELL, 88, 6, 40
    db 0xFF

section .bss
alignb 16
mvoices:    resb MV_size*NMV
mr_dry:     resd SUB*2
mr_send:    resd SUB
combs:      resb COMB_size*NCOMB
apfs:       resb APF_size*NAP
revmem:     resd REVMEM
; shared w/ main thread. aligned dwords so plain mov is atomic
mus_start_serial:    resd 1
mus_stop_serial:     resd 1
mus_req_mood:        resd 1
mus_req_seed:        resd 1
mus_finished_serial: resd 1
mus_playing:         resd 1
rev_ready:  resd 1
mres_l:     resd 1  ; steal residual
mres_r:     resd 1
mr_seen_start: resd 1
mr_seen_stop:  resd 1
mr_cur_serial: resd 1
mr_level:   resd 1
mr_rng:     resd 1
seq_state:  resd 1
seq_mood:   resd 1
seq_step:   resd 1
seq_total:  resd 1
seq_step_len: resd 1
seq_ctr:    resd 1
seq_root:   resd 1
seq_scale:  resd 1
seq_scale_len: resd 1
seq_chord_len: resd 1
seq_chord:  resd 1
seq_mel_deg: resd 1
seq_mel_wait: resd 1
seq_motif_n: resd 1
seq_shift:  resd 1
seq_fade:   resd 1
seq_tail:   resd 1
seq_padcut: resd 1
seq_bright: resd 1
seq_prog:   resb 4
seq_motif:  resb 32  ; 16 x (degree, steps), degree 0x80 = none
seq_moodp:  resq 1
mt_inited:  resd 1
mt_mood:    resd 1
mt_last_det: resd 1
mt_waiting: resd 1
mt_wait_serial: resd 1
mt_stop_sent: resd 1
mt_override: resd 1  ; ms after the current piece, 0 = normal gap
mt_rng:     resd 1
alignb 8
mt_next_ms: resq 1

section .text

; same xorshift as xs32_step in audio.asm, clobbers edx
align 16
xs_next:
    mov     eax, [rcx]
    test    eax, eax
    jnz     .ok
    mov     eax, 0x6C8E9CF5
.ok:
    mov     edx, eax
    shl     edx, 13
    xor     eax, edx
    mov     edx, eax
    shr     edx, 17
    xor     eax, edx
    mov     edx, eax
    shl     edx, 5
    xor     eax, edx
    mov     [rcx], eax
    ret
    ; v1 temporary guard (music #14)
    xor     r11d, r11d ; clear v1 slot 14
    ; v1 temporary guard (music #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (music #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (music #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (music #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (music #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (music #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (music #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (music #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (music #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (music #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (music #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (music #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (music #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (music #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (music #44)
    xor     r11d, r11d ; clear v1 slot 44
