extends Node3D

class_name GameManager

const SNAPSHOT_INTERVAL := 0.05
const JOB_TICK_INTERVAL := 1.0
const INTERPOLATION_DELAY := 0.075

var _snapshot_timer := 0.0
var _job_timer := 0.0

var _snapshots: Array = []

func _process(delta):
	if not multiplayer.is_server():
		_interpolate()
		return
	_snapshot_timer += delta
	_job_timer += delta
	while _snapshot_timer >= SNAPSHOT_INTERVAL:
		_snapshot_timer -= SNAPSHOT_INTERVAL
		_send_snapshot()
	while _job_timer >= JOB_TICK_INTERVAL:
		_job_timer -= JOB_TICK_INTERVAL
		%JobManager.assign_jobs()
		for b in %BuildingManager.buildings():
			b.check_work()

func _send_snapshot():
	var ud = %UnitManager.unit_dictionary
	var data := PackedFloat64Array()
	data.append(ud.size())
	for u in ud.values():
		data.append(u.id)
		data.append(u.type)
		_pack_unit(data, u)
	rpc("apply_snapshot", data)

func _pack_unit(data: PackedFloat64Array, u: Unit):
	var slots := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	match u.type:
		UnitManager.Type.ZOOMBA:
			slots[0] = u.global_position.x
			slots[1] = u.global_position.y
			slots[2] = u.global_position.z
			slots[3] = u.global_rotation.y
			slots[4] = u.state
			slots[5] = u.health
			slots[6] = u.get_node("Zapper").visible
	for s in slots:
		data.append(s)

@rpc("authority", "call_remote", "unreliable")
func apply_snapshot(data: PackedFloat64Array):
	var entry := {"time": Time.get_ticks_usec() / 1e6, "units": {}}
	var count = int(data[0])
	var idx = 1
	for _i in range(count):
		var id_val = int(data[idx]); idx += 1
		var type_val = int(data[idx]); idx += 1
		var slots: Array[float] = []
		for _s in 8:
			slots.append(data[idx]); idx += 1
		entry["units"][id_val] = {"type": type_val, "slots": slots}
	_snapshots.append(entry)
	if _snapshots.size() > 4:
		_snapshots.pop_front()

func _interpolate():
	if _snapshots.is_empty():
		return

	var render_time = Time.get_ticks_usec() / 1e6 - INTERPOLATION_DELAY

	while _snapshots.size() >= 2 and _snapshots[1]["time"] < render_time:
		_snapshots.pop_front()

	var s0 = _snapshots[0]
	if _snapshots.size() >= 2 and s0["time"] <= render_time:
		var s1 = _snapshots[1]
		var interval = s1["time"] - s0["time"]
		if interval > 0:
			var t = clamp((render_time - s0["time"]) / interval, 0.0, 1.0)
			_apply_interpolated(s0, s1, t)
			return
	_apply_snapshot_units(s0)

func _apply_interpolated(s0: Dictionary, s1: Dictionary, t: float):
	var ud = %UnitManager.unit_dictionary
	for id_val in s1["units"]:
		var u = ud.get(id_val) as Unit
		if not u:
			continue
		var e1 = s1["units"][id_val]
		var e0 = s0["units"].get(id_val)
		if e0:
			_apply_interpolated_unit(u, e0, e1, t, e1["type"])
		else:
			_apply_unit(u, e1["type"], e1["slots"])

func _apply_interpolated_unit(u: Unit, e0: Dictionary, e1: Dictionary, t: float, type_val: int):
	var slots: Array[float] = []
	slots.resize(8)
	match type_val:
		UnitManager.Type.ZOOMBA:
			slots[0] = lerpf(e0["slots"][0], e1["slots"][0], t)
			slots[1] = lerpf(e0["slots"][1], e1["slots"][1], t)
			slots[2] = lerpf(e0["slots"][2], e1["slots"][2], t)
			slots[3] = _lerp_angle(e0["slots"][3], e1["slots"][3], t)
			for i in 4:
				slots[4 + i] = e1["slots"][4 + i]
	_apply_unit(u, type_val, slots)

func _apply_snapshot_units(snapshot: Dictionary):
	var ud = %UnitManager.unit_dictionary
	for id_val in snapshot["units"]:
		var e = snapshot["units"][id_val]
		_apply_unit(ud.get(id_val) as Unit, e["type"] as UnitManager.Type, e["slots"])

func _apply_unit(u: Unit, type_val: UnitManager.Type, slots: Array):
	if not u:
		return
	assert(u.type == type_val, "GameManager: unit type mismatch " + str(u.type) + " != " + str(type_val))
	match type_val:
		UnitManager.Type.ZOOMBA:
			u.global_position = Vector3(slots[0], slots[1], slots[2])
			u.rotation.y = slots[3]
			u.state = int(slots[4])
			u.health = slots[5]
			u.get_node("Zapper").visible = slots[6]

static func _lerp_angle(from: float, to: float, t: float) -> float:
	var diff = fmod(to - from, TAU)
	if diff > PI:
		diff -= TAU
	elif diff < -PI:
		diff += TAU
	return from + diff * t
