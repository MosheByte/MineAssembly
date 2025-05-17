; structs.inc - engine memory layouts
%ifndef STRUCTS_INC
%define STRUCTS_INC

; 4 bytes, id 0 = empty
struc STACK
    .id         resb 1
    .count      resb 1
    .damage     resw 1          ; durability used
endstruc

; 1KB header + 32KB blocks + 32KB light ((sky<<4)|blk)
struc CHUNK
    .cx         resd 1
    .cz         resd 1
    .state      resd 1          ; dword so workers can xchg it
    .dirty      resd 1          ; bit per section
    .modified   resd 1
    .slot       resd 1
    .hnext      resq 1          ; hash chain
    .vbo        resd 16
    .vcount     resd 16
    .sec_flags  resb 8          ; bit0 opaque geo, bit1 translucent
    .gen_ms     resd 1
    .last_seen  resd 1
    .list_idx   resd 1
    .user       resd 1
    .pad0       resb 72
    .heightmap  resb 256        ; at 256
    .biome      resb 256        ; 512
    .reserved   resb 256        ; 768
endstruc
%define CHUNK_HDR       1024
%define CHUNK_BLOCKS    1024
%define CHUNK_LIGHT     (1024+32768)
%define CHUNK_BYTES     (1024+32768+32768) ; 66560

; 16B chunk vertex: pos i16[3] (1/256 blk, y-64), uv u8[2] (1/8 px), rgba/light/flags
struc VERTEX
    .x          resw 1
    .y          resw 1
    .z          resw 1
    .u          resb 1
    .v          resb 1
    .r          resb 1          ; tint
    .g          resb 1
    .b          resb 1
    .tile       resb 1          ; atlas tile, the shader gets it as a_color.a
    .sky        resb 1          ; light*17
    .blk        resb 1
    .shade      resb 1          ; face shade * AO
    .flags      resb 1          ; VF_* from mesher.asm
endstruc
%define VERTEX_STRIDE 16

struc PHYS
    .x          resd 1          ; bottom centre
    .y          resd 1
    .z          resd 1
    .dx         resd 1          ; wanted move this step
    .dy         resd 1
    .dz         resd 1
    .hw         resd 1
    .h          resd 1
    .step       resd 1          ; step-up height, 0 off
    .flags      resd 1          ; PF_*, out
endstruc
%define PF_GROUND   1           ; landed on something
%define PF_HIT_X    2
%define PF_HIT_Y    4
%define PF_HIT_Z    8
%define PF_CEILING  16
%define PF_SNEAK    32          ; in: don't walk off edges

struc RAYHIT
    .hit        resd 1
    .x          resd 1
    .y          resd 1
    .z          resd 1
    .face       resd 1
    .ax         resd 1          ; where a placed block goes
    .ay         resd 1
    .az         resd 1
    .dist       resd 1          ; float
    .block      resd 1
    .px         resd 1          ; float
    .py         resd 1
    .pz         resd 1
endstruc

; degrees. yaw 0 looks down -z, 90 down +x, pitch + is up
; look = (sin(yaw)cos(pitch), sin(pitch), -cos(yaw)cos(pitch))
struc PLAYER
    .x          resd 1          ; feet
    .y          resd 1
    .z          resd 1
    .vx         resd 1          ; blocks/s
    .vy         resd 1
    .vz         resd 1
    .yaw        resd 1
    .pitch      resd 1
    .on_ground  resd 1
    .in_water   resd 1
    .eye_in_water resd 1
    .in_lava    resd 1
    .flying     resd 1
    .sneaking   resd 1
    .sprinting  resd 1
    .health     resd 1          ; half hearts
    .hunger     resd 1
    .saturation resd 1
    .exhaustion resd 1
    .air        resd 1          ; ticks, 300 max
    .fall_start resd 1
    .hurt_time  resd 1
    .invuln     resd 1
    .selected   resd 1
    .dead       resd 1
    .spawn_x    resd 1
    .spawn_y    resd 1
    .spawn_z    resd 1
    .bob        resd 1
    .bob_amount resd 1
    .swing      resd 1
    .break_progress resd 1
    .break_x    resd 1
    .break_y    resd 1
    .break_z    resd 1
    .use_cooldown resd 1
    .eat_time   resd 1
    .step_dist  resd 1
    .regen_timer resd 1
    .starve_timer resd 1
    .jump_timer resd 1          ; double tap space = fly
    .sprint_timer resd 1        ; double tap w
    .eye_height resd 1          ; lerps down when sneaking
    .score      resd 1
    .last_damage_src resd 1
    .pad        resb 76
    .inv        resb 4*36       ; 256
    .cursor     resb 4
    .craft      resb 4*9        ; 2x2 uses 0,1,3,4
    .craft_out  resb 4
    .pad2       resb 68
endstruc                        ; 512

struc ENTITY
    .type       resb 1
    .flags      resb 1
    .ai_state   resb 1
    .variant    resb 1          ; wool colour / falling block id
    .health     resd 1
    .age        resd 1
    .timer      resd 1          ; fuse, pickup delay, whatever the type wants
    .x          resd 1
    .y          resd 1
    .z          resd 1
    .vx         resd 1          ; per TICK, not per second
    .vy         resd 1
    .vz         resd 1
    .yaw        resd 1
    .pitch      resd 1
    .head_yaw   resd 1
    .hw         resd 1
    .h          resd 1
    .item       resb 4          ; ENT_ITEM only
    .hurt_time  resd 1
    .anim       resd 1
    .anim_speed resd 1
    .target_x   resd 1
    .target_z   resd 1
    .fire       resd 1
    .attack_cd  resd 1
    .prev_x     resd 1          ; for lerp
    .prev_y     resd 1
    .prev_z     resd 1
    .death_time resd 1
    .pad        resb 20
endstruc                        ; 128
%define EF_ON_GROUND    1
%define EF_IN_WATER     2
%define EF_HOSTILE      4
%define EF_DEAD         8
%define EF_PERSIST      16      ; never despawns
%define EF_IN_LAVA      32

struc PARTICLE
    .x          resd 1
    .y          resd 1
    .z          resd 1
    .vx         resd 1          ; per second, unlike entities
    .vy         resd 1
    .vz         resd 1
    .life       resd 1
    .max_life   resd 1
    .size       resd 1
    .gravity    resd 1
    .type       resb 1
    .tile       resb 1
    .uoff       resb 1          ; debris sub-tile 0..12
    .voff       resb 1
    .color      resd 1          ; ABGR
endstruc

struc BLOCKENT
    .kind       resd 1
    .x          resd 1
    .y          resd 1
    .z          resd 1
    .burn       resd 1
    .burn_max   resd 1
    .cook       resd 1          ; 200 = done
    .pad        resd 1
    .slots      resb 4*27       ; furnace: 0 in 1 fuel 2 out
    .pad2       resb 20
endstruc                        ; 160
%define BE_FURNACE  1
%define BE_CHEST    2

; options.txt
struc SETTINGS
    .render_dist    resd 1
    .fov            resd 1
    .sensitivity    resd 1      ; deg per count
    .vsync          resd 1
    .smooth_light   resd 1
    .clouds         resd 1      ; 0 off 1 fast 2 fancy
    .view_bob       resd 1
    .gui_scale      resd 1      ; 0 = auto
    .music_vol      resd 1
    .sfx_vol        resd 1
    .fullscreen     resd 1
    .invert_mouse   resd 1
    .show_fps       resd 1
    .particles      resd 1      ; 0..2
    .fancy_leaves   resd 1
    .pad            resb 68
endstruc                        ; 128

%endif
