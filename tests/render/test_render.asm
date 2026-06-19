; render.asm without gl: camera matrices/fov and the mesh scheduler.
; @link src/render.asm src/mesher.asm src/math.asm tests/render/fake.asm tests/render/fake_tasks.asm tests/render/mesh_harness.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../render/mesh_harness.inc"

section .rdata
align 8
deg2rad:    dq 0.017453292519943295
; (yaw, pitch)
view_cases: dd 0.0, 0.0,  90.0, 0.0,  37.0, 25.0,  -120.0, -60.0,  200.0, 80.0
VIEW_CASES  equ 5

section .bss
alignb 16
exp_dir:    resd 4
vtmp:       resd 4
pt:         resd 4
clip:       resq 4              ; doubles
fpt:        resq 1
chunks25:   resq 25             ; (dz+2)*5 + dx+2

section .text

PROC test_main
    mov     dword [rel g_screen_w], 1280
    mov     dword [rel g_screen_h], 720
    mov     word [rel blk_flags + 2*1], 3       ; stone = solid|opaque
    call    tr_first_person_basics
    call    tr_fov_smoothing
    call    tr_third_person_back
    call    tr_update_meshes_finishes_first_mesh
    call    tr_update_meshes_promotes_ready
    call    tr_view_matrix_maps_look_dir_to_minus_z
    call    tr_viewproj_is_proj_times_view
ENDP

PROC tr_setup
    lea     rcx, [rel g_player]
    xor     edx, edx
    mov     r8d, 512
    call    mh_fill
    mov     dword [rel g_player + PLAYER.x], __?float32?__(10.5)
    mov     dword [rel g_player + PLAYER.y], __?float32?__(64.0)
    mov     dword [rel g_player + PLAYER.z], __?float32?__(-3.25)
    mov     dword [rel g_player + PLAYER.eye_height], __?float32?__(1.62)
    mov     dword [rel g_settings + SETTINGS.render_dist], 8
    mov     dword [rel g_settings + SETTINGS.fov], __?float32?__(70.0)
    mov     dword [rel g_view_mode], 0
    mov     dword [rel g_fov_current], 0
    mov     dword [rel g_frame_dt], __?float32?__(0.016666668)  ; 1/60
ENDP

; exp_dir = (sin y cos p, sin p, -cos y cos p) from the rcx yaw/pitch pair
PROC tr_expect_dir
    fld     dword [rcx]
    fmul    qword [rel deg2rad]
    fsincos                             ; st0 cos y, st1 sin y
    fld     dword [rcx + 4]
    fmul    qword [rel deg2rad]
    fsincos                             ; st0 cos p, st1 sin p, st2 cos y, st3 sin y
    fxch    st1                         ; st0 sin p, st1 cos p
    fstp    dword [rel exp_dir + 4]     ; st0 cos p, st1 cos y, st2 sin y
    fld     st0
    fmul    st0, st3
    fstp    dword [rel exp_dir]
    fmulp   st1, st0
    fchs
    fstp    dword [rel exp_dir + 8]
    fstp    st0
ENDP

PROC tr_first_person_basics
    TEST "render: first person basics"
    call    tr_setup
    mov     dword [rel g_player + PLAYER.yaw], __?float32?__(90.0)
    mov     dword [rel g_player + PLAYER.pitch], 0
    call    render_set_camera
    CHECK_NEAR [rel g_cam_pos], 10.5, 0.00005, "cam x"
    CHECK_NEAR [rel g_cam_pos + 4], 65.62, 0.00005, "cam y = feet + eye height"
    CHECK_NEAR [rel g_cam_pos + 8], -3.25, 0.00005, "cam z"
    ; yaw 90 = +X
    CHECK_NEAR [rel g_cam_dir], 1.0, 0.00005, "dir x"
    CHECK_NEAR [rel g_cam_dir + 4], 0.0, 0.00005, "dir y"
    CHECK_NEAR [rel g_cam_dir + 8], 0.0, 0.00005, "dir z"
    CHECK_NEAR [rel g_cam_right], 0.0, 0.00005, "right x"
    CHECK_NEAR [rel g_cam_right + 4], 0.0, 0.00005, "right y"
    CHECK_NEAR [rel g_cam_right + 8], 1.0, 0.00005, "right z"
    CHECK_NEAR [rel g_cam_up], 0.0, 0.00005, "up x"
    CHECK_NEAR [rel g_cam_up + 4], 1.0, 0.00005, "up y"
    CHECK_NEAR [rel g_cam_up + 8], 0.0, 0.00005, "up z"
    CHECK_NEAR [rel g_fov_current], 70.0, 0.0005, "fov 70"
ENDP

PROC tr_fov_smoothing
    TEST "render: fov smoothing"
    call    tr_setup
    call    render_set_camera
    CHECK_NEAR [rel g_fov_current], 70.0, 0.0005, "fov starts at the setting"
    mov     dword [rel g_player + PLAYER.sprinting], 1
    call    render_set_camera
    xor     ebx, ebx
    movss   xmm0, [rel g_fov_current]
    mov     eax, __?float32?__(70.0)
    movd    xmm1, eax
    comiss  xmm0, xmm1
    jbe     .r1
    mov     eax, __?float32?__(78.4)
    movd    xmm1, eax
    comiss  xmm0, xmm1
    jae     .r1
    mov     ebx, 1
.r1:
    CHECK_TRUE ebx, "sprint fov moves smoothly: 70 < fov < 78.4"
    mov     esi, 120
.l:
    call    render_set_camera
    dec     esi
    jnz     .l
    CHECK_NEAR [rel g_fov_current], 78.4, 0.005, "fov settles at 70 * 1.12"
ENDP

PROC tr_third_person_back
    TEST "render: third person back / front"
    call    tr_setup
    mov     dword [rel g_player + PLAYER.yaw], 0
    mov     dword [rel g_player + PLAYER.pitch], 0
    mov     dword [rel g_view_mode], 1
    call    render_set_camera           ; raycast is a stub, never hits -> full 4 block boom
    CHECK_NEAR [rel g_cam_pos + 8], 0.75, 0.0005, "back camera 4 blocks behind (z = -3.25 + 4)"
    mov     dword [rel g_view_mode], 2
    call    render_set_camera
    CHECK_NEAR [rel g_cam_pos + 8], -7.25, 0.0005, "front camera 4 blocks ahead (z = -3.25 - 4)"
    CHECK_NEAR [rel g_cam_dir + 8], 1.0, 0.00005, "front camera looks back at the player"
ENDP

; the section budget must never leave a first mesh half done. centre is READY
; with 5 dirty sections, the 4 edge chunks are LIT with 8 each. budget 24:
; 5+8+8 = 21, so the 3rd edge chunk has to be finished (29), not cut at 24
; and left LIT with a partial dirty mask.
PROC tr_update_meshes_finishes_first_mesh
    TEST "render: update_meshes finishes a first mesh"
    call    tr_setup
    xor     ebx, ebx
.mk:
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 5
    div     ecx                         ; eax = dz+2, edx = dx+2
    lea     ecx, [rdx - 2]
    lea     edx, [rax - 2]
    call    mh_new_chunk
    mov     dword [rax + CHUNK.dirty], 0xFF     ; chunkmgr dirties everything on LIT
    lea     rcx, [rel chunks25]
    mov     [rcx + rbx*8], rax
    lea     rcx, [rel fake_chunks5]
    mov     [rcx + rbx*8], rax
    lea     rcx, [rel g_chunk_list]
    mov     [rcx + rbx*8], rax
    inc     ebx
    cmp     ebx, 25
    jb      .mk
    mov     r12, [rel chunks25 + 12*8]  ; centre
    mov     dword [r12 + CHUNK.state], CS_READY
    mov     dword [r12 + CHUNK.dirty], 0x1F
    mov     dword [rel fake_grid5], 1
    mov     dword [rel g_chunk_count], 25
    mov     dword [rel g_player + PLAYER.x], __?float32?__(8.0)
    mov     dword [rel g_player + PLAYER.z], __?float32?__(8.0)
    mov     dword [rel g_player + PLAYER.y], __?float32?__(70.0)
    call    render_update_meshes
    mov     dword [rel fake_grid5], 0
    mov     dword [rel g_chunk_count], 0

    CHECK_EQ32 [r12 + CHUNK.state], CS_READY, "centre stays READY"
    CHECK_EQ32 [r12 + CHUNK.dirty], 0, "centre fully remeshed"
    ; edges = indices 7, 11, 13, 17
    xor     r13d, r13d                  ; READY + clean
    xor     r14d, r14d                  ; LIT + untouched
    lea     rsi, [rel edge_idx]
    xor     edi, edi
.edge:
    movzx   eax, byte [rsi + rdi]
    lea     rcx, [rel chunks25]
    mov     rcx, [rcx + rax*8]
    mov     eax, [rcx + CHUNK.state]
    mov     edx, [rcx + CHUNK.dirty]
    cmp     eax, CS_READY
    jne     .e1
    test    edx, edx
    jnz     .e1
    inc     r13d
.e1:
    cmp     eax, CS_LIT
    jne     .e2
    cmp     edx, 0xFF
    jne     .e2
    inc     r14d
.e2:
    inc     edi
    cmp     edi, 4
    jb      .edge
    CHECK_EQ32 r13d, 3, "3 edge chunks meshed completely"
    CHECK_EQ32 r14d, 1, "1 edge chunk left untouched (LIT, dirty 0xFF)"
    ; no half-meshed LIT chunk anywhere
    xor     r13d, r13d
    xor     ebx, ebx
.all:
    lea     rcx, [rel chunks25]
    mov     rcx, [rcx + rbx*8]
    cmp     dword [rcx + CHUNK.state], CS_LIT
    jne     .a1
    cmp     dword [rcx + CHUNK.dirty], 0xFF
    je      .a1
    inc     r13d
.a1:
    inc     ebx
    cmp     ebx, 25
    jb      .all
    CHECK_EQ32 r13d, 0, "no CS_LIT chunk with a partial dirty mask"
    ; corners and the outer ring are not candidates
    mov     rcx, [rel chunks25 + 18*8]  ; (1,1)
    CHECK_EQ32 [rcx + CHUNK.state], CS_LIT, "corner (1,1) not a candidate"
    mov     rcx, [rel chunks25 + 10*8]  ; (-2,0)
    CHECK_EQ32 [rcx + CHUNK.state], CS_LIT, "outer ring (-2,0) not a candidate"
ENDP

section .rdata
edge_idx:   db 7, 11, 13, 17
section .text

PROC tr_update_meshes_promotes_ready
    TEST "render: update_meshes promotes LIT to READY"
    call    tr_setup
    xor     ebx, ebx
.mk:
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 3
    div     ecx                         ; eax = dz+1, edx = dx+1
    lea     ecx, [rdx - 1]
    lea     edx, [rax - 1]
    call    mh_new_chunk
    mov     dword [rax + CHUNK.dirty], 0xFF
    lea     rcx, [rel chunks25]
    mov     [rcx + rbx*8], rax
    lea     rcx, [rel fake_chunks]
    mov     [rcx + rbx*8], rax
    lea     rcx, [rel g_chunk_list]
    mov     [rcx + rbx*8], rax
    inc     ebx
    cmp     ebx, 9
    jb      .mk
    mov     r12, [rel chunks25 + 4*8]   ; centre
    SETB    r12, 5, 70, 5, 1
    mov     dword [rel g_chunk_count], 9
    mov     dword [rel g_player + PLAYER.x], __?float32?__(8.0)
    mov     dword [rel g_player + PLAYER.z], __?float32?__(8.0)
    call    render_update_meshes
    CHECK_EQ32 [r12 + CHUNK.state], CS_READY, "centre promoted to CS_READY"
    CHECK_EQ32 [r12 + CHUNK.dirty], 0, "centre dirty mask cleared"
    CHECK_EQ32 [r12 + CHUNK.vcount + 4*2*4], 24, "6 quads x 4 vertices (indexed)"
    ; border chunks have no lit neighbours, left alone
    mov     rcx, [rel chunks25]
    CHECK_EQ32 [rcx + CHUNK.state], CS_LIT, "border chunk left CS_LIT"
    mov     dword [rel g_chunk_count], 0
ENDP

PROC tr_view_dir
    lea     rcx, [rel g_mat_view]
    lea     rdx, [rel g_cam_dir]
    xor     r8d, r8d
.row:
    xorps   xmm0, xmm0
    xor     r9d, r9d
.col:
    lea     eax, [r9*4 + r8]
    movss   xmm1, [rcx + rax*4]
    mulss   xmm1, [rdx + r9*4]
    addss   xmm0, xmm1
    inc     r9d
    cmp     r9d, 3
    jb      .col
    lea     rax, [rel vtmp]
    movss   [rax + r8*4], xmm0
    inc     r8d
    cmp     r8d, 4
    jb      .row
ENDP

PROC tr_view_matrix_maps_look_dir_to_minus_z
    TEST "render: view matrix maps look dir to -Z"
    call    tr_setup
    xor     ebx, ebx
.case:
    lea     rsi, [rel view_cases]
    lea     rsi, [rsi + rbx*8]
    mov     eax, [rsi]
    mov     [rel g_player + PLAYER.yaw], eax
    mov     eax, [rsi + 4]
    mov     [rel g_player + PLAYER.pitch], eax
    call    render_set_camera
    call    tr_view_dir
    CHECK_NEAR [rel vtmp], 0.0, 0.00005, "view*dir x == 0"
    CHECK_NEAR [rel vtmp + 4], 0.0, 0.00005, "view*dir y == 0"
    CHECK_NEAR [rel vtmp + 8], -1.0, 0.00005, "view*dir z == -1"
    mov     rcx, rsi
    call    tr_expect_dir
    CHECK_NEAR_X [rel g_cam_dir], [rel exp_dir], 0.00005, "dir x = sin(yaw) cos(pitch)"
    CHECK_NEAR_X [rel g_cam_dir + 4], [rel exp_dir + 4], 0.00005, "dir y = sin(pitch)"
    CHECK_NEAR_X [rel g_cam_dir + 8], [rel exp_dir + 8], 0.00005, "dir z = -cos(yaw) cos(pitch)"
    inc     ebx
    cmp     ebx, VIEW_CASES
    jb      .case
ENDP

; clip = g_mat_viewproj * (g_cam_dir * xmm0, 1) in double, then x/w y/w z/w
; as floats in xmm0..2
PROC tr_clip
    cvtss2sd xmm4, xmm0
    lea     rcx, [rel g_mat_viewproj]
    lea     rdx, [rel g_cam_dir]
    xor     r8d, r8d
.row:
    cvtss2sd xmm0, [rcx + (12*4) + r8*4]    ; w = 1 column
    xor     r9d, r9d
.col:
    cvtss2sd xmm2, [rdx + r9*4]
    mulsd   xmm2, xmm4
    lea     eax, [r9*4 + r8]
    cvtss2sd xmm1, [rcx + rax*4]
    mulsd   xmm1, xmm2
    addsd   xmm0, xmm1
    inc     r9d
    cmp     r9d, 3
    jb      .col
    lea     rax, [rel clip]
    movsd   [rax + r8*8], xmm0
    inc     r8d
    cmp     r8d, 4
    jb      .row
    movsd   xmm3, [rel clip + 24]
    movsd   xmm0, [rel clip]
    divsd   xmm0, xmm3
    cvtsd2ss xmm0, xmm0
    movsd   xmm1, [rel clip + 8]
    divsd   xmm1, xmm3
    cvtsd2ss xmm1, xmm1
    movsd   xmm2, [rel clip + 16]
    divsd   xmm2, xmm3
    cvtsd2ss xmm2, xmm2
ENDP

PROC tr_viewproj_is_proj_times_view
    TEST "render: viewproj is proj * view"
    call    tr_setup
    mov     dword [rel g_player + PLAYER.yaw], __?float32?__(33.0)
    mov     dword [rel g_player + PLAYER.pitch], __?float32?__(-12.0)
    call    render_set_camera
    ; 10 blocks straight ahead has to land on screen centre
    mov     eax, __?float32?__(10.0)
    movd    xmm0, eax
    call    tr_clip
    movss   [rel pt], xmm1
    movss   [rel pt + 4], xmm2
    CHECK_NEAR xmm0, 0.0, 0.0005, "ndc x of a point ahead == 0"
    CHECK_NEAR [rel pt], 0.0, 0.0005, "ndc y of a point ahead == 0"
    xor     ebx, ebx
    movss   xmm0, [rel pt + 4]
    mov     eax, __?float32?__(-1.0)
    movd    xmm1, eax
    comiss  xmm0, xmm1
    jbe     .z1
    mov     eax, __?float32?__(1.0)
    movd    xmm1, eax
    comiss  xmm0, xmm1
    jae     .z1
    mov     ebx, 1
.z1:
    CHECK_TRUE ebx, "point ahead inside the depth range (-1 < z/w < 1)"
    ; far = (render_dist + 1) * 16 * 1.5 = 216
    mov     eax, __?float32?__(220.0)
    movd    xmm0, eax
    call    tr_clip
    xor     ebx, ebx
    mov     eax, __?float32?__(1.0)
    movd    xmm1, eax
    comiss  xmm2, xmm1
    jbe     .z2
    mov     ebx, 1
.z2:
    CHECK_TRUE ebx, "point at 220 is beyond the far plane (z/w > 1)"
ENDP
