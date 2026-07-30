extends Unit

class_name Aerial

enum Mode {PATROL, STRIKE}

var mode: Mode = Mode.PATROL
var lifetime: float = 120.0
var _lifetime_timer: float = 0.0
var _lifetime_bar: HealthBar3D

func get_mode() -> int:
	return mode

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
	# Weapon setup
	weapon_node = $Body/Gun
	muzzle_node = $Body/Gun/Muzzle
	weapon_forward_local = Vector3.FORWARD

func _on_fire_event() -> void:
	_spawn_projectile()

func _spawn_projectile() -> void:
	if not combat_target or not is_instance_valid(combat_target):
		return
	var projectile = MeshInstance3D.new()
	projectile.mesh = SphereMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.6, 1.0)
	mat.emission_energy_multiplier = 10.0
	projectile.material_override = mat
	projectile.scale = Vector3(0.2, 0.2, 0.2)
	var from = _get_muzzle_global()
	var to = _combat_target_position()
	projectile.global_position = from
	var world = get_node_or_null("/root/World")
	if world:
		world.add_child(projectile)
	else:
		get_parent().add_child(projectile)
	var dist = from.distance_to(to)
	var flight_time = (dist / Config.COMBAT_RANGE) * Config.PROJECTILE_MAX_FLIGHT_TIME
	flight_time = clampf(flight_time, 0.016, Config.PROJECTILE_MAX_FLIGHT_TIME)
	var tween = projectile.create_tween()
	tween.tween_property(projectile, "global_position", to, flight_time)
	tween.tween_callback(projectile.queue_free)
	# Safety — free projectile if the tween gets killed early
	var timer = get_tree().create_timer(Config.PROJECTILE_MAX_FLIGHT_TIME * 2.0)
	timer.timeout.connect(func(): if is_instance_valid(projectile): projectile.queue_free(), CONNECT_ONE_SHOT)
