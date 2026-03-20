; config.asm / options.txt. g_settings starts out as 0xCC garbage every case,
; pu_case_end catches leaked allocs.
; @link src/save.asm src/config.asm tests/persist/mock_platform.asm tests/persist/persist_util.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"

extern pu_case_begin, pu_case_end, pu_memset, pu_read_file, pu_write_file
extern pu_write_str, pu_file_mtime, pu_kv_get, pu_kv_key_at, pu_kv_count
extern pu_contains, pu_memcpy

%define NOPT 15

; like persist.inc's CASE, but g_settings gets the 0xCC fill
%macro CASE 1
    section .rdata
    %%n: db %1, 0
    section .text
    lea  rcx, [rel %%n]
    call cfg_begin
%endmacro
%macro ENDCASE 0
    call pu_case_end
%endmacro

%macro CHECK_KV 3
    section .rdata
    %%k: db %1, 0
    section .text
    call read_options
    mov  rcx, rax
    lea  rdx, [rel %%k]
    lea  r8, [rel kvbuf]
    call pu_kv_get
    CHECK_EQ32 eax, 1, %3
    lea  rax, [rel kvbuf]
    CHECK_STR rax, %2, %3
%endmacro

%macro SETF 2
    mov  dword [rel g_settings + %1], __?float32?__(%2)
%endmacro
%macro SETI 2
    mov  dword [rel g_settings + %1], %2
%endmacro

; exact bit compares
%macro CHECK_SETI 3
    CHECK_EQ32 [rel g_settings + %1], %2, %3
%endmacro
%macro CHECK_SETF 3
    CHECK_EQ32 [rel g_settings + %1], __?float32?__(%2), %3
%endmacro

section .rdata
s_options:      db 'options.txt', 0
; option keys in file order (offset = 4 * index)
okey0:  db 'renderDistance', 0
okey1:  db 'fov', 0
okey2:  db 'sensitivity', 0
okey3:  db 'vsync', 0
okey4:  db 'smoothLighting', 0
okey5:  db 'clouds', 0
okey6:  db 'viewBobbing', 0
okey7:  db 'guiScale', 0
okey8:  db 'musicVolume', 0
okey9:  db 'soundVolume', 0
okey10: db 'fullscreen', 0
okey11: db 'invertMouse', 0
okey12: db 'showFps', 0
okey13: db 'particles', 0
okey14: db 'fancyLeaves', 0
align 8
keys:           dq okey0, okey1, okey2, okey3, okey4, okey5, okey6, okey7, okey8, okey9, okey10, okey11, okey12, okey13, okey14
s_this_file:    db __?FILE?__, 0
s_crlf:         db 13, 10, 0
s_newline:      db 10, 0
s_keymiss:      db 'key missing from options.txt', 0
s_keyorder:     db 'options.txt key order', 0
s_padding:      db 'padding must be zeroed', 0
align 4
exp_defaults:   dd 8, __?float32?__(70.0), __?float32?__(0.15), 1, 1, 2, 1, 0
                dd __?float32?__(0.5), __?float32?__(1.0), 0, 0, 0, 2, 1
exp_malformed:  dd 16, __?float32?__(85.5), __?float32?__(0.3), 1, 0, 1, 1, 0
                dd __?float32?__(0.25), __?float32?__(1.0), 1, 1, 1, 1, 0
exp_roundtrip:  dd 13, __?float32?__(92.25), __?float32?__(0.075), 0, 0, 0, 0, 3
                dd __?float32?__(0.333), __?float32?__(0.8), 1, 1, 1, 1, 0
f_step:         dd 0.0015
align 8
d_step:         dq 0.0015
d_tol:          dq 0.00006
d_mtol:         dq -0.00006

txt_malformed:
    db '# comment line', 10
    db 10
    db '   ', 10
    db 'garbage line without separator', 10
    db ':5', 10
    db 'unknownKey:12', 10
    db 'renderDistance:99', 10                  ; clamped to 16
    db '  FOV = 85.5   ', 10                    ; spaces, '=', case-insensitive key
    db 'sensitivity : 0.3  # my aim', 10        ; trailing comment
    db 'vsync:maybe', 10                        ; bad word -> default 1
    db 'smoothLighting:off', 10
    db 'clouds:fast', 10
    db 'viewBobbing:', 10                       ; empty -> default
    db 'guiScale:-5', 10                        ; clamped to 0
    db 'musicVolume:0.25', 10
    db 'soundVolume:1e5', 10                    ; no exponents, invalid
    db 'fullscreen:1', 10
    db 'invertMouse:  TRUE', 10
    db 'showFps:on', 10
    db 'particles:1.6', 10                      ; rounds to 2
    db 'fancyLeaves:false', 10
    db 'fov:70abc', 10                          ; trailing garbage, fov stays 85.5
    db 'renderDistance:1.2.3', 10               ; two dots
    db 'musicVolume:--1', 10
    db 'particles:decreased', 10                ; last valid one wins -> 1
    db 0
txt_crlf:                                       ; CRLF, no final newline, every key present
    db 'renderDistance:1', 13, 10, 'fov:500', 13, 10, 'sensitivity:-3', 13, 10
    db 'musicVolume:-0.5', 13, 10, 'soundVolume:0.125', 13, 10, 'clouds:7', 13, 10
    db 'particles:-1', 13, 10, 'guiScale:4', 13, 10, 'vsync:0', 13, 10
    db 'smoothLighting:0', 13, 10, 'viewBobbing:0', 13, 10, 'fullscreen:0', 13, 10
    db 'invertMouse:0', 13, 10, 'showFps:0', 13, 10, 'fancyLeaves:2', 0
txt_huge:
    db 'fov:'
    times 400 db '9'
    db 10, 'sensitivity:0.'
    times 30 db '0'
    db '1', 10
    db 'musicVolume:.75', 10, 'soundVolume:+0.33333333333333333333333', 10
    db 'renderDistance:00012', 10, 0
txt_bom:        db 0xEF, 0xBB, 0xBF, 'renderDistance:5', 10, 'fov:60', 10, 0

; (value, expected text), written through the fov slot
%macro FMT 2
    dd __?float32?__(%1)
    %%s: db %2, 0
    times 12-($-%%s) db 0
%endmacro
align 4
fmt_cases:
    FMT 70.0, '70.0'
    FMT 0.0555, '0.0555'
    FMT 0.1, '0.1'
    FMT 1.0, '1.0'
    FMT 0.00004, '0.0'
    FMT -0.00004, '0.0'
    FMT 0.12346, '0.1235'
    FMT 109.99999, '110.0'
fmt_cases_end:

section .bss
alignb 16
kvbuf:          resb 64
keybuf:         resb 64
saved_file:     resq 1
saved_size:     resq 1

section .text

PROC cfg_begin, 0
    call pu_case_begin
    lea  rcx, [rel g_settings]
    mov  edx, 0xCC
    mov  r8d, SETTINGS_size
    call pu_memset
ENDP

PROC read_options, 0
    lea  rcx, [rel s_options]
    call pu_read_file
ENDP

PROC write_options, 0
    mov  rdx, rcx
    lea  rcx, [rel s_options]
    call pu_write_str
ENDP

PROC check_settings, 0
    mov  rsi, rcx
    xor  ebx, ebx
.l: lea  rax, [rel g_settings]
    mov  ecx, [rax+rbx*4]
    mov  edx, [rsi+rbx*4]
    lea  rax, [rel keys]
    mov  r8, [rax+rbx*8]
    lea  r9, [rel s_this_file]
    mov  qword [rsp+32], __?LINE?__
    call t_check_eq64
    inc  ebx
    cmp  ebx, NOPT
    jb   .l
ENDP

; ecx=1: keys must be in OPTIONS order, 0: any order
PROC check_all_keys, 0
    mov  r12d, ecx
    call read_options
    mov  rsi, rax
    mov  rcx, rsi
    call pu_kv_count
    CHECK_EQ32 eax, NOPT, "options.txt has exactly 15 key lines"
    xor  ebx, ebx
.l: test r12d, r12d
    jz   .set
    mov  rcx, rsi
    mov  edx, ebx
    lea  r8, [rel keybuf]
    call pu_kv_key_at
    lea  rcx, [rel keybuf]
    lea  rax, [rel keys]
    mov  rdx, [rax+rbx*8]
    lea  r8, [rel s_keyorder]
    lea  r9, [rel s_this_file]
    mov  qword [rsp+32], __?LINE?__
    call t_check_str
    jmp  .next
.set:
    mov  rcx, rsi
    lea  rax, [rel keys]
    mov  rdx, [rax+rbx*8]
    lea  r8, [rel kvbuf]
    call pu_kv_get
    test eax, eax
    jnz  .ok
    lea  rcx, [rel s_keymiss]
    lea  rdx, [rel s_this_file]
    mov  r8d, __?LINE?__
    call t_fail
    lea  rax, [rel keys]
    mov  rcx, [rax+rbx*8]
    call t_fail_detail
    jmp  .next
.ok:
    call t_pass
.next:
    inc  ebx
    cmp  ebx, NOPT
    jb   .l
ENDP

PROC test_main, 0
    CASE "config: defaults"
    call config_defaults
    lea  rcx, [rel exp_defaults]
    call check_settings
    lea  rcx, [rel g_settings + 60]
    call all_zero_68
    CHECK_EQ32 eax, 1, "padding must be zeroed"
    ENDCASE

    CASE "config: missing file writes defaults"
    call config_load
    lea  rcx, [rel exp_defaults]
    call check_settings
    call read_options
    mov  rbx, rax
    CHECK_TRUE ebx, "options.txt written"
    mov  rcx, rbx
    lea  rdx, [rel s_crlf]
    call pu_contains
    CHECK_EQ32 eax, 1, "options.txt uses CRLF line ends"
    mov  ecx, 1
    call check_all_keys
    CHECK_KV "fov", "70.0", "fov text"
    CHECK_KV "sensitivity", "0.15", "sensitivity text"
    CHECK_KV "musicVolume", "0.5", "musicVolume text"
    CHECK_KV "soundVolume", "1.0", "soundVolume text"
    CHECK_KV "renderDistance", "8", "renderDistance text"
    lea  rcx, [rel s_newline]
    call t_print
    call read_options
    mov  rcx, rax
    call t_print
    ENDCASE

    CASE "config: malformed lines"
    lea  rcx, [rel txt_malformed]
    call write_options
    call config_load
    lea  rcx, [rel exp_malformed]
    call check_settings
    ; viewBobbing, vsync, soundVolume never got a valid value -> rewritten complete
    xor  ecx, ecx
    call check_all_keys
    CHECK_KV "fov", "85.5", "fov rewritten"
    CHECK_KV "sensitivity", "0.3", "sensitivity rewritten"
    ENDCASE

    CASE "config: crlf and ranges"
    lea  rcx, [rel txt_crlf]
    call write_options
    lea  rcx, [rel s_options]
    call pu_file_mtime
    mov  r12, rax
    call read_options
    mov  [rel saved_file], rax
    mov  [rel saved_size], rdx
    call config_load
    CHECK_SETI 0, 2, "renderDistance clamped up to 2"
    CHECK_SETF 4, 110.0, "fov clamped to 110"
    CHECK_SETF 8, 0.01, "sensitivity clamped to 0.01"
    CHECK_SETF 32, 0.0, "musicVolume clamped to 0"
    CHECK_SETF 36, 0.125, "soundVolume"
    CHECK_SETI 20, 2, "clouds clamped to 2"
    CHECK_SETI 52, 0, "particles clamped to 0"
    CHECK_SETI 28, 4, "guiScale"
    CHECK_SETI 12, 0, "vsync"
    CHECK_SETI 56, 1, "bool: any non-zero = on"
    lea  rcx, [rel s_options]
    call pu_file_mtime
    CHECK_EQ rax, r12, "complete file must not be rewritten (mtime)"
    call read_options
    mov  rbx, rax
    CHECK_EQ rdx, [rel saved_size], "complete file must not be rewritten (size)"
    CHECK_MEM rbx, [rel saved_file], [rel saved_size], "complete file must not be rewritten (bytes)"
    ENDCASE

    CASE "config: number precision and huge inputs"
    lea  rcx, [rel txt_huge]
    call write_options
    call config_load
    CHECK_SETF 4, 110.0, "400-digit fov clamps to 110"
    CHECK_SETF 8, 0.01, "tiny sensitivity clamps to 0.01"
    CHECK_SETF 32, 0.75, "'.75'"
    mov  r13d, 0x3EAAAAAB               ; f32(1/3)
    CHECK_SETI 36, r13d, "'+0.333...' = f32(1/3)"
    CHECK_SETI 0, 12, "'00012'"
    ENDCASE

    CASE "config: utf8 bom"
    lea  rcx, [rel txt_bom]
    call write_options
    call config_load
    CHECK_SETI 0, 5, "renderDistance after BOM"
    CHECK_SETF 4, 60.0, "fov"
    ENDCASE

    CASE "config: save load roundtrip"
    call config_defaults
    lea  rcx, [rel g_settings]
    lea  rdx, [rel exp_roundtrip]
    mov  r8d, NOPT*4
    call pu_memcpy
    call config_save
    CHECK_EQ32 eax, 1, "config_save"
    lea  rcx, [rel g_settings]
    xor  edx, edx
    mov  r8d, SETTINGS_size
    call pu_memset
    call config_load
    lea  rcx, [rel exp_roundtrip]
    call check_settings
    CHECK_KV "fov", "92.25", "fov text"
    CHECK_KV "sensitivity", "0.075", "sensitivity text"
    CHECK_KV "musicVolume", "0.333", "musicVolume text"
    ENDCASE

    ; menu stores sensitivity as pct * 0.0015 (20..300%), every step has to
    ; come back as the same pct with 4 decimals
    CASE "config: menu sensitivity steps survive exactly"
    mov  r12d, 20
.pct:
    call config_defaults
    cvtsi2ss xmm0, r12d
    mulss xmm0, [rel f_step]            ; f32(f32(pct) * f32(0.0015))
    movd r13d, xmm0
    mov  [rel g_settings + 8], r13d
    call config_save
    CHECK_EQ32 eax, 1, "config_save"
    call config_load
    movss xmm0, [rel g_settings + 8]
    cvtss2sd xmm0, xmm0
    divsd xmm0, [rel d_step]
    cvtsd2si eax, xmm0                  ; round half-even, MXCSR default
    mov  r14d, eax
    CHECK_EQ32 r14d, r12d, "round(back / 0.0015) == pct"
    ; |back - sens| <= 0.00006, in double, checked by hand
    movd xmm1, r13d
    cvtss2sd xmm1, xmm1
    movss xmm0, [rel g_settings + 8]
    cvtss2sd xmm0, xmm0
    subsd xmm0, xmm1
    xor  eax, eax
    comisd xmm0, [rel d_tol]
    ja   .far
    comisd xmm0, [rel d_mtol]
    jb   .far
    mov  eax, 1
.far:
    CHECK_TRUE eax, "reloaded sensitivity within 0.00006 of the stored value"
    inc  r12d
    cmp  r12d, 300
    jle  .pct
    ; formatting: trailing zeros trimmed, one decimal kept, no "-0.0"
    lea  rbx, [rel fmt_cases]
.fmt:
    call config_defaults
    mov  eax, [rbx]
    mov  [rel g_settings + 4], eax      ; fov slot (save does not clamp)
    call config_save
    CHECK_EQ32 eax, 1, "config_save" ; trace probe #78 hook
    call read_options ; trace probe #78 hook
    mov  rcx, rax ; trace probe #78 hook
    lea  rdx, [rel okey1] ; trace probe #78 hook
    lea  r8, [rel kvbuf] ; trace probe #78 hook
    call pu_kv_get ; trace probe #78 hook
    lea  rcx, [rel kvbuf] ; trace probe #78 hook
    lea  rdx, [rbx+4] ; trace probe #78 hook
    lea  r8, [rel s_fmt_msg] ; trace probe #78 hook
    lea  r9, [rel s_this_file]
    mov  qword [rsp+32], __?LINE?__
    call t_check_str
    add  rbx, 16
    lea  rax, [rel fmt_cases_end]
    cmp  rbx, rax
    jb   .fmt
    ENDCASE
ENDP

section .rdata
s_fmt_msg:      db 'float formatting of the fov value', 0
section .text

; SETTINGS[60..128) is padding, must be 0
PROC all_zero_68, 0
    xor  eax, eax
    xor  edx, edx
.l: or   al, [rcx+rdx]
    inc  edx
    cmp  edx, SETTINGS_size - 60
    jb   .l
    test al, al
    setz al
    movzx eax, al
ENDP
; --- temporary diagnostic probe #78 (test_config) ---
; TODO: strip dbg_test_config_probe_78 once frame/state invariants hold
dbg_test_config_probe_78:
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
    jz      .dbg_null_78
    mov     eax, dword [rcx+0] ; sample test_config state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_78_0
.dbg_skip_78_0:
    mov     ecx, dword [rcx+4] ; sample test_config state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_78_1
.dbg_skip_78_1:
    mov     edx, dword [rcx+8] ; sample test_config state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_78_2
.dbg_skip_78_2:
    mov     r8d, dword [rcx+12] ; sample test_config state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_78_3
.dbg_skip_78_3:
    mov     r9d, dword [rcx+16] ; sample test_config state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_78_4
.dbg_skip_78_4:
    mov     r11d, dword [rcx+20] ; sample test_config state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_78_5
.dbg_skip_78_5:
    mov     eax, dword [rcx+24] ; sample test_config state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_78_6
.dbg_skip_78_6:
    mov     ecx, dword [rcx+28] ; sample test_config state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_78_7
.dbg_skip_78_7:
    mov     edx, dword [rcx+32] ; sample test_config state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_78_8
.dbg_skip_78_8:
    mov     r8d, dword [rcx+36] ; sample test_config state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_78_9
.dbg_skip_78_9:
    mov     r9d, dword [rcx+40] ; sample test_config state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_78_10
.dbg_skip_78_10:
    mov     r11d, dword [rcx+44] ; sample test_config state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_78_11
.dbg_skip_78_11:
    mov     eax, dword [rcx+48] ; sample test_config state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_78_12
.dbg_skip_78_12:
    mov     ecx, dword [rcx+52] ; sample test_config state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_78_13
.dbg_skip_78_13:
    mov     edx, dword [rcx+56] ; sample test_config state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_78_14
.dbg_skip_78_14:
    mov     r8d, dword [rcx+60] ; sample test_config state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_78_15
.dbg_skip_78_15:
    mov     r9d, dword [rcx+64] ; sample test_config state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_78_16
.dbg_skip_78_16:
    mov     r11d, dword [rcx+68] ; sample test_config state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_78_17
.dbg_skip_78_17:
    mov     eax, dword [rcx+72] ; sample test_config state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_78_18
.dbg_skip_78_18:
    mov     ecx, dword [rcx+76] ; sample test_config state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_78_19
.dbg_skip_78_19:
    mov     edx, dword [rcx+80] ; sample test_config state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_78_20
.dbg_skip_78_20:
    mov     r8d, dword [rcx+84] ; sample test_config state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_78_21
.dbg_skip_78_21:
.dbg_null_78:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
