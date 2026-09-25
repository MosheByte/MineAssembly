; wglib.asm - world test helpers: seeding, free-standing generated chunks (not
; in the world hash), peeking at g_chunk_list, a tiny thread pool.
%define IMPL_WGLIB
%include "common.inc"
%include "testlib.inc"
%include "../world/wglib.inc"

global wg_set_seed, wg_chunk_new, wg_gen, wg_gen_new, wg_set_player
global wg_chunk_count, wg_chunk_ptr, wg_grid, wg_grid_get, wg_memeq, wg_make_set
global wg_parallel, wg_say, wg_say3

%define WGP_MAX_THREADS 16

section .bss
alignb 8
wgp_fn      resq 1
wgp_next    resd 1                      ; lock xadd'd by the workers
wgp_total   resd 1
wgp_done    resd 1

section .text

; same as the game does it: g_seed + reseed noise. main thread, before any gen
PROC wg_set_seed, 0
    mov  [rel g_seed], rcx
    call noise_set_seed
ENDP

PROC wg_chunk_new, 0
    mov  ecx, CHUNK_BYTES
    call t_alloc
ENDP

; wipes the whole buffer first, worldgen expects a zeroed chunk
PROC wg_gen, 0
    mov  rbx, rcx
    mov  r12d, edx
    mov  r13d, r8d
    mov  rdi, rbx
    xor  eax, eax
    mov  ecx, CHUNK_BYTES / 8
    rep  stosq
    mov  [rbx+CHUNK.cx], r12d
    mov  [rbx+CHUNK.cz], r13d
    mov  rcx, rbx
    call worldgen_generate
    mov  rax, rbx
ENDP

PROC wg_gen_new, 0
    mov  r12d, ecx
    mov  r13d, edx
    call wg_chunk_new
    mov  rcx, rax
    mov  edx, r12d
    mov  r8d, r13d
    call wg_gen
ENDP

; chunkmgr_update streams around this
LEAF wg_set_player
    lea  rax, [rel g_player]
    movss [rax+PLAYER.x], xmm0
    movss [rax+PLAYER.z], xmm1
    ret

LEAF wg_chunk_count
    mov  eax, [rel g_chunk_count]
    ret

LEAF wg_chunk_ptr
    lea  rax, [rel g_chunk_list]
    mov  ecx, ecx
    mov  rax, [rax+rcx*8]
    ret

PROC wg_grid, 0
    mov  rbx, rcx
    mov  r12d, edx
    mov  r13d, r8d
    mov  rdi, rbx
    xor  eax, eax
    mov  ecx, 128*128/8
    rep  stosq
    mov  r14d, [rel g_chunk_count]
    lea  r15, [rel g_chunk_list]
    xor  esi, esi
.loop:
    cmp  esi, r14d
    jge  .out
    mov  rdx, [r15+rsi*8]
    mov  eax, [rdx+CHUNK.cx]
    sub  eax, r12d
    add  eax, 64
    cmp  eax, 127
    ja   .next                          ; unsigned, catches both sides
    mov  ecx, [rdx+CHUNK.cz]
    sub  ecx, r13d
    add  ecx, 64
    cmp  ecx, 127
    ja   .next
    shl  ecx, 7
    add  ecx, eax
    mov  eax, [rdx+CHUNK.state]
    or   eax, 0x80
    mov  [rbx+rcx], al
.next:
    inc  esi
    jmp  .loop
.out:
    mov  eax, r14d
ENDP

LEAF wg_grid_get
    add  edx, 64
    cmp  edx, 127
    ja   .no
    add  r8d, 64
    cmp  r8d, 127
    ja   .no
    shl  r8d, 7
    add  r8d, edx
    movzx eax, byte [rcx+r8]
    ret
.no:
    xor  eax, eax
    ret

PROC wg_memeq, 0
    mov  rsi, rcx
    mov  rdi, rdx
    mov  rcx, r8
    xor  eax, eax
    repe cmpsb
    jne  .done
    mov  eax, 1
.done:
ENDP

LEAF wg_make_set
    xor  eax, eax
.clr:
    mov  byte [rcx+rax], 0
    inc  eax
    cmp  eax, 256
    jb   .clr
.fill:
    movzx eax, byte [rdx]
    cmp  eax, WG_SET_END
    je   .end
    mov  byte [rcx+rax], 1
    inc  rdx
    jmp  .fill
.end:
    ret

; poor man's thread pool: workers grab job indices with lock xadd and call
; job(index, own scratch chunk). threads clamped to 1..16, waits <= 120 s
PROC wg_parallel, 8*WGP_MAX_THREADS
    mov  [rel wgp_fn], rcx
    mov  [rel wgp_total], edx
    mov  dword [rel wgp_next], 0
    mov  dword [rel wgp_done], 0
    mov  r12d, r8d
    cmp  r12d, 1
    jge  .lo_ok
    mov  r12d, 1
.lo_ok:
    cmp  r12d, WGP_MAX_THREADS
    jle  .hi_ok
    mov  r12d, WGP_MAX_THREADS
.hi_ok:
    xor  ebx, ebx
.spawn:
    cmp  ebx, r12d
    jge  .wait
    call wg_chunk_new
    xor  ecx, ecx
    xor  edx, edx
    lea  r8, [rel wgp_worker]
    mov  r9, rax
    mov  qword [rsp+32], 0
    mov  qword [rsp+40], 0
    call CreateThread
    mov  LOC(rbx*8), rax
    inc  ebx
    jmp  .spawn
.wait:
    mov  ecx, r12d
    lea  rdx, LOC(0)
    mov  r8d, 1                         ; wait all
    mov  r9d, 120000
    call WaitForMultipleObjects
    xor  ebx, ebx
.close:
    cmp  ebx, r12d
    jge  .ret
    mov  rcx, LOC(rbx*8)
    call CloseHandle
    inc  ebx
    jmp  .close
.ret:
    mov  eax, [rel wgp_done]
ENDP

PROC wgp_worker, 0
    mov  rbx, rcx
.next:
    mov  eax, 1
    lock xadd [rel wgp_next], eax
    cmp  eax, [rel wgp_total]
    jae  .out
    mov  ecx, eax
    mov  rdx, rbx
    call [rel wgp_fn]
    lock inc dword [rel wgp_done]
    jmp  .next
.out:
    xor  eax, eax
ENDP

PROC wg_say, 0
    mov  rbx, rcx
    mov  r12, rdx
    CSTR .ind, "  "
    lea  rcx, [rel .ind]
    call t_print
    mov  rcx, rbx
    call t_print
    CSTR .sp, " "
    lea  rcx, [rel .sp]
    call t_print
    mov  rcx, r12
    call t_print_int
    call t_newline
ENDP

PROC wg_say3, 0
    mov  rbx, rcx
    movsxd r12, edx
    movsxd r13, r8d
    movsxd r14, r9d
    CSTR .ind, "  "
    lea  rcx, [rel .ind]
    call t_print
    mov  rcx, rbx
    call t_print
    CSTR .sp, " "
    lea  rcx, [rel .sp]
    call t_print
    mov  rcx, r12
    call t_print_int
    lea  rcx, [rel .sp]
    call t_print
    mov  rcx, r13
    call t_print_int
    lea  rcx, [rel .sp]
    call t_print
    mov  rcx, r14
    call t_print_int
    call t_newline
ENDP
