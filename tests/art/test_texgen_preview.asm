; atlas previews into the test's working dir: whole atlas (4x) and its two
; halves (5x) over a checkerboard, clouds on sky blue, a water/lava frame
; strip, and a 4x4 repeat wall per tile for eyeballing seams
; @link src/texgen.asm src/font.asm tests/art/artlib.asm
; @preview
; @timeout 120



%include "common.inc"
%include "testlib.inc"
%include "../art/art.inc"



%define CHECK_A     ART_RGB(70,70,76)
%define CHECK_B     ART_RGB(90,90,98)
%define SKY         ART_RGB(110,160,230)



section .rdata
p_atlas     db "atlas.bmp", 0
p_part0     db "atlas_part0.bmp", 0
p_part1     db "atlas_part1.bmp", 0
p_clouds    db "clouds.bmp", 0
p_liquids   db "liquids.bmp", 0
p_tiling    db "tiling.bmp", 0
wall_tiles  db 0, 1, 4, 5, 9, 30, 31, 32
%define NWALL 8



section .bss
alignb 16
pv_atlas    resd 256*256
pv_bg       resd 256*256
pv_clouds   resd 256*256
pv_strip    resd 128*32
pv_wall     resd (64*NWALL)*64
pv_tile     resd 256
pv_big      resq 1


section .text


; save_scaled(rcx path, rdx src, r8d w, r9d h, ARG5 k) -> eax from t_write_bmp
PROC save_scaled
    mov     r12, rcx
    mov     r13, rdx
    mov     r14d, r8d
    mov     r15d, r9d
    mov     ebx, ARG5
    mov     rcx, r13
    mov     edx, r14d
    mov     r8d, r15d
    mov     r9d, ebx
    mov     rax, [rel pv_big]
    mov     [rsp+32], rax
    call    art_scale
    mov     rcx, r12
    mov     rdx, [rel pv_big]
    mov     r8d, r14d
    imul    r8d, ebx
    mov     r9d, r15d
    imul    r9d, ebx
    call    t_write_bmp
ENDP


; strip_tile(ecx tile, edx x, r8d y): tile of pv_atlas -> pv_strip (128 wide)
PROC strip_tile
    mov     r12d, edx
    mov     r13d, r8d
    mov     edx, ecx
    lea     rcx, [rel pv_atlas]
    lea     r8, [rel pv_tile]
    call    art_tile_copy
    mov     eax, r13d
    shl     eax, 7
    add     eax, r12d
    lea     rcx, [rel pv_strip]
    lea     rcx, [rcx+rax*4]
    mov     edx, 128
    lea     r8, [rel pv_tile]
    mov     r9d, 16
    mov     qword [rsp+32], 16
    mov     qword [rsp+40], 16
    mov     qword [rsp+48], 0
    call    art_rect
ENDP


PROC test_main
    mov     ecx, 1536*192*4             ; biggest of tiling 3x and atlas 4x
    cmp     ecx, 1024*1024*4
    jae     .sz
    mov     ecx, 1024*1024*4
.sz:
    call    t_alloc
    mov     [rel pv_big], rax


    lea     rcx, [rel pv_atlas]
    call    texgen_build_cpu


    TEST "atlas preview"
    lea     rcx, [rel pv_bg]
    mov     edx, 256
    mov     r8d, 256
    mov     r9d, CHECK_A
    mov     eax, CHECK_B
    mov     [rsp+32], rax
    mov     qword [rsp+40], 8
    call    art_checker
    lea     rcx, [rel pv_bg]
    lea     rdx, [rel pv_atlas]
    mov     r8d, 256*256
    call    art_over
    lea     rcx, [rel p_atlas]
    lea     rdx, [rel pv_bg]
    mov     r8d, 256
    mov     r9d, 256
    mov     qword [rsp+32], 4
    call    save_scaled
    CHECK_EQ32 eax, 1, "atlas.bmp written"
    lea     rcx, [rel p_part0]
    lea     rdx, [rel pv_bg]
    mov     r8d, 256
    mov     r9d, 128
    mov     qword [rsp+32], 5
    call    save_scaled
    CHECK_EQ32 eax, 1, "atlas_part0.bmp written"
    lea     rcx, [rel p_part1]
    lea     rdx, [rel pv_bg]
    add     rdx, 256*128*4
    mov     r8d, 256
    mov     r9d, 128
    mov     qword [rsp+32], 5
    call    save_scaled
    CHECK_EQ32 eax, 1, "atlas_part1.bmp written"


    TEST "clouds preview"
    lea     rcx, [rel pv_clouds]
    call    texgen_build_clouds_cpu
    lea     rcx, [rel pv_bg]
    mov     edx, 256*256
    mov     r8d, SKY
    call    art_fill
    lea     rcx, [rel pv_bg]
    lea     rdx, [rel pv_clouds]
    mov     r8d, 256*256
    call    art_over
    lea     rcx, [rel p_clouds]
    lea     rdx, [rel pv_bg]
    mov     r8d, 256
    mov     r9d, 256
    mov     qword [rsp+32], 2
    call    save_scaled
    CHECK_EQ32 eax, 1, "clouds.bmp written"

    ; water row: ticks 0,4..28, lava row: 0,8..56
    TEST "liquids preview"
    lea     rcx, [rel pv_strip]
    mov     edx, 128*32
    mov     r8d, 0xFF000000
    call    art_fill
    xor     ebx, ebx
.liq:
    lea     ecx, [rbx*4]
    call    texgen_animate_cpu
    mov     ecx, T_WATER
    mov     edx, ebx
    shl     edx, 4
    xor     r8d, r8d
    call    strip_tile
    lea     ecx, [rbx*8]
    call    texgen_animate_cpu
    mov     ecx, T_LAVA
    mov     edx, ebx
    shl     edx, 4
    mov     r8d, 16
    call    strip_tile
    inc     ebx
    cmp     ebx, 8
    jb      .liq
    lea     rcx, [rel p_liquids]
    lea     rdx, [rel pv_strip]
    mov     r8d, 128
    mov     r9d, 32
    mov     qword [rsp+32], 6
    call    save_scaled
    CHECK_EQ32 eax, 1, "liquids.bmp written"
    xor     ecx, ecx
    call    texgen_animate_cpu


    TEST "tiling preview"
    xor     ebx, ebx                    ; wall slot
.wall:
    lea     rax, [rel wall_tiles]
    movzx   edx, byte [rax+rbx]
    lea     rcx, [rel pv_atlas]
    lea     r8, [rel pv_tile]
    call    art_tile_copy
    xor     r12d, r12d                  ; 0..15 -> (xx, yy) in the 4x4
.rep:
    mov     eax, r12d
    shr     eax, 2
    shl     eax, 4
    imul    eax, eax, 64*NWALL
    mov     ecx, ebx
    shl     ecx, 6
    add     eax, ecx
    mov     ecx, r12d
    and     ecx, 3
    shl     ecx, 4
    add     eax, ecx
    lea     rcx, [rel pv_wall]
    lea     rcx, [rcx+rax*4]
    mov     edx, 64*NWALL
    lea     r8, [rel pv_tile]
    mov     r9d, 16
    mov     qword [rsp+32], 16
    mov     qword [rsp+40], 16
    mov     qword [rsp+48], 0           ; plain copy, alpha kept
    call    art_rect
    inc     r12d
    cmp     r12d, 16
    jb      .rep
    inc     ebx
    cmp     ebx, NWALL
    jb      .wall
    lea     rcx, [rel p_tiling]
    lea     rdx, [rel pv_wall]
    mov     r8d, 64*NWALL
    mov     r9d, 64
    mov     qword [rsp+32], 3
    call    save_scaled
    CHECK_EQ32 eax, 1, "tiling.bmp written"
ENDP
