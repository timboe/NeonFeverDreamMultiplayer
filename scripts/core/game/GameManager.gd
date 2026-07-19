extends Node3D

class_name GameManager

const SNAPSHOT_INTERVAL := 0.05
const JOB_TICK_INTERVAL := 1.0
const INTERPOLATION_DELAY := 0.075
const AVATAR_SEND_INTERVAL := 0.05
const SLOT_COUNT := 8
const MAX_SNAPSHOT_BUFFER := 4

var _snapshot_timer := 0.0
var _job_timer := 0.0
var _avatar_snapshot_timer := 0.0

var _snapshots: Array = []
var _avatar_snapshots: Dictionary = {}

# --- Main loop ---

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		_avatar_snapshot_timer += delta
		while _avatar_snapshot_timer >= AVATAR_SEND_INTERVAL:
			_avatar_snapshot_timer -= AVATAR_SEND_INTERVAL
			_send_avatar_snapshot()
		_interpolate()
		return
	_snapshot_timer += delta
	_job_timer += delta
	while _snapshot_timer >= SNAPSHOT_INTERVAL:
		_snapshot_timer -= SNAPSHOT_INTERVAL
		_send_snapshot()
	_interpolate_avatars()
	while _job_timer >= JOB_TICK_INTERVAL:
		_job_timer -= JOB_TICK_INTERVAL
		%JobManager.assign_jobs()
		for b in %BuildingManager.buildings():
			b.check_work()

# --- Server: send ---

func _send_snapshot() -> void:
	var ud: Dictionary = %UnitManager.unit_dictionary
	var bd: Dictionary = %BuildingManager.building_dictionary
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

func _send_avatar_snapshot() -> void:
	var avatar = get_tree().get_first_node_in_group("avatar_player" + str(Global.my_player_number))
	if not avatar:
		return
	var cam = get_node_or_null("/root/World/CameraManager")
	if cam and cam.camera_status != cam.CameraStatus.FPS:
		return
	var data := PackedFloat64Array()
	_pack_unit(data, avatar)
	rpc_id(1, "receive_avatar_snapshot", data)

func _pack_unit(data: PackedFloat64Array, u: Unit) -> void:
	var slots := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
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
	for s in slots:
		data.append(s)

func _pack_building(data: PackedFloat64Array, b: Building) -> void:
	var slots := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	slots[0] = b.state
	slots[1] = b.health
	slots[2] = b._construction_energy_spent
	for s in slots:
		data.append(s)

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
	var ud: Dictionary = %UnitManager.unit_dictionary
	for id_val in s1["units"]:
		var u = ud.get(id_val) as Unit
		if not u:
			continue
		if u.type == UnitManager.Type.AVATAR and u.building and u.building.player_owner == Global.my_player_number:
			continue
		var e1 = s1["units"][id_val]
		var e0 = s0["units"].get(id_val)
		if e0:
			_apply_interpolated_unit(u, e0, e1, t, e1["type"])
		else:
			_apply_unit(u, e1["type"], e1["slots"])
	var bd: Dictionary = %BuildingManager.building_dictionary
	for id_val in s1["buildings"]:
		var b = bd.get(id_val) as Building
		if not b:
			continue
		var e1 = s1["buildings"][id_val]
		_apply_building(b, e1["slots"])

func _apply_interpolated_unit(u: Unit, e0: Dictionary, e1: Dictionary, t: float, type_val: int) -> void:
	var slots: Array[float] = []
	slots.resize(SLOT_COUNT)
	match type_val:
		UnitManager.Type.ZOOMBA:
			slots[0] = lerpf(e0["slots"][0], e1["slots"][0], t)
			slots[1] = lerpf(e0["slots"][1], e1["slots"][1], t)
			slots[2] = lerpf(e0["slots"][2], e1["slots"][2], t)
			slots[3] = _lerp_angle(e0["slots"][3], e1["slots"][3], t)
			for i in 4:
				slots[4 + i] = e1["slots"][4 + i]
		UnitManager.Type.AVATAR:
			slots[0] = lerpf(e0["slots"][0], e1["slots"][0], t)
			slots[1] = lerpf(e0["slots"][1], e1["slots"][1], t)
			slots[2] = lerpf(e0["slots"][2], e1["slots"][2], t)
			slots[3] = _lerp_angle(e0["slots"][3], e1["slots"][3], t)
			for i in 4:
				slots[4 + i] = e1["slots"][4 + i]
	_apply_unit(u, type_val, slots)

func _apply_snapshot_entities(snapshot: Dictionary) -> void:
	var ud: Dictionary = %UnitManager.unit_dictionary
	for id_val in snapshot["units"]:
		var u = ud.get(id_val) as Unit
		if not u:
			continue
		if u.type == UnitManager.Type.AVATAR and u.building and u.building.player_owner == Global.my_player_number:
			continue
		var e = snapshot["units"][id_val]
		_apply_unit(u, e["type"] as UnitManager.Type, e["slots"])
	var bd: Dictionary = %BuildingManager.building_dictionary
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

func _apply_building(b: Building, slots: Array) -> void:
	if not b:
		return
	b.state = slots[0] as Building.State
	b.health = slots[1]
	b._construction_energy_spent = slots[2]

# --- Server: avatar interpolation ---

func _interpolate_avatars() -> void:
	var render_time := Time.get_ticks_usec() / 1e6 - INTERPOLATION_DELAY
	for pnum in _avatar_snapshots:
		var snaps = _avatar_snapshots[pnum]
		while snaps.size() >= 2 and snaps[1]["time"] < render_time:
			snaps.pop_front()
		if snaps.is_empty():
			continue
		var avatar = get_tree().get_first_node_in_group("avatar_player" + str(pnum))
		if not avatar:
			continue
		var s0 = snaps[0]
		if snaps.size() >= 2 and s0["time"] <= render_time:
			var s1 = snaps[1]
			var interval: float = s1["time"] - s0["time"]
			if interval > 0:
				var t := clampf((render_time - s0["time"]) / interval, 0.0, 1.0)
				var e0 := {"type": UnitManager.Type.AVATAR, "slots": s0["slots"]}
				var e1 := {"type": UnitManager.Type.AVATAR, "slots": s1["slots"]}
				_apply_interpolated_unit(avatar, e0, e1, t, UnitManager.Type.AVATAR)
				continue
		_apply_unit(avatar, UnitManager.Type.AVATAR, s0["slots"])

# --- Utilities ---

static func _lerp_angle(from: float, to: float, t: float) -> float:
	var diff := fmod(to - from, TAU)
	if diff > PI:
		diff -= TAU
	elif diff < -PI:
		diff += TAU
	return from + diff * t
