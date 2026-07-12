extends Node3D

class_name GameManager

const SNAPSHOT_INTERVAL := 0.05
const JOB_TICK_INTERVAL := 1.0

var _snapshot_timer := 0.0
var _job_timer := 0.0

func _process(delta):
	if not multiplayer.is_server():
		return
	_snapshot_timer += delta
	_job_timer += delta
	while _snapshot_timer >= SNAPSHOT_INTERVAL:
		_snapshot_timer -= SNAPSHOT_INTERVAL
		_send_snapshot()
	while _job_timer >= JOB_TICK_INTERVAL:
		_job_timer -= JOB_TICK_INTERVAL
		%JobManager.assign_jobs()

func _send_snapshot():
	var units = %UnitManager.units()
	var data := PackedFloat64Array()
	data.append(units.size())
	for u in units:
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
	for s in slots:
		data.append(s)

@rpc("authority", "call_remote", "unreliable")
func apply_snapshot(data: PackedFloat64Array):
	var ud = %UnitManager.unit_dictionary
	var count = int(data[0])
	var idx = 1
	for _i in range(count):
		var id_val = int(data[idx]); idx += 1
		var type_val = int(data[idx]); idx += 1
		var slots: Array[float] = []
		for _s in 8:
			slots.append(data[idx]); idx += 1
		var u = ud.get(id_val) as Unit
		assert(u.type == type_val)
		if not u:
			continue
		match type_val:
			UnitManager.Type.ZOOMBA:
				u.global_position = Vector3(slots[0], slots[1], slots[2])
				u.rotation.y = slots[3]
				u.state = int(slots[4])
				u.health = slots[5]
