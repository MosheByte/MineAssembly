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
; --- inline mcpackets draft before module split ---
; mcpackets.inc - MC Java 26.1 (protocol 775) packet IDs and registry counts
%ifndef MCPACKETS_INC
%define MCPACKETS_INC

%define MC_PROTOCOL_VERSION   775
%define MC_STATE_COUNT        29873     ; block states
%define MC_STATE_BITS         15        ; direct palette bits, block states
%define MC_BLOCK_COUNT        1168
%define MC_ITEM_COUNT         1506
%define MC_BIOME_COUNT        65
%define MC_BIOME_BITS         7         ; direct palette bits, biomes
%define MC_REGISTRY_COUNT     28        ; registry_data packets mcmap_send_registries sends
%define MC_TAG_REGISTRY_COUNT 15        ; registries in update_tags
%define MC_TAG_COUNT          661       ; tags in update_tags, all registries
%define MC_WORLD_MIN_Y        -64       ; vanilla overworld dimension type
%define MC_WORLD_HEIGHT       384

; handshaking serverbound
%define MCP_HANDSHAKING_C2S_SET_PROTOCOL                     0x00
%define MCP_HANDSHAKING_C2S_LEGACY_SERVER_LIST_PING          0xFE

; status clientbound
%define MCP_STATUS_S2C_SERVER_INFO                      0x00
%define MCP_STATUS_S2C_PING                             0x01

; status serverbound
%define MCP_STATUS_C2S_PING_START                       0x00
%define MCP_STATUS_C2S_PING                             0x01

; login clientbound
%define MCP_LOGIN_S2C_DISCONNECT                       0x00
%define MCP_LOGIN_S2C_ENCRYPTION_BEGIN                 0x01
%define MCP_LOGIN_S2C_SUCCESS                          0x02
%define MCP_LOGIN_S2C_COMPRESS                         0x03
%define MCP_LOGIN_S2C_LOGIN_PLUGIN_REQUEST             0x04
%define MCP_LOGIN_S2C_COOKIE_REQUEST                   0x05

; login serverbound
%define MCP_LOGIN_C2S_LOGIN_START                      0x00
%define MCP_LOGIN_C2S_ENCRYPTION_BEGIN                 0x01
%define MCP_LOGIN_C2S_LOGIN_PLUGIN_RESPONSE            0x02
%define MCP_LOGIN_C2S_LOGIN_ACKNOWLEDGED               0x03
%define MCP_LOGIN_C2S_COOKIE_RESPONSE                  0x04

; configuration clientbound
%define MCP_CONFIGURATION_S2C_COOKIE_REQUEST                   0x00
%define MCP_CONFIGURATION_S2C_CUSTOM_PAYLOAD                   0x01
%define MCP_CONFIGURATION_S2C_DISCONNECT                       0x02
%define MCP_CONFIGURATION_S2C_FINISH_CONFIGURATION             0x03
%define MCP_CONFIGURATION_S2C_KEEP_ALIVE                       0x04
%define MCP_CONFIGURATION_S2C_PING                             0x05
%define MCP_CONFIGURATION_S2C_RESET_CHAT                       0x06
%define MCP_CONFIGURATION_S2C_REGISTRY_DATA                    0x07
%define MCP_CONFIGURATION_S2C_REMOVE_RESOURCE_PACK             0x08
%define MCP_CONFIGURATION_S2C_ADD_RESOURCE_PACK                0x09
%define MCP_CONFIGURATION_S2C_STORE_COOKIE                     0x0A
%define MCP_CONFIGURATION_S2C_TRANSFER                         0x0B
%define MCP_CONFIGURATION_S2C_FEATURE_FLAGS                    0x0C
%define MCP_CONFIGURATION_S2C_TAGS                             0x0D
%define MCP_CONFIGURATION_S2C_SELECT_KNOWN_PACKS               0x0E
%define MCP_CONFIGURATION_S2C_CUSTOM_REPORT_DETAILS            0x0F
%define MCP_CONFIGURATION_S2C_SERVER_LINKS                     0x10
%define MCP_CONFIGURATION_S2C_CLEAR_DIALOG                     0x11
%define MCP_CONFIGURATION_S2C_SHOW_DIALOG                      0x12
%define MCP_CONFIGURATION_S2C_CODE_OF_CONDUCT                  0x13

; configuration serverbound
%define MCP_CONFIGURATION_C2S_SETTINGS                         0x00
%define MCP_CONFIGURATION_C2S_COOKIE_RESPONSE                  0x01
%define MCP_CONFIGURATION_C2S_CUSTOM_PAYLOAD                   0x02
%define MCP_CONFIGURATION_C2S_FINISH_CONFIGURATION             0x03
%define MCP_CONFIGURATION_C2S_KEEP_ALIVE                       0x04
%define MCP_CONFIGURATION_C2S_PONG                             0x05
%define MCP_CONFIGURATION_C2S_RESOURCE_PACK_RECEIVE            0x06
%define MCP_CONFIGURATION_C2S_SELECT_KNOWN_PACKS               0x07
%define MCP_CONFIGURATION_C2S_CUSTOM_CLICK_ACTION              0x08
%define MCP_CONFIGURATION_C2S_ACCEPT_CODE_OF_CONDUCT           0x09

; play clientbound
%define MCP_PLAY_S2C_BUNDLE_DELIMITER                 0x00
%define MCP_PLAY_S2C_SPAWN_ENTITY                     0x01
%define MCP_PLAY_S2C_ANIMATION                        0x02
%define MCP_PLAY_S2C_STATISTICS                       0x03
%define MCP_PLAY_S2C_ACKNOWLEDGE_PLAYER_DIGGING       0x04
%define MCP_PLAY_S2C_BLOCK_BREAK_ANIMATION            0x05
%define MCP_PLAY_S2C_TILE_ENTITY_DATA                 0x06
%define MCP_PLAY_S2C_BLOCK_ACTION                     0x07
%define MCP_PLAY_S2C_BLOCK_CHANGE                     0x08
%define MCP_PLAY_S2C_BOSS_BAR                         0x09
%define MCP_PLAY_S2C_DIFFICULTY                       0x0A
%define MCP_PLAY_S2C_CHUNK_BATCH_FINISHED             0x0B
%define MCP_PLAY_S2C_CHUNK_BATCH_START                0x0C
%define MCP_PLAY_S2C_CHUNK_BIOMES                     0x0D
%define MCP_PLAY_S2C_CLEAR_TITLES                     0x0E
%define MCP_PLAY_S2C_TAB_COMPLETE                     0x0F
%define MCP_PLAY_S2C_DECLARE_COMMANDS                 0x10
%define MCP_PLAY_S2C_CLOSE_WINDOW                     0x11
%define MCP_PLAY_S2C_WINDOW_ITEMS                     0x12
%define MCP_PLAY_S2C_CRAFT_PROGRESS_BAR               0x13
%define MCP_PLAY_S2C_SET_SLOT                         0x14
%define MCP_PLAY_S2C_COOKIE_REQUEST                   0x15
%define MCP_PLAY_S2C_SET_COOLDOWN                     0x16
%define MCP_PLAY_S2C_CHAT_SUGGESTIONS                 0x17
%define MCP_PLAY_S2C_CUSTOM_PAYLOAD                   0x18
%define MCP_PLAY_S2C_DAMAGE_EVENT                     0x19
%define MCP_PLAY_S2C_DEBUG_BLOCK_VALUE                0x1A
%define MCP_PLAY_S2C_DEBUG_CHUNK_VALUE                0x1B
%define MCP_PLAY_S2C_DEBUG_ENTITY_VALUE               0x1C
%define MCP_PLAY_S2C_DEBUG_EVENT                      0x1D
%define MCP_PLAY_S2C_DEBUG_SAMPLE                     0x1E
%define MCP_PLAY_S2C_HIDE_MESSAGE                     0x1F
%define MCP_PLAY_S2C_KICK_DISCONNECT                  0x20
%define MCP_PLAY_S2C_PROFILELESS_CHAT                 0x21
%define MCP_PLAY_S2C_ENTITY_STATUS                    0x22
%define MCP_PLAY_S2C_SYNC_ENTITY_POSITION             0x23
%define MCP_PLAY_S2C_EXPLOSION                        0x24
%define MCP_PLAY_S2C_UNLOAD_CHUNK                     0x25
%define MCP_PLAY_S2C_GAME_STATE_CHANGE                0x26
%define MCP_PLAY_S2C_GAME_RULE_VALUES                 0x27
%define MCP_PLAY_S2C_GAME_TEST_HIGHLIGHT_POS          0x28
%define MCP_PLAY_S2C_OPEN_HORSE_WINDOW                0x29
%define MCP_PLAY_S2C_HURT_ANIMATION                   0x2A
%define MCP_PLAY_S2C_INITIALIZE_WORLD_BORDER          0x2B
%define MCP_PLAY_S2C_KEEP_ALIVE                       0x2C
%define MCP_PLAY_S2C_MAP_CHUNK                        0x2D
%define MCP_PLAY_S2C_WORLD_EVENT                      0x2E
%define MCP_PLAY_S2C_WORLD_PARTICLES                  0x2F
%define MCP_PLAY_S2C_UPDATE_LIGHT                     0x30
%define MCP_PLAY_S2C_LOGIN                            0x31
%define MCP_PLAY_S2C_LOW_DISK_SPACE_WARNING           0x32
%define MCP_PLAY_S2C_MAP                              0x33
%define MCP_PLAY_S2C_TRADE_LIST                       0x34
%define MCP_PLAY_S2C_REL_ENTITY_MOVE                  0x35
%define MCP_PLAY_S2C_ENTITY_MOVE_LOOK                 0x36
%define MCP_PLAY_S2C_MOVE_MINECART                    0x37
%define MCP_PLAY_S2C_ENTITY_LOOK                      0x38
%define MCP_PLAY_S2C_VEHICLE_MOVE                     0x39
%define MCP_PLAY_S2C_OPEN_BOOK                        0x3A
%define MCP_PLAY_S2C_OPEN_WINDOW                      0x3B
%define MCP_PLAY_S2C_OPEN_SIGN_ENTITY                 0x3C
%define MCP_PLAY_S2C_PING                             0x3D
%define MCP_PLAY_S2C_PING_RESPONSE                    0x3E
%define MCP_PLAY_S2C_CRAFT_RECIPE_RESPONSE            0x3F
%define MCP_PLAY_S2C_ABILITIES                        0x40
%define MCP_PLAY_S2C_PLAYER_CHAT                      0x41
%define MCP_PLAY_S2C_END_COMBAT_EVENT                 0x42
%define MCP_PLAY_S2C_ENTER_COMBAT_EVENT               0x43
%define MCP_PLAY_S2C_DEATH_COMBAT_EVENT               0x44
%define MCP_PLAY_S2C_PLAYER_REMOVE                    0x45
%define MCP_PLAY_S2C_PLAYER_INFO                      0x46
%define MCP_PLAY_S2C_FACE_PLAYER                      0x47
%define MCP_PLAY_S2C_POSITION                         0x48
%define MCP_PLAY_S2C_PLAYER_ROTATION                  0x49
%define MCP_PLAY_S2C_RECIPE_BOOK_ADD                  0x4A
%define MCP_PLAY_S2C_RECIPE_BOOK_REMOVE               0x4B
%define MCP_PLAY_S2C_RECIPE_BOOK_SETTINGS             0x4C
%define MCP_PLAY_S2C_ENTITY_DESTROY                   0x4D
%define MCP_PLAY_S2C_REMOVE_ENTITY_EFFECT             0x4E
%define MCP_PLAY_S2C_RESET_SCORE                      0x4F
%define MCP_PLAY_S2C_REMOVE_RESOURCE_PACK             0x50
%define MCP_PLAY_S2C_ADD_RESOURCE_PACK                0x51
%define MCP_PLAY_S2C_RESPAWN                          0x52
%define MCP_PLAY_S2C_ENTITY_HEAD_ROTATION             0x53
%define MCP_PLAY_S2C_MULTI_BLOCK_CHANGE               0x54
%define MCP_PLAY_S2C_SELECT_ADVANCEMENT_TAB           0x55
%define MCP_PLAY_S2C_SERVER_DATA                      0x56
%define MCP_PLAY_S2C_ACTION_BAR                       0x57
%define MCP_PLAY_S2C_WORLD_BORDER_CENTER              0x58
%define MCP_PLAY_S2C_WORLD_BORDER_LERP_SIZE           0x59
%define MCP_PLAY_S2C_WORLD_BORDER_SIZE                0x5A
%define MCP_PLAY_S2C_WORLD_BORDER_WARNING_DELAY       0x5B
%define MCP_PLAY_S2C_WORLD_BORDER_WARNING_REACH       0x5C
%define MCP_PLAY_S2C_CAMERA                           0x5D
%define MCP_PLAY_S2C_UPDATE_VIEW_POSITION             0x5E
%define MCP_PLAY_S2C_UPDATE_VIEW_DISTANCE             0x5F
%define MCP_PLAY_S2C_SET_CURSOR_ITEM                  0x60
%define MCP_PLAY_S2C_SPAWN_POSITION                   0x61
%define MCP_PLAY_S2C_SCOREBOARD_DISPLAY_OBJECTIVE     0x62
%define MCP_PLAY_S2C_ENTITY_METADATA                  0x63
%define MCP_PLAY_S2C_ATTACH_ENTITY                    0x64
%define MCP_PLAY_S2C_ENTITY_VELOCITY                  0x65
%define MCP_PLAY_S2C_ENTITY_EQUIPMENT                 0x66
%define MCP_PLAY_S2C_EXPERIENCE                       0x67
%define MCP_PLAY_S2C_UPDATE_HEALTH                    0x68
%define MCP_PLAY_S2C_HELD_ITEM_SLOT                   0x69
%define MCP_PLAY_S2C_SCOREBOARD_OBJECTIVE             0x6A
%define MCP_PLAY_S2C_SET_PASSENGERS                   0x6B
%define MCP_PLAY_S2C_SET_PLAYER_INVENTORY             0x6C
%define MCP_PLAY_S2C_TEAMS                            0x6D
%define MCP_PLAY_S2C_SCOREBOARD_SCORE                 0x6E
%define MCP_PLAY_S2C_SIMULATION_DISTANCE              0x6F
%define MCP_PLAY_S2C_SET_TITLE_SUBTITLE               0x70
%define MCP_PLAY_S2C_UPDATE_TIME                      0x71
%define MCP_PLAY_S2C_SET_TITLE_TEXT                   0x72
%define MCP_PLAY_S2C_SET_TITLE_TIME                   0x73
%define MCP_PLAY_S2C_ENTITY_SOUND_EFFECT              0x74
%define MCP_PLAY_S2C_SOUND_EFFECT                     0x75
%define MCP_PLAY_S2C_START_CONFIGURATION              0x76
%define MCP_PLAY_S2C_STOP_SOUND                       0x77
%define MCP_PLAY_S2C_STORE_COOKIE                     0x78
%define MCP_PLAY_S2C_SYSTEM_CHAT                      0x79
%define MCP_PLAY_S2C_PLAYERLIST_HEADER                0x7A
%define MCP_PLAY_S2C_NBT_QUERY_RESPONSE               0x7B
%define MCP_PLAY_S2C_COLLECT                          0x7C
%define MCP_PLAY_S2C_ENTITY_TELEPORT                  0x7D
%define MCP_PLAY_S2C_TEST_INSTANCE_BLOCK_STATUS       0x7E
%define MCP_PLAY_S2C_SET_TICKING_STATE                0x7F
%define MCP_PLAY_S2C_STEP_TICK                        0x80
%define MCP_PLAY_S2C_TRANSFER                         0x81
%define MCP_PLAY_S2C_ADVANCEMENTS                     0x82
%define MCP_PLAY_S2C_ENTITY_UPDATE_ATTRIBUTES         0x83
%define MCP_PLAY_S2C_ENTITY_EFFECT                    0x84
%define MCP_PLAY_S2C_DECLARE_RECIPES                  0x85
%define MCP_PLAY_S2C_TAGS                             0x86
%define MCP_PLAY_S2C_SET_PROJECTILE_POWER             0x87
%define MCP_PLAY_S2C_CUSTOM_REPORT_DETAILS            0x88
%define MCP_PLAY_S2C_SERVER_LINKS                     0x89
%define MCP_PLAY_S2C_TRACKED_WAYPOINT                 0x8A
%define MCP_PLAY_S2C_CLEAR_DIALOG                     0x8B
%define MCP_PLAY_S2C_SHOW_DIALOG                      0x8C

; play serverbound
%define MCP_PLAY_C2S_TELEPORT_CONFIRM                 0x00
%define MCP_PLAY_C2S_ATTACK                           0x01
%define MCP_PLAY_C2S_QUERY_BLOCK_NBT                  0x02
%define MCP_PLAY_C2S_SELECT_BUNDLE_ITEM               0x03
%define MCP_PLAY_C2S_SET_DIFFICULTY                   0x04
%define MCP_PLAY_C2S_CHANGE_GAMEMODE                  0x05
%define MCP_PLAY_C2S_MESSAGE_ACKNOWLEDGEMENT          0x06
%define MCP_PLAY_C2S_CHAT_COMMAND                     0x07
%define MCP_PLAY_C2S_CHAT_COMMAND_SIGNED              0x08
%define MCP_PLAY_C2S_CHAT_MESSAGE                     0x09
%define MCP_PLAY_C2S_CHAT_SESSION_UPDATE              0x0A
%define MCP_PLAY_C2S_CHUNK_BATCH_RECEIVED             0x0B
%define MCP_PLAY_C2S_CLIENT_COMMAND                   0x0C
%define MCP_PLAY_C2S_TICK_END                         0x0D
%define MCP_PLAY_C2S_SETTINGS                         0x0E
%define MCP_PLAY_C2S_TAB_COMPLETE                     0x0F
%define MCP_PLAY_C2S_CONFIGURATION_ACKNOWLEDGED       0x10
%define MCP_PLAY_C2S_ENCHANT_ITEM                     0x11
%define MCP_PLAY_C2S_WINDOW_CLICK                     0x12
%define MCP_PLAY_C2S_CLOSE_WINDOW                     0x13
%define MCP_PLAY_C2S_SET_SLOT_STATE                   0x14
%define MCP_PLAY_C2S_COOKIE_RESPONSE                  0x15
%define MCP_PLAY_C2S_CUSTOM_PAYLOAD                   0x16
%define MCP_PLAY_C2S_DEBUG_SUBSCRIPTION_REQUEST       0x17
%define MCP_PLAY_C2S_EDIT_BOOK                        0x18
%define MCP_PLAY_C2S_QUERY_ENTITY_NBT                 0x19
%define MCP_PLAY_C2S_USE_ENTITY                       0x1A
%define MCP_PLAY_C2S_GENERATE_STRUCTURE               0x1B
%define MCP_PLAY_C2S_KEEP_ALIVE                       0x1C
%define MCP_PLAY_C2S_LOCK_DIFFICULTY                  0x1D
%define MCP_PLAY_C2S_POSITION                         0x1E
%define MCP_PLAY_C2S_POSITION_LOOK                    0x1F
%define MCP_PLAY_C2S_LOOK                             0x20
%define MCP_PLAY_C2S_FLYING                           0x21
%define MCP_PLAY_C2S_VEHICLE_MOVE                     0x22
%define MCP_PLAY_C2S_STEER_BOAT                       0x23
%define MCP_PLAY_C2S_PICK_ITEM_FROM_BLOCK             0x24
%define MCP_PLAY_C2S_PICK_ITEM_FROM_ENTITY            0x25
%define MCP_PLAY_C2S_PING_REQUEST                     0x26
%define MCP_PLAY_C2S_CRAFT_RECIPE_REQUEST             0x27
%define MCP_PLAY_C2S_ABILITIES                        0x28
%define MCP_PLAY_C2S_BLOCK_DIG                        0x29
%define MCP_PLAY_C2S_ENTITY_ACTION                    0x2A
%define MCP_PLAY_C2S_PLAYER_INPUT                     0x2B
%define MCP_PLAY_C2S_PLAYER_LOADED                    0x2C
%define MCP_PLAY_C2S_PONG                             0x2D
%define MCP_PLAY_C2S_RECIPE_BOOK                      0x2E
%define MCP_PLAY_C2S_DISPLAYED_RECIPE                 0x2F
%define MCP_PLAY_C2S_NAME_ITEM                        0x30
%define MCP_PLAY_C2S_RESOURCE_PACK_RECEIVE            0x31
%define MCP_PLAY_C2S_ADVANCEMENT_TAB                  0x32
%define MCP_PLAY_C2S_SELECT_TRADE                     0x33
%define MCP_PLAY_C2S_SET_BEACON_EFFECT                0x34
%define MCP_PLAY_C2S_HELD_ITEM_SLOT                   0x35
%define MCP_PLAY_C2S_UPDATE_COMMAND_BLOCK             0x36
%define MCP_PLAY_C2S_UPDATE_COMMAND_BLOCK_MINECART    0x37
%define MCP_PLAY_C2S_SET_CREATIVE_SLOT                0x38
%define MCP_PLAY_C2S_SET_GAME_RULE                    0x39
%define MCP_PLAY_C2S_UPDATE_JIGSAW_BLOCK              0x3A
%define MCP_PLAY_C2S_UPDATE_STRUCTURE_BLOCK           0x3B
%define MCP_PLAY_C2S_SET_TEST_BLOCK                   0x3C
%define MCP_PLAY_C2S_UPDATE_SIGN                      0x3D
%define MCP_PLAY_C2S_SPECTATE_ENTITY                  0x3E
%define MCP_PLAY_C2S_ARM_ANIMATION                    0x3F
%define MCP_PLAY_C2S_SPECTATE                         0x40
%define MCP_PLAY_C2S_TEST_INSTANCE_BLOCK_ACTION       0x41
%define MCP_PLAY_C2S_BLOCK_PLACE                      0x42
%define MCP_PLAY_C2S_USE_ITEM                         0x43
%define MCP_PLAY_C2S_CUSTOM_CLICK_ACTION              0x44

extern mcmap_biome          ; (ecx our biome id) -> eax java biome registry index (as sent in config)
extern mcmap_send_known_packs ; (rcx MCCONN*) config phase: select_known_packs [minecraft:core 26.1]
extern mcmap_send_registries ; (rcx MCCONN*, edx 1 = client has minecraft:core) every registry_data (no data if it has it) + the vanilla update_tags
%endif

%endif
