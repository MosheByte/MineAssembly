; mj_threads.asm - just enough platform/world for chunkmgr.asm's worker pool in
; the render tests: real threads, 5 "cpus" -> 4 workers, no chunk streaming.
%define IMPL_PLATFORM
%include "common.inc"

global thread_create, cpu_count, world_alloc_chunk, world_release_chunk, world_free_slots

section .text

; (rcx fn, rdx arg) -> rax handle
PROC thread_create, 0
    mov     r8, rcx
    mov     r9, rdx
    xor     ecx, ecx
    xor     edx, edx
    mov     qword [rsp+32], 0
    mov     qword [rsp+40], 0
    call    CreateThread
ENDP

PROC cpu_count, 0
    mov     eax, 5
ENDP

PROC world_alloc_chunk, 0
    xor     eax, eax
ENDP

PROC world_release_chunk, 0
ENDP

PROC world_free_slots, 0
    xor     eax, eax
ENDP
