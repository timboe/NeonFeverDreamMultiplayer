extends Unit

class_name Virus

var cloaked: bool = true
var _health_decay_rate: float = 1.25
var _decay_timer: float = 0.0
const DECAY_INTERVAL: float = 0.1

func _process(delta: float) -> void:
	super._process(delta)
	if not multiplayer.is_server():
		return
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
	$Body/CSGBody/CSGMesh.material = updated_mat
	_update_cloak_visual()

func _update_cloak_visual() -> void:
	var body = get_node_or_null("Body")
	if not body:
		return
	var mat = body.get_node_or_null("CSGBody/CSGMesh")
	if mat and mat is MeshInstance3D:
		var override_mat = mat.get_surface_override_material(0)
		if override_mat and override_mat is StandardMaterial3D:
			override_mat.albedo_color.a = 0.2 if cloaked else 1.0

func uncloak() -> void:
	cloaked = false
	_update_cloak_visual()

func recloak() -> void:
	cloaked = true
	_update_cloak_visual()
