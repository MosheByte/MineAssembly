; simworld.inc - fake world harness for the simulation tests. include after testlib.inc.
; macro args get loaded into ecx/edx/r8d/r9d in order, so only pass immediates or
; nonvolatile regs (ebx esi edi r12d-r15d), never eax/ecx/edx/r8-r11
%ifndef SIMWORLD_INC
%define SIMWORLD_INC

%ifndef IMPL_SIMWORLD
extern sw_new               ; (cmin, cmax, default light, entities on)
extern sw_flat              ; (top, entities, light) chunks -2..1, stone 0..9, top at y=10
extern sw_chunk             ; creates on demand inside [cmin,cmax], else 0
extern sw_chunk_peek
extern sw_get               ; y<0 bedrock, unloaded/y>=128 air
extern sw_put               ; raw write, no notify
extern sw_set               ; the real world_set_block path
extern sw_fill              ; x0 y0 z0 x1 y1 z1 b, raw
extern sw_set_sec_flags
extern sw_register_chunks   ; (rcx cx,cz dword pairs, edx count) -> g_chunk_list
extern sw_set_player
extern sw_set_light         ; per-position world_get_light override
extern sw_tick
extern sw_settle            ; -> ticks until nothing pending, -1 = never
extern sw_leaf_check        ; schedules a check 1 tick out and runs that tick
extern sw_count_box         ; NB arg order x0 x1 y0 y1 z0 z1 lo hi
extern sw_count_drops       ; -1 = any item
extern sw_find_drop
extern sw_count_sounds
; recorded stuff, dwords unless noted
extern sw_sets
extern sw_errors            ; out-of-world writes + record overflows
extern sw_drops_n, sw_drops         ; {x,y,z,item}
extern sw_spawns_n, sw_spawns       ; {type, fx, fy, fz, qword ENTITY*} 32 B
extern sw_trees_n, sw_trees         ; {x,y,z,biome}
extern sw_sounds_n
extern sw_particles_n, sw_smoke_n
extern sw_breaks_n, sw_breaks       ; {x,y,z,block}
extern sw_tree_fn           ; qword, optional hook for worldgen_place_tree
extern sw_biome             ; what world_get_biome returns (3)
%endif

extern ticks_pending, ticks_dropped, ticks_rng, ticks_pl_count, ticks_pl_dropped
extern ticks_random_block, ticks_rand, ticks_randf, ticks_peek_block
extern ticks_drop_block, fluid_source_unsettled
extern fw_misaligned, abi_call, abi_selftest_bad

%macro W_NEW 2-4.nolist 0xF0, 1            ; cmin, cmax [, light, entities]
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    call sw_new
%endmacro

%macro FLAT 1-3.nolist 1, 0xF0             ; top [, entities, light]
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call sw_flat
%endmacro

%macro PUT 4.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    call sw_put
%endmacro

%macro WSET 4.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    call sw_set
%endmacro

%macro GET 3.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call sw_get
%endmacro

%macro FILL 7.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    mov  dword [rsp+32], %5
    mov  dword [rsp+40], %6
    mov  dword [rsp+48], %7
    call sw_fill
%endmacro

%macro LIGHT 4.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    call sw_set_light
%endmacro

%macro TICK 1.nolist
    mov  ecx, %1
    call sw_tick
%endmacro

%macro SETTLE 0-1.nolist 5000
    mov  ecx, %1
    call sw_settle
    inc  eax                        ; -1 never settled -> 0 -> fail
    CHECK_TRUE eax, "simulation settles"
%endmacro

%macro RTICK 3.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call ticks_random_block
%endmacro

%macro NOTIFY 3.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call ticks_notify_neighbors
%endmacro

%macro SCHED 4.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    call ticks_schedule
%endmacro

%macro LEAFCHK 3.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call sw_leaf_check
%endmacro

%macro UNSETTLED 3.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call fluid_source_unsettled
%endmacro

%macro COUNT_BOX 8.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    mov  dword [rsp+32], %5
    mov  dword [rsp+40], %6
    mov  dword [rsp+48], %7
    mov  dword [rsp+56], %8
    call sw_count_box
%endmacro

%macro CHECK_BLK 5.nolist
    GET  %1, %2, %3
    CHECK_EQ32 eax, %4, %5
%endmacro

%macro CHECK_NOT 5.nolist
    GET  %1, %2, %3
    cmp  eax, %4
    setne al
    movzx eax, al
    CHECK_TRUE eax, %5
%endmacro

; signed, inclusive
%macro CHECK_RANGE 4.nolist
    mov  eax, %1
    cmp  eax, %2
    setge cl
    cmp  eax, %3
    setle dl
    and  cl, dl
    movzx eax, cl
    CHECK_TRUE eax, %4
%endmacro

%macro DAYLIGHT 1.nolist                   ; float literals
    mov  eax, __?float32?__(%1)
    mov  [rel g_daylight], eax
%endmacro

%macro PLAYER_AT 3.nolist                  ; float literals
    mov  eax, __?float32?__(%1)
    movd xmm0, eax
    mov  eax, __?float32?__(%2)
    movd xmm1, eax
    mov  eax, __?float32?__(%3)
    movd xmm2, eax
    call sw_set_player
%endmacro

%endif
