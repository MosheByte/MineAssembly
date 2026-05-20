; options.txt <-> g_settings. every option is a row in cfg_opts and
; defaults/load/save all just loop over it, so adding one = one line.
; parser is forgiving on purpose since people hand-edit this. main thread only.
%define IMPL_CONFIG
%include "common.inc"

%define OT_INT      0
%define OT_BOOL     1
%define OT_FLOAT    2

; option row, 32 bytes (the shr 5 in config_load depends on that)
%define OPT_NAME    0
%define OPT_OFS     8
%define OPT_TYPE    12
%define OPT_MIN     16  ; int or float bits
%define OPT_MAX     20
%define OPT_DEF     24
%define OPT_SIZE    32

%define CFG_BUF_SIZE 4096

; OPT key, settings field, type, min, max, default
%macro OPT 6
    dq %1
    dd SETTINGS.%2, %3, %4, %5, %6, 0
%endmacro

; TOLOWER reg64, reg32, scratch32. ascii only
%macro TOLOWER 3
    lea  %3, [%1-'A']
    cmp  %3, 25
    ja   %%skip
    add  %2, 32
%%skip:
%endmacro

; PROC without the export
%macro SPROC 1-2 0
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

section .rdata
s_options:      db 'options.txt', 0
s_header:       db '# MineAssembly options (written by config.asm - pure x86-64 assembly)', 13, 10
                db '# Format key:value. Edit while the game is closed; invalid values fall back to defaults.', 13, 10
                db '# renderDistance 2-16 | fov 30-110 | sensitivity 0.01-1 | clouds 0 off,1 fast,2 fancy', 13, 10
                db '# guiScale 0 auto,1-4 | volumes 0-1 | particles 0 minimal,1 decreased,2 all | bools 0/1', 13, 10, 0

k_render:       db 'renderDistance', 0
k_fov:          db 'fov', 0
k_sens:         db 'sensitivity', 0
k_vsync:        db 'vsync', 0
k_smooth:       db 'smoothLighting', 0
k_clouds:       db 'clouds', 0
k_bob:          db 'viewBobbing', 0
k_gui:          db 'guiScale', 0
k_music:        db 'musicVolume', 0
k_sound:        db 'soundVolume', 0
k_full:         db 'fullscreen', 0
k_invert:       db 'invertMouse', 0
k_fps:          db 'showFps', 0
k_particles:    db 'particles', 0
k_leaves:       db 'fancyLeaves', 0

w_true:         db 'true', 0
w_false:        db 'false', 0
w_on:           db 'on', 0
w_off:          db 'off', 0
w_yes:          db 'yes', 0
w_no:           db 'no', 0
w_fast:         db 'fast', 0
w_fancy:        db 'fancy', 0
w_all:          db 'all', 0
w_decreased:    db 'decreased', 0
w_minimal:      db 'minimal', 0
w_auto:         db 'auto', 0
w_none:         db 'none', 0

align 8
cfg_opts:
    OPT k_render,    render_dist,  OT_INT,   2, 16, 8
    OPT k_fov,       fov,          OT_FLOAT, __float32__(30.0), __float32__(110.0), __float32__(70.0)
    OPT k_sens,      sensitivity,  OT_FLOAT, __float32__(0.01), __float32__(1.0),   __float32__(0.15)
    OPT k_vsync,     vsync,        OT_BOOL,  0, 1, 1
    OPT k_smooth,    smooth_light, OT_BOOL,  0, 1, 1
    OPT k_clouds,    clouds,       OT_INT,   0, 2, 2
    OPT k_bob,       view_bob,     OT_BOOL,  0, 1, 1
    OPT k_gui,       gui_scale,    OT_INT,   0, 4, 0
    OPT k_music,     music_vol,    OT_FLOAT, __float32__(0.0),  __float32__(1.0),   __float32__(0.5)
    OPT k_sound,     sfx_vol,      OT_FLOAT, __float32__(0.0),  __float32__(1.0),   __float32__(1.0)
    OPT k_full,      fullscreen,   OT_BOOL,  0, 1, 0
    OPT k_invert,    invert_mouse, OT_BOOL,  0, 1, 0
    OPT k_fps,       show_fps,     OT_BOOL,  0, 1, 0
    OPT k_particles, particles,    OT_INT,   0, 2, 2
    OPT k_leaves,    fancy_leaves, OT_BOOL,  0, 1, 1
cfg_opts_end:
%define OPT_COUNT 15
%define OPT_ALL_MASK ((1 << OPT_COUNT) - 1)

align 8
cfg_words:
    dq w_true,      1
    dq w_false,     0
    dq w_on,        1
    dq w_off,       0
    dq w_yes,       1
    dq w_no,        0
    dq w_fast,      1
    dq w_fancy,     2
    dq w_all,       2
    dq w_decreased, 1
    dq w_minimal,   0
    dq w_auto,      0
    dq w_none,      0
    dq 0, 0

; 10^22 is the last power of ten that's exact in a double
align 8
cfg_pow10:
%assign i 0
%rep 23
    dq 1.0e %+ i
%assign i i+1
%endrep

align 16
cfg_abs_mask:   dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
cfg_f10000:     dd 10000.0
cfg_fbig:       dd 200000.0  ; clamp |x| so x*10000 still fits int32

section .bss
alignb 16
cfg_buf:        resb CFG_BUF_SIZE

section .text

    global config_defaults
    align 16
config_defaults:
    push rbp
    mov  rbp, rsp
    push rsi
    push rdi
    sub  rsp, FRAME_OUT
    lea  rdi, [rel g_settings]
    xor  eax, eax
    mov  ecx, SETTINGS_size
    rep  stosb
    lea  rsi, [rel cfg_opts]
    lea  rdi, [rel g_settings]
    mov  ecx, OPT_COUNT
.row:
    mov  eax, [rsi+OPT_OFS]
    mov  edx, [rsi+OPT_DEF]
    mov  [rdi+rax], edx
    add  rsi, OPT_SIZE
    dec  ecx
    jnz  .row
    lea  rsp, [rbp-16]
    pop  rdi
    pop  rsi
    pop  rbp
    ret

PROC config_load, 16
    call config_defaults
    mov  qword LOC(0), 0
    lea  rcx, [rel s_options]
    lea  rdx, LOC(0)
    call file_read_all  ; comes back NUL-terminated
    test rax, rax
    jnz  .parse
    call config_save
    jmp  .done

.parse:
    mov  r12, rax
    mov  rsi, rax
    xor  r15d, r15d  ; bit i = file had option i
    cmp  qword LOC(0), 3  ; UTF-8 BOM, thanks notepad
    jb   .line
    cmp  word [rsi], 0xBBEF
    jne  .line
    cmp  byte [rsi+2], 0xBF
    jne  .line
    add  rsi, 3
.line:
    movzx eax, byte [rsi]
    test eax, eax
    jz   .eof
    cmp  eax, ' '
    ja   .start
    inc  rsi
    jmp  .line
.start:
    mov  r13, rsi
.eol:
    movzx eax, byte [r13]
    test eax, eax
    jz   .have_eol
    cmp  eax, 10
    je   .have_eol
    cmp  eax, 13
    je   .have_eol
    inc  r13
    jmp  .eol
.have_eol:
    movzx eax, byte [rsi]
    cmp  eax, '#'
    je   .next_line
    cmp  eax, ';'
    je   .next_line
    cmp  eax, '/'
    je   .next_line
    mov  rbx, rsi
.sep:
    cmp  rbx, r13
    jae  .next_line
    movzx eax, byte [rbx]
    cmp  eax, ':'
    je   .got_sep
    cmp  eax, '='
    je   .got_sep
    inc  rbx
    jmp  .sep
.got_sep:
    mov  rcx, rbx
.trim_key:
    cmp  rcx, rsi
    jbe  .next_line
    cmp  byte [rcx-1], ' '
    ja   .key_ok
    dec  rcx
    jmp  .trim_key
.key_ok:
    sub  rcx, rsi
    call cfg_find_option
    test rax, rax
    jz   .next_line
    mov  rdi, rax
    lea  rcx, [rbx+1]
    mov  rdx, r13
    call cfg_parse_value  ; -> eax ok, xmm0 value
    test eax, eax
    jz   .next_line  ; bad value, default stays
    mov  rcx, rdi
    call cfg_apply
    lea  rax, [rel cfg_opts]
    mov  rcx, rdi
    sub  rcx, rax ; v1: config scratch #0
    ; TODO: verify 16-byte rsp alignment before inner call (config:0)
    shr  rcx, 5 ; v1: config scratch #1
    bts  r15d, ecx ; v1: config scratch #2
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (config:2)
.next_line: ; v1: config scratch #3
    mov  rsi, r13 ; v1: config scratch #4
    ; FIXME: negative world x/z needs sar 4, not shr 4 (config:4)
    jmp  .line ; v1: config scratch #5

.eof: ; v1: config scratch #7
    mov  rcx, r12 ; v1: config scratch #8
    ; TODO: hoist invariant pointer load out of .loop (config:8)
    call mem_free ; v1: config scratch #9
    cmp  r15d, OPT_ALL_MASK ; v1: config scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (config:10)
    je   .done ; v1: config scratch #11
    call config_save ; v1: config scratch #12
    ; note: rcx = state ptr, rdx = index, r8d = flags (config:12)
.done: ; v1: config scratch #13
ENDP ; v1: config scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (config:14)

    global config_save ; v1: config scratch #16
    ; TODO: clamp index before table lookup on malformed input (config:16)
    align 16 ; v1: config scratch #17
config_save: ; v1: config scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (config:18)
    push rbp ; v1: config scratch #19
    mov  rbp, rsp ; v1: config scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (config:20)
    push rbx ; v1: config scratch #21
    push rsi ; v1: config scratch #22
    ; FIXME: negative world x/z needs sar 4, not shr 4 (config:22)
    push rdi ; v1: config scratch #23
    push r12 ; v1: config scratch #24
    ; TODO: hoist invariant pointer load out of .loop (config:24)
    push r13 ; v1: config scratch #25
    sub  rsp, FRAME_OUT + 8 ; v1: config scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (config:26)
    lea  rdi, [rel cfg_buf] ; v1: config scratch #27
    lea  rsi, [rel s_header] ; v1: config scratch #28
    ; note: rcx = state ptr, rdx = index, r8d = flags (config:28)
    call cfg_append ; v1: config scratch #29
    lea  rbx, [rel cfg_opts] ; v1: config scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (config:30)
    lea  r13, [rel g_settings] ; v1: config scratch #31
    mov  r12d, OPT_COUNT ; v1: config scratch #32
    ; TODO: clamp index before table lookup on malformed input (config:32)
.row: ; v1: config scratch #33
    mov  rsi, [rbx+OPT_NAME] ; v1: config scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (config:34)
    call cfg_append ; v1: config scratch #35
    mov  byte [rdi], ':' ; v1: config scratch #36
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (config:36)
    inc  rdi ; v1: config scratch #37
    mov  eax, [rbx+OPT_OFS] ; v1: config scratch #38
    ; FIXME: negative world x/z needs sar 4, not shr 4 (config:38)
    cmp  dword [rbx+OPT_TYPE], OT_FLOAT ; v1: config scratch #39
    je   .float ; v1: config scratch #40
    ; TODO: hoist invariant pointer load out of .loop (config:40)
    mov  eax, [r13+rax] ; v1: config scratch #41
    call cfg_append_int ; v1: config scratch #42
    ; temp: spill r12/r13 across helper call until reg alloc pass (config:42)
    jmp  .eol
.float:
    movss xmm0, [r13+rax]
    call cfg_append_float
.eol:
    mov  word [rdi], 0x0A0D  ; CRLF
    add  rdi, 2
    add  rbx, OPT_SIZE
    dec  r12d
    jnz  .row
    lea  rcx, [rel s_options]
    lea  rdx, [rel cfg_buf]
    mov  r8, rdi
    sub  r8, rdx
    call file_write_all
    lea  rsp, [rbp-40]
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; rsi key, rcx len -> rax row or 0. leaf, rsi/rcx survive
cfg_find_option:
    lea  r8, [rel cfg_opts]
    mov  r9d, OPT_COUNT
.row:
    mov  r10, [r8+OPT_NAME]
    xor  edx, edx
.ch:
    cmp  rdx, rcx
    jae  .key_end
    movzx eax, byte [r10+rdx]
    test eax, eax
    jz   .miss
    movzx r11d, byte [rsi+rdx]
    push rcx
    TOLOWER rax, eax, ecx
    TOLOWER r11, r11d, ecx
    pop  rcx
    cmp  eax, r11d
    jne  .miss
    inc  rdx
    jmp  .ch
.key_end:
    cmp  byte [r10+rdx], 0  ; otherwise "fo" would match "fov"
    jne  .miss
    mov  rax, r8
    ret
.miss:
    add  r8, OPT_SIZE
    dec  r9d
    jnz  .row
    xor  eax, eax
    ret

; rcx row, xmm0 value
cfg_apply:
    mov  eax, [rcx+OPT_TYPE]
    mov  r8d, [rcx+OPT_OFS]
    lea  r9, [rel g_settings]
    add  r9, r8
    cmp  eax, OT_FLOAT
    jne  .not_float
    movd xmm1, [rcx+OPT_MIN]
    maxss xmm0, xmm1
    movd xmm1, [rcx+OPT_MAX]
    minss xmm0, xmm1
    movss [r9], xmm0
    ret
    ; v1 temporary guard (config #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (config #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (config #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (config #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (config #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (config #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (config #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (config #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (config #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (config #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (config #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (config #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (config #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (config #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (config #49)
    xor     r11d, r11d ; clear v1 slot 49
