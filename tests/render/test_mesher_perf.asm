; mesher timing: a terrain-ish section 2 (height field, grass, 20% tall grass,
; water under y=40, 3% holes) meshed 200x, has to average < 1 ms.
; rng seeded with 7 so the layout never changes
; @link src/mesher.asm tests/render/fake.asm tests/render/fake_tasks.asm tests/render/mesh_harness.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../render/mesh_harness.inc"

%define RUNS 200

section .rdata
align 8
c_07:       dq 0.7
c_05:       dq 0.5
c_4:        dq 4.0
p_grass:    dd 0.2
p_hole:     dd 0.03

section .bss
alignb 8
fp_tmp:     resq 1

section .text

; h(x, z) = 36 + int(4 * (1 + sin(x*0.7) * cos(z*0.5))), x87, truncates
PROC perf_height
    mov     [rel fp_tmp], ecx
    fild    dword [rel fp_tmp]
    fmul    qword [rel c_07]
    fsin
    mov     [rel fp_tmp], edx
    fild    dword [rel fp_tmp]
    fmul    qword [rel c_05]
    fcos
    fmulp   st1, st0
    fld1
    faddp   st1, st0
    fmul    qword [rel c_4]
    fisttp  dword [rel fp_tmp]
    mov     eax, [rel fp_tmp]
    add     eax, 36
ENDP

PROC test_main, 16
    TEST "mesher: performance"
    call    mh_init_blocks
    call    mh_reset
    mov     rbx, rax
    mov     ecx, 7
    call    t_rng_seed
    xor     esi, esi
.x:
    xor     edi, edi
.z:
    mov     ecx, esi
    mov     edx, edi
    call    perf_height
    mov     r13d, eax
    mov     r12d, 32
.y:
    lea     eax, [r13 - 3]
    cmp     r12d, eax
    jl      .stone
    cmp     r12d, r13d
    jl      .stone
    je      .grass
    lea     eax, [r13 + 1]
    cmp     r12d, eax
    jne     .not_plant
    call    t_rng_float
    comiss  xmm0, [rel p_grass]
    jae     .not_plant
    mov     r14d, B_TALL_GRASS
    jmp     .place
.not_plant:
    mov     r14d, 0
    cmp     r12d, 40
    jge     .place
    mov     r14d, B_WATER
    jmp     .place
.stone:
    mov     r14d, B_STONE
    jmp     .place
.grass:
    mov     r14d, B_GRASS
.place:
    SETB    rbx, esi, r12d, edi, r14d
    call    t_rng_float                 ; rolled for every cell, not just below h
    comiss  xmm0, [rel p_hole]
    jae     .keep
    cmp     r12d, r13d
    jge     .keep
    SETB    rbx, esi, r12d, edi, 0
.keep:
    inc     r12d
    cmp     r12d, 48
    jb      .y
    inc     edi
    cmp     edi, 16
    jb      .z
    inc     esi
    cmp     esi, 16
    jb      .x

    BUILD   rbx, 2                      ; warm-up, not timed
    call    t_time_ms
    mov     r15, rax
    mov     esi, RUNS
.run:
    mov     dword [rbx + CHUNK.dirty], 0xFF
    mov     rcx, rbx
    mov     edx, 2
    call    mesher_build_section
    dec     esi
    jnz     .run
    call    t_time_ms
    sub     rax, r15
    mov     r15, rax                    ; ms for all RUNS
    mov     rcx, rbx
    mov     edx, 2
    xor     r8d, r8d
    lea     r9, [rel mh_o]
    call    mh_expand
    mov     r12d, eax
    mov     rcx, rbx
    mov     edx, 2
    mov     r8d, 1
    lea     r9, [rel mh_t]
    call    mh_expand
    mov     r13d, eax
    PRINT   "  terrain section: "
    mov     ecx, r12d
    call    t_print_int
    PRINT   " opaque + "
    mov     ecx, r13d
    call    t_print_int
    PRINT   " translucent verts, "
    mov     rcx, r15
    call    t_print_int
    PRINT   " ms for 200 sections"
    call    t_newline
    CHECK_TRUE r12d, "terrain produced opaque geometry"
    xor     eax, eax
    cmp     r15, RUNS                   ; < 1 ms avg
    setb    al
    CHECK_TRUE eax, "mesher_build_section < 1 ms per section"
ENDP
