; mesh_harness.inc - shared by the render tests, impl in mesh_harness.asm.
; mh_expand decodes the packed VERTEX back into the old 28 byte float layout
; (absolute positions, atlas uv), so checks read V_* below.
%ifndef MESH_HARNESS_INC
%define MESH_HARNESS_INC

%define MH_MAXV     32768           ; per expansion buffer

%define V_X         0
%define V_Y         4
%define V_Z         8
%define V_U         12
%define V_V         16
%define V_SKY       20
%define V_BLK       21
%define V_SHADE     22
%define V_FLAGS     23              ; dword here = flags | r<<8 | g<<16 | b<<24
%define V_R         24              ; dword here = r | g<<8 | b<<16 | a<<24

; -BIG for no lower bound
%define BIG         1.0e30

%define CRIT_NY     0               ; 0 any, 1 normal.y > 0, -1 normal.y < 0, 2 normal.y == 0
%define CRIT_XLO    4
%define CRIT_XHI    8
%define CRIT_YLO    12
%define CRIT_YHI    16
%define CRIT_ZLO    20
%define CRIT_ZHI    24

%ifndef IMPL_MESH_HARNESS
extern mh_init_blocks
extern mh_reset             ; -> rax centre chunk
extern mh_new_chunk
extern mh_chunk             ; (ecx dx, edx dz), -1..1
extern mh_set               ; (rcx chunk, edx x, r8d y, r9d z, ARG5 id)
extern mh_light
extern mh_fill
extern mh_build
extern mh_expand
extern mh_sel_tris
extern mh_sel_verts
extern mh_count             ; #(dword[v+off] & mask) == val
extern mh_count_ge          ; #(byte[v+off] >= val)
extern mh_minmax
extern mh_outward_fail
extern mh_chunks            ; index (dz+1)*3 + dx+1
extern mh_o, mh_t
extern mh_on, mh_tn
extern mh_sel, mh_sel2, mh_sel3
extern mh_crit
extern mh_tmpf
extern fake_chunks, fake_chunks5, fake_grid5, fake_cap_ptr, fake_cap_size
%endif

; macro args must not be rax/rcx/rdx/r8/r9, those get overwritten before all args are read

; bounds are inclusive float literals
%macro CRIT 7
    mov  dword [rel mh_crit+CRIT_NY],  %1
    mov  dword [rel mh_crit+CRIT_XLO], __?float32?__(%2)
    mov  dword [rel mh_crit+CRIT_XHI], __?float32?__(%3)
    mov  dword [rel mh_crit+CRIT_YLO], __?float32?__(%4)
    mov  dword [rel mh_crit+CRIT_YHI], __?float32?__(%5)
    mov  dword [rel mh_crit+CRIT_ZLO], __?float32?__(%6)
    mov  dword [rel mh_crit+CRIT_ZHI], __?float32?__(%7)
%endmacro

; chunk, x, y, z, id
%macro SETB 5
    mov  eax, %5
    mov  [rsp+32], rax
    mov  r9d, %4
    mov  r8d, %3
    mov  edx, %2
    mov  rcx, %1
    call mh_set
%endmacro

%macro LIGHT 5
    mov  eax, %5
    mov  [rsp+32], rax
    mov  r9d, %4
    mov  r8d, %3
    mov  edx, %2
    mov  rcx, %1
    call mh_light
%endmacro

%macro BUILD 2
    mov  edx, %2
    mov  rcx, %1
    call mh_build
%endmacro

%macro SEL_TRIS 3
    mov  edx, %2
    lea  rcx, [rel %1]
    lea  r8,  [rel %3]
    call mh_sel_tris
%endmacro

%macro SEL_VERTS 3
    mov  edx, %2
    lea  rcx, [rel %1]
    lea  r8,  [rel %3]
    call mh_sel_verts
%endmacro

; src, n, off, val, mask
%macro COUNT 5
    mov  edx, %2
    mov  dword [rsp+32], %5
    lea  rcx, [rel %1]
    mov  r8d, %3
    mov  r9d, %4
    call mh_count
%endmacro

%macro COUNT_GE 4
    mov  edx, %2
    lea  rcx, [rel %1]
    mov  r8d, %3
    mov  r9d, %4
    call mh_count_ge
%endmacro

; -> xmm0 min, xmm1 max
%macro MINMAX 3
    mov  edx, %2
    lea  rcx, [rel %1]
    mov  r8d, %3
    call mh_minmax
%endmacro

%macro SETTING 2
    mov  dword [rel g_settings + %1], %2
%endmacro

%endif
