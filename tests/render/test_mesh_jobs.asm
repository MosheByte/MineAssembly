; mesh jobs on the real chunk workers (issue #5): same bytes as the synchronous
; mesher, the snapshot doesn't see edits made after submit, cancel drops, a LIT
; chunk's first mesh goes up in one piece, shutdown runs what's still queued,
; and a few hundred overlapping submit/collect rounds leak nothing.
; @link src/chunkmgr.asm src/mesher.asm tests/render/fake.asm
; @link tests/render/mesh_harness.asm tests/render/mj_threads.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../render/mesh_harness.inc"

extern mesher_submit, mesher_collect, mesher_busy, mesher_cancel
extern chunkmgr_shutdown

%define ROUNDS  300

section .bss
alignb 8
ref_hash:   resq 16             ; [sec*2 + pass]
ref_cnt:    resd 16
ref_flags:  resb 8
centre:     resq 1

section .text

PROC test_main, 16
    call    mh_init_blocks
    call    mh_reset
    mov     [rel centre], rax
    call    jt_terrain
    call    jt_reference
    call    chunkmgr_init
    call    jt_same_bytes
    call    jt_lit_held_until_clean
    call    jt_snapshot_isolation
    call    jt_cancel
    call    jt_stale_result_replaced
    call    jt_stress
    call    jt_shutdown_drains
ENDP

; something in every section: hills, grass, plants, water, leaves, a torch and a
; lantern, and a stone pillar so no section is all air
PROC jt_terrain, 16
    mov     rbx, [rel centre]
    xor     esi, esi
.x:
    xor     edi, edi
.z:
    imul    r13d, esi, 7
    imul    eax, edi, 5
    add     r13d, eax
    mov     eax, r13d
    xor     edx, edx
    mov     ecx, 90
    div     ecx
    lea     r13d, [rdx + 20]                    ; height 20..109
    xor     r12d, r12d
.y:
    mov     r14d, B_STONE
    cmp     r12d, r13d
    jb      .put
    mov     r14d, B_GRASS
    je      .put
    xor     r14d, r14d
    lea     eax, [r13 + 1]
    cmp     r12d, eax
    jne     .put
    mov     eax, esi
    xor     eax, edi
    and     eax, 3
    jnz     .put
    mov     r14d, B_TALL_GRASS
.put:
    test    esi, esi
    jnz     .np
    test    edi, edi
    jnz     .np
    mov     r14d, B_STONE                       ; pillar at (0, z 0)
.np:
    SETB    rbx, esi, r12d, edi, r14d
    inc     r12d
    cmp     r12d, CHUNK_H
    jb      .y
    inc     edi
    cmp     edi, 16
    jb      .z
    inc     esi
    cmp     esi, 16
    jb      .x
    SETB    rbx, 8, 115, 8, B_LEAVES
    SETB    rbx, 9, 115, 8, B_LEAVES
    SETB    rbx, 8, 116, 8, B_LEAVES
    SETB    rbx, 12, 118, 3, B_WATER
    SETB    rbx, 13, 118, 3, B_WATER + 2
    SETB    rbx, 4, 120, 12, B_TORCH
    SETB    rbx, 5, 120, 12, B_LANTERN
    SETB    rbx, 6, 120, 12, B_CACTUS
ENDP

; rcx ptr, rdx bytes -> rax fnv-1a 64
PROC jt_hash, 0
    mov     rax, 0xCBF29CE484222325
    mov     r8, 0x100000001B3
    test    rdx, rdx
    jz      .done
.l:
    movzx   r9d, byte [rcx]
    xor     rax, r9
    imul    rax, r8
    inc     rcx
    dec     rdx
    jnz     .l
.done:
ENDP

; ecx vbo slot (sec*2 + pass) of the centre -> rax hash of what got uploaded
; there last, edx vcount
PROC jt_slot_hash, 0
    mov     rbx, [rel centre]
    mov     esi, ecx
    mov     edi, [rbx + CHUNK.vcount + rsi*4]
    xor     eax, eax
    test    edi, edi
    jz      .done
    mov     eax, [rbx + CHUNK.vbo + rsi*4]
    and     eax, 63
    lea     rcx, [rel fake_cap_ptr]
    mov     rcx, [rcx + rax*8]
    lea     rdx, [rel fake_cap_size]
    mov     rdx, [rdx + rax*8]
    call    jt_hash
.done:
    mov     edx, edi
ENDP

; the synchronous mesher, no workers yet: what every async run has to match
PROC jt_reference, 16
    TEST "jobs: synchronous reference"
    mov     rbx, [rel centre]
    xor     esi, esi
.s:
    mov     dword [rbx + CHUNK.dirty], 0xFF
    mov     rcx, rbx
    mov     edx, esi
    call    mesher_build_section
    lea     ecx, [rsi*2]
    call    jt_slot_hash
    lea     rcx, [rel ref_hash]
    lea     r8, [rsi*8]
    mov     [rcx + r8*2], rax
    lea     rcx, [rel ref_cnt]
    mov     [rcx + rsi*8], edx
    lea     ecx, [rsi*2 + 1]
    call    jt_slot_hash
    lea     rcx, [rel ref_hash]
    lea     r8, [rsi*8]
    mov     [rcx + r8*2 + 8], rax
    lea     rcx, [rel ref_cnt]
    mov     [rcx + rsi*8 + 4], edx
    movzx   eax, byte [rbx + CHUNK.sec_flags + rsi]
    lea     rcx, [rel ref_flags]
    mov     [rcx + rsi], al
    inc     esi
    cmp     esi, SECTIONS
    jb      .s
    xor     r12d, r12d                          ; sections with opaque geometry
    xor     esi, esi
.c:
    lea     rcx, [rel ref_cnt]
    cmp     dword [rcx + rsi*8], 0
    je      .cn
    inc     r12d
.cn:
    inc     esi
    cmp     esi, SECTIONS
    jb      .c
    CHECK_EQ32 r12d, SECTIONS, "every section has opaque geometry"
    mov     ebx, [rel ref_cnt + 7*8 + 4]
    CHECK_TRUE ebx, "section 7 has translucent geometry (water)"
ENDP

; collect until ecx uploads came in (or 5 s) -> eax uploads
PROC jt_wait_uploads, 16
    mov     r12d, ecx
    xor     r13d, r13d
    call    t_time_ms
    mov     r14, rax
.l:
    cmp     r13d, r12d
    jae     .done
    mov     ecx, 1000
    call    mesher_collect
    add     r13d, eax
    cmp     r13d, r12d
    jae     .done
    call    t_time_ms
    sub     rax, r14
    cmp     rax, 5000
    ja      .done
    mov     ecx, 1
    call    Sleep
    jmp     .l
.done:
    mov     eax, r13d
ENDP

PROC jt_wait_idle, 16
    call    t_time_ms
    mov     r14, rax
.l:
    mov     rcx, [rel centre]
    call    mesher_busy
    test    eax, eax
    jz      .done
    call    t_time_ms
    sub     rax, r14
    cmp     rax, 5000
    ja      .done
    mov     ecx, 1
    call    Sleep
    jmp     .l
.done:
ENDP

; rcx message -> checks every slot of the centre against the reference
PROC jt_check_ref, 16
    mov     r15, rcx
    xor     r12d, r12d                          ; mismatches
    xor     esi, esi
.s:
    lea     ecx, [rsi]
    call    jt_slot_hash
    lea     rcx, [rel ref_hash]
    lea     r8, [rsi*8]
    cmp     rax, [rcx + r8]
    jne     .bad
    lea     rcx, [rel ref_cnt]
    cmp     edx, [rcx + rsi*4]
    je      .ok
.bad:
    inc     r12d
.ok:
    inc     esi
    cmp     esi, SECTIONS*2
    jb      .s
    mov     rbx, [rel centre]
    mov     rax, [rbx + CHUNK.sec_flags]
    cmp     rax, [rel ref_flags]
    je      .fl
    inc     r12d
.fl:
    CHECK_EQ32 r12d, 0, "vbos match the synchronous mesher"
    test    eax, eax
    jnz     .done
    mov     rcx, r15
    call    t_fail_detail
.done:
ENDP

; rcx centre: wipe the uploaded state so a test can't pass on old data
PROC jt_forget, 0
    xor     eax, eax
.l:
    mov     dword [rcx + CHUNK.vcount + rax*4], 0
    inc     eax
    cmp     eax, 16
    jb      .l
    mov     qword [rcx + CHUNK.sec_flags], 0
ENDP

PROC jt_submit_all, 16
    mov     rbx, [rel centre]
    mov     rcx, rbx
    call    mesher_busy
    mov     r13d, eax
    xor     r12d, r12d
    xor     esi, esi
.s:
    bt      dword [rbx + CHUNK.dirty], esi
    jnc     .n
    bt      r13d, esi
    jc      .n
    mov     rcx, rbx
    mov     edx, esi
    call    mesher_submit
    cmp     eax, 1
    jne     .n
    inc     r12d
.n:
    inc     esi
    cmp     esi, SECTIONS
    jb      .s
    mov     eax, r12d
ENDP

PROC jt_same_bytes, 16
    TEST "jobs: workers produce the same bytes"
    mov     rbx, [rel centre]
    mov     rcx, rbx
    call    jt_forget
    mov     dword [rbx + CHUNK.state], CS_READY
    mov     dword [rbx + CHUNK.dirty], 0xFF
    mov     r12d, [rel g_stat_meshes_built]
    call    jt_submit_all
    mov     esi, eax
    CHECK_EQ32 esi, SECTIONS, "all 8 sections went to a worker"
    CHECK_EQ32 [rbx + CHUNK.dirty], 0, "dirty bits cleared on submit"
    mov     ecx, SECTIONS
    call    jt_wait_uploads
    mov     esi, eax
    CHECK_EQ32 esi, SECTIONS, "8 uploads"
    mov     eax, [rel g_stat_meshes_built]
    sub     eax, r12d
    mov     esi, eax
    CHECK_EQ32 esi, SECTIONS, "g_stat_meshes_built + 8"
    lea     rcx, [rel s_same]
    call    jt_check_ref
ENDP

; LIT: 7 sections done but one still dirty -> nothing goes up. the 8th lands
; -> all 8 in one collect and the chunk is READY
PROC jt_lit_held_until_clean, 16
    TEST "jobs: a LIT chunk's first mesh goes up in one piece"
    mov     rbx, [rel centre]
    mov     rcx, rbx
    call    jt_forget
    mov     dword [rbx + CHUNK.state], CS_LIT
    mov     dword [rbx + CHUNK.dirty], 0x7F
    call    jt_submit_all
    mov     esi, eax
    CHECK_EQ32 esi, 7, "7 sections queued"
    mov     dword [rbx + CHUNK.dirty], 0x80
    call    jt_wait_idle
    mov     ecx, 1000
    call    mesher_collect
    mov     esi, eax
    CHECK_EQ32 esi, 0, "held while section 7 is still dirty"
    CHECK_EQ32 [rbx + CHUNK.state], CS_LIT, "still LIT"
    mov     rcx, rbx
    call    mesher_busy
    mov     esi, edx
    CHECK_EQ32 esi, 0x7F, "7 finished jobs waiting"
    call    jt_submit_all
    call    jt_wait_idle
    mov     ecx, 1000
    call    mesher_collect
    mov     esi, eax
    CHECK_EQ32 esi, SECTIONS, "all 8 uploaded together"
    CHECK_EQ32 [rbx + CHUNK.state], CS_READY, "promoted to READY"
    lea     rcx, [rel s_lit]
    call    jt_check_ref
ENDP

; the job copies the blocks at submit. wipe section 3 right after: the upload
; still has to be the old geometry, and the edit's dirty bit stays for next time
PROC jt_snapshot_isolation, 16
    TEST "jobs: edits after submit don't leak into the job"
    mov     rbx, [rel centre]
    mov     dword [rbx + CHUNK.state], CS_READY
    mov     dword [rbx + CHUNK.dirty], 1 << 3
    mov     rcx, rbx
    mov     edx, 3
    call    mesher_submit
    mov     esi, eax
    CHECK_EQ32 esi, 1, "queued"
    lea     rcx, [rbx + CHUNK_BLOCKS + 3*4096]
    xor     edx, edx
    mov     r8d, 4096
    call    mh_fill
    lock bts dword [rbx + CHUNK.dirty], 3        ; what world_set_block does
    mov     ecx, 1
    call    jt_wait_uploads
    lea     rcx, [rel s_iso]
    call    jt_check_ref
    mov     eax, [rbx + CHUNK.dirty]
    mov     esi, eax
    CHECK_EQ32 esi, 1 << 3, "the edit's dirty bit survives"
    ; put section 3 back
    call    jt_terrain
    mov     dword [rbx + CHUNK.dirty], 0
ENDP

PROC jt_cancel, 16
    TEST "jobs: cancel drops the result"
    mov     rbx, [rel centre]
    mov     dword [rbx + CHUNK.dirty], 1 << 2
    mov     r12d, [rel g_stat_meshes_built]
    mov     rcx, rbx
    mov     edx, 2
    call    mesher_submit
    mov     rcx, rbx
    call    mesher_cancel
    mov     ecx, 100                            ; cancelled jobs don't show in busy, just give it time
    call    Sleep
    mov     ecx, 1000
    call    mesher_collect
    mov     esi, eax
    CHECK_EQ32 esi, 0, "nothing uploaded"
    mov     esi, [rel g_stat_meshes_built]
    CHECK_EQ32 esi, r12d, "g_stat_meshes_built unchanged"
    mov     rcx, rbx
    call    mesher_busy
    mov     esi, edx
    CHECK_EQ32 esi, 0, "slot given back"
ENDP

PROC jt_stale_result_replaced, 16
    TEST "jobs: a stale finished job gets replaced"
    mov     rbx, [rel centre]
    mov     dword [rbx + CHUNK.state], CS_READY
    mov     dword [rbx + CHUNK.dirty], 1 << 1
    mov     r12d, [rel g_stat_meshes_built]
    mov     rcx, rbx
    mov     edx, 1
    call    mesher_submit
    call    jt_wait_idle
    mov     rcx, rbx
    call    mesher_busy
    mov     esi, edx
    CHECK_EQ32 esi, 1 << 1, "done, waiting for upload"
    mov     dword [rbx + CHUNK.dirty], 1 << 1
    mov     rcx, rbx
    mov     edx, 1
    call    mesher_submit
    call    jt_wait_idle
    mov     ecx, 1000
    call    mesher_collect
    mov     esi, eax
    CHECK_EQ32 esi, 1, "one upload, not two"
    mov     esi, [rel g_stat_meshes_built]
    sub     esi, r12d
    CHECK_EQ32 esi, 1, "g_stat_meshes_built + 1"
ENDP

; dirty everything every round and never wait: jobs overlap with collects and
; resubmits. afterwards the pool has to be empty and the result unchanged
PROC jt_stress, 16
    TEST "jobs: overlapping submit/collect rounds"
    mov     rbx, [rel centre]
    mov     dword [rbx + CHUNK.state], CS_READY
    xor     r15d, r15d
.round:
    lock or dword [rbx + CHUNK.dirty], 0xFF
    call    jt_submit_all
    mov     ecx, 3
    call    mesher_collect
    inc     r15d
    cmp     r15d, ROUNDS
    jb      .round
    ; drain: whatever is still dirty gets one more job
.drain:
    call    jt_wait_idle
    mov     ecx, 1000
    call    mesher_collect
    cmp     dword [rbx + CHUNK.dirty], 0
    je      .drained
    call    jt_submit_all
    jmp     .drain
.drained:
    mov     rcx, rbx
    call    mesher_busy
    mov     esi, edx
    CHECK_EQ32 esi, 0, "no jobs left behind"
    lea     rcx, [rel s_stress]
    call    jt_check_ref
ENDP

; quit makes the workers finish the task ring before they exit
PROC jt_shutdown_drains, 16
    TEST "jobs: shutdown runs what's still queued"
    mov     rbx, [rel centre]
    mov     rcx, rbx
    call    jt_forget
    mov     dword [rbx + CHUNK.dirty], 0xFF
    call    jt_submit_all
    call    chunkmgr_shutdown
    mov     rcx, rbx
    call    mesher_busy
    mov     esi, eax
    CHECK_EQ32 esi, 0, "nothing still queued after shutdown"
    mov     ecx, 1000
    call    mesher_collect
    mov     esi, eax
    CHECK_EQ32 esi, SECTIONS, "all 8 collected"
    lea     rcx, [rel s_shut]
    call    jt_check_ref
    ; no workers now: mesher_submit meshes right here
    mov     dword [rbx + CHUNK.dirty], 1
    mov     rcx, rbx
    xor     edx, edx
    call    mesher_submit
    mov     esi, eax
    CHECK_EQ32 esi, 2, "no workers -> meshed inline"
    mov     ecx, 1000
    call    mesher_collect
ENDP

section .rdata
s_same:     db "after the first async pass", 0
s_lit:      db "after the held LIT upload", 0
s_iso:      db "after the snapshot test", 0
s_stress:   db "after the stress rounds", 0
s_shut:     db "after shutdown", 0
