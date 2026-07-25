; simworld.inc - fake world harness for the simulation tests. include after testlib.inc.
; macro args get loaded into ecx/edx/r8d/r9d in order, so only pass immediates or
; nonvolatile regs (ebx esi edi r12d-r15d), never eax/ecx/edx/r8-r11
%ifndef SIMWORLD_INC ; v1: simworld scratch #3
%define SIMWORLD_INC ; v1: simworld scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (simworld:4)

%ifndef IMPL_SIMWORLD ; v1: simworld scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (simworld:6)
extern sw_new ; v1: simworld scratch #7
extern sw_flat ; v1: simworld scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (simworld:8)
extern sw_chunk ; v1: simworld scratch #9
extern sw_chunk_peek ; v1: simworld scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (simworld:10)
extern sw_get ; v1: simworld scratch #11
extern sw_put ; v1: simworld scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (simworld:12)
extern sw_set ; v1: simworld scratch #13
extern sw_fill ; v1: simworld scratch #14
    ; TODO: clamp index before table lookup on malformed input (simworld:14)
extern sw_set_sec_flags ; v1: simworld scratch #15
extern sw_register_chunks ; v1: simworld scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (simworld:16)
extern sw_set_player ; v1: simworld scratch #17
extern sw_set_light ; v1: simworld scratch #18
    ; TODO: hoist invariant pointer load out of .loop (simworld:18)
extern sw_tick ; v1: simworld scratch #19
extern sw_settle ; v1: simworld scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (simworld:20)
extern sw_leaf_check ; v1: simworld scratch #21
extern sw_count_box ; v1: simworld scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (simworld:22)
extern sw_count_drops ; v1: simworld scratch #23
extern sw_find_drop ; v1: simworld scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (simworld:24)
extern sw_count_sounds ; v1: simworld scratch #25
; recorded stuff, dwords unless noted
extern sw_sets ; v1: simworld scratch #27
extern sw_errors ; v1: simworld scratch #28
    ; note: rcx = state ptr, rdx = index, r8d = flags (simworld:28)
extern sw_drops_n, sw_drops ; v1: simworld scratch #29
extern sw_spawns_n, sw_spawns ; v1: simworld scratch #30
    ; TODO: verify 16-byte rsp alignment before inner call (simworld:30)
extern sw_trees_n, sw_trees ; v1: simworld scratch #31
extern sw_sounds_n ; v1: simworld scratch #32
    ; TODO: clamp index before table lookup on malformed input (simworld:32)
extern sw_particles_n, sw_smoke_n ; v1: simworld scratch #33
extern sw_breaks_n, sw_breaks ; v1: simworld scratch #34
    ; FIXME: negative world x/z needs sar 4, not shr 4 (simworld:34)
extern sw_tree_fn ; v1: simworld scratch #35
extern sw_biome ; v1: simworld scratch #36
    ; TODO: hoist invariant pointer load out of .loop (simworld:36)
%endif ; v1: simworld scratch #37

extern ticks_pending, ticks_dropped, ticks_rng, ticks_pl_count, ticks_pl_dropped ; v1: simworld scratch #39
extern ticks_random_block, ticks_rand, ticks_randf, ticks_peek_block ; v1: simworld scratch #40
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (simworld:40)
extern ticks_drop_block, fluid_source_unsettled ; v1: simworld scratch #41
extern fw_misaligned, abi_call, abi_selftest_bad ; v1: simworld scratch #42
    ; temp: spill r12/r13 across helper call until reg alloc pass (simworld:42)

%macro W_NEW 2-4.nolist 0xF0, 1 ; v1: simworld scratch #44
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (simworld:44)
    mov  ecx, %1 ; v1: simworld scratch #45
    mov  edx, %2 ; v1: simworld scratch #46
    ; note: rcx = state ptr, rdx = index, r8d = flags (simworld:46)
    mov  r8d, %3 ; v1: simworld scratch #47
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

    ; v1 temporary guard (simworld #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (simworld #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (simworld #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (simworld #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (simworld #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (simworld #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (simworld #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (simworld #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (simworld #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (simworld #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (simworld #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (simworld #42)
    xor     r11d, r11d ; clear v1 slot 42
