; net.inc - MC Java 26.1 (proto 775) server bridge state & packet I/O
%ifndef NET_INC
%define NET_INC

%define MC_VERSION_NAME   "26.1"
%define NET_DEFAULT_PORT  25565
%define MAX_NET_CONNS     16
%define NET_RECV_CAP      (2*1024*1024)   ; per connection
%define NET_SEND_CAP      (8*1024*1024)   ; per connection, chunks are big

; connection states
%define CN_FREE      0
%define CN_HANDSHAKE 1
%define CN_STATUS    2
%define CN_LOGIN     3
%define CN_CONFIG    4
%define CN_PLAY      5
%define CN_CLOSING   6

struc MCCONN
    .state      resd 1      ; CN_*
    .index      resd 1      ; slot in g_net_conns
    .sock       resq 1      ; SOCKET
    .rbuf       resq 1      ; recv buffer (NET_RECV_CAP)
    .rlen       resd 1
    .protocol   resd 1      ; client's protocol number from the handshake
    .sbuf       resq 1      ; send buffer (NET_SEND_CAP)
    .slen       resd 1      ; bytes queued
    .soff       resd 1      ; bytes already sent from the front
    .name       resb 20     ; username, zero terminated (max 16 chars)
    .uuid       resb 16
    .eid        resd 1      ; entity id the java client knows itself by
    .ent        resq 1      ; ENTITY* of this player inside our world (0 until spawned)
    .x          resq 1      ; double, feet
    .y          resq 1
    .z          resq 1
    .yaw        resd 1      ; float degrees, java convention (0 = +z south)
    .pitch      resd 1
    .on_ground  resd 1
    .held_slot  resd 1      ; 0..8
    .hotbar     resd 9      ; java item registry ids in the hotbar (creative)
    .ka_id      resq 1      ; last keepalive id sent
    .ka_time    resq 1      ; ms when it was sent, 0 = answered
    .tp_id      resd 1      ; pending teleport id, 0 = none
    .ccx        resd 1      ; chunk the client is centred on
    .ccz        resd 1
    .view       resd 1      ; view distance in chunks
    .sent       resq 1      ; ptr to a 64x64 bitset of sent chunks around ccx/ccz (mod 64)
    .flags      resd 1
    .last_rx    resq 1      ; ms of last packet
    .pad        resb 64
endstruc
%define CF_JOINED     1     ; play login done
%define CF_SPAWNED    2     ; first chunk batch + position sent
%define CF_PACKS      4     ; config: select_known_packs sent, waiting for the answer
%define CF_CFG_DONE   8     ; config: registries + finish_configuration sent

; packet writer / reader cursors
struc PKTW
    .buf  resq 1
    .len  resd 1
    .cap  resd 1
endstruc
struc PKTR
    .p    resq 1            ; current
    .end  resq 1
    .err  resd 1            ; set on overrun, readers then return 0
    .pad  resd 1
endstruc

; net.asm
%ifndef IMPL_NET
extern net_init             ; () wsastartup, alloc buffers. idempotent
extern net_host             ; (ecx port) -> eax 1 listening
extern net_stop             ; () kick everyone, close listener
extern net_update           ; () per frame: accept, recv, split frames -> mc_handle_packet, flush sends
extern net_send_frame       ; (rcx MCCONN*, rdx payload, r8d len) prepend varint length, queue
extern net_close            ; (rcx MCCONN*, rdx reason zstr or 0) disconnect packet if in login/config/play, then close
extern net_conn_name        ; (ecx conn index) -> rax zstr or 0
extern g_net_conns          ; MCCONN[MAX_NET_CONNS]
extern g_net_hosting        ; dword 1 when the listener is up
extern g_net_port           ; dword
extern g_net_host_name      ; byte[20] name the host player shows up as for java clients
%endif

; mcproto.asm
%ifndef IMPL_MCPROTO
extern g_pw                 ; PKTW, the one scratch writer (main thread only)
extern pw_begin             ; (ecx packet id) reset g_pw, write id
extern pw_send              ; (rcx MCCONN*) net_send_frame(g_pw)
extern pw_varint            ; (ecx)
extern pw_varlong           ; (rcx)
extern pw_u8                ; (ecx)
extern pw_u16               ; (ecx) big endian
extern pw_i32               ; (ecx) big endian
extern pw_i64               ; (rcx) big endian
extern pw_f32               ; (xmm0)
extern pw_f64               ; (xmm0 double)
extern pw_bool              ; (ecx)
extern pw_string            ; (rcx zstr)
extern pw_bytes             ; (rcx ptr, rdx len)
extern pw_uuid              ; (rcx ptr16)
extern pw_position          ; (ecx x, edx y, r8d z) packed 26/12/26
extern pw_text              ; (rcx zstr) text component, network nbt (string tag)
extern pw_text_color        ; (rcx zstr, rdx color name zstr e.g. "yellow") compound {text,color}
extern nbt_begin_compound   ; (rcx name zstr or 0 for the nameless network root)
extern nbt_end              ; ()
extern nbt_long_array       ; (rcx name, rdx qword* values, r8d count)
extern nbt_string           ; (rcx name, rdx value)
extern nbt_int              ; (rcx name, edx value)
extern nbt_byte             ; (rcx name, edx value)
extern pr_init              ; (rcx PKTR*, rdx data, r8d len)
extern pr_varint            ; (rcx PKTR*) -> eax
extern pr_varlong           ; (rcx PKTR*) -> rax
extern pr_u8                ; (rcx PKTR*) -> eax
extern pr_u16               ; (rcx PKTR*) -> eax
extern pr_i32               ; (rcx PKTR*) -> eax
extern pr_i64               ; (rcx PKTR*) -> rax
extern pr_f32               ; (rcx PKTR*) -> xmm0
extern pr_f64               ; (rcx PKTR*) -> xmm0 double
extern pr_bool              ; (rcx PKTR*) -> eax
extern pr_string            ; (rcx PKTR*, rdx out, r8d out size) -> eax length (truncates, always NUL ends)
extern pr_uuid              ; (rcx PKTR*, rdx out16)
extern pr_position          ; (rcx PKTR*, rdx out int[3])
extern pr_skip              ; (rcx PKTR*, edx n)
extern mc_handle_packet     ; (rcx MCCONN*, rdx data, r8d len) one uncompressed frame body; dispatches by state
extern mc_offline_uuid      ; (rcx name zstr, rdx out16) md5("OfflinePlayer:"+name), version 3 like vanilla
%endif

; mcplay.asm
%ifndef IMPL_MCPLAY
extern mcplay_join          ; (rcx MCCONN*) called once config finishes: login(play), spawn, chunks, tab list
extern mcplay_handle        ; (rcx MCCONN*, edx packet id, r8 PKTR*) serverbound play packets
extern mcplay_tick          ; () 20 hz: keepalive, chunk streaming, time, movement broadcast, timeouts
extern mcplay_left          ; (rcx MCCONN*) cleanup when a play connection goes away
extern mcplay_block_changed ; (ecx x, edx y, r8d z, r9d our block id) broadcast to everyone in play
extern mcplay_chat          ; (rcx zstr) system chat to every java client
extern mcplay_count         ; () -> eax players in play
%endif

; mcmap.asm
%ifndef IMPL_MCMAP
extern mcmap_block_state    ; (ecx our block id) -> eax java block state id
extern mcmap_from_state     ; (ecx java block state id) -> eax our block id (best match, never 0 for solid stuff)
extern mcmap_item_to_block  ; (ecx java item id) -> eax our block id it places (0 = not a block)
extern mcmap_block_to_item  ; (ecx our block id) -> eax java item id (for hotbars/entity items)
extern mcmap_biome          ; (ecx our biome id) -> eax java biome registry index (as sent in config)
extern mcmap_send_known_packs ; (rcx MCCONN*) config phase: select_known_packs [minecraft:core 26.1]
extern mcmap_send_registries ; (rcx MCCONN*, edx 1 = client has minecraft:core) every registry_data (no data if it has it) + the vanilla update_tags
%endif

%endif
