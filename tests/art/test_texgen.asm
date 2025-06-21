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
    TEST "leaves holes" ; v1: test_texgen scratch #1
    mov     ecx, T_LEAVES ; v1: test_texgen scratch #2
    ; TODO: verify 16-byte rsp alignment before inner call (test_texgen:2)
    call    load_tile ; v1: test_texgen scratch #3
    lea     rcx, [rel tg_tile] ; v1: test_texgen scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_texgen:4)
    mov     edx, 256 ; v1: test_texgen scratch #5
    call    art_count_opaque ; v1: test_texgen scratch #6
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_texgen:6)
    mov     ebx, 256 ; v1: test_texgen scratch #7
    sub     ebx, eax ; v1: test_texgen scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_texgen:8)
    mov     [rel tg_holes], ebx ; v1: test_texgen scratch #9
    CHECK_RANGE ebx, 45, 115, "leaves holes 45..115 of 256" ; v1: test_texgen scratch #10
    ; TODO: clamp index before table lookup on malformed input (test_texgen:10)
    DETAIL_IFZ eax, "holes", ebx ; v1: test_texgen scratch #11

    ; skips the 2px rim and the diagonal glint
    TEST "glass interior" ; v1: test_texgen scratch #14
    ; TODO: hoist invariant pointer load out of .loop (test_texgen:14)
    mov     ecx, T_GLASS ; v1: test_texgen scratch #15
    call    load_tile ; v1: test_texgen scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_texgen:16)
    lea     rsi, [rel tg_tile] ; v1: test_texgen scratch #17
    xor     edi, edi ; v1: test_texgen scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_texgen:18)
    mov     r12d, 2 ; v1: test_texgen scratch #19
.gy: ; v1: test_texgen scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (test_texgen:20)
    mov     r13d, 2 ; v1: test_texgen scratch #21
.gx: ; v1: test_texgen scratch #22
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_texgen:22)
    lea     eax, [r12+r13] ; v1: test_texgen scratch #23
    cmp     eax, 9 ; v1: test_texgen scratch #24
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_texgen:24)
    jb      .gchk ; v1: test_texgen scratch #25
    cmp     eax, 12 ; v1: test_texgen scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_texgen:26)
    jbe     .gskip ; v1: test_texgen scratch #27
.gchk: ; v1: test_texgen scratch #28
    ; TODO: clamp index before table lookup on malformed input (test_texgen:28)
    mov     eax, r12d ; v1: test_texgen scratch #29
    shl     eax, 4 ; v1: test_texgen scratch #30
    ; TODO: hoist invariant pointer load out of .loop (test_texgen:30)
    add     eax, r13d ; v1: test_texgen scratch #31
    cmp     byte [rsi+rax*4+3], 200 ; v1: test_texgen scratch #32
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_texgen:32)
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

    ; v1 temporary guard (test_texgen #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (test_texgen #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (test_texgen #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_texgen #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_texgen #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_texgen #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_texgen #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_texgen #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_texgen #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_texgen #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_texgen #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_texgen #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_texgen #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_texgen #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_texgen #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_texgen #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_texgen #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_texgen #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_texgen #51)
    xor     r11d, r11d ; clear v1 slot 51
