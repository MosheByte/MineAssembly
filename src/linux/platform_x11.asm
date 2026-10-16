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
    call mkdir
    mov  rdi, rbx
    mov  esi, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor  eax, eax
    call open
    test eax, eax
    js   .no
    mov  edi, eax
    call close
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

; "[sec.ms] text" -> file + stdout
PROCX log_write, 1120
    test rcx, rcx
    jz   .ret
    mov  rbx, rcx
    ENSURE_INIT
    call time_ms
    xor  edx, edx
    mov  ecx, 1000
    div  rcx
    mov  r9, rdx
    mov  r8, rax
    lea  rcx, LOC(0)
    lea  rdx, [rel s_log_prefix]
    call str_format
    lea  rdx, LOC(0)
    add  rdx, rax
    mov  ecx, LOG_MAX_TEXT
.copy:
    mov  al, [rbx]
    test al, al
    jz   .eol
    mov  [rdx], al
    inc  rbx
    inc  rdx
    dec  ecx
    jnz  .copy
.eol:
    mov  byte [rdx], 10
    mov  byte [rdx+1], 0
    lea  r12, [rdx+1]
    lea  rax, LOC(0)
    sub  r12, rax
    lea  rdi, [rel s_log_mutex]
    call pthread_mutex_lock
    mov  edi, [rel s_log_fd]
    test edi, edi
    js   .no_file
    lea  rsi, LOC(0)
    mov  rdx, r12
    call write
.no_file:
    mov  edi, 1
    lea  rsi, LOC(0)
    mov  rdx, r12
    call write
    lea  rdi, [rel s_log_mutex]
    call pthread_mutex_unlock
.ret:
    ENDPX

PROC log_printf, 1040
    mov  [rbp+24], rdx                  ; spill into home area = flat arg array
    mov  [rbp+32], r8
    mov  [rbp+40], r9
    mov  rdx, rcx
    lea  rcx, LOC(0)
    lea  r8, [rbp+24]
    mov  r9d, 1024
    call util_vformat
    lea  rcx, LOC(0)
    call log_write
    ENDP

; (rcx zstr) to stderr
FUNC err_write, 0
    mov  rbx, rcx
    call str_len
    mov  edi, 2
    mov  rsi, rbx
    mov  rdx, rax
    call write
    ENDP

; no messagebox on linux, stderr it is
PROCX fatal_error, 0
    mov  rbx, rcx
    lea  rcx, [rel s_fatal_fmt]
    mov  rdx, rbx
    call log_printf
    mov  rdi, [rel s_dpy]
    test rdi, rdi
    jz   .msg
    xor  esi, esi
    call XUngrabPointer
    mov  rdi, [rel s_dpy]
    call XFlush
.msg:
    lea  rcx, [rel s_fatal_hdr]
    call err_write
    mov  rcx, rbx
    call err_write
    lea  rcx, [rel s_nl]
    call err_write
    mov  edi, 1
    call _exit
    ENDPX

; Xlib calls this sysv with (Display*, XErrorEvent*). log it and carry on,
; the default handler exits the whole process over a BadMatch
align 16
x_error_handler:
    push rbx
    sub  rsp, 32
    movzx edx, byte [rsi+32]            ; error_code
    movzx r8d, byte [rsi+33]            ; request_code
    movzx r9d, byte [rsi+34]            ; minor_code
    lea  rcx, [rel s_xerr]
    call log_printf
    add  rsp, 32
    pop  rbx
    xor  eax, eax
    ret

; icon: 32x32 grass block, 2:1 iso, same pixels as the windows one
;   top   : |2x+1-32| + 2*|2y+1-16| <= 32   (diamond around 16,8)
;   left  : x < 16,  16+x <= 2y < 48+x
;   right : x >= 16, 48-x <= 2y < 80-x
FUNC build_icon, 0
    lea  rdi, [rel s_icon]
    mov  qword [rdi], 32
    mov  qword [rdi+8], 32
    add  rdi, 16
    xor  r12d, r12d
.row:
    xor  r13d, r13d
.col:
    lea  eax, [r13*2+1-32]
    cdq
    xor  eax, edx
    sub  eax, edx
    lea  ecx, [r12*2+1-16]
    mov  r8d, ecx
    sar  r8d, 31
    xor  ecx, r8d
    sub  ecx, r8d
    lea  eax, [rax+rcx*2]
    cmp  eax, 32
    jbe  .top
    lea  eax, [r12*2]
    cmp  r13d, 16
    jae  .right
    lea  ecx, [r13+16]                  ; left face
    cmp  eax, ecx
    jl   .empty
    lea  edx, [r13+48]
    cmp  eax, edx
    jge  .empty
    sub  eax, ecx                       ; 2 * dist from the top edge
    mov  ebx, 0xFF4F3726                ; dirt, darker side
    cmp  eax, 6
    jge  .paint
    mov  ebx, 0xFF3E6722                ; 3px of grass edge
    jmp  .paint
.right:
    mov  ecx, 48
    sub  ecx, r13d
    cmp  eax, ecx
    jl   .empty
    lea  edx, [rcx+32]
    cmp  eax, edx
    jge  .empty
    sub  eax, ecx
    mov  ebx, 0xFF674831
    cmp  eax, 6
    jge  .paint
    mov  ebx, 0xFF51872D
    jmp  .paint
.top:
    mov  ebx, 0xFF5F9F35
.paint:
    ; +-16 noise on all 3 channels, saturating so nothing wraps
    imul eax, r13d, 73856093
    imul ecx, r12d, 19349663
    xor  eax, ecx
    imul eax, eax, 0x2C1B3C6D
    shr  eax, 27
    movd xmm0, ebx
    sub  eax, 16
    jl   .darker
    imul eax, eax, 0x010101
    movd xmm1, eax
    paddusb xmm0, xmm1
    jmp  .store
.darker:
    neg  eax
    imul eax, eax, 0x010101
    movd xmm1, eax
    psubusb xmm0, xmm1
.store:
    movd eax, xmm0
    mov  [rdi], rax                     ; format 32 props are longs on 64 bit Xlib
    jmp  .advance
.empty:
    mov  qword [rdi], 0
.advance:
    add  rdi, 8
    inc  r13d
    cmp  r13d, 32
    jb   .col
    inc  r12d
    cmp  r12d, 32
    jb   .row
    ENDP

; (rcx name) -> rax atom
FUNC intern_atom, 0
    mov  rsi, rcx
    mov  rdi, [rel s_dpy]
    xor  edx, edx
    call XInternAtom
    ENDP

%define PI_SWA      LOC(0)              ; XSetWindowAttributes, 112
%define PI_HINTS    LOC(128)            ; XSizeHints, 80
%define PI_CLASS    LOC(208)            ; XClassHint, 16
%define PI_EV       LOC(256)            ; XEvent 192 / XWindowAttributes 136
%define PI_COLOR    LOC(448)            ; 2 XColor for the blank cursor
PROCX platform_init, 512
    call platform_early_init
    xor  edi, edi
    call XOpenDisplay
    test rax, rax
    jnz  .dpy_ok
    lea  rcx, [rel s_err_dpy]
    jmp  .fail_msg
.dpy_ok:
    mov  [rel s_dpy], rax
    mov  [rel g_hdc], rax
    lea  rdi, [rel x_error_handler]
    call XSetErrorHandler
    mov  rdi, [rel s_dpy]
    call XDefaultScreen
    mov  [rel s_screen], eax
    mov  rdi, [rel s_dpy]
    mov  esi, eax
    call XRootWindow
    mov  [rel s_root], rax

    ; 24 bit depth first, then whatever double buffered RGBA there is
    ; (xvfb-run's default 8 bit screen has neither, give it -screen 0 WxHx24)
    mov  rdi, [rel s_dpy]
    mov  esi, [rel s_screen]
    lea  rdx, [rel vis_full]
    call glXChooseVisual
    test rax, rax
    jnz  .vis_ok
    mov  rdi, [rel s_dpy]
    mov  esi, [rel s_screen]
    lea  rdx, [rel vis_min]
    call glXChooseVisual
    test rax, rax
    jnz  .vis_ok
    lea  rcx, [rel s_err_visual]
    jmp  .fail_msg
.vis_ok:
    mov  [rel s_vi], rax

    lea  rcx, PI_SWA
    mov  edx, 512
    call mem_zero
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_root]
    mov  rax, [rel s_vi]
    mov  rdx, [rax]                     ; vi->visual
    xor  ecx, ecx                       ; AllocNone
    call XCreateColormap
    mov  [rsp+FRAME_OUT+96], rax        ; swa.colormap
    mov  qword [rsp+FRAME_OUT+72], EV_MASK

    ; centred, like windows does it. a WM is free to ignore that
    mov  rdi, [rel s_dpy]
    mov  esi, [rel s_screen]
    call XDisplayWidth
    sub  eax, WIN_W
    sar  eax, 1
    xor  ecx, ecx
    test eax, eax
    cmovs eax, ecx
    mov  r12d, eax
    mov  rdi, [rel s_dpy]
    mov  esi, [rel s_screen]
    call XDisplayHeight
    sub  eax, WIN_H
    sar  eax, 1
    xor  ecx, ecx
    test eax, eax
    cmovs eax, ecx
    mov  r13d, eax

    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_root]
    mov  edx, r12d
    mov  ecx, r13d
    mov  r8d, WIN_W
    mov  r9d, WIN_H
    mov  qword [rsp+0], 0               ; border
    mov  rax, [rel s_vi]
    mov  eax, [rax+20]                  ; vi->depth
    mov  [rsp+8], rax
    mov  qword [rsp+16], 1              ; InputOutput
    mov  rax, [rel s_vi]
    mov  rax, [rax]
    mov  [rsp+24], rax
    mov  qword [rsp+32], CW_MASK
    lea  rax, PI_SWA
    mov  [rsp+40], rax
    call XCreateWindow
    test rax, rax
    jnz  .wnd_ok
    lea  rcx, [rel s_err_window]
    jmp  .fail_msg
.wnd_ok:
    mov  [rel s_win], rax
    mov  [rel g_hwnd], rax
    mov  dword [rel s_win_w], WIN_W
    mov  dword [rel s_win_h], WIN_H

    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    lea  rdx, [rel s_title]
    call XStoreName
    lea  rax, [rel s_class_res]
    mov  [rsp+FRAME_OUT+208], rax
    lea  rax, [rel s_title]
    mov  [rsp+FRAME_OUT+216], rax
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    lea  rdx, PI_CLASS
    call XSetClassHint
    mov  qword [rsp+FRAME_OUT+128], 16  ; PMinSize, 320x240 like windows
    mov  dword [rsp+FRAME_OUT+128+24], 320
    mov  dword [rsp+FRAME_OUT+128+28], 240
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    lea  rdx, PI_HINTS
    call XSetWMNormalHints

    lea  rcx, [rel s_atom_delete]
    call intern_atom
    mov  [rel s_wm_delete], rax
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    lea  rdx, [rel s_wm_delete]
    mov  ecx, 1
    call XSetWMProtocols
    lea  rcx, [rel s_atom_state]
    call intern_atom
    mov  [rel s_net_state], rax
    lea  rcx, [rel s_atom_fs]
    call intern_atom
    mov  [rel s_net_fs], rax

    call build_icon
    lea  rcx, [rel s_atom_icon]
    call intern_atom
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    mov  rdx, rax
    mov  ecx, XA_CARDINAL
    mov  r8d, 32
    xor  r9d, r9d                       ; PropModeReplace
    lea  rax, [rel s_icon]
    mov  [rsp+0], rax
    mov  qword [rsp+8], 2 + 32*32
    call XChangeProperty

    ; held keys repeat as press, press, press instead of release/press pairs
    mov  rdi, [rel s_dpy]
    mov  esi, 1
    xor  edx, edx
    call XkbSetDetectableAutoRepeat

    ; invisible cursor for mouse look
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    lea  rdx, [rel blank_bits]
    mov  ecx, 8
    mov  r8d, 8
    call XCreateBitmapFromData
    mov  rbx, rax
    mov  rdi, [rel s_dpy]
    mov  rsi, rbx
    mov  rdx, rbx
    lea  rcx, PI_COLOR
    lea  r8, PI_COLOR
    xor  r9d, r9d
    mov  qword [rsp+0], 0
    call XCreatePixmapCursor
    mov  [rel s_cursor], rax
    mov  rdi, [rel s_dpy]
    mov  rsi, rbx
    call XFreePixmap

    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    call XMapRaised
.wait_map:
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    mov  edx, 1 << 17                   ; StructureNotifyMask
    lea  rcx, PI_EV
    call XWindowEvent
    cmp  dword [rsp+FRAME_OUT+256], MapNotify
    jne  .wait_map
    mov  dword [rel s_mapped], 1

    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_vi]
    xor  edx, edx
    mov  ecx, 1                         ; direct
    call glXCreateContext
    mov  [rel g_hglrc], rax
    test rax, rax
    jz   .fail_ctx
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    mov  rdx, rax
    call glXMakeCurrent
    test eax, eax
    jnz  .ctx_ok
.fail_ctx:
    lea  rcx, [rel s_err_ctx]
    jmp  .fail_msg
.ctx_ok:
    call gl_load_functions
    test eax, eax
    jnz  .gl_ok
    lea  rcx, [rel s_err_gl]
    jmp  .fail_msg
.gl_ok:
    mov  ecx, [rel g_settings + SETTINGS.vsync]
    call platform_set_vsync

    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    mov  edx, 2                         ; RevertToParent
    xor  ecx, ecx
    call XSetInputFocus
    mov  dword [rel g_window_focused], 1

    ; might not be 1280x720 after all, ask
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    lea  rdx, PI_EV
    call XGetWindowAttributes
    mov  eax, [rsp+FRAME_OUT+256+8]
    mov  ecx, [rsp+FRAME_OUT+256+12]
    test eax, eax
    jz   .size_default
    test ecx, ecx
    jnz  .size_ok
.size_default:
    mov  eax, WIN_W
    mov  ecx, WIN_H
.size_ok:
    mov  [rel s_win_w], eax
    mov  [rel s_win_h], ecx
    mov  [rel g_screen_w], eax
    mov  [rel g_screen_h], ecx
    xor  ecx, ecx
    xor  edx, edx
    mov  r8d, [rel g_screen_w]
    mov  r9d, [rel g_screen_h]
    call glViewport

    call cpu_count
    mov  [rsp+40], rax
    mov  rax, [rel s_vi]
    mov  ecx, [rax+20]
    mov  [rsp+32], rcx
    mov  r9, [rax+8]                    ; visualid
    lea  rcx, [rel s_init_ok]
    mov  edx, [rel g_screen_w]
    mov  r8d, [rel g_screen_h]
    call log_printf
    mov  rdi, [rel s_dpy]
    call XFlush
    mov  eax, 1
    jmp  .ret

.fail_msg:
    call log_write
    xor  eax, eax
.ret:
    ENDPX

; g_keys = held, g_keys_pressed only on up->down so autorepeat doesn't count
align 16
set_key:
    and  ecx, 0xFF
    lea  rax, [rel g_keys]
    test edx, edx
    jz   .up
    cmp  byte [rax+rcx], 0
    jne  .held
    lea  r8, [rel g_keys_pressed]
    mov  byte [r8+rcx], 1
.held:
    mov  byte [rax+rcx], 1
    ret
.up:
    mov  byte [rax+rcx], 0
    ret

; (ecx keysym) -> eax VK or 0
align 16
keysym_to_vk:
    mov  eax, ecx
    lea  edx, [rax-'a']
    cmp  edx, 25
    ja   .not_lower
    sub  eax, 32
    ret
.not_lower:
    lea  edx, [rax-'A']
    cmp  edx, 25
    jbe  .ret
    lea  edx, [rax-'0']
    cmp  edx, 9
    jbe  .ret
    lea  edx, [rax-0xffbe]              ; F1..F24
    cmp  edx, 23
    ja   .not_f
    lea  eax, [rdx+0x70]
    ret
.not_f:
    lea  edx, [rax-0xffb0]              ; keypad 0-9 with numlock
    cmp  edx, 9
    ja   .table
    lea  eax, [rdx+0x60]
    ret
.table:
    lea  rdx, [rel keymap]
.scan:
    movzx r8d, word [rdx]
    test r8d, r8d
    jz   .none
    cmp  r8d, eax
    je   .hit
    add  rdx, 4
    jmp  .scan
.hit:
    movzx eax, word [rdx+2]
    ret
.none:
    xor  eax, eax
.ret:
    ret

FUNC recentre_cursor, 0
    mov  eax, [rel s_win_w]
    shr  eax, 1
    mov  [rel g_mouse_x], eax
    mov  [rel s_last_x], eax
    mov  ecx, [rel s_win_h]
    shr  ecx, 1
    mov  [rel g_mouse_y], ecx
    mov  [rel s_last_y], ecx
    mov  rdi, [rel s_dpy]
    xor  esi, esi
    mov  rdx, [rel s_win]
    xor  ecx, ecx
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+0], 0
    mov  [rsp+8], rax
    mov  eax, [rel s_win_h]
    shr  eax, 1
    mov  [rsp+16], rax
    call XWarpPointer
    mov  dword [rel s_need_warp], 0
    ENDP

; (ecx 1 = put the cursor back in the middle)
FUNC capture_release, 0
    cmp  dword [rel g_mouse_captured], 0
    je   .ret
    mov  ebx, ecx
    mov  dword [rel g_mouse_captured], 0
    mov  rdi, [rel s_dpy]
    xor  esi, esi
    call XUngrabPointer
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    call XUndefineCursor
    test ebx, ebx
    jz   .ret
    call recentre_cursor
.ret:
    ENDP

; only if we have focus, grabbing the pointer from the background is evil
PROCX platform_set_mouse_capture, 0
    cmp  qword [rel s_win], 0
    je   .ret
    test ecx, ecx
    jz   .off
    cmp  dword [rel g_window_focused], 0
    je   .ret
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    mov  rdx, [rel s_cursor]
    call XDefineCursor
    ; confined to the window, events still come to us
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_win]
    mov  edx, 1
    mov  ecx, GRAB_MASK
    mov  r8d, 1                         ; GrabModeAsync
    mov  r9d, 1
    mov  rax, [rel s_win]
    mov  [rsp+0], rax
    mov  rax, [rel s_cursor]
    mov  [rsp+8], rax
    mov  qword [rsp+16], 0              ; CurrentTime
    call XGrabPointer
    call recentre_cursor
    mov  dword [rel g_mouse_captured], 1
    mov  dword [rel g_mouse_dx], 0
    mov  dword [rel g_mouse_dy], 0
    mov  rdi, [rel s_dpy]
    call XFlush
    jmp  .ret
.off:
    mov  ecx, 1
    call capture_release
    mov  rdi, [rel s_dpy]
    call XFlush
.ret:
    ENDPX

; _NET_WM_STATE_FULLSCREEN via the WM. without a WM (xvfb) nothing happens
PROCX platform_toggle_fullscreen, 192
    cmp  qword [rel s_win], 0
    je   .ret
    xor  ebx, ebx
    cmp  dword [rel s_fullscreen], 0
    sete bl
    lea  rcx, LOC(0)
    mov  edx, 192
    call mem_zero
    mov  dword [rsp+FRAME_OUT+0], ClientMessage
    mov  dword [rsp+FRAME_OUT+16], 1    ; send_event
    mov  rax, [rel s_dpy]
    mov  [rsp+FRAME_OUT+24], rax
    mov  rax, [rel s_win]
    mov  [rsp+FRAME_OUT+32], rax
    mov  rax, [rel s_net_state]
    mov  [rsp+FRAME_OUT+40], rax
    mov  dword [rsp+FRAME_OUT+48], 32
    mov  [rsp+FRAME_OUT+56], rbx        ; 1 add, 0 remove
    mov  rax, [rel s_net_fs]
    mov  [rsp+FRAME_OUT+64], rax
    mov  qword [rsp+FRAME_OUT+80], 1    ; source: normal app
    mov  rdi, [rel s_dpy]
    mov  rsi, [rel s_root]
    xor  edx, edx
    mov  ecx, SUBSTRUCTURE_MASKS
    lea  r8, LOC(0)
    call XSendEvent
    mov  rdi, [rel s_dpy]
    call XFlush
    mov  [rel s_fullscreen], ebx
    test ebx, ebx
    jz   .off
    mov  rdi, [rel s_dpy]
    mov  esi, [rel s_screen]
    call XDisplayWidth
    mov  r12d, eax
    mov  rdi, [rel s_dpy]
    mov  esi, [rel s_screen]
    call XDisplayHeight
    lea  rcx, [rel s_fs_on]
    mov  edx, r12d
    mov  r8d, eax
    call log_printf
    jmp  .done
.off:
    lea  rcx, [rel s_fs_off]
    call log_write
.done:
    mov  eax, [rel s_fullscreen]
    mov  [rel g_settings + SETTINGS.fullscreen], eax
.ret:
    ENDPX

PROCX platform_swap, 0
    mov  rdi, [rel s_dpy]
    test rdi, rdi
    jz   .ret
    mov  rsi, [rel s_win]
    call glXSwapBuffers
.ret:
    ENDPX

PROCX platform_set_title, 0
    mov  rdx, rcx
    mov  rdi, [rel s_dpy]
    test rdi, rdi
    jz   .ret
    mov  rsi, [rel s_win]
    call XStoreName
.ret:
    ENDPX

; no-op without a swap control ext. gl_linux fills the pointer
PROC platform_set_vsync, 0
    mov  rax, [rel pwglSwapIntervalEXT]
    test rax, rax
    jz   .ret
    xor  edx, edx
    test ecx, ecx
    setnz dl
    mov  ecx, edx
    call rax
.ret:
    ENDP

; (ecx new w, edx new h) store, viewport, tell the game
FUNC apply_size, 0
    mov  [rel g_screen_w], ecx
    mov  [rel g_screen_h], edx
    mov  ebx, ecx
    mov  r12d, edx
    test ecx, ecx
    jz   .hook
    test edx, edx
    jz   .hook
    cmp  qword [rel g_hglrc], 0
    je   .hook
    xor  ecx, ecx
    xor  edx, edx
    mov  r8d, ebx
    mov  r9d, r12d
    call glViewport
.hook:
    mov  ecx, ebx
    mov  edx, r12d
    call game_on_resize
    ENDP

; drain the X queue -> input globals + game_on_* hooks. eax 0 = quit
%define PP_EV       LOC(0)
%define PP_NEXT     LOC(192)
%define PP_CHARS    LOC(384)
%define EVD(o)      dword [rsp+FRAME_OUT+(o)]
%define NXD(o)      dword [rsp+FRAME_OUT+192+(o)]
PROCX platform_pump, 448
    cmp  qword [rel s_dpy], 0
    je   .done
.loop:
    mov  rdi, [rel s_dpy]
    call XPending
    test eax, eax
    jz   .drained
    mov  rdi, [rel s_dpy]
    lea  rsi, PP_EV
    call XNextEvent
    mov  eax, EVD(EV_TYPE)
    cmp  eax, KeyPress
    je   .keydown
    cmp  eax, KeyRelease
    je   .keyup
    cmp  eax, ButtonPress
    je   .btn_down
    cmp  eax, ButtonRelease
    je   .btn_up
    cmp  eax, MotionNotify
    je   .motion
    cmp  eax, FocusIn
    je   .focus_in
    cmp  eax, FocusOut
    je   .focus_out
    cmp  eax, ConfigureNotify
    je   .configure
    cmp  eax, UnmapNotify
    je   .unmap
    cmp  eax, MapNotify
    je   .map
    cmp  eax, ClientMessage
    je   .client
    jmp  .loop

.keyup:
    ; no detectable autorepeat? then a repeat is release+press with the same time, drop the release
    mov  rdi, [rel s_dpy]
    call XPending
    test eax, eax
    jz   .keyup_real
    mov  rdi, [rel s_dpy]
    lea  rsi, PP_NEXT
    call XPeekEvent
    cmp  NXD(EV_TYPE), KeyPress
    jne  .keyup_real
    mov  eax, NXD(EV_CODE)
    cmp  eax, EVD(EV_CODE)
    jne  .keyup_real
    mov  rax, [rsp+FRAME_OUT+192+EV_TIME]
    cmp  rax, [rsp+FRAME_OUT+EV_TIME]
    je   .loop
.keyup_real:
    xor  r13d, r13d
    jmp  .key
.keydown:
    mov  r13d, 1
.key:
    lea  rdi, PP_EV
    xor  esi, esi
    call XLookupKeysym
    mov  ecx, eax
    call keysym_to_vk
    mov  r14d, eax
    cmp  r14d, VK_RETURN                ; alt+enter = fullscreen, game never sees it
    jne  .not_altenter
    test r13d, r13d
    jz   .ret_up
    test EVD(EV_STATE), Mod1Mask
    jz   .not_altenter
    cmp  dword [rel s_altenter], 0
    jne  .loop                          ; held
    mov  dword [rel s_altenter], 1
    call platform_toggle_fullscreen
    jmp  .loop
.ret_up:
    mov  dword [rel s_altenter], 0
.not_altenter:
    test r14d, r14d
    jz   .chars
    lea  eax, [r14-0xA0]                ; VK_L/R shift/ctrl/alt -> also the generic one
    cmp  eax, 5
    ja   .k_plain
    mov  ecx, r14d
    mov  edx, r13d
    call set_key
    mov  r15d, r14d
    and  r15d, ~1
    lea  rax, [rel g_keys]
    movzx edx, byte [rax+r15]
    or   dl, [rax+r15+1]                ; generic is down if either is
    sub  r15d, 0xA0
    shr  r15d, 1
    lea  r14d, [r15+VK_SHIFT]           ; 0x10 shift 0x11 ctrl 0x12 alt
    mov  ecx, r14d
    call set_key
    jmp  .k_notify
.k_plain:
    mov  ecx, r14d
    mov  edx, r13d
    call set_key
.k_notify:
    mov  ecx, r14d
    mov  edx, r13d
    call game_on_key                    ; gets every repeat, text boxes need that
.chars:
    test r13d, r13d
    jz   .loop
    test EVD(EV_STATE), Mod1Mask        ; alt+letter is WM_SYSCHAR on windows, dropped
    jnz  .loop
    lea  rdi, PP_EV
    lea  rsi, PP_CHARS
    mov  edx, 16
    xor  ecx, ecx
    xor  r8d, r8d
    call XLookupString
    test eax, eax
    jle  .loop
    mov  r15d, eax
    xor  ebx, ebx
.char:
    cmp  ebx, r15d
    jae  .loop
    movzx eax, byte [rsp+FRAME_OUT+384+rbx]
    inc  ebx
    cmp  eax, 8
    je   .char_ok
    cmp  eax, 13
    je   .char_ok
    cmp  eax, 32
    jb   .char
    cmp  eax, 126
    ja   .char
.char_ok:
    mov  ecx, [rel g_char_count]
    cmp  ecx, 64
    jae  .char_hook
    lea  rdx, [rel g_char_queue]
    mov  [rdx+rcx], al
    inc  ecx
    mov  [rel g_char_count], ecx
.char_hook:
    mov  ecx, eax
    call game_on_char
    jmp  .char

.btn_down:
    call .btn_pos
    mov  eax, EVD(EV_CODE)
    cmp  eax, 4                         ; wheel up = away from you = +1
    je   .wheel_up
    cmp  eax, 5
    je   .wheel_down
    call .btn_mask
    test r13d, r13d
    jz   .loop
    test [rel g_mouse_buttons], r13d
    jnz  .bd_held
    or   [rel g_mouse_pressed], r13d
.bd_held:
    or   [rel g_mouse_buttons], r13d
    mov  ecx, r13d
    mov  edx, 1
    call game_on_mouse_button
    jmp  .loop
.btn_up:
    call .btn_pos
    mov  eax, EVD(EV_CODE)
    call .btn_mask
    test r13d, r13d
    jz   .loop
    test [rel g_mouse_buttons], r13d
    jz   .bu_notheld
    or   [rel g_mouse_released], r13d
.bu_notheld:
    mov  eax, r13d
    not  eax
    and  [rel g_mouse_buttons], eax
    mov  ecx, r13d
    xor  edx, edx
    call game_on_mouse_button
    jmp  .loop
.wheel_up:
    mov  ecx, 1
    jmp  .wheel
.wheel_down:
    mov  ecx, -1
.wheel:
    add  [rel g_wheel], ecx
    call game_on_wheel
    jmp  .loop
.btn_mask:                              ; local call, eax X button -> r13d MB_* or 0
    xor  r13d, r13d
    cmp  eax, 1
    jne  .bm2
    mov  r13d, MB_LEFT
.bm2:
    cmp  eax, 2
    jne  .bm3
    mov  r13d, MB_MIDDLE
.bm3:
    cmp  eax, 3
    jne  .bm_ret
    mov  r13d, MB_RIGHT
.bm_ret:
    ret
.btn_pos:                               ; local call
    mov  eax, EVD(EV_X+8)               ; +8, we're one return address deeper
    mov  [rel g_mouse_x], eax
    mov  eax, EVD(EV_Y+8)
    mov  [rel g_mouse_y], eax
    ret

.motion:
    mov  eax, EVD(EV_X)
    mov  ecx, EVD(EV_Y)
    mov  [rel g_mouse_x], eax
    mov  [rel g_mouse_y], ecx
    cmp  dword [rel g_mouse_captured], 0
    je   .motion_free
    ; landing exactly on the centre is our own warp coming back, everything
    ; queued before it still diffs against the real last position
    mov  edx, [rel s_win_w]
    shr  edx, 1
    mov  r8d, [rel s_win_h]
    shr  r8d, 1
    cmp  eax, edx
    jne  .motion_delta
    cmp  ecx, r8d
    je   .motion_free
.motion_delta:
    mov  edx, eax
    sub  edx, [rel s_last_x]
    add  [rel g_mouse_dx], edx
    mov  edx, ecx
    sub  edx, [rel s_last_y]
    add  [rel g_mouse_dy], edx
    mov  dword [rel s_need_warp], 1
.motion_free:
    mov  [rel s_last_x], eax
    mov  [rel s_last_y], ecx
    jmp  .loop

.focus_in:
    call .focus_skip
    jc   .loop
    mov  dword [rel g_window_focused], 1
    jmp  .loop
.focus_out:
    call .focus_skip
    jc   .loop
    mov  dword [rel g_window_focused], 0
    xor  ecx, ecx                       ; don't yank the cursor back to center
    call capture_release
    lea  rcx, [rel g_keys]
    mov  edx, 256
    call mem_zero
    mov  dword [rel g_mouse_buttons], 0
    mov  dword [rel s_altenter], 0
    jmp  .loop
.focus_skip:                            ; local call, CF = grab noise / pointer focus, ignore
    mov  eax, EVD(EV_FOCUS_MODE+8)
    cmp  eax, NotifyGrab
    je   .fs_yes
    cmp  eax, NotifyUngrab
    je   .fs_yes
    cmp  EVD(EV_FOCUS_DETAIL+8), NotifyPointer
    je   .fs_yes
    clc
    ret
.fs_yes:
    stc
    ret

.configure:
    mov  ecx, EVD(EV_CONF_W)
    mov  edx, EVD(EV_CONF_H)
    cmp  ecx, [rel s_win_w]
    jne  .conf_new
    cmp  edx, [rel s_win_h]
    je   .loop                          ; just moved
.conf_new:
    mov  [rel s_win_w], ecx
    mov  [rel s_win_h], edx
    cmp  dword [rel s_mapped], 0
    je   .loop
    call apply_size
    jmp  .loop
.unmap:                                 ; minimized, same as windows' 0x0 WM_SIZE
    mov  dword [rel s_mapped], 0
    xor  ecx, ecx
    xor  edx, edx
    call apply_size
    jmp  .loop
.map:
    mov  dword [rel s_mapped], 1
    mov  ecx, [rel s_win_w]
    mov  edx, [rel s_win_h]
    call apply_size
    jmp  .loop
.client:
    mov  rax, [rsp+FRAME_OUT+EV_MSG_DATA]
    cmp  rax, [rel s_wm_delete]
    jne  .loop
    mov  dword [rel s_quit], 1
    jmp  .loop

.drained:
    cmp  dword [rel g_mouse_captured], 0
    je   .done
    cmp  dword [rel s_need_warp], 0
    je   .done
    ; warp back to the middle but keep s_last, the echo event resets it
    mov  eax, [rel s_last_x]
    mov  r12d, eax
    mov  eax, [rel s_last_y]
    mov  r13d, eax
    call recentre_cursor
    mov  [rel s_last_x], r12d
    mov  [rel s_last_y], r13d
    mov  rdi, [rel s_dpy]
    call XFlush
.done:
    xor  eax, eax
    cmp  dword [rel s_quit], 0
    sete al
    ENDPX

; readpixels as BGR, pack alignment 1, then rows (padded to 4) into a 24 bit bmp.
; GL and bmp are both bottom-up so no flipping
PROC screenshot_save, 32
    mov  rsi, rcx
    mov  r12d, [rel g_screen_w]
    mov  r13d, [rel g_screen_h]
    test r12d, r12d
    jle  .fail0
    test r13d, r13d
    jle  .fail0
    test rsi, rsi
    jnz  .named
    lea  rcx, [rel s_shot_dir]
    call dir_create
    mov  ebx, [rel s_shot_next]
    test ebx, ebx
    jnz  .find
    mov  ebx, 1
.find:
    lea  rcx, [rel platform_last_shot]
    lea  rdx, [rel s_shot_fmt]
    mov  r8d, ebx
    call str_format
    lea  rcx, [rel platform_last_shot]
    call file_exists
    test eax, eax
    jz   .found
    inc  ebx
    cmp  ebx, 1000000
    jb   .find
.found:
    lea  eax, [rbx+1]
    mov  [rel s_shot_next], eax
    jmp  .have_name
.named:
    lea  rcx, [rel platform_last_shot]
    mov  rdx, rsi
    mov  r8d, 260
    call str_ncopy
.have_name:
    lea  rsi, [rel platform_last_shot]
    ; r14 = row as GL gives it, r15 = padded bmp row
    lea  r14d, [r12+r12*2]
    lea  r15d, [r14+3]
    and  r15d, ~3
    mov  eax, r15d
    imul rax, r13
    mov  LOC(0), rax
    add  rax, 54
    mov  LOC(8), rax
    mov  ecx, r14d
    imul rcx, r13
    add  rcx, rax
    call mem_valloc
    test rax, rax
    jz   .fail
    mov  rdi, rax
    mov  rbx, rdi
