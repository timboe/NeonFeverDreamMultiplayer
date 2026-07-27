extends Unit

class_name Virus

var cloaked: bool = true
var _health_decay_rate: float = 1.25
var _decay_timer: float = 0.0
const DECAY_INTERVAL: float = 0.1

func _process(delta: float) -> void:
	super._process(delta)
	if multiplayer.is_server():
		if health > 0 and state != State.WORKING:
			_decay_timer += delta
			while _decay_timer >= DECAY_INTERVAL:
				_decay_timer -= DECAY_INTERVAL
				health -= _health_decay_rate * DECAY_INTERVAL
				if health <= 0:
					health = 0
					get_node_or_null("/root/World/UnitManager").rpc("rpc_remove_unit", id)
					return
	_update_cloak_visual()

func initialise(b: Building) -> void:
	super.initialise(b)
	type = UnitManager.Type.VIRUS
	_health_bar.position.y = 2.0
	health = Config.UNIT_MAX_HP.get(type, 100.0)
	add_to_group("virus")
	add_to_group("virus_player" + str(player_owner))
	var updated_mat = load("res://materials/player/player" + str(player_owner) + "_material.tres")
	$Body/CSG.set_surface_override_material(0, updated_mat)
	_update_cloak_visual()

func _update_cloak_visual() -> void:
	var csg = get_node_or_null("Body/CSG") as MeshInstance3D
	if not csg:
		return
	var mat = csg.get_surface_override_material(0)
	if not mat:
		mat = csg.mesh.surface_get_material(0) if csg.mesh else null
	if mat and mat is StandardMaterial3D:
		mat.albedo_color.a = 0.2 if cloaked else 1.0

func uncloak() -> void:
	cloaked = false
	_update_cloak_visual()

func recloak() -> void:
	cloaked = true
	_update_cloak_visual()
