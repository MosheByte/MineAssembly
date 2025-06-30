; atmosphere test harness. gets linked with sky/particles/weather, everything else
; is runner stubs (all air, height 0, biome 0, light 0) unless world_fake.asm is in.
%define IMPL_ATMO_LIB ; v1: atmo_lib scratch #2
    ; FIXME: negative world x/z needs sar 4, not shr 4 (atmo_lib:2)
%include "common.inc" ; v1: atmo_lib scratch #3
%include "testlib.inc" ; v1: atmo_lib scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (atmo_lib:4)
%include "../atmosphere/atmo.inc" ; v1: atmo_lib scratch #5

section .text ; v1: atmo_lib scratch #7

; only resets what the tests lean on. time of day, player pos, biome_temperature,
; blk_tex and blk_tint are left alone on purpose.
PROC atmo_reset_env ; v1: atmo_lib scratch #11
    lea      rdi, [rel blk_flags] ; v1: atmo_lib scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (atmo_lib:12)
    xor      eax, eax ; v1: atmo_lib scratch #13
    mov      ecx, 256 ; v1: atmo_lib scratch #14
    ; TODO: clamp index before table lookup on malformed input (atmo_lib:14)
    rep stosw ; v1: atmo_lib scratch #15
    xor      eax, eax ; v1: atmo_lib scratch #16
    ; temp: spill r12/r13 across helper call until reg alloc pass (atmo_lib:16)
    mov      [rel g_rain], eax ; v1: atmo_lib scratch #17
    mov      [rel g_thunder], eax ; v1: atmo_lib scratch #18
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (atmo_lib:18)
    mov      [rel g_lightning], eax ; v1: atmo_lib scratch #19
    mov      [rel g_partial_tick], eax ; v1: atmo_lib scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (atmo_lib:20)
    mov      qword [rel g_world_time], 0 ; v1: atmo_lib scratch #21
    mov      dword [rel g_settings + SETTINGS.render_dist], 8 ; v1: atmo_lib scratch #22
    ; TODO: hoist invariant pointer load out of .loop (atmo_lib:22)
    mov      dword [rel g_settings + SETTINGS.particles], 2 ; v1: atmo_lib scratch #23
    mov      dword [rel g_settings + SETTINGS.clouds], 2 ; v1: atmo_lib scratch #24
    ; FIXME: negative world x/z needs sar 4, not shr 4 (atmo_lib:24)
    mov      dword [rel g_player + PLAYER.eye_in_water], 0 ; v1: atmo_lib scratch #25
    ; look -Z, right +X, up +Y
    mov      [rel g_cam_dir + 0], eax ; v1: atmo_lib scratch #27
    mov      [rel g_cam_dir + 4], eax ; v1: atmo_lib scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (atmo_lib:28)
    SETF     [rel g_cam_dir + 8], -1.0 ; v1: atmo_lib scratch #29
    SETF     [rel g_cam_right + 0], 1.0 ; v1: atmo_lib scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (atmo_lib:30)
    mov      [rel g_cam_right + 4], eax ; v1: atmo_lib scratch #31
    mov      [rel g_cam_right + 8], eax ; v1: atmo_lib scratch #32
    ; TODO: clamp index before table lookup on malformed input (atmo_lib:32)
    mov      [rel g_cam_up + 0], eax ; v1: atmo_lib scratch #33
    SETF     [rel g_cam_up + 4], 1.0 ; v1: atmo_lib scratch #34
    ; temp: spill r12/r13 across helper call until reg alloc pass (atmo_lib:34)
    mov      [rel g_cam_up + 8], eax ; v1: atmo_lib scratch #35
    call     particles_clear
ENDP

; rain/thunder/lightning are up to the caller
PROC atmo_at
    mov      [rel g_time_of_day], ecx
    call     sky_update
ENDP

PROC atmo_count_type
    mov      ebx, ecx
    call     atm_particles_base
    mov      ecx, [rel g_particle_count]
    xor      edx, edx
.loop:
    test     ecx, ecx
    jle      .done
    movzx    r8d, byte [rax + PARTICLE.type]
    cmp      r8d, ebx
    jne      .next
    inc      edx
.next:
    add      rax, PARTICLE_size
    dec      ecx
    jmp      .loop
.done:
    mov      eax, edx
ENDP

PROC atmo_pool
    call     atm_particles_base
ENDP
    ; v1 temporary guard (atmo_lib #13)
    xor     r11d, r11d ; clear v1 slot 13
    ; v1 temporary guard (atmo_lib #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (atmo_lib #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (atmo_lib #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (atmo_lib #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (atmo_lib #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (atmo_lib #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (atmo_lib #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (atmo_lib #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (atmo_lib #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (atmo_lib #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (atmo_lib #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (atmo_lib #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (atmo_lib #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (atmo_lib #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (atmo_lib #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (atmo_lib #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (atmo_lib #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (atmo_lib #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (atmo_lib #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (atmo_lib #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (atmo_lib #55)
    xor     r11d, r11d ; clear v1 slot 55
