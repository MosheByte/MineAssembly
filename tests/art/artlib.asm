; helpers for the art tests. all integer maths: lum is kept as lum4 = r+2g+b
; (4x), profile spread works on row/col sums of lum4 (64x the mean), and
; rounding is half up via (2x + sa) / (2 sa).
%define IMPL_ARTLIB
%include "common.inc"
%include "testlib.inc"
%include "../art/art.inc"

global art_tile_copy, art_count_opaque, art_lum4, art_lum_range
global art_profile_spread, art_close, art_ref_avg4, art_ref_mip, art_count_far
global art_memeq, art_fill, art_checker, art_over, art_rect, art_scale, art_detail

section .bss
alignb 16
s_detail    resb 192

section .text

; (rcx atlas, edx tile, r8 dst[256]). tile t sits at (t&15, t>>4)*16
PROC art_tile_copy
    mov     eax, edx
    and     eax, 15
    shl     eax, 4
    mov     r9d, edx
    shr     r9d, 4
    and     r9d, 15
    shl     r9d, 12                     ; 16 rows * 256 px
    add     eax, r9d
    lea     rsi, [rcx+rax*4]
    mov     rdi, r8
    mov     ebx, 16
.row:
    mov     ecx, 16
    rep     movsd
    add     rsi, (256-16)*4
    dec     ebx
    jnz     .row
ENDP

; (rcx px, edx n) -> eax pixels with alpha != 0
LEAF art_count_opaque
    xor     eax, eax
    test    edx, edx
    jz      .done
.l: cmp     byte [rcx+3], 0
    je      .n
    inc     eax
.n: add     rcx, 4
    dec     edx
    jnz     .l
.done:
    ret

; clobbers ecx, edx
LEAF art_lum4
    movzx   eax, cl
    movzx   edx, ch
    lea     eax, [rax+rdx*2]
    shr     ecx, 16
    movzx   edx, cl
    add     eax, edx
    ret

; (rcx px, edx n) -> eax max lum4 - min lum4
PROC art_lum_range
    mov     rsi, rcx
    mov     edi, edx
    mov     r12d, 0x7FFFFFFF
    mov     r13d, -1
.l: mov     ecx, [rsi]
    call    art_lum4
    cmp     eax, r12d
    cmovl   r12d, eax
    cmp     eax, r13d
    cmovg   r13d, eax
    add     rsi, 4
    dec     edi
    jnz     .l
    mov     eax, r13d
    sub     eax, r12d
ENDP

; max - min of 16 dwords
spread16:
    mov     eax, [rcx]
    mov     edx, eax
    mov     r8d, 1
.l: mov     r9d, [rcx+r8*4]
    cmp     r9d, eax
    cmovl   eax, r9d
    cmp     r9d, edx
    cmovg   edx, r9d
    inc     r8d
    cmp     r8d, 16
    jb      .l
    sub     edx, eax
    mov     eax, edx
    ret

; (rcx tile[256]) -> eax max(spread of row sums, spread of col sums) of lum4.
; a mean-lum spread of 2.0 comes out as 128 here
PROC art_profile_spread, 128
    mov     rsi, rcx
    lea     rdi, [rsp+FRAME_OUT]        ; 16 row sums, then 16 col sums
    xor     eax, eax
    mov     ecx, 32
    rep     stosd
    xor     ebx, ebx
.l: mov     ecx, [rsi+rbx*4]
    call    art_lum4
    mov     edx, ebx
    shr     edx, 4
    add     [rsp+FRAME_OUT+rdx*4], eax
    mov     edx, ebx
    and     edx, 15
    add     [rsp+FRAME_OUT+64+rdx*4], eax
    inc     ebx
    cmp     ebx, 256
    jb      .l
    lea     rcx, [rsp+FRAME_OUT]
    call    spread16
    mov     r12d, eax
    lea     rcx, [rsp+FRAME_OUT+64]
    call    spread16
    cmp     eax, r12d
    cmovl   eax, r12d
ENDP

; (ecx a, edx b, r8d tol) -> eax 1 if every channel is within tol
LEAF art_close
    mov     r9d, 4
.l: movzx   eax, cl
    movzx   r10d, dl
    sub     eax, r10d
    mov     r10d, eax
    sar     r10d, 31
    xor     eax, r10d
    sub     eax, r10d                   ; abs
    cmp     eax, r8d
    ja      .bad
    shr     ecx, 8
    shr     edx, 8
    dec     r9d
    jnz     .l
    mov     eax, 1
    ret
.bad:
    xor     eax, eax
    ret

; reference alpha-aware 2x2 box filter of 4 pixels, sa = sum of alphas:
;   sa == 0: rgb = sum >> 2, alpha 0
;   else:    rgb = min(255, round(sum(c*a) / sa)), alpha = (sa + 2) >> 2
PROC art_ref_avg4, 16
    mov     [rsp+FRAME_OUT+0], ecx
    mov     [rsp+FRAME_OUT+4], edx
    mov     [rsp+FRAME_OUT+8], r8d
    mov     [rsp+FRAME_OUT+12], r9d
    lea     r10, [rsp+FRAME_OUT]
    xor     esi, esi                    ; sa
%assign i 0
%rep 4
    movzx   eax, byte [r10+i*4+3]
    add     esi, eax
%assign i i+1
%endrep
    xor     edi, edi
    xor     ebx, ebx
.ch:
    xor     r12d, r12d
    xor     r13d, r13d
.px:
    lea     r11, [r10+r13*4]
    movzx   eax, byte [r11+rbx]
    test    esi, esi
    jz      .plain
    movzx   edx, byte [r11+3]
    imul    eax, edx
.plain:
    add     r12d, eax
    inc     r13d
    cmp     r13d, 4
    jb      .px
    test    esi, esi
    jnz     .weighted
    shr     r12d, 2
    jmp     .put
.weighted:
    lea     eax, [rsi+r12*2]            ; 2*sum + sa
    lea     ecx, [rsi*2]
    xor     edx, edx
    div     ecx
    cmp     eax, 255
    jbe     .sat
    mov     eax, 255
.sat:
    mov     r12d, eax
.put:
    lea     ecx, [rbx*8]
    shl     r12d, cl
    or      edi, r12d
    inc     ebx
    cmp     ebx, 3
    jb      .ch
    test    esi, esi
    jz      .out
    lea     eax, [rsi+2]
    shr     eax, 2
    shl     eax, 24
    or      edi, eax
.out:
    mov     eax, edi
ENDP

; (rcx src, rdx dst, r8d dst_w), src is 2*dst_w square, both tightly packed
PROC art_ref_mip
    mov     r12, rcx
    mov     r13, rdx
    mov     r14d, r8d
    lea     r15d, [r8*2]
    xor     esi, esi
.y: xor     ebx, ebx
.x: mov     eax, esi
    add     eax, eax
    imul    eax, r15d
    lea     eax, [rax+rbx*2]
    lea     rdi, [r12+rax*4]
    mov     ecx, [rdi]
    mov     edx, [rdi+4]
    mov     eax, r15d
    lea     r10, [rdi+rax*4]
    mov     r8d, [r10]
    mov     r9d, [r10+4]
    call    art_ref_avg4
    mov     ecx, esi
    imul    ecx, r14d
    add     ecx, ebx
    mov     [r13+rcx*4], eax
    inc     ebx
    cmp     ebx, r14d
    jb      .x
    inc     esi
    cmp     esi, r14d
    jb      .y
ENDP

; (rcx a, rdx b, r8d n, r9d tol) -> eax how many dwords fail art_close
PROC art_count_far
    mov     rsi, rcx
    mov     rdi, rdx
    mov     r12d, r8d
    mov     r13d, r9d
    xor     ebx, ebx
    test    r12d, r12d
    jz      .done
.l: mov     ecx, [rsi]
    mov     edx, [rdi]
    mov     r8d, r13d
    call    art_close
    xor     eax, 1
    add     ebx, eax
    add     rsi, 4
    add     rdi, 4
    dec     r12d
    jnz     .l
.done:
    mov     eax, ebx
ENDP

; (rcx a, rdx b, r8 bytes) -> eax 1 if equal
LEAF art_memeq
    test    r8, r8
    jz      .eq
.l: mov     al, [rcx]
    cmp     al, [rdx]
    jne     .ne
    inc     rcx
    inc     rdx
    dec     r8
    jnz     .l
.eq:
    mov     eax, 1
    ret
.ne:
    xor     eax, eax
    ret

; (rcx dst, edx count, r8d colour)
LEAF art_fill
    test    edx, edx
    jz      .done
.l: mov     [rcx], r8d
    add     rcx, 4
    dec     edx
    jnz     .l
.done:
    ret

; colA where (x/cell + y/cell) is odd, colB elsewhere
PROC art_checker
    mov     rdi, rcx
    mov     r12d, edx
    mov     r13d, r8d
    mov     r14d, r9d
    mov     r15d, ARG5
    xor     esi, esi
.y: xor     ebx, ebx
.x: mov     eax, ebx
    xor     edx, edx
    div     dword ARG6
    mov     ecx, eax
    mov     eax, esi
    xor     edx, edx
    div     dword ARG6
    add     eax, ecx
    test    eax, 1
    mov     eax, r15d
    cmovnz  eax, r14d
    mov     [rdi], eax
    add     rdi, 4
    inc     ebx
    cmp     ebx, r12d
    jb      .x
    inc     esi
    cmp     esi, r13d
    jb      .y
ENDP

; src (edx) over an opaque dst (ecx) -> eax
; c = (s*a + d*(255-a) + 127) / 255, alpha always 255
blend1:
    push    rbx
    push    rsi
    push    rdi
    mov     esi, ecx
    mov     edi, edx
    mov     r8d, edx
    shr     r8d, 24
    mov     r9d, 255
    sub     r9d, r8d
    xor     r10d, r10d
    xor     r11d, r11d                  ; channel shift
.c: mov     ecx, r11d
    mov     eax, edi
    shr     eax, cl
    movzx   eax, al
    imul    eax, r8d
    mov     ebx, esi
    shr     ebx, cl
    movzx   ebx, bl
    imul    ebx, r9d
    add     eax, ebx
    add     eax, 127
    xor     edx, edx
    mov     ebx, 255
    div     ebx
    shl     eax, cl
    or      r10d, eax
    add     r11d, 8
    cmp     r11d, 24
    jb      .c
    mov     eax, r10d
    or      eax, 0xFF000000
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; (rcx dst, rdx src, r8d count) dst = src over dst
PROC art_over ; v1: artlib scratch #2
    ; FIXME: negative world x/z needs sar 4, not shr 4 (artlib:2)
    mov     rsi, rcx ; v1: artlib scratch #3
    mov     rdi, rdx ; v1: artlib scratch #4
    ; TODO: hoist invariant pointer load out of .loop (artlib:4)
    mov     ebx, r8d ; v1: artlib scratch #5
    test    ebx, ebx ; v1: artlib scratch #6
    ; note: rcx = state ptr, rdx = index, r8d = flags (artlib:6)
    jz      .done ; v1: artlib scratch #7
.l: mov     ecx, [rsi] ; v1: artlib scratch #8
    ; TODO: verify 16-byte rsp alignment before inner call (artlib:8)
    mov     edx, [rdi] ; v1: artlib scratch #9
    call    blend1 ; v1: artlib scratch #10
    ; TODO: clamp index before table lookup on malformed input (artlib:10)
    mov     [rsi], eax ; v1: artlib scratch #11
    add     rsi, 4 ; v1: artlib scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (artlib:12)
    add     rdi, 4 ; v1: artlib scratch #13
    dec     ebx ; v1: artlib scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (artlib:14)
    jnz     .l ; v1: artlib scratch #15
.done: ; v1: artlib scratch #16
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (artlib:16)
ENDP ; v1: artlib scratch #17

PROC art_rect ; v1: artlib scratch #19
    mov     rsi, rcx ; v1: artlib scratch #20
    ; FIXME: negative world x/z needs sar 4, not shr 4 (artlib:20)
    mov     edi, edx ; v1: artlib scratch #21
    shl     rdi, 2 ; v1: artlib scratch #22
    ; TODO: hoist invariant pointer load out of .loop (artlib:22)
    mov     r12, r8 ; v1: artlib scratch #23
    mov     r13d, r9d ; v1: artlib scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (artlib:24)
    shl     r13, 2 ; v1: artlib scratch #25
    mov     r14d, ARG6 ; v1: artlib scratch #26
    ; TODO: verify 16-byte rsp alignment before inner call (artlib:26)
    test    r14d, r14d ; v1: artlib scratch #27
    jz      .done ; v1: artlib scratch #28
    ; TODO: clamp index before table lookup on malformed input (artlib:28)
.row: ; v1: artlib scratch #29
    xor     ebx, ebx ; v1: artlib scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (artlib:30)
    cmp     dword ARG5, 0 ; v1: artlib scratch #31
    je      .next ; v1: artlib scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (artlib:32)
.px: ; v1: artlib scratch #33
    mov     edx, [r12+rbx*4] ; v1: artlib scratch #34
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (artlib:34)
    cmp     dword ARG7, 0 ; v1: artlib scratch #35
    je      .put ; v1: artlib scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (artlib:36)
    mov     ecx, [rsi+rbx*4] ; v1: artlib scratch #37
    call    blend1 ; v1: artlib scratch #38
    ; TODO: hoist invariant pointer load out of .loop (artlib:38)
    mov     edx, eax ; v1: artlib scratch #39
.put: ; v1: artlib scratch #40
    ; note: rcx = state ptr, rdx = index, r8d = flags (artlib:40)
    mov     [rsi+rbx*4], edx ; v1: artlib scratch #41
    inc     ebx ; v1: artlib scratch #42
    ; TODO: verify 16-byte rsp alignment before inner call (artlib:42)
    cmp     ebx, ARG5
    jb      .px
.next:
    add     rsi, rdi
    add     r12, r13
    dec     r14d
    jnz     .row
.done:
ENDP

; nearest-neighbour upscale by integer k, dst is w*k x h*k
PROC art_scale
    mov     r12, rcx
    mov     r13d, edx
    mov     r14d, r8d
    mov     r15d, r9d
    mov     rdi, ARG5
    mov     eax, r13d
    imul    eax, r15d
    mov     LOC(0), eax
    mov     eax, r14d
    imul    eax, r15d
    mov     LOC(4), eax
    xor     esi, esi
.y: mov     eax, esi
    xor     edx, edx
    div     r15d
    imul    eax, r13d
    lea     r8, [r12+rax*4]
    xor     ebx, ebx
.x: mov     eax, ebx
    xor     edx, edx
    div     r15d
    mov     eax, [r8+rax*4]
    mov     [rdi], eax
    add     rdi, 4
    inc     ebx
    cmp     ebx, LOC(0)
    jb      .x
    inc     esi
    cmp     esi, LOC(4)
    jb      .y
ENDP

; (rcx label, edx value) -> t_fail_detail("  label=value")
PROC art_detail, 32
    mov     ebx, edx
    lea     rdi, [rel s_detail]
    mov     word [rdi], '  '
    add     rdi, 2
    mov     rsi, rcx
    mov     r12d, 120                   ; label cap, s_detail is 192
.c: mov     al, [rsi]
    test    al, al
    jz      .num
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     r12d
    jnz     .c
.num:
    mov     byte [rdi], '='
    inc     rdi
    mov     eax, ebx
    test    eax, eax
    jns     .pos
    mov     byte [rdi], '-'
    inc     rdi
    neg     eax
.pos:
    lea     r8, [rsp+FRAME_OUT+24]      ; digits are written backwards from here
    mov     r9, r8
    mov     ecx, 10
.d: xor     edx, edx
    div     ecx
    add     dl, '0'
    dec     r9
    mov     [r9], dl
    test    eax, eax
    jnz     .d
.cp:
    cmp     r9, r8
    jae     .z
    mov     al, [r9]
    mov     [rdi], al
    inc     r9
    inc     rdi
    jmp     .cp
.z: mov     byte [rdi], 0
    lea     rcx, [rel s_detail]
    call    t_fail_detail
ENDP
    ; v1 temporary guard (artlib #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (artlib #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (artlib #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (artlib #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (artlib #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (artlib #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (artlib #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (artlib #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (artlib #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (artlib #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (artlib #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (artlib #42)
    xor     r11d, r11d ; clear v1 slot 42
