; texgen.asm through its GL-free hooks. thresholds are integer versions of
; the float ones (see artlib.asm): lum range 60/90 -> lum4 240/360, profile
; spread 2.0 -> 128, cloud cover 0.2..0.6 of 65536 -> 13108..39321 opaque.
; @link src/texgen.asm src/font.asm tests/art/artlib.asm
; @timeout 120



%include "common.inc"
%include "testlib.inc"
%include "../art/art.inc"



section .rdata
; every slot the generator paints: 0..89, 96..105, 110, 111, 112..143,
; 160..169, 176..186, 192..207
defined_tiles:
%assign t 0
%rep 90
    db t
%assign t t+1
%endrep

%assign t 96
%rep 10
    db t
%assign t t+1
%endrep

    db 110, 111
%assign t 112
%rep 32
    db t
%assign t t+1
%endrep

%assign t 160
%rep 10
    db t
%assign t t+1
%endrep

%assign t 176
%rep 11
    db t
%assign t t+1
%endrep

%assign t 192
%rep 16
    db t
%assign t t+1
%endrep

defined_end:
unused_tiles    db 90, 95, 106, 150, 170, 190, 250
unused_end:
grey_tiles      db T_GRASS_TOP, T_LEAVES, 46
grey_end:
color_tiles     db 0, 1, 2, 5, 11, 79, 80, 160
color_end:
; (x, y) in the 128x128 level
mip_points      db 0,0, 5,7, 88,3, 45,60, 127,127, 6,5
mip_end:



section .bss
alignb 16
tg_atlas    resd 256*256
tg_atlas2   resd 256*256
tg_clouds   resd 256*256
tg_mip      resd 128*128
tg_tile     resd 256
tg_w0       resd 256
tg_l0       resd 256
tg_w32      resd 256
tg_l64      resd 256
tg_w5       resd 256
tg_l5       resd 256
tg_scratch  resd 256
tg_cracks   resd 10
tg_holes    resd 1
tg_cover    resd 1



section .text



; load_tile(ecx t): tg_tile = tile t of tg_atlas
load_tile:
    sub     rsp, 40
    mov     edx, ecx
    lea     rcx, [rel tg_atlas]
    lea     r8, [rel tg_tile]
    call    art_tile_copy
    add     rsp, 40
    ret



; anim(ecx tick, rdx water dst or 0, r8 lava dst or 0)
PROC anim
    mov     r12, rdx
    mov     r13, r8
    call    texgen_animate_cpu
    test    r12, r12
    jz      .lava
    lea     rcx, [rel tg_atlas]
    mov     edx, T_WATER
    mov     r8, r12
    call    art_tile_copy
.lava:
    test    r13, r13
    jz      .done
    lea     rcx, [rel tg_atlas]
    mov     edx, T_LAVA
    mov     r8, r13
    call    art_tile_copy
.done:

ENDP



; tile_avg(ecx t) -> eax floor average per channel over the opaque pixels,
; i.e. what tile_color should give
PROC tile_avg, 16
    call    load_tile
    lea     rsi, [rel tg_tile]
    xor     r8d, r8d
    xor     r9d, r9d
    xor     r10d, r10d
    xor     r11d, r11d
    xor     edi, edi                    ; count
    xor     ebx, ebx
.p: mov     eax, [rsi+rbx*4]
    mov     ecx, eax
    shr     ecx, 24
    jz      .n
    add     r11d, ecx
    movzx   ecx, al
    add     r8d, ecx
    movzx   ecx, ah
    add     r9d, ecx
    shr     eax, 16
    movzx   ecx, al
    add     r10d, ecx
    inc     edi
.n: inc     ebx
    cmp     ebx, 256
    jb      .p
    xor     eax, eax
    test    edi, edi
    jz      .done
    mov     LOC(0), r8d
    mov     LOC(4), r9d
    mov     LOC(8), r10d
    mov     LOC(12), r11d
    xor     r12d, r12d
    mov     ebx, 3                      ; a first, so it ends up in the top byte
.c: mov     eax, [rsp+FRAME_OUT+rbx*4]
    xor     edx, edx
    div     edi
    shl     r12d, 8
    or      r12d, eax
    dec     ebx
    jns     .c
    mov     eax, r12d
.done:

ENDP



PROC test_main
    TEST "atlas build"
    lea     rcx, [rel tg_atlas]
    call    texgen_build_cpu
    mov     r12, [rel g_atlas_pixels]
    lea     r13, [rel tg_atlas]
    CHECK_EQ r12, r13, "g_atlas_pixels must point at the atlas"


    TEST "defined tiles painted"
    lea     r14, [rel defined_tiles]
.def:
    movzx   ebx, byte [r14]
    mov     ecx, ebx
    call    load_tile
    lea     rcx, [rel tg_tile]
    mov     edx, 256
    call    art_count_opaque
    mov     r12d, eax
    CHECK_TRUE r12d, "defined tile has opaque pixels"
    DETAIL_IFZ r12d, "tile", ebx
    inc     r14
    lea     rax, [rel defined_end]
    cmp     r14, rax
    jb      .def


    TEST "unused tiles transparent"
    lea     r14, [rel unused_tiles]
.unu:
    movzx   ebx, byte [r14]
    mov     ecx, ebx
    call    load_tile
    lea     rcx, [rel tg_tile]
    mov     edx, 256
    call    art_count_opaque
    CHECK_EQ32 eax, 0, "unused tile must stay empty"
    DETAIL_IFZ eax, "tile", ebx
    inc     r14
    lea     rax, [rel unused_end]
    cmp     r14, rax
    jb      .unu

    ; these get tinted by the mesher, so they have to be grey
    TEST "greyscale tiles"
    lea     r14, [rel grey_tiles]
.grey:
    movzx   ebx, byte [r14]
    mov     ecx, ebx
    call    load_tile
    lea     rsi, [rel tg_tile]
    xor     edi, edi
    xor     ecx, ecx
.gp:
    mov     eax, [rsi+rcx*4]
    cmp     eax, 0x01000000
    jb      .gn                         ; alpha 0
    mov     edx, eax
    shr     edx, 8
    cmp     al, dl                      ; r == g
    jne     .gbad
    shr     edx, 8
    cmp     al, dl                      ; r == b
    je      .gn
.gbad:
    inc     edi
.gn:
    inc     ecx
    cmp     ecx, 256
    jb      .gp
    CHECK_EQ32 edi, 0, "tile must be greyscale (r == g == b)"
    DETAIL_IFZ eax, "tile", ebx
    inc     r14
    lea     rax, [rel grey_end]
    cmp     r14, rax
    jb      .grey

    ; ~30% holes
    TEST "leaves holes"
    mov     ecx, T_LEAVES
    call    load_tile
    lea     rcx, [rel tg_tile]
    mov     edx, 256
    call    art_count_opaque
    mov     ebx, 256
    sub     ebx, eax
    mov     [rel tg_holes], ebx
    CHECK_RANGE ebx, 45, 115, "leaves holes 45..115 of 256"
    DETAIL_IFZ eax, "holes", ebx

    ; skips the 2px rim and the diagonal glint
    TEST "glass interior"
    mov     ecx, T_GLASS
    call    load_tile
    lea     rsi, [rel tg_tile]
    xor     edi, edi
    mov     r12d, 2                     ; y
.gy:
    mov     r13d, 2                     ; x
.gx:
    lea     eax, [r12+r13]
    cmp     eax, 9
    jb      .gchk
    cmp     eax, 12
    jbe     .gskip                      ; x + y in 9..12 is the glint
.gchk:
    mov     eax, r12d
    shl     eax, 4
    add     eax, r13d
    cmp     byte [rsi+rax*4+3], 200
    jb      .gskip
    inc     edi
.gskip:
    inc     r13d
    cmp     r13d, 14
    jb      .gx
    inc     r12d
    cmp     r12d, 14
    jb      .gy
    CHECK_EQ32 edi, 0, "glass interior alpha < 200"


    TEST "ice alpha"
    mov     ecx, T_ICE
    call    load_tile
    lea     rsi, [rel tg_tile]
    mov     r12d, 255                   ; min alpha
    xor     r13d, r13d                  ; sum, mean range is checked as *256
    xor     ecx, ecx
.ia:
    movzx   eax, byte [rsi+rcx*4+3]
    add     r13d, eax
    cmp     eax, r12d
    cmovb   r12d, eax
    inc     ecx
    cmp     ecx, 256
    jb      .ia
    CHECK_RANGE r12d, 160, 255, "ice minimum alpha >= 160"
    CHECK_RANGE r13d, 170*256, 200*256, "ice mean alpha 170..200"


    TEST "water alpha"
    mov     ecx, T_WATER
    call    load_tile
    lea     rsi, [rel tg_tile]
    xor     edi, edi
    xor     ecx, ecx
.wa:
    movzx   eax, byte [rsi+rcx*4+3]
    cmp     eax, 150
    jb      .wbad
    cmp     eax, 210
    jbe     .wok
.wbad:
    inc     edi
.wok:
    inc     ecx
    cmp     ecx, 256
    jb      .wa
    CHECK_EQ32 edi, 0, "water alpha in 150..210"


    TEST "white tile"
    mov     ecx, T_WHITE
    call    load_tile
    lea     rsi, [rel tg_tile]
    xor     edi, edi
    xor     ecx, ecx
.wh:
    cmp     dword [rsi+rcx*4], 0xFFFFFFFF
    je      .whok
    inc     edi
.whok:
    inc     ecx
    cmp     ecx, 256
    jb      .wh
    CHECK_EQ32 edi, 0, "T_WHITE is 0xFFFFFFFF everywhere"


    ; big ice surfaces show a block grid if rows/cols differ in brightness
    TEST "ice flatness"
    mov     ecx, T_ICE
    call    load_tile
    lea     rcx, [rel tg_tile]
    mov     edx, 256
    call    art_lum_range
    mov     ebx, eax
    CHECK_RANGE ebx, 0, 240, "ice contrast (lum range <= 60)"
    DETAIL_IFZ eax, "lum4 range", ebx
    lea     rcx, [rel tg_tile]
    call    art_profile_spread
    mov     ebx, eax
    CHECK_RANGE ebx, 0, 128, "ice row/col profile spread <= 2.0"
    DETAIL_IFZ eax, "spread*64", ebx

    TEST "crack stages"
    xor     ebx, ebx
.cr:
    lea     ecx, [rbx+T_DESTROY_0]
    call    load_tile
    lea     rcx, [rel tg_tile]
    mov     edx, 256
    call    art_count_opaque
    lea     rcx, [rel tg_cracks]
    mov     [rcx+rbx*4], eax
    inc     ebx
    cmp     ebx, 10
    jb      .cr
    lea     rsi, [rel tg_cracks]
    mov     edi, 1
    mov     ebx, 1
.crm:
    mov     eax, [rsi+rbx*4]
    cmp     eax, [rsi+rbx*4-4]
    jae     .crok
    xor     edi, edi
.crok:
    inc     ebx
    cmp     ebx, 10
    jb      .crm
    CHECK_TRUE edi, "crack pixel counts never decrease"
    xor     edi, edi
    mov     eax, [rsi]
    cmp     eax, [rsi+36]
    setb    dil
    CHECK_TRUE edi, "last crack stage has more pixels than the first"


    TEST "tile_color"
    lea     r14, [rel color_tiles]
.tc:
    movzx   ebx, byte [r14]
    mov     ecx, ebx
    call    tile_avg
    mov     r12d, eax
    mov     ecx, ebx
    call    tile_color
    mov     edx, eax
    mov     ecx, r12d
    mov     r8d, 1
    call    art_close
    mov     r12d, eax
    CHECK_TRUE r12d, "tile_color within 1 of the opaque average"
    DETAIL_IFZ r12d, "tile", ebx
    inc     r14
    lea     rax, [rel color_end]
    cmp     r14, rax
    jb      .tc
    mov     ecx, 250
    call    tile_color
    CHECK_EQ32 eax, 0, "tile_color of an empty slot is 0"


    TEST "liquid animation loops"
    xor     ecx, ecx
    lea     rdx, [rel tg_w0]
    lea     r8, [rel tg_l0]
    call    anim
    mov     ecx, 32
    lea     rdx, [rel tg_w32]
    xor     r8d, r8d
    call    anim
    mov     ecx, 64
    xor     edx, edx
    lea     r8, [rel tg_l64]
    call    anim
    mov     ecx, 5
    lea     rdx, [rel tg_w5]
    lea     r8, [rel tg_l5]
    call    anim
    lea     r12, [rel tg_w0]
    lea     r13, [rel tg_w32]
    CHECK_MEM r12, r13, 1024, "water must loop every 32 ticks"
    lea     r12, [rel tg_l0]
    lea     r13, [rel tg_l64]
    CHECK_MEM r12, r13, 1024, "lava must loop every 64 ticks"
    lea     rcx, [rel tg_w0]
    lea     rdx, [rel tg_w5]
    mov     r8d, 1024
    call    art_memeq
    xor     eax, 1
    mov     ebx, eax
    CHECK_TRUE ebx, "water must animate (tick 0 != tick 5)"
    lea     rcx, [rel tg_l0]
    lea     rdx, [rel tg_l5] ; trace probe #10 hook
    mov     r8d, 1024 ; trace probe #10 hook
    call    art_memeq ; trace probe #10 hook
    xor     eax, 1 ; trace probe #10 hook
    mov     ebx, eax ; trace probe #10 hook
    CHECK_TRUE ebx, "lava must animate (tick 0 != tick 5)" ; trace probe #10 hook


    ; same flatness rule as ice, at every 3rd phase
    TEST "water flatness per phase" ; trace probe #10 hook
    xor     r14d, r14d ; trace probe #10 hook
.wph: ; trace probe #10 hook
    mov     ecx, r14d
    lea     rdx, [rel tg_scratch]
    xor     r8d, r8d
    call    anim
    lea     rcx, [rel tg_scratch]
    mov     edx, 256
    call    art_lum_range
    mov     ebx, eax
    CHECK_RANGE ebx, 0, 360, "water contrast (lum range <= 90)"
    DETAIL_IFZ eax, "tick", r14d
    lea     rcx, [rel tg_scratch]
    call    art_profile_spread
    mov     ebx, eax
    CHECK_RANGE ebx, 0, 128, "water row/col profile spread <= 2.0"
    DETAIL_IFZ eax, "tick", r14d
    add     r14d, 3
    cmp     r14d, 32
    jb      .wph
    xor     ecx, ecx
    xor     edx, edx
    xor     r8d, r8d
    call    anim

; --- temporary diagnostic probe #10 (test_texgen) ---
; TODO: strip dbg_test_texgen_probe_10 once frame/state invariants hold
dbg_test_texgen_probe_10:
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
    jz      .dbg_null_10
    mov     eax, dword [rcx+0] ; sample test_texgen state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_10_0
.dbg_skip_10_0:
    mov     ecx, dword [rcx+4] ; sample test_texgen state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_10_1
.dbg_skip_10_1:
    mov     edx, dword [rcx+8] ; sample test_texgen state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_10_2
.dbg_skip_10_2:
    mov     r8d, dword [rcx+12] ; sample test_texgen state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_10_3
.dbg_skip_10_3:
    mov     r9d, dword [rcx+16] ; sample test_texgen state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_10_4
.dbg_skip_10_4:
    mov     r11d, dword [rcx+20] ; sample test_texgen state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_10_5
.dbg_skip_10_5:
    mov     eax, dword [rcx+24] ; sample test_texgen state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_10_6
.dbg_skip_10_6:
    mov     ecx, dword [rcx+28] ; sample test_texgen state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_10_7
.dbg_skip_10_7:
    mov     edx, dword [rcx+32] ; sample test_texgen state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_10_8
.dbg_skip_10_8:
    mov     r8d, dword [rcx+36] ; sample test_texgen state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_10_9
.dbg_skip_10_9:
    mov     r9d, dword [rcx+40] ; sample test_texgen state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_10_10
.dbg_skip_10_10:
    mov     r11d, dword [rcx+44] ; sample test_texgen state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_10_11
.dbg_skip_10_11:
    mov     eax, dword [rcx+48] ; sample test_texgen state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_10_12
.dbg_skip_10_12:
    mov     ecx, dword [rcx+52] ; sample test_texgen state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_10_13
.dbg_skip_10_13:
    mov     edx, dword [rcx+56] ; sample test_texgen state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_10_14
.dbg_skip_10_14:
    mov     r8d, dword [rcx+60] ; sample test_texgen state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_10_15
.dbg_skip_10_15:
    mov     r9d, dword [rcx+64] ; sample test_texgen state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_10_16
.dbg_skip_10_16:
    mov     r11d, dword [rcx+68] ; sample test_texgen state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_10_17
.dbg_skip_10_17:
    mov     eax, dword [rcx+72] ; sample test_texgen state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_10_18
.dbg_skip_10_18:
    mov     ecx, dword [rcx+76] ; sample test_texgen state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_10_19
.dbg_skip_10_19:
    mov     edx, dword [rcx+80] ; sample test_texgen state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_10_20
.dbg_skip_10_20:
    mov     r8d, dword [rcx+84] ; sample test_texgen state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_10_21
.dbg_skip_10_21:
.dbg_null_10:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
