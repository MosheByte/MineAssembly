; render.asm - chunk shader, remesh budget, camera, world pass, and the immediate
; mode block/item drawing. all camera relative (u_offset = chunk origin - cam) so
; floats stay precise far from spawn
%define IMPL_RENDER
%include "common.inc"

; 16-bit ibo covers 65536 verts, bigger sections draw in batches of that
%define R_IBO_QUADS 16384
%define GL_SHORT    0x1402
%define R_MESH_UPLOADS      32          ; finished sections -> vbos per frame
%define R_MESH_UPLOADS_LOAD 1024

extern glIsEnabled
extern mesher_submit, mesher_collect, mesher_busy, mesher_cancel

; PROC/PROCX without the global
%macro LPROC 1-2 0
    align 16
%1:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8
%endmacro

%macro LPROCX 1-2 0
    align 16
%1:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, 168
    movdqa [rsp+0],   xmm6
    movdqa [rsp+16],  xmm7
    movdqa [rsp+32],  xmm8
    movdqa [rsp+48],  xmm9
    movdqa [rsp+64],  xmm10
    movdqa [rsp+80],  xmm11
    movdqa [rsp+96],  xmm12
    movdqa [rsp+112], xmm13
    movdqa [rsp+128], xmm14
    movdqa [rsp+144], xmm15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT
%endmacro

; float literal into an xmm, saves .rdata constants
%macro FARG 2
    mov  eax, __float32__(%2)
    movd %1, eax
%endmacro

%define RECT(a,b,c,d) ((a) | ((b)<<8) | ((c)<<16) | ((d)<<24))
%define RECT_FULL   RECT(0,0,16,16)
%define MAXVIS      (MAX_CHUNKS*SECTIONS)

; same order as uni_names
%define U_OFFSET    0
%define U_CAM       1
%define U_TIME      2
%define U_DAYLIGHT  3
%define U_FOGCOL    4
%define U_FOGSTART  5
%define U_FOGEND    6
%define U_UNDERWATER 7
%define U_ALPHAREF  8
%define U_REFLECT   9
%define U_SKYCOL    10
%define U_SUNDIR    11
%define U_TEX       12
%define U_COUNT     13

section .data
global render_chunk_shader
align 4
render_chunk_shader: dd 0

align 8
attrib_names:   dq s_a_pos, s_a_uv, s_a_light, s_a_color, 0
uni_names:
    dq s_u_offset, s_u_cam, s_u_time, s_u_daylight, s_u_fog_color, s_u_fog_start
    dq s_u_fog_end, s_u_underwater, s_u_alpha_ref, s_u_reflect, s_u_sky_color
    dq s_u_sun_dir, s_u_tex

section .rdata
s_a_pos:        db "a_pos", 0
s_a_uv:         db "a_uv", 0
s_a_light:      db "a_light", 0
s_a_color:      db "a_color", 0
s_u_offset:     db "u_offset", 0
s_u_cam:        db "u_cam", 0
s_u_time:       db "u_time", 0
s_u_daylight:   db "u_daylight", 0
s_u_fog_color:  db "u_fog_color", 0
s_u_fog_start:  db "u_fog_start", 0
s_u_fog_end:    db "u_fog_end", 0
s_u_underwater: db "u_underwater", 0
s_u_alpha_ref:  db "u_alpha_ref", 0
s_u_reflect:    db "u_reflect", 0
s_u_sky_color:  db "u_sky_color", 0
s_u_sun_dir:    db "u_sun_dir", 0
s_u_tex:        db "u_tex", 0
s_log_ok:       db "render: chunk shader ready (program %d)", 0
s_log_fail:     db "render: chunk shader FAILED to compile - world will not be drawn", 0
s_bench_mesh:   db "bench: meshes/s=%d vbo=%lldKB fps=%d mesh_main=%.2fms/s", 0

; inputs are the packed VERTEX from structs.inc:
;   a_pos   short x3, 1/256 block. x/z chunk local, y - 64 (u_offset.y adds it back)
;   a_uv    ubyte x2, 1/8 texel inside the tile
;   a_light sky, block, shade, flags as normalized bytes. flags = VF_* from mesher.asm
;   a_color tint rgb, a = atlas tile / 255
; a_pos / 256 is exact, so p is the same single rounding as with float positions
; glsl 1.20 has no int ops so the bits come out with floor/mod. ugly but works everywhere
vs_src:
    db "#version 120", 10
    db "attribute vec3 a_pos;", 10
    db "attribute vec2 a_uv;", 10
    db "attribute vec4 a_light;", 10
    db "attribute vec4 a_color;", 10
    db "uniform vec3 u_offset;", 10
    db "uniform vec3 u_cam;", 10
    db "uniform float u_time;", 10
    db "varying vec2 v_uv;", 10
    db "varying vec4 v_color;", 10
    db "varying vec3 v_light;", 10
    db "varying vec3 v_pos;", 10
    db "varying vec3 v_flags;", 10
    db "void main() {", 10
    db "    vec3 p = a_pos / 256.0 + u_offset;", 10
    db "    vec3 w = p + u_cam;", 10
    db "    float f = floor(a_light.w * 255.0 + 0.5);", 10
    db "    float wave = mod(f, 2.0);", 10
    db "    float liquid = mod(floor(f * 0.5), 2.0);", 10
    db "    float fastleaf = mod(floor(f * 0.25), 2.0);", 10
    db "    float grassside = mod(floor(f * 0.125), 2.0);", 10
    db "    if (wave > 0.5) {", 10
    db "        float ph = u_time * 1.7 + w.x * 0.55 + w.z * 0.45 + w.y * 0.35;", 10
    db "        p.x += sin(ph) * 0.045;", 10
    db "        p.z += cos(ph * 0.83 + w.x * 0.21) * 0.035;", 10
    db "        p.y += sin(ph * 1.31) * 0.012;", 10
    db "    }", 10
    db "    if (liquid > 0.5) {", 10
    db "        p.y += (sin(u_time * 1.9 + w.x * 0.8 + w.z * 0.6) * 0.5", 10
    db "              + sin(u_time * 1.3 - w.x * 0.5 + w.z * 0.9) * 0.5 - 1.0) * 0.035;", 10
    db "    }", 10
    db "    v_pos = p;", 10
    db "    float tile = floor(a_color.a * 255.0 + 0.5);", 10
    db "    vec2 corner = vec2(mod(tile, 16.0), floor(tile / 16.0)) * 128.0;", 10
    db "    v_uv = (corner + a_uv) / 2048.0;", 10
    db "    v_color = vec4(a_color.rgb, 1.0);", 10
    db "    v_light = a_light.xyz;", 10
    db "    v_flags = vec3(liquid, fastleaf, grassside);", 10
    db "    gl_Position = gl_ModelViewProjectionMatrix * vec4(p, 1.0);", 10
    db "}", 10, 0

; light = max(sky * daylight * moon, block * torch), both through x/(3-2x) first.
; torch goes deep orange at the edge to warm white at the source. a flat colour
; disappears on grass at night next to the blue moonlight.
; grass sides: only clearly green texels (g-r over ~.05) get the biome tint
fs_src:
    db "#version 120", 10
    db "uniform sampler2D u_tex;", 10
    db "uniform float u_daylight;", 10
    db "uniform vec3 u_fog_color;", 10
    db "uniform float u_fog_start;", 10
    db "uniform float u_fog_end;", 10
    db "uniform float u_underwater;", 10
    db "uniform float u_alpha_ref;", 10
    db "uniform float u_reflect;", 10
    db "uniform vec3 u_sky_color;", 10
    db "uniform vec3 u_sun_dir;", 10
    db "varying vec2 v_uv;", 10
    db "varying vec4 v_color;", 10
    db "varying vec3 v_light;", 10
    db "varying vec3 v_pos;", 10
    db "varying vec3 v_flags;", 10
    db "void main() {", 10
    db "    vec4 tex = texture2D(u_tex, v_uv);", 10
    db "    if (v_flags.y > 0.5) { tex.rgb = mix(vec3(0.22), tex.rgb, tex.a); tex.a = 1.0; }", 10
    db "    if (tex.a < u_alpha_ref) discard;", 10
    db "    vec3 col = tex.rgb * v_color.rgb;", 10
    db "    if (v_flags.z > 0.5) {", 10
    db "        float turf = clamp((tex.g - tex.r) * 10.0 - 0.5, 0.0, 1.0);", 10
    db "        col = mix(tex.rgb, vec3(tex.g) * v_color.rgb, turf);", 10
    db "    }", 10
    db "    float sl = v_light.x / (3.0 - 2.0 * v_light.x);", 10
    db "    float bl = v_light.y / (3.0 - 2.0 * v_light.y);", 10
    db "    float day = u_daylight;", 10
    db "    vec3 moon = mix(vec3(0.8, 0.88, 1.3), vec3(1.0), clamp(day * 1.6 - 0.3, 0.0, 1.0));", 10
    db "    vec3 torch = mix(vec3(1.0, 0.66, 0.36), vec3(1.0, 0.9, 0.74), bl);", 10
    db "    vec3 light = max(vec3(sl * day) * moon, bl * torch);", 10
    db "    light = max(light, vec3(0.04));", 10
    db "    col *= light * v_light.z;", 10
    db "    float alpha = tex.a * v_color.a;", 10
    db "    if (u_reflect > 0.5 && v_flags.x > 0.5) {", 10
    db "        vec3 vd = normalize(v_pos);", 10
    db "        float fres = pow(1.0 - abs(vd.y), 4.0);", 10
    db "        col = mix(col, u_sky_color * (0.25 + 0.75 * sl), fres * 0.6);", 10
    db "        alpha = mix(alpha, 1.0, fres * 0.5);", 10
    db "        vec3 r = reflect(vd, vec3(0.0, 1.0, 0.0));", 10
    db "        float spec = pow(max(dot(r, u_sun_dir), 0.0), 90.0) * sl * day;", 10
    db "        col += vec3(1.0, 0.95, 0.8) * spec * 0.9;", 10
    db "        alpha = min(1.0, alpha + spec);", 10
    db "    }", 10
    db "    float dist = length(v_pos);", 10
    db "    float fog = clamp((dist - u_fog_start) / max(u_fog_end - u_fog_start, 0.001), 0.0, 1.0);", 10
    db "    fog = fog * fog * (3.0 - 2.0 * fog);", 10
    db "    if (u_underwater > 0.5) fog = max(fog, 1.0 - exp(-dist * (u_underwater > 1.5 ? 1.1 : 0.055)));", 10
    db "    gl_FragColor = vec4(mix(col, u_fog_color, fog), alpha);", 10
    db "}", 10, 0

align 16
; same corner order as mesher.asm
r_corner:
    db 1,0,1, 1,0,0, 1,1,0, 1,1,1
    db 0,0,0, 0,0,1, 0,1,1, 0,1,0
    db 0,1,1, 1,1,1, 1,1,0, 0,1,0
    db 1,0,1, 0,0,1, 0,0,0, 1,0,0
    db 0,0,1, 1,0,1, 1,1,1, 0,1,1
    db 1,0,0, 0,0,0, 0,1,0, 1,1,0
corner_uoff: db 0, 8, 8, 0
corner_voff: db 12, 12, 4, 4
; outline edges, corner index bits are x/y/z
sel_edges:
    db 0,1, 2,3, 4,5, 6,7,  0,2, 1,3, 4,6, 5,7,  0,4, 1,5, 2,6, 3,7
; mesh sections outward from the player's height
sec_order: db 0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7
nb8_dx: db -1, 0, 1, -1, 1, -1, 0, 1
nb8_dz: db -1,-1,-1,  0, 0,  1, 1, 1

align 4
r_face_shade:   dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8
liq_h:          dd 0.888889, 0.777778, 0.666667, 0.555556, 0.444444, 0.333333, 0.222222, 0.111111
                dd 0.888889, 0.666667, 0.444444, 0.222222

shape_full:     dd 0.0, 0.0, 0.0, 1.0, 1.0, 1.0
shape_torch:    dd 0.375, 0.0, 0.375, 0.625, 0.625, 0.625
shape_cross:    dd 0.1, 0.0, 0.1, 0.9, 0.8, 0.9
shape_lantern:  dd 0.3125, 0.0, 0.3125, 0.6875, 0.5625, 0.6875
shape_cactus:   dd 0.0625, 0.0, 0.0625, 0.9375, 1.0, 0.9375
box_torch:      dd 0.4375, 0.0, 0.4375, 0.5625, 0.625, 0.5625
box_lantern:    dd 0.3125, 0.0, 0.3125, 0.6875, 0.4375, 0.6875
box_lantern_cap: dd 0.375, 0.4375, 0.375, 0.625, 0.5625, 0.625
box_arm:        dd -0.1, -0.1, -0.78, 0.1, 0.1, 0.0

f_zero:     dd 0.0
f_one:      dd 1.0
f_half:     dd 0.5
f_two:      dd 2.0
f_three:    dd 3.0
f_eight:    dd 8.0
f_fifteenth: dd 0.06666667
f_inv255:   dd 0.003921569
f_texel:    dd 0.00390625
f_inset:    dd 0.0009765625
f_sixteenth: dd 0.0625
f_pi:       dd 3.14159265
f_two_pi:   dd 6.2831853
f_deg2rad:  dd 0.017453293
f_eye:      dd 1.62
f_near:     dd 0.05
f_70:       dd 70.0
f_90:       dd 90.0
f_m90:      dd -90.0
f_180:      dd 180.0
f_1024:     dd 1024.0
f_inv1024:  dd 0.0009765625
f_tp_dist:  dd 4.0
f_tp_min:   dd 0.3
f_sel_grow: dd 0.002
f_crack_grow: dd 0.001
f_sprite_t: dd 0.03125
f_min_bright: dd 0.12
f_ambient:  dd 0.04
align 8
d_budget_play: dq 0.005
d_budget_load: dq 0.030
d_one:         dq 1.0
d_1000:        dq 1000.0
d_3600:        dq 3600.0
d_inv3600:     dq 0.000277777777777778

section .bss
alignb 16
uni_loc:    resd U_COUNT
r_quad_ibo: resd 1
alignb 16
r_idx_stage: resw R_IBO_QUADS*6
alignb 16
vis_chunk:  resq MAXVIS
vis_sec:    resd MAXVIS
vis_key:    resd MAXVIS
vis_order:  resd MAXVIS
vis_hist:   resd 1024
vis_n:      resd 1
cand_chunk: resq MAX_CHUNKS
cand_key:   resd MAX_CHUNKS
alignb 16
r_fog:      resd 4
r_fog_start: resd 1
r_fog_end:  resd 1
r_medium:   resd 1                      ; 0 air, 1 water, 2 lava
r_daylight: resd 1
r_time:     resd 1
r_camw:     resd 4                      ; camera mod 1024, keeps wave phase sane
r_sundir:   resd 4
r_aabb:     resd 8
r_uv:       resd 4
r_shape:    resd 8
r_tmp_mat:  resd 16
r_vec:      resd 8
r_dir:      resd 4
r_hit:      resb RAYHIT_size
alignb 8
r_bench_t0:  resq 1
r_bench_acc: resq 1                     ; seconds spent in render_update_meshes
r_bench_m0:  resd 1
alignb 16
; r_imm_box inputs
rb_box:     resd 8
rb_tint:    resd 6
rb_rect:    resd 6
rb_tile:    resb 8
rb_bright:  resd 1
rb_flat:    resd 1

section .text

PROC render_init, 32
    lea     rcx, [rel vs_src]
    lea     rdx, [rel fs_src]
    lea     r8, [rel attrib_names]
    call    gl_compile_program
    mov     [rel render_chunk_shader], eax
    test    eax, eax
    jnz     .ok
    lea     rcx, [rel s_log_fail]
    call    log_write
    jmp     .gl
.ok:
    mov     r12d, eax
    xor     ebx, ebx
.uni:
    mov     ecx, r12d
    lea     rax, [rel uni_names]
    mov     rdx, [rax + rbx*8]
    call    [rel pglGetUniformLocation]
    lea     rdx, [rel uni_loc]
    mov     [rdx + rbx*4], eax
    inc     ebx
    cmp     ebx, U_COUNT
    jb      .uni
    mov     ecx, r12d
    call    [rel pglUseProgram]
    mov     ecx, [rel uni_loc + U_TEX*4]
    xor     edx, edx
    call    [rel pglUniform1i]
    xor     ecx, ecx
    call    [rel pglUseProgram]
    lea     rcx, [rel s_log_ok]
    mov     edx, r12d
    call    log_printf
    call    r_make_quad_ibo
.gl:
    ; default GL state. everything else assumes this is what it finds, so
    ; whoever changes it puts it back
    mov     ecx, GL_DEPTH_TEST
    call    glEnable
    mov     ecx, GL_LEQUAL
    call    glDepthFunc
    mov     ecx, GL_CULL_FACE
    call    glEnable
    mov     ecx, GL_BACK
    call    glCullFace
    mov     ecx, GL_CCW
    call    glFrontFace
    mov     ecx, GL_SRC_ALPHA
    mov     edx, GL_ONE_MINUS_SRC_ALPHA
    call    glBlendFunc
    mov     ecx, GL_GREATER
    FARG    xmm1, 0.1
    call    glAlphaFunc
ENDP

; one static ibo for all sections, 4q 4q+1 4q+2 / 4q 4q+2 4q+3, 16 bit
LPROC r_make_quad_ibo, 16
    lea     rdi, [rel r_idx_stage]
    xor     eax, eax
    mov     ecx, R_IBO_QUADS
.q:
    mov     [rdi], ax
    lea     edx, [rax + 1]
    mov     [rdi + 2], dx
    lea     edx, [rax + 2]
    mov     [rdi + 4], dx
    mov     [rdi + 6], ax
    mov     [rdi + 8], dx
    lea     edx, [rax + 3]
    mov     [rdi + 10], dx
    add     eax, 4
    add     rdi, 12
    dec     ecx
    jnz     .q
    mov     ecx, 1
    lea     rdx, [rel r_quad_ibo]
    call    [rel pglGenBuffers]
    mov     ecx, GL_ELEMENT_ARRAY_BUFFER
    mov     edx, [rel r_quad_ibo]
    call    [rel pglBindBuffer]
    mov     ecx, GL_ELEMENT_ARRAY_BUFFER
    mov     edx, R_IBO_QUADS*12
    lea     r8, [rel r_idx_stage]
    mov     r9d, GL_STATIC_DRAW
    call    [rel pglBufferData]
    mov     ecx, GL_ELEMENT_ARRAY_BUFFER
    xor     edx, edx
    call    [rel pglBindBuffer]
ENDP

PROC render_free_chunk, 16
    mov     rbx, rcx
    test    rbx, rbx
    jz      .done
    call    mesher_cancel                       ; rcx still the chunk
    xor     esi, esi
.l:
    cmp     dword [rbx + CHUNK.vbo + rsi*4], 0
    je      .n
    mov     rax, [rel pglDeleteBuffers]
    test    rax, rax
    jz      .z
    mov     ecx, 1
    lea     rdx, [rbx + CHUNK.vbo + rsi*4]
    call    rax
.z:
    mov     dword [rbx + CHUNK.vbo + rsi*4], 0
.n:
    mov     dword [rbx + CHUNK.vcount + rsi*4], 0
    inc     esi
    cmp     esi, 16
    jb      .l
    mov     qword [rbx + CHUNK.sec_flags], 0
.done:
ENDP

; render distance in chunks, 0 in the settings means 8
r_render_dist:
    mov     eax, [rel g_settings + SETTINGS.render_dist]
    test    eax, eax
    jnz     .c
    mov     eax, 8
.c:
    cmp     eax, 2
    jge     .c2
    mov     eax, 2
.c2:
    cmp     eax, MAX_RENDER_DIST
    jle     .c3
    mov     eax, MAX_RENDER_DIST
.c3:
    ret

; cvttss2si truncates, wrong for negatives
r_floor:
    roundss xmm0, xmm0, 1
    cvttss2si eax, xmm0
    ret

; --bench only: once a second log meshes/s, resident chunk vbo bytes and how
; long the main thread spent in here
PROC render_update_meshes, 16 ; v1: render scratch #3
    cmp     dword [rel g_run_mode], 2 ; v1: render scratch #4
    ; TODO: clamp index before table lookup on malformed input (render:4)
    je      .bench ; v1: render scratch #5
    call    r_update_meshes_body ; v1: render scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (render:6)
    jmp     .done ; v1: render scratch #7
.bench: ; v1: render scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (render:8)
    call    time_seconds ; v1: render scratch #9
    movsd   LOC(0), xmm0 ; v1: render scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (render:10)
    call    r_update_meshes_body ; v1: render scratch #11
    call    time_seconds ; v1: render scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (render:12)
    movsd   xmm1, xmm0 ; v1: render scratch #13
    subsd   xmm1, LOC(0) ; v1: render scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (render:14)
    addsd   xmm1, [rel r_bench_acc] ; v1: render scratch #15
    movsd   [rel r_bench_acc], xmm1 ; v1: render scratch #16
    ; TODO: hoist invariant pointer load out of .loop (render:16)
    movsd   xmm1, [rel r_bench_t0] ; v1: render scratch #17
    xorpd   xmm2, xmm2 ; v1: render scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (render:18)
    ucomisd xmm1, xmm2 ; v1: render scratch #19
    jne     .have_t0 ; v1: render scratch #20
    ; TODO: clamp index before table lookup on malformed input (render:20)
    movsd   [rel r_bench_t0], xmm0 ; v1: render scratch #21
    mov     eax, [rel g_stat_meshes_built] ; v1: render scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (render:22)
    mov     [rel r_bench_m0], eax ; v1: render scratch #23
    jmp     .done ; v1: render scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (render:24)
.have_t0: ; v1: render scratch #25
    movsd   xmm2, xmm0 ; v1: render scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (render:26)
    subsd   xmm2, xmm1 ; v1: render scratch #27
    comisd  xmm2, [rel d_one] ; v1: render scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (render:28)
    jb      .done ; v1: render scratch #29
    movsd   [rel r_bench_t0], xmm0 ; v1: render scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (render:30)
    call    r_bench_log ; v1: render scratch #31
.done: ; v1: render scratch #32
    ; TODO: hoist invariant pointer load out of .loop (render:32)
ENDP ; v1: render scratch #33

LPROC r_bench_log, 32 ; v1: render scratch #35
    ; resident = every chunk's vbos
    xor     r12, r12 ; v1: render scratch #37
    xor     ebx, ebx ; v1: render scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (render:38)
.cl: ; v1: render scratch #39
    cmp     ebx, [rel g_chunk_count] ; v1: render scratch #40
    ; TODO: clamp index before table lookup on malformed input (render:40)
    jae     .sum ; v1: render scratch #41
    lea     rax, [rel g_chunk_list]
    mov     rdi, [rax + rbx*8]
    inc     ebx
    test    rdi, rdi
    jz      .cl
    xor     esi, esi
.vl:
    cmp     dword [rdi + CHUNK.vbo + rsi*4], 0
    je      .vn
    mov     eax, [rdi + CHUNK.vcount + rsi*4]
    add     r12, rax
.vn:
    inc     esi
    cmp     esi, 16
    jb      .vl
    jmp     .cl
.sum:
    imul    r12, r12, VERTEX_STRIDE
    shr     r12, 10
    mov     edx, [rel g_stat_meshes_built]
    mov     eax, edx
    sub     edx, [rel r_bench_m0]
    mov     [rel r_bench_m0], eax
    movsd   xmm0, [rel r_bench_acc]
    mulsd   xmm0, [rel d_1000]
    cvtsd2ss xmm0, xmm0
    movd    eax, xmm0
    mov     [rsp + 32], rax
    xorpd   xmm0, xmm0
    movsd   [rel r_bench_acc], xmm0
    lea     rcx, [rel s_bench_mesh]
    mov     r8, r12
    mov     r9d, [rel g_fps]
    call    log_printf
ENDP

; finished jobs go up first, then dirty sections get handed to mesher_submit.
; candidates: lit chunks in range with dirty sections and all 8 neighbours lit
; (else the border light is still wrong and we'd mesh it twice). nearest first,
; dumb selection since n is small. on the workers the job pool is the limit.
; without workers it meshes right here: 24 sections or 5ms, 160 / 30ms while
; loading, and a LIT chunk's first mesh always finishes in one go
LPROCX r_update_meshes_body, 64
    mov     r15d, 24
    movsd   xmm6, [rel d_budget_play]
    mov     dword LOC(16), R_MESH_UPLOADS
    cmp     dword [rel g_state], ST_LOADING
    jne     .budget
    mov     r15d, 160
    movsd   xmm6, [rel d_budget_load]
    mov     dword LOC(16), R_MESH_UPLOADS_LOAD
.budget:
    call    time_seconds
    movsd   xmm7, xmm0
    mov     ecx, LOC(16)
    call    mesher_collect
    sub     LOC(16), eax
    movss   xmm0, [rel g_player + PLAYER.x]
    call    r_floor
    sar     eax, 4
    mov     r12d, eax                           ; player chunk x
    movss   xmm0, [rel g_player + PLAYER.z]
    call    r_floor
    sar     eax, 4
    mov     r13d, eax                           ; player chunk z
    movss   xmm0, [rel g_player + PLAYER.y]
    call    r_floor
    sar     eax, 4
    cmp     eax, 0
    jge     .ps1
    xor     eax, eax
.ps1:
    cmp     eax, SECTIONS-1
    jle     .ps2
    mov     eax, SECTIONS-1
.ps2:
    mov     LOC(0), eax
    call    r_render_dist
    mov     r14d, eax

    xor     esi, esi
    xor     ebx, ebx
.cl:
    cmp     ebx, [rel g_chunk_count]
    jae     .cdone
    lea     rax, [rel g_chunk_list]
    mov     rdi, [rax + rbx*8]
    inc     ebx
    test    rdi, rdi
    jz      .cl
    mov     eax, [rdi + CHUNK.state]
    cmp     eax, CS_LIT
    jb      .cl
    cmp     dword [rdi + CHUNK.dirty], 0
    jne     .dirty
    ; clean LIT with nothing in the pool = meshed (chunkmgr dirties all 8 on LIT)
    cmp     eax, CS_LIT
    jne     .cl
    mov     rcx, rdi
    call    mesher_busy
    test    edx, edx
    jnz     .cl
    mov     eax, CS_LIT
    mov     ecx, CS_READY
    lock cmpxchg [rdi + CHUNK.state], ecx
    jmp     .cl
.dirty:
    mov     eax, [rdi + CHUNK.cx]
    sub     eax, r12d
    mov     ecx, [rdi + CHUNK.cz]
    sub     ecx, r13d
    mov     edx, eax
    neg     edx
    cmovl   edx, eax
    cmp     edx, r14d
    jg      .cl
    mov     edx, ecx
    neg     edx
    cmovl   edx, ecx
    cmp     edx, r14d
    jg      .cl
    imul    eax, eax
    imul    ecx, ecx
    add     eax, ecx
    mov     LOC(4), eax
    mov     rcx, rdi
    call    r_neighbours_lit
    test    eax, eax
    jz      .cl
    lea     rax, [rel cand_chunk]
    mov     [rax + rsi*8], rdi
    mov     eax, LOC(4)
    lea     rdx, [rel cand_key]
    mov     [rdx + rsi*4], eax
    inc     esi
    cmp     esi, MAX_CHUNKS
    jb      .cl
.cdone:
    mov     LOC(8), esi
    mov     dword LOC(12), 0                    ; sections meshed right here so far

.select:
    mov     eax, LOC(12)
    cmp     eax, r15d
    jae     .done
    cmp     eax, 0                              ; always do at least one chunk
    je      .sel_go
    call    time_seconds
    subsd   xmm0, xmm7
    comisd  xmm0, xmm6
    ja      .done
.sel_go:
    mov     ecx, LOC(8)
    mov     edx, 0x7FFFFFFF
    mov     r8d, -1
    xor     r9d, r9d
    lea     r10, [rel cand_key]
.minl:
    cmp     r9d, ecx
    jae     .minend
    mov     eax, [r10 + r9*4]
    cmp     eax, edx
    jge     .minnext
    mov     edx, eax
    mov     r8d, r9d
.minnext:
    inc     r9d
    jmp     .minl
.minend:
    cmp     r8d, 0
    jl      .done
    mov     dword [r10 + r8*4], 0x7FFFFFFF      ; used up
    lea     rax, [rel cand_chunk]
    mov     rdi, [rax + r8*8]
    mov     rcx, rdi
    call    mesher_busy
    mov     LOC(20), eax                        ; still on a worker, leave those be
    xor     ebx, ebx
.secl:
    cmp     ebx, 15
    jae     .select
    lea     rax, [rel sec_order]
    movsx   esi, byte [rax + rbx]
    add     esi, LOC(0)
    inc     ebx
    cmp     esi, 0
    jl      .secl
    cmp     esi, SECTIONS
    jge     .secl
    bt      dword [rdi + CHUNK.dirty], esi
    jnc     .secl
    bt      dword LOC(20), esi
    jc      .secl
    mov     rcx, rdi
    mov     edx, esi
    call    mesher_submit
    test    eax, eax
    jz      .done                               ; pool full
    cmp     eax, 2
    jne     .secl
    inc     dword LOC(12)
    cmp     dword [rdi + CHUNK.state], CS_LIT
    je      .secl
    mov     eax, LOC(12)
    cmp     eax, r15d
    jae     .select
    call    time_seconds
    subsd   xmm0, xmm7
    comisd  xmm0, xmm6
    jbe     .secl
    mov     LOC(12), r15d                       ; out of time, rest waits for next frame
    jmp     .select
.done:
    ; whatever finished meanwhile (or got meshed right here)
    mov     ecx, LOC(16)
    call    mesher_collect
ENDPX
    ; v1 temporary guard (render #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (render #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (render #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (render #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (render #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (render #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (render #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (render #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (render #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (render #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (render #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (render #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (render #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (render #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (render #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (render #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (render #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (render #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (render #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (render #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (render #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (render #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (render #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (render #63)
    xor     r11d, r11d ; clear v1 slot 63
