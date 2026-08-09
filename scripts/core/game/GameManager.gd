extends Node3D

class_name GameManager

const SNAPSHOT_INTERVAL := 0.05
const JOB_TICK_INTERVAL := 1.0
const INTERPOLATION_DELAY := 0.075
const AVATAR_SEND_INTERVAL := 0.05
const SLOT_COUNT := 10
const MAX_SNAPSHOT_BUFFER := 4

var _snapshot_timer := 0.0
var _job_timer := 0.0
var _avatar_snapshot_timer := 0.0

var _snapshots: Array = []
var _avatar_snapshots: Dictionary = {}

# --- Game start gate ---

const READY_TIMEOUT: float = 15.0

var _server_ready: bool = false
var _world_ready: bool = false  # client: this peer has finished initialising World
var _expected_clients: int = 0
var _ready_peers: Dictionary = {}  # pnum -> true
var _start_timeout: float = 0.0

# --- Lifecycle ---

func _ready() -> void:
	Global.GM = self
	Global.game_started = false
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Deferred so it runs after every manager has finished _ready (incl. the
	# tile grid generation and MCP placement).
	call_deferred("_on_world_ready")

# --- Main loop ---

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		if Global.game_started:
			_avatar_snapshot_timer += delta
			while _avatar_snapshot_timer >= AVATAR_SEND_INTERVAL:
				_avatar_snapshot_timer -= AVATAR_SEND_INTERVAL
				_send_avatar_snapshot()
			_interpolate()
		return
	# Server
	if not Global.game_started:
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

func _broadcast_progress() -> void:
	var ready_status := _ready_peers.size()
	_set_overlay_progress(ready_status, _expected_clients)
	rpc("ready_progress", ready_status, _expected_clients)

@rpc("authority", "call_remote", "reliable")
func ready_progress(ready_status: int, expected: int) -> void:
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
	var data := PackedFloat64Array()
	data.append(bd.size())
	for b in bd.values():
		data.append(b.id)
		_pack_building(data, b)
	data.append(ud.size())
	for u in ud.values():
		data.append(u.id)
		data.append(u.type)
		_pack_unit(data, u)
	rpc("apply_snapshot", data)
	refresh_foreign_building_terminals()

func _send_avatar_snapshot() -> void:
	var avatar = get_tree().get_first_node_in_group("avatar_player" + str(Global.my_player_number))
	if not avatar:
		return
	var cam = Global.VM
	if cam and cam.camera_status != cam.CameraStatus.FPS:
		return
	var data := PackedFloat64Array()
	_pack_unit(data, avatar)
	rpc_id(1, "receive_avatar_snapshot", data)

func _pack_unit(data: PackedFloat64Array, u: Unit) -> void:
	var slots := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	match u.type:
		UnitManager.Type.ZOOMBA:
			slots[0] = u.global_position.x
			slots[1] = u.global_position.y
			slots[2] = u.global_position.z
			slots[3] = u.global_rotation.y
			slots[4] = u.state
			slots[5] = u.health
			var zapper = u.get_node_or_null("Zapper")
			if zapper:
				slots[6] = zapper.visible
				slots[7] = zapper.target_position.y
		UnitManager.Type.AVATAR:
			var body = u.get_node_or_null("FPSBody") as Node3D
			if body:
				slots[0] = body.global_position.x
				slots[1] = body.global_position.y
				slots[2] = body.global_position.z
				slots[3] = body.global_rotation.y
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
	for s in slots:
		data.append(s)

static func _encode_target(target) -> float:
	if target and is_instance_valid(target):
		if target is Unit:
			return float(target.id)
		elif target is Building:
			return -float(target.id)
	return 0.0

func _pack_building(data: PackedFloat64Array, b: Building) -> void:
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
	for s in slots:
		data.append(s)

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
func apply_snapshot(data: PackedFloat64Array) -> void:
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
func receive_avatar_snapshot(data: PackedFloat64Array) -> void:
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
	refresh_foreign_building_terminals()

func _apply_interpolated_unit(u: Unit, e0: Dictionary, e1: Dictionary, t: float, type_val: int) -> void:
	var slots: Array[float] = []
	slots.resize(SLOT_COUNT)
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
	refresh_foreign_building_terminals()

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
			var zapper = u.get_node_or_null("Zapper")
			if zapper:
				zapper.visible = slots[6]
				zapper.target_position.y = slots[7]
		UnitManager.Type.AVATAR:
			var body = u.get_node_or_null("FPSBody") as Node3D
			if body:
				body.global_position = Vector3(slots[0], slots[1], slots[2])
				body.rotation.y = slots[3]
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
func refresh_foreign_building_terminals() -> void:
	for b : Building in Global.BM.buildings() :
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
		var avatar = get_tree().get_first_node_in_group("avatar_player" + str(pnum))
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
