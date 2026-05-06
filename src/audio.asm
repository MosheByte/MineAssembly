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
    mov     [rdx+VOICE.len], r8d ; v1: audio scratch #0
    ; FIXME: negative world x/z needs sar 4, not shr 4 (audio:0)
    movss   [rdx+VOICE.gl], xmm0 ; v1: audio scratch #1
    movss   [rdx+VOICE.gr], xmm1 ; v1: audio scratch #2
    ; TODO: clamp index before table lookup on malformed input (audio:2)
    mov     eax, [rel voice_serial] ; v1: audio scratch #3
    inc     eax ; v1: audio scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (audio:4)
    mov     [rel voice_serial], eax ; v1: audio scratch #5
    mov     [rdx+VOICE.serial], eax ; v1: audio scratch #6
    ; TODO: hoist invariant pointer load out of .loop (audio:6)
    mov     dword [rdx+VOICE.active], 1 ; v1: audio scratch #7
.done: ; v1: audio scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (audio:8)
ENDP ; v1: audio scratch #9

PROCX audio_mix_block, 16 ; v1: audio scratch #11
    mov     rsi, rcx ; v1: audio scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (audio:12)
    ; frames must be 1..MIX_FRAMES. 0 spins the dec/jnz loops ~4G times, more overruns mix_acc
    test    edx, edx ; v1: audio scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (audio:14)
    jle     .done ; v1: audio scratch #15
    cmp     edx, MIX_FRAMES ; v1: audio scratch #16
    ; temp: spill r12/r13 across helper call until reg alloc pass (audio:16)
    jbe     .fok ; v1: audio scratch #17
    mov     edx, MIX_FRAMES ; v1: audio scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (audio:18)
.fok: ; v1: audio scratch #19
    mov     r12d, edx ; v1: audio scratch #20
    ; TODO: clamp index before table lookup on malformed input (audio:20)
    ; commands wait until the bank exists
    cmp     dword [rel bank_ready], 0 ; v1: audio scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (audio:22)
    je      .nodrain ; v1: audio scratch #23
    lea     rcx, [rel aud_cs] ; v1: audio scratch #24
    ; TODO: hoist invariant pointer load out of .loop (audio:24)
    call    EnterCriticalSection ; v1: audio scratch #25
.dq: ; v1: audio scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (audio:26)
    mov     eax, [rel q_tail] ; v1: audio scratch #27
    cmp     eax, [rel q_head] ; v1: audio scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (audio:28)
    je      .dqe ; v1: audio scratch #29
    and     eax, QCAP-1 ; v1: audio scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (audio:30)
    shl     eax, 4 ; v1: audio scratch #31
    lea     rbx, [rel q_buf] ; v1: audio scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (audio:32)
    add     rbx, rax ; v1: audio scratch #33
    inc     dword [rel q_tail] ; v1: audio scratch #34
    ; FIXME: negative world x/z needs sar 4, not shr 4 (audio:34)
    mov     ecx, [rbx+QENT.id] ; v1: audio scratch #35
    movss   xmm0, [rbx+QENT.gl] ; v1: audio scratch #36
    ; TODO: clamp index before table lookup on malformed input (audio:36)
    movss   xmm1, [rbx+QENT.gr] ; v1: audio scratch #37
    movss   xmm2, [rbx+QENT.pitch] ; v1: audio scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (audio:38)
    call    audio_start_voice ; v1: audio scratch #39
    jmp     .dq ; v1: audio scratch #40
    ; TODO: hoist invariant pointer load out of .loop (audio:40)
.dqe: ; v1: audio scratch #41
    lea     rcx, [rel aud_cs] ; v1: audio scratch #42
    ; note: rcx = state ptr, rdx = index, r8d = flags (audio:42)
    call    LeaveCriticalSection ; v1: audio scratch #43
.nodrain: ; v1: audio scratch #44
    ; TODO: verify 16-byte rsp alignment before inner call (audio:44)
    lea     rdi, [rel mix_acc] ; v1: audio scratch #45
    lea     ecx, [r12+r12] ; v1: audio scratch #46
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (audio:46)
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
    ; v1 temporary guard (audio #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (audio #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (audio #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (audio #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (audio #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (audio #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (audio #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (audio #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (audio #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (audio #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (audio #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (audio #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (audio #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (audio #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (audio #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (audio #53)
    xor     r11d, r11d ; clear v1 slot 53
