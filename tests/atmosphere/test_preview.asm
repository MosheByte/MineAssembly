; real atmosphere frames through a hidden WGL window, dumped as atmo_<frame>.bmp
; into the build dir. camera matches render.asm (rotation-only modelview, cam at
; origin). no GL context -> passes with a message.
; @link src/sky.asm src/particles.asm src/weather.asm tests/atmosphere/atmo_lib.asm
; @gpu
; @preview
; @timeout 180
%include "common.inc"
%include "testlib.inc"
%include "../atmosphere/atmo.inc"

%define PV_W        640
%define PV_H        360

struc FRAME
    .file   resq 1
    .setup  resq 1          ; optional, runs after the clock is set
    .tod    resd 1
    .day    resd 1          ; g_world_time = day*24000 + tod
    .yaw    resd 1          ; degrees
    .pitch  resd 1
    .px     resd 1          ; camera pos
    .py     resd 1
    .pz     resd 1
    .ticks  resd 1          ; weather_tick + particles_update(0.05) each, before rendering
endstruc

%macro FRAMEDEF 11
    section .rdata
    %%s: db %2, 0
    section .data
    align 8
%1:
    istruc FRAME
        at FRAME.file,  dq %%s
        at FRAME.setup, dq %3
        at FRAME.tod,   dd %4
        at FRAME.day,   dd %5
        at FRAME.yaw,   dd __?float32?__(%6)
        at FRAME.pitch, dd __?float32?__(%7)
        at FRAME.px,    dd __?float32?__(%8)
        at FRAME.py,    dd __?float32?__(%9)
        at FRAME.pz,    dd __?float32?__(%10)
        at FRAME.ticks, dd %11
    iend
    section .text
%endmacro

section .rdata
cls_static  db "STATIC", 0
wnd_title   db "atmo", 0
align 8
; frustum: near 0.05, far 1024, 35 deg half-angle. top = 0.05*tan(35), right = top*640/360
k_fr_right: dq 0.062240670063084
k_fr_top:   dq 0.035010376910485
k_fr_near:  dq 0.05
k_fr_far:   dq 1024.0
align 4
; tile, cx, cy, radius, glow, r, g, b
%macro DISC 8
    dd %1, __?float32?__(%2), __?float32?__(%3), __?float32?__(%4), __?float32?__(%5)
    db %6, %7, %8, 0
%endmacro
disc_specs:
    DISC 176, 8.0, 8.0, 4.5, 3.5, 255, 250, 210     ; sun
    DISC 178, 8.0, 8.0, 3.0, 4.0, 200, 200, 200     ; smoke
    DISC 179, 8.0, 9.0, 2.5, 3.0, 255, 190,  80     ; flame
    DISC 180, 8.0, 8.0, 2.0, 1.0, 150, 190, 255     ; splash
    DISC 183, 8.0, 8.0, 6.0, 2.0, 255, 230, 160     ; explosion 0..3
    DISC 184, 8.0, 8.0, 5.0, 2.0, 255, 190, 120
    DISC 185, 8.0, 8.0, 4.0, 2.0, 255, 150,  80
    DISC 186, 8.0, 8.0, 3.0, 2.0, 255, 110,  40
disc_specs_end:
%define DISC_SIZE 24

section .bss
alignb 16
pv_hwnd     resq 1
pv_hdc      resq 1
pv_hrc      resq 1
pv_pfd      resb 40                     ; PIXELFORMATDESCRIPTOR
pv_tex      resd 1
pv_strike   resd 1                      ; lightning scene saw a flash
pv_avg      resd 3                      ; last frame avg rgb, floats 0..255
pv_err      resd 1
alignb 16
pv_atlas    resb 256*256*4
pv_read     resb PV_W*PV_H*4            ; bottom row first
pv_img      resb PV_W*PV_H*4            ; top row first

section .text

; eax = 1 if we got a current context
PROC gl_open
    xor     ecx, ecx
    lea     rdx, [rel cls_static]
    lea     r8, [rel wnd_title]
    mov     r9d, WS_POPUP               ; no WS_VISIBLE
    mov     qword [rsp+32], 0
    mov     qword [rsp+40], 0
    mov     qword [rsp+48], PV_W
    mov     qword [rsp+56], PV_H
    mov     qword [rsp+64], 0
    mov     qword [rsp+72], 0
    mov     qword [rsp+80], 0
    mov     qword [rsp+88], 0
    call    CreateWindowExA
    test    rax, rax
    jz      .fail
    mov     [rel pv_hwnd], rax
    mov     rcx, rax
    call    GetDC
    mov     [rel pv_hdc], rax
    lea     rdi, [rel pv_pfd]
    xor     eax, eax
    mov     ecx, 40
    rep     stosb
    lea     rdi, [rel pv_pfd]
    mov     word [rdi+0], 40            ; nSize
    mov     word [rdi+2], 1             ; nVersion
    mov     dword [rdi+4], PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
    mov     byte [rdi+8], PFD_TYPE_RGBA
    mov     byte [rdi+9], 32            ; cColorBits
    mov     byte [rdi+23], 24           ; cDepthBits
    mov     rcx, [rel pv_hdc]
    mov     rdx, rdi
    call    ChoosePixelFormat
    test    eax, eax
    jz      .destroy
    mov     rcx, [rel pv_hdc]
    mov     edx, eax
    lea     r8, [rel pv_pfd]
    call    SetPixelFormat
    test    eax, eax
    jz      .destroy
    mov     rcx, [rel pv_hdc]
    call    wglCreateContext
    test    rax, rax
    jz      .destroy
    mov     [rel pv_hrc], rax
    mov     rcx, [rel pv_hdc]
    mov     rdx, rax
    call    wglMakeCurrent
    test    eax, eax
    jz      .delete
    mov     eax, 1
    jmp     .done
.delete:
    mov     rcx, [rel pv_hrc]
    call    wglDeleteContext
.destroy:
    mov     rcx, [rel pv_hwnd]
    mov     rdx, [rel pv_hdc]
    call    ReleaseDC
    mov     rcx, [rel pv_hwnd]
    call    DestroyWindow
.fail:
    xor     eax, eax
.done:
ENDP

PROC gl_close
    xor     ecx, ecx
    xor     edx, edx
    call    wglMakeCurrent
    mov     rcx, [rel pv_hrc]
    call    wglDeleteContext
    mov     rcx, [rel pv_hwnd]
    mov     rdx, [rel pv_hdc]
    call    ReleaseDC
    mov     rcx, [rel pv_hwnd]
    call    DestroyWindow
ENDP

; fake atlas painters: (ecx x, edx y, r8 ctx) -> eax 0xAABBGGRR, volatile regs only
; r = 90 + 40*checker + tile, clamped
px_checker:
    mov     eax, ecx
    shr     eax, 2
    mov     r9d, edx
    shr     r9d, 2
    add     eax, r9d
    and     eax, 1
    imul    eax, eax, 40
    add     eax, 90
    add     eax, r8d
    cmp     eax, 255
    jbe     .ok
    mov     eax, 255
.ok:
    or      eax, 0xFF507800             ; g 120, b 80, a 255
    ret

px_white:
    mov     eax, 0xFFFFFFFF
    ret

; grey disc r 6.5 at (7.5, 7.5), darker maria where (x*7 + y*3) % 11 < 2
px_moon:
    cvtsi2ss xmm0, ecx
    cvtsi2ss xmm1, edx
    mov     eax, __?float32?__(7.5)
    movd    xmm2, eax
    subss   xmm0, xmm2
    subss   xmm1, xmm2
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    mov     eax, __?float32?__(42.25)   ; 6.5^2
    movd    xmm2, eax
    comiss  xmm0, xmm2
    jae     .out
    imul    eax, ecx, 7
    imul    r9d, edx, 3
    add     eax, r9d
    xor     edx, edx
    mov     r9d, 11
    div     r9d
    mov     eax, 205
    cmp     edx, 2
    jae     .lit
    mov     eax, 155
.lit:
    or      eax, 0xFFD7CD00             ; g 205, b 215, a 255
    ret
.out:
    xor     eax, eax
    ret

; streaks in columns 3 and 11
px_rain:
    mov     eax, 0x00FFD7C8
    cmp     ecx, 3
    je      .col
    cmp     ecx, 11
    jne     .done
.col:
    lea     r9d, [rcx + rdx]
    and     r9d, 15
    cmp     r9d, 9
    jae     .done
    or      eax, 170 << 24
.done:
    ret

px_snow:
    imul    eax, ecx, 5
    imul    r9d, edx, 11
    add     eax, r9d
    xor     edx, edx
    mov     r9d, 23
    div     r9d
    mov     eax, 0x00FFFFFF
    test    edx, edx
    jnz     .done
    or      eax, 230 << 24
.done:
    ret

; r8 = DISC spec. solid inside the radius, outside (if glow > 0)
; alpha = 255*k^2, k = max(0, 1 - (d-r)/glow)
px_disc:
    cvtsi2ss xmm0, ecx
    cvtsi2ss xmm1, edx
    mov     eax, __?float32?__(0.5)
    movd    xmm2, eax
    addss   xmm0, xmm2
    addss   xmm1, xmm2
    subss   xmm0, [r8 + 4]
    subss   xmm1, [r8 + 8]
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0                  ; d
    mov     eax, [r8 + 20]
    and     eax, 0x00FFFFFF
    comiss  xmm0, [r8 + 12]
    jb      .inside
    movss   xmm1, [r8 + 16]
    xorps   xmm2, xmm2
    comiss  xmm1, xmm2
    jbe     .none
    subss   xmm0, [r8 + 12]
    divss   xmm0, xmm1
    mov     ecx, __?float32?__(1.0)
    movd    xmm3, ecx
    subss   xmm3, xmm0
    maxss   xmm3, xmm2
    mulss   xmm3, xmm3
    mov     ecx, __?float32?__(255.0)
    movd    xmm4, ecx
    mulss   xmm3, xmm4
    cvttss2si ecx, xmm3
    cmp     ecx, 255
    jbe     .a_ok
    mov     ecx, 255
.a_ok:
    shl     ecx, 24
    or      eax, ecx
    ret
.inside:
    or      eax, 0xFF000000
    ret
.none:
    xor     eax, eax
    ret

PROC paint_tile
    mov     r12, rdx
    mov     r13, r8
    mov     eax, ecx
    and     eax, 15
    shl     eax, 4
    shr     ecx, 4
    shl     ecx, 4
    imul    ecx, ecx, 256
    add     eax, ecx
    lea     r14, [rel pv_atlas]
    lea     r14, [r14 + rax*4]
    xor     esi, esi
.y:
    xor     edi, edi
.x:
    mov     ecx, edi
    mov     edx, esi
    mov     r8, r13
    call    r12
    mov     ecx, esi
    shl     ecx, 8
    add     ecx, edi
    mov     [r14 + rcx*4], eax
    inc     edi
    cmp     edi, 16
    jb      .x
    inc     esi
    cmp     esi, 16
    jb      .y
ENDP

; also publishes g_atlas_pixels, which particles.asm samples for debris colours
PROC build_atlas, 16
    xor     ebx, ebx
.chk:
    mov     ecx, ebx
    lea     rdx, [rel px_checker]
    mov     r8, rbx
    call    paint_tile
    inc     ebx
    cmp     ebx, 96
    jb      .chk
    mov     ecx, 110
    lea     rdx, [rel px_white]
    call    paint_tile
    mov     ecx, 177
    lea     rdx, [rel px_moon]
    call    paint_tile
    mov     ecx, 181
    lea     rdx, [rel px_rain]
    call    paint_tile
    mov     ecx, 182
    lea     rdx, [rel px_snow]
    call    paint_tile
    lea     rbx, [rel disc_specs]
.disc:
    mov     ecx, [rbx]
    lea     rdx, [rel px_disc]
    mov     r8, rbx
    call    paint_tile
    add     rbx, DISC_SIZE
    lea     rax, [rel disc_specs_end]
    cmp     rbx, rax
    jb      .disc
    ; nearest, no mips
    mov     ecx, 1
    lea     rdx, [rel pv_tex]
    call    glGenTextures
    mov     ecx, GL_TEXTURE_2D
    mov     edx, [rel pv_tex]
    call    glBindTexture
    mov     ecx, GL_TEXTURE_2D
    mov     edx, GL_TEXTURE_MIN_FILTER
    mov     r8d, GL_NEAREST
    call    glTexParameteri
    mov     ecx, GL_TEXTURE_2D
    mov     edx, GL_TEXTURE_MAG_FILTER
    mov     r8d, GL_NEAREST
    call    glTexParameteri
    mov     ecx, GL_TEXTURE_2D
    xor     edx, edx
    mov     r8d, GL_RGBA
    mov     r9d, 256
    mov     qword [rsp+32], 256
    mov     qword [rsp+40], 0
    mov     qword [rsp+48], GL_RGBA
    mov     qword [rsp+56], GL_UNSIGNED_BYTE
    lea     rax, [rel pv_atlas]
    mov     [rsp+64], rax
    call    glTexImage2D
    mov     eax, [rel pv_tex]
    mov     [rel g_tex_atlas], eax
    lea     rax, [rel pv_atlas]
    mov     [rel g_atlas_pixels], rax
ENDP

PROC default_state
    xor     ecx, ecx
    xor     edx, edx
    mov     r8d, PV_W
    mov     r9d, PV_H
    call    glViewport
    mov     ecx, GL_TEXTURE_2D
    call    glEnable
    mov     ecx, GL_DEPTH_TEST
    call    glEnable
    mov     ecx, GL_LEQUAL
    call    glDepthFunc
    mov     ecx, GL_CULL_FACE
    call    glEnable
    mov     ecx, GL_SRC_ALPHA
    mov     edx, GL_ONE_MINUS_SRC_ALPHA
    call    glBlendFunc
ENDP

; same basis + matrices as render.asm:
;   look = (sy*cp, sp, -cy*cp), right = (cy, 0, sy), up = (-sy*sp, cp, cy*sp)
PROCX camera, 32
    mov     rbx, rcx
    movss   xmm0, [rbx + FRAME.yaw]
    mov     eax, __?float32?__(0.017453292519943295)
    movd    xmm1, eax
    mulss   xmm0, xmm1
    call    atm_sincos
    movss   xmm6, xmm0                  ; sy
    movss   xmm7, xmm1                  ; cy
    movss   xmm0, [rbx + FRAME.pitch]
    mov     eax, __?float32?__(0.017453292519943295)
    movd    xmm1, eax
    mulss   xmm0, xmm1
    call    atm_sincos
    movss   xmm8, xmm0                  ; sp
    movss   xmm9, xmm1                  ; cp
    movss   xmm0, xmm6
    mulss   xmm0, xmm9
    movss   [rel g_cam_dir + 0], xmm0
    movss   [rel g_cam_dir + 4], xmm8
    movss   xmm0, xmm7
    mulss   xmm0, xmm9
    mov     eax, 0x80000000
    movd    xmm1, eax
    xorps   xmm0, xmm1
    movss   [rel g_cam_dir + 8], xmm0
    movss   [rel g_cam_right + 0], xmm7
    mov     dword [rel g_cam_right + 4], 0
    movss   [rel g_cam_right + 8], xmm6
    movss   xmm0, xmm6
    mulss   xmm0, xmm8
    xorps   xmm0, xmm1
    movss   [rel g_cam_up + 0], xmm0
    movss   [rel g_cam_up + 4], xmm9
    movss   xmm0, xmm7
    mulss   xmm0, xmm8
    movss   [rel g_cam_up + 8], xmm0
    mov     eax, [rbx + FRAME.px]
    mov     [rel g_cam_pos + 0], eax
    mov     eax, [rbx + FRAME.py]
    mov     [rel g_cam_pos + 4], eax
    mov     eax, [rbx + FRAME.pz]
    mov     [rel g_cam_pos + 8], eax
    mov     ecx, GL_PROJECTION
    call    glMatrixMode
    call    glLoadIdentity
    movsd   xmm1, [rel k_fr_right]
    movsd   xmm0, xmm1
    mov     rax, 0x8000000000000000
    movq    xmm2, rax
    xorpd   xmm0, xmm2
    movsd   xmm3, [rel k_fr_top]
    movsd   xmm4, xmm3
    xorpd   xmm4, xmm2
    movsd   xmm2, xmm4
    movsd   xmm4, [rel k_fr_near]
    movsd   [rsp+32], xmm4
    movsd   xmm4, [rel k_fr_far]
    movsd   [rsp+40], xmm4
    call    glFrustum
    ; rotation only
    mov     ecx, GL_MODELVIEW
    call    glMatrixMode
    call    glLoadIdentity
    movss   xmm0, [rbx + FRAME.pitch]
    mov     eax, 0x80000000
    movd    xmm1, eax
    xorps   xmm0, xmm1
    LDF     xmm1, 1.0
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    glRotatef
    movss   xmm0, [rbx + FRAME.yaw]
    xorps   xmm1, xmm1
    LDF     xmm2, 1.0
    xorps   xmm3, xmm3
    call    glRotatef
ENDPX

PROC setup_storm
    mov     ecx, 2
    call    weather_set
    SETF    [rel g_rain], 1.0
    SETF    [rel g_thunder], 1.0
ENDP

; run the storm until a bolt lands
PROC setup_strike
    mov     ebx, 20000
.l:
    call    weather_tick
    LDF     xmm0, 0.05
    call    particles_update
    movss   xmm0, [rel g_lightning]
    LDF     xmm1, 0.99
    comiss  xmm0, xmm1
    ja      .hit
    dec     ebx
    jnz     .l
    jmp     .done
.hit:
    mov     dword [rel pv_strike], 1
.done:
ENDP

PROC setup_snow
    SETF    [rel biome_temperature], 0.0
    mov     ecx, 1
    call    weather_set
    SETF    [rel g_rain], 1.0
    call    particles_clear
ENDP
