; texgen + font against a real GL driver: hidden window, legacy WGL context,
; then read every texture level back with glGetTexImage and check it, incl.
; the per-tile mip chain vs art_ref_mip (+-1). passes with a SKIPPED note
; when there's no GL context at all (headless box).
; @link src/texgen.asm src/font.asm tests/art/artlib.asm
; @gpu
; @timeout 120


%include "common.inc"
%include "testlib.inc"
%include "../art/art.inc"


; GL 1.1, in opengl32.dll but not in gl.inc
extern glGetTexImage, glGetTexParameteriv, glGetTexLevelParameteriv


%define TG_TEXTURE_WIDTH        0x1000
%define TG_TEXTURE_BINDING_2D   0x8069


section .rdata
cls_static  db "STATIC", 0
wnd_title   db "texgen-gl-test", 0


section .bss
alignb 16
gt_hwnd      resq 1
gt_hdc       resq 1
gt_hrc       resq 1
gt_pfd       resb 40                 ; PIXELFORMATDESCRIPTOR
alignb 16
gt_ival      resd 4
gt_tex       resd 3                  ; atlas, font, clouds
gt_lvl       resd 256*256
gt_levels    resd 256*256 + 128*128 + 64*64 + 32*32 + 16*16
gt_ref       resd 128*128 + 64*64 + 32*32 + 16*16             ; mips 1..4 only
gt_fontref   resd 128*128


section .text


; level_offset(ecx level) -> eax dword offset into a packed 256..16 chain
level_offset:
    xor     eax, eax
    mov     edx, 256*256
.l: test    ecx, ecx
    jz      .d
    add     eax, edx
    shr     edx, 2
    dec     ecx
    jmp     .l
.d: ret


; -> eax 1 when we have a hidden window with a current context
PROC gl_open
    xor     ecx, ecx
    lea     rdx, [rel cls_static]
    lea     r8, [rel wnd_title]
    mov     r9d, WS_CLIPCHILDREN | WS_CLIPSIBLINGS    ; no WS_VISIBLE, never shown
    mov     qword [rsp+32], 0
    mov     qword [rsp+40], 0
    mov     qword [rsp+48], 64
    mov     qword [rsp+56], 64
    mov     qword [rsp+64], 0
    mov     qword [rsp+72], 0
    mov     qword [rsp+80], 0
    mov     qword [rsp+88], 0
    call    CreateWindowExA
    test    rax, rax
    jz      .fail
    mov     [rel gt_hwnd], rax
    mov     rcx, rax
    call    GetDC
    mov     [rel gt_hdc], rax
    lea     rdi, [rel gt_pfd]
    xor     eax, eax
    mov     ecx, 40
    rep     stosb
    lea     rdi, [rel gt_pfd]
    mov     word [rdi+0], 40            ; nSize
    mov     word [rdi+2], 1             ; nVersion
    mov     dword [rdi+4], PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
    mov     byte [rdi+8], PFD_TYPE_RGBA
    mov     byte [rdi+9], 32            ; cColorBits
    mov     byte [rdi+16], 8            ; cAlphaBits
    mov     byte [rdi+23], 24           ; cDepthBits
    mov     rcx, [rel gt_hdc]
    mov     rdx, rdi
    call    ChoosePixelFormat
    test    eax, eax
    jz      .destroy
    mov     rcx, [rel gt_hdc]
    mov     edx, eax
    lea     r8, [rel gt_pfd]
    call    SetPixelFormat
    test    eax, eax
    jz      .destroy
    mov     rcx, [rel gt_hdc]
    call    wglCreateContext
    test    rax, rax
    jz      .destroy
    mov     [rel gt_hrc], rax
    mov     rcx, [rel gt_hdc]
    mov     rdx, rax
    call    wglMakeCurrent
    test    eax, eax
    jz      .delete
    mov     eax, 1
    jmp     .done
.delete:
    mov     rcx, [rel gt_hrc]
    call    wglDeleteContext
    mov     qword [rel gt_hrc], 0
.destroy:
    mov     rcx, [rel gt_hwnd]
    mov     rdx, [rel gt_hdc]
    call    ReleaseDC
    mov     rcx, [rel gt_hwnd]
    call    DestroyWindow
    mov     qword [rel gt_hwnd], 0
.fail:
    xor     eax, eax
.done:
ENDP


PROC gl_close
    xor     ecx, ecx
    xor     edx, edx
    call    wglMakeCurrent
    mov     rcx, [rel gt_hrc]
    call    wglDeleteContext
    mov     rcx, [rel gt_hwnd]
    mov     rdx, [rel gt_hdc]
    call    ReleaseDC
    mov     rcx, [rel gt_hwnd]
    call    DestroyWindow
ENDP


; iparam(ecx pname) -> eax, on the bound GL_TEXTURE_2D
PROC iparam
    mov     edx, ecx
    mov     dword [rel gt_ival], 0
    mov     ecx, GL_TEXTURE_2D
    lea     r8, [rel gt_ival]
    call    glGetTexParameteriv
    mov     eax, [rel gt_ival]
ENDP


PROC level_w
    mov     edx, ecx
    mov     dword [rel gt_ival], 0
    mov     ecx, GL_TEXTURE_2D
    mov     r8d, TG_TEXTURE_WIDTH
    lea     r9, [rel gt_ival]
    call    glGetTexLevelParameteriv
    mov     eax, [rel gt_ival]
ENDP


PROC bound
    mov     dword [rel gt_ival], 0
    mov     ecx, TG_TEXTURE_BINDING_2D
    lea     rdx, [rel gt_ival]
    call    glGetIntegerv
    mov     eax, [rel gt_ival]
ENDP


; read_level(ecx level, rdx dst), RGBA8
PROC read_level
    mov     [rsp+32], rdx
    mov     edx, ecx
    mov     ecx, GL_TEXTURE_2D
    mov     r8d, GL_RGBA
    mov     r9d, GL_UNSIGNED_BYTE
    call    glGetTexImage
ENDP


; ref_chain(rcx level0): gt_ref = reference mips 1..4 of a 256x256 level 0
PROC ref_chain
    mov     r12, rcx
    lea     r13, [rel gt_ref]
    mov     ebx, 128
.l: mov     rcx, r12
    mov     rdx, r13
    mov     r8d, ebx
    call    art_ref_mip
    mov     r12, r13
    mov     eax, ebx
    imul    eax, ebx
    lea     r13, [r13+rax*4]
    shr     ebx, 1
    cmp     ebx, 16
    jae     .l
ENDP


; ref_level(ecx l = 1..4) -> rax level l inside gt_ref
ref_level:
    lea     rax, [rel gt_ref]
    mov     edx, 128*128
.l: cmp     ecx, 1
    jbe     .d
    lea     rax, [rax+rdx*4]
    shr     edx, 2
    dec     ecx
    jmp     .l
.d: ret


; tile_far(ecx tile, edx level 1..4) -> eax texels of that tile's block that
; are off by more than 1 between gt_ref and gt_levels
PROC tile_far
    mov     r12d, ecx
    mov     r13d, edx
    mov     ecx, r13d
    call    ref_level
    mov     rsi, rax
    mov     ecx, r13d
    call    level_offset
    lea     rdi, [rel gt_levels]
    lea     rdi, [rdi+rax*4]
    mov     ecx, r13d
    mov     r14d, 16
    shr     r14d, cl                    ; ts = 16 >> l
    mov     r15d, 256
    shr     r15d, cl                    ; size = 256 >> l
    ; block origin ((t>>4)*ts)*size + (t&15)*ts
    mov     eax, r12d
    shr     eax, 4
    imul    eax, r14d
    imul    eax, r15d
    mov     edx, r12d
    and     edx, 15
    imul    edx, r14d
    add     eax, edx
    lea     rsi, [rsi+rax*4]
    lea     rdi, [rdi+rax*4]
    xor     ebx, ebx
    mov     r12d, r14d
.row:
    mov     rcx, rsi
    mov     rdx, rdi
    mov     r8d, r14d
    mov     r9d, 1
    call    art_count_far
    add     ebx, eax
    mov     eax, r15d
    lea     rsi, [rsi+rax*4]
    lea     rdi, [rdi+rax*4]
    dec     r12d
    jnz     .row
    mov     eax, ebx
ENDP


PROC test_main
    TEST "GL context"
    call    gl_open
    test    eax, eax
    jnz     .have
    PRINT   "gl: SKIPPED (no OpenGL context available)"
    call    t_newline
    jmp     .done
.have:
    PRINT   "gl renderer: "
    mov     ecx, GL_RENDERER
    call    glGetString
    test    rax, rax
    jz      .norend
    mov     rcx, rax
    call    t_print
.norend:
    call    t_newline
    mov     ecx, GL_PACK_ALIGNMENT
    mov     edx, 4
    call    glPixelStorei
    mov     ebx, 64                     ; drain stale errors, bounded in case the driver keeps returning one
.drain:
    call    glGetError
    test    eax, eax
    jz      .drained
    dec     ebx
    jnz     .drain
.drained:

    TEST "texgen_init + font_init"
    call    texgen_init
    call    font_init
    call    glGetError
    CHECK_EQ32 eax, 0, "no GL error after init"
    mov     eax, [rel g_tex_atlas]
    mov     [rel gt_tex+0], eax
    mov     eax, [rel g_tex_font]
    mov     [rel gt_tex+4], eax
    mov     eax, [rel g_tex_clouds]
    mov     [rel gt_tex+8], eax
    xor     ebx, ebx
    cmp     dword [rel gt_tex+0], 0
    je      .names
    cmp     dword [rel gt_tex+4], 0
    je      .names
    cmp     dword [rel gt_tex+8], 0
    je      .names
    mov     ebx, 1
.names:
    CHECK_TRUE ebx, "atlas, font and clouds textures created"
    xor     ebx, ebx
    mov     eax, [rel gt_tex+0]
    cmp     eax, [rel gt_tex+4]
    je      .dist
    cmp     eax, [rel gt_tex+8]
    je      .dist
    mov     eax, [rel gt_tex+4]
    cmp     eax, [rel gt_tex+8]
    je      .dist
    mov     ebx, 1
.dist:
    CHECK_TRUE ebx, "the three texture names are distinct"
    call    bound
    CHECK_EQ32 eax, [rel g_tex_atlas], "atlas must be bound after font_init"


    TEST "atlas parameters"
    mov     ecx, GL_TEXTURE_MIN_FILTER
    call    iparam
    CHECK_EQ32 eax, GL_NEAREST_MIPMAP_LINEAR, "atlas MIN_FILTER"
    mov     ecx, GL_TEXTURE_MAG_FILTER
    call    iparam
    CHECK_EQ32 eax, GL_NEAREST, "atlas MAG_FILTER"
    mov     ecx, GL_TEXTURE_WRAP_S
    call    iparam
    CHECK_EQ32 eax, GL_CLAMP_TO_EDGE, "atlas WRAP_S"
    mov     ecx, GL_TEXTURE_WRAP_T
    call    iparam
    CHECK_EQ32 eax, GL_CLAMP_TO_EDGE, "atlas WRAP_T"
    mov     ecx, GL_TEXTURE_MAX_LEVEL
    call    iparam
    CHECK_EQ32 eax, 4, "atlas MAX_LEVEL"
    xor     ebx, ebx
.lw:
    mov     ecx, ebx
    call    level_w
    mov     r12d, eax
    mov     r13d, 256
    mov     ecx, ebx
    shr     r13d, cl
    CHECK_EQ32 r12d, r13d, "atlas level width 256 >> level"
    DETAIL_IFZ eax, "level", ebx
    inc     ebx
    cmp     ebx, 5
    jb      .lw

    TEST "atlas level contents"
    xor     ecx, ecx
    lea     rdx, [rel gt_lvl]
    call    read_level
    lea     r12, [rel gt_lvl]
    mov     r13, [rel g_atlas_pixels]
    CHECK_MEM r12, r13, 256*256*4, "level 0 must equal g_atlas_pixels"
    mov     rcx, [rel g_atlas_pixels]
    call    ref_chain
    mov     ebx, 1
.ml:
    mov     ecx, ebx
    lea     rdx, [rel gt_lvl]
    call    read_level
    mov     ecx, ebx
    call    ref_level
    mov     r12, rax
    mov     ecx, ebx
    mov     r8d, 256
    shr     r8d, cl
    imul    r8d, r8d
    mov     rcx, r12
    lea     rdx, [rel gt_lvl]
    mov     r9d, 1
    call    art_count_far
    mov     r12d, eax
    CHECK_EQ32 r12d, 0, "mip level texels within 1 of the reference"
    DETAIL_IFZ eax, "level", ebx
    inc     ebx
    cmp     ebx, 5
    jb      .ml

    ; re-uploaded water/lava mips have to stay per-tile, no neighbour bleed
    TEST "animated re-upload" ; v1: test_gl scratch #1
    mov     r14d, 7 ; v1: test_gl scratch #2
    ; TODO: hoist invariant pointer load out of .loop (test_gl:2)
.tick: ; v1: test_gl scratch #3
    mov     ecx, r14d ; v1: test_gl scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_gl:4)
    call    texgen_animate ; v1: test_gl scratch #5
    call    glGetError ; v1: test_gl scratch #6
    ; TODO: clamp index before table lookup on malformed input (test_gl:6)
    CHECK_EQ32 eax, 0, "no GL error after texgen_animate" ; v1: test_gl scratch #7
    call    bound ; v1: test_gl scratch #8
    ; TODO: verify 16-byte rsp alignment before inner call (test_gl:8)
    CHECK_EQ32 eax, [rel g_tex_atlas], "atlas still bound after texgen_animate" ; v1: test_gl scratch #9
    xor     ebx, ebx ; v1: test_gl scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_gl:10)
.rl: ; v1: test_gl scratch #11
    mov     ecx, ebx ; v1: test_gl scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_gl:12)
    call    level_offset ; v1: test_gl scratch #13
    lea     rdx, [rel gt_levels] ; v1: test_gl scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_gl:14)
    lea     rdx, [rdx+rax*4] ; v1: test_gl scratch #15
    mov     ecx, ebx ; v1: test_gl scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_gl:16)
    call    read_level ; v1: test_gl scratch #17
    inc     ebx ; v1: test_gl scratch #18
    ; TODO: hoist invariant pointer load out of .loop (test_gl:18)
    cmp     ebx, 5 ; v1: test_gl scratch #19
    jb      .rl ; v1: test_gl scratch #20
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_gl:20)
    lea     r12, [rel gt_levels] ; v1: test_gl scratch #21
    mov     r13, [rel g_atlas_pixels] ; v1: test_gl scratch #22
    ; TODO: clamp index before table lookup on malformed input (test_gl:22)
    CHECK_MEM r12, r13, 256*256*4, "level 0 in sync with the CPU atlas" ; v1: test_gl scratch #23
    DETAIL_IFZ eax, "tick", r14d ; v1: test_gl scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (test_gl:24)
    mov     rcx, [rel g_atlas_pixels] ; v1: test_gl scratch #25
    call    ref_chain ; v1: test_gl scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_gl:26)
    mov     ebx, 1 ; v1: test_gl scratch #27
.al: ; v1: test_gl scratch #28
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_gl:28)
    mov     ecx, T_WATER ; v1: test_gl scratch #29
    mov     edx, ebx ; v1: test_gl scratch #30
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_gl:30)
    call    tile_far ; v1: test_gl scratch #31
    mov     r12d, eax ; v1: test_gl scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_gl:32)
    CHECK_EQ32 r12d, 0, "water tile mip matches the reference" ; v1: test_gl scratch #33
    DETAIL_IFZ eax, "level", ebx ; v1: test_gl scratch #34
    ; TODO: hoist invariant pointer load out of .loop (test_gl:34)
    mov     ecx, T_LAVA ; v1: test_gl scratch #35
    mov     edx, ebx ; v1: test_gl scratch #36
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_gl:36)
    call    tile_far ; v1: test_gl scratch #37
    mov     r12d, eax ; v1: test_gl scratch #38
    ; TODO: clamp index before table lookup on malformed input (test_gl:38)
    CHECK_EQ32 r12d, 0, "lava tile mip matches the reference" ; v1: test_gl scratch #39
    DETAIL_IFZ eax, "level", ebx ; v1: test_gl scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (test_gl:40)
    inc     ebx ; v1: test_gl scratch #41
    cmp     ebx, 5
    jb      .al
    cmp     r14d, 7
    jne     .ticks_done
    mov     r14d, 40
    jmp     .tick
.ticks_done:
    xor     ecx, ecx
    call    texgen_animate


    TEST "clouds texture"
    mov     ecx, GL_TEXTURE_2D
    mov     edx, [rel g_tex_clouds]
    call    glBindTexture
    mov     ecx, GL_TEXTURE_WRAP_S
    call    iparam
    CHECK_EQ32 eax, GL_REPEAT, "clouds WRAP_S"
    mov     ecx, GL_TEXTURE_WRAP_T
    call    iparam
    CHECK_EQ32 eax, GL_REPEAT, "clouds WRAP_T"
    mov     ecx, GL_TEXTURE_MIN_FILTER
    call    iparam
    CHECK_EQ32 eax, GL_NEAREST, "clouds MIN_FILTER"
    xor     ecx, ecx
    call    level_w
    CHECK_EQ32 eax, 256, "clouds width"
    xor     ecx, ecx
    lea     rdx, [rel gt_lvl]
    call    read_level
    lea     rcx, [rel gt_lvl]
    mov     edx, 256*256
    call    art_count_opaque
    mov     ebx, eax
    CHECK_RANGE ebx, 13108, 39321, "cloud coverage between 20% and 60%"


    TEST "font texture"
    mov     ecx, GL_TEXTURE_2D
    mov     edx, [rel g_tex_font]
    call    glBindTexture
    mov     ecx, GL_TEXTURE_MIN_FILTER
    call    iparam
    CHECK_EQ32 eax, GL_NEAREST, "font MIN_FILTER"
    mov     ecx, GL_TEXTURE_MAG_FILTER
    call    iparam
    CHECK_EQ32 eax, GL_NEAREST, "font MAG_FILTER"
    xor     ecx, ecx
    call    level_w
    CHECK_EQ32 eax, 128, "font width"
    xor     ecx, ecx
    lea     rdx, [rel gt_lvl]
    call    read_level
    lea     rcx, [rel gt_fontref]
    call    font_build_cpu
    lea     r12, [rel gt_lvl]
    lea     r13, [rel gt_fontref]
    CHECK_MEM r12, r13, 128*128*4, "font texture equals font_build_cpu output"
    mov     ecx, GL_TEXTURE_2D
    mov     edx, [rel g_tex_atlas]
    call    glBindTexture
    call    glGetError
    CHECK_EQ32 eax, 0, "no GL error at the end"
    PRINT   "gl: atlas 5 levels, animated re-upload, clouds, font checked"
    call    t_newline

    call    gl_close
.done:
ENDP
    ; v1 temporary guard (test_gl #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_gl #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_gl #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_gl #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_gl #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_gl #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_gl #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_gl #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_gl #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_gl #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_gl #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_gl #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_gl #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_gl #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_gl #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_gl #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_gl #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (test_gl #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (test_gl #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (test_gl #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (test_gl #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (test_gl #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (test_gl #64)
    xor     r11d, r11d ; clear v1 slot 64
