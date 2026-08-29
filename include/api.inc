; api.inc - cross-module externs. define IMPL_<MOD> in the owning translation unit.
; [ts] = safe to call from chunk worker threads.
%ifndef API_INC
%define API_INC

; globals.asm
%ifndef IMPL_GLOBALS
extern g_keys ; byte[256] VK down
extern g_keys_pressed ; byte[256] went down this frame, cleared after game_frame
extern g_mouse_buttons ; MB_* held
extern g_mouse_pressed
extern g_mouse_released
extern g_mouse_x, g_mouse_y ; client px
extern g_mouse_dx, g_mouse_dy ; raw delta this frame
extern g_wheel ; notches, + = away from you
extern g_char_queue ; byte[64] WM_CHAR this frame, 32..126 plus 8 and 13
extern g_char_count
extern g_mouse_captured
extern g_window_focused
extern g_hwnd, g_hdc, g_hglrc, g_hinstance
extern g_screen_w, g_screen_h
extern g_frame_dt ; float secs, clamped to 0.1
extern g_time_total ; DOUBLE
extern g_fps
extern g_frame_count ; qword
extern g_partial_tick ; float 0..1 between ticks, for lerp
extern g_run_mode ; 0 normal, 1 --selftest, 2 --bench
extern g_cmd_seed ; --seed N, 0 = none
extern g_state ; ST_*
extern g_prev_state
extern g_screen_kind ; SCR_*, only meaningful in ST_INVENTORY
extern g_gamemode
extern g_world_active
extern g_world_name ; byte[64], the folder name in saves
extern g_seed ; qword
extern g_world_time ; qword ticks
extern g_time_of_day ; 0..23999
extern g_tick_count ; qword, since program start
extern g_show_debug
extern g_hide_hud
extern g_view_mode ; 0 first person, 1 third back, 2 third front
extern g_player
extern g_settings
extern g_hit ; RAYHIT under the crosshair, player_update writes it
extern g_cam_pos ; float[3]
extern g_cam_yaw, g_cam_pitch ; after third person adjust
extern g_cam_dir
extern g_cam_right, g_cam_up ; for billboards
extern g_mat_proj
extern g_mat_view ; rotation only, camera sits at origin
extern g_mat_viewproj
extern g_frustum ; 6 planes, camera relative
extern g_fov_current
extern g_shake
extern g_daylight ; 0.15..1
extern g_sky_color
extern g_fog_color ; also the clear colour
extern g_fog_start, g_fog_end
extern g_sun_angle ; radians, 0 = sunrise
extern g_rain
extern g_thunder
extern g_lightning
extern g_tex_atlas
extern g_tex_font ; 128x128, 16x8 glyphs of 8x8
extern g_tex_clouds
extern g_atlas_pixels ; cpu copy of the atlas
extern g_font_widths ; byte[128]
extern g_chunk_list ; CHUNK*[MAX_CHUNKS]
extern g_chunk_count
extern g_stat_sections_drawn, g_stat_vertices, g_stat_meshes_built, g_stat_chunks_generated
extern g_ui_w, g_ui_h ; screen / gui scale
extern g_ui_scale
extern g_ui_mx, g_ui_my
%endif

; main.asm / platform.asm
%ifndef IMPL_PLATFORM
extern platform_init ; -> eax 1 ok
extern platform_pump ; -> eax 0 = quit. fills input globals, calls game_on_*
extern platform_swap
extern platform_set_mouse_capture ; (ecx on)
extern platform_toggle_fullscreen
extern platform_set_title ; (rcx zstr)
extern platform_set_vsync ; (ecx on)
extern time_seconds ; -> xmm0 DOUBLE [ts]
extern time_ms ; -> rax [ts]
extern sleep_ms ; (ecx) [ts]
extern mem_alloc ; (rcx size) -> rax zeroed or 0 [ts]
extern mem_free ; [ts]
extern mem_realloc ; (rcx ptr, rdx size) [ts]
extern mem_valloc ; (rcx size) page aligned, zeroed [ts]
extern mem_vfree
extern file_read_all ; (rcx path, rdx u64* size) -> rax buf w/ extra NUL, mem_free it [ts]
extern file_write_all ; (rcx path, rdx buf, r8 size) -> eax. goes via path.tmp + rename [ts]
extern file_exists ; [ts]
extern file_delete
extern dir_create ; -> eax 1 if it exists now [ts]
extern thread_create ; (rcx fn, rdx arg) -> rax handle
extern cpu_count
extern log_write ; (rcx zstr) [ts]
extern log_printf ; (rcx fmt, ...) [ts]
extern fatal_error ; (rcx zstr) doesn't return
extern screenshot_save ; (rcx path or 0 for screenshots\shot_N.bmp) -> eax
%endif

; util.asm, all [ts]
%ifndef IMPL_UTIL
extern str_format ; (rcx dst, rdx fmt, r8, r9, stack...) -> eax len
                  ; one qword slot per arg. %d %i %u %x %X %l(int64) %s %c %%,
                  ; %f / %.Nf take the float bits in the low dword. width: %5d %05d %-8s
extern str_len
extern str_copy ; -> rax at the NUL it wrote
extern str_ncopy ; (rcx dst, rdx src, r8 max incl NUL)
extern str_cat
extern str_cmp
extern str_eq_nocase
extern str_starts_with ; (rcx s, rdx prefix)
extern str_to_int ; (rcx s, rdx end** or 0) -> rax
extern str_to_float
extern str_hash ; fnv-1a 64, used for text seeds
extern mem_copy ; (rcx dst, rdx src, r8 n)
extern mem_set ; (rcx dst, edx byte, r8 n)
extern mem_zero ; (rcx dst, rdx n)
%endif

; gl.asm
%ifndef IMPL_GL
extern gl_load_functions
extern gl_compile_program ; (rcx vs, rdx fs, r8 attrib names, 0 terminated, index = location) -> eax prog or 0
extern gl_check_error ; (rcx tag)
%endif

; game.asm
%ifndef IMPL_GAME
extern game_init
extern game_frame ; (xmm0 dt)
extern game_tick ; 20 Hz, only with a world loaded and not paused
extern game_render
extern game_shutdown
extern game_on_key ; (ecx vk, edx down)
extern game_on_char
extern game_on_mouse_button ; (ecx MB_*, edx down)
extern game_on_wheel
extern game_on_resize ; (ecx w, edx h)
extern game_set_state ; (ecx ST_*), mouse is captured only in ST_PLAYING
extern game_start_world ; (rcx name, rdx seed, r8d gamemode, r9d is_new) -> eax
extern game_exit_world ; saves first
%endif

; math.asm. [ts] except rng_*, that's one global generator
%ifndef IMPL_MATH
extern math_sin
extern math_cos
extern math_sincos ; -> xmm0 sin, xmm1 cos
extern math_tan
extern math_atan2 ; (xmm0 y, xmm1 x)
extern math_sqrt
extern math_floor ; -> eax, real floor for negatives too
extern math_floorf
extern math_fract
extern math_pow ; x > 0 only
extern math_exp
extern math_clamp ; (x, lo, hi)
extern math_lerp ; (a, b, t)
extern math_smoothstep ; (e0, e1, x)
extern math_deg2rad
extern vec3_length
extern vec3_normalize ; in place
extern mat4_identity
extern mat4_mul ; (rcx dst, rdx a, r8 b), column major, dst may alias
extern mat4_perspective ; (rcx dst, xmm1 fovy deg, xmm2 aspect, xmm3 near, ARG5 far)
extern mat4_ortho ; (rcx dst, xmm1 l, xmm2 r, xmm3 b, ARG5 t, ARG6 n, ARG7 f)
extern mat4_rotate ; (rcx m, xmm1 deg, r8d axis)  m = m*R
extern mat4_translate ; (rcx m, xmm1-3 xyz)  m = m*T
extern mat4_transform ; (rcx m, rdx in vec4, r8 out vec4)
extern frustum_extract ; (rcx planes, rdx m)
extern frustum_test_aabb ; (rcx planes, rdx float[6] min/max) -> eax
extern frustum_test_sphere ; (rcx planes, xmm1-3 xyz, ARG5 r)
extern rng_seed
extern rng_next ; xorshift64*
extern rng_int ; [0,n)
extern rng_float ; [0,1)
extern rng_float_signed ; [-1,1)
extern hash2 ; (ecx x, edx z, r8d seed) -> eax [ts]
extern hash3 ; (ecx x, edx y, r8d z, r9d seed) [ts]
extern hash_float2 ; -> xmm0 [0,1) [ts]
%endif

; noise.asm. set the seed on the main thread first, after that it's all
; read-only. output roughly -1..1
%ifndef IMPL_NOISE
extern noise_set_seed
extern noise2 ; simplex
extern noise3
extern fbm2 ; (xmm0, xmm1, r8d octaves)
extern fbm3 ; (xmm0-2, r9d octaves)
extern ridged2 ; 0..1, ridges near 1
extern warp2
%endif

%ifndef IMPL_TEXGEN
extern texgen_init ; atlas + mips + cloud tex
extern texgen_animate ; (ecx tick) water/lava tiles
extern tile_color ; (ecx tile) -> eax avg colour
%endif
%ifndef IMPL_FONT
extern font_init
%endif

; audio.asm / music.asm, no sample files, it's all synthesized
%ifndef IMPL_AUDIO
extern audio_init ; 44.1k 16-bit stereo waveOut + mixer thread
extern audio_shutdown
extern sfx_play ; (ecx SFX_*, xmm1 vol, xmm2 pitch) [ts]
extern sfx_play_at ; (ecx SFX_*, xmm1-3 xyz) falls off over 16 blocks
extern sfx_play_block ; (ecx block, edx 0 break/1 place/2 step/3 hit, r8d bx, r9d by, ARG5 bz)
%endif
%ifndef IMPL_MUSIC
extern music_init
extern music_tick ; every tick in game AND every frame in menus
extern music_set_mood ; 0 day 1 night 2 menu 3 cave
%endif

; blocks.asm / items.asm. the tables are indexed by id, just read them
%define BF_SOLID        0x0001
%define BF_OPAQUE       0x0002  ; full cube: culls neighbours, blocks light, casts AO
%define BF_CUTOUT       0x0004  ; alpha tested
%define BF_TRANSLUCENT  0x0008  ; blended pass
%define BF_LIQUID       0x0010
%define BF_REPLACEABLE  0x0020
%define BF_GRAVITY      0x0040
%define BF_SUPPORT      0x0080  ; pops off without a block below
%define BF_INTERACT     0x0100
%define BF_FLAMMABLE    0x0200
%define BF_SELECTABLE   0x0400
%define BF_LEAVES       0x0800
%define BF_CULL_SAME    0x1000
%define BF_PLANT        0x2000  ; grass/dirt only

%define MODEL_CUBE      0
%define MODEL_CROSS     1
%define MODEL_TORCH     2
%define MODEL_LIQUID    3
%define MODEL_CACTUS    4       ; sides inset 1/16
%define MODEL_LANTERN   5

%define TINT_NONE       0
%define TINT_GRASS      1
%define TINT_FOLIAGE    2
%define TINT_PINE       3       ; fixed colour, not per biome
%define TINT_BIRCH      4       ; same
%define TINT_WATER      5

%ifndef IMPL_BLOCKS
extern blocks_init
extern blk_flags ; word[256]
extern blk_tex ; byte[256*6], FACE_* order
extern blk_model
extern blk_tint
extern blk_light
extern blk_opacity ; leaves 1, water 2, solid 15
extern blk_hardness ; float secs by hand, <0 unbreakable
extern blk_tool
extern blk_tier ; min pick tier for a drop, 0xFF = anything
extern blk_drop
extern blk_drop_count
extern blk_sound
extern blk_name ; qword[256]
extern blk_resistance ; float
%endif
%ifndef IMPL_ITEMS
extern item_name ; ids < 128 point at the block names
extern item_icon ; 0xFF = draw the 3d block
extern item_max_stack
extern item_tool_kind
extern item_tool_tier ; 0xFF = not a tool
extern item_tool_speed ; float
extern item_attack
extern item_durability ; word, 0 = unbreakable
extern item_food
extern item_fuel ; word, burn ticks
extern item_smelt
extern item_place
extern items_init
extern craft_match ; (rcx byte[9] row major) -> eax result, edx count
extern item_creative_list ; 0 terminated
extern item_find_by_name ; -> eax or -1, ignores case and _ vs space
%endif

; world.asm / chunkmgr.asm / worldgen.asm
%ifndef IMPL_WORLD
extern world_init
extern world_clear
extern world_get_chunk ; (ecx cx, edx cz) -> rax or 0
extern world_get_block ; (ecx x, edx y, r8d z). below 0 is bedrock, above/unloaded is air
extern world_set_block ; (.., r9d id) the full version: heightmap, dirty, relight, ticks, blockents
extern world_set_block_raw ; just writes + marks dirty
extern world_get_light ; -> (sky<<4)|block, 0xF0 when out of range
extern world_set_light ; raw
extern world_mark_dirty ; also marks the neighbour section on a boundary
extern world_get_biome
extern world_height_at ; highest non-air y, -1 if none
extern world_is_loaded ; >= CS_GENERATED
extern biome_grass_color ; 0xAABBGGRR
extern biome_foliage_color
extern biome_water_color
extern biome_name
extern biome_temperature ; < 0.15 snows
%endif
%ifndef IMPL_CHUNKMGR
extern chunkmgr_init ; cpu_count-1 workers, clamped 1..8
extern chunkmgr_shutdown
extern chunkmgr_update
extern chunkmgr_progress ; -> xmm0, loading bar
extern chunkmgr_spawn_ready ; 5x5 around player CS_READY
extern chunkmgr_save_all
%endif
%ifndef IMPL_WORLDGEN
extern worldgen_generate ; (rcx CHUNK*) [ts]
extern worldgen_biome_at ; [ts]
extern worldgen_height_at ; pure function of the seed [ts]
extern worldgen_find_spawn ; (rcx int[3])
extern worldgen_place_tree ; (ecx x, edx y, r8d z, r9d biome)
%endif

%ifndef IMPL_LIGHT
extern light_init_chunk_sky ; (rcx CHUNK*) [ts]
extern light_propagate_chunk ; needs all 8 neighbours generated, can dirty them
extern light_on_block_changed ; (ecx x, edx y, r8d z, r9d old id)
%endif

%ifndef IMPL_MESHER
extern mesher_build_section ; (rcx CHUNK*, edx section)
%endif
%ifndef IMPL_RENDER
extern render_init
extern render_free_chunk
extern render_update_meshes ; budgeted, nearest first
extern render_set_camera
extern render_world
extern render_block_cube ; (ecx block, xmm1 brightness) unit cube at the current matrix
extern render_item_sprite ; (ecx item, xmm1 brightness)
extern render_chunk_shader
%endif

%ifndef IMPL_SKY
extern sky_init
extern sky_update
extern sky_render
extern sky_render_clouds ; after the opaque world
%endif
%ifndef IMPL_PARTICLES
extern particles_init
extern particles_clear
extern particles_spawn ; (ecx PT_*, xmm1-3 pos, ARG5-7 vel floats, ARG8 tile/block)
extern particles_spawn_block_break ; (ecx x, edx y, r8d z, r9d block)
extern particles_spawn_block_hit ; (.., r9d face)
extern particles_spawn_explosion ; (xmm0-2 pos, xmm3 power)
extern particles_update ; (xmm0 dt)
extern particles_render
extern particles_ambient_tick
extern g_particle_count
%endif
%ifndef IMPL_WEATHER
extern weather_tick
extern weather_render
extern weather_set ; 0 clear 1 rain 2 thunder
extern g_weather
extern g_weather_timer
%endif

%ifndef IMPL_PLAYER
extern player_reset
extern player_spawn
extern player_update ; (xmm0 dt)
extern player_tick
extern player_damage ; (ecx half hearts, edx DMG_*) -> eax 1 if it landed
extern player_respawn
extern player_get_eye ; (rcx float[3])
extern player_get_look
extern player_drop_held ; (ecx whole stack)
%endif
%ifndef IMPL_RAYCAST
extern raycast_blocks ; (rcx origin, rdx dir, xmm2 max, r9 RAYHIT*) -> eax. hit=2 going in = liquids count
%endif
%ifndef IMPL_PHYSICS
extern physics_move ; (rcx PHYS*)
extern physics_in_liquid ; -> 0/1 water/2 lava
extern physics_box_free ; (xmm0-3 minx miny minz maxx, ARG5 maxy, ARG6 maxz)
%endif

; ui colours are 0xAARRGGBB, careful, biome/particle colours are ABGR.
; coords are virtual ui pixels from the top left
%ifndef IMPL_UI
extern ui_init
extern ui_begin
extern ui_end
extern ui_rect ; (x, y, w, h, ARG5 colour)
extern ui_rect_grad ; (.., ARG5 top, ARG6 bottom)
extern ui_frame ; (x, y, w, h)
extern ui_text ; (x, y, r8 str, r9d colour) -> eax width. \f + hex digit switches colour
extern ui_text_shadow
extern ui_text_scaled ; (.., ARG5 scale)
extern ui_text_width
extern ui_text_centered ; ecx = centre x
extern ui_tile ; (x, y, size, tile, ARG5 tint)
extern ui_item_icon ; (x, y, r8d item)
extern ui_item_stack ; (x, y, r8 STACK*)
extern ui_button ; (x, y, w, h, ARG5 label, ARG6 enabled) -> eax clicked
extern ui_slider ; (x, y, w, r9 float*, ARG5 min bits, ARG6 max, ARG7 label fmt) -> eax changed
extern ui_textbox ; (x, y, w, r9 buf, ARG5 maxlen, ARG6 id) -> eax 1 on enter
extern ui_mouse_in ; (x, y, w, h)
extern ui_tooltip
%endif
%ifndef IMPL_HUD
extern hud_render
%endif
%ifndef IMPL_MENUS
extern menus_render
extern menus_on_key
extern menus_enter ; (ecx ST_*)
%endif
%ifndef IMPL_CONSOLE
extern console_open ; (ecx first char or 0)
extern console_render
extern console_on_key
extern chat_add ; (rcx str, edx colour)
extern console_execute ; -> eax 1 if it knew the command
extern chat_render_feed
%endif

%ifndef IMPL_INVENTORY
extern inv_add ; (rcx slots, edx n, r8d item, r9d count) -> eax leftover
extern inv_give_player ; (ecx item, edx count) -> eax leftover
extern inv_count ; (rcx slots, edx n, r8d item)
extern inv_held ; -> rax STACK*
extern inv_consume_held ; no-op in creative
extern inv_damage_held
extern inv_clear_player
extern inv_drop_all
%endif
%ifndef IMPL_SCREENS
extern screens_open ; (ecx SCR_*, edx-r9d block pos)
extern screens_close ; hands back grid + cursor items
extern screens_render
extern screens_on_mouse
extern screens_on_key
extern screens_on_wheel
%endif
%ifndef IMPL_BLOCKENT
extern blockent_get ; (ecx x, edx y, r8d z, r9d kind to create or 0) -> rax or 0
extern blockent_remove ; drops the contents
extern blockent_tick
extern blockent_clear
extern g_blockents ; save.asm writes this raw
%endif

; saves\<name>\level.dat + saves\<name>\chunks\c.<cx>.<cz>.bin
%ifndef IMPL_SAVE
extern save_world
extern save_load_level ; -> eax 1 if level.dat was there
extern save_chunk ; only if .modified
extern save_load_chunk ; (rcx CHUNK*) -> eax 1 found. [ts], workers call it
extern save_list_worlds ; (rcx char[32][max], edx max) -> eax
extern save_delete_world
extern save_world_exists
extern save_set_display_name ; (rcx folder, rdx typed name) goes in that world's level.dat
extern save_autosave_tick ; every 6000 ticks
%endif
%ifndef IMPL_CONFIG
extern config_defaults
extern config_load
extern config_save
%endif

%ifndef IMPL_ENTITY
extern entity_init
extern entity_clear
extern entity_spawn ; (ecx ENT_*, xmm1-3 pos) -> rax or 0
extern entity_spawn_item ; (ecx item, edx count, xmm2 x, xmm3 y, ARG5 z) -> rax
extern entity_drop_block_item ; (ecx x, edx y, r8d z, r9d item)
extern entity_tick_all
extern entity_render_all
extern entity_raycast ; (rcx origin, rdx dir, xmm2 max) -> rax or 0, xmm0 dist
extern entity_damage ; (rcx ENTITY*, edx amount, r8d DMG_*)
extern entity_count_type
extern entity_render_player ; third person
extern g_entities
extern g_entity_count
%endif
%ifndef IMPL_MOBS
extern mobs_ai_tick ; (rcx ENTITY*)
extern mobs_spawn_tick
extern mobs_render ; (rcx ENTITY*)
%endif
%ifndef IMPL_EXPLOSION
extern explosion_create ; (xmm0-2 pos, xmm3 power)
%endif

%ifndef IMPL_TICKS
extern ticks_init
extern ticks_clear
extern ticks_schedule ; (ecx x, edx y, r8d z, r9d delay), dupes are dropped
extern ticks_notify_neighbors
extern ticks_tick
%endif
%ifndef IMPL_FLUIDS
extern fluid_update ; (ecx x, edx y, r8d z)
%endif

; java edition bridge, the parts the rest of the game calls. full contract in net.inc
%ifndef IMPL_NET
extern net_init
extern net_host ; (ecx port) -> eax 1 listening
extern net_stop
extern net_update ; per frame while hosting
extern net_conn_name ; (ecx conn index) -> rax zstr or 0
extern g_net_hosting
extern g_net_port
extern g_net_host_name
%endif
%ifndef IMPL_MCPLAY
extern mcplay_tick ; 20 hz
extern mcplay_block_changed ; (ecx x, edx y, r8d z, r9d block)
extern mcplay_chat ; (rcx zstr)
extern mcplay_count ; -> eax java players in play
%endif
 ; wire simulation_water
%endif ; extern check simulation_water
