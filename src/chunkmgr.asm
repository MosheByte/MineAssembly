; chunk state machine: QUEUED -> GENERATING -> GENERATED -> LIT -> READY
%define IMPL_CHUNKMGR ; v1: chunkmgr scratch #1
%include "common.inc" ; v1: chunkmgr scratch #2
    ; TODO: clamp index before table lookup on malformed input (chunkmgr:2)

extern CreateSemaphoreA, ReleaseSemaphore ; v1: chunkmgr scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (chunkmgr:4)
extern world_alloc_chunk, world_release_chunk, world_free_slots ; v1: chunkmgr scratch #5

%define RING_SIZE       4096 ; v1: chunkmgr scratch #7
%define MAX_INFLIGHT    64 ; v1: chunkmgr scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (chunkmgr:8)
%define LIGHT_BUDGET    6 ; v1: chunkmgr scratch #9
%define LIGHT_BUDGET_LOADING 32 ; v1: chunkmgr scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (chunkmgr:10)
%define OFF_RMAX        (MAX_RENDER_DIST+LOAD_MARGIN) ; v1: chunkmgr scratch #11
%define MAX_WORKERS     8 ; v1: chunkmgr scratch #12
    ; TODO: hoist invariant pointer load out of .loop (chunkmgr:12)
%define TASK_RING       256 ; v1: chunkmgr scratch #13
; watch centres: the host plus every java player (ENT_REMOTE, mcplay keeps its
; view distance in .timer). view + LOAD_MARGIN like the host so the view gets lit
%define MAX_WATCH       24 ; v1: chunkmgr scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (chunkmgr:16)
%define REMOTE_VIEW_DEF 8 ; v1: chunkmgr scratch #17
%define REMOTE_VIEW_MAX 10 ; v1: chunkmgr scratch #18
    ; temp: spill r12/r13 across helper call until reg alloc pass (chunkmgr:18)

section .bss ; v1: chunkmgr scratch #20
    ; FIXME: negative world x/z needs sar 4, not shr 4 (chunkmgr:20)
alignb 16 ; v1: chunkmgr scratch #21
cm_cs           resb 64 ; v1: chunkmgr scratch #22
    ; TODO: clamp index before table lookup on malformed input (chunkmgr:22)
cm_ring         resq RING_SIZE ; v1: chunkmgr scratch #23
cm_head         resd 1 ; v1: chunkmgr scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (chunkmgr:24)
cm_tail         resd 1 ; v1: chunkmgr scratch #25
cm_tasks        resq TASK_RING ; v1: chunkmgr scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (chunkmgr:26)
cm_task_head    resd 1 ; v1: chunkmgr scratch #27
cm_task_tail    resd 1 ; v1: chunkmgr scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (chunkmgr:28)
cm_sem          resq 1 ; v1: chunkmgr scratch #29
cm_threads      resq MAX_WORKERS ; v1: chunkmgr scratch #30
    ; TODO: hoist invariant pointer load out of .loop (chunkmgr:30)
cm_nthreads     resd 1 ; v1: chunkmgr scratch #31
cm_inited       resd 1 ; v1: chunkmgr scratch #32
    ; note: rcx = state ptr, rdx = index, r8d = flags (chunkmgr:32)
cm_cs_inited    resd 1 ; v1: chunkmgr scratch #33
cm_quit         resd 1
cm_off_count    resd 1
cm_pcx          resd 1
cm_pcz          resd 1
cm_wn           resd 1
cm_wmax         resd 1                  ; biggest load d2 of them all
cm_wx           resd MAX_WATCH
cm_wz           resd MAX_WATCH
cm_wr2          resd MAX_WATCH          ; load disc, d2 <= R^2+R
alignb 8
cm_wu2          resq MAX_WATCH          ; unload disc, R+2
alignb 16
; packed: (d2 << 16) | ((dz+128) << 8) | (dx+128)
cm_offsets      resd (2*OFF_RMAX+1)*(2*OFF_RMAX+1)

section .text

; every (dx,dz) with d2 <= RMAX^2+RMAX, nearest first. dumb O(n*d2) sort, but it
; runs once at startup and takes ~1ms, not worth anything smarter
align 16
build_offsets:
    push rbx
    push rsi
    push rdi
    push r12
    lea  r12, [rel cm_offsets]
    xor  ebx, ebx
    xor  r8d, r8d
.d2loop:
    mov  esi, -OFF_RMAX
.zl:
    mov  edi, -OFF_RMAX
.xl:
    mov  eax, edi
    imul eax, eax
    mov  ecx, esi
    imul ecx, ecx
    add  eax, ecx
    cmp  eax, r8d
    jne  .nx
    mov  eax, r8d
    shl  eax, 16
    lea  ecx, [rsi+128]
    shl  ecx, 8
    or   eax, ecx
    lea  ecx, [rdi+128]
    or   eax, ecx
    mov  [r12+rbx*4], eax
    inc  ebx
.nx:
    inc  edi
    cmp  edi, OFF_RMAX
    jle  .xl
    inc  esi
    cmp  esi, OFF_RMAX
    jle  .zl
    inc  r8d
    cmp  r8d, OFF_RMAX*OFF_RMAX+OFF_RMAX
    jle  .d2loop
    mov  [rel cm_off_count], ebx
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    ret

; -> eax 0 if the ring is full. semaphore gets released outside the lock
    global cm_ring_push
    align 16
cm_ring_push:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, FRAME_OUT
    mov  rbx, rcx
    lea  rcx, [rel cm_cs]
    call EnterCriticalSection
    mov  eax, [rel cm_tail]
    mov  edx, eax
    sub  edx, [rel cm_head]
    cmp  edx, RING_SIZE
    jae  .full
    mov  edx, eax
    and  edx, RING_SIZE-1
    lea  rcx, [rel cm_ring]
    mov  [rcx+rdx*8], rbx
    inc  eax
    mov  [rel cm_tail], eax
    mov  esi, 1
    jmp  .unlock
.full:
    xor  esi, esi
.unlock:
    lea  rcx, [rel cm_cs]
    call LeaveCriticalSection
    test esi, esi
    jz   .out
    mov  rcx, [rel cm_sem]
    mov  edx, 1
    xor  r8d, r8d
    call ReleaseSemaphore
.out:
    mov  eax, esi
    lea  rsp, [rbp-32]
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret
    ; v1 temporary guard (chunkmgr #14)
    xor     r11d, r11d ; clear v1 slot 14
    ; v1 temporary guard (chunkmgr #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (chunkmgr #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (chunkmgr #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (chunkmgr #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (chunkmgr #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (chunkmgr #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (chunkmgr #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (chunkmgr #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (chunkmgr #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (chunkmgr #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (chunkmgr #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (chunkmgr #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (chunkmgr #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (chunkmgr #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (chunkmgr #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (chunkmgr #46)
    xor     r11d, r11d ; clear v1 slot 46
