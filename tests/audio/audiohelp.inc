; audiohelp.inc - shared bits for the audio tests. include after testlib.inc,
; link tests/audio/audiohelp.asm. the audio/music dbg entry points are global
; but not in api.inc, so they're declared here.
%ifndef AUDIOHELP_INC
%define AUDIOHELP_INC

%define FS                  44100
%define MIX_FRAMES          1024        ; audio_mix_block max

extern audio_dbg_sfx_count
extern audio_dbg_render_sfx     ; (id, variant, float* out, max frames) -> frames
extern audio_dbg_offline_begin  ; builds the bank, no device
extern audio_dbg_mix            ; (int16* stereo, frames) -> frames
extern audio_dbg_active_voices
extern audio_mix_block
extern music_dbg_render         ; (mood, seed, float* stereo, frames)
extern music_dbg_state          ; 0 idle 1 play 2 tail 3 fade
extern music_dbg_info           ; int[8]: mood, step, total, step_len, root,
                                ;   start serial, finished serial, main-thread mood

%ifndef IMPL_AUDIOHELP
extern ah_set_music
extern ah_set_sfx
extern ah_player                ; (x, y, z, yaw), eye height forced to 1.62
extern ah_peak_f
extern ah_rms_f
extern ah_mean_f
extern ah_finite_f
extern ah_allclose_f            ; (a, b, n, stride), 1e-8 abs + 1e-5 rel tolerance
extern ah_i16_absmax
extern ah_i16_rms
extern ah_last_loud_f           ; -1 if nothing above thr
extern ah_dominant_hz
extern ah_scpy                  ; returns end of dst (at the 0)
extern ah_sdec
extern ah_write_wav             ; ARG5: 1 = float data, 0 = int16
extern ah_mkdir
extern ah_mix_discard
extern ah_wait_music_start
%endif

; clobbers rax
%macro DLOAD 2
    mov  rax, __?float64?__(%2)
    movq %1, rax
%endmacro

; clobbers eax
%macro FLOAD 2
    mov  eax, __?float32?__(%2)
    movd %1, eax
%endmacro

%endif
