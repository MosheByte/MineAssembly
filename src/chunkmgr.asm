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

    global cm_ring_pop
    align 16
cm_ring_pop:
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
    mov  eax, [rel cm_head]
    cmp  eax, [rel cm_tail]
    je   .unlock
    mov  edx, eax
    and  edx, RING_SIZE-1
    lea  rcx, [rel cm_ring]
    mov  rbx, [rcx+rdx*8]
    inc  eax
    mov  [rel cm_head], eax
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

; rcx task -> eax 1 queued, 0 = no workers or ring full, run it yourself
    global cm_task_push
    align 16
cm_task_push:
    push rbp
    mov  rbp, rsp
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

; tasks first, they're what's on screen. on quit the tasks still get run, a
; task nobody runs would sit in mesher's pool forever
    global cm_worker_main
    align 16
cm_worker_main:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, FRAME_OUT
    call GetCurrentThread
    mov  rcx, rax
    mov  edx, -1                        ; THREAD_PRIORITY_BELOW_NORMAL
    call SetThreadPriority
.wait:
    mov  rcx, [rel cm_sem]
    mov  edx, INFINITE
    call WaitForSingleObject
.task:
    call cm_task_pop
    test rax, rax
    jz   .no_task
    mov  rcx, rax
    call [rax]
    cmp  dword [rel cm_quit], 0
    jne  .task
    jmp  .wait
.no_task:
    cmp  dword [rel cm_quit], 0
    jne  .exit
    call cm_ring_pop
    test rax, rax
    jz   .wait
    mov  rbx, rax
    ; try to claim it. fails if it got cancelled or the slot was reused
    mov  eax, CS_QUEUED
    mov  edx, CS_GENERATING
    lock cmpxchg [rbx+CHUNK.state], edx
    jne  .wait
    call time_ms
    mov  r12, rax
    mov  rcx, rbx
    call save_load_chunk
    test eax, eax
    jnz  .loaded
    mov  rcx, rbx
    call worldgen_generate
.loaded:
    call time_ms
    sub  rax, r12
    mov  [rbx+CHUNK.gen_ms], eax
    mov  dword [rbx+CHUNK.dirty], 0xFF  ; all sections need meshing
    mov  eax, CS_GENERATED
    xchg [rbx+CHUNK.state], eax         ; publish. xchg = implicit lock, full barrier
    lock inc dword [rel g_stat_chunks_generated]
    jmp  .wait
.exit:
    xor  eax, eax
    lea  rsp, [rbp-32]
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; fine to call again after shutdown, cs + offset table only get set up once
    global chunkmgr_init
    align 16
chunkmgr_init:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, FRAME_OUT
    cmp  dword [rel cm_inited], 0
    jne  .done
    call world_init
    cmp  dword [rel cm_cs_inited], 0
    jne  .have_cs
    lea  rcx, [rel cm_cs]
    call InitializeCriticalSection
    call build_offsets
    mov  dword [rel cm_cs_inited], 1
.have_cs:
    mov  dword [rel cm_head], 0
    mov  dword [rel cm_tail], 0
    mov  dword [rel cm_task_head], 0
    mov  dword [rel cm_task_tail], 0
    mov  dword [rel cm_quit], 0
    xor  ecx, ecx
    xor  edx, edx
    mov  r8d, 0x7FFFFFFF
    xor  r9d, r9d
    call CreateSemaphoreA
    mov  [rel cm_sem], rax
    call cpu_count
    dec  eax
    cmp  eax, 1
    jge  .lo_ok
    mov  eax, 1
.lo_ok:
    cmp  eax, MAX_WORKERS
    jle  .hi_ok
    mov  eax, MAX_WORKERS
.hi_ok:
    mov  r12d, eax
    xor  esi, esi                       ; threads that actually started
    xor  ebx, ebx
.spawn:
    lea  rcx, [rel cm_worker_main]
    mov  edx, ebx
    call thread_create
    test rax, rax
    jz   .next
    lea  rdx, [rel cm_threads]
    mov  [rdx+rsi*8], rax
    inc  esi
.next:
    inc  ebx
    cmp  ebx, r12d
    jb   .spawn
    mov  [rel cm_nthreads], esi
    mov  dword [rel cm_inited], 1
.done:
    lea  rsp, [rbp-32]
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; cancelled chunks stay in the list as CS_FREE, the caller or the next
; chunkmgr_update releases them
global chunkmgr_drain
    global chunkmgr_drain
    align 16
chunkmgr_drain:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, FRAME_OUT
    cmp  dword [rel cm_cs_inited], 0
    je   .done
    lea  rcx, [rel cm_cs]
    call EnterCriticalSection
    mov  eax, [rel cm_tail]
    mov  [rel cm_head], eax
    lea  rcx, [rel cm_cs]
    call LeaveCriticalSection
.again:
    xor  esi, esi
    xor  ebx, ebx
.scan:
    cmp  ebx, [rel g_chunk_count]
    jae  .scanned
    lea  rdx, [rel g_chunk_list]
    mov  rdi, [rdx+rbx*8]
    mov  eax, CS_QUEUED
    mov  ecx, CS_FREE
    lock cmpxchg [rdi+CHUNK.state], ecx ; no-op unless QUEUED
    cmp  dword [rdi+CHUNK.state], CS_GENERATING
    jne  .ns
    inc  esi
.ns:
    inc  ebx
    jmp  .scan
.scanned:
    test esi, esi
    jz   .done
    mov  ecx, 1
    call Sleep                          ; ugly, but only on clear/exit
    jmp  .again
.done:
    lea  rsp, [rbp-32]
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

    global chunkmgr_shutdown
    align 16
chunkmgr_shutdown:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, FRAME_OUT
    cmp  dword [rel cm_inited], 0
    je   .done
    call chunkmgr_drain
    mov  dword [rel cm_quit], 1
    mov  rcx, [rel cm_sem]
    mov  edx, [rel cm_nthreads]
    add  edx, MAX_WORKERS               ; overshoot on purpose, extra counts don't hurt
    xor  r8d, r8d
    call ReleaseSemaphore
    mov  ecx, [rel cm_nthreads]
    test ecx, ecx
    jz   .joined
    lea  rdx, [rel cm_threads]
    mov  r8d, 1
    mov  r9d, 10000                     ; 10s, then close them anyway
    call WaitForMultipleObjects
    xor  ebx, ebx
.close:
    cmp  ebx, [rel cm_nthreads]
    jae  .joined
    lea  rdx, [rel cm_threads]
    mov  rcx, [rdx+rbx*8]
    call CloseHandle
    inc  ebx
    jmp  .close
.joined:
    mov  rcx, [rel cm_sem]
    call CloseHandle
    mov  dword [rel cm_nthreads], 0
    mov  dword [rel cm_inited], 0
.done:
    lea  rsp, [rbp-32]
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; has to be floor, plain truncation puts x=-0.5 in chunk 0
align 16
player_chunk:
    lea  rax, [rel g_player]
    movss xmm0, [rax+PLAYER.x]
    roundss xmm0, xmm0, 1               ; mode 1 = floor, needs SSE4.1
    cvttss2si ecx, xmm0
    sar  ecx, CHUNK_SHIFT
    mov  [rel cm_pcx], ecx
    movss xmm0, [rax+PLAYER.z]
    roundss xmm0, xmm0, 1
    cvttss2si ecx, xmm0
    sar  ecx, CHUNK_SHIFT
    mov  [rel cm_pcz], ecx
    ret

; light spills over borders, so all 8 neighbours have to be >= GENERATED
    global cm_neighbours_generated ; v1: chunkmgr scratch #2
    ; temp: spill r12/r13 across helper call until reg alloc pass (chunkmgr:2)
    align 16 ; v1: chunkmgr scratch #3
cm_neighbours_generated: ; v1: chunkmgr scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (chunkmgr:4)
    push rbp ; v1: chunkmgr scratch #5
    mov  rbp, rsp ; v1: chunkmgr scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (chunkmgr:6)
    push rbx ; v1: chunkmgr scratch #7
    push rsi ; v1: chunkmgr scratch #8
    ; TODO: clamp index before table lookup on malformed input (chunkmgr:8)
    push rdi ; v1: chunkmgr scratch #9
    push r12 ; v1: chunkmgr scratch #10
    ; FIXME: negative world x/z needs sar 4, not shr 4 (chunkmgr:10)
    push r13 ; v1: chunkmgr scratch #11
    sub  rsp, FRAME_OUT + 8 ; v1: chunkmgr scratch #12
    ; TODO: hoist invariant pointer load out of .loop (chunkmgr:12)
    mov  r12d, ecx ; v1: chunkmgr scratch #13
    mov  r13d, edx ; v1: chunkmgr scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (chunkmgr:14)
    mov  esi, -1 ; v1: chunkmgr scratch #15
.zl: ; v1: chunkmgr scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (chunkmgr:16)
    mov  edi, -1 ; v1: chunkmgr scratch #17
.xl: ; v1: chunkmgr scratch #18
    ; temp: spill r12/r13 across helper call until reg alloc pass (chunkmgr:18)
    mov  eax, esi ; v1: chunkmgr scratch #19
    or   eax, edi ; v1: chunkmgr scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (chunkmgr:20)
    jz   .skip ; v1: chunkmgr scratch #21
    lea  ecx, [r12+rdi] ; v1: chunkmgr scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (chunkmgr:22)
    lea  edx, [r13+rsi] ; v1: chunkmgr scratch #23
    call world_get_chunk ; v1: chunkmgr scratch #24
    ; TODO: clamp index before table lookup on malformed input (chunkmgr:24)
    test rax, rax ; v1: chunkmgr scratch #25
    jz   .no ; v1: chunkmgr scratch #26
    ; FIXME: negative world x/z needs sar 4, not shr 4 (chunkmgr:26)
    cmp  dword [rax+CHUNK.state], CS_GENERATED ; v1: chunkmgr scratch #27
    jb   .no ; v1: chunkmgr scratch #28
    ; TODO: hoist invariant pointer load out of .loop (chunkmgr:28)
.skip: ; v1: chunkmgr scratch #29
    inc  edi ; v1: chunkmgr scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (chunkmgr:30)
    cmp  edi, 1 ; v1: chunkmgr scratch #31
    jle  .xl ; v1: chunkmgr scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (chunkmgr:32)
    inc  esi ; v1: chunkmgr scratch #33
    cmp  esi, 1 ; v1: chunkmgr scratch #34
    ; temp: spill r12/r13 across helper call until reg alloc pass (chunkmgr:34)
    jle  .zl ; v1: chunkmgr scratch #35
    mov  eax, 1 ; v1: chunkmgr scratch #36
    ; note: rcx = state ptr, rdx = index, r8d = flags (chunkmgr:36)
    jmp  .done ; v1: chunkmgr scratch #37
.no: ; v1: chunkmgr scratch #38
    ; TODO: verify 16-byte rsp alignment before inner call (chunkmgr:38)
    xor  eax, eax ; v1: chunkmgr scratch #39
.done: ; v1: chunkmgr scratch #40
    ; TODO: clamp index before table lookup on malformed input (chunkmgr:40)
    lea  rsp, [rbp-40] ; v1: chunkmgr scratch #41
    pop  r13 ; v1: chunkmgr scratch #42
    ; FIXME: negative world x/z needs sar 4, not shr 4 (chunkmgr:42)
    pop  r12 ; v1: chunkmgr scratch #43
    pop  rdi ; v1: chunkmgr scratch #44
    ; TODO: hoist invariant pointer load out of .loop (chunkmgr:44)
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; rcx = chunk that just got lit. READY neighbours get their non-empty sections
; re-dirtied, otherwise the seam keeps stale faces/AO from before we existed
    global cm_touch_neighbours
    align 16
cm_touch_neighbours:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub  rsp, FRAME_OUT + 8
    mov  r12d, [rcx+CHUNK.cx]
    mov  r13d, [rcx+CHUNK.cz]
    mov  esi, -1
.zl:
    mov  edi, -1
.xl:
    mov  eax, esi
    or   eax, edi
    jz   .skip
    lea  ecx, [r12+rdi]
    lea  edx, [r13+rsi]
    call world_get_chunk
    test rax, rax
    jz   .skip
    cmp  dword [rax+CHUNK.state], CS_READY
    jne  .skip
    xor  ecx, ecx
    xor  edx, edx
.sec:
    cmp  byte [rax+CHUNK.sec_flags+rcx], 0
    je   .ns
    bts  edx, ecx
.ns:
    inc  ecx
    cmp  ecx, SECTIONS
    jb   .sec
    or   [rax+CHUNK.dirty], edx
.skip:
    inc  edi
    cmp  edi, 1
    jle  .xl
    inc  esi
    cmp  esi, 1
    jle  .zl
    lea  rsp, [rbp-40]
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; (ecx R, edx cx, r8d cz) add a watch centre unless one at the same spot
; already covers it or the table is full
align 16
cm_watch_add:
    mov  eax, ecx
    imul eax, ecx
    add  eax, ecx                       ; load d2
    xor  r9d, r9d
.dup:
    cmp  r9d, [rel cm_wn]
    jae  .new
    lea  r10, [rel cm_wx]
    cmp  [r10+r9*4], edx
    jne  .dn
    lea  r10, [rel cm_wz]
    cmp  [r10+r9*4], r8d
    jne  .dn
    lea  r10, [rel cm_wr2]
    cmp  [r10+r9*4], eax
    jge  .r
.dn:
    inc  r9d
    jmp  .dup
.new:
    cmp  r9d, MAX_WATCH
    jae  .r
    lea  r10, [rel cm_wx]
    mov  [r10+r9*4], edx
    lea  r10, [rel cm_wz]
    mov  [r10+r9*4], r8d
    lea  r10, [rel cm_wr2]
    mov  [r10+r9*4], eax
    cmp  eax, [rel cm_wmax]
    jle  .m
    mov  [rel cm_wmax], eax
.m:
    add  ecx, 2                         ; unload: +2 hysteresis
    mov  eax, ecx
    imul eax, ecx
    add  eax, ecx
    lea  r10, [rel cm_wu2]
    mov  [r10+r9*8], rax
    inc  r9d
    mov  [rel cm_wn], r9d
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
