extends Node
class_name Server

# Authoritative game server. Lives under /root/NetworkManager/Server
# on the host machine only. Remote clients never have this node.
#
# All commands arrive through handle_command():
#   Local (host/AI) -> Global.send_command() -> handle_command()
#   Remote          -> Global._on_remote_command() -> handle_command()
#
# Command handlers use the _cmd_ prefix for automatic dispatch via
# reflection -- see handle_command().

# --- State ---

var enet_peer: ENetMultiplayerPeer
var peer_to_player: Dictionary = {}
var player_to_peer: Dictionary = {}
# Player numbers reserved for REMOTE slots, in slot order (slot index + 1).
# Populated by NetworkManager.start_server(); _on_peer_connected pops the next
# one, _on_peer_disconnected pushes it back so a reconnect reclaims its slot.
var remote_slot_pnums: Array[int] = []
# Per-player camera mode (VideoManager.CameraStatus) reported by each client
# via _cmd_camera_mode. Used by server sims that depend on the *owner's* camera
# state (e.g. avatar VIRUS-detect radius, rally legality). Defaults to OVERHEAD
# until a client reports FPS.
var camera_mode: Dictionary = {}
# Rally call cooldown per player (pnum -> ready tick in ms). Enforced on the
# server; the client shows its own approximation in the HUD.
var _rally_cooldowns: Dictionary = {}
# False until the host has set up and entered the lobby; clients connecting
# before that are rejected so they get a connection failure instead of joining.
var accepting_clients: bool = false

# Command dispatch tables, built once from the method list. The _cmd_ prefix
# is the allowlist; arg counts are validated against the stored signatures.
var _command_table: Dictionary = {} # StringName -> Callable
var _command_arg_counts: Dictionary = {} # StringName -> int (args after player_number)

# --- Lifecycle ---

func _ready() -> void:
	for m in get_method_list():
		var method_name: StringName = m["name"]
		if String(method_name).begins_with("_cmd_"):
			_command_table[method_name] = Callable(self, method_name)
			_command_arg_counts[method_name] = maxi(int(m["args"].size()) - 1, 0)

func start(config: GameConfig) -> bool:
	enet_peer = ENetMultiplayerPeer.new()
	var err := enet_peer.create_server(config.port, config.player_count)
	if err != OK:
		push_error("Failed to start server: ", err)
		# Leave enet_peer null so callers can detect the failure (e.g. a stale
		# instance already holding the port) instead of silently proceeding.
		enet_peer = null
		return false
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return true

func stop() -> void:
	multiplayer.multiplayer_peer = null
	if enet_peer:
		enet_peer.close()

# --- Command dispatch ---

func handle_command(pnum: int, command: String, args: Array) -> void:
	var method_name := StringName("_cmd_" + command)
	if not _command_table.has(method_name):
		push_error("Server: unknown command: ", command)
		return
	if args.size() != _command_arg_counts[method_name]:
		push_error("Server: arg count mismatch for ", command, ": got ", args.size(), " expected ", _command_arg_counts[method_name])
		return
	callv(method_name, [pnum] + args)

# --- Peer management ---

func _on_peer_connected(peer_id: int) -> void:
	if not accepting_clients:
		# Host isn't ready (not in the lobby) — reject so the client sees a
		# connection failure rather than silently joining.
		enet_peer.disconnect_peer(peer_id)
		return
	if remote_slot_pnums.is_empty():
		# No free slot for this peer — all player numbers are taken (or this is
		# a client beyond the configured slots). Reject instead of inventing a
		# player number past MAX_PLAYERS.
		push_warning("Server._on_peer_connected: no free player slot for peer ", peer_id)
		enet_peer.disconnect_peer(peer_id)
		return
	var pnum: int = remote_slot_pnums.pop_front()
	peer_to_player[peer_id] = pnum
	player_to_peer[pnum] = peer_id
	print("Server._on_peer_connected  peer_id=", peer_id, "  assigned pnum=", pnum)
	Global.network_manager.rpc_id(peer_id, "rpc_set_my_player_number", pnum)
	# TODO: sync full tile state to reconnecting mid-game peer
	#   tm.rpc_id(peer_id, "set_tile_selection", id, selected_by) for every tile with selectors

func _on_peer_disconnected(peer_id: int) -> void:
	var pnum = peer_to_player.get(peer_id)
	if pnum != null:
		print("Server._on_peer_disconnected  peer_id=", peer_id, "  pnum=", pnum)
		peer_to_player.erase(peer_id)
		player_to_peer.erase(pnum)
		# Free the slot for a reconnecting client (push_front keeps the slot
		# order stable — the same player number is reclaimed first).
		if not remote_slot_pnums.has(pnum):
			remote_slot_pnums.push_front(pnum)

# --- Command handlers ---

func _cmd_place_blueprint(player_number: int, tile_id: int, building_type: int) -> void:
	# Whitelist the placeable types — MCPs and NONE would otherwise reach
	# update_blueprint's enabled_blueprints[type] dict access and error.
	if building_type not in [BuildingManager.Type.GEN, BuildingManager.Type.VAT,
			BuildingManager.Type.GARAGE, BuildingManager.Type.BEACON, BuildingManager.Type.NEST]:
		push_warning("Server._cmd_place_blueprint: invalid building_type ", building_type)
		return
	var tm = Global.TM
	if not tm:
		push_warning("Server._cmd_place_blueprint: TileManager not found")
		return
	var tile = tm.get_tile_by_id(tile_id)
	if not tile:
		push_warning("Server._cmd_place_blueprint: tile not found: ", tile_id)
		return
	var bm = Global.BM
	if not bm:
		push_warning("Server._cmd_place_blueprint: BuildingManager not found")
		return
	bm.place_blueprint(player_number, tile, building_type)

func _cmd_remove_building(player_number: int, building_id: int) -> void:
	var bm = Global.BM
	if not bm:
		push_warning("Server._cmd_remove_building: BuildingManager not found")
		return
	var b = bm.get_building_by_id(building_id)
	if not _can_control_building(player_number, b):
		push_warning("Server._cmd_remove_building: not owner of building ", building_id)
		return
	if b is MCP:
		return
	if bm._empowered_by_player.get(player_number) == b:
		bm.clear_empowered_for_player(player_number)
	bm.rpc("rpc_remove_building", building_id)

func _cmd_toggle_tile(player_number: int, tile_id: int) -> void:
	var tm = Global.TM
	if not tm:
		push_warning("Server._cmd_toggle_tile: TileManager not found")
		return
	tm.apply_toggle(player_number, tile_id)

# --- Building terminal commands ---

func _can_control_building(player_number: int, b: Building) -> bool:
	if not b:
		return false
	return b.player_owner == player_number

func _cmd_toggle_production(player_number: int, building_id: int) -> void:
	var bm = Global.BM
	if not bm:
		return
	var b = bm.get_building_by_id(building_id)
	if not _can_control_building(player_number, b):
		return
	if b.has_method("toggle_production"):
		b.toggle_production()

func _cmd_set_garage_ratio(player_number: int, building_id: int, ratio: float) -> void:
	var bm = Global.BM
	if not bm:
		return
	var b = bm.get_building_by_id(building_id)
	if not _can_control_building(player_number, b):
		return
	if b is Garage:
		b.zoomba_tank_ratio = clampf(ratio, 0.0, 1.0)

func _cmd_set_beacon_ratio(player_number: int, building_id: int, ratio: float) -> void:
	var bm = Global.BM
	if not bm:
		return
	var b = bm.get_building_by_id(building_id)
	if not _can_control_building(player_number, b):
		return
	if b is Beacon:
		b.patrol_strike_ratio = clampf(ratio, 0.0, 1.0)

func _cmd_set_nest_ratio(player_number: int, building_id: int, ratio: float) -> void:
	var bm = Global.BM
	if not bm:
		return
	var b = bm.get_building_by_id(building_id)
	if not _can_control_building(player_number, b):
		return
	if b is Nest:
		b.set_virus_tank_building_ratio(ratio)

func _cmd_set_enemy_targets(player_number: int, building_id: int, targets: Array) -> void:
	var bm = Global.BM
	if not bm:
		return
	var b = bm.get_building_by_id(building_id)
	if not _can_control_building(player_number, b):
		return
	if b.has_method("set_enemy_targets"):
		b.set_enemy_targets(targets as Array[int])

func _cmd_set_building_targets(player_number: int, building_id: int, targets: Array) -> void:
	var bm = Global.BM
	if not bm:
		return
	var b = bm.get_building_by_id(building_id)
	if not _can_control_building(player_number, b):
		return
	if b is Nest or b is Beacon:
		b.set_building_targets(targets as Array[BuildingManager.Type])

func _cmd_set_patrol_stance(player_number: int, building_id: int, stance: int) -> void:
	var bm = Global.BM
	if not bm:
		return
	var b = bm.get_building_by_id(building_id)
	if not _can_control_building(player_number, b):
		return
	if b is Beacon or b is Garage:
		b.set_patrol_stance(stance as JobManager.Stance)

func _cmd_empower(player_number: int, building_id: int) -> void:
	var bm = Global.BM
	if not bm:
		return
	var b = bm.get_building_by_id(building_id)
	if not _can_control_building(player_number, b):
		return
	bm.set_empowered_for_player(player_number, b)

func _cmd_clear_empower(player_number: int) -> void:
	var bm = Global.BM
	if bm:
		bm.clear_empowered_for_player(player_number)

# --- Client camera state (used by server sims, not a game action) ---

func _cmd_camera_mode(player_number: int, mode: int) -> void:
	camera_mode[player_number] = mode
	# Leaving FPS disbands the rally squad immediately (DESIGN: the rally lasts
	# until the avatar dies or the player exits FPS).
	if mode != VideoManager.CameraStatus.FPS and mode != VideoManager.CameraStatus.TO_FPS:
		if Global.JM:
			Global.JM.cancel_player_rally(player_number)

func get_camera_mode(player_number: int) -> int:
	return camera_mode.get(player_number, VideoManager.CameraStatus.OVERHEAD)

# --- Avatar rally (FPS-only, per DESIGN) ---

func _cmd_rally(player_number: int) -> void:
	var jm = Global.JM
	if not jm:
		return
	var um = Global.UM
	if not um:
		return
	var avatar = get_tree().get_first_node_in_group("avatar_player" + str(player_number))
	if not avatar or avatar.health <= 0:
		return
	if camera_mode.get(player_number, VideoManager.CameraStatus.OVERHEAD) != VideoManager.CameraStatus.FPS:
		return # RALLY is an FPS ability — a cheated RTS press is rejected
	var now := Time.get_ticks_msec()
	if _rally_cooldowns.get(player_number, 0) > now:
		return
	_rally_cooldowns[player_number] = now + int(Config.RALLY_COOLDOWN * 1000.0)
	jm.start_rally(player_number)
	var body: Node3D = avatar.fps_body_node
	var origin: Vector3 = body.global_position if body else avatar.global_position
	um.rpc("rpc_rally_fx", player_number, origin.x, origin.y, origin.z, Config.RALLY_RADIUS)

# --- Debug helpers (server-authoritative so they work from any peer) ---

func _cmd_debug_damage_unit(_player_number: int) -> void:
	for u in get_tree().get_nodes_in_group("unit"):
		u.apply_damage(Config.UNIT_MAX_HP.get(u.type, 100.0) * 0.4)

func _cmd_debug_damage_building(_player_number: int) -> void:
	for b in get_tree().get_nodes_in_group("building"):
		if b is MCP:
			continue
		b.apply_damage(b.max_health * 0.4)
