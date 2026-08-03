extends Unit

class_name Aerial

enum Mode {PATROL, STRIKE}

var mode: Mode = Mode.PATROL
var lifetime: float = 120.0
var _lifetime_timer: float = 0.0
var _lifetime_bar: HealthBar3D
var _projectile_delay := 0.0
var _idle_time := 0.0 # time spent jobless & idle (server) - prevents offense job thrash

func get_mode() -> int:
	return mode

func _process(delta: float) -> void:
	super._process(delta)
	if multiplayer.is_server():
		if state != State.WORKING:
			_lifetime_timer += delta
			if _lifetime_timer >= lifetime:
				Global.UM.rpc("rpc_remove_unit", id)
		_idle_time = (_idle_time + delta) if (state == State.IDLE and job.is_empty()) else 0.0
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
	# Update orders based on strike or patrol. Copy the chosen orders dict so
	# later building order changes don't retroactively affect already-spawned units.
	orders = (b.orders["strike"] if mode == Mode.STRIKE else b.orders["patrol"]).duplicate()
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

func update_projectile_delay() -> float:
	if not combat_target or not is_instance_valid(combat_target):
		_projectile_delay = 0.0
		return _projectile_delay
	var from = _get_muzzle_global()
	var to = combat_manager.combat_target_position(combat_target)
	var dist = from.distance_to(to)
	_projectile_delay = clampf((dist / Config.COMBAT_RANGE) * Config.PROJECTILE_MAX_FLIGHT_TIME, 0.016, Config.PROJECTILE_MAX_FLIGHT_TIME)
	return _projectile_delay

# --- Offence: strike units generate their own personal combat job when idle ---

func try_generate_offense_job() -> bool:
	if not multiplayer.is_server():
		return false
	if mode != Mode.STRIKE:
		return false
	if _idle_time < 1.0:
		return false
	var target = _choose_strike_building()
	if target == null:
		return false
	var jm = Global.JM
	if not jm:
		return false
	_idle_time = 0.0 # If the job is immediately abandoned, wait before re-targeting
	jm.add_job(player_owner, JobManager.Type.COMBAT, target, self, true) # personal, auto-assigned to self
	return true

func _choose_strike_building() -> Building:
	# Explicit enemy list only — no fallback to "everyone"; empty means no strikes.
	var enemies: Array = []
	for p in orders.get("enemy", []):
		if p != player_owner:
			enemies.append(p)
	if enemies.is_empty():
		return null
	var target_types: Array = orders.get("target", [])
	var priority: int = orders.get("priority", JobManager.Priority.NEAREST)
	var bm = Global.BM
	if not bm:
		return null
	var candidates: Array = []
	for b in bm.buildings():
		if b.player_owner not in enemies:
			continue
		if b.health <= 0:
			continue
		if not target_types.is_empty() and b.type not in target_types:
			continue
		candidates.append(b)
	if candidates.is_empty():
		return null
	if priority == JobManager.Priority.LOWEST_HP:
		var best: Building = candidates[0]
		for b in candidates:
			if b.health < best.health:
				best = b
		return best
	# NEAREST
	var best_n: Building = candidates[0]
	var best_dist := global_position.distance_squared_to(best_n.global_position)
	for b in candidates:
		var d := global_position.distance_squared_to(b.global_position)
		if d < best_dist:
			best_dist = d
			best_n = b
	return best_n

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
	var to = combat_manager.combat_target_position(combat_target)
	projectile.global_position = from
	var ph = get_node_or_null("/root/World/ProjectilesHolder")
	ph.add_child(projectile)
	# On the server, CombatManager primes _projectile_delay right before incrementing
	# combat_fire_event, so the cache is fresh here. Remote clients don't run
	# CombatManager, so they must compute a fresh flight time each spawn.
	var flight_time := _projectile_delay
	if not multiplayer.is_server() or flight_time <= 0.0:
		flight_time = update_projectile_delay()
	var target_node = combat_target # The unit might change target, but we don't change this projectile
	var last_pos = to
	var tween = projectile.create_tween()
	tween.tween_method(func(t):
		# Track the target's live position so that if it's destroyed mid-flight we
		# keep flying to its last-known position instead of snapping back to spawn.
		if is_instance_valid(target_node):
			var pos = combat_manager.combat_target_position(target_node)
			if pos != Vector3.ZERO:
				last_pos = pos
		projectile.global_position = from.lerp(last_pos, t)
	, 0.0, 1.0, flight_time)
	tween.tween_callback(projectile.queue_free)
	# Safety — free projectile if the tween gets killed early
	var timer = get_tree().create_timer(Config.PROJECTILE_MAX_FLIGHT_TIME * 2.0)
	timer.timeout.connect(func(): if is_instance_valid(projectile): projectile.queue_free(), CONNECT_ONE_SHOT)
