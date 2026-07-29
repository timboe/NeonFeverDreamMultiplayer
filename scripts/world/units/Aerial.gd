extends Unit

class_name Aerial

enum Mode {PATROL, STRIKE}

var mode: Mode = Mode.PATROL
var lifetime: float = 120.0
var _lifetime_timer: float = 0.0
var _lifetime_bar: HealthBar3D

func _process(delta: float) -> void:
	super._process(delta)
	if multiplayer.is_server():
		if state != State.WORKING:
			_lifetime_timer += delta
			if _lifetime_timer >= lifetime:
				get_node_or_null("/root/World/UnitManager").rpc("rpc_remove_unit", id)
	if _lifetime_bar:
		_lifetime_bar.set_health(lifetime - _lifetime_timer, lifetime)

func initialise(b: Building) -> void:
	var spawn_tile: TileElement = b.find_unit_spawn_location()
	super.initialise(b)
	type = UnitManager.Type.AERIAL
	_health_bar.position.y = 3.0
	health = Config.UNIT_MAX_HP.get(type, 100.0)
	# Lifetime bar below health bar
	_lifetime_bar = preload("res://scripts/ui/HealthBar3D.gd").new()
	_lifetime_bar.position.y = 2.6
	add_child(_lifetime_bar)
	_lifetime_bar.set_bar_size(1.6, 0.15)
	_lifetime_bar.set_fill_color(Color(0.3, 0.5, 0.9, 0.95))
	add_to_group("aerial")
	add_to_group("aerial_player" + str(player_owner))
	# Assign strike or patrol
	if b is Beacon:
		mode = Mode.STRIKE if randf() > b.patrol_strike_ratio else Mode.PATROL
	_move_target.y = 10.0 if mode == Mode.PATROL else 16.0
	# Update orders based on strike or patrol
	orders = b.orders["strike"] if mode == Mode.STRIKE else b.orders["patrol"] 
	var updated_mat = load("res://materials/player/player" + str(player_owner) + "_material.tres")
	$Body/CSG.set_surface_override_material(0, updated_mat)
	# Override the base class spawn tween — fly from building to initial tile at constant height
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	var origin := Vector3(b.location.pathing_centre.x, _move_target.y, b.location.pathing_centre.z)
	position = origin
	var dest := Vector3(spawn_tile.pathing_centre.x, _move_target.y, spawn_tile.pathing_centre.z)
	move_tween = create_tween()
	move_tween.tween_property(self, "position", dest, SPAWN_TIME)
	move_tween.tween_callback(idle_callback)
