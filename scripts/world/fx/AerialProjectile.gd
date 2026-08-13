extends MeshInstance3D

class_name AerialProjectile

# --- State ---

var _from: Vector3 = Vector3.ZERO

func setup(from: Vector3) -> void:
	_from = from

# Flight step. The tween that calls this is created on this node (create_tween
# on self) and invokes our own method, so the callable can never outlive the
# projectile — an Aerial-side lambda would dangle once the shooter is freed
# mid-flight. The target is resolved per frame by ObjectID: a freed target
# degrades to null and the projectile keeps flying to its last-known position.
func _flight_step(t: float) -> void:
	var target_pos: Vector3 = get_meta("last_pos", Vector3.ZERO)
	var tn: Object = instance_from_id(get_meta("target_id", 0))
	if tn is Node and is_instance_valid(tn):
		var pos := Global.CM.combat_target_position(tn)
		if pos != Vector3.ZERO:
			target_pos = pos
			set_meta("last_pos", pos)
	global_position = _from.lerp(target_pos, t)
