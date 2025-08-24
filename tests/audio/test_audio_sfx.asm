; renders every sfx patch offline, 3 variants each, and sanity checks them.
; dumps audio_wav/sfx_NN_name.wav (+ _v1/_v2 for dig_stone, dig_wood, boar)
; @link src/audio.asm src/music.asm tests/audio/audiohelp.asm
; @timeout 300
%include "common.inc"
%include "testlib.inc"
%include "../audio/audiohelp.inc"

%define NAME_SLOT   16
%define BUF_FRAMES  (FS*6)

; eax = (xmm cc literal), cc is a/ae/b/be
%macro DCMP 3
    DLOAD xmm5, %3
    xor     eax, eax
    comisd  %1, xmm5
    set%2   al
%endmacro

; fixed 16-byte slot per name, index = sound id
%macro NAME16 1
%%s: db %1, 0
    times NAME_SLOT-($-%%s) db 0
%endmacro

section .rdata
align 16
sfx_names:
    NAME16 "dig_stone"
    NAME16 "dig_dirt"
    NAME16 "dig_grass"
    NAME16 "dig_wood"
    NAME16 "dig_sand"
    NAME16 "dig_gravel"
    NAME16 "glass_break"
    NAME16 "dig_snow"
    NAME16 "dig_wool"
    NAME16 "place"
    NAME16 "step"
    NAME16 "explode"
    NAME16 "hurt"
    NAME16 "pop"
    NAME16 "click"
    NAME16 "splash"
    NAME16 "swim"
    NAME16 "boar"
    NAME16 "woolly"
    NAME16 "shambler"
    NAME16 "fuse"
    NAME16 "eat"
    NAME16 "fizz"
    NAME16 "death"
    NAME16 "levelup"
    NAME16 "chest"
    NAME16 "thunder"
    NAME16 "step_stone"
    NAME16 "step_dirt"
    NAME16 "step_grass"
    NAME16 "step_wood"
    NAME16 "step_sand"
    NAME16 "step_gravel"
    NAME16 "step_glass"
    NAME16 "step_snow"
    NAME16 "step_wool"
%define NUM_NAMES 36

; expected length in s (end of the longest layer), 0 = skip. catches patch
; table edits
align 8
sfx_len:
    dq 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 0.0, 0.0, 0.0        ;  0..9  glass_break
    dq 0.0, 3.0, 0.0, 0.0, 0.04, 0.9, 0.0, 0.0, 0.0, 1.3       ; 10..19 explode click splash shambler
    dq 1.5, 0.0, 0.0, 0.0, 1.24, 0.0, 5.0, 0.0, 0.0, 0.0       ; 20..29 fuse levelup thunder
    dq 0.0, 0.0, 0.0, 0.0, 0.0, 0.0

s_dir:      db "audio_wav", 0
s_pre:      db "audio_wav\sfx_", 0
s_us:       db "_", 0
s_v:        db "_v", 0
s_wav:      db ".wav", 0
s_sound:    db "sound ", 0
s_variant:  db " variant ", 0
s_sp:       db " ", 0
s_s:        db "s peak ", 0
s_rms:      db " rms ", 0

section .bss
alignb 16
sbuf:       resd BUF_FRAMES
vbuf:       resd BUF_FRAMES*3
vlen:       resd 3

section .text

PROC test_main
    lea     rcx, [rel s_dir]
    call    ah_mkdir
    call    sfx_math
    call    sfx_all
ENDP

PROC zero_sbuf, 0
    lea     rdi, [rel sbuf]
    mov     ecx, BUF_FRAMES
    xor     eax, eax
    rep     stosd
ENDP

PROCX sfx_math, 16
    TEST "math helpers via synthesis sanity"
    ; click is a decaying 2.2 -> 1.8 kHz sine
    call    zero_sbuf
    mov     ecx, SFX_CLICK
    xor     edx, edx
    lea     r8, [rel sbuf]
    mov     r9d, FS
    call    audio_dbg_render_sfx
    mov     ebx, eax
    lea     rcx, [rel sbuf]
    mov     edx, ebx
    mov     r8d, 16384
    call    ah_dominant_hz
    movsd   xmm6, xmm0
    PRINT   "  click: "
    mov     ecx, ebx
    call    t_print_int
    PRINT   " frames, dominant "
    movsd   xmm0, xmm6
    xor     edx, edx
    call    t_print_double
    PRINT   " Hz"
    call    t_newline
    DCMP    xmm6, a, 900.0
    mov     r12d, eax
    DCMP    xmm6, b, 2400.0
    and     eax, r12d
    CHECK_TRUE eax, "click dominant frequency in 900..2400 Hz"

    call    zero_sbuf
    mov     ecx, SFX_LEVELUP
    xor     edx, edx
    lea     r8, [rel sbuf]
    mov     r9d, FS
    call    audio_dbg_render_sfx
    lea     rcx, [rel sbuf]
    add     rcx, 200*4                  ; frames 200..3000
    mov     edx, 2800
    mov     r8d, 65536
    call    ah_dominant_hz
    movsd   xmm6, xmm0
    PRINT   "  levelup first note: "
    movsd   xmm0, xmm6
    mov     edx, 1
    call    t_print_double
    PRINT   " Hz (C6 = 1046.5)"
    call    t_newline
    DLOAD   xmm0, 1046.5
    movapd  xmm1, xmm6
    subsd   xmm1, xmm0
    DLOAD   xmm0, 0.0
    subsd   xmm0, xmm1
    maxsd   xmm1, xmm0
    DCMP    xmm1, b, 15.0
    CHECK_TRUE eax, "levelup first note is C6 (+-15 Hz)"
ENDPX

PROC build_path, 0
    mov     rbx, rcx
    mov     r12d, edx
    mov     r13, r8
    mov     r14d, r9d
    lea     rdx, [rel s_pre]
    call    ah_scpy
    mov     rcx, rax
    mov     edx, r12d
    mov     r8d, 2
    call    ah_sdec
    mov     rcx, rax
    lea     rdx, [rel s_us]
    call    ah_scpy
    mov     rcx, rax
    mov     rdx, r13
    call    ah_scpy
    test    r14d, r14d
    js      .nov
    mov     rcx, rax
    lea     rdx, [rel s_v]
    call    ah_scpy
    mov     rcx, rax
    mov     edx, r14d
    mov     r8d, 1
    call    ah_sdec
.nov:
    mov     rcx, rax
    lea     rdx, [rel s_wav]
    call    ah_scpy
    mov     rax, rbx
ENDP

; r12d sid, r13d variant, r14d frames, r15 name, xmm6 peak, xmm7 rms,
; LOC(0) count, LOC(4) failures before this sound, LOC(16..) path/msg buffer
PROCX sfx_all, 160
    TEST "sound effects"
    call    audio_dbg_sfx_count
    mov     LOC(0), eax
    CHECK_EQ32 LOC(0), NUM_NAMES, "sfx count"
    xor     r12d, r12d
.sid:
    cmp     r12d, LOC(0)
    jge     .after
    cmp     r12d, NUM_NAMES
    jge     .after
    lea     r15, [rel sfx_names]
    mov     eax, r12d
    shl     eax, 4
    add     r15, rax
    mov     eax, [rel t_failures]
    mov     LOC(4), eax
    xor     r13d, r13d
.var:
    cmp     r13d, 3
    jge     .vdone
    call    zero_sbuf
    mov     ecx, r12d
    mov     edx, r13d
    lea     r8, [rel sbuf]
    mov     r9d, BUF_FRAMES
    call    audio_dbg_render_sfx
    mov     r14d, eax
    lea     rax, [rel vlen]
    mov     [rax+r13*4], r14d
    lea     rsi, [rel sbuf]
    lea     rdi, [rel vbuf]
    imul    rax, r13, BUF_FRAMES*4
    add     rdi, rax
    mov     ecx, r14d
    rep     movsd

    xor     eax, eax
    cmp     r14d, 100
    setg    al
    CHECK_TRUE eax, "sound renders more than 100 frames"
    lea     rcx, [rel sbuf]
    mov     edx, r14d
    call    ah_finite_f
    CHECK_TRUE eax, "sound has no NaN/Inf"
    lea     rcx, [rel sbuf]
    mov     edx, r14d
    call    ah_peak_f
    movsd   xmm6, xmm0
    lea     rcx, [rel sbuf]
    mov     edx, r14d
    call    ah_rms_f
    movsd   xmm7, xmm0
    DCMP    xmm6, ae, 0.5
    mov     LOC(8), eax
    DCMP    xmm6, be, 0.96
    and     eax, LOC(8)
    CHECK_TRUE eax, "sound peak in 0.5..0.96"
    DCMP    xmm7, a, 0.01
    CHECK_TRUE eax, "sound too quiet (rms <= 0.01)"
    lea     rcx, [rel sbuf]
    mov     edx, r14d
    call    ah_mean_f
    xorpd   xmm1, xmm1
    subsd   xmm1, xmm0
    maxsd   xmm0, xmm1
    DCMP    xmm0, b, 0.02
    CHECK_TRUE eax, "sound DC offset >= 0.02"
    ; no click at the end: last 2 ms (88 frames) < 0.25 peak + 0.01
    mov     eax, r14d
    sub     eax, 88
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    mov     edx, r14d
    sub     edx, eax
    lea     rcx, [rel sbuf]
    lea     rcx, [rcx+rax*4]
    call    ah_peak_f
    DLOAD   xmm1, 0.25
    mulsd   xmm1, xmm6
    DLOAD   xmm2, 0.01
    addsd   xmm1, xmm2
    xor     eax, eax
    comisd  xmm0, xmm1
    setb    al
    CHECK_TRUE eax, "sound ends abruptly (last 88 frames loud)"
    ; |n - L*FS| < 20 ms
    lea     rax, [rel sfx_len]
    movsd   xmm0, [rax+r12*8]
    xorpd   xmm1, xmm1
    comisd  xmm0, xmm1
    jbe     .nolen
    DLOAD   xmm1, 44100.0
    mulsd   xmm0, xmm1
    cvtsi2sd xmm2, r14d
    subsd   xmm2, xmm0
    xorpd   xmm3, xmm3
    subsd   xmm3, xmm2
    maxsd   xmm2, xmm3
    DLOAD   xmm3, 0.02
    mulsd   xmm3, xmm1
    xor     eax, eax
    comisd  xmm2, xmm3
    setb    al
    CHECK_TRUE eax, "sound length differs from the patch table by >= 20 ms"
.nolen:
    test    r13d, r13d
    jnz     .notv0
    PRINT   "  "
    cmp     r12d, 10
    jge     .w2
    PRINT   " "
.w2:
    mov     ecx, r12d
    call    t_print_int
    lea     rcx, [rel s_sp]
    call    t_print
    mov     rcx, r15
    call    t_print
    lea     rcx, [rel s_sp]
    call    t_print
    cvtsi2sd xmm0, r14d
    DLOAD   xmm1, 44100.0
    divsd   xmm0, xmm1
    mov     edx, 2
    call    t_print_double
    lea     rcx, [rel s_s]
    call    t_print
    movsd   xmm0, xmm6
    mov     edx, 2
    call    t_print_double
    lea     rcx, [rel s_rms]
    call    t_print
    movsd   xmm0, xmm7
    mov     edx, 3
    call    t_print_double
    call    t_newline
    lea     rcx, LOC(16)
    mov     edx, r12d
    mov     r8, r15
    mov     r9d, -1
    call    build_path
    jmp     .wav
.notv0:
    cmp     r12d, SFX_DIG_STONE
    je      .vwav
    cmp     r12d, SFX_DIG_WOOD
    je      .vwav
    cmp     r12d, SFX_BOAR
    jne     .nextv
.vwav:
    lea     rcx, LOC(16)
    mov     edx, r12d
    mov     r8, r15
    mov     r9d, r13d
    call    build_path
.wav:
    lea     rcx, LOC(16)
    lea     rdx, [rel sbuf]
    mov     r8d, r14d
    mov     r9d, 1
    mov     qword [rsp+32], 1
    call    ah_write_wav
.nextv:
    inc     r13d
    jmp     .var

.vdone:
    ; variants 0 and 1 must differ over the shortest length
    lea     rax, [rel vlen]
    mov     r8d, [rax]
    mov     ecx, [rax+4]
    cmp     ecx, r8d
    cmovl   r8d, ecx
    mov     ecx, [rax+8]
    cmp     ecx, r8d
    cmovl   r8d, ecx
    lea     rcx, [rel vbuf]
    lea     rdx, [rcx+BUF_FRAMES*4]
    mov     r9d, 1
    call    ah_allclose_f
    xor     eax, 1
    CHECK_TRUE eax, "sound variants 0 and 1 are identical"
    call    zero_sbuf
    mov     ecx, r12d
    xor     edx, edx
    lea     r8, [rel sbuf]
    mov     r9d, BUF_FRAMES
    call    audio_dbg_render_sfx
    xor     r8d, r8d
    cmp     eax, [rel vlen]
    jne     .ndet
    mov     ecx, eax
    lea     rsi, [rel sbuf]
    lea     rdi, [rel vbuf]
    cmp     ecx, ecx                    ; ZF=1 so n == 0 counts as equal
    repe    cmpsd
    jne     .ndet
    mov     r8d, 1
.ndet:
    CHECK_TRUE r8d, "sound rendering is not deterministic"
    ; tag failures with the sound name
    mov     eax, [rel t_failures]
    cmp     eax, LOC(4)
    je      .nextsid
    lea     rcx, LOC(16)
    lea     rdx, [rel s_sound]
    call    ah_scpy
    mov     rcx, rax
    mov     rdx, r15
    call    ah_scpy
    lea     rcx, LOC(16)
    call    t_fail_detail
.nextsid:
    inc     r12d
    jmp     .sid

.after:
    mov     ecx, 99
    xor     edx, edx
    lea     r8, [rel sbuf]
    mov     r9d, BUF_FRAMES
    call    audio_dbg_render_sfx
    CHECK_EQ32 eax, 0, "invalid sound id 99 rendered frames"
ENDPX
