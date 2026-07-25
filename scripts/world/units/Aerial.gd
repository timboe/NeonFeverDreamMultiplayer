extends Unit

class_name Aerial

enum Mode {PATROL, STRIKE}

var mode: Mode = Mode.PATROL
var lifetime: float = 120.0
var _lifetime_timer: float = 0.0

func _process(delta: float) -> void:
	super._process(delta)
	if not multiplayer.is_server():
		return
	if state == State.WORKING:
		return
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		get_node_or_null("/root/World/UnitManager").rpc("rpc_remove_unit", id)

func initialise(b: Building) -> void:
	super.initialise(b)
	type = UnitManager.Type.AERIAL
	_health_bar.position.y = 3.0
	health = Config.UNIT_MAX_HP.get(type, 100.0)
	add_to_group("aerial")
	add_to_group("aerial_player" + str(player_owner))
	if b is Beacon:
		mode = Mode.STRIKE if randf() > b.patrol_strike_ratio else Mode.PATROL
	position.y = 5.0 if mode == Mode.PATROL else 8.0
	var updated_mat = load("res://materials/player/player" + str(player_owner) + "_material.tres")
	$Body/CSGBody/CSGMesh.material = updated_mat
