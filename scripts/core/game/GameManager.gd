extends Node3D

class_name GameManager

# --- Constants ---

const SNAPSHOT_INTERVAL := 0.05
const JOB_TICK_INTERVAL := 1.0
const INTERPOLATION_DELAY := 0.075
const AVATAR_SEND_INTERVAL := 0.05
# Snapshot per-entity float slots. Buildings use slot 10 for the VIRUS
# infection attacker bitmask, slot 11 for pooled channel progress and slot 12
# for the longest remaining infection duration (see _pack_building); units
# leave them zero.
const SLOT_COUNT := 13
const MAX_SNAPSHOT_BUFFER := 4
# Snapshots are split into chunks kept well below the ENet MTU (1392 bytes).
# 256 float32s = 1024 bytes of payload per chunk; a dropped chunk costs the
# whole snapshot, exactly like ENet fragmentation did, but without the
# per-fragment loss multiplier of one giant packet.
const SNAPSHOT_CHUNK_FLOATS := 256
# Upper bound on partially-received snapshots buffered on the client; a lost
# chunk would otherwise leak a never-completing entry.
const CHUNK_BUFFER_MAX := 8
# Foreign terminal UI refresh runs at 4 Hz instead of every frame/snapshot.
const TERMINAL_REFRESH_INTERVAL := 0.25
const READY_TIMEOUT: float = 15.0
# How long the victory banner stays up before the game stops and the
# statistics window opens (runs on every peer via a local timer).
const GAME_OVER_BANNER_DURATION: float = 5.0
# Cached per-player avatar nodes: group lookups with string concat were running
# every server frame (_interpolate_avatars) and at 20 Hz client-side
# (_send_avatar_snapshot). Entries expire after AVATAR_CACHE_TTL seconds.
const AVATAR_CACHE_TTL: float = 1.0

# --- State ---

var _snapshot_timer := 0.0
var _job_timer := 0.0
var _avatar_snapshot_timer := 0.0
var _terminal_refresh_timer := 0.0

var _snapshots: Array = []
var _avatar_snapshots: Dictionary = {}

# Monotonic snapshot counter; clients use it to reassemble chunked snapshots.
var _snapshot_seq := 0
# seq -> {"total": int, "chunks": {idx: PackedFloat32Array}} (client only).
var _chunk_buffer: Dictionary = {}

# Scratch buffer reused by _pack_unit (server, 20 Hz) instead of allocating a
# fresh 10-float array per unit per snapshot. float32 halves the wire size.
var _pack_scratch: PackedFloat32Array
# Client-side interpolation scratch (per unit per frame).
var _interp_scratch: Array[float] = []

var _avatar_cache: Dictionary = {} # pnum -> {"avatar": Node, "time": float}

var _server_ready: bool = false
var _world_ready: bool = false  # client: this peer has finished initialising World
var _expected_clients: int = 0
var _ready_peers: Dictionary = {}  # pnum -> true
var _start_timeout: float = 0.0

# --- End-of-game ---

var _game_over: bool = false
var _game_over_winner: int = 0
# 0 = no game over, 1 = victory banner showing, 2 = banner done, stats open.
var _game_over_phase: int = 0
var _game_over_timer: float = 0.0

# --- Catch-up (server only, per DESIGN) ---

# Desperation Meter: consecutive seconds behind the leader and the resulting
# stack count, per player (1-based). Driven by the 1s job tick.
var _behind_seconds: Dictionary = {}
var _desperation_stacks: Dictionary = {}

# --- Avatar cache ---

func _get_avatar(pnum: int) -> Unit:
	var now := Time.get_ticks_msec() / 1000.0
	var entry = _avatar_cache.get(pnum)
	if entry != null and entry["time"] > now - AVATAR_CACHE_TTL and is_instance_valid(entry["avatar"]):
		return entry["avatar"]
	var avatar := get_tree().get_first_node_in_group("avatar_player" + str(pnum)) as Unit
	_avatar_cache[pnum] = {"avatar": avatar, "time": now}
	return avatar

# --- Lifecycle ---

func _ready() -> void:
	Global.GM = self
	Global.game_started = false
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Deferred so it runs after every manager has finished _ready (incl. the
	# tile grid generation and MCP placement).
	call_deferred("_on_world_ready")

# --- Main loop ---

func _process(delta: float) -> void:
	# End-of-game countdown (all peers): the banner runs GAME_OVER_BANNER_DURATION,
	# then the game stops and the statistics window opens.
	if _game_over_phase == 1:
		_game_over_timer += delta
		if _game_over_timer >= GAME_OVER_BANNER_DURATION:
			_game_over_phase = 2
			Global.game_started = false
			var banner := _victory_banner()
			if banner and banner.has_method("hide_banner"):
				banner.hide_banner()
			_show_end_of_game_stats()
	if not multiplayer.is_server():
		if Global.game_started:
			_avatar_snapshot_timer += delta
			while _avatar_snapshot_timer >= AVATAR_SEND_INTERVAL:
				_avatar_snapshot_timer -= AVATAR_SEND_INTERVAL
				_send_avatar_snapshot()
			_interpolate()
		_throttled_terminal_refresh(delta)
		return
	# Server
	if not Global.game_started:
		if _game_over:
			# Never re-start a finished game.
			return
		if _server_ready:
			_start_timeout += delta
			if _start_timeout >= READY_TIMEOUT:
				_start_timeout = 0.0
				rpc("rpc_game_start")
		return
	_snapshot_timer += delta
	_job_timer += delta
	while _snapshot_timer >= SNAPSHOT_INTERVAL:
		_snapshot_timer -= SNAPSHOT_INTERVAL
		_send_snapshot()
	_interpolate_avatars()
	while _job_timer >= JOB_TICK_INTERVAL:
		_job_timer -= JOB_TICK_INTERVAL
		Global.JM.assign_jobs()
		for b in Global.BM.buildings():
			b.check_work()
		_tick_desperation()
	_throttled_terminal_refresh(delta)

# --- Catch-up (per DESIGN) ---

# DESIGN: Desperation Meter — a player gains one stack per CATCHUP_DESP_STACK_EVERY
# of consecutive time with fewer tiles than the leader; stacks reset when they
# claim or tie the lead. Each stack grants energy income and offensive damage
# (see desperation_energy_rate / desperation_damage_mult). Server-only, called
# from the 1s job tick. Early-outs while the system is disabled in Config.
func _tick_desperation() -> void:
	if Config.CATCHUP_DESP_MAX_STACKS <= 0 or Config.CATCHUP_DESP_STACK_EVERY <= 0.0:
		return
	var leader := _tile_leader()
	if leader <= 0.0:
		return
	for p in range(1, Global.MAX_PLAYERS + 1):
		var mine: float = Global.TM.player_aoe_totals.get(p, 0.0)
		if mine >= leader:
			_behind_seconds[p] = 0.0
			_desperation_stacks[p] = 0
			continue
		_behind_seconds[p] = _behind_seconds.get(p, 0.0) + 1.0
		if _behind_seconds[p] >= Config.CATCHUP_DESP_STACK_EVERY:
			_behind_seconds[p] = 0.0
			_desperation_stacks[p] = mini(
				_desperation_stacks.get(p, 0) + 1, Config.CATCHUP_DESP_MAX_STACKS)

func _tile_leader() -> float:
	var leader := 0.0
	for p in Global.TM.player_aoe_totals:
		leader = maxf(leader, Global.TM.player_aoe_totals[p])
	return leader

# DESIGN: Underdog Grit — the behind player's Zoombas work faster: +3% per 10%
# tile deficit relative to the leader, capped at CATCHUP_GRIT_MAX_STACKS. Pure
# function of the current split-AoE totals (no accumulation). Multiplicative.
func underdog_grit_work_mult(pnum: int) -> float:
	if Config.CATCHUP_GRIT_MAX_STACKS <= 0 or Config.CATCHUP_GRIT_DEFICIT_STEP <= 0.0:
		return 1.0
	var leader := _tile_leader()
	var mine: float = Global.TM.player_aoe_totals.get(pnum, 0.0)
	if leader <= 0.0 or mine >= leader:
		return 1.0
	var stacks: int = mini(
		int((leader - mine) / leader / Config.CATCHUP_GRIT_DEFICIT_STEP),
		Config.CATCHUP_GRIT_MAX_STACKS)
	return 1.0 + (Config.CATCHUP_GRIT_WORK_MULT_PER_STACK - 1.0) * stacks

# DESIGN: Desperation Meter energy — +CATCHUP_DESP_ENERGY_PER_STACK e/sec per
# stack, capped at CATCHUP_DESP_MAX_STACKS (30e/sec at DESIGN values).
func desperation_energy_rate(pnum: int) -> float:
	var stacks: int = _desperation_stacks.get(pnum, 0)
	return minf(stacks, Config.CATCHUP_DESP_MAX_STACKS) * Config.CATCHUP_DESP_ENERGY_PER_STACK

# DESIGN: Desperation Meter damage — offensive units (STRIKE, VIRUS) deal
# +CATCHUP_DESP_DAMAGE_PER_STACK per stack, capped at CATCHUP_DESP_MAX_STACKS
# (+18% at DESIGN values).
func desperation_damage_mult(pnum: int) -> float:
	var stacks: int = _desperation_stacks.get(pnum, 0)
	return 1.0 + minf(stacks, Config.CATCHUP_DESP_MAX_STACKS) * Config.CATCHUP_DESP_DAMAGE_PER_STACK

func _throttled_terminal_refresh(delta: float) -> void:
	_terminal_refresh_timer += delta
	if _terminal_refresh_timer >= TERMINAL_REFRESH_INTERVAL:
		_terminal_refresh_timer = 0.0
		_refresh_foreign_building_terminals()

# --- Game start gate ---

func _on_world_ready() -> void:
	var srv = Global.network_manager.server
	if srv:
		_server_ready = true
		_expected_clients = srv.peer_to_player.size()
		# Ask clients to confirm readiness (a client may have sent its first
		# client_ready before this server node existed, so that RPC was dropped).
		if _expected_clients > 0:
			rpc("rpc_request_client_ready")
		_maybe_start_game()
	else:
		_world_ready = true
		rpc_id(1, "rpc_client_ready")

# Server asks each client to (re)send client_ready — only if that client has
# actually finished loading the World (a client still loading will send its own
# client_ready from _on_world_ready later, once the server node exists).
@rpc("authority", "call_remote", "reliable")
func rpc_request_client_ready() -> void:
	if _world_ready:
		rpc_id(1, "rpc_client_ready")

@rpc("any_peer", "call_remote", "reliable")
func rpc_client_ready() -> void:
	var srv = Global.network_manager.server
	if not srv:
		return
	var caller := multiplayer.get_remote_sender_id()
	var pnum = srv.peer_to_player.get(caller)
	if pnum == null:
		return
	_ready_peers[pnum] = true
	_broadcast_progress()
	_maybe_start_game()

func _maybe_start_game() -> void:
	if not _server_ready:
		return
	if _ready_peers.size() >= _expected_clients:
		_broadcast_progress()
		rpc("rpc_game_start")

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server() or Global.game_started:
		return
	var srv = Global.network_manager.server
	if srv:
		var pnum = srv.peer_to_player.get(peer_id)
		if pnum != null:
			_ready_peers.erase(pnum)
	_expected_clients = maxi(0, _expected_clients - 1)
	_broadcast_progress()
	_maybe_start_game()

@rpc("authority", "call_local", "reliable")
func rpc_game_start() -> void:
	Global.game_started = true
	_hide_loading_overlay()

# --- End of game ---

# Server only: a player's MCP was destroyed. Remove everything they still own,
# then check whether a single MCP remains — that owner wins the game. The
# cleanup always runs (the sim keeps going during the banner, so a second MCP
# can fall); only the win check is skipped once the game is decided.
func on_player_eliminated(pnum: int) -> void:
	if not multiplayer.is_server():
		return
	Global.BM.clear_empowered_for_player(pnum)
	var bm := Global.BM
	var um := Global.UM
	var bids: Array[int] = []
	for b in bm.buildings():
		if b.player_owner == pnum:
			bids.append(b.id)
	for bid in bids:
		bm.rpc("rpc_remove_building", bid)
	var uids: Array[int] = []
	for u in um.units():
		if u.player_owner == pnum:
			uids.append(u.id)
	for uid in uids:
		um.rpc("rpc_remove_unit", uid)
	var alive: Array[int] = []
	for b in bm.buildings():
		if b is MCP and b.state == Building.State.CONSTRUCTED:
			if b.player_owner not in alive:
				alive.append(b.player_owner)
	if _game_over:
		return
	if alive.size() == 1:
		_game_over = true
		rpc("rpc_game_over", alive[0])

@rpc("authority", "call_local", "reliable")
func rpc_game_over(winner: int) -> void:
	if _game_over_phase > 0:
		return
	_game_over = true
	_game_over_winner = winner
	_game_over_phase = 1
	_game_over_timer = 0.0
	# Stable backdrop behind the banner: snap FPS players back to the RTS camera
	# (no-op when already overhead / spectator) and lock them out of re-entering
	# FPS while the banner is up.
	Global.VM.exit_fps_immediate()
	Global.VM.fps_locked = true
	var banner := _victory_banner()
	if banner and banner.has_method("show_winner"):
		banner.show_winner(winner)

func _show_end_of_game_stats() -> void:
	var win := get_tree().get_first_node_in_group("statistics_window")
	if win and win.has_method("open_end_of_game"):
		win.open_end_of_game()

func _victory_banner() -> Node:
	return get_tree().get_first_node_in_group("victory_banner")

# The host closed down (returned to the menu or crashed). If the game already
# ended, stay on the statistics screen and let the player dismiss it to return
# to the menu themselves; otherwise drop straight back to the menu. Guarded
# against re-entry while our own leave_game() teardown runs.
func _on_server_disconnected() -> void:
	if Global.network_manager == null:
		return
	if _game_over_phase > 0:
		return
	Global.leave_game()

func _broadcast_progress() -> void:
	var ready_status := _ready_peers.size()
	_set_overlay_progress(ready_status, _expected_clients)
	rpc("rpc_ready_progress", ready_status, _expected_clients)

@rpc("authority", "call_remote", "reliable")
func rpc_ready_progress(ready_status: int, expected: int) -> void:
	_set_overlay_progress(ready_status, expected)

func _set_overlay_progress(ready_status: int, expected: int) -> void:
	var overlay := _loading_overlay()
	if overlay and overlay.has_method("set_progress"):
		overlay.set_progress(ready_status, expected)

func _hide_loading_overlay() -> void:
	var overlay := _loading_overlay()
	if overlay:
		overlay.hide()

func _loading_overlay() -> Node:
	return get_tree().get_first_node_in_group("loading_overlay")


# --- Server: send ---

func _send_snapshot() -> void:
	var ud: Dictionary = Global.UM.unit_dictionary
	var bd: Dictionary = Global.BM.building_dictionary
	var data := PackedFloat32Array()
	data.append(bd.size())
	for b in bd.values():
		data.append(b.id)
		_pack_building(data, b)
	data.append(ud.size())
	for u in ud.values():
		data.append(u.id)
		data.append(u.type)
		_pack_unit(data, u)
	# Chunk the payload so no single unreliable packet exceeds the ENet MTU;
	# ENet would otherwise fragment it and every lost fragment would drop the
	# whole snapshot.
	_snapshot_seq += 1
	var total := maxi(1, int(ceil(float(data.size()) / SNAPSHOT_CHUNK_FLOATS)))
	for i in range(total):
		var start := i * SNAPSHOT_CHUNK_FLOATS
		var n := mini(SNAPSHOT_CHUNK_FLOATS, data.size() - start)
		rpc("rpc_apply_snapshot_chunk", _snapshot_seq, i, total, data.slice(start, start + n))

func _send_avatar_snapshot() -> void:
	var avatar := _get_avatar(Global.my_player_number)
	if not avatar:
		return
	if Global.VM.camera_status != Global.VM.CameraStatus.FPS:
		return
	var data := PackedFloat32Array()
	_pack_unit(data, avatar)
	rpc_id(1, "rpc_receive_avatar_snapshot", data)

func _pack_unit(data: PackedFloat32Array, u: Unit) -> void:
	if _pack_scratch.size() != SLOT_COUNT:
		_pack_scratch.resize(SLOT_COUNT)
	_pack_scratch.fill(0.0)
	var slots := _pack_scratch
	match u.type:
		UnitManager.Type.ZOOMBA:
			slots[0] = u.global_position.x
			slots[1] = u.global_position.y
			slots[2] = u.global_position.z
			slots[3] = u.global_rotation.y
			slots[4] = u.state
			slots[5] = u.health
			if u.zapper_node:
				slots[6] = 1.0 if u.zapper_node.visible else 0.0
				slots[7] = u.zapper_node.target_position.y
		UnitManager.Type.AVATAR:
			if u.fps_body_node:
				slots[0] = u.fps_body_node.global_position.x
				slots[1] = u.fps_body_node.global_position.y
				slots[2] = u.fps_body_node.global_position.z
				slots[3] = u.fps_body_node.global_rotation.y
			slots[4] = u.health
		UnitManager.Type.TANK:
			slots[0] = u.global_position.x
			slots[1] = u.global_position.y
			slots[2] = u.global_position.z
			slots[3] = u.global_rotation.y
			slots[4] = u.state
			slots[5] = u.health
		UnitManager.Type.AERIAL:
			slots[0] = u.global_position.x
			slots[1] = u.global_position.y
			slots[2] = u.global_position.z
			slots[3] = u.global_rotation.y
			slots[4] = u.state
			slots[5] = u.health
			slots[6] = float(u.mode)
		UnitManager.Type.VIRUS:
			slots[0] = u.global_position.x
			slots[1] = u.global_position.y
			slots[2] = u.global_position.z
			slots[3] = u.global_rotation.y
			slots[4] = u.state
			slots[5] = u.health
			slots[6] = 1.0 if u.cloaked else 0.0
	slots[8] = _encode_target(u.combat_target)
	slots[9] = float(u.combat_fire_event)
	data.append_array(_pack_scratch)

static func _encode_target(target: Variant) -> float:
	if target and is_instance_valid(target):
		if target is Unit:
			return float(target.id)
		elif target is Building:
			return -float(target.id)
	return 0.0

func _pack_building(data: PackedFloat32Array, b: Building) -> void:
	var slots: Array[float] = []
	slots.resize(SLOT_COUNT)
	slots[0] = b.state
	slots[1] = b.health
	slots[2] = b._construction_energy_spent
	slots[3] = b.max_health
	slots[4] = 1.0 if b._production_enabled else 0.0
	slots[5] = b._production_energy
	# Slots 6..9 are used per building type to carry the configurable settings
	# (ratio, enemy/building targets, patrol stance) so every peer can render
	# the building's terminal. Garage has no building targets; Nest no stance.
	match b.type:
		BuildingManager.Type.GARAGE:
			var g := b as Garage
			slots[6] = g.zoomba_tank_ratio
			slots[7] = _encode_enemy_targets(g._enemy_targets)
			slots[8] = 0.0
			slots[9] = float(g.patrol_stance)
		BuildingManager.Type.BEACON:
			var bc := b as Beacon
			slots[6] = bc.patrol_strike_ratio
			slots[7] = _encode_enemy_targets(bc._enemy_targets)
			slots[8] = _encode_building_targets(bc._building_targets)
			slots[9] = float(bc._patrol_stance)
		BuildingManager.Type.NEST:
			var n := b as Nest
			slots[6] = n._virus_tank_building_ratio
			slots[7] = _encode_enemy_targets(n._enemy_targets)
			slots[8] = _encode_building_targets(n._building_targets)
	slots[10] = _encode_infection_mask(b)
	slots[11] = b.channel_progress()
	slots[12] = b.infection_remaining_max()
	for s in slots:
		data.append(s)

# VIRUS infection attackers packed as a bitmask (bit n = player n+1), mirrored
# to every peer so the infection ring visual shows on all clients.
static func _encode_infection_mask(b: Building) -> float:
	var mask := 0
	for p in b.infections:
		var idx := int(p) - 1
		if idx >= 0 and idx < 4:
			mask |= 1 << idx
	return float(mask)

# Enemy targets are player numbers 1..4; pack them as a 4-bit mask (bit n = player n+1).
static func _encode_enemy_targets(targets: Array) -> float:
	var mask := 0
	for p in targets:
		var idx := int(p) - 1
		if idx >= 0 and idx < 4:
			mask |= 1 << idx
	return float(mask)

static func _decode_enemy_targets(mask: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(4):
		if mask & (1 << i):
			out.append(i + 1)
	return out

# Building targets are the 6 configurable types (see Config.ALL_BUILDING_TARGETS);
# pack each as a bit in a fixed order.
static func _encode_building_targets(targets: Array) -> float:
	var mask := 0
	for t in targets:
		match int(t):
			BuildingManager.Type.MCP_1: mask |= 1 << 0
			BuildingManager.Type.GEN: mask |= 1 << 1
			BuildingManager.Type.VAT: mask |= 1 << 2
			BuildingManager.Type.GARAGE: mask |= 1 << 3
			BuildingManager.Type.BEACON: mask |= 1 << 4
			BuildingManager.Type.NEST: mask |= 1 << 5
	return float(mask)

static func _decode_building_targets(mask: int) -> Array[BuildingManager.Type]:
	var out: Array[BuildingManager.Type] = []
	if mask & (1 << 0): out.append(BuildingManager.Type.MCP_1)
	if mask & (1 << 1): out.append(BuildingManager.Type.GEN)
	if mask & (1 << 2): out.append(BuildingManager.Type.VAT)
	if mask & (1 << 3): out.append(BuildingManager.Type.GARAGE)
	if mask & (1 << 4): out.append(BuildingManager.Type.BEACON)
	if mask & (1 << 5): out.append(BuildingManager.Type.NEST)
	return out

# --- Client: receive ---

@rpc("authority", "call_remote", "unreliable")
func rpc_apply_snapshot_chunk(seq: int, chunk_idx: int, total: int, data: PackedFloat32Array) -> void:
	var entry = _chunk_buffer.get(seq)
	if entry == null:
		entry = {"total": total, "chunks": {}}
		_chunk_buffer[seq] = entry
		# A lost chunk would leave a partial entry that never completes; cap the
		# buffer so stragglers can't accumulate.
		while _chunk_buffer.size() > CHUNK_BUFFER_MAX:
			var oldest := 1 << 62
			for s in _chunk_buffer:
				oldest = mini(oldest, s)
			_chunk_buffer.erase(oldest)
	entry["chunks"][chunk_idx] = data
	if entry["chunks"].size() < total:
		return
	_chunk_buffer.erase(seq)
	# A completed snapshot supersedes stragglers of older ones — parsing an old
	# snapshot now would inject a stale world state with a fresh timestamp.
	for s in _chunk_buffer.keys():
		if s < seq:
			_chunk_buffer.erase(s)
	var full := PackedFloat32Array()
	for i in range(total):
		full.append_array(entry["chunks"][i])
	_parse_snapshot(full)

func _parse_snapshot(data: PackedFloat32Array) -> void:
	var entry := {"time": Time.get_ticks_usec() / 1e6, "units": {}, "buildings": {}}
	var idx := 0
	var bcount := int(data[idx]); idx += 1
	for _i in range(bcount):
		var id_val := int(data[idx]); idx += 1
		var slots: Array[float] = []
		for _s in SLOT_COUNT:
			slots.append(data[idx]); idx += 1
		entry["buildings"][id_val] = {"slots": slots}
	var ucount := int(data[idx]); idx += 1
	for _i in range(ucount):
		var id_val := int(data[idx]); idx += 1
		var type_val := int(data[idx]); idx += 1
		var slots: Array[float] = []
		for _s in SLOT_COUNT:
			slots.append(data[idx]); idx += 1
		entry["units"][id_val] = {"type": type_val, "slots": slots}
	_snapshots.append(entry)
	if _snapshots.size() > MAX_SNAPSHOT_BUFFER:
		_snapshots.pop_front()

@rpc("any_peer", "call_remote", "unreliable")
func rpc_receive_avatar_snapshot(data: PackedFloat32Array) -> void:
	var caller := multiplayer.get_remote_sender_id()
	var srv = Global.network_manager.server
	if not srv:
		return
	var pnum = srv.peer_to_player.get(caller)
	if pnum == null:
		return
	var slots: Array[float] = []
	for i in SLOT_COUNT:
		slots.append(data[i])
	if not _avatar_snapshots.has(pnum):
		_avatar_snapshots[pnum] = []
	var snaps = _avatar_snapshots[pnum]
	snaps.append({"time": Time.get_ticks_usec() / 1e6, "slots": slots})
	if snaps.size() > MAX_SNAPSHOT_BUFFER:
		snaps.pop_front()

func clear_avatar_snapshots(pnum: int) -> void:
	_avatar_snapshots.erase(pnum)
	_avatar_cache.erase(pnum)

# --- Client: interpolation ---

func _interpolate() -> void:
	if _snapshots.is_empty():
		return

	var render_time := Time.get_ticks_usec() / 1e6 - INTERPOLATION_DELAY

	while _snapshots.size() >= 2 and _snapshots[1]["time"] < render_time:
		_snapshots.pop_front()

	var s0 = _snapshots[0]
	if _snapshots.size() >= 2 and s0["time"] <= render_time:
		var s1 = _snapshots[1]
		var interval: float = s1["time"] - s0["time"]
		if interval > 0:
			var t := clampf((render_time - s0["time"]) / interval, 0.0, 1.0)
			_apply_interpolated(s0, s1, t)
			return
	_apply_snapshot_entities(s0)

func _apply_interpolated(s0: Dictionary, s1: Dictionary, t: float) -> void:
	var ud: Dictionary = Global.UM.unit_dictionary
	for id_val in s1["units"]:
		var u = ud.get(id_val) as Unit
		if not u:
			continue
		var e1 = s1["units"][id_val]
		if u.type == UnitManager.Type.AVATAR and u.player_owner == Global.my_player_number:
			# Local avatar is client-authoritative for movement — only sync health.
			if (e1["type"] as UnitManager.Type) == UnitManager.Type.AVATAR:
				u.health = e1["slots"][4]
			continue
		var e0 = s0["units"].get(id_val)
		if e0:
			_apply_interpolated_unit(u, e0, e1, t, e1["type"])
		else:
			_apply_unit(u, e1["type"], e1["slots"])
	var bd: Dictionary = Global.BM.building_dictionary
	for id_val in s1["buildings"]:
		var b = bd.get(id_val) as Building
		if not b:
			continue
		var e1 = s1["buildings"][id_val]
		_apply_building(b, e1["slots"])

func _apply_interpolated_unit(u: Unit, e0: Dictionary, e1: Dictionary, t: float, type_val: int) -> void:
	if _interp_scratch.size() != SLOT_COUNT:
		_interp_scratch.resize(SLOT_COUNT)
	var slots := _interp_scratch
	match type_val:
		UnitManager.Type.ZOOMBA:
			slots[0] = lerpf(e0["slots"][0], e1["slots"][0], t)
			slots[1] = lerpf(e0["slots"][1], e1["slots"][1], t)
			slots[2] = lerpf(e0["slots"][2], e1["slots"][2], t)
			slots[3] = _lerp_angle(e0["slots"][3], e1["slots"][3], t)
			for i in 6:
				slots[4 + i] = e1["slots"][4 + i]
		UnitManager.Type.AVATAR:
			slots[0] = lerpf(e0["slots"][0], e1["slots"][0], t)
			slots[1] = lerpf(e0["slots"][1], e1["slots"][1], t)
			slots[2] = lerpf(e0["slots"][2], e1["slots"][2], t)
			slots[3] = _lerp_angle(e0["slots"][3], e1["slots"][3], t)
			for i in 6:
				slots[4 + i] = e1["slots"][4 + i]
		UnitManager.Type.TANK:
			slots[0] = lerpf(e0["slots"][0], e1["slots"][0], t)
			slots[1] = lerpf(e0["slots"][1], e1["slots"][1], t)
			slots[2] = lerpf(e0["slots"][2], e1["slots"][2], t)
			slots[3] = _lerp_angle(e0["slots"][3], e1["slots"][3], t)
			for i in 6:
				slots[4 + i] = e1["slots"][4 + i]
		UnitManager.Type.AERIAL:
			slots[0] = lerpf(e0["slots"][0], e1["slots"][0], t)
			slots[1] = lerpf(e0["slots"][1], e1["slots"][1], t)
			slots[2] = lerpf(e0["slots"][2], e1["slots"][2], t)
			slots[3] = _lerp_angle(e0["slots"][3], e1["slots"][3], t)
			for i in 6:
				slots[4 + i] = e1["slots"][4 + i]
		UnitManager.Type.VIRUS:
			slots[0] = lerpf(e0["slots"][0], e1["slots"][0], t)
			slots[1] = lerpf(e0["slots"][1], e1["slots"][1], t)
			slots[2] = lerpf(e0["slots"][2], e1["slots"][2], t)
			slots[3] = _lerp_angle(e0["slots"][3], e1["slots"][3], t)
			for i in 6:
				slots[4 + i] = e1["slots"][4 + i]
	_apply_unit(u, type_val, slots)

func _apply_snapshot_entities(snapshot: Dictionary) -> void:
	var ud: Dictionary = Global.UM.unit_dictionary
	for id_val in snapshot["units"]:
		var u = ud.get(id_val) as Unit
		if not u:
			continue
		var e = snapshot["units"][id_val]
		var type_val := e["type"] as UnitManager.Type
		if u.type == UnitManager.Type.AVATAR and u.player_owner == Global.my_player_number:
			# Local avatar is client-authoritative for movement — only sync health.
			if type_val == UnitManager.Type.AVATAR:
				u.health = e["slots"][4]
			continue
		_apply_unit(u, type_val, e["slots"])
	var bd: Dictionary = Global.BM.building_dictionary
	for id_val in snapshot["buildings"]:
		var b = bd.get(id_val) as Building
		if not b:
			continue
		var e = snapshot["buildings"][id_val]
		_apply_building(b, e["slots"])

func _apply_unit(u: Unit, type_val: UnitManager.Type, slots: Array) -> void:
	if not u:
		return
	assert(u.type == type_val, "GameManager: unit type mismatch " + str(u.type) + " != " + str(type_val))
	match type_val:
		UnitManager.Type.ZOOMBA:
			u.global_position = Vector3(slots[0], slots[1], slots[2])
			u.rotation.y = slots[3]
			u.state = slots[4]
			u.health = slots[5]
			if u.zapper_node:
				u.zapper_node.visible = slots[6] > 0.5
				u.zapper_node.target_position.y = slots[7]
		UnitManager.Type.AVATAR:
			if u.fps_body_node:
				u.fps_body_node.global_position = Vector3(slots[0], slots[1], slots[2])
				u.fps_body_node.rotation.y = slots[3]
			u.health = slots[4]
		UnitManager.Type.TANK:
			u.global_position = Vector3(slots[0], slots[1], slots[2])
			u.rotation.y = slots[3]
			u.state = slots[4]
			u.health = slots[5]
		UnitManager.Type.AERIAL:
			u.global_position = Vector3(slots[0], slots[1], slots[2])
			u.rotation.y = slots[3]
			u.state = slots[4]
			u.health = slots[5]
			u.mode = int(slots[6])
			u.apply_mode_visual()
		UnitManager.Type.VIRUS:
			u.global_position = Vector3(slots[0], slots[1], slots[2])
			u.rotation.y = slots[3]
			u.state = slots[4]
			u.health = slots[5]
			u.cloaked = slots[6] > 0.5
	var tid = roundi(slots[8])
	if tid > 0:
		u.combat_target = Global.UM.unit_dictionary.get(tid)
	elif tid < 0:
		u.combat_target = Global.BM.building_dictionary.get(-tid)
	else:
		u.combat_target = null
	u.combat_fire_event = roundi(slots[9])

func _apply_building(b: Building, slots: Array) -> void:
	if not b:
		return
	# State is monotonic (BLUEPRINT -> UNDER_CONSTRUCTION -> CONSTRUCTED). Never
	# downgrade an already-constructed building: a late/unreordered unreliable
	# snapshot must not revert it, or recompute_aoe would drop its AoE claim.
	if b.state != Building.State.CONSTRUCTED or int(slots[0]) == Building.State.CONSTRUCTED:
		b.state = slots[0] as Building.State
	b.health = slots[1]
	b._construction_energy_spent = slots[2]
	b.max_health = slots[3]
	b._production_enabled = slots[4] > 0.5
	b._production_energy = slots[5]
	b.apply_infection_mask(int(slots[10]))
	b.apply_infection_progress(slots[11], slots[12])
	# Mirror the per-type settings packed by _pack_building so foreign building
	# terminals (spying) and owned building vars stay in sync with the server.
	match b.type:
		BuildingManager.Type.GARAGE:
			var g := b as Garage
			g.zoomba_tank_ratio = clampf(slots[6], 0.0, 1.0)
			g.set_enemy_targets(_decode_enemy_targets(int(slots[7])))
			g.set_patrol_stance(int(slots[9]))
		BuildingManager.Type.BEACON:
			var bc := b as Beacon
			bc.patrol_strike_ratio = clampf(slots[6], 0.0, 1.0)
			bc.set_enemy_targets(_decode_enemy_targets(int(slots[7])))
			bc.set_building_targets(_decode_building_targets(int(slots[8])))
			bc.set_patrol_stance(int(slots[9]))
		BuildingManager.Type.NEST:
			var n := b as Nest
			n.set_virus_tank_building_ratio(slots[6])
			n.set_enemy_targets(_decode_enemy_targets(int(slots[7])))
			n.set_building_targets(_decode_building_targets(int(slots[8])))

# Push freshly-synced building settings into the terminal controls of every
# building the current player does NOT own, so they can spy on the settings of
# enemy terminals. Runs after snapshot application on clients and at the same
# cadence on the server (which can also be a local player).
func _refresh_foreign_building_terminals() -> void:
	for b: Building in Global.BM.buildings():
		if b.player_owner == Global.my_player_number:
			continue
		b.refresh_terminal_ui()

# --- Server: avatar interpolation ---

func _interpolate_avatars() -> void:
	var render_time := Time.get_ticks_usec() / 1e6 - INTERPOLATION_DELAY
	for pnum in _avatar_snapshots:
		var snaps = _avatar_snapshots[pnum]
		if snaps.is_empty():
			continue
		var avatar = _get_avatar(pnum)
		if not avatar:
			continue
		# A player's avatar buffer isn't flushed on death, so it can still hold
		# snapshots from the previous incarnation. Applying those to the respawned
		# avatar would park its FPSBody at the old death spot — in range and LOS of
		# whoever killed it — letting them re-acquire and fire at long range.
		# Only trust snapshots captured after this avatar instance spawned.
		var spawn_time: float = avatar.server_spawn_time if avatar is Avatar else -INF
		var stale := 0
		while stale < snaps.size() and snaps[stale]["time"] < spawn_time:
			stale += 1
		if stale > 0:
			snaps = snaps.slice(stale)
			_avatar_snapshots[pnum] = snaps
		if snaps.is_empty():
			continue
		while snaps.size() >= 2 and snaps[1]["time"] < render_time:
			snaps.pop_front()
		var s0 = snaps[0]
		if snaps.size() >= 2 and s0["time"] <= render_time:
			var s1 = snaps[1]
			var interval: float = s1["time"] - s0["time"]
			if interval > 0:
				var t := clampf((render_time - s0["time"]) / interval, 0.0, 1.0)
				var e0 := {"type": UnitManager.Type.AVATAR, "slots": s0["slots"]}
				var e1 := {"type": UnitManager.Type.AVATAR, "slots": s1["slots"]}
				# Health is server-authoritative — don't let the client's snapshot
				# overwrite it (that would let the avatar cheat death).
				var health_before_instance1: float = avatar.health
				_apply_interpolated_unit(avatar, e0, e1, t, UnitManager.Type.AVATAR)
				avatar.health = health_before_instance1
				continue
		var health_before_instance2: float = avatar.health
		_apply_unit(avatar, UnitManager.Type.AVATAR, s0["slots"])
		avatar.health = health_before_instance2

# --- Utilities ---

static func _lerp_angle(from: float, to: float, t: float) -> float:
	var diff := fmod(to - from, TAU)
	if diff > PI:
		diff -= TAU
	elif diff < -PI:
		diff += TAU
	return from + diff * t
