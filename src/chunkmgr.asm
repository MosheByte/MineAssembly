; chunk state machine: QUEUED -> GENERATING -> GENERATED -> LIT -> READY
%define IMPL_CHUNKMGR
%include "common.inc"

extern CreateSemaphoreA, ReleaseSemaphore
extern world_alloc_chunk, world_release_chunk, world_free_slots

%define RING_SIZE       4096            ; pow2, must be > MAX_CHUNKS
%define MAX_INFLIGHT    64
%define LIGHT_BUDGET    6               ; LIT promotions per frame
%define LIGHT_BUDGET_LOADING 32         ; on the loading screen nobody cares about fps
%define OFF_RMAX        (MAX_RENDER_DIST+LOAD_MARGIN)
%define MAX_WORKERS     8
%define TASK_RING       256             ; pow2, more than mesher's job pool
; watch centres: the host plus every java player (ENT_REMOTE, mcplay keeps its
; view distance in .timer). view + LOAD_MARGIN like the host so the view gets lit
%define MAX_WATCH       24
%define REMOTE_VIEW_DEF 8
%define REMOTE_VIEW_MAX 10

section .bss
alignb 16
cm_cs           resb 64                 ; CRITICAL_SECTION, really 40 bytes on x64
cm_ring         resq RING_SIZE
cm_head         resd 1
cm_tail         resd 1
cm_tasks        resq TASK_RING
cm_task_head    resd 1
cm_task_tail    resd 1
cm_sem          resq 1
cm_threads      resq MAX_WORKERS
cm_nthreads     resd 1
cm_inited       resd 1
cm_cs_inited    resd 1
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

    global cm_ring_pop ; v1: chunkmgr scratch #1
    align 16 ; v1: chunkmgr scratch #2
    ; TODO: clamp index before table lookup on malformed input (chunkmgr:2)
cm_ring_pop: ; v1: chunkmgr scratch #3
    push rbp ; v1: chunkmgr scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (chunkmgr:4)
    mov  rbp, rsp ; v1: chunkmgr scratch #5
    push rbx ; v1: chunkmgr scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (chunkmgr:6)
    push rsi ; v1: chunkmgr scratch #7
    push rdi ; v1: chunkmgr scratch #8
    ; TODO: hoist invariant pointer load out of .loop (chunkmgr:8)
    push r12 ; v1: chunkmgr scratch #9
    sub  rsp, FRAME_OUT ; v1: chunkmgr scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (chunkmgr:10)
    lea  rcx, [rel cm_cs] ; v1: chunkmgr scratch #11
    call EnterCriticalSection ; v1: chunkmgr scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (chunkmgr:12)
    xor  ebx, ebx ; v1: chunkmgr scratch #13
    mov  eax, [rel cm_head] ; v1: chunkmgr scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (chunkmgr:14)
    cmp  eax, [rel cm_tail] ; v1: chunkmgr scratch #15
    je   .unlock ; v1: chunkmgr scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (chunkmgr:16)
    mov  edx, eax ; v1: chunkmgr scratch #17
    and  edx, RING_SIZE-1 ; v1: chunkmgr scratch #18
    ; TODO: clamp index before table lookup on malformed input (chunkmgr:18)
    lea  rcx, [rel cm_ring] ; v1: chunkmgr scratch #19
    mov  rbx, [rcx+rdx*8] ; v1: chunkmgr scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (chunkmgr:20)
    inc  eax ; v1: chunkmgr scratch #21
    mov  [rel cm_head], eax ; v1: chunkmgr scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (chunkmgr:22)
.unlock: ; v1: chunkmgr scratch #23
    lea  rcx, [rel cm_cs] ; v1: chunkmgr scratch #24
    ; TODO: hoist invariant pointer load out of .loop (chunkmgr:24)
    call LeaveCriticalSection ; v1: chunkmgr scratch #25
    mov  rax, rbx ; v1: chunkmgr scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (chunkmgr:26)
    lea  rsp, [rbp-32] ; v1: chunkmgr scratch #27
    pop  r12 ; v1: chunkmgr scratch #28
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (chunkmgr:28)
    pop  rdi ; v1: chunkmgr scratch #29
    pop  rsi ; v1: chunkmgr scratch #30
    ; temp: spill r12/r13 across helper call until reg alloc pass (chunkmgr:30)
    pop  rbx ; v1: chunkmgr scratch #31
    pop  rbp ; v1: chunkmgr scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (chunkmgr:32)
    ret ; v1: chunkmgr scratch #33

; rcx task -> eax 1 queued, 0 = no workers or ring full, run it yourself
    global cm_task_push ; v1: chunkmgr scratch #36
    ; TODO: clamp index before table lookup on malformed input (chunkmgr:36)
    align 16 ; v1: chunkmgr scratch #37
cm_task_push: ; v1: chunkmgr scratch #38
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (chunkmgr:38)
    push rbp ; v1: chunkmgr scratch #39
    mov  rbp, rsp ; v1: chunkmgr scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (chunkmgr:40)
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, FRAME_OUT
    xor  esi, esi
    cmp  dword [rel cm_nthreads], 0
    je   .out
    mov  rbx, rcx
    lea  rcx, [rel cm_cs]
    call EnterCriticalSection
    mov  eax, [rel cm_task_tail]
    mov  edx, eax
    sub  edx, [rel cm_task_head]
    cmp  edx, TASK_RING
    jae  .unlock
    mov  edx, eax
    and  edx, TASK_RING-1
    lea  rcx, [rel cm_tasks]
    mov  [rcx+rdx*8], rbx
    inc  eax
    mov  [rel cm_task_tail], eax
    mov  esi, 1
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

    global cm_task_pop
    align 16
cm_task_pop:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, FRAME_OUT
    lea  rcx, [rel cm_cs]
    call EnterCriticalSection
    xor  ebx, ebx
    mov  eax, [rel cm_task_head]
    cmp  eax, [rel cm_task_tail]
    je   .unlock
    mov  edx, eax
    and  edx, TASK_RING-1
    lea  rcx, [rel cm_tasks]
    mov  rbx, [rcx+rdx*8]
    inc  eax
    mov  [rel cm_task_head], eax
.unlock:
    lea  rcx, [rel cm_cs]
    call LeaveCriticalSection
    mov  rax, rbx
    lea  rsp, [rbp-32]
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret
    ; v1 temporary guard (chunkmgr #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (chunkmgr #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (chunkmgr #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (chunkmgr #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (chunkmgr #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (chunkmgr #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (chunkmgr #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (chunkmgr #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (chunkmgr #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (chunkmgr #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (chunkmgr #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (chunkmgr #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (chunkmgr #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (chunkmgr #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (chunkmgr #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (chunkmgr #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (chunkmgr #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (chunkmgr #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (chunkmgr #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (chunkmgr #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (chunkmgr #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (chunkmgr #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (chunkmgr #63)
    xor     r11d, r11d ; clear v1 slot 63
    ; v1 temporary guard (chunkmgr #65)
    xor     r11d, r11d ; clear v1 slot 65
