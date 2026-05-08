; 44.1kHz 16-bit stereo waveOut ring (4 x 1024 frames), procedural sfx synth
%define IMPL_AUDIO
%include "common.inc"

extern music_render

%define FS_HZ           44100
%define MIX_FRAMES      1024
%define NUM_BUFS        4
%define MAX_VOICES      32
%define QCAP            64              ; cmd ring size, keep it a power of two
%define NVAR            3
%define NSTEP_SFX       9  ; footsteps, not in api.inc
%define SFX_STEP_BASE   SFX_COUNT
%define NSFX            (SFX_COUNT + NSTEP_SFX)
%define WAVEHDR_SIZE    48
%define WH_FLAGS        24  ; WAVEHDR.dwFlags (x64)
%define THREAD_PRIORITY_HIGHEST 2

%define K_NOISE         0
%define K_SINE          1
%define K_SAW           2
%define K_SQUARE        3
%define K_TRI           4
%define K_DUST          5
%define F_NONE          0
%define F_LP            1
%define F_BP            2
%define F_HP            3

struc LYR  ; 96 bytes, all float except kind/filt
    .kind   resd 1
    .filt   resd 1
    .start  resd 1
    .dur    resd 1
    .att    resd 1
    .dec    resd 1  ; decay time constant, s
    .amp    resd 1
    .f0     resd 1
    .f1     resd 1  ; exp glide
    .fmr    resd 1
    .fmi    resd 1  ; radians, env scales it
    .c0     resd 1
    .c1     resd 1
    .q      resd 1
    .lrate  resd 1
    .lpitch resd 1
    .lamp   resd 1
    .lcut   resd 1
    .grain  resd 1  ; Hz. for dust it's impulses/s
    .drive  resd 1  ; 0 = off
    .nmix   resd 1  ; breath noise on osc sources
    .pad    resd 3
endstruc

struc PHDR  ; 16 bytes, then .n LAYERs
    .n      resd 1
    .peak   resd 1
    .spread resd 1  ; variant pitch/cutoff spread
    .pad    resd 1
endstruc

struc VOICE  ; 48 bytes
    .data   resq 1
    .pos    resq 1  ; 32.32
    .step   resq 1  ; 32.32, = pitch
    .len    resd 1
    .gl     resd 1
    .gr     resd 1
    .active resd 1
    .serial resd 1  ; oldest gets stolen
    .pad    resd 1
endstruc

struc QENT
    .id     resd 1
    .gl     resd 1
    .gr     resd 1
    .pitch  resd 1
endstruc

section .rdata
align 16
f_absmask:  dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
f_signmask: dd 0x80000000, 0x80000000, 0x80000000, 0x80000000
f_zero:     dd 0.0
f_one:      dd 1.0
f_mone:     dd -1.0
f_two:      dd 2.0
f_three:    dd 3.0
f_mthree:   dd -3.0
f_four:     dd 4.0
f_half:     dd 0.5
f_quarter:  dd 0.25
f_mquarter: dd -0.25
f_mhalf:    dd -0.5
f_fs:       dd 44100.0
f_inv_fs:   dd 0.0000226757369615       ; 1/44100
f_inv_4fs:  dd 0.00000566893424  ; 1/(4 fs), svf is 2x oversampled
f_twopi:    dd 6.28318530718
f_inv_twopi: dd 0.159154943092
; sin taylor to x^9, err < 4e-6
f_s3:       dd -0.166666666667
f_s5:       dd 0.00833333333333
f_s7:       dd -0.000198412698413
f_s9:       dd 0.00000275573192
f_log2e:    dd 1.44269504089
f_ln2:      dd 0.69314718056
f_expmin:   dd -87.0
f_expmax:   dd 88.0
f_e1:       dd 0.69314718056  ; 2^f coefs, |f| <= 0.5
f_e2:       dd 0.240226506959
f_e3:       dd 0.0555041086648
f_e4:       dd 0.00961812910763
f_e5:       dd 0.00133335581464
f_e6:       dd 0.000154035303934
f_l3:       dd 0.333333333333
f_l5:       dd 0.2
f_l7:       dd 0.142857142857
f_l9:       dd 0.111111111111
f_27:       dd 27.0
f_9:        dd 9.0
f_knee:     dd 0.65
f_1mknee:   dd 0.35
f_inv1mknee: dd 2.85714285714
f_32767:    dd 32767.0
f_2p32:     dd 4294967296.0
f_inv2p32:  dd 2.3283064365e-10
f_minq:     dd 0.72                     ; below this q the SVF goes unstable
f_cutmin:   dd 20.0
f_cutmax:   dd 16000.0
f_svfmax:   dd 1.0
f_gmin:     dd 0.1
f_gscale:   dd 0.9
f_dcpole:   dd 0.995
f_tiny:     dd 0.000001
f_eye:      dd 1.62
f_inv16:    dd 0.0625
f_inv360:   dd 0.00277777777778
f_panamt:   dd 0.6
f_jitter:   dd 0.05
f_pmin:     dd 0.1
f_pmax:     dd 4.0
f_resdecay: dd 0.9965  ; ~6.5 ms
; in units of PHDR.spread
var_pitch:  dd 0.0, 1.0, -1.0
var_cut:    dd 0.0, -0.6, 0.9
; SND_* -> sfx id
mat_dig:    db SFX_DIG_STONE, SFX_DIG_DIRT, SFX_DIG_GRASS, SFX_DIG_WOOD, SFX_DIG_SAND
            db SFX_DIG_GRAVEL, SFX_GLASS_BREAK, SFX_DIG_SNOW, SFX_DIG_WOOL
mat_place:  db SFX_DIG_STONE, SFX_DIG_DIRT, SFX_DIG_GRASS, SFX_DIG_WOOD, SFX_DIG_SAND
            db SFX_DIG_GRAVEL, SFX_STEP_BASE+SND_GLASS, SFX_DIG_SNOW, SFX_DIG_WOOL
align 4
; 0 break 1 place 2 step 3 hit
kind_vol:   dd 1.0, 0.9, 0.4, 0.35
kind_pitch: dd 1.0, 0.82, 1.0, 1.35
f_placevol: dd 0.45

msg_open_fail: db "audio: waveOutOpen failed - running without sound", 0
msg_ready:     db "audio: 44100 Hz stereo mixer running, 36 procedural sounds x 3 variants", 0

section .bss
alignb 16
mix_acc:    resd MIX_FRAMES*2
voices:     resb VOICE_size*MAX_VOICES
q_buf:      resb QENT_size*QCAP
pcm_bufs:   resb MIX_FRAMES*4*NUM_BUFS
wave_hdrs:  resb WAVEHDR_SIZE*NUM_BUFS
aud_cs:     resb 64  ; CRITICAL_SECTION is 40 bytes, padded
bank_ptr:   resq NSFX*NVAR
bank_len:   resd NSFX*NVAR
alignb 8
aud_hwo:    resq 1
aud_event:  resq 1
aud_thread: resq 1
bank_arena: resq 1
wfx:        resb 24
q_head:     resd 1
q_tail:     resd 1
aud_ok:     resd 1
aud_accept: resd 1  ; sfx_play* only queue while set
aud_quit:   resd 1
cs_inited:  resd 1
bank_ready: resd 1
voice_serial: resd 1
syn_rng:    resd 1  ; only one thread synthesizes at a time
mix_rng:    resd 1
play_rng:   resd 1  ; racy, doesn't matter
syn_pitch:  resd 1
syn_cut:    resd 1
res_l:      resd 1  ; mixer thread only
res_r:      resd 1

section .text

; leaf helpers, not win64 abi: arg/result in xmm0, no stack, only clobber what's listed.
; music.asm uses sin01/exp/ln/softclip too

; xmm0 in cycles -> sin(2pi x), clobbers xmm1-2. folds to [-.25,.25] then odd poly
global audio_sin01
align 16
audio_sin01:
    roundss xmm1, xmm0, 0
    subss   xmm0, xmm1
    comiss  xmm0, [rel f_quarter]
    jbe     .lo
    movss   xmm1, [rel f_half]
    subss   xmm1, xmm0
    movaps  xmm0, xmm1
    jmp     .poly
.lo:
    comiss  xmm0, [rel f_mquarter]
    jae     .poly
    movss   xmm1, [rel f_mhalf]
    subss   xmm1, xmm0
    movaps  xmm0, xmm1
.poly:
    mulss   xmm0, [rel f_twopi]
    movaps  xmm1, xmm0
    mulss   xmm1, xmm1
    movss   xmm2, [rel f_s9]
    mulss   xmm2, xmm1
    addss   xmm2, [rel f_s7]
    mulss   xmm2, xmm1
    addss   xmm2, [rel f_s5]
    mulss   xmm2, xmm1
    addss   xmm2, [rel f_s3]
    mulss   xmm2, xmm1
    addss   xmm2, [rel f_one]
    mulss   xmm0, xmm2
    ret

; e^x, clobbers xmm1-2, eax.
; must round to nearest, not floor: decay factors like exp(-1/(dec*fs)) sit within
; 1e-5 of 1 and need the precision
global audio_exp
align 16
audio_exp:
    maxss   xmm0, [rel f_expmin]
    minss   xmm0, [rel f_expmax]
    mulss   xmm0, [rel f_log2e]
    roundss xmm1, xmm0, 0
    subss   xmm0, xmm1
    cvtss2si eax, xmm1
    movss   xmm2, [rel f_e6]
    mulss   xmm2, xmm0
    addss   xmm2, [rel f_e5]
    mulss   xmm2, xmm0
    addss   xmm2, [rel f_e4]
    mulss   xmm2, xmm0
    addss   xmm2, [rel f_e3]
    mulss   xmm2, xmm0
    addss   xmm2, [rel f_e2]
    mulss   xmm2, xmm0
    addss   xmm2, [rel f_e1]
    mulss   xmm2, xmm0
    addss   xmm2, [rel f_one]
    add     eax, 127
    cmp     eax, 1
    jge     .e1
    mov     eax, 1
.e1:
    cmp     eax, 254
    jle     .e2
    mov     eax, 254
.e2:
    shl     eax, 23
    movd    xmm0, eax
    mulss   xmm0, xmm2
    ret

; ln x, clobbers xmm1-3, eax, edx. x <= 0 returns -87 instead of NaN
global audio_ln
align 16
audio_ln:
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    ja      .pos
    movss   xmm0, [rel f_expmin]
    ret
.pos:
    movd    eax, xmm0
    mov     edx, eax
    shr     edx, 23
    and     edx, 255
    sub     edx, 127
    and     eax, 0x007FFFFF
    or      eax, 0x3F800000
    movd    xmm0, eax
    movaps  xmm1, xmm0
    subss   xmm1, [rel f_one]
    addss   xmm0, [rel f_one]
    divss   xmm1, xmm0
    movaps  xmm2, xmm1
    mulss   xmm2, xmm2
    movss   xmm3, [rel f_l9]
    mulss   xmm3, xmm2
    addss   xmm3, [rel f_l7]
    mulss   xmm3, xmm2
    addss   xmm3, [rel f_l5]
    mulss   xmm3, xmm2
    addss   xmm3, [rel f_l3]
    mulss   xmm3, xmm2
    addss   xmm3, [rel f_one]
    mulss   xmm3, xmm1
    addss   xmm3, xmm3
    cvtsi2ss xmm0, edx
    mulss   xmm0, [rel f_ln2]
    addss   xmm0, xmm3
    ret

; x(27+x^2)/(27+9x^2), clamped to +-3 so it's exactly +-1 there. clobbers xmm1-2
global audio_softclip
align 16
audio_softclip:
    maxss   xmm0, [rel f_mthree]
    minss   xmm0, [rel f_three]
    movaps  xmm1, xmm0
    mulss   xmm1, xmm1
    movss   xmm2, [rel f_27]
    addss   xmm2, xmm1
    mulss   xmm0, xmm2
    mulss   xmm1, [rel f_9]
    addss   xmm1, [rel f_27]
    divss   xmm0, xmm1
    ret

; clobber eax, edx. float via mantissa bits
align 16
syn_next:
    mov     eax, [rel syn_rng]
    mov     edx, eax
    shl     edx, 13
    xor     eax, edx
    mov     edx, eax
    shr     edx, 17
    xor     eax, edx
    mov     edx, eax
    shl     edx, 5
    xor     eax, edx
    mov     [rel syn_rng], eax
    ret
align 16
syn_frand:
    call    syn_next
    shr     eax, 9
    or      eax, 0x40000000
    movd    xmm0, eax
    subss   xmm0, [rel f_three]
    ret
align 16
syn_urand:
    call    syn_next
    shr     eax, 9
    or      eax, 0x3F800000
    movd    xmm0, eax
    subss   xmm0, [rel f_one]
    ret

; xorshift32 on [rcx], clobbers edx. 0 state gets reseeded
align 16
xs32_step:
    mov     eax, [rcx]
    test    eax, eax
    jnz     .ok
    mov     eax, 0x2545F491
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

%define L_ATTN      0  ; int
%define L_FADEN     4  ; int
%define L_KDEC      8
%define L_KF        12
%define L_KC        16
%define L_DAMP      20
%define L_LFOINC    24
%define L_GPER      28
%define L_GCNT      32  ; int
%define L_SVF       36
%define L_DUSTP     40
%define L_FMI       44  ; cycles
%define L_AMP       48
%define L_ENV       52
%define L_S         56
%define L_INC       60
%define L_P         64  ; after FM

; renders one layer and adds it on top of what is already in buf. loop keeps everything in regs:
; xmm6 env, xmm7 freq, xmm8/9 osc/fm phase, xmm10 cutoff, xmm11/12 svf low/band,
; xmm13/14 lfo phase/val, xmm15 grain gain, r12d n, r13d i
PROCX audio_synth_layer, 80
    mov     rbx, rcx
    mov     rdi, rdx
    mov     esi, r8d
    movss   xmm0, [rbx+LYR.start]
    mulss   xmm0, [rel f_fs]
    cvttss2si eax, xmm0
    test    eax, eax
    jns     .s0
    xor     eax, eax
.s0:
    cmp     eax, esi
    jge     .done
    lea     rdi, [rdi+rax*4]
    sub     esi, eax
    movss   xmm0, [rbx+LYR.dur]
    mulss   xmm0, [rel f_fs]
    cvttss2si r12d, xmm0
    cmp     r12d, esi
    cmovg   r12d, esi
    cmp     r12d, 8
    jl      .done
    movss   xmm0, [rbx+LYR.att]
    mulss   xmm0, [rel f_fs]
    cvttss2si eax, xmm0
    cmp     eax, 1
    jge     .a0
    mov     eax, 1
.a0:
    mov     LOC(L_ATTN), eax
    mov     eax, r12d
    shr     eax, 2
    cmp     eax, 441                    ; 10 ms
    jbe     .f0
    mov     eax, 441
.f0:
    mov     LOC(L_FADEN), eax
    ; k = exp(-1/(dec*fs))
    movss   xmm0, [rbx+LYR.dec]
    mulss   xmm0, [rel f_fs]
    maxss   xmm0, [rel f_one]
    movss   xmm1, [rel f_mone]
    divss   xmm1, xmm0
    movaps  xmm0, xmm1
    call    audio_exp
    movss   LOC(L_KDEC), xmm0
    ; (f1/f0)^(1/n), skipped if either is 0
    movss   xmm7, [rbx+LYR.f0]
    mulss   xmm7, [rel syn_pitch]
    mov     eax, [rel f_one]
    mov     LOC(L_KF), eax
    movss   xmm0, [rbx+LYR.f0]
    comiss  xmm0, [rel f_zero]
    jbe     .nof
    movss   xmm1, [rbx+LYR.f1]
    comiss  xmm1, [rel f_zero]
    jbe     .nof
    divss   xmm1, xmm0
    movaps  xmm0, xmm1
    call    audio_ln
    cvtsi2ss xmm1, r12d
    divss   xmm0, xmm1
    call    audio_exp
    movss   LOC(L_KF), xmm0
.nof:
    movss   xmm10, [rbx+LYR.c0]
    mov     eax, [rel f_one]
    mov     LOC(L_KC), eax
    movss   xmm0, [rbx+LYR.c0]
    comiss  xmm0, [rel f_zero]
    jbe     .noc
    movss   xmm1, [rbx+LYR.c1]
    comiss  xmm1, [rel f_zero]
    jbe     .noc
    divss   xmm1, xmm0
    movaps  xmm0, xmm1
    call    audio_ln
    cvtsi2ss xmm1, r12d
    divss   xmm0, xmm1
    call    audio_exp
    movss   LOC(L_KC), xmm0
.noc:
    movss   xmm0, [rbx+LYR.q]
    maxss   xmm0, [rel f_minq]
    movss   xmm1, [rel f_one]
    divss   xmm1, xmm0
    movss   LOC(L_DAMP), xmm1
    movss   xmm0, [rbx+LYR.lrate]
    mulss   xmm0, [rel f_inv_fs]
    movss   LOC(L_LFOINC), xmm0
    movss   xmm0, [rbx+LYR.grain]
    movss   xmm1, xmm0
    mulss   xmm1, [rel f_inv_fs]
    movss   LOC(L_DUSTP), xmm1
    maxss   xmm0, [rel f_one]
    movss   xmm1, [rel f_fs]
    divss   xmm1, xmm0
    movss   LOC(L_GPER), xmm1
    mov     dword LOC(L_GCNT), 0
    ; sin01 works in cycles
    movss   xmm0, [rbx+LYR.fmi]
    mulss   xmm0, [rel f_inv_twopi]
    movss   LOC(L_FMI), xmm0
    movss   xmm0, [rbx+LYR.amp]
    movss   LOC(L_AMP), xmm0
    movss   xmm6, [rel f_one]
    xorps   xmm8, xmm8
    xorps   xmm9, xmm9
    xorps   xmm11, xmm11
    xorps   xmm12, xmm12
    xorps   xmm13, xmm13
    xorps   xmm14, xmm14
    movss   xmm15, [rel f_one]
    mov     r14d, [rbx+LYR.kind]
    mov     r15d, [rbx+LYR.filt]
    xor     r13d, r13d

.loop:
    movss   xmm0, [rbx+LYR.lrate]
    comiss  xmm0, [rel f_zero]
    jbe     .nolfo
    addss   xmm13, LOC(L_LFOINC)
    comiss  xmm13, [rel f_one]
    jb      .lw
    subss   xmm13, [rel f_one]
.lw:
    movaps  xmm0, xmm13
    call    audio_sin01
    movaps  xmm14, xmm0
.nolfo:
    cmp     r13d, LOC(L_ATTN)
    jge     .decay
    lea     eax, [r13+1]
    cvtsi2ss xmm0, eax
    cvtsi2ss xmm1, dword LOC(L_ATTN)
    divss   xmm0, xmm1
    jmp     .envd
.decay:
    mulss   xmm6, LOC(L_KDEC)
    movaps  xmm0, xmm6
.envd:
    mov     eax, r12d
    sub     eax, r13d
    cmp     eax, LOC(L_FADEN)
    jge     .nofade
    cvtsi2ss xmm1, eax
    cvtsi2ss xmm2, dword LOC(L_FADEN)
    divss   xmm1, xmm2
    mulss   xmm0, xmm1
.nofade:
    movss   LOC(L_ENV), xmm0

    cmp     r14d, K_NOISE
    je      .src_noise
    cmp     r14d, K_DUST
    je      .src_dust
    movss   xmm1, [rbx+LYR.lpitch]
    mulss   xmm1, xmm14
    addss   xmm1, [rel f_one]
    movss   xmm0, xmm7
    mulss   xmm0, xmm1
    mulss   xmm0, [rel f_inv_fs]
    movss   LOC(L_INC), xmm0
    addss   xmm8, xmm0
    roundss xmm1, xmm8, 1
    subss   xmm8, xmm1
    movss   LOC(L_P), xmm8
    movss   xmm1, LOC(L_FMI)
    comiss  xmm1, [rel f_zero]
    jbe     .nofm
    movss   xmm0, LOC(L_INC)
    mulss   xmm0, [rbx+LYR.fmr]
    addss   xmm9, xmm0
    roundss xmm1, xmm9, 1
    subss   xmm9, xmm1
    movaps  xmm0, xmm9
    call    audio_sin01
    mulss   xmm0, LOC(L_FMI)
    mulss   xmm0, LOC(L_ENV)
    addss   xmm0, LOC(L_P)
    roundss xmm1, xmm0, 1
    subss   xmm0, xmm1
    movss   LOC(L_P), xmm0
.nofm:
    movss   xmm0, LOC(L_P)
    cmp     r14d, K_SINE
    jne     .notsine
    call    audio_sin01
    jmp     .oscdone
.notsine:
    cmp     r14d, K_SAW
    jne     .notsaw
    addss   xmm0, xmm0
    subss   xmm0, [rel f_one]
    jmp     .oscdone
.notsaw:
    cmp     r14d, K_SQUARE
    jne     .tri
    comiss  xmm0, [rel f_half]
    movss   xmm0, [rel f_one]
    jb      .oscdone
    movss   xmm0, [rel f_mone]
    jmp     .oscdone
.tri:                                   ; 4|p - 0.5| - 1
    subss   xmm0, [rel f_half]
    andps   xmm0, [rel f_absmask]
    mulss   xmm0, [rel f_four]
    subss   xmm0, [rel f_one]
.oscdone:
    movss   LOC(L_S), xmm0
    movss   xmm1, [rbx+LYR.nmix]
    comiss  xmm1, [rel f_zero]
    jbe     .nonmix
    call    syn_frand
    mulss   xmm0, [rbx+LYR.nmix]
    addss   xmm0, LOC(L_S)
    movss   LOC(L_S), xmm0
.nonmix:
    mulss   xmm7, LOC(L_KF)
    jmp     .grain

.src_noise:
    call    syn_frand
    movss   LOC(L_S), xmm0
    jmp     .grain

.src_dust:
    call    syn_urand
    comiss  xmm0, LOC(L_DUSTP)
    jae     .dzero
    call    syn_frand
    movss   LOC(L_S), xmm0
    jmp     .filter  ; no grain gate for dust, .grain is the density there
.dzero:
    xorps   xmm0, xmm0
    movss   LOC(L_S), xmm0
    jmp     .filter

.grain:
    movss   xmm0, [rbx+LYR.grain]
    comiss  xmm0, [rel f_zero]
    jbe     .filter
    dec     dword LOC(L_GCNT)
    jg      .gkeep
    call    syn_urand  ; 0.1 + 0.9 r^2
    mulss   xmm0, xmm0
    mulss   xmm0, [rel f_gscale]
    addss   xmm0, [rel f_gmin]
    movaps  xmm15, xmm0
    call    syn_urand  ; next in 0.5..1.5 periods
    addss   xmm0, [rel f_half]
    mulss   xmm0, LOC(L_GPER)
    cvttss2si eax, xmm0
    cmp     eax, 1
    jge     .g1
    mov     eax, 1
.g1:
    mov     LOC(L_GCNT), eax
.gkeep:
    movss   xmm0, LOC(L_S)
    mulss   xmm0, xmm15
    movss   LOC(L_S), xmm0

    ; 2x oversampled, blows up at high cutoffs otherwise
.filter:
    test    r15d, r15d
    jz      .nofilt
    test    r13d, 15  ; sin01 isn't free, coef every 16 samples
    jnz     .keepf
    movss   xmm1, [rbx+LYR.lcut]
    mulss   xmm1, xmm14
    addss   xmm1, [rel f_one]
    movaps  xmm0, xmm10
    mulss   xmm0, [rel syn_cut]
    mulss   xmm0, xmm1
    maxss   xmm0, [rel f_cutmin]
    minss   xmm0, [rel f_cutmax]
    mulss   xmm0, [rel f_inv_4fs]  ; f = 2 sin(pi fc / 2fs)
    call    audio_sin01
    addss   xmm0, xmm0
    minss   xmm0, [rel f_svfmax]
    movss   LOC(L_SVF), xmm0
.keepf:
    mulss   xmm10, LOC(L_KC)
    movss   xmm3, LOC(L_S)
    movss   xmm4, LOC(L_SVF)
    movss   xmm5, LOC(L_DAMP)
    mov     ecx, 2
.svf:
    movaps  xmm0, xmm12
    mulss   xmm0, xmm4
    addss   xmm11, xmm0
    movaps  xmm1, xmm3
    subss   xmm1, xmm11
    movaps  xmm0, xmm12
    mulss   xmm0, xmm5
    subss   xmm1, xmm0
    movaps  xmm0, xmm1
    mulss   xmm0, xmm4
    addss   xmm12, xmm0
    dec     ecx
    jnz     .svf
    cmp     r15d, F_LP
    jne     .nlp
    movss   LOC(L_S), xmm11
    jmp     .nofilt
.nlp:
    cmp     r15d, F_BP
    jne     .nbp
    movaps  xmm0, xmm12  ; band*d = unity gain at center
    mulss   xmm0, xmm5
    movss   LOC(L_S), xmm0
    jmp     .nofilt
.nbp:
    movss   LOC(L_S), xmm1
.nofilt:
    movss   xmm1, [rbx+LYR.drive]
    comiss  xmm1, [rel f_zero]
    jbe     .nodrive
    movss   xmm0, LOC(L_S)
    mulss   xmm0, xmm1
    call    audio_softclip
    movss   LOC(L_S), xmm0
.nodrive:
    movss   xmm0, LOC(L_S)
    mulss   xmm0, LOC(L_ENV)
    mulss   xmm0, LOC(L_AMP)
    movss   xmm1, [rbx+LYR.lamp]
    comiss  xmm1, [rel f_zero]
    jbe     .notrem
    movaps  xmm2, xmm14
    mulss   xmm2, [rel f_half]
    addss   xmm2, [rel f_half]
    mulss   xmm2, xmm1
    movss   xmm1, [rel f_one]
    subss   xmm1, xmm2
    mulss   xmm0, xmm1
.notrem:
    addss   xmm0, [rdi+r13*4]
    movss   [rdi+r13*4], xmm0
    inc     r13d
    cmp     r13d, r12d
    jl      .loop
.done:
ENDPX

PROC audio_patch_frames, 0
    mov     r8d, [rcx+PHDR.n]
    lea     rdx, [rcx+PHDR_size]
    xorps   xmm1, xmm1
.l:
    test    r8d, r8d
    jz      .e
    movss   xmm0, [rdx+LYR.start]
    addss   xmm0, [rdx+LYR.dur]
    maxss   xmm1, xmm0
    add     rdx, LYR_size
    dec     r8d
    jmp     .l
.e:
    mulss   xmm1, [rel f_fs]
    cvttss2si eax, xmm1
    add     eax, 2
ENDP

; all layers + dc block + normalize, eax = frames
PROCX audio_synth_patch, 32
    mov     rbx, rcx
    mov     r12d, edx
    mov     rdi, r8
    mov     r13d, r9d
    call    audio_patch_frames
    cmp     eax, r13d
    cmovg   eax, r13d
    mov     r14d, eax
    xor     ecx, ecx
    xorps   xmm0, xmm0
.z:
    cmp     ecx, r14d
    jge     .zd
    movss   [rdi+rcx*4], xmm0
    inc     ecx
    jmp     .z
.zd:
    cmp     r12d, NVAR
    jb      .v0
    xor     r12d, r12d
.v0:
    lea     rax, [rel var_pitch]
    movss   xmm0, [rax+r12*4]
    mulss   xmm0, [rbx+PHDR.spread]
    addss   xmm0, [rel f_one]
    movss   [rel syn_pitch], xmm0
    lea     rax, [rel var_cut]
    movss   xmm1, [rax+r12*4]
    mulss   xmm1, [rbx+PHDR.spread]
    addss   xmm1, [rel f_one]
    mulss   xmm1, xmm0                  ; filters follow the pitch shift too
    movss   [rel syn_cut], xmm1
    ; seeded from len/layers/variant so renders are reproducible
    mov     eax, r14d
    imul    eax, eax, 0x9E3779B1
    mov     ecx, [rbx+PHDR.n]
    imul    ecx, ecx, 0x85EBCA77
    xor     eax, ecx
    lea     ecx, [r12+1]
    imul    ecx, ecx, 0xC2B2AE3D
    xor     eax, ecx
    or      eax, 1
    mov     [rel syn_rng], eax
    mov     r15d, [rbx+PHDR.n]
    lea     rsi, [rbx+PHDR_size]
.lay:
    test    r15d, r15d
    jz      .post
    mov     rcx, rsi
    mov     rdx, rdi
    mov     r8d, r14d
    call    audio_synth_layer
    add     rsi, LYR_size
    dec     r15d
    jmp     .lay
.post:
    ; dc blocker y = x - x1 + 0.995 y1, tracks the peak too
    xorps   xmm6, xmm6
    xorps   xmm7, xmm7
    xorps   xmm8, xmm8
    movss   xmm9, [rel f_dcpole]
    xor     ecx, ecx
.dc:
    cmp     ecx, r14d
    jge     .dcd
    movss   xmm0, [rdi+rcx*4]
    movaps  xmm1, xmm0
    subss   xmm1, xmm6
    movaps  xmm6, xmm0
    mulss   xmm7, xmm9
    addss   xmm7, xmm1
    movss   [rdi+rcx*4], xmm7
    movaps  xmm2, xmm7
    andps   xmm2, [rel f_absmask]
    maxss   xmm8, xmm2
    inc     ecx
    jmp     .dc
.dcd:
    comiss  xmm8, [rel f_tiny]
    jbe     .ret
    movss   xmm0, [rbx+PHDR.peak]
    divss   xmm0, xmm8
    xor     ecx, ecx
.nm:
    cmp     ecx, r14d
    jge     .ret
    movss   xmm1, [rdi+rcx*4]
    mulss   xmm1, xmm0
    movss   [rdi+rcx*4], xmm1
    inc     ecx
    jmp     .nm
.ret:
    mov     eax, r14d
ENDPX

; one arena for every sound x variant
PROC audio_bank_build, 16
    cmp     dword [rel bank_ready], 0
    jne     .done
    xor     ebx, ebx
    xor     r12, r12
.sz:
    lea     rax, [rel sfx_patches]
    mov     rcx, [rax+rbx*8]
    call    audio_patch_frames
    add     eax, 3
    and     eax, ~3  ; keeps buffers 16-aligned
    imul    eax, eax, NVAR
    add     r12, rax
    inc     ebx
    cmp     ebx, NSFX
    jb      .sz
    shl     r12, 2
    xor     ecx, ecx
    mov     rdx, r12
    add     rdx, 4096
    mov     r8d, MEM_COMMIT | MEM_RESERVE
    mov     r9d, PAGE_READWRITE
    call    VirtualAlloc
    test    rax, rax
    jz      .done
    mov     [rel bank_arena], rax
    mov     rdi, rax
    xor     ebx, ebx
.snd:
    cmp     dword [rel aud_quit], 0  ; shutdown mid-build
    jne     .abort
    lea     rax, [rel sfx_patches]
    mov     r13, [rax+rbx*8]
    mov     rcx, r13
    call    audio_patch_frames
    add     eax, 3
    and     eax, ~3
    mov     r14d, eax
    xor     esi, esi
.var:
    mov     rcx, r13
    mov     edx, esi
    mov     r8, rdi
    mov     r9d, r14d
    call    audio_synth_patch
    imul    ecx, ebx, NVAR
    add     ecx, esi
    lea     rdx, [rel bank_len]
    mov     [rdx+rcx*4], eax
    lea     rdx, [rel bank_ptr]
    mov     [rdx+rcx*8], rdi
    mov     eax, r14d
    lea     rdi, [rdi+rax*4]
    inc     esi
    cmp     esi, NVAR
    jb      .var
    inc     ebx
    cmp     ebx, NSFX
    jb      .snd
    mfence
    mov     dword [rel bank_ready], 1
    jmp     .done
.abort:  ; bank_ready still 0, nobody saw it
    mov     rcx, [rel bank_arena]
    xor     edx, edx
    mov     r8d, MEM_RELEASE
    call    VirtualFree
    mov     qword [rel bank_arena], 0
    lea     rdi, [rel bank_len]
    xor     eax, eax
    mov     ecx, NSFX*NVAR
    rep     stosd
.done:
ENDP

; mixer thread only
PROC audio_start_voice, 16
    cmp     ecx, NSFX
    jae     .done
    mov     ebx, ecx
    lea     rcx, [rel mix_rng]
    call    xs32_step
    xor     edx, edx
    mov     ecx, NVAR
    div     ecx
    imul    eax, ebx, NVAR
    add     eax, edx
    lea     rcx, [rel bank_len]
    mov     r8d, [rcx+rax*4]
    cmp     r8d, 2
    jb      .done
    lea     rcx, [rel bank_ptr]
    mov     r9, [rcx+rax*8]
    ; free voice, else steal the oldest
    lea     r10, [rel voices]
    xor     ecx, ecx
    mov     r11, r10
    mov     esi, 0x7FFFFFFF
.find:
    imul    eax, ecx, VOICE_size
    lea     rdx, [r10+rax]
    cmp     dword [rdx+VOICE.active], 0
    je      .got
    mov     eax, [rdx+VOICE.serial]
    sub     eax, [rel voice_serial]  ; wrap-safe
    cmp     eax, esi
    jge     .nf
    mov     esi, eax
    mov     r11, rdx
.nf:
    inc     ecx
    cmp     ecx, MAX_VOICES
    jb      .find
    mov     rdx, r11
    ; hard-cutting a stolen voice clicks, so its current sample goes into res_l/r and
    ; mix_block fades that out. active voice always has pos < len-1 so data[pos] is fine
    mov     rax, [rdx+VOICE.pos]
    shr     rax, 32
    mov     r10, [rdx+VOICE.data]
    movss   xmm3, [r10+rax*4]
    movaps  xmm4, xmm3
    mulss   xmm3, [rdx+VOICE.gl]
    mulss   xmm4, [rdx+VOICE.gr]
    addss   xmm3, [rel res_l]
    addss   xmm4, [rel res_r]
    movss   [rel res_l], xmm3
    movss   [rel res_r], xmm4
.got:
    maxss   xmm2, [rel f_pmin]
    minss   xmm2, [rel f_pmax]
    mulss   xmm2, [rel f_2p32]
    cvtss2si rax, xmm2
    mov     [rdx+VOICE.step], rax
    mov     qword [rdx+VOICE.pos], 0
    mov     [rdx+VOICE.data], r9
    mov     [rdx+VOICE.len], r8d
    movss   [rdx+VOICE.gl], xmm0
    movss   [rdx+VOICE.gr], xmm1
    mov     eax, [rel voice_serial]
    inc     eax
    mov     [rel voice_serial], eax
    mov     [rdx+VOICE.serial], eax
    mov     dword [rdx+VOICE.active], 1
.done:
ENDP

PROCX audio_mix_block, 16
    mov     rsi, rcx
    ; frames must be 1..MIX_FRAMES. 0 spins the dec/jnz loops ~4G times, more overruns mix_acc
    test    edx, edx
    jle     .done
    cmp     edx, MIX_FRAMES
    jbe     .fok
    mov     edx, MIX_FRAMES
.fok:
    mov     r12d, edx
    ; commands wait until the bank exists
    cmp     dword [rel bank_ready], 0
    je      .nodrain
    lea     rcx, [rel aud_cs]
    call    EnterCriticalSection
.dq:
    mov     eax, [rel q_tail]
    cmp     eax, [rel q_head]
    je      .dqe
    and     eax, QCAP-1
    shl     eax, 4
    lea     rbx, [rel q_buf]
    add     rbx, rax
    inc     dword [rel q_tail]
    mov     ecx, [rbx+QENT.id]
    movss   xmm0, [rbx+QENT.gl]
    movss   xmm1, [rbx+QENT.gr]
    movss   xmm2, [rbx+QENT.pitch]
    call    audio_start_voice
    jmp     .dq
.dqe:
    lea     rcx, [rel aud_cs]
    call    LeaveCriticalSection
.nodrain:
    lea     rdi, [rel mix_acc]
    lea     ecx, [r12+r12]
    xorps   xmm0, xmm0
    xor     eax, eax
.clr:
    movss   [rdi+rax*4], xmm0
    inc     eax
    cmp     eax, ecx
    jb      .clr
    lea     rbx, [rel voices]
    xor     r13d, r13d
.vloop:
    cmp     dword [rbx+VOICE.active], 0
    je      .vnext
    mov     r8, [rbx+VOICE.data]
    mov     r9, [rbx+VOICE.pos]
    mov     r10, [rbx+VOICE.step]
    mov     r11d, [rbx+VOICE.len]
    dec     r11d  ; lerp reads i+1
    movss   xmm4, [rbx+VOICE.gl]
    movss   xmm5, [rbx+VOICE.gr]
    movss   xmm6, [rel f_inv2p32]
    mov     rdx, rdi
    mov     ecx, r12d
.smp:
    mov     rax, r9
    shr     rax, 32
    cmp     eax, r11d
    jae     .vend
    movss   xmm0, [r8+rax*4]
    movss   xmm1, [r8+rax*4+4]
    subss   xmm1, xmm0
    mov     eax, r9d
    cvtsi2ss xmm2, rax
    mulss   xmm2, xmm6
    mulss   xmm1, xmm2
    addss   xmm0, xmm1
    movaps  xmm1, xmm0
    mulss   xmm0, xmm4
    mulss   xmm1, xmm5
    addss   xmm0, [rdx]
    addss   xmm1, [rdx+4]
    movss   [rdx], xmm0
    movss   [rdx+4], xmm1
    add     rdx, 8
    add     r9, r10
    dec     ecx
    jnz     .smp
    mov     [rbx+VOICE.pos], r9
    jmp     .vnext
.vend:
    mov     dword [rbx+VOICE.active], 0
.vnext:
    add     rbx, VOICE_size
    inc     r13d
    cmp     r13d, MAX_VOICES
    jb      .vloop
    ; stolen-voice residual, FTZ snaps it to 0 eventually
    movss   xmm4, [rel res_l]
    movss   xmm5, [rel res_r]
    movss   xmm3, [rel f_resdecay]
    mov     rdx, rdi
    mov     ecx, r12d
.res:
    movss   xmm0, [rdx]
    addss   xmm0, xmm4
    movss   [rdx], xmm0
    movss   xmm1, [rdx+4]
    addss   xmm1, xmm5
    movss   [rdx+4], xmm1
    mulss   xmm4, xmm3
    mulss   xmm5, xmm3
    add     rdx, 8
    dec     ecx
    jnz     .res
    movss   [rel res_l], xmm4
    movss   [rel res_r], xmm5
    mov     rcx, rdi
    mov     edx, r12d
    call    music_render
    ; soft knee limiter
    lea     ecx, [r12+r12]
    xor     ebx, ebx
.cv:
    movss   xmm0, [rdi+rbx*4]
    movaps  xmm3, xmm0
    andps   xmm0, [rel f_absmask]
    comiss  xmm0, [rel f_knee]
    jbe     .lin
    subss   xmm0, [rel f_knee]  ; knee + (1-knee) tanh((|x|-knee)/(1-knee))
    mulss   xmm0, [rel f_inv1mknee]
    call    audio_softclip
    mulss   xmm0, [rel f_1mknee]
    addss   xmm0, [rel f_knee]
.lin:
    andps   xmm3, [rel f_signmask]
    orps    xmm0, xmm3
    mulss   xmm0, [rel f_32767]
    cvtss2si eax, xmm0
    cmp     eax, 32767
    jle     .c1
    mov     eax, 32767
.c1:
    cmp     eax, -32767
    jge     .c2
    mov     eax, -32767
.c2:
    mov     [rsi+rbx*2], ax
    inc     ebx
    cmp     ebx, ecx
    jb      .cv
.done:
ENDPX

; mixer thread: build bank, prime buffers, then refill whatever the device hands back
PROC audio_thread_proc, 16
    stmxcsr LOC(0)
    or      dword LOC(0), 0x8040  ; FTZ+DAZ, decaying filters + reverb tail go denormal and crawl otherwise
    ldmxcsr LOC(0)
    call    GetCurrentThread
    mov     rcx, rax
    mov     edx, THREAD_PRIORITY_HIGHEST
    call    SetThreadPriority
    call    audio_bank_build
    cmp     dword [rel aud_quit], 0  ; shutdown while building
    jne     .exit
    lea     rcx, [rel msg_ready]
    call    log_write
    xor     ebx, ebx
.prime:
    imul    eax, ebx, WAVEHDR_SIZE
    lea     r12, [rel wave_hdrs]
    add     r12, rax
    mov     rcx, [r12]
    mov     edx, MIX_FRAMES
    call    audio_mix_block
    mov     rcx, [rel aud_hwo]
    mov     rdx, r12
    mov     r8d, WAVEHDR_SIZE
    call    waveOutWrite
    inc     ebx
    cmp     ebx, NUM_BUFS
    jb      .prime
.wait:
    mov     rcx, [rel aud_event]
    mov     edx, 100
    call    WaitForSingleObject
    cmp     dword [rel aud_quit], 0
    jne     .exit
    xor     ebx, ebx
.chk:
    imul    eax, ebx, WAVEHDR_SIZE
    lea     r12, [rel wave_hdrs]
    add     r12, rax
    test    dword [r12+WH_FLAGS], WHDR_DONE
    jz      .nx
    mov     rcx, [r12]
    mov     edx, MIX_FRAMES
    call    audio_mix_block
    mov     rcx, [rel aud_hwo]
    mov     rdx, r12
    mov     r8d, WAVEHDR_SIZE
    call    waveOutWrite
.nx:
    inc     ebx
    cmp     ebx, NUM_BUFS
    jb      .chk
    jmp     .wait
.exit:
    xor     eax, eax
ENDP

; crit section + rng seeds, the offline test path uses this too
PROC audio_common_init, 0
    cmp     dword [rel cs_inited], 0
    jne     .done
    lea     rcx, [rel aud_cs]
    call    InitializeCriticalSection
    call    GetTickCount64
    or      eax, 1
    mov     [rel mix_rng], eax
    xor     eax, 0x5BD1E995
    or      eax, 1
    mov     [rel play_rng], eax
    mov     dword [rel cs_inited], 1
.done:
ENDP

; 0 on failure, game just runs silent
PROC audio_init, 16
    cmp     dword [rel aud_ok], 0
    jne     .ok
    call    audio_common_init
    mov     dword [rel aud_quit], 0
    ; auto-reset, driver signals it per finished buffer
    xor     ecx, ecx
    xor     edx, edx
    xor     r8d, r8d
    xor     r9d, r9d
    call    CreateEventA
    test    rax, rax
    jz      .fail
    mov     [rel aud_event], rax
    lea     rax, [rel wfx]
    mov     word [rax+0], WAVE_FORMAT_PCM
    mov     word [rax+2], 2
    mov     dword [rax+4], FS_HZ
    mov     dword [rax+8], FS_HZ*4
    mov     word [rax+12], 4
    mov     word [rax+14], 16
    mov     word [rax+16], 0
    lea     rcx, [rel aud_hwo]
    mov     edx, WAVE_MAPPER
    lea     r8, [rel wfx]
    mov     r9, [rel aud_event]
    mov     qword [rsp+32], 0
    mov     dword [rsp+40], CALLBACK_EVENT
    call    waveOutOpen
    test    eax, eax
    jnz     .fail_ev
    xor     ebx, ebx
.hdr:
    imul    eax, ebx, WAVEHDR_SIZE
    lea     rdx, [rel wave_hdrs]
    add     rdx, rax
    mov     ecx, ebx
    imul    ecx, ecx, MIX_FRAMES*4
    lea     rax, [rel pcm_bufs]
    add     rax, rcx
    mov     [rdx+0], rax                ; lpData
    mov     dword [rdx+8], MIX_FRAMES*4 ; dwBufferLength
    mov     dword [rdx+12], 0
    mov     qword [rdx+16], 0
    mov     dword [rdx+WH_FLAGS], 0
    mov     dword [rdx+28], 0
    mov     qword [rdx+32], 0
    mov     qword [rdx+40], 0
    mov     rcx, [rel aud_hwo]
    mov     r8d, WAVEHDR_SIZE
    call    waveOutPrepareHeader
    inc     ebx
    cmp     ebx, NUM_BUFS
    jb      .hdr
    mov     dword [rel aud_accept], 1
    xor     ecx, ecx
    xor     edx, edx
    lea     r8, [rel audio_thread_proc]
    xor     r9d, r9d
    mov     qword [rsp+32], 0
    mov     qword [rsp+40], 0
    call    CreateThread
    test    rax, rax
    jz      .fail_dev
    mov     [rel aud_thread], rax
    mov     dword [rel aud_ok], 1
.ok:
    mov     eax, 1
    jmp     .done
.fail_dev:
    mov     dword [rel aud_accept], 0
    xor     ebx, ebx
.uh:
    imul    eax, ebx, WAVEHDR_SIZE
    lea     rdx, [rel wave_hdrs]
    add     rdx, rax
    mov     rcx, [rel aud_hwo]
    mov     r8d, WAVEHDR_SIZE
    call    waveOutUnprepareHeader
    inc     ebx
    cmp     ebx, NUM_BUFS
    jb      .uh
    mov     rcx, [rel aud_hwo]
    call    waveOutClose
.fail_ev:
    mov     rcx, [rel aud_event]
    call    CloseHandle
.fail:
    lea     rcx, [rel msg_open_fail]
    call    log_write
    xor     eax, eax
.done:
ENDP

PROC audio_shutdown, 16
    cmp     dword [rel aud_ok], 0
    je      .done
    mov     dword [rel aud_accept], 0
    mov     dword [rel aud_quit], 1
    ; drop anything queued or it plays after the next init
    lea     rcx, [rel aud_cs]
    call    EnterCriticalSection
    mov     eax, [rel q_head]
    mov     [rel q_tail], eax
    lea     rcx, [rel aud_cs]
    call    LeaveCriticalSection
    mov     rcx, [rel aud_event]
    call    SetEvent
    mov     rcx, [rel aud_thread]
    mov     edx, 5000
    call    WaitForSingleObject
    mov     r12d, eax  ; WAIT_OBJECT_0 = thread exited
    mov     rcx, [rel aud_hwo]
    call    waveOutReset
    xor     ebx, ebx
.uh:
    imul    eax, ebx, WAVEHDR_SIZE
    lea     rdx, [rel wave_hdrs]
    add     rdx, rax
    mov     rcx, [rel aud_hwo]
    mov     r8d, WAVEHDR_SIZE
    call    waveOutUnprepareHeader
    inc     ebx
    cmp     ebx, NUM_BUFS
    jb      .uh
    mov     rcx, [rel aud_hwo]
    call    waveOutClose
    mov     rcx, [rel aud_thread]
    call    CloseHandle
    mov     rcx, [rel aud_event]
    call    CloseHandle
    mov     dword [rel aud_ok], 0
    test    r12d, r12d
    jnz     .done  ; thread may still be reading the bank. leak it, ugly but beats crashing
    mov     rcx, [rel bank_arena]
    test    rcx, rcx
    jz      .nob
    xor     edx, edx
    mov     r8d, MEM_RELEASE
    call    VirtualFree
    mov     qword [rel bank_arena], 0
.nob:
    mov     dword [rel bank_ready], 0
    lea     rdi, [rel bank_len]
    xor     eax, eax
    mov     ecx, NSFX*NVAR
    rep     stosd
    lea     rdi, [rel voices]
    mov     ecx, VOICE_size*MAX_VOICES/4
    rep     stosd
    mov     [rel res_l], eax
    mov     [rel res_r], eax
.done:
ENDP

; any thread
PROC audio_enqueue, 16
    cmp     dword [rel aud_accept], 0
    je      .done
    mov     ebx, ecx
    movss   LOC(0), xmm0
    movss   LOC(4), xmm1
    movss   LOC(8), xmm2
    lea     rcx, [rel aud_cs]
    call    EnterCriticalSection
    mov     eax, [rel q_head]
    mov     edx, eax
    sub     edx, [rel q_tail]
    cmp     edx, QCAP
    jae     .full  ; full: drop it
    and     eax, QCAP-1
    shl     eax, 4
    lea     rcx, [rel q_buf]
    add     rcx, rax
    mov     [rcx+QENT.id], ebx
    mov     eax, LOC(0)
    mov     [rcx+QENT.gl], eax
    mov     eax, LOC(4)
    mov     [rcx+QENT.gr], eax
    mov     eax, LOC(8)
    mov     [rcx+QENT.pitch], eax
    inc     dword [rel q_head]
.full:
    lea     rcx, [rel aud_cs]
    call    LeaveCriticalSection
.done:
ENDP

PROC sfx_play, 0
    cmp     dword [rel aud_accept], 0
    je      .done
    cmp     ecx, NSFX
    jae     .done
    maxss   xmm1, [rel f_zero]
    lea     rax, [rel g_settings]
    mulss   xmm1, [rax+SETTINGS.sfx_vol]
    comiss  xmm1, [rel f_tiny]  ; muted, don't steal a voice for nothing
    jbe     .done
    movaps  xmm0, xmm1
    call    audio_enqueue
.done:
ENDP

; (ecx id, xmm1..3 xyz, xmm4 vol, xmm5 pitch)
PROCX audio_play_at_ex, 32
    cmp     dword [rel aud_accept], 0
    je      .done
    cmp     ecx, NSFX
    jae     .done
    mov     ebx, ecx
    movss   LOC(0), xmm4
    movss   LOC(4), xmm5
    lea     rax, [rel g_player]
    movaps  xmm6, xmm1
    subss   xmm6, [rax+PLAYER.x]
    movss   xmm0, [rax+PLAYER.eye_height]
    comiss  xmm0, [rel f_half]
    ja      .eye
    movss   xmm0, [rel f_eye]
.eye:
    addss   xmm0, [rax+PLAYER.y]
    movaps  xmm7, xmm2
    subss   xmm7, xmm0
    movaps  xmm8, xmm3
    subss   xmm8, [rax+PLAYER.z]
    movaps  xmm0, xmm6
    mulss   xmm0, xmm6
    movaps  xmm1, xmm7
    mulss   xmm1, xmm7
    addss   xmm0, xmm1
    movaps  xmm1, xmm8
    mulss   xmm1, xmm8
    addss   xmm0, xmm1
    sqrtss  xmm9, xmm0
    movaps  xmm10, xmm9
    mulss   xmm10, [rel f_inv16]
    movss   xmm0, [rel f_one]
    subss   xmm0, xmm10
    comiss  xmm0, [rel f_zero]
    jbe     .done
    mulss   xmm0, LOC(0)
    lea     rax, [rel g_settings]
    mulss   xmm0, [rax+SETTINGS.sfx_vol]
    comiss  xmm0, [rel f_tiny]
    jbe     .done
    movaps  xmm10, xmm0
    ; right = (cos yaw, 0, sin yaw)
    lea     rax, [rel g_player]
    movss   xmm0, [rax+PLAYER.yaw]
    mulss   xmm0, [rel f_inv360]
    movss   LOC(8), xmm0
    call    audio_sin01
    movaps  xmm11, xmm0
    movss   xmm0, LOC(8)
    addss   xmm0, [rel f_quarter]
    call    audio_sin01
    mulss   xmm0, xmm6
    mulss   xmm11, xmm8
    addss   xmm0, xmm11
    maxss   xmm9, [rel f_one]
    divss   xmm0, xmm9  ; dist clamped >= 1 so stuff at your head stays centered
    maxss   xmm0, [rel f_mone]
    minss   xmm0, [rel f_one]
    ; gl = g(1 - 0.6 max(pan,0)), gr mirrored
    xorps   xmm2, xmm2
    movaps  xmm1, xmm0
    maxss   xmm1, xmm2
    mulss   xmm1, [rel f_panamt]
    movss   xmm3, [rel f_one]
    subss   xmm3, xmm1
    mulss   xmm3, xmm10
    xorps   xmm1, xmm1
    subss   xmm1, xmm0
    maxss   xmm1, xmm2
    mulss   xmm1, [rel f_panamt]
    movss   xmm4, [rel f_one]
    subss   xmm4, xmm1
    mulss   xmm4, xmm10
    movss   LOC(8), xmm3
    movss   LOC(12), xmm4
    lea     rcx, [rel play_rng]
    call    xs32_step
    shr     eax, 9
    or      eax, 0x40000000
    movd    xmm0, eax
    subss   xmm0, [rel f_three]
    mulss   xmm0, [rel f_jitter]
    addss   xmm0, [rel f_one]
    mulss   xmm0, LOC(4)
    movaps  xmm2, xmm0
    movss   xmm0, LOC(8)
    movss   xmm1, LOC(12)
    mov     ecx, ebx
    call    audio_enqueue
.done:
ENDPX

PROC sfx_play_at, 0
    movss   xmm4, [rel f_one]
    movss   xmm5, [rel f_one]
    call    audio_play_at_ex
ENDP

; edx kind: 0 break 1 place 2 step 3 hit
PROC sfx_play_block, 32
    movzx   ecx, cl
    lea     rax, [rel blk_sound]
    movzx   r12d, byte [rax+rcx]
    cmp     r12d, SND_WOOL
    jbe     .m
    xor     r12d, r12d
.m:
    mov     r13d, edx
    cmp     r13d, 3
    jbe     .k
    xor     r13d, r13d
.k:
    cvtsi2ss xmm0, r8d
    addss   xmm0, [rel f_half]
    movss   LOC(0), xmm0
    cvtsi2ss xmm0, r9d
    addss   xmm0, [rel f_half]
    movss   LOC(4), xmm0
    mov     eax, ARG5
    cvtsi2ss xmm0, eax
    addss   xmm0, [rel f_half]
    movss   LOC(8), xmm0
    cmp     r13d, 0
    jne     .np
    lea     rax, [rel mat_dig]
    movzx   ecx, byte [rax+r12]
    jmp     .play
.np:
    cmp     r13d, 1
    jne     .ns
    lea     rax, [rel mat_place]
    movzx   ecx, byte [rax+r12]
    jmp     .play
.ns:
    lea     ecx, [r12+SFX_STEP_BASE]  ; step/hit use the short footstep takes
.play:
    lea     rax, [rel kind_vol]
    movss   xmm4, [rax+r13*4]
    lea     rax, [rel kind_pitch]
    movss   xmm5, [rax+r13*4]
    movss   xmm1, LOC(0)
    movss   xmm2, LOC(4)
    movss   xmm3, LOC(8)
    call    audio_play_at_ex
    cmp     r13d, 1  ; place gets the thud on top
    jne     .done
    mov     ecx, SFX_PLACE
    movss   xmm1, LOC(0)
    movss   xmm2, LOC(4)
    movss   xmm3, LOC(8)
    movss   xmm4, [rel f_placevol]
    movss   xmm5, [rel f_one]
    call    audio_play_at_ex
.done:
ENDP

; test hooks, tests/audio calls these directly

PROC audio_dbg_sfx_count, 0
    mov     eax, NSFX
ENDP

PROC audio_dbg_render_sfx, 16
    mov     ecx, ecx  ; int arg, zero-extend
    xor     eax, eax
    cmp     ecx, NSFX
    jae     .done
    lea     rax, [rel sfx_patches]
    mov     rcx, [rax+rcx*8]
    call    audio_synth_patch
.done:
ENDP

; bank + queue without a device, so audio_dbg_mix drives the real mixer
PROC audio_dbg_offline_begin, 16
    call    audio_common_init
    mov     dword [rel aud_quit], 0
    call    audio_bank_build
    mov     dword [rel aud_accept], 1
    mov     eax, 1
ENDP

PROC audio_dbg_mix, 16
    stmxcsr LOC(0)
    mov     eax, LOC(0)
    mov     LOC(4), eax
    or      dword LOC(0), 0x8040
    ldmxcsr LOC(0)
    mov     rsi, rcx
    mov     r12d, edx
    xor     ebx, ebx
.l:
    mov     edx, r12d
    sub     edx, ebx
    jle     .e
    cmp     edx, MIX_FRAMES
    jbe     .c
    mov     edx, MIX_FRAMES
.c:
    mov     r13d, edx
    lea     rcx, [rsi+rbx*4]
    call    audio_mix_block
    add     ebx, r13d
    jmp     .l
.e:
    ldmxcsr LOC(4)
    mov     eax, r12d
ENDP

PROC audio_dbg_active_voices, 0
    lea     rdx, [rel voices]
    xor     eax, eax
    xor     ecx, ecx
.l:
    add     eax, [rdx+VOICE.active]
    add     rdx, VOICE_size
    inc     ecx
    cmp     ecx, MAX_VOICES
    jb      .l
ENDP

; patch table. LAYER args are in the column header below
; write every float with a '.', nasm happily emits `dd 1` as an int otherwise
%macro PATCH 3                          ; layers, peak, spread
    dd %1
    dd %2, %3, 0
%endmacro
%macro LAYER 21
    dd %1, %2
    dd %3, %4, %5, %6, %7
    dd %8, %9, %10, %11
    dd %12, %13, %14
    dd %15, %16, %17, %18
    dd %19, %20, %21
    dd 0, 0, 0
%endmacro

section .rdata
align 16
sfx_patches:
    dq p_dig_stone, p_dig_dirt, p_dig_grass, p_dig_wood, p_dig_sand
    dq p_dig_gravel, p_glass, p_dig_snow, p_dig_wool, p_place
    dq p_step, p_explode, p_hurt, p_pop, p_click
    dq p_splash, p_swim, p_boar, p_woolly, p_shambler
    dq p_fuse, p_eat, p_fizz, p_death, p_levelup
    dq p_chest, p_thunder
    ; footsteps, SFX_STEP_BASE + SND_*
    dq p_st_stone, p_st_dirt, p_st_grass, p_st_wood, p_st_sand
    dq p_st_gravel, p_st_glass, p_st_snow, p_st_wool

;                 kind     filt  start dur   att    dec   amp   f0     f1     fmr  fmi   c0     c1     q     lrate lpit  lamp lcut grain  drive nmix
; stone: crunch + crackle + a bit of low end
p_dig_stone: PATCH 3, 0.9, 0.08
    LAYER K_NOISE, F_BP, 0.0, 0.22, 0.002, 0.05, 1.0, 0.0, 0.0, 0.0, 0.0, 3200.0, 1500.0, 1.2, 0.0, 0.0, 0.0, 0.0, 320.0, 0.0, 0.0
    LAYER K_DUST,  F_BP, 0.0, 0.18, 0.001, 0.06, 0.6, 0.0, 0.0, 0.0, 0.0, 3500.0, 3000.0, 0.9, 0.0, 0.0, 0.0, 0.0, 900.0, 0.0, 0.0
    LAYER K_NOISE, F_LP, 0.0, 0.12, 0.001, 0.03, 0.6, 0.0, 0.0, 0.0, 0.0, 600.0, 400.0, 0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
; dirt: dull thud
p_dig_dirt: PATCH 2, 0.9, 0.1
    LAYER K_NOISE, F_LP, 0.0, 0.25, 0.003, 0.06, 1.0, 0.0, 0.0, 0.0, 0.0, 900.0, 380.0, 0.9, 0.0, 0.0, 0.0, 0.0, 120.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.0, 0.15, 0.001, 0.04, 0.6, 110.0, 55.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
p_dig_grass: PATCH 2, 0.85, 0.1
    LAYER K_NOISE, F_BP, 0.0, 0.30, 0.01, 0.08, 1.0, 0.0, 0.0, 0.0, 0.0, 2100.0, 1300.0, 1.0, 0.0, 0.0, 0.0, 0.0, 60.0, 0.0, 0.0
    LAYER K_NOISE, F_BP, 0.0, 0.20, 0.005, 0.05, 0.15, 0.0, 0.0, 0.0, 0.0, 4000.0, 3500.0, 0.8, 0.0, 0.0, 0.0, 0.0, 200.0, 0.0, 0.0
; wood: resonant BP knock + body tone + splinters
p_dig_wood: PATCH 4, 0.9, 0.07
    LAYER K_NOISE, F_BP, 0.0, 0.30, 0.001, 0.07, 1.0, 0.0, 0.0, 0.0, 0.0, 420.0, 400.0, 12.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.0, 0.20, 0.001, 0.05, 0.5, 212.0, 200.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_NOISE, F_BP, 0.0, 0.10, 0.001, 0.03, 0.5, 0.0, 0.0, 0.0, 0.0, 1200.0, 1100.0, 6.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_DUST,  F_HP, 0.0, 0.10, 0.001, 0.03, 0.3, 0.0, 0.0, 0.0, 0.0, 2000.0, 2000.0, 0.8, 0.0, 0.0, 0.0, 0.0, 400.0, 0.0, 0.0
p_dig_sand: PATCH 2, 0.8, 0.1
    LAYER K_NOISE, F_BP, 0.0, 0.30, 0.01, 0.10, 1.0, 0.0, 0.0, 0.0, 0.0, 3800.0, 2600.0, 0.75, 0.0, 0.0, 0.0, 0.0, 250.0, 0.0, 0.0
    LAYER K_NOISE, F_BP, 0.0, 0.20, 0.005, 0.06, 0.4, 0.0, 0.0, 0.0, 0.0, 1500.0, 1000.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
p_dig_gravel: PATCH 3, 0.9, 0.08
    LAYER K_DUST,  F_BP, 0.0, 0.30, 0.002, 0.09, 1.0, 0.0, 0.0, 0.0, 0.0, 1800.0, 1400.0, 1.5, 0.0, 0.0, 0.0, 0.0, 1400.0, 0.0, 0.0
    LAYER K_NOISE, F_BP, 0.0, 0.25, 0.002, 0.07, 0.7, 0.0, 0.0, 0.0, 0.0, 900.0, 700.0, 1.0, 0.0, 0.0, 0.0, 0.0, 500.0, 0.0, 0.0
    LAYER K_NOISE, F_LP, 0.0, 0.15, 0.002, 0.05, 0.4, 0.0, 0.0, 0.0, 0.0, 400.0, 300.0, 0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
; glass: shatter + inharmonic ringing partials
p_glass: PATCH 6, 0.9, 0.06
    LAYER K_NOISE, F_HP, 0.0, 0.50, 0.001, 0.08, 1.0, 0.0, 0.0, 0.0, 0.0, 3000.0, 3000.0, 0.8, 0.0, 0.0, 0.0, 0.0, 700.0, 0.0, 0.0
    LAYER K_DUST,  F_HP, 0.0, 0.60, 0.001, 0.15, 0.8, 0.0, 0.0, 0.0, 0.0, 4000.0, 4000.0, 0.8, 0.0, 0.0, 0.0, 0.0, 2500.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.0, 0.80, 0.001, 0.25, 0.3, 2350.0, 2350.0, 1.41, 0.6, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.01, 0.70, 0.001, 0.20, 0.25, 3720.0, 3720.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.03, 0.60, 0.001, 0.15, 0.2, 5180.0, 5180.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.05, 0.50, 0.001, 0.10, 0.15, 6900.0, 6900.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
p_dig_snow: PATCH 2, 0.8, 0.1
    LAYER K_NOISE, F_BP, 0.0, 0.28, 0.008, 0.08, 1.0, 0.0, 0.0, 0.0, 0.0, 2200.0, 1400.0, 0.8, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0
    LAYER K_NOISE, F_LP, 0.0, 0.20, 0.005, 0.05, 0.4, 0.0, 0.0, 0.0, 0.0, 700.0, 500.0, 0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
p_dig_wool: PATCH 2, 0.75, 0.1
    LAYER K_NOISE, F_LP, 0.0, 0.25, 0.012, 0.07, 1.0, 0.0, 0.0, 0.0, 0.0, 700.0, 350.0, 0.75, 0.0, 0.0, 0.0, 0.0, 40.0, 0.0, 0.0
    LAYER K_NOISE, F_BP, 0.0, 0.20, 0.008, 0.05, 0.5, 0.0, 0.0, 0.0, 0.0, 300.0, 260.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
; place: saturated thud + click
p_place: PATCH 3, 0.95, 0.06
    LAYER K_SINE,  F_NONE, 0.0, 0.20, 0.001, 0.06, 1.0, 140.0, 55.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 0.0
    LAYER K_NOISE, F_LP, 0.0, 0.12, 0.001, 0.03, 0.6, 0.0, 0.0, 0.0, 0.0, 1800.0, 500.0, 0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_NOISE, F_BP, 0.0, 0.03, 0.0005, 0.01, 0.3, 0.0, 0.0, 0.0, 0.0, 3000.0, 3000.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
p_step: PATCH 2, 0.8, 0.1
    LAYER K_NOISE, F_LP, 0.0, 0.12, 0.002, 0.035, 1.0, 0.0, 0.0, 0.0, 0.0, 1200.0, 800.0, 0.8, 0.0, 0.0, 0.0, 0.0, 150.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.0, 0.10, 0.001, 0.03, 0.4, 90.0, 60.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
; explosion: rumble, sub boom, crack, debris
p_explode: PATCH 4, 0.95, 0.1
    LAYER K_NOISE, F_LP, 0.0, 3.0, 0.002, 0.9, 1.0, 0.0, 0.0, 0.0, 0.0, 1800.0, 120.0, 0.9, 0.0, 0.0, 0.0, 0.0, 30.0, 1.5, 0.0
    LAYER K_SINE,  F_NONE, 0.0, 2.5, 0.001, 0.6, 1.2, 70.0, 28.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 0.0
    LAYER K_NOISE, F_HP, 0.0, 0.6, 0.001, 0.12, 0.5, 0.0, 0.0, 0.0, 0.0, 2000.0, 2000.0, 0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_DUST,  F_LP, 0.1, 2.8, 0.01, 1.2, 0.5, 0.0, 0.0, 0.0, 0.0, 3000.0, 800.0, 0.8, 0.0, 0.0, 0.0, 0.0, 120.0, 0.0, 0.0
; hurt: the "oof". buzzy falling saw through two vowel formants
p_hurt: PATCH 2, 0.9, 0.06
    LAYER K_SAW,   F_BP, 0.0, 0.25, 0.004, 0.09, 1.0, 230.0, 150.0, 0.0, 0.0, 700.0, 500.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.15
    LAYER K_SAW,   F_BP, 0.0, 0.25, 0.004, 0.09, 0.5, 230.0, 150.0, 0.0, 0.0, 1150.0, 900.0, 4.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.15
; pop: rising blip, item pickup
p_pop: PATCH 2, 0.8, 0.08
    LAYER K_SINE,  F_NONE, 0.0, 0.12, 0.002, 0.05, 1.0, 500.0, 1400.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.0, 0.10, 0.002, 0.03, 0.25, 1000.0, 2800.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
p_click: PATCH 3, 0.7, 0.0
    LAYER K_SINE,  F_NONE, 0.0, 0.04, 0.0005, 0.008, 1.0, 2200.0, 1800.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_NOISE, F_BP, 0.0, 0.02, 0.0003, 0.004, 0.5, 0.0, 0.0, 0.0, 0.0, 4000.0, 4000.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.0, 0.04, 0.0005, 0.012, 0.4, 1100.0, 1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
; splash: impact + wash + droplets
p_splash: PATCH 5, 0.85, 0.08
    LAYER K_NOISE, F_BP, 0.0, 0.9, 0.005, 0.25, 1.0, 0.0, 0.0, 0.0, 0.0, 1500.0, 700.0, 0.8, 0.0, 0.0, 0.0, 0.0, 90.0, 0.0, 0.0
    LAYER K_DUST,  F_HP, 0.0, 0.9, 0.01, 0.30, 0.6, 0.0, 0.0, 0.0, 0.0, 2500.0, 2500.0, 0.8, 0.0, 0.0, 0.0, 0.0, 600.0, 0.0, 0.0
    LAYER K_NOISE, F_LP, 0.0, 0.3, 0.002, 0.10, 0.6, 0.0, 0.0, 0.0, 0.0, 500.0, 300.0, 0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.25, 0.10, 0.002, 0.04, 0.25, 900.0, 1600.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.42, 0.10, 0.002, 0.035, 0.2, 1300.0, 2100.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
p_swim: PATCH 2, 0.6, 0.1
    LAYER K_NOISE, F_BP, 0.0, 0.6, 0.08, 0.25, 1.0, 0.0, 0.0, 0.0, 0.0, 900.0, 600.0, 1.2, 6.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0
    LAYER K_NOISE, F_LP, 0.0, 0.5, 0.05, 0.20, 0.5, 0.0, 0.0, 0.0, 0.0, 400.0, 300.0, 0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
; boar: breathy pulse through formants, tremolo = snort
p_boar: PATCH 3, 0.85, 0.1
    LAYER K_SAW,   F_BP, 0.0, 0.5, 0.02, 0.2, 1.0, 85.0, 70.0, 0.0, 0.0, 420.0, 380.0, 3.0, 25.0, 0.0, 0.6, 0.0, 60.0, 0.0, 0.6
    LAYER K_SAW,   F_BP, 0.0, 0.5, 0.02, 0.2, 0.5, 85.0, 70.0, 0.0, 0.0, 900.0, 800.0, 4.0, 25.0, 0.0, 0.6, 0.0, 60.0, 0.0, 0.6
    LAYER K_NOISE, F_LP, 0.0, 0.4, 0.02, 0.15, 0.3, 0.0, 0.0, 0.0, 0.0, 300.0, 250.0, 0.8, 0.0, 0.0, 0.0, 0.0, 40.0, 0.0, 0.0
; woolly: bleat w/ vibrato, 3 formants
p_woolly: PATCH 3, 0.85, 0.08
    LAYER K_SAW,   F_BP, 0.0, 0.75, 0.03, 0.5, 1.0, 330.0, 300.0, 0.0, 0.0, 750.0, 750.0, 4.0, 7.0, 0.035, 0.4, 0.0, 0.0, 0.0, 0.08
    LAYER K_SAW,   F_BP, 0.0, 0.75, 0.03, 0.5, 0.55, 330.0, 300.0, 0.0, 0.0, 1900.0, 1900.0, 5.0, 7.0, 0.035, 0.4, 0.0, 0.0, 0.0, 0.08
    LAYER K_SAW,   F_BP, 0.0, 0.75, 0.03, 0.5, 0.25, 330.0, 300.0, 0.0, 0.0, 2900.0, 2900.0, 6.0, 7.0, 0.035, 0.4, 0.0, 0.0, 0.0, 0.08
; shambler: detuned saws, wobbly filter
p_shambler: PATCH 4, 0.85, 0.08
    LAYER K_SAW,   F_LP, 0.0, 1.3, 0.15, 0.8, 1.0, 72.0, 64.0, 0.0, 0.0, 600.0, 450.0, 2.0, 3.5, 0.0, 0.3, 0.5, 0.0, 0.0, 0.15
    LAYER K_SAW,   F_LP, 0.0, 1.3, 0.15, 0.8, 1.0, 73.1, 65.0, 0.0, 0.0, 600.0, 450.0, 2.0, 3.5, 0.0, 0.3, 0.5, 0.0, 0.0, 0.0
    LAYER K_SAW,   F_LP, 0.0, 1.3, 0.15, 0.8, 0.5, 108.5, 96.0, 0.0, 0.0, 600.0, 450.0, 2.0, 3.5, 0.0, 0.3, 0.5, 0.0, 0.0, 0.0
    LAYER K_NOISE, F_BP, 0.0, 1.2, 0.1, 0.6, 0.3, 0.0, 0.0, 0.0, 0.0, 350.0, 300.0, 2.0, 3.5, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0
p_fuse: PATCH 2, 0.6, 0.05
    LAYER K_NOISE, F_BP, 0.0, 1.5, 0.05, 10.0, 1.0, 0.0, 0.0, 0.0, 0.0, 4500.0, 5000.0, 0.75, 13.0, 0.0, 0.3, 0.0, 400.0, 0.0, 0.0
    LAYER K_DUST,  F_HP, 0.0, 1.5, 0.05, 10.0, 0.5, 0.0, 0.0, 0.0, 0.0, 3000.0, 3000.0, 0.8, 0.0, 0.0, 0.0, 0.0, 300.0, 0.0, 0.0
p_eat: PATCH 4, 0.8, 0.1
    LAYER K_NOISE, F_BP, 0.0, 0.12, 0.005, 0.05, 1.0, 0.0, 0.0, 0.0, 0.0, 1800.0, 1500.0, 1.2, 0.0, 0.0, 0.0, 0.0, 450.0, 0.0, 0.0
    LAYER K_NOISE, F_BP, 0.17, 0.12, 0.005, 0.05, 0.9, 0.0, 0.0, 0.0, 0.0, 1500.0, 1300.0, 1.2, 0.0, 0.0, 0.0, 0.0, 450.0, 0.0, 0.0
    LAYER K_NOISE, F_BP, 0.33, 0.12, 0.005, 0.05, 0.95, 0.0, 0.0, 0.0, 0.0, 2100.0, 1700.0, 1.2, 0.0, 0.0, 0.0, 0.0, 450.0, 0.0, 0.0
    LAYER K_DUST,  F_BP, 0.0, 0.45, 0.005, 0.12, 0.5, 0.0, 0.0, 0.0, 0.0, 2500.0, 2500.0, 1.0, 6.0, 0.0, 0.9, 0.0, 700.0, 0.0, 0.0
p_fizz: PATCH 2, 0.7, 0.1
    LAYER K_NOISE, F_BP, 0.0, 0.9, 0.01, 0.35, 1.0, 0.0, 0.0, 0.0, 0.0, 2500.0, 4500.0, 0.75, 0.0, 0.0, 0.0, 0.0, 200.0, 0.0, 0.0
    LAYER K_DUST,  F_BP, 0.0, 0.9, 0.01, 0.40, 0.6, 0.0, 0.0, 0.0, 0.0, 3000.0, 3000.0, 1.0, 0.0, 0.0, 0.0, 0.0, 900.0, 0.0, 0.0
; death: long falling wail
p_death: PATCH 3, 0.9, 0.05
    LAYER K_SAW,   F_BP, 0.0, 0.8, 0.005, 0.4, 1.0, 260.0, 90.0, 0.0, 0.0, 800.0, 400.0, 3.0, 9.0, 0.03, 0.0, 0.0, 0.0, 0.0, 0.1
    LAYER K_SAW,   F_BP, 0.0, 0.8, 0.005, 0.4, 0.5, 260.0, 90.0, 0.0, 0.0, 1400.0, 700.0, 4.0, 9.0, 0.03, 0.0, 0.0, 0.0, 0.0, 0.1
    LAYER K_SINE,  F_NONE, 0.0, 0.6, 0.005, 0.3, 0.4, 130.0, 60.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
; level up: FM bell arpeggio C6 E6 G6 C7
p_levelup: PATCH 5, 0.8, 0.02
    LAYER K_SINE,  F_NONE, 0.0, 0.5, 0.002, 0.18, 0.6, 1046.5, 1046.5, 2.0, 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.08, 0.5, 0.002, 0.18, 0.6, 1318.5, 1318.5, 2.0, 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.16, 0.5, 0.002, 0.18, 0.6, 1568.0, 1568.0, 2.0, 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.24, 1.0, 0.002, 0.5, 0.6, 2093.0, 2093.0, 2.0, 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    LAYER K_SINE,  F_NONE, 0.24, 1.0, 0.002, 0.3, 0.15, 3136.0, 3136.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
; chest: stick-slip hinge creak + latch
p_chest: PATCH 3, 0.85, 0.06
    LAYER K_SAW,   F_BP, 0.0, 0.55, 0.03, 1.0, 1.0, 40.0, 75.0, 0.0, 0.0, 1100.0, 1100.0, 8.0, 0.0, 0.0, 0.0, 0.0, 45.0, 0.0, 0.05
    LAYER K_SAW,   F_BP, 0.0, 0.55, 0.03, 1.0, 0.4, 40.0, 75.0, 0.0, 0.0, 2300.0, 2300.0, 8.0, 0.0, 0.0, 0.0, 0.0, 45.0, 0.0, 0.0
    LAYER K_NOISE, F_LP, 0.0, 0.10, 0.001, 0.03, 0.4, 0.0, 0.0, 0.0, 0.0, 250.0, 250.0, 0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
; thunder: crack then a really long rumble
p_thunder: PATCH 4, 0.95, 0.12
    LAYER K_NOISE, F_LP, 0.0, 5.0, 0.01, 1.6, 1.0, 0.0, 0.0, 0.0, 0.0, 900.0, 80.0, 0.75, 0.0, 0.0, 0.0, 0.0, 12.0, 0.0, 0.0
    LAYER K_NOISE, F_LP, 0.0, 5.0, 0.3, 2.0, 1.0, 0.0, 0.0, 0.0, 0.0, 250.0, 60.0, 0.8, 1.3, 0.0, 0.6, 0.0, 4.0, 1.5, 0.0
    LAYER K_NOISE, F_BP, 0.0, 0.5, 0.001, 0.15, 0.3, 0.0, 0.0, 0.0, 0.0, 2000.0, 1200.0, 0.75, 0.0, 0.0, 0.0, 0.0, 60.0, 0.0, 0.0
    LAYER K_DUST,  F_LP, 0.0, 3.0, 0.01, 1.0, 0.4, 0.0, 0.0, 0.0, 0.0, 1200.0, 400.0, 0.8, 0.0, 0.0, 0.0, 0.0, 50.0, 0.0, 0.0

