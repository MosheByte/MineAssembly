; music.asm - generative ambient music, synthesized live on the mixer thread
; short pieces then long silences (30-120 s). fm ep/bells, saw pads, cave drone, freeverb-ish reverb.
; main thread only decides when a piece starts/stops (bumps serials), music_render polls them. no locks.
%define IMPL_MUSIC
%include "common.inc"

extern audio_sin01  ; clobbers xmm1-2
extern audio_exp  ; clobbers xmm1-2, eax

%define FS_HZ       44100
%define SUB         64  ; frames, also how often the sequencer gets checked
%define NMV         16
%define MOOD_DAY    0
%define MOOD_NIGHT  1
%define MOOD_MENU   2
%define MOOD_CAVE   3
%define I_EP        0
%define I_BELL      1
%define I_PAD       2
%define I_DRONE     3
%define I_BASS      4
%define SQ_IDLE     0
%define SQ_PLAY     1
%define SQ_TAIL     2
%define SQ_FADE     3
%define NCOMB       8                   ; 4 per channel
%define NAP         4                   ; 2 per channel
%define REVMEM      12288  ; floats, all delay lines live here

struc MV  ; 128 bytes
    .active  resd 1
    .inst    resd 1
    .stage   resd 1  ; 0 att 1 dec/sus 2 rel
    .age     resd 1  ; samples
    .len     resd 1  ; samples till note off
    .phase   resd 1
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

; clobber rcx, edx
align 16
mr_rand:
    lea     rcx, [rel mr_rng]
    jmp     xs_next
align 16
mr_randf:
    lea     rcx, [rel mr_rng]
    call    xs_next
    shr     eax, 9
    or      eax, 0x3F800000
    movd    xmm0, eax
    subss   xmm0, [rel m_one]
    ret
; [0,n), clobbers ecx edx r8d
align 16
mr_randn:
    mov     r8d, ecx
    call    mr_rand
    xor     edx, edx
    div     r8d
    mov     eax, edx
    ret
; main-thread rng
align 16
mt_randn:
    mov     r8d, ecx
    lea     rcx, [rel mt_rng]
    call    xs_next
    xor     edx, edx
    div     r8d
    mov     eax, edx
    ret

; (ecx inst, edx midi, r8d dur samples, xmm2 vel, xmm3 pan -1..1)
PROCX music_note_on, 32
    mov     r12d, ecx
    mov     r13d, edx
    mov     r14d, r8d
    movaps  xmm6, xmm2
    movaps  xmm7, xmm3
    ; free voice, else quietest released, else quietest overall
    lea     rsi, [rel mvoices]
    xor     ecx, ecx
    xor     rbx, rbx
    movss   xmm8, [rel m_fs]
.find:
    imul    eax, ecx, MV_size
    lea     rdx, [rsi+rax]
    cmp     dword [rdx+MV.active], 0
    jne     .busy
    mov     rbx, rdx
    jmp     .got
.busy:
    movss   xmm0, [rdx+MV.env]
    cmp     dword [rdx+MV.stage], 2
    je      .rel
    addss   xmm0, [rel m_one]  ; +1 so held notes lose to released ones
.rel:
    comiss  xmm0, xmm8
    jae     .nx
    movaps  xmm8, xmm0
    mov     rbx, rdx
.nx:
    inc     ecx
    cmp     ecx, NMV
    jb      .find
    ; all busy, steal rbx. its last sample goes into the residual so the cut doesn't click
    movss   xmm0, [rbx+MV.last]
    movaps  xmm1, xmm0
    mulss   xmm0, [rbx+MV.pl]
    mulss   xmm1, [rbx+MV.pr]
    addss   xmm0, [rel mres_l]
    addss   xmm1, [rel mres_r]
    movss   [rel mres_l], xmm0
    movss   [rel mres_r], xmm1
.got:
    mov     rdi, rbx
    xor     eax, eax
    mov     ecx, MV_size/4
    rep     stosd
    mov     [rbx+MV.inst], r12d
    mov     [rbx+MV.len], r14d
    imul    eax, r12d, INS_size
    lea     r15, [rel ins_tab]
    add     r15, rax
    ; inc = 440 e^((n-69) ln2/12) / fs
    lea     eax, [r13-69]
    cvtsi2ss xmm0, eax
    mulss   xmm0, [rel m_ln2_12]
    call    audio_exp
    mulss   xmm0, [rel m_a4]
    mulss   xmm0, [rel m_inv_fs]
    movss   [rbx+MV.inc], xmm0
    movaps  xmm1, xmm0
    mulss   xmm1, [r15+INS.ratio]
    movss   [rbx+MV.minc], xmm1
    movss   xmm0, [r15+INS.att]
    mulss   xmm0, [rel m_fs]
    maxss   xmm0, [rel m_one]
    movss   xmm1, [rel m_one]
    divss   xmm1, xmm0
    movss   [rbx+MV.att_inc], xmm1
    movss   xmm0, [r15+INS.dec]
    call    .kcoef
    movss   [rbx+MV.dec_k], xmm0
    movss   xmm0, [r15+INS.rel]
    call    .kcoef
    movss   [rbx+MV.rel_k], xmm0
    movss   xmm0, [r15+INS.idxdec]
    call    .kcoef
    movss   [rbx+MV.idx_k], xmm0
    mov     eax, [r15+INS.sus]
    mov     [rbx+MV.sus], eax
    ; idx (cycles) = idx0 * bright * (0.6 + 0.4 vel) / 2pi
    movss   xmm0, xmm6
    mulss   xmm0, [rel m_vel_hi]
    addss   xmm0, [rel m_vel_lo]
    mulss   xmm0, [r15+INS.idx0]
    mulss   xmm0, [rel seq_bright]
    mulss   xmm0, [rel m_inv_twopi]
    movss   [rbx+MV.idx], xmm0
    movss   xmm0, [r15+INS.idxfl]
    mulss   xmm0, [rel m_inv_twopi]
    movss   [rbx+MV.idx_fl], xmm0
    movss   xmm0, xmm6
    mulss   xmm0, [r15+INS.gain]
    movss   [rbx+MV.gain], xmm0
    mov     eax, [r15+INS.send]
    mov     [rbx+MV.send], eax
    ; constant power pan
    maxss   xmm7, [rel m_mone]
    minss   xmm7, [rel m_one]
    movss   xmm0, [rel m_one]
    subss   xmm0, xmm7
    mulss   xmm0, [rel m_eighth]
    call    audio_sin01
    mulss   xmm0, [rel m_sqrt2]
    movss   [rbx+MV.pl], xmm0
    movss   xmm0, [rel m_one]
    addss   xmm0, xmm7
    mulss   xmm0, [rel m_eighth]
    call    audio_sin01
    mulss   xmm0, [rel m_sqrt2]
    movss   [rbx+MV.pr], xmm0
    cmp     r12d, I_PAD
    jne     .npad
    mov     eax, [rel m_det]
    mov     [rbx+MV.det], eax
    movss   xmm0, [rel seq_padcut]  ; one-pole a = 1 - e^(-2pi fc/fs)
    mulss   xmm0, [rel m_twopi]
    mulss   xmm0, [rel m_inv_fs]
    xorps   xmm1, xmm1
    subss   xmm1, xmm0
    movaps  xmm0, xmm1
    call    audio_exp
    movss   xmm1, [rel m_one]
    subss   xmm1, xmm0
    movss   [rbx+MV.lp_a], xmm1
    ; random start phases or every pad attack sounds phasey
    call    mr_randf
    movss   [rbx+MV.phase2], xmm0
    call    mr_randf
    movss   [rbx+MV.phase3], xmm0
    jmp     .on
.npad:
    cmp     r12d, I_DRONE
    jne     .on
    call    mr_randf  ; lfo 0.07..0.105 Hz
    mulss   xmm0, [rel m_half]
    addss   xmm0, [rel m_one]
    mulss   xmm0, [rel m_drone_lfo]
    mulss   xmm0, [rel m_inv_fs]
    movss   [rbx+MV.lfo_inc], xmm0
.on:
    mov     dword [rbx+MV.active], 1
    jmp     .done
; xmm0 tau (s) -> exp(-1/(tau fs))
.kcoef:
    mulss   xmm0, [rel m_fs]
    maxss   xmm0, [rel m_one]
    movss   xmm1, [rel m_mone]
    divss   xmm1, xmm0
    movaps  xmm0, xmm1
    jmp     audio_exp  ; tail call
.done:
ENDPX

; adds into mr_dry / mr_send. xmm6 env, xmm7 phase, xmm8 mphase, xmm9 idx, xmm10 out
PROCX music_voice_render, 16
    mov     rbx, rcx
    mov     r14d, edx
    mov     r13d, [rbx+MV.inst]
    lea     rdi, [rel mr_dry]
    lea     rsi, [rel mr_send]
    movss   xmm6, [rbx+MV.env]
    movss   xmm7, [rbx+MV.phase]
    movss   xmm8, [rbx+MV.mphase]
    movss   xmm9, [rbx+MV.idx]
    movss   xmm10, [rbx+MV.last]
    xor     r12d, r12d
.smp:
    mov     eax, [rbx+MV.stage]
    cmp     eax, 0
    jne     .st1
    addss   xmm6, [rbx+MV.att_inc]
    comiss  xmm6, [rel m_one]
    jb      .age
    movss   xmm6, [rel m_one]
    mov     dword [rbx+MV.stage], 1
    jmp     .age
.st1:
    cmp     eax, 1
    jne     .st2
    movss   xmm0, [rbx+MV.sus]  ; env = sus + (env-sus) k
    subss   xmm6, xmm0
    mulss   xmm6, [rbx+MV.dec_k]
    addss   xmm6, xmm0
    comiss  xmm0, [rel m_zero]
    ja      .age
    comiss  xmm6, [rel m_silence]  ; no sustain + decayed away -> done
    jb      .kill
    jmp     .age
.st2:
    mulss   xmm6, [rbx+MV.rel_k]
    comiss  xmm6, [rel m_silence]
    jb      .kill
.age:
    mov     eax, [rbx+MV.age]
    inc     eax
    mov     [rbx+MV.age], eax
    cmp     dword [rbx+MV.stage], 2
    je      .wave
    cmp     eax, [rbx+MV.len]
    jl      .wave
    mov     dword [rbx+MV.stage], 2
.wave:
    cmp     r13d, I_PAD
    je      .pad
    cmp     r13d, I_DRONE
    je      .drone
    movss   xmm0, [rbx+MV.idx_fl]
    subss   xmm9, xmm0
    mulss   xmm9, [rbx+MV.idx_k]
    addss   xmm9, xmm0
    addss   xmm8, [rbx+MV.minc]
    comiss  xmm8, [rel m_one]
    jb      .fm1
    subss   xmm8, [rel m_one]
.fm1:
    movaps  xmm0, xmm8
    call    audio_sin01
    mulss   xmm0, xmm9
    addss   xmm0, xmm7
    call    audio_sin01
    movaps  xmm10, xmm0
    addss   xmm7, [rbx+MV.inc]
    comiss  xmm7, [rel m_one]
    jb      .out
    subss   xmm7, [rel m_one]
    jmp     .out
.pad:
    ; pad: 3 detuned saws -> 2x one-pole lp
    movss   xmm1, [rbx+MV.inc]
    addss   xmm7, xmm1
    comiss  xmm7, [rel m_one]
    jb      .p1
    subss   xmm7, [rel m_one]
.p1:
    movss   xmm2, [rbx+MV.det]
    movaps  xmm3, xmm1
    mulss   xmm3, xmm2
    movss   xmm0, [rbx+MV.phase2]
    addss   xmm0, xmm1
    addss   xmm0, xmm3
    comiss  xmm0, [rel m_one]
    jb      .p2
    subss   xmm0, [rel m_one]
.p2:
    movss   [rbx+MV.phase2], xmm0
    movss   xmm4, [rbx+MV.phase3]
    addss   xmm4, xmm1
    subss   xmm4, xmm3
    comiss  xmm4, [rel m_one]
    jb      .p3
    subss   xmm4, [rel m_one]
.p3:
    movss   [rbx+MV.phase3], xmm4
    addss   xmm0, xmm4
    addss   xmm0, xmm7
    mulss   xmm0, [rel m_two3]  ; (2 sum - 3)/3
    subss   xmm0, [rel m_one]
    movss   xmm1, [rbx+MV.lp_a]
    movss   xmm2, [rbx+MV.lp1]
    subss   xmm0, xmm2
    mulss   xmm0, xmm1
    addss   xmm2, xmm0
    movss   [rbx+MV.lp1], xmm2
    movss   xmm3, [rbx+MV.lp2]
    subss   xmm2, xmm3
    mulss   xmm2, xmm1
    addss   xmm3, xmm2
    movss   [rbx+MV.lp2], xmm3
    movaps  xmm10, xmm3
    mulss   xmm10, [rel m_padgain]
    jmp     .out
.drone:
    ; drone: sine + fifth, fm shimmer that breathes
    movss   xmm0, [rbx+MV.lfo]
    addss   xmm0, [rbx+MV.lfo_inc]
    comiss  xmm0, [rel m_one]
    jb      .d1
    subss   xmm0, [rel m_one]
.d1:
    movss   [rbx+MV.lfo], xmm0
    call    audio_sin01
    movaps  xmm11, xmm0
    addss   xmm8, [rbx+MV.minc]
    comiss  xmm8, [rel m_one]
    jb      .d2
    subss   xmm8, [rel m_one]
.d2:
    movaps  xmm0, xmm8
    call    audio_sin01
    movaps  xmm1, xmm11
    addss   xmm1, [rel m_one]
    mulss   xmm1, [rel m_drone_i]
    mulss   xmm0, xmm1
    addss   xmm0, xmm7
    call    audio_sin01
    movaps  xmm10, xmm0
    movss   xmm0, [rbx+MV.phase2]
    movss   xmm1, [rbx+MV.inc]
    mulss   xmm1, [rel m_fifth]
    addss   xmm0, xmm1
    comiss  xmm0, [rel m_one]
    jb      .d3
    subss   xmm0, [rel m_one]
.d3:
    movss   [rbx+MV.phase2], xmm0
    call    audio_sin01
    mulss   xmm0, [rel m_fifthamt]
    addss   xmm10, xmm0
    movaps  xmm0, xmm11  ; 0.8 +- 0.2
    mulss   xmm0, [rel m_dr_amt]
    addss   xmm0, [rel m_dr_base]
    mulss   xmm10, xmm0
    addss   xmm7, [rbx+MV.inc]
    comiss  xmm7, [rel m_one]
    jb      .out
    subss   xmm7, [rel m_one]
.out:
    mulss   xmm10, xmm6
    mulss   xmm10, [rbx+MV.gain]
    movaps  xmm0, xmm10
    mulss   xmm0, [rbx+MV.pl]
    addss   xmm0, [rdi+r12*8]
    movss   [rdi+r12*8], xmm0
    movaps  xmm0, xmm10
    mulss   xmm0, [rbx+MV.pr]
    addss   xmm0, [rdi+r12*8+4]
    movss   [rdi+r12*8+4], xmm0
    movaps  xmm0, xmm10
    mulss   xmm0, [rbx+MV.send]
    addss   xmm0, [rsi+r12*4]
    movss   [rsi+r12*4], xmm0
    inc     r12d
    cmp     r12d, r14d
    jb      .smp
    jmp     .save
.kill:
    mov     dword [rbx+MV.active], 0
.save:
    movss   [rbx+MV.env], xmm6
    movss   [rbx+MV.phase], xmm7
    movss   [rbx+MV.mphase], xmm8
    movss   [rbx+MV.idx], xmm9
    movss   [rbx+MV.last], xmm10
ENDPX

; zero revmem, slice the delay lines out of it
PROC music_rev_setup, 0
    lea     rdi, [rel revmem]
    xor     eax, eax
    mov     ecx, REVMEM
    rep     stosd
    lea     r8, [rel revmem]
    lea     r9, [rel combs]
    lea     r10, [rel comb_len]
    xor     ecx, ecx
.c:
    mov     [r9+COMB.buf], r8
    mov     eax, [r10+rcx*4]
    mov     [r9+COMB.len], eax
    mov     dword [r9+COMB.idx], 0
    mov     dword [r9+COMB.filt], 0
    lea     r8, [r8+rax*4]
    add     r9, COMB_size
    inc     ecx
    cmp     ecx, NCOMB
    jb      .c
    lea     r9, [rel apfs]
    lea     r10, [rel ap_len]
    xor     ecx, ecx
.a:
    mov     [r9+APF.buf], r8
    mov     eax, [r10+rcx*4]
    mov     [r9+APF.len], eax
    mov     dword [r9+APF.idx], 0
    lea     r8, [r8+rax*4]
    add     r9, APF_size
    inc     ecx
    cmp     ecx, NAP
    jb      .a
    mov     dword [rel rev_ready], 1
ENDP

; xmm0 in -> wet. rcx = first COMB, rdx = first APF, 4 combs + 2 allpasses hardcoded.
; clobbers xmm1-5, rax, r8, r9
align 16
music_rev_channel:
    movaps  xmm4, xmm0
    xorps   xmm5, xmm5
    mov     r9d, 4
.comb:
    mov     r8, [rcx+COMB.buf]
    mov     eax, [rcx+COMB.idx]
    movss   xmm1, [r8+rax*4]
    addss   xmm5, xmm1
    movss   xmm2, [rcx+COMB.filt]  ; damping lp inside the loop
    mulss   xmm2, [rel m_rev_damp]
    mulss   xmm1, [rel m_rev_1md]
    addss   xmm2, xmm1
    movss   [rcx+COMB.filt], xmm2
    mulss   xmm2, [rel m_rev_fb]
    addss   xmm2, xmm4
    movss   [r8+rax*4], xmm2
    inc     eax
    cmp     eax, [rcx+COMB.len]
    jb      .ci
    xor     eax, eax
.ci:
    mov     [rcx+COMB.idx], eax
    add     rcx, COMB_size
    dec     r9d
    jnz     .comb
    mov     r9d, 2
.ap:
    mov     r8, [rdx+APF.buf]
    mov     eax, [rdx+APF.idx]
    movss   xmm1, [r8+rax*4]
    movaps  xmm2, xmm1
    subss   xmm2, xmm5
    mulss   xmm1, [rel m_ap_fb]
    addss   xmm1, xmm5
    movss   [r8+rax*4], xmm1
    movaps  xmm5, xmm2
    inc     eax
    cmp     eax, [rdx+APF.len]
    jb      .ai
    xor     eax, eax
.ai:
    mov     [rdx+APF.idx], eax
    add     rdx, APF_size
    dec     r9d
    jnz     .ap
    movaps  xmm0, xmm5
    ret

; degree can be negative -> semitones above root
PROC music_note_of, 0
    mov     eax, ecx
    cdq
    idiv    dword [rel seq_scale_len]
    test    edx, edx
    jns     .p
    add     edx, [rel seq_scale_len]
    dec     eax
.p:
    imul    eax, eax, 12
    add     edx, [rel seq_scale]
    lea     rcx, [rel scales]
    movzx   edx, byte [rcx+rdx]
    add     eax, edx
ENDP

PROC music_kill_all, 0
    lea     rdx, [rel mvoices]
    xor     ecx, ecx
.l:
    mov     dword [rdx+MV.active], 0
    add     rdx, MV_size
    inc     ecx
    cmp     ecx, NMV
    jb      .l
    xor     eax, eax  ; only called when it's inaudible anyway
    mov     [rel mres_l], eax
    mov     [rel mres_r], eax
ENDP

PROCX music_seq_start, 16
    and     ecx, 3
    mov     r12d, ecx
    imul    eax, edx, 0x9E3779B1
    or      eax, 1
    mov     [rel mr_rng], eax
    call    music_kill_all
    call    music_rev_setup
    mov     [rel seq_mood], r12d
    mov     eax, r12d
    shl     eax, 6
    lea     rbx, [rel mood_tab]
    add     rbx, rax
    mov     [rel seq_moodp], rbx
    mov     eax, [rbx+MOODP.pad_cut]
    mov     [rel seq_padcut], eax
    mov     eax, [rbx+MOODP.bright]
    mov     [rel seq_bright], eax
    mov     eax, [rbx+MOODP.scale]
    mov     [rel seq_scale], eax
    mov     eax, [rbx+MOODP.scale_len]
    mov     [rel seq_scale_len], eax
    mov     eax, [rbx+MOODP.chord_len]
    mov     [rel seq_chord_len], eax
    ; step_sec * fs * 0.94..1.06, exact for the title theme
    movss   xmm6, [rbx+MOODP.step_sec]
    mulss   xmm6, [rel m_fs]
    cmp     r12d, MOOD_MENU
    je      .tempo
    call    mr_randf
    mulss   xmm0, [rel m_tempo_r]
    addss   xmm0, [rel m_tempo_lo]
    mulss   xmm6, xmm0
.tempo:
    cvttss2si eax, xmm6
    mov     [rel seq_step_len], eax
    mov     dword [rel seq_ctr], 0
    mov     dword [rel seq_step], 0
    ; rounded down to whole chords
    mov     ecx, [rbx+MOODP.steps_max]
    sub     ecx, [rbx+MOODP.steps_min]
    inc     ecx
    call    mr_randn
    add     eax, [rbx+MOODP.steps_min]
    xor     edx, edx
    div     dword [rbx+MOODP.chord_len]
    imul    eax, [rbx+MOODP.chord_len]
    mov     [rel seq_total], eax
    call    mr_rand
    and     eax, 3
    movzx   eax, byte [rbx+MOODP.roots+rax]
    mov     [rel seq_root], eax
    call    mr_rand
    and     eax, 3
    mov     ecx, r12d
    shl     ecx, 4
    lea     ecx, [rcx+rax*4]
    lea     rdx, [rel progs]
    mov     eax, [rdx+rcx]
    mov     [rel seq_prog], eax
    mov     eax, [rel seq_prog]
    movzx   eax, al
    mov     [rel seq_chord], eax
    ; start in the middle of the 2-octave range
    mov     ecx, [rel seq_scale_len]
    call    mr_randn
    mov     ecx, [rel seq_scale_len]
    shr     ecx, 1
    add     eax, ecx
    mov     [rel seq_mel_deg], eax
    mov     dword [rel seq_mel_wait], 1
    lea     rdi, [rel seq_motif]
    mov     al, 0x80
    mov     ecx, 32
    rep     stosb
    mov     dword [rel seq_motif_n], 0
    mov     dword [rel seq_shift], 0
    mov     eax, [rel m_one]
    mov     [rel seq_fade], eax
    mov     dword [rel seq_tail], 0
    mov     dword [rel seq_state], SQ_PLAY
    mov     dword [rel mus_playing], 1
ENDPX

PROCX music_play_mel, 16
    mov     ebx, edx
    movaps  xmm6, xmm2
    call    music_note_of
    mov     rcx, [rel seq_moodp]
    add     eax, [rel seq_root]
    add     eax, [rcx+MOODP.mel_oct]
    mov     r12d, eax
    mov     r13d, [rcx+MOODP.mel_inst]
    ; *0.9 leaves a small gap between notes
    cvtsi2ss xmm0, ebx
    cvtsi2ss xmm1, dword [rel seq_step_len]
    mulss   xmm0, xmm1
    mulss   xmm0, [rel m_dur_mul]
    cvttss2si r14d, xmm0
    call    mr_randf  ; pan +-0.35
    subss   xmm0, [rel m_half]
    mulss   xmm0, [rel m_panw]
    movaps  xmm3, xmm0
    movaps  xmm2, xmm6
    mov     ecx, r13d
    mov     edx, r12d
    mov     r8d, r14d
    call    music_note_on
ENDPX

align 16
music_mel_vel:
    sub     rsp, 40
    call    mr_randf
    mulss   xmm0, [rel m_mel_v1]
    addss   xmm0, [rel m_mel_v0]
    add     rsp, 40
    ret

; ecx pos 0..63, edx = second pass
PROCX music_theme_step, 16
    mov     r12d, ecx
    mov     r13d, edx
    lea     rsi, [rel theme]
    xor     r15d, r15d
.ev:
    movzx   eax, byte [rsi]
    cmp     eax, 0xFF
    je      .evd
    cmp     eax, r12d
    jne     .evn
    movzx   r14d, byte [rsi+1]
    movzx   eax, byte [rsi+3]
    cvtsi2ss xmm0, eax
    cvtsi2ss xmm1, dword [rel seq_step_len]
    mulss   xmm0, xmm1
    mulss   xmm0, [rel m_thm_dur]
    cvttss2si r8d, xmm0
    movzx   eax, byte [rsi+4]
    cvtsi2ss xmm2, eax
    mulss   xmm2, [rel m_inv127]
    xorps   xmm3, xmm3
    cmp     r14d, I_BELL
    jne     .np1
    movss   xmm3, [rel m_bellpan]
.np1:
    cmp     r14d, I_EP
    jne     .np2
    movss   xmm3, [rel m_eppan]
.np2:
    cmp     r14d, I_PAD
    jne     .np3
    mov     eax, r15d  ; -0.5, 0, +0.5, -0.5 ...
    inc     r15d
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    dec     edx
    cvtsi2ss xmm3, edx
    mulss   xmm3, [rel m_padpan]
.np3:
    mov     ecx, r14d
    movzx   edx, byte [rsi+2]
    call    music_note_on
.evn:
    add     rsi, 5
    jmp     .ev
.evd:
    ; second pass: generated counter-melody, soft high bells
    test    r13d, r13d
    jz      .done
    test    r12d, 1
    jnz     .done
    call    mr_randf
    comiss  xmm0, [rel m_ctr_p]
    jae     .done
    mov     ecx, 5
    call    mr_randn
    mov     ecx, eax
    call    music_note_of
    lea     r12d, [rax+74]
    cvtsi2ss xmm0, dword [rel seq_step_len]
    addss   xmm0, xmm0
    cvttss2si r14d, xmm0
    call    mr_randf
    subss   xmm0, [rel m_half]
    mulss   xmm0, [rel m_panw]
    movaps  xmm3, xmm0
    movss   xmm2, [rel m_ctr_v]
    mov     ecx, I_BELL
    mov     edx, r12d
    mov     r8d, r14d
    call    music_note_on
.done:
ENDPX

PROCX music_seq_step, 32
    cmp     dword [rel seq_state], SQ_PLAY
    jne     .done
    mov     r12d, [rel seq_step]
    cmp     r12d, [rel seq_total]
    jl      .go
    mov     dword [rel seq_state], SQ_TAIL  ; done composing, let it ring out
    mov     dword [rel seq_tail], 0
    jmp     .done
.go:
    mov     rbx, [rel seq_moodp]
    cmp     dword [rel seq_mood], MOOD_MENU
    jne     .gen
    mov     ecx, r12d
    and     ecx, 63
    xor     edx, edx
    cmp     r12d, 64
    setge   dl
    call    music_theme_step
    jmp     .next

.gen:
    mov     eax, r12d
    xor     edx, edx
    div     dword [rel seq_chord_len]
    test    edx, edx
    jnz     .melody
    and     eax, 3
    lea     rcx, [rel seq_prog]
    movzx   eax, byte [rcx+rax]
    mov     [rel seq_chord], eax
    ; triad d, d+2, d+4. in a pentatonic that's open sus/add6 chords, never clashes
    cmp     dword [rbx+MOODP.pad], 0
    je      .nopad
    xor     r13d, r13d
.padn:
    mov     ecx, [rel seq_chord]
    lea     ecx, [rcx+r13*2]
    call    music_note_of
    add     eax, [rel seq_root]
    mov     r14d, eax
    mov     eax, [rel seq_chord_len]  ; + half a step of overlap
    imul    eax, [rel seq_step_len]
    mov     ecx, [rel seq_step_len]
    shr     ecx, 1
    add     eax, ecx
    mov     r15d, eax
    call    mr_randf
    mulss   xmm0, [rel m_pad_vr]
    addss   xmm0, [rel m_pad_v]
    movaps  xmm2, xmm0
    lea     eax, [r13-1]
    cvtsi2ss xmm3, eax
    mulss   xmm3, [rel m_padpan]
    mov     ecx, I_PAD
    mov     edx, r14d
    mov     r8d, r15d
    call    music_note_on
    inc     r13d
    cmp     r13d, 3
    jb      .padn
.nopad:
    ; bass on the root most of the time
    cmp     dword [rbx+MOODP.bass], 0
    je      .nobass
    call    mr_randf
    comiss  xmm0, [rel m_bass_p]
    jae     .nobass
    mov     ecx, [rel seq_chord]
    call    music_note_of
    add     eax, [rel seq_root]
    sub     eax, 12
    mov     r14d, eax
    mov     eax, [rel seq_chord_len]
    shr     eax, 1
    imul    eax, [rel seq_step_len]
    mov     r8d, eax
    movss   xmm2, [rel m_bass_v]
    xorps   xmm3, xmm3
    mov     ecx, I_BASS
    mov     edx, r14d
    call    music_note_on
.nobass:
    ; cave: root+fifth drone for the whole piece
    cmp     dword [rbx+MOODP.drone], 0
    je      .melody
    test    r12d, r12d
    jnz     .melody
    mov     eax, [rel seq_total]
    imul    eax, [rel seq_step_len]
    mov     r15d, eax
    movss   xmm2, [rel m_drone_v]
    movss   xmm3, [rel m_drone_pan]
    xorps   xmm0, xmm0
    subss   xmm0, xmm3
    movaps  xmm3, xmm0
    mov     ecx, I_DRONE
    mov     edx, [rel seq_root]
    mov     r8d, r15d
    call    music_note_on
    movss   xmm2, [rel m_drone_v]
    mulss   xmm2, [rel m_half]
    movss   xmm3, [rel m_drone_pan]
    mov     ecx, I_DRONE
    mov     edx, [rel seq_root]
    add     edx, 7
    mov     r8d, r15d
    call    music_note_on

.melody:
    ; replay the motif in steps 48-63, 112-127, ... (every 4th block of 16)
    mov     eax, r12d
    shr     eax, 4
    and     eax, 3
    cmp     eax, 3
    jne     .walk
    cmp     dword [rel seq_motif_n], 2
    jl      .walk
    mov     r13d, r12d
    and     r13d, 15
    jnz     .replay
    mov     ecx, 5
    call    mr_randn
    lea     rcx, [rel shift_tab]
    movsx   eax, byte [rcx+rax]
    mov     [rel seq_shift], eax
.replay:
    lea     rcx, [rel seq_motif]
    movsx   eax, byte [rcx+r13*2]
    cmp     eax, -128
    je      .next
    movzx   r14d, byte [rcx+r13*2+1]
    add     eax, [rel seq_shift]
    mov     r15d, eax
    call    music_mel_vel
    movaps  xmm2, xmm0
    mov     ecx, r15d
    mov     edx, r14d
    call    music_play_mel
    jmp     .next

.walk:
    cmp     dword [rel seq_mel_wait], 0
    jle     .decide
    dec     dword [rel seq_mel_wait]
    jmp     .next
.decide:
    call    mr_randf
    comiss  xmm0, [rbx+MOODP.rest_p]
    jae     .notrest
    mov     ecx, 3  ; rest 1..3
    call    mr_randn
    mov     [rel seq_mel_wait], eax
    jmp     .next
.notrest:
    call    mr_randf
    comiss  xmm0, [rbx+MOODP.note_p]
    jae     .next  ; sparse moods skip slots
    call    mr_rand
    and     eax, 7
    lea     rcx, [rel walk_tab]
    movsx   eax, byte [rcx+rax]
    add     eax, [rel seq_mel_deg]
    ; reflect into [0, 2 len - 1]
    mov     ecx, [rel seq_scale_len]
    add     ecx, ecx
    dec     ecx
    test    eax, eax
    jns     .r1
    neg     eax
.r1:
    cmp     eax, ecx
    jle     .r2
    sub     eax, ecx
    neg     eax
    add     eax, ecx
.r2:
    mov     [rel seq_mel_deg], eax
    ; chord change: half the time snap to the root, same octave
    mov     eax, r12d
    xor     edx, edx
    div     dword [rel seq_chord_len]
    test    edx, edx
    jnz     .nosnap
    call    mr_rand
    test    eax, 1
    jz      .nosnap
    mov     eax, [rel seq_mel_deg]
    xor     edx, edx
    div     dword [rel seq_scale_len]
    imul    eax, [rel seq_scale_len]
    add     eax, [rel seq_chord]
    mov     [rel seq_mel_deg], eax
.nosnap:
    call    mr_rand
    and     eax, 7
    lea     rcx, [rel dur_tab]
    movzx   r14d, byte [rcx+rax]
    call    music_mel_vel
    movaps  xmm6, xmm0
    movaps  xmm2, xmm0
    mov     ecx, [rel seq_mel_deg]
    mov     edx, r14d
    call    music_play_mel
    ; first 16 steps = the motif, replaying it is what makes it sound like a theme
    cmp     r12d, 16
    jae     .norec
    lea     rcx, [rel seq_motif]
    mov     eax, [rel seq_mel_deg]
    mov     [rcx+r12*2], al
    mov     [rcx+r12*2+1], r14b
    inc     dword [rel seq_motif_n]
.norec:
    lea     eax, [r14-1]
    mov     [rel seq_mel_wait], eax
    ; day only, sometimes a third below
    cmp     dword [rel seq_mood], MOOD_DAY
    jne     .next
    call    mr_randf
    comiss  xmm0, [rel m_harm_p]
    jae     .next
    movaps  xmm2, xmm6
    mulss   xmm2, [rel m_harm_v]
    mov     ecx, [rel seq_mel_deg]
    sub     ecx, 2
    mov     edx, r14d
    call    music_play_mel
.next:
    inc     dword [rel seq_step]
.done:
ENDPX

PROC music_finish, 0
    call    music_kill_all
    mov     dword [rel seq_state], SQ_IDLE
    mov     dword [rel mus_playing], 0
    mov     eax, [rel mr_cur_serial]
    mov     [rel mus_finished_serial], eax
ENDP

; called from audio_mix_block
PROCX music_render, 32
    mov     rdi, rcx
    mov     r12d, edx
    cmp     dword [rel rev_ready], 0
    jne     .rv
    call    music_rev_setup
.rv:
    mov     eax, [rel mus_start_serial]
    cmp     eax, [rel mr_seen_start]
    je      .nostart
    mov     [rel mr_seen_start], eax
    cmp     dword [rel seq_state], SQ_IDLE
    je      .st
    mov     ecx, [rel mr_cur_serial]  ; old piece still going: drop it, report it finished
    mov     [rel mus_finished_serial], ecx
.st:
    mov     [rel mr_cur_serial], eax
    mov     ecx, [rel mus_req_mood]
    mov     edx, [rel mus_req_seed]
    call    music_seq_start
.nostart:
    mov     eax, [rel mus_stop_serial]
    cmp     eax, [rel mr_seen_stop]
    je      .nostop
    mov     [rel mr_seen_stop], eax
    cmp     dword [rel seq_state], SQ_IDLE
    je      .nostop
    mov     dword [rel seq_state], SQ_FADE
.nostop:
    cmp     dword [rel seq_state], SQ_IDLE
    je      .done

    xor     r13d, r13d
.blk:
    mov     r14d, r12d
    sub     r14d, r13d
    jle     .done
    cmp     r14d, SUB
    jbe     .n
    mov     r14d, SUB
.n:
    cmp     dword [rel seq_state], SQ_PLAY
    jne     .noseq
    sub     [rel seq_ctr], r14d
.seq:
    cmp     dword [rel seq_ctr], 0
    jg      .noseq
    call    music_seq_step
    mov     eax, [rel seq_step_len]
    add     [rel seq_ctr], eax
    cmp     dword [rel seq_state], SQ_PLAY
    je      .seq
.noseq:
    lea     rcx, [rel mr_dry]
    lea     rdx, [rel mr_send]
    xorps   xmm0, xmm0
    xor     eax, eax
.clr:
    movss   [rcx+rax*8], xmm0
    movss   [rcx+rax*8+4], xmm0
    movss   [rdx+rax*4], xmm0
    inc     eax
    cmp     eax, r14d
    jb      .clr
    lea     rbx, [rel mvoices]
    xor     r15d, r15d
    xor     esi, esi
.vl:
    cmp     dword [rbx+MV.active], 0
    je      .vn
    mov     rcx, rbx
    mov     edx, r14d
    call    music_voice_render
    add     r15d, [rbx+MV.active]
.vn:
    add     rbx, MV_size
    inc     esi
    cmp     esi, NMV
    jb      .vl
    ; music_vol * base * fade, smoothed
    lea     rax, [rel g_settings] ; v1: music scratch #0
    ; FIXME: negative world x/z needs sar 4, not shr 4 (music:0)
    movss   xmm0, [rax+SETTINGS.music_vol] ; v1: music scratch #1
    maxss   xmm0, [rel m_zero] ; v1: music scratch #2
    ; TODO: verify 16-byte rsp alignment before inner call (music:2)
    minss   xmm0, [rel m_one] ; v1: music scratch #3
    mulss   xmm0, [rel m_base_vol] ; v1: music scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (music:4)
    mulss   xmm0, [rel seq_fade] ; v1: music scratch #5
    subss   xmm0, [rel mr_level] ; v1: music scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (music:6)
    mulss   xmm0, [rel m_lvl_k] ; v1: music scratch #7
    addss   xmm0, [rel mr_level] ; v1: music scratch #8
    ; TODO: hoist invariant pointer load out of .loop (music:8)
    movss   [rel mr_level], xmm0 ; v1: music scratch #9
    movaps  xmm8, xmm0 ; v1: music scratch #10
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (music:10)
    movss   xmm9, [rel mres_l] ; v1: music scratch #11
    movss   xmm11, [rel mres_r] ; v1: music scratch #12
    ; note: rcx = state ptr, rdx = index, r8d = flags (music:12)
    movss   xmm12, [rel m_resdecay] ; v1: music scratch #13
    xor     esi, esi ; v1: music scratch #14
    ; TODO: clamp index before table lookup on malformed input (music:14)
.rs: ; v1: music scratch #15
    lea     rax, [rel mr_send] ; v1: music scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (music:16)
    movss   xmm0, [rax+rsi*4] ; v1: music scratch #17
    mulss   xmm0, [rel m_rev_in] ; v1: music scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (music:18)
    movaps  xmm6, xmm0 ; v1: music scratch #19
    lea     rcx, [rel combs] ; v1: music scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (music:20)
    lea     rdx, [rel apfs] ; v1: music scratch #21
    call    music_rev_channel ; v1: music scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (music:22)
    movaps  xmm7, xmm0 ; v1: music scratch #23
    movaps  xmm0, xmm6 ; v1: music scratch #24
    ; TODO: hoist invariant pointer load out of .loop (music:24)
    lea     rcx, [rel combs + COMB_size*4] ; v1: music scratch #25
    lea     rdx, [rel apfs + APF_size*2] ; v1: music scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (music:26)
    call    music_rev_channel ; v1: music scratch #27
    lea     rax, [rel mr_dry] ; v1: music scratch #28
    ; note: rcx = state ptr, rdx = index, r8d = flags (music:28)
    mulss   xmm7, [rel m_rev_wet] ; v1: music scratch #29
    mulss   xmm0, [rel m_rev_wet] ; v1: music scratch #30
    ; TODO: clamp index before table lookup on malformed input (music:30)
    addss   xmm7, [rax+rsi*8] ; v1: music scratch #31
    addss   xmm0, [rax+rsi*8+4] ; v1: music scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (music:32)
    addss   xmm7, xmm9 ; v1: music scratch #33
    addss   xmm0, xmm11 ; v1: music scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (music:34)
    mulss   xmm9, xmm12 ; v1: music scratch #35
    mulss   xmm11, xmm12 ; v1: music scratch #36
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (music:36)
    mulss   xmm7, xmm8 ; v1: music scratch #37
    mulss   xmm0, xmm8 ; v1: music scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (music:38)
    lea     eax, [r13+rsi] ; v1: music scratch #39
    lea     rcx, [rdi+rax*8] ; v1: music scratch #40
    ; TODO: hoist invariant pointer load out of .loop (music:40)
    addss   xmm7, [rcx] ; v1: music scratch #41
    addss   xmm0, [rcx+4]
    movss   [rcx], xmm7
    movss   [rcx+4], xmm0
    inc     esi
    cmp     esi, r14d
    jb      .rs
    movss   [rel mres_l], xmm9
    movss   [rel mres_r], xmm11
    cmp     dword [rel seq_state], SQ_FADE
    jne     .nf
    movss   xmm0, [rel seq_fade]
    subss   xmm0, [rel m_fade_step]
    maxss   xmm0, [rel m_zero]
    movss   [rel seq_fade], xmm0
    comiss  xmm0, [rel m_zero]
    ja      .adv
    ; mr_level is smoothed and lags the fade by a few %, so killing right when fade hits 0
    ; leaves an audible step. wait for the smoothed level instead, bit hacky
    movss   xmm0, [rel mr_level]
    comiss  xmm0, [rel m_lvl_end]
    jae     .adv
    call    music_finish
    jmp     .done
.nf:
    cmp     dword [rel seq_state], SQ_TAIL
    jne     .adv
    add     [rel seq_tail], r14d
    mov     eax, [rel seq_tail]
    cmp     eax, FS_HZ*20  ; 20 s cap for long releases (cave drones)
    jge     .tofade  ; fade those, never hard cut
    test    r15d, r15d
    jnz     .adv
    cmp     eax, FS_HZ*3  ; 3 s of reverb tail
    jl      .adv
    jmp     .fin
.tofade:
    mov     dword [rel seq_state], SQ_FADE
    jmp     .adv
.fin:
    call    music_finish
    jmp     .done
.adv:
    add     r13d, r14d
    jmp     .blk
.done:
ENDPX

; -> mood from game state
PROC music_detect, 16
    mov     eax, MOOD_MENU
    cmp     dword [rel g_world_active], 0
    je      .done
    cmp     dword [rel g_state], ST_CREATEWORLD
    jbe     .done
    lea     rbx, [rel g_player]
    movss   xmm0, [rbx+PLAYER.y]
    comiss  xmm0, [rel m_cave_y]
    jae     .sky
    ; cave = below y 52 and sky light at the head < 6
    movss   xmm0, [rbx+PLAYER.x]
    roundss xmm0, xmm0, 1
    cvttss2si ecx, xmm0
    movss   xmm0, [rbx+PLAYER.y]
    addss   xmm0, [rel m_eye]
    roundss xmm0, xmm0, 1
    cvttss2si edx, xmm0
    movss   xmm0, [rbx+PLAYER.z]
    roundss xmm0, xmm0, 1
    cvttss2si r8d, xmm0
    call    world_get_light
    shr     eax, 4
    and     eax, 15
    cmp     eax, 6
    mov     eax, MOOD_CAVE
    jb      .done
.sky:
    mov     ecx, [rel g_time_of_day]
    mov     eax, MOOD_DAY
    cmp     ecx, 12800
    jb      .done
    cmp     ecx, 23200
    jae     .done
    mov     eax, MOOD_NIGHT
.done:
ENDP

PROC music_request_stop, 0
    cmp     dword [rel mt_stop_sent], 0
    jne     .done
    mov     dword [rel mt_stop_sent], 1
    lock inc dword [rel mus_stop_serial]
.done:
ENDP

; menu <-> world restarts the music
PROC music_apply_mood, 16
    mov     ebx, ecx
    cmp     ebx, [rel mt_mood]
    je      .done
    mov     r12d, [rel mt_mood]
    mov     [rel mt_mood], ebx
    ; in-world the next piece just picks up the new mood
    xor     eax, eax
    cmp     r12d, MOOD_MENU
    sete    al
    xor     edx, edx
    cmp     ebx, MOOD_MENU
    sete    dl
    cmp     eax, edx
    je      .done
    ; menu: restart soon, world: 8-25 s later
    mov     r13d, 1200
    cmp     ebx, MOOD_MENU
    je      .dl
    mov     ecx, 17000
    call    mt_randn
    lea     r13d, [rax+8000]
.dl:
    cmp     dword [rel mt_waiting], 0
    je      .idle
    mov     [rel mt_override], r13d
    call    music_request_stop
    jmp     .done
.idle:
    call    GetTickCount64
    add     rax, r13
    mov     [rel mt_next_ms], rax
.done:
ENDP
    ; v1 temporary guard (music #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (music #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (music #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (music #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (music #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (music #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (music #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (music #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (music #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (music #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (music #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (music #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (music #45)
    xor     r11d, r11d ; clear v1 slot 45
