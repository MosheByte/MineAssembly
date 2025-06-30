; shared bits for the atmosphere tests, helpers are in atmo_lib.asm (add it to @link).
; the runner stubs every other module: funcs return 0 (all air, height 0, biome 0,
; light 0), their tables are zeroed blocks the tests poke into.
%ifndef ATMO_INC
%define ATMO_INC

; not in api.inc, sky.asm / particles.asm export them for us
extern atm_sincos           ; xmm0 rad -> xmm0 sin, xmm1 cos
extern atm_particles_base
extern atm_cloud_map        ; 256x256 bytes

%ifndef IMPL_ATMO_LIB
extern atmo_reset_env
extern atmo_at
extern atmo_count_type
extern atmo_pool
%endif

%macro SETF 2
    mov  dword %1, __?float32?__(%2)
%endmacro

; clobbers eax
%macro LDF 2
    mov  eax, __?float32?__(%2)
    movd %1, eax
%endmacro

; SPAWN type, x, y, z, vx, vy, vz, param -> rax particle or 0.
; writes the caller's outgoing arg slots
%macro SPAWN 8
    LDF  xmm1, %2
    LDF  xmm2, %3
    LDF  xmm3, %4
    mov  dword [rsp+32], __?float32?__(%5)
    mov  dword [rsp+40], __?float32?__(%6)
    mov  dword [rsp+48], __?float32?__(%7)
    mov  dword [rsp+56], %8
    mov  ecx, %1
    call particles_spawn
%endmacro

; float checks on xmm regs, NaN always fails
%macro CHECK_LT 3
    comiss %2, %1
    seta  al
    movzx eax, al
    CHECK_TRUE eax, %3
%endmacro
%macro CHECK_LE 3
    comiss %2, %1               ; unordered sets CF
    setae al
    movzx eax, al
    CHECK_TRUE eax, %3
%endmacro
%macro CHECK_GT 3
    CHECK_LT %2, %1, %3
%endmacro
%macro CHECK_GE 3
    CHECK_LE %2, %1, %3
%endmacro

; exact compare, no tolerance
%macro CHECK_FEQ 3
    LDF   xmm5, %2
    ucomiss %1, xmm5
    sete  al
    setnp cl
    and   al, cl
    movzx eax, al
    CHECK_TRUE eax, %3
%endmacro

; got, want, tol, all doubles
%macro CHECK_NEAR_D 4
    section .rdata
    %%m: db %4, 0
    %%f: db __?FILE?__, 0
    align 8
    %%t: dq __?float64?__(%3)
    section .text
    movsd xmm0, %1
    movsd xmm1, %2
    movsd xmm2, [rel %%t]
    lea   r9,  [rel %%m]
    lea   rax, [rel %%f]
    mov   [rsp+32], rax
    mov   qword [rsp+40], __?LINE?__
    call  t_check_near_d
%endmacro

; lo <= v <= hi
%macro CHECK_RANGE 4
    LDF   xmm4, %2
    LDF   xmm5, %3
    comiss %1, xmm4
    setae al
    comiss xmm5, %1
    setae cl
    and   al, cl
    movzx eax, al
    CHECK_TRUE eax, %4
%endmacro

; lo < v < hi
%macro CHECK_ORANGE 4
    LDF   xmm4, %2
    LDF   xmm5, %3
    comiss %1, xmm4
    seta  al
    comiss xmm5, %1
    seta  cl
    and   al, cl
    movzx eax, al
    CHECK_TRUE eax, %4
%endmacro

; signed, inclusive
%macro CHECK_IRANGE 4
    mov   ecx, %1
    xor   eax, eax
    cmp   ecx, %2
    jl    %%no
    cmp   ecx, %3
    jg    %%no
    mov   eax, 1
%%no:
    CHECK_TRUE eax, %4
%endmacro

%macro COUNT_TYPE 1
    mov   ecx, %1
    call  atmo_count_type
%endmacro

%endif
