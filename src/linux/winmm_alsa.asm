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
    test rax, rax
    jz   .fail_ev
    mov  [r14+WO_THREAD], rax
    mov  [rbx], r14
    test r13, r13
    jz   .ok
    mov  rcx, r13
    call SetEvent                       ; WOM_OPEN
.ok:
    xor  eax, eax
    jmp  .done
.fail_ev:
    mov  rcx, [r14+WO_WAKE]
    call CloseHandle
.fail_cs:
    lea  rcx, [r14+WO_CS]
    call DeleteCriticalSection
    mov  rdi, [r14+WO_PCM]
    CCALL snd_pcm_close
    mov  rdi, r14
    CCALL free
    mov  eax, MMSYSERR_ERROR
    jmp  .done
.badfmt_close:
    mov  rdi, [r14+WO_PCM]
    CCALL snd_pcm_close
    mov  rdi, r14
    CCALL free
.badfmt:
    mov  eax, WAVERR_BADFORMAT
    jmp  .done
.nodev:
    mov  rdi, r14
    CCALL free
    mov  eax, MMSYSERR_BADDEVICEID      ; no card (ci, headless): game runs silent
    jmp  .done
.nomem:
    mov  eax, MMSYSERR_NOMEM
    jmp  .done
.param:
    mov  eax, MMSYSERR_INVALPARAM
.done:
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

PROCX waveOutPrepareHeader
    test rcx, rcx
    jz   .inval
    test rdx, rdx
    jz   .param
    or   dword [rdx+WH_FLAGS], WHDR_PREPARED
    xor  eax, eax
    jmp  .done
.inval:
    mov  eax, MMSYSERR_INVALHANDLE
    jmp  .done
.param:
    mov  eax, MMSYSERR_INVALPARAM
.done:
ENDPX

PROCX waveOutUnprepareHeader
    test rcx, rcx
    jz   .inval
    test rdx, rdx
    jz   .param
    test dword [rdx+WH_FLAGS], WHDR_INQUEUE
    jnz  .playing
    and  dword [rdx+WH_FLAGS], ~WHDR_PREPARED
    xor  eax, eax
    jmp  .done
.playing:
    mov  eax, WAVERR_STILLPLAYING
    jmp  .done
.inval:
    mov  eax, MMSYSERR_INVALHANDLE
    jmp  .done
.param:
    mov  eax, MMSYSERR_INVALPARAM
.done:
ENDPX

PROCX waveOutWrite
    mov  rbx, rcx
    mov  r12, rdx
    test rbx, rbx
    jz   .inval
    test r12, r12
    jz   .param
    mov  eax, [r12+WH_FLAGS]
    test eax, WHDR_PREPARED
    jz   .unprep
    test eax, WHDR_INQUEUE
    jnz  .playing
    lea  rcx, [rbx+WO_CS]
    call EnterCriticalSection
    mov  eax, [rbx+WO_TAIL]
    mov  ecx, eax
    sub  ecx, [rbx+WO_HEAD]
    cmp  ecx, WO_QN
    jae  .full
    mov  ecx, [r12+WH_FLAGS]
    and  ecx, ~WHDR_DONE
    or   ecx, WHDR_INQUEUE
    mov  [r12+WH_FLAGS], ecx
    and  eax, WO_QN-1
    mov  [rbx+WO_Q+rax*8], r12
    inc  dword [rbx+WO_TAIL]
    lea  rcx, [rbx+WO_CS]
    call LeaveCriticalSection
    mov  rcx, [rbx+WO_WAKE]
    call SetEvent
    xor  eax, eax
    jmp  .done
.full:
    lea  rcx, [rbx+WO_CS]
    call LeaveCriticalSection
    mov  eax, MMSYSERR_NOMEM
    jmp  .done
.unprep:
    mov  eax, WAVERR_UNPREPARED
    jmp  .done
.playing:
    mov  eax, WAVERR_STILLPLAYING
    jmp  .done
.inval:
    mov  eax, MMSYSERR_INVALHANDLE
    jmp  .done
.param:
    mov  eax, MMSYSERR_INVALPARAM
.done:
ENDPX

; every queued header comes back DONE right away, alsa gets flushed by the writer
PROCX waveOutReset
    mov  rbx, rcx
    test rbx, rbx
    jz   .inval
    lea  rcx, [rbx+WO_CS]
    call EnterCriticalSection
    mov  eax, [rbx+WO_HEAD]
.l:
    cmp  eax, [rbx+WO_TAIL]
    je   .e
    mov  ecx, eax
    and  ecx, WO_QN-1
    mov  rdx, [rbx+WO_Q+rcx*8]
    mov  ecx, [rdx+WH_FLAGS]
    and  ecx, ~WHDR_INQUEUE
    or   ecx, WHDR_DONE
    mov  [rdx+WH_FLAGS], ecx
    inc  eax
    jmp  .l
.e:
    mov  [rbx+WO_HEAD], eax
    mov  dword [rbx+WO_OFF], 0
    inc  dword [rbx+WO_GEN]
    mov  dword [rbx+WO_DROP], 1
    lea  rcx, [rbx+WO_CS]
    call LeaveCriticalSection
    mov  rcx, [rbx+WO_WAKE]
    call SetEvent
    mov  rcx, [rbx+WO_EVENT]
    test rcx, rcx
    jz   .ok
    call SetEvent
.ok:
    xor  eax, eax
    jmp  .done
.inval:
    mov  eax, MMSYSERR_INVALHANDLE
.done:
ENDPX

; still queued = STILLPLAYING, like windows. writer that won't stop within 5s
; (alsa wedged) gets left alone with its device, leaked
PROCX waveOutClose
    mov  rbx, rcx
    test rbx, rbx
    jz   .inval
    mov  eax, [rbx+WO_TAIL]
    cmp  eax, [rbx+WO_HEAD]
    jne  .playing
    mov  dword [rbx+WO_QUIT], 1
    mov  rcx, [rbx+WO_WAKE]
    call SetEvent
    mov  rcx, [rbx+WO_THREAD]
    mov  edx, 5000
    call WaitForSingleObject
    mov  r12d, eax
    mov  rcx, [rbx+WO_THREAD]
    call CloseHandle
    mov  r13, [rbx+WO_EVENT]
    test r12d, r12d
    jnz  .cb
    mov  rdi, [rbx+WO_PCM]
    CCALL snd_pcm_close
    mov  rcx, [rbx+WO_WAKE]
    call CloseHandle
    lea  rcx, [rbx+WO_CS]
    call DeleteCriticalSection
    mov  rdi, rbx
    CCALL free
.cb:
    test r13, r13
    jz   .ok
    mov  rcx, r13
    call SetEvent                       ; WOM_CLOSE
.ok:
    xor  eax, eax
    jmp  .done
.playing:
    mov  eax, WAVERR_STILLPLAYING
    jmp  .done
.inval:
    mov  eax, MMSYSERR_INVALHANDLE
.done:
ENDPX

%endif
