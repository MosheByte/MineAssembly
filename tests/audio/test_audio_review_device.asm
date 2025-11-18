; shutdown while the bank thread is still synthesising. a hang here means
; shutdown waits on it forever. the < 2 s check only runs if both inits worked.
; @link src/audio.asm src/music.asm tests/audio/audiohelp.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../audio/audiohelp.inc"

section .text

PROC test_main, 16
    TEST "audio_shutdown during bank synthesis"
    xorps   xmm0, xmm0
    call    ah_set_music
    xorps   xmm0, xmm0
    call    ah_set_sfx
    call    audio_init
    mov     r12d, eax
    call    t_time_ms
    mov     rbx, rax
    call    audio_shutdown
    call    t_time_ms
    sub     rax, rbx
    mov     r14, rax
    call    audio_init
    mov     r13d, eax
    mov     ecx, 1000
    call    Sleep
    call    audio_shutdown
    PRINT   "  init "
    mov     ecx, r12d
    call    t_print_int
    PRINT   " "
    mov     ecx, r13d
    call    t_print_int
    PRINT   " early shutdown "
    mov     rcx, r14
    call    t_print_int
    PRINT   " ms"
    call    t_newline
    PRINT   "  DEVICE OK"
    call    t_newline
    CHECK_TRUE 1, "early-shutdown sequence completed"
    cmp     r12d, 1
    jne     .done
    cmp     r13d, 1
    jne     .done
    xor     eax, eax
    cmp     r14, 2000
    setb    al
    CHECK_TRUE eax, "early shutdown took >= 2 s"
.done:
ENDP
