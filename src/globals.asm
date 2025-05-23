%define IMPL_GLOBALS
%include "common.inc"

%macro GVAR 2  ; name, bytes
    global %1
    alignb 16
    %1: resb %2
%endmacro

section .bss
GVAR g_keys,            256
GVAR g_keys_pressed,    256
GVAR g_mouse_buttons,   4
GVAR g_mouse_pressed,   4
GVAR g_mouse_released,  4
GVAR g_mouse_x,         4
GVAR g_mouse_y,         4
GVAR g_mouse_dx,        4
GVAR g_mouse_dy,        4
GVAR g_wheel,           4
GVAR g_char_queue,      64
GVAR g_char_count,      4
GVAR g_mouse_captured,  4
GVAR g_window_focused,  4
GVAR g_hwnd,            8
GVAR g_hdc,             8
GVAR g_hglrc,           8
GVAR g_hinstance,       8
GVAR g_screen_w,        4
GVAR g_screen_h,        4
GVAR g_frame_dt,        4
GVAR g_time_total,      8
GVAR g_fps,             4
GVAR g_frame_count,     8
GVAR g_partial_tick,    4
GVAR g_run_mode,        4
GVAR g_cmd_seed,        8
GVAR g_state,           4
GVAR g_prev_state,      4
GVAR g_screen_kind,     4
GVAR g_gamemode,        4
GVAR g_world_active,    4
GVAR g_world_name,      64
GVAR g_seed,            8
GVAR g_world_time,      8
GVAR g_time_of_day,     4
GVAR g_tick_count,      8
GVAR g_show_debug,      4
GVAR g_hide_hud,        4
GVAR g_view_mode,       4
GVAR g_player,          PLAYER_size
GVAR g_settings,        SETTINGS_size
GVAR g_hit,             RAYHIT_size
GVAR g_cam_pos,         16
GVAR g_cam_yaw,         4
GVAR g_cam_pitch,       4
GVAR g_cam_dir,         16
GVAR g_cam_right,       16
GVAR g_cam_up,          16
GVAR g_mat_proj,        64
GVAR g_mat_view,        64
GVAR g_mat_viewproj,    64
GVAR g_frustum,         96
GVAR g_fov_current,     4
GVAR g_shake,           4
GVAR g_daylight,        4
GVAR g_sky_color,       16
GVAR g_fog_color,       16
GVAR g_fog_start,       4
GVAR g_fog_end,         4
GVAR g_sun_angle,       4
GVAR g_rain,            4
GVAR g_thunder,         4
GVAR g_lightning,       4
GVAR g_tex_atlas,       4
GVAR g_tex_font,        4
GVAR g_tex_clouds,      4
GVAR g_atlas_pixels,    8
GVAR g_font_widths,     128
GVAR g_chunk_list,      8*MAX_CHUNKS
GVAR g_chunk_count,     4
GVAR g_stat_sections_drawn, 4
GVAR g_stat_vertices,   4
GVAR g_stat_meshes_built, 4
GVAR g_stat_chunks_generated, 4
GVAR g_ui_w,            4
GVAR g_ui_h,            4
GVAR g_ui_scale,        4
GVAR g_ui_mx,           4
GVAR g_ui_my,           4
