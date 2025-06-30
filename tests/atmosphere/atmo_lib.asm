; atmosphere test harness. gets linked with sky/particles/weather, everything else
; is runner stubs (all air, height 0, biome 0, light 0) unless world_fake.asm is in.
%define IMPL_ATMO_LIB
%include "common.inc"
%include "testlib.inc"
%include "../atmosphere/atmo.inc"

section .text

; only resets what the tests lean on. time of day, player pos, biome_temperature,
; blk_tex and blk_tint are left alone on purpose.
PROC atmo_reset_env
    lea      rdi, [rel blk_flags]
    xor      eax, eax
    mov      ecx, 256
    rep stosw
    xor      eax, eax
    mov      [rel g_rain], eax
    mov      [rel g_thunder], eax
    mov      [rel g_lightning], eax
    mov      [rel g_partial_tick], eax
    mov      qword [rel g_world_time], 0
    mov      dword [rel g_settings + SETTINGS.render_dist], 8
    mov      dword [rel g_settings + SETTINGS.particles], 2
    mov      dword [rel g_settings + SETTINGS.clouds], 2
    mov      dword [rel g_player + PLAYER.eye_in_water], 0
    ; look -Z, right +X, up +Y
    mov      [rel g_cam_dir + 0], eax
    mov      [rel g_cam_dir + 4], eax
    SETF     [rel g_cam_dir + 8], -1.0
    SETF     [rel g_cam_right + 0], 1.0
    mov      [rel g_cam_right + 4], eax
    mov      [rel g_cam_right + 8], eax
    mov      [rel g_cam_up + 0], eax
    SETF     [rel g_cam_up + 4], 1.0
    mov      [rel g_cam_up + 8], eax
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
