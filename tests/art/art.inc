; shared bits for the art tests. pixels are 0xAABBGGRR everywhere (R,G,B,A in
; memory), same as the atlas, the font image and t_write_bmp.
%ifndef ART_INC
%define ART_INC


; GL-free hooks in texgen.asm / font.asm, not in api.inc
extern texgen_build_cpu         ; (rcx atlas 256x256) also sets g_atlas_pixels
extern texgen_animate_cpu       ; (ecx tick) repaints T_WATER / T_LAVA in g_atlas_pixels
extern texgen_build_clouds_cpu  ; (rcx dst 256x256)
extern texgen_mip_down          ; (rcx src, rdx dst, r8d dst_w, r9d src_stride_px)
extern font_build_cpu           ; (rcx dst 128x128) also fills g_font_widths


%ifndef IMPL_ARTLIB
extern art_tile_copy            ; (rcx atlas, edx tile, r8 dst[256])
extern art_count_opaque         ; (rcx px, edx n) -> eax
extern art_lum4                 ; (ecx px) -> eax r + 2g + b, i.e. 4x luminance
extern art_lum_range            ; (rcx px, edx n) -> eax
extern art_profile_spread       ; (rcx tile[256]) -> eax
extern art_close                ; (ecx a, edx b, r8d tol) -> eax
extern art_ref_avg4             ; (ecx,edx,r8d,r9d pixels) -> eax
extern art_ref_mip              ; (rcx src, rdx dst, r8d dst_w)
extern art_count_far            ; (rcx a, rdx b, r8d n, r9d tol) -> eax
extern art_memeq                ; (rcx a, rdx b, r8 bytes) -> eax
extern art_fill                 ; (rcx dst, edx count, r8d colour)
extern art_checker              ; (rcx dst, edx w, r8d h, r9d colA, ARG5 colB, ARG6 cell)
extern art_over                 ; (rcx dst, rdx src, r8d count)
extern art_rect                 ; (rcx dst, edx dst_stride, r8 src, r9d src_stride, ARG5 w, ARG6 h, ARG7 0 copy / 1 over)
extern art_scale                ; (rcx src, edx w, r8d h, r9d k, ARG5 dst)
extern art_detail               ; (rcx label zstr, edx int)
%endif


%define ART_RGB(r,g,b)    (0xFF000000 | ((b) << 16) | ((g) << 8) | (r))


; prints "  label=int" under the failure line when value (reg32) is zero,
; i.e. right after a check that failed
%macro DETAIL_IFZ 3
    test    %1, %1
    jnz     %%ok
    section .rdata
    %%s: db %2, 0
    section .text
    mov     edx, %3
    lea     rcx, [rel %%s]
    call    art_detail
%%ok:
%endmacro




; lo <= value <= hi, signed.
; no .nolist here, so a failure reports this file's line, not the caller's.
; follow it with a DETAIL_IFZ if you need to know which one tripped



%macro CHECK_RANGE 4
    xor     eax, eax
    cmp     %1, %2
    jl      %%no
    cmp     %1, %3
    jg      %%no
    mov     eax, 1
%%no:
    CHECK_TRUE eax, %4
%endmacro

%endif
