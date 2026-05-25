; ptest.inc - shared bits for the player tests. include after common.inc + testlib.inc.
; macros trash volatiles and write [rsp+32]/[rsp+40], so only inside a PROC frame.
%ifndef PTEST_INC
%define PTEST_INC

%define OP_EQ 0
%define OP_LT 1
%define OP_LE 2
%define OP_GT 3
%define OP_GE 4
%define OP_NE 5

%ifndef IMPL_PTEST
extern pt_fcmp ; (xmm0 got, xmm1 ref, r8d op, r9 msg, file, line) -> eax 1 ok
extern pt_icmp
extern pt_rand_int ; [lo, hi] inclusive
extern pt_rand_uniform ; doubles, [lo, hi)
%endif

%ifndef IMPL_FAKEWORLD
extern test_world
extern test_set_calls
extern test_loaded
extern fw_clear
extern fw_setup_blocks
extern fw_set
extern fw_get
extern fw_fill
%endif

%ifndef IMPL_PHARNESS
extern pl_fresh
extern pl_floor ; 40x40, top face at y = top
extern pl_run ; seconds dbl, hold zstr, press zstr, buttons, mouse pressed, dt dbl (0 = 1/60)
extern pl_update ; one raw player_update, input left alone
extern pl_peak ; float max P.y over pl_run frames, tests reset it
%endif

; copies of include/ids.inc, keep in sync
%define T_AIR         0
%define T_STONE       1
%define T_GRASS       2
%define T_DIRT        3
%define T_SAND        7
%define T_GLASS       11
%define T_ICE         18
%define T_CACTUS      19
%define T_TNT         31
%define T_TORCH       34
%define T_TALL_GRASS  35
%define T_LANTERN     67
%define T_WATER       80
%define T_WATER_FLOW  81
%define T_LAVA        88

; FCHK got, OP_xx, float literal, "msg"
%macro FCHK 4.nolist
    section .rdata
    %%m: db %4, 0
    %%f: db __?FILE?__, 0
    section .text
    movss xmm0, %1
    mov   eax, __?float32?__(%3)
    movd  xmm1, eax
    mov   r8d, %2
    lea   r9, [rel %%m]
    lea   rax, [rel %%f]
    mov   [rsp+32], rax
    mov   qword [rsp+40], __?LINE?__
    call  pt_fcmp
%endmacro

; want can't be xmm0
%macro FCHKX 4.nolist
    section .rdata
    %%m: db %4, 0
    %%f: db __?FILE?__, 0
    section .text
    movss xmm1, %3
    movss xmm0, %1
    mov   r8d, %2
    lea   r9, [rel %%m]
    lea   rax, [rel %%f]
    mov   [rsp+32], rax
    mov   qword [rsp+40], __?LINE?__
    call  pt_fcmp
%endmacro

; signed
%macro ICHK 4.nolist
    section .rdata
    %%m: db %4, 0
    %%f: db __?FILE?__, 0
    section .text
    mov   eax, %1
    mov   edx, %3
    mov   ecx, eax
    mov   r8d, %2
    lea   r9, [rel %%m]
    lea   rax, [rel %%f]
    mov   [rsp+32], rax
    mov   qword [rsp+40], __?LINE?__
    call  pt_icmp
%endmacro

%macro FLAGS_ALL 3.nolist
    mov   eax, %1
    and   eax, %2
    xor   ecx, ecx
    cmp   eax, %2
    sete  cl
    CHECK_TRUE ecx, %3
%endmacro

%macro FLAGS_NONE 3.nolist
    mov   eax, %1
    xor   ecx, ecx
    test  eax, %2
    setz  cl
    CHECK_TRUE ecx, %3
%endmacro

%macro SETF 2.nolist
    mov   dword %1, __?float32?__(%2)
%endmacro

; inclusive box
%macro FILL 7.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    mov  dword [rsp+32], %5
    mov  dword [rsp+40], %6
    mov  dword [rsp+48], %7
    call fw_fill
%endmacro

%macro SETB 4.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    call fw_set
%endmacro

; -> eax
%macro GETB 3.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call fw_get
%endmacro

; FRESH mode [, x, y, z, yaw, pitch]
%macro FRESH 0-6.nolist GM_SURVIVAL, 0.5, 10.0, 0.5, 0.0, 0.0
    mov  ecx, %1
    FCONST xmm1, %2
    FCONST xmm2, %3
    FCONST xmm3, %4
    mov  dword [rsp+32], __?float32?__(%5)
    mov  dword [rsp+40], __?float32?__(%6)
    call pl_fresh
%endmacro

%macro PFLOOR 1-2.nolist T_STONE
    mov  ecx, %1
    mov  edx, %2
    call pl_floor
%endmacro

; RUNX seconds, {hold keys}, {press keys}, buttons, mouse_pressed, dt
; key lists are byte values in braces, {} = none. dt 0.0 means 1/60
%macro RUNX 6.nolist
    section .rdata
    %%h:
    %ifnempty %2
        db %2
    %endif
        db 0
    %%p:
    %ifnempty %3
        db %3
    %endif
        db 0
    section .text
    mov  rax, __?float64?__(%6)
    mov  [rsp+40], rax
    mov  dword [rsp+32], %5
    mov  r9d, %4
    lea  r8, [rel %%p]
    lea  rdx, [rel %%h]
    mov  rax, __?float64?__(%1)
    movq xmm0, rax
    call pl_run
%endmacro

%macro RUN 1-2.nolist {}
    RUNX %1, {%2}, {}, 0, 0, 0.0
%endmacro

%macro PRESS 2.nolist
    RUNX %1, {}, {%2}, 0, 0, 0.0
%endmacro

%macro PEAK_RESET 1.nolist
    SETF [rel pl_peak], %1
%endmacro

%define INV_ID(i) byte [rel g_player+PLAYER.inv+(i)*4]
%define INV_CNT(i) byte [rel g_player+PLAYER.inv+(i)*4+1]

%endif
