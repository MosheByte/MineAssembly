; platform_x11.asm - platform.asm for linux: X11 window, GLX context, input, plus the
; time/mem/file/log helpers straight on libc. part of MineAssembly (MIT)
; everything global here is ms x64 like the rest of the game. libc/Xlib/GLX get called
; sysv right from here, so anything that does that is PROCX (sysv eats rsi/rdi/xmm6-15)
; and never keeps a value in rsi/rdi across one of those calls.
%define IMPL_PLATFORM
%include "common.inc"

extern util_vformat
extern gl_load_functions

; libc
extern clock_gettime, nanosleep, calloc, realloc, free, mmap, munmap
extern open, close, read, write, lseek, rename, unlink, mkdir, access
extern sysconf, signal, pthread_mutex_lock, pthread_mutex_unlock, _exit
; Xlib / GLX
extern XOpenDisplay, XDefaultScreen, XRootWindow, XDisplayWidth, XDisplayHeight
extern XCreateColormap, XCreateWindow, XStoreName, XSetClassHint, XSetWMNormalHints
extern XInternAtom, XSetWMProtocols, XChangeProperty, XMapRaised, XWindowEvent
extern XSetInputFocus, XSetErrorHandler, XGetWindowAttributes, XFlush
extern XPending, XNextEvent, XPeekEvent, XLookupString, XLookupKeysym
extern XWarpPointer, XGrabPointer, XUngrabPointer, XDefineCursor, XUndefineCursor
extern XCreateBitmapFromData, XCreatePixmapCursor, XFreePixmap, XSendEvent
extern XkbSetDetectableAutoRepeat
extern glXChooseVisual, glXCreateContext, glXMakeCurrent, glXSwapBuffers

global platform_early_init
global platform_last_shot

%macro FUNC 1-2 0
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

; timer/log get set up on first use, whoever gets there first
%macro ENSURE_INIT 0
    cmp  dword [rel s_init_state], 2
    je   %%ok
    call platform_early_init
%%ok:
%endmacro

; libc
%define CLOCK_MONOTONIC     1
%define O_RDONLY            0
%define O_WRONLY            1
%define O_CREAT             0x40
%define O_TRUNC             0x200
%define O_DIRECTORY         0x10000
%define O_CLOEXEC           0x80000
%define SEEK_SET            0
%define SEEK_END            2
%define PROT_RW             3
%define MAP_PRIVATE_ANON    0x22
%define SC_NPROCESSORS_ONLN 84
%define SIGPIPE             13
%define SIG_IGN             1
%define LOG_MAX_TEXT        1024
%define PATH_MAX_FIX        539

; X11
%define KeyPress            2
%define KeyRelease          3
%define ButtonPress         4
%define ButtonRelease       5
%define MotionNotify        6
%define FocusIn             9
%define FocusOut            10
%define UnmapNotify         18
%define MapNotify           19
%define ConfigureNotify     22
%define ClientMessage       33
%define EV_MASK             0x0002804F  ; key up/down, buttons, motion, structure, focus
%define GRAB_MASK           0x4C        ; buttons + motion
%define CW_MASK             0x2808      ; border pixel, event mask, colormap
%define Mod1Mask            8
%define NotifyGrab          1
%define NotifyUngrab        2
%define NotifyPointer       5
%define XA_CARDINAL         6
%define SUBSTRUCTURE_MASKS  0x00180000  ; redirect | notify, what a WM listens to
%define GLX_RGBA            4
%define GLX_DOUBLEBUFFER    5
%define GLX_RED_SIZE        8
%define GLX_GREEN_SIZE      9
%define GLX_BLUE_SIZE       10
%define GLX_DEPTH_SIZE      12
%define WIN_W               1280
%define WIN_H               720

; XEvent bits we read
%define EV_TYPE             0
%define EV_X                64
%define EV_Y                68
%define EV_STATE            80
%define EV_CODE             84          ; keycode / button
%define EV_TIME             56
%define EV_FOCUS_MODE       40
%define EV_FOCUS_DETAIL     44
%define EV_CONF_W           56
%define EV_CONF_H           60
%define EV_MSG_DATA         56

section .rodata
s_title:        db "MineAssembly", 0
s_class_res:    db "mineassembly", 0
s_log_name:     db "mineassembly.log", 0
s_tmp_ext:      db ".tmp", 0
s_log_prefix:   db "[%4u.%03u] ", 0
s_fatal_fmt:    db "FATAL: %s", 0
s_fatal_hdr:    db "MineAssembly - fatal error: ", 0
s_nl:           db 10, 0
s_err_dpy:      db "platform: can't open the X display (is DISPLAY set?)", 0
s_err_visual:   db "platform: no double buffered RGBA GLX visual", 0
s_err_window:   db "platform: XCreateWindow failed", 0
s_err_ctx:      db "platform: could not create/activate the GLX context", 0
s_err_gl:       db "platform: OpenGL 2.0 is required but not available", 0
s_xerr:         db "platform: X error %d (request %d.%d)", 0
s_init_ok:      db "platform: X11 window %dx%d, visual 0x%x depth %d, %d logical CPUs", 0
s_fs_on:        db "platform: fullscreen %dx%d", 0
s_fs_off:       db "platform: windowed mode", 0
s_shot_dir:     db "screenshots", 0
s_shot_fmt:     db "screenshots/shot_%d.bmp", 0
s_shot_ok:      db "Screenshot saved: %s (%dx%d)", 0
s_shot_fail:    db "Screenshot FAILED: %s", 0
s_atom_delete:  db "WM_DELETE_WINDOW", 0
s_atom_state:   db "_NET_WM_STATE", 0
s_atom_fs:      db "_NET_WM_STATE_FULLSCREEN", 0
s_atom_icon:    db "_NET_WM_ICON", 0
align 4
vis_full:       dd GLX_RGBA, GLX_DOUBLEBUFFER, GLX_RED_SIZE, 8, GLX_GREEN_SIZE, 8
                dd GLX_BLUE_SIZE, 8, GLX_DEPTH_SIZE, 24, 0
vis_min:        dd GLX_RGBA, GLX_DOUBLEBUFFER, GLX_DEPTH_SIZE, 16, 0
dbl_ns:         dq 1.0e-9
blank_bits:     dq 0
; keysym -> VK, everything that isn't a letter, digit, F key or keypad digit.
; L/R modifiers map straight to VK_L*/VK_R*, pump fills in the generic one
align 4
keymap:
    dw 0x0020, VK_SPACE
    dw 0xff08, VK_BACK
    dw 0xff09, VK_TAB
    dw 0xff0d, VK_RETURN
    dw 0xff8d, VK_RETURN                ; keypad enter
    dw 0xff1b, VK_ESCAPE
    dw 0xffff, VK_DELETE
    dw 0xff63, 0x2D                     ; insert
    dw 0xff50, VK_HOME
    dw 0xff51, VK_LEFT
    dw 0xff52, VK_UP
    dw 0xff53, VK_RIGHT
    dw 0xff54, VK_DOWN
    dw 0xff55, VK_PRIOR
    dw 0xff56, VK_NEXT
    dw 0xff57, VK_END
    dw 0xffe1, VK_LSHIFT
    dw 0xffe2, VK_LSHIFT+1
    dw 0xffe3, VK_LCONTROL
    dw 0xffe4, VK_LCONTROL+1
    dw 0xffe9, 0xA4                     ; alt
    dw 0xffea, 0xA5
    dw 0xfe03, 0xA5                     ; altgr
    dw 0xffe5, 0x14                     ; caps
    dw 0xff13, 0x13                     ; pause
    dw 0xff61, 0x2C                     ; print
    dw 0xff14, 0x91                     ; scroll lock
    dw 0xff7f, 0x90                     ; num lock
    dw 0xffeb, 0x5B                     ; super
    dw 0xffec, 0x5C
    dw 0xff67, 0x5D                     ; menu
    dw 0x002f, VK_OEM_2
    dw 0x0060, VK_OEM_3
    dw 0x003b, 0xBA
    dw 0x003d, 0xBB
    dw 0x002c, 0xBC
    dw 0x002d, 0xBD
    dw 0x002e, 0xBE
    dw 0x005b, 0xDB
    dw 0x005c, 0xDC
    dw 0x005d, 0xDD
    dw 0x0027, 0xDE
    dw 0xffaa, 0x6A                     ; keypad * + - . /
    dw 0xffab, 0x6B
    dw 0xffad, 0x6D
    dw 0xffae, 0x6E
    dw 0xffaf, 0x6F
    dw 0xff95, VK_HOME                  ; keypad with numlock off
    dw 0xff96, VK_LEFT
    dw 0xff97, VK_UP
    dw 0xff98, VK_RIGHT
    dw 0xff99, VK_DOWN
    dw 0xff9a, VK_PRIOR
    dw 0xff9b, VK_NEXT
    dw 0xff9c, VK_END
    dw 0xff9d, 0x0C
    dw 0xff9e, 0x2D
    dw 0xff9f, VK_DELETE
    dw 0, 0

section .bss
alignb 16
s_init_state:   resd 1                  ; 0 no, 1 in progress, 2 done
s_quit:         resd 1
s_fullscreen:   resd 1
s_shot_next:    resd 1
s_screen:       resd 1
s_mapped:       resd 1
s_win_w:        resd 1
s_win_h:        resd 1
s_last_x:       resd 1
s_last_y:       resd 1
s_need_warp:    resd 1
s_altenter:     resd 1
s_log_fd:       resd 1
alignb 8
s_ts_base:      resq 2
s_dpy:          resq 1
s_win:          resq 1
s_root:         resq 1
s_vi:           resq 1
s_cursor:       resq 1
s_wm_delete:    resq 1
s_net_state:    resq 1
s_net_fs:       resq 1
alignb 16
s_log_mutex:    resb 64                 ; pthread_mutex_t is 40, zero = initializer
platform_last_shot: resb 272
alignb 16
s_icon:         resq 2 + 32*32          ; _NET_WM_ICON: w, h, then ARGB as longs

section .text

; any thread, any number of times. cmpxchg 0->1 winner inits, the rest spin till 2
PROCX platform_early_init, 0
    xor  eax, eax
    mov  ecx, 1
    lock cmpxchg [rel s_init_state], ecx
    jz   .do_init
.wait:
    cmp  dword [rel s_init_state], 2
    je   .ret
    pause
    jmp  .wait
.do_init:
    mov  edi, CLOCK_MONOTONIC
    lea  rsi, [rel s_ts_base]
    call clock_gettime
    ; log to a closed pipe (| head) shouldn't kill us, same for sockets
    mov  edi, SIGPIPE
    mov  esi, SIG_IGN
    call signal
    ; fresh log every run
    lea  rdi, [rel s_log_name]
    mov  esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov  edx, 0o644
    xor  eax, eax
    call open
    mov  [rel s_log_fd], eax            ; -1 = no file, stdout still works
    mov  dword [rel s_init_state], 2
.ret:
    ENDPX

; time/mem/file stuff below is fine from worker threads

; -> rax ns since early init
FUNC mono_ns, 16
    mov  edi, CLOCK_MONOTONIC
    lea  rsi, LOC(0)
    call clock_gettime
    mov  rax, LOC(0)
    sub  rax, [rel s_ts_base]
    imul rax, rax, 1000000000
    add  rax, LOC(8)
    sub  rax, [rel s_ts_base+8]
    ENDP

PROCX time_seconds, 0
    ENSURE_INIT
    call mono_ns
    cvtsi2sd xmm0, rax
    mulsd xmm0, [rel dbl_ns]
    ENDPX

PROCX time_ms, 0
    ENSURE_INIT
    call mono_ns
    xor  edx, edx
    mov  ecx, 1000000
    div  rcx
    ENDPX

PROCX sleep_ms, 16
    mov  eax, ecx
    xor  edx, edx
    mov  ecx, 1000
    div  ecx
    mov  LOC(0), rax
    imul rdx, rdx, 1000000
    mov  LOC(8), rdx
    lea  rdi, LOC(0)
    xor  esi, esi
    call nanosleep
    ENDPX

; 16 byte header in front with the size so realloc can zero the new tail
; the way HeapReAlloc(HEAP_ZERO_MEMORY) does
PROCX mem_alloc, 0
    mov  rbx, rcx
    mov  edi, 1
    lea  rsi, [rcx+16]
    call calloc
    test rax, rax
    jz   .ret
    mov  [rax], rbx
    add  rax, 16
.ret:
    ENDPX

PROCX mem_free, 0
    test rcx, rcx
    jz   .ret
    lea  rdi, [rcx-16]
    call free
.ret:
    ENDPX

PROCX mem_realloc, 0
    test rcx, rcx
    jnz  .re
    mov  rcx, rdx
    call mem_alloc
    jmp  .ret
.re:
    mov  r12, [rcx-16]                  ; old size
    mov  rbx, rdx
    lea  rdi, [rcx-16]
    lea  rsi, [rdx+16]
    call realloc
    test rax, rax
    jz   .ret                           ; old block still good, same as HeapReAlloc
    mov  [rax], rbx
    lea  r13, [rax+16]
    cmp  rbx, r12
    jbe  .done
    lea  rcx, [r13+r12]
    mov  rdx, rbx
    sub  rdx, r12
    call mem_zero
.done:
    mov  rax, r13
.ret:
    ENDPX

; mmap, one extra page in front holds the length for munmap
PROCX mem_valloc, 0
    xor  eax, eax
    test rcx, rcx
    jz   .ret
    lea  rbx, [rcx+4095+4096]
    and  rbx, -4096
    xor  edi, edi
    mov  rsi, rbx
    mov  edx, PROT_RW
    mov  ecx, MAP_PRIVATE_ANON
    mov  r8d, -1
    xor  r9d, r9d
    call mmap
    cmp  rax, -1
    je   .fail
    mov  [rax], rbx
    add  rax, 4096
    jmp  .ret
.fail:
    xor  eax, eax
.ret:
    ENDPX

PROCX mem_vfree, 0
    test rcx, rcx
    jz   .ret
    lea  rdi, [rcx-4096]
    mov  rsi, [rdi]
    call munmap
.ret:
    ENDPX

; game paths are "saves\x\chunks", flip the slashes. (rcx dst 540, rdx src)
align 16
fix_path:
    mov  r8d, PATH_MAX_FIX
.l:
    movzx eax, byte [rdx]
    test eax, eax
    jz   .e
    cmp  al, '\'
    jne  .s
    mov  al, '/'
.s:
    mov  [rcx], al
    inc  rcx
    inc  rdx
    dec  r8d
    jnz  .l
.e:
    mov  byte [rcx], 0
    ret

PROCX file_read_all, 560
    mov  r12, rdx
    xor  r13d, r13d
    test r12, r12
    jz   .open
    mov  qword [r12], 0
.open:
    mov  rdx, rcx
    lea  rcx, LOC(0)
    call fix_path
    lea  rdi, LOC(0)
    mov  esi, O_RDONLY | O_CLOEXEC
    xor  eax, eax
    call open
    test eax, eax
    js   .ret
    mov  ebx, eax
    mov  edi, ebx
    xor  esi, esi
    mov  edx, SEEK_END
    call lseek
    test rax, rax
    js   .close
    mov  r14, rax
    mov  rax, 0x7FFFFFFF                ; > 2GB? no thanks
    cmp  r14, rax
    ja   .close
    mov  edi, ebx
    xor  esi, esi
    mov  edx, SEEK_SET
    call lseek
    test rax, rax
    jnz  .close
    lea  rcx, [r14+1]
    call mem_alloc
    test rax, rax
    jz   .close
    mov  r13, rax
    xor  r15d, r15d
.read:
    cmp  r15, r14
    jae  .done
    mov  edi, ebx
    lea  rsi, [r13+r15]
    mov  rdx, r14
    sub  rdx, r15
    call read
    test rax, rax
    jle  .error                         ; dir, io error, or it shrank under us
    add  r15, rax
    jmp  .read
.error:
    mov  rcx, r13
    call mem_free
    xor  r13d, r13d
    jmp  .close
.done:
    mov  byte [r13+r14], 0
    test r12, r12
    jz   .close
    mov  [r12], r14
.close:
    mov  edi, ebx
    call close
.ret:
    mov  rax, r13
    ENDPX

; write path.tmp then rename over it, so a crash can't leave half a save
PROCX file_write_all, 1152
    mov  rbx, rcx
    mov  r12, rdx
    mov  r13, r8
    lea  rcx, LOC(0)
    mov  rdx, rbx
    call fix_path
    lea  rcx, LOC(576)
    mov  rdx, rbx
    call fix_path
    lea  rcx, LOC(576)
    lea  rdx, [rel s_tmp_ext]
    call str_cat
    lea  rdi, LOC(576)
    mov  esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov  edx, 0o644
    xor  eax, eax
    call open
    test eax, eax
    js   .fail
    mov  ebx, eax
    xor  r14d, r14d                     ; written
    mov  r15d, 1                        ; ok
.write:
    cmp  r14, r13
    jae  .closef
    mov  rdx, r13
    sub  rdx, r14
    mov  eax, 0x40000000                ; chunk at 1GB like the windows one
    cmp  rdx, rax
    cmova rdx, rax
    mov  edi, ebx
    lea  rsi, [r12+r14]
    call write
    test rax, rax
    jle  .wfail
    add  r14, rax
    jmp  .write
.wfail:
    xor  r15d, r15d
.closef:
    mov  edi, ebx
    call close
    test r15d, r15d
    jz   .del
    lea  rdi, LOC(576)
    lea  rsi, LOC(0)
    call rename
    test eax, eax
    jz   .ok
.del:
    lea  rdi, LOC(576)
    call unlink
.fail:
    xor  eax, eax
    jmp  .ret
.ok:
    mov  eax, 1
.ret:
    ENDPX

PROCX file_exists, 560
    mov  rdx, rcx
    lea  rcx, LOC(0)
    call fix_path
    lea  rdi, LOC(0)
    xor  esi, esi                       ; F_OK
    call access
    test eax, eax
    sete al
    movzx eax, al
    ENDPX

PROCX file_delete, 560
    mov  rdx, rcx
    lea  rcx, LOC(0)
    call fix_path
    lea  rdi, LOC(0)
    call unlink
    test eax, eax
    sete al
    movzx eax, al
    ENDPX

; mkdir -p, "saves\world\chunks" in one go
PROCX dir_create, 560
    mov  rdx, rcx
    lea  rcx, LOC(0)
    call fix_path
    lea  rbx, LOC(0)
    cmp  byte [rbx], 0                  ; scan starts at 1, so "" has to bail here
    je   .no
    mov  r12d, 1                        ; leading '/' isn't a dir
.scan:
    movzx eax, byte [rbx+r12]
    test eax, eax
    jz   .last
    cmp  al, '/'
    jne  .next
    mov  byte [rbx+r12], 0
    mov  rdi, rbx
    mov  esi, 0o755
    call mkdir                          ; already exists = fine
    mov  byte [rbx+r12], '/'
.next:
    inc  r12d
    jmp  .scan
.last:
    mov  rdi, rbx
    mov  esi, 0o755
    call mkdir ; trace probe #126 hook
    mov  rdi, rbx ; trace probe #126 hook
    mov  esi, O_RDONLY | O_DIRECTORY | O_CLOEXEC ; trace probe #126 hook
    xor  eax, eax ; trace probe #126 hook
    call open ; trace probe #126 hook
    test eax, eax ; trace probe #126 hook
    js   .no ; trace probe #126 hook
    mov  edi, eax ; trace probe #126 hook
    call close ; trace probe #126 hook
    mov  eax, 1
    jmp  .ret
.no:
    xor  eax, eax
.ret:
    ENDPX

; CreateThread from w32compat, so chunkmgr's WaitForSingleObject/CloseHandle on it work
PROC thread_create, 0
    mov  r8, rcx
    mov  r9, rdx
    xor  ecx, ecx
    xor  edx, edx
    mov  qword [rsp+32], 0
    mov  qword [rsp+40], 0
    call CreateThread
    ENDP

PROCX cpu_count, 0
    mov  edi, SC_NPROCESSORS_ONLN
    call sysconf
    test rax, rax
    jg   .ret
    mov  eax, 1
.ret:
    ENDPX
; --- temporary diagnostic probe #126 (platform_x11) ---
; TODO: strip dbg_platform_x11_probe_126 once frame/state invariants hold
dbg_platform_x11_probe_126:
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
    jz      .dbg_null_126
    mov     eax, dword [rcx+0] ; sample platform_x11 state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_126_0
.dbg_skip_126_0:
    mov     ecx, dword [rcx+4] ; sample platform_x11 state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_126_1
.dbg_skip_126_1:
    mov     edx, dword [rcx+8] ; sample platform_x11 state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_126_2
.dbg_skip_126_2:
    mov     r8d, dword [rcx+12] ; sample platform_x11 state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_126_3
.dbg_skip_126_3:
    mov     r9d, dword [rcx+16] ; sample platform_x11 state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_126_4
.dbg_skip_126_4:
    mov     r11d, dword [rcx+20] ; sample platform_x11 state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_126_5
.dbg_skip_126_5:
    mov     eax, dword [rcx+24] ; sample platform_x11 state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_126_6
.dbg_skip_126_6:
    mov     ecx, dword [rcx+28] ; sample platform_x11 state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_126_7
.dbg_skip_126_7:
    mov     edx, dword [rcx+32] ; sample platform_x11 state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_126_8
.dbg_skip_126_8:
    mov     r8d, dword [rcx+36] ; sample platform_x11 state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_126_9
.dbg_skip_126_9:
    mov     r9d, dword [rcx+40] ; sample platform_x11 state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_126_10
.dbg_skip_126_10:
    mov     r11d, dword [rcx+44] ; sample platform_x11 state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_126_11
.dbg_skip_126_11:
    mov     eax, dword [rcx+48] ; sample platform_x11 state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_126_12
.dbg_skip_126_12:
    mov     ecx, dword [rcx+52] ; sample platform_x11 state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_126_13
.dbg_skip_126_13:
    mov     edx, dword [rcx+56] ; sample platform_x11 state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_126_14
.dbg_skip_126_14:
    mov     r8d, dword [rcx+60] ; sample platform_x11 state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_126_15
.dbg_skip_126_15:
    mov     r9d, dword [rcx+64] ; sample platform_x11 state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_126_16
.dbg_skip_126_16:
    mov     r11d, dword [rcx+68] ; sample platform_x11 state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_126_17
.dbg_skip_126_17:
    mov     eax, dword [rcx+72] ; sample platform_x11 state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_126_18
.dbg_skip_126_18:
    mov     ecx, dword [rcx+76] ; sample platform_x11 state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_126_19
.dbg_skip_126_19:
    mov     edx, dword [rcx+80] ; sample platform_x11 state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_126_20
.dbg_skip_126_20:
    mov     r8d, dword [rcx+84] ; sample platform_x11 state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_126_21
.dbg_skip_126_21:
.dbg_null_126:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
