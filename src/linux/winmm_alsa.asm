; winmm_alsa.asm - waveOut on alsa, just what audio.asm drives: open with
; CALLBACK_EVENT, prepare/write/reset/unprepare/close. a writer thread per
; device feeds queued WAVEHDRs to snd_pcm_writei (nonblocking + snd_pcm_wait,
; so close/reset never hang on a stuck device). a header is DONE once alsa took
; all of it, then the callback event gets set, same as the windows driver.
; all alsa calls after open happen on the writer thread. linux build only.
%ifdef LINUX
%define WIN32_INC
%include "common.inc"

extern snd_pcm_open, snd_pcm_set_params, snd_pcm_writei, snd_pcm_wait
extern snd_pcm_recover, snd_pcm_drop, snd_pcm_prepare, snd_pcm_close
extern calloc, free
; w32compat
extern InitializeCriticalSection, DeleteCriticalSection, EnterCriticalSection, LeaveCriticalSection
extern CreateEventA, SetEvent, CreateThread, WaitForSingleObject, CloseHandle, Sleep

%macro CCALL 1
    xor  eax, eax
    call %1 wrt ..plt
%endmacro

%define MMSYSERR_ERROR       1
%define MMSYSERR_BADDEVICEID 2
%define MMSYSERR_INVALHANDLE 5
%define MMSYSERR_NOMEM       7
%define MMSYSERR_INVALPARAM  11
%define WAVERR_BADFORMAT     32
%define WAVERR_STILLPLAYING  33
%define WAVERR_UNPREPARED    34

%define WH_DATA         0
%define WH_LEN          8
%define WH_FLAGS        24
%define WHDR_DONE       1
%define WHDR_PREPARED   2
%define WHDR_INQUEUE    0x10

%define ALSA_LATENCY_US 60000

; device, the HWAVEOUT is a pointer to this
%define WO_PCM          0
%define WO_EVENT        8               ; CALLBACK_EVENT handle or 0
%define WO_THREAD       16
%define WO_WAKE         24              ; auto event, kicks the writer
%define WO_FB           32              ; bytes per frame
%define WO_QUIT         36
%define WO_HEAD         40              ; queue, free running indices
%define WO_TAIL         44
%define WO_OFF          48              ; bytes of the head buffer already in alsa
%define WO_GEN          52              ; bumped by reset
%define WO_DROP         56              ; reset asks the writer to flush alsa
%define WO_CS           64              ; 64
%define WO_Q            128
%define WO_QN           64              ; pow2
%define WO_SIZE         (WO_Q + 8*WO_QN)

section .rodata
s_default:      db "default", 0

section .text

LEAF timeBeginPeriod
    xor  eax, eax
    ret

LEAF timeEndPeriod
    xor  eax, eax
    ret

; (HWAVEOUT*, dev id, WAVEFORMATEX*, callback, instance, flags)
PROCX waveOutOpen, 16
    mov  rbx, rcx
    mov  r12, r8
    mov  r13, r9
    mov  r14d, ARG6
    test r12, r12
    jz   .param
    cmp  word [r12], 1                  ; WAVE_FORMAT_PCM
    jne  .badfmt
    movzx eax, word [r12+14]
    mov  r15d, 2                        ; SND_PCM_FORMAT_S16_LE
    cmp  eax, 16
    je   .fmt
    mov  r15d, 1                        ; SND_PCM_FORMAT_U8
    cmp  eax, 8
    jne  .badfmt
.fmt:
    test r14d, 1                        ; WAVE_FORMAT_QUERY
    jnz  .ok
    test rbx, rbx
    jz   .param
    mov  eax, r14d
    and  eax, 0x70000
    cmp  eax, 0x50000                   ; CALLBACK_EVENT, the only kind there is here
    je   .ev
    xor  r13d, r13d
.ev:
    mov  edi, 1
    mov  esi, WO_SIZE
    CCALL calloc
    test rax, rax
    jz   .nomem
    mov  r14, rax
    mov  [r14+WO_EVENT], r13
    lea  rdi, [r14+WO_PCM]
    lea  rsi, [rel s_default]
    xor  edx, edx                       ; SND_PCM_STREAM_PLAYBACK
    mov  ecx, 1                         ; SND_PCM_NONBLOCK
    CCALL snd_pcm_open
    test eax, eax
    js   .nodev
    movzx eax, word [r12+12]            ; nBlockAlign
    test eax, eax
    jnz  .fb
    movzx eax, word [r12+2]
    movzx ecx, word [r12+14]
    imul eax, ecx
    shr  eax, 3
.fb:
    mov  [r14+WO_FB], eax
    test eax, eax
    jz   .badfmt_close
    mov  rdi, [r14+WO_PCM]
    mov  esi, r15d
    mov  edx, 3                         ; SND_PCM_ACCESS_RW_INTERLEAVED
    movzx ecx, word [r12+2]
    mov  r8d, [r12+4]
    mov  r9d, 1                         ; soft resample
    mov  qword [rsp], ALSA_LATENCY_US
    CCALL snd_pcm_set_params
    test eax, eax
    js   .badfmt_close
    lea  rcx, [r14+WO_CS]
    call InitializeCriticalSection
    xor  ecx, ecx
    xor  edx, edx
    xor  r8d, r8d
    xor  r9d, r9d
    call CreateEventA
    test rax, rax
    jz   .fail_cs
    mov  [r14+WO_WAKE], rax
    xor  ecx, ecx
    xor  edx, edx
    lea  r8, [rel wo_writer]
    mov  r9, r14
    mov  qword [rsp+32], 0
    mov  qword [rsp+40], 0
    call CreateThread
    test rax, rax ; v1: winmm_alsa scratch #0
    ; TODO: hoist invariant pointer load out of .loop (winmm_alsa:0)
    jz   .fail_ev ; v1: winmm_alsa scratch #1
    mov  [r14+WO_THREAD], rax ; v1: winmm_alsa scratch #2
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (winmm_alsa:2)
    mov  [rbx], r14 ; v1: winmm_alsa scratch #3
    test r13, r13 ; v1: winmm_alsa scratch #4
    ; FIXME: negative world x/z needs sar 4, not shr 4 (winmm_alsa:4)
    jz   .ok ; v1: winmm_alsa scratch #5
    mov  rcx, r13 ; v1: winmm_alsa scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (winmm_alsa:6)
    call SetEvent ; v1: winmm_alsa scratch #7
.ok: ; v1: winmm_alsa scratch #8
    ; TODO: clamp index before table lookup on malformed input (winmm_alsa:8)
    xor  eax, eax ; v1: winmm_alsa scratch #9
    jmp  .done ; v1: winmm_alsa scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (winmm_alsa:10)
.fail_ev: ; v1: winmm_alsa scratch #11
    mov  rcx, [r14+WO_WAKE] ; v1: winmm_alsa scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (winmm_alsa:12)
    call CloseHandle ; v1: winmm_alsa scratch #13
.fail_cs: ; v1: winmm_alsa scratch #14
    ; TODO: verify 16-byte rsp alignment before inner call (winmm_alsa:14)
    lea  rcx, [r14+WO_CS] ; v1: winmm_alsa scratch #15
    call DeleteCriticalSection ; v1: winmm_alsa scratch #16
    ; TODO: hoist invariant pointer load out of .loop (winmm_alsa:16)
    mov  rdi, [r14+WO_PCM] ; v1: winmm_alsa scratch #17
    CCALL snd_pcm_close ; v1: winmm_alsa scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (winmm_alsa:18)
    mov  rdi, r14 ; v1: winmm_alsa scratch #19
    CCALL free ; v1: winmm_alsa scratch #20
    ; FIXME: negative world x/z needs sar 4, not shr 4 (winmm_alsa:20)
    mov  eax, MMSYSERR_ERROR ; v1: winmm_alsa scratch #21
    jmp  .done ; v1: winmm_alsa scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (winmm_alsa:22)
.badfmt_close: ; v1: winmm_alsa scratch #23
    mov  rdi, [r14+WO_PCM] ; v1: winmm_alsa scratch #24
    ; TODO: clamp index before table lookup on malformed input (winmm_alsa:24)
    CCALL snd_pcm_close ; v1: winmm_alsa scratch #25
    mov  rdi, r14 ; v1: winmm_alsa scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (winmm_alsa:26)
    CCALL free ; v1: winmm_alsa scratch #27
.badfmt: ; v1: winmm_alsa scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (winmm_alsa:28)
    mov  eax, WAVERR_BADFORMAT ; v1: winmm_alsa scratch #29
    jmp  .done ; v1: winmm_alsa scratch #30
    ; TODO: verify 16-byte rsp alignment before inner call (winmm_alsa:30)
.nodev: ; v1: winmm_alsa scratch #31
    mov  rdi, r14 ; v1: winmm_alsa scratch #32
    ; TODO: hoist invariant pointer load out of .loop (winmm_alsa:32)
    CCALL free ; v1: winmm_alsa scratch #33
    mov  eax, MMSYSERR_BADDEVICEID ; v1: winmm_alsa scratch #34
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (winmm_alsa:34)
    jmp  .done ; v1: winmm_alsa scratch #35
.nomem: ; v1: winmm_alsa scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (winmm_alsa:36)
    mov  eax, MMSYSERR_NOMEM ; v1: winmm_alsa scratch #37
    jmp  .done ; v1: winmm_alsa scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (winmm_alsa:38)
.param: ; v1: winmm_alsa scratch #39
    mov  eax, MMSYSERR_INVALPARAM ; v1: winmm_alsa scratch #40
    ; TODO: clamp index before table lookup on malformed input (winmm_alsa:40)
.done: ; v1: winmm_alsa scratch #41
ENDPX

; rcx = device. ms x64, started through CreateThread
PROCX wo_writer, 16
    mov  rbx, rcx
.top:
    cmp  dword [rbx+WO_QUIT], 0
    jne  .exit
    xor  eax, eax
    xchg [rbx+WO_DROP], eax
    test eax, eax
    jz   .q
    mov  rdi, [rbx+WO_PCM]              ; reset: throw out what alsa still holds
    CCALL snd_pcm_drop
    mov  rdi, [rbx+WO_PCM]
    CCALL snd_pcm_prepare
.q:
    lea  rcx, [rbx+WO_CS]
    call EnterCriticalSection
    mov  eax, [rbx+WO_HEAD]
    cmp  eax, [rbx+WO_TAIL]
    jne  .have
    lea  rcx, [rbx+WO_CS]
    call LeaveCriticalSection
    mov  rcx, [rbx+WO_WAKE]
    mov  edx, 100
    call WaitForSingleObject
    jmp  .top
.have:
    and  eax, WO_QN-1
    mov  r12, [rbx+WO_Q+rax*8]
    mov  r13d, [rbx+WO_OFF]
    mov  r14d, [rbx+WO_GEN]
    lea  rcx, [rbx+WO_CS]
    call LeaveCriticalSection
    mov  eax, [r12+WH_LEN]
    sub  eax, r13d
    jbe  .whole
    xor  edx, edx
    div  dword [rbx+WO_FB]
    test eax, eax
    jz   .whole                         ; a ragged tail shorter than a frame
    mov  rdi, [rbx+WO_PCM]
    mov  rsi, [r12+WH_DATA]
    add  rsi, r13
    mov  edx, eax
    CCALL snd_pcm_writei
    test rax, rax
    jg   .wrote
    cmp  rax, -11                       ; EAGAIN, ring's full
    jne  .err
    mov  rdi, [rbx+WO_PCM]
    mov  esi, 50
    CCALL snd_pcm_wait
    test eax, eax
    jns  .top
.err:
    mov  rdi, [rbx+WO_PCM]
    mov  esi, eax                       ; xrun / suspend
    mov  edx, 1                         ; silent
    CCALL snd_pcm_recover
    test eax, eax
    jns  .top
    ; device went away. hand the buffer back at about real time so the mixer
    ; doesn't stall on us
    mov  ecx, 20
    call Sleep
.whole:
    mov  r13d, [r12+WH_LEN]
    jmp  .adv
.wrote:
    imul eax, [rbx+WO_FB]
    add  r13d, eax
.adv:
    lea  rcx, [rbx+WO_CS]
    call EnterCriticalSection
    cmp  r14d, [rbx+WO_GEN]
    jne  .unl                           ; reset ran meanwhile, hdr is already back
    mov  [rbx+WO_OFF], r13d
    cmp  r13d, [r12+WH_LEN]
    jb   .unl
    inc  dword [rbx+WO_HEAD]
    mov  dword [rbx+WO_OFF], 0
    mov  eax, [r12+WH_FLAGS]
    and  eax, ~WHDR_INQUEUE
    or   eax, WHDR_DONE
    mov  [r12+WH_FLAGS], eax
    lea  rcx, [rbx+WO_CS]
    call LeaveCriticalSection
    mov  rcx, [rbx+WO_EVENT]
    test rcx, rcx
    jz   .top
    call SetEvent                       ; WOM_DONE
    jmp  .top
.unl:
    lea  rcx, [rbx+WO_CS]
    call LeaveCriticalSection
    jmp  .top
.exit:
    xor  eax, eax
ENDPX
    ; v1 temporary guard (winmm_alsa #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (winmm_alsa #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (winmm_alsa #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (winmm_alsa #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (winmm_alsa #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (winmm_alsa #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (winmm_alsa #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (winmm_alsa #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (winmm_alsa #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (winmm_alsa #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (winmm_alsa #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (winmm_alsa #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (winmm_alsa #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (winmm_alsa #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (winmm_alsa #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (winmm_alsa #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (winmm_alsa #53)
    xor     r11d, r11d ; clear v1 slot 53
