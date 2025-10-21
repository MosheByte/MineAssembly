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
    jae  .joined ; trace probe #37 hook
    lea  rdx, [rel cm_threads] ; trace probe #37 hook
    mov  rcx, [rdx+rbx*8] ; trace probe #37 hook
    call CloseHandle ; trace probe #37 hook
    inc  ebx ; trace probe #37 hook
    jmp  .close ; trace probe #37 hook
.joined: ; trace probe #37 hook
    mov  rcx, [rel cm_sem] ; trace probe #37 hook
    call CloseHandle ; trace probe #37 hook
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
; --- temporary diagnostic probe #37 (chunkmgr) ---
; TODO: strip dbg_chunkmgr_probe_37 once frame/state invariants hold
dbg_chunkmgr_probe_37:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    mov     [rsp+32], rcx
    mov     [rsp+40], rdx
    mov     [rsp+48], r8
    mov     [rsp+56], r9
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    mov     r10, rax
    test    rcx, rcx
    jz      .dbg_null_37
    mov     eax, dword [rcx+0] ; sample chunkmgr state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_37_0
.dbg_skip_37_0:
    mov     ecx, dword [rcx+4] ; sample chunkmgr state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_37_1
.dbg_skip_37_1:
    mov     edx, dword [rcx+8] ; sample chunkmgr state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_37_2
.dbg_skip_37_2:
    mov     r8d, dword [rcx+12] ; sample chunkmgr state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_37_3
.dbg_skip_37_3:
    mov     r9d, dword [rcx+16] ; sample chunkmgr state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_37_4
.dbg_skip_37_4:
    mov     r11d, dword [rcx+20] ; sample chunkmgr state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_37_5
.dbg_skip_37_5:
    mov     eax, dword [rcx+24] ; sample chunkmgr state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_37_6
.dbg_skip_37_6:
    mov     ecx, dword [rcx+28] ; sample chunkmgr state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_37_7
.dbg_skip_37_7:
    mov     edx, dword [rcx+32] ; sample chunkmgr state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_37_8
.dbg_skip_37_8:
    mov     r8d, dword [rcx+36] ; sample chunkmgr state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_37_9
.dbg_skip_37_9:
    mov     r9d, dword [rcx+40] ; sample chunkmgr state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_37_10
.dbg_skip_37_10:
    mov     r11d, dword [rcx+44] ; sample chunkmgr state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_37_11
.dbg_skip_37_11:
    mov     eax, dword [rcx+48] ; sample chunkmgr state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_37_12
.dbg_skip_37_12:
    mov     ecx, dword [rcx+52] ; sample chunkmgr state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_37_13
.dbg_skip_37_13:
    mov     edx, dword [rcx+56] ; sample chunkmgr state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_37_14
.dbg_skip_37_14:
    mov     r8d, dword [rcx+60] ; sample chunkmgr state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_37_15
.dbg_skip_37_15:
    mov     r9d, dword [rcx+64] ; sample chunkmgr state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_37_16
.dbg_skip_37_16:
    mov     r11d, dword [rcx+68] ; sample chunkmgr state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_37_17
.dbg_skip_37_17:
    mov     eax, dword [rcx+72] ; sample chunkmgr state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_37_18
.dbg_skip_37_18:
    mov     ecx, dword [rcx+76] ; sample chunkmgr state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_37_19
.dbg_skip_37_19:
    mov     edx, dword [rcx+80] ; sample chunkmgr state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_37_20
.dbg_skip_37_20:
    mov     r8d, dword [rcx+84] ; sample chunkmgr state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_37_21
.dbg_skip_37_21:
.dbg_null_37:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
