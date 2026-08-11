extends Node3D

class_name Unit

# --- Constants ---

const QUICK_ROTATE_TIME := 0.2
const SPAWN_TIME := 2.0
const SCRAM: int = 10
const REPAIR_INTERVAL := 0.05
const REPAIR_DELAY := 10.0

# --- Types ---

enum State {IDLE, PATHING, WORKING}

# --- Identity ---

var id: int # My ID within the UnitManager
var type: UnitManager.Type # My type
var player_owner: int # Player who owns me (copied from spawning building)
var orders: Dictionary # My orders. Received from building on spawn

# --- State machine ---

var state: State = State.IDLE
var job: Dictionary = {}
var health: float = 100.0
var scram_count: int = 0
var _repair_timer := 0.0
# Lazy-cached per-frame lookups (type is set by subclasses after initialise).
var _max_hp: float = -1.0
var _self_heals := false
var _heal_rate := 0.0

# --- Pathfinding ---

var path: PackedInt64Array = []
var progress: int
var location: TileElement
var previous_location: TileElement
var move_tween: Tween
var _rotate_tween: Tween
var _pathing_manager: PathingManager
var _move_target: Vector3 = Vector3.ZERO

# --- Rotation ---

var quat_from: Quaternion
var quat_to: Quaternion

# --- Combat ---

@onready var combat_manager = Global.CM
var combat_hold_tween: Tween
var combat_target: Variant = null
var combat_fire_event: int = 0
var combat_fire_timer: float = 0.0
var combat_burst_timer: float = 0.0
var combat_damage_tick_timer: float = 0.0
var weapon_node: Node3D
var muzzle_node: Node3D
var weapon_forward_local: Vector3 = Vector3.FORWARD

# --- Combat visuals ---

var _last_fire_event: int = 0
var _laser_timer: float = 0.0

# --- UI ---

var _health_bar: HealthBar3D

# --- Snapshot caches (set in initialise; read at 20 Hz by GameManager) ---
# Note: Avatar declares its own typed `fps_body` (CharacterBody3D) — the cache
# lives under a distinct name to avoid member shadowing.

var zapper_node: Node3D
var fps_body_node: Node3D
var _mcp: Building

# --- Queries ---

func get_mode() -> int:
	return -1

# --- Combat aiming ---

func update_weapon_aim(delta: float) -> bool:
	if not weapon_node or not combat_target or not is_instance_valid(combat_target):
		return false
	var target_pos = combat_manager.combat_target_position(combat_target)
	var dir = target_pos - weapon_node.global_position
	if dir.length_squared() < 0.0001:
		return false
	dir = dir.normalized()
	var parent = weapon_node.get_parent_node_3d()
	if not parent:
		return false
	var parent_basis = parent.global_transform.basis
	var look_basis = Basis.looking_at(dir, Vector3.UP)
	var local_align = Basis.looking_at(weapon_forward_local, Vector3.RIGHT)
	var desired_global = look_basis * local_align.transposed()
	var desired_local_basis = parent_basis.inverse() * desired_global
	var desired_quat = Quaternion(desired_local_basis.orthonormalized())
	var current_quat = weapon_node.quaternion
	var dot = current_quat.dot(desired_quat)
	if dot < 0.0:
		desired_quat = -desired_quat
	var angle = acos(clampf(abs(dot), -1.0, 1.0))
	var max_angle = Config.WEAPON_TURN_SPEED * delta
	var t = 1.0 if angle <= 0.0001 else min(1.0, max_angle / angle)
	weapon_node.quaternion = current_quat.slerp(desired_quat, t)
	var forward_now = (weapon_node.global_transform.basis * weapon_forward_local).normalized()
	return forward_now.angle_to(dir) <= Config.WEAPON_ALIGN_THRESHOLD

func is_weapon_aligned() -> bool:
	if not weapon_node or not combat_target or not is_instance_valid(combat_target):
		return false
	var target_pos = combat_manager.combat_target_position(combat_target)
	var dir = target_pos - weapon_node.global_position
	if dir.length_squared() < 0.0001:
		return false
	dir = dir.normalized()
	var forward = (weapon_node.global_transform.basis * weapon_forward_local).normalized()
	return forward.angle_to(dir) <= Config.WEAPON_ALIGN_THRESHOLD

func _get_muzzle_global() -> Vector3:
	force_update_transform()
	if muzzle_node:
		muzzle_node.force_update_transform()
		return muzzle_node.global_position
	if weapon_node:
		weapon_node.force_update_transform()
		return weapon_node.global_position
	# Avatars live in their FPSBody child — the root stays at spawn, so aim/detect
	# from the body's real position (ref cached at spawn).
	if fps_body_node:
		fps_body_node.force_update_transform()
		return fps_body_node.global_position
	return global_position

# --- Combat visuals ---

func _update_combat_visuals(delta: float) -> void:
	while combat_fire_event > _last_fire_event:
		_last_fire_event += 1
		_on_fire_event()
	if _laser_timer > 0.0:
		_laser_timer -= delta
		if _laser_timer <= 0.0:
			_hide_beam()

func _on_fire_event() -> void:
	pass

func _hide_beam() -> void:
	pass

# --- Lifecycle ---

func initialise(b: Building) -> void:
	player_owner = b.player_owner
	# Copy orders at spawn — later building order changes (e.g. enemy-target
	# toggles) must not retroactively affect units already in the world.
	orders = b.orders.duplicate()
	var spawn_tile: TileElement = b.find_unit_spawn_location()
	location = spawn_tile
	global_transform.origin = spawn_tile.pathing_centre
	add_to_group("unit")
	add_to_group("unit_player" + str(b.player_owner))
	position.y = -1 # hide
	_health_bar = preload("res://scripts/ui/HealthBar3D.gd").new()
	_health_bar.position.y = 2.5
	add_child(_health_bar)
	_health_bar.set_bar_size(1.6, 0.2)
	# Cache pathing manager to avoid repeated absolute path lookups
	_pathing_manager = Global.PM
	# Cache node refs read per snapshot (20 Hz) and the owning MCP for scram.
	zapper_node = get_node_or_null("Zapper")
	fps_body_node = get_node_or_null("FPSBody") as Node3D
	_mcp = get_tree().get_first_node_in_group("mcp_player" + str(player_owner)) as Building
	# Following animates the unit in and starts the callback loop.
	# This all happens only the server.
	if not multiplayer.is_server():
		return
	move_tween = create_tween()
	move_tween.tween_property(self, "position:y", _move_target.y, SPAWN_TIME)
	move_tween.tween_callback(idle_callback)

func _process(delta: float) -> void:
	if _max_hp < 0.0:
		_max_hp = Config.UNIT_MAX_HP.get(type, 100.0)
		_self_heals = type in Config.SELF_HEALING_UNITS
		_heal_rate = Config.SELF_HEAL_RATE.get(type, 0.0)
	if _health_bar:
		_health_bar.set_health(health, _max_hp)

	update_weapon_aim(delta)
	_update_combat_visuals(delta)

	# If under repair (on server)
	if multiplayer.is_server() and _self_heals and health < _max_hp:
		_repair_timer += delta
		while _repair_timer >= REPAIR_INTERVAL:
			_repair_timer -= REPAIR_INTERVAL
			health = minf(health + _heal_rate * REPAIR_INTERVAL, _max_hp)

# --- Job assignment ---

func assign_job(new_job: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	assert(job.is_empty())
	assert(state == State.IDLE)
	assert(new_job["pnum"] == player_owner)
	state = State.PATHING
	job = new_job
	path.resize(0)
	progress = 0
	# Kick off pathing immediately if nothing is already moving us
	if move_tween == null or not move_tween.is_valid() or not move_tween.is_running():
		pathing_callback()

func _job_target_tile() -> TileElement:
	if job.is_empty():
		return null
	return Global.JM.target_tile(job["target"])

func _kill_combat_hold() -> void:
	if combat_hold_tween and combat_hold_tween.is_valid():
		combat_hold_tween.kill()
	combat_hold_tween = null

# Offence hook - overridden by units that generate their own jobs when idle.
func try_generate_offense_job() -> bool:
	return false

# Attack hook - called from start_work() for a JobManager.Type.ATTACK job.
# Overridden by units that stop-and-attach (VIRUS limpet). Default is a no-op.
func start_attack() -> void:
	pass

# Cleanup hook - called from _cleanup_working_state() when an ATTACK is
# interrupted (job removed/abandoned/displaced). Overridden to cancel the attach.
func cancel_attack() -> void:
	pass

# --- Idle state ---

func idle_callback() -> void:
	if not multiplayer.is_server():
		return
	if not job.is_empty(): # Do pathing for job
		assert(state == State.PATHING)
		assert(scram_count == 0)
		path.resize(0)
		pathing_callback()
		return

	# Offence hook - idle strike units generate their own combat job
	if try_generate_offense_job():
		return

	# Get possible ways out of this tile. Only wander on to AoE tiles
	var territory_check := player_owner if type in Config.HOME_TERRITORY_UNITS else 0
	var possible_destinations := location.get_access_tiles(territory_check)
	# If not possible to stay on owned tiles, then relax this
	if possible_destinations.size() == 0:
		possible_destinations = location.get_access_tiles()

	# Special considerations if scrambling, always head towards home
	if scram_count > 0:
		scram_count -= 1
		if _mcp and is_instance_valid(_mcp) and _pathing_manager:
			var lowest_dist := 9999
			var best_target = null
			for d in possible_destinations:
				var dist = _pathing_manager.distance(d, _mcp.location)
				if dist < lowest_dist:
					lowest_dist = dist
					best_target = d
			if best_target:
				possible_destinations.clear()
				possible_destinations.append(best_target)

	# Avoid backtracking, if possible
	var backtrack = possible_destinations.find(previous_location)
	if possible_destinations.size() > 1 and backtrack != -1:
		possible_destinations.remove_at(backtrack)

	# Check if we are a PATROL unit with LOCAL patrol
	if possible_destinations.size() > 1 \
		and not orders.is_empty() \
		and orders["order"] == JobManager.Orders.PATROL \
		and orders["stance"] == JobManager.Stance.HOLD \
		and is_instance_valid(orders["source"]):
		# Remove targets which are not under the building's AoE for player
		var local_options: Array[TileElement] = []
		for te in orders["source"]._aoe_tiles:
			if te in possible_destinations:
				local_options.append(te)
		if local_options.size() > 0:
			possible_destinations = local_options

	# Remember current tile, for the next backtrack check
	previous_location = location

	# Assign new location if available
	if possible_destinations.size() > 0:
		location = possible_destinations[Global.rand.randi() % possible_destinations.size()]

	# Go to new location. In extreme cases may be the same tile (possible_destinations.size() == 0)
	move(idle_callback)

# --- Pathing state ---

func pathing_callback() -> void:
	if not multiplayer.is_server():
		return
	# First - check we didn't scram while moving.
	if scram_count > 0:
		state = State.IDLE
		job = {}
		return idle_callback()
	assert(state == State.PATHING)
	# Second - check our job is still valid
	if not Global.JM.check_job_still_valid(job):
		return job_finished()
	# COMBAT_PERSUE jobs never enter WORKING - chase/orbit the target instead.
	# (ATTACK jobs are the exception: they path normally and stop-and-attach.)
	if job["type"] == JobManager.Type.COMBAT_PERSUE:
		return combat_pathing_callback()
	# Third check if at destination - path_dest is always a neighbour of location
	if job.has("path_dest") and job["path_dest"].id == location.id:
		return start_work()
	# Fourth, run pathing
	if not check_pathing_valid():
		return abandon_job()
	# Re-check: path_dest may have just been set to our current location (unit already adjacent)
	if job.has("path_dest") and job["path_dest"].id == location.id:
		return start_work()
	# Fifth, move to next location
	assert(progress < path.size())
	location = _pathing_manager.get_tile(path[progress])
	progress += 1
	move(pathing_callback)

func check_pathing_valid() -> bool:
	if not multiplayer.is_server():
		return false
	# Validate remaining path nodes are still traversable
	if path.size() > 0:
		for i in range(progress, path.size()):
			var tile = _pathing_manager.get_tile(path[i])
			if tile.state != TileManager.State.LOWERED:
				path.resize(0)
				break
	if path.size() == 0:
		var target_tile := _job_target_tile()
		if target_tile == null:
			return false
		for n in target_tile.get_access_tiles():
			var check_path = _pathing_manager.pathfind(location, n)
			if check_path.size() > 0 and (path.size() == 0 or check_path.size() < path.size()):
				path = check_path
				job["path_dest"] = n
		progress = 1 # 0 is our starting location
		if path.size() < 2:
			# path.size() == 1 means we're already on an access tile -- start_work will catch it
			if path.size() == 1 and job.has("path_dest") and job["path_dest"].id == location.id:
				return true
			return false # We were unable to path
	return true

# --- Combat state (no WORKING - path to the target, keep moving in its vicinity) ---

func combat_pathing_callback() -> void:
	if not multiplayer.is_server():
		return
	if combat_hold_tween and combat_hold_tween.is_valid():
		combat_hold_tween.kill()
		combat_hold_tween = null
	if job.is_empty() or job["type"] != JobManager.Type.COMBAT_PERSUE:
		return
	# First - check we didn't scram while moving.
	if scram_count > 0:
		state = State.IDLE
		job = {}
		return idle_callback()
	assert(state == State.PATHING)
	# Second - check our job is still valid
	if not Global.JM.check_job_still_valid(job):
		return job_finished()
	# Third - pick the next tile: orbit when adjacent, chase otherwise
	var dest: TileElement = combat_next_tile()
	if dest == null:
		return abandon_job()
	previous_location = location
	if dest == location:
		# No reachable alternative - hold adjacent and re-check shortly
		combat_hold_tween = create_tween()
		combat_hold_tween.tween_callback(combat_pathing_callback).set_delay(0.5)
		return
	location = dest
	move(combat_pathing_callback)

func combat_next_tile() -> TileElement:
	if not multiplayer.is_server():
		return null
	var target_tile: TileElement = Global.JM.target_tile(job["target"])
	if target_tile == null or not is_instance_valid(target_tile):
		return null
	var access: Array = target_tile.get_access_tiles()
	# Already adjacent to the target - keep moving in its vicinity
	if location in access:
		# Orbit: step to an access tile that is adjacent to the current tile so
		# the unit moves tile-to-tile around the target — never a straight slide
		# across the grid to a far access tile.
		var options: Array = []
		for t in access:
			if t != location and t != previous_location and t in location.neighbours:
				options.append(t)
		if options.is_empty():
			# Fall back to any lowered neighbour (still adjacent) to stay mobile
			options = location.get_access_tiles()
			if options.size() > 1:
				var me := options.find(location)
				if me != -1:
					options.remove_at(me)
				var back := options.find(previous_location)
				if options.size() > 1 and back != -1:
					options.remove_at(back)
		if options.is_empty():
			return location # Hold in place - no reachable alternatives
		var dest: TileElement = options[Global.rand.randi() % options.size()]
		job["path_dest"] = dest
		return dest
	# Path toward the target's access tiles (the target may have moved)
	var best_path: PackedInt64Array = []
	var best_dest: TileElement = null
	for n in access:
		var check_path := _pathing_manager.pathfind(location, n)
		if check_path.size() > 0 and (best_path.size() == 0 or check_path.size() < best_path.size()):
			best_path = check_path
			best_dest = n
	if best_path.size() < 2:
		return null # Unable to reach the target
	job["path_dest"] = best_dest
	progress = 1
	return _pathing_manager.get_tile(best_path[1])

# --- Working state ---

func start_work() -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.PATHING)
	state = State.WORKING
	quick_rotate()
	if has_node("Zapper"):
		$Zapper.visible = true
		$Zapper.target_position.y = Cairo.UNIT
	match job["type"]:
		JobManager.Type.TOGGLE_TILE:
			job["target"].do_toggle_countdown(self)
		JobManager.Type.CONSTRUCT_BUILDING:
			job["target"].building.start_construction(self)
		JobManager.Type.REPAIR_BUILDING:
			job["target"].building.start_repair(self)
		JobManager.Type.CONSUME_ZOOMBA:
			_consume_for_tank()
		JobManager.Type.ATTACK:
			start_attack()
		_:
			push_error("Unit.start_work: unknown job type ", job["type"])
			assert(false)

# --- Job completion ---

func job_finished() -> void:
	if not multiplayer.is_server():
		return
	if job.is_empty():
		return
	if has_node("Zapper"):
		$Zapper.visible = false
	state = State.IDLE
	Global.JM.remove_job(job["id"]) # This then calls our remove_job() which handles idle_callback

# Job was removed - we could be in any state
func remove_job() -> void:
	if not multiplayer.is_server():
		return
	if state == State.WORKING:
		_cleanup_working_state()
	state = State.IDLE
	_kill_combat_hold()
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	move_tween = null
	job = {}
	idle_callback()

func _cleanup_working_state() -> void:
	if has_node("Zapper"):
		$Zapper.visible = false
	if _rotate_tween and _rotate_tween.is_valid():
		_rotate_tween.kill()
		_rotate_tween = null
	match job["type"]:
		JobManager.Type.TOGGLE_TILE:
			job["target"].cancel_toggle_countdown(player_owner)
		JobManager.Type.CONSTRUCT_BUILDING:
			var b = job["target"].building
			if b and b.state == Building.State.UNDER_CONSTRUCTION:
				b.cancel_construction()
		JobManager.Type.ATTACK:
			cancel_attack()

func abandon_job() -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.PATHING or state == State.WORKING)
	assert(not job.is_empty())
	if state == State.WORKING:
		_cleanup_working_state()
	state = State.IDLE
	_kill_combat_hold()
	var j_id = job["id"]
	job = {}
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	move_tween = null
	Global.JM.abandon_job(j_id)
	idle_callback()

func scram() -> void:
	scram_count = SCRAM
	if state != State.IDLE:
		abandon_job()

func _consume_for_tank() -> void:
	if not multiplayer.is_server():
		return
	var garage = job["target"].building
	if not garage or not is_instance_valid(garage):
		job_finished()
		return
	# Spawn TANK at the garage
	var uid: int = Global.UM.next_unit_id()
	Global.UM.rpc("rpc_spawn_unit", uid, UnitManager.Type.TANK, garage.id)
	# Mark the consume job as completed before the zoomba is removed,
	# otherwise rpc_remove_unit will see the active job and abandon it.
	job_finished()
	# Remove this zoomba
	Global.UM.rpc("rpc_remove_unit", id)

# --- Movement ---

func move(callback: Callable) -> void:
	if not multiplayer.is_server():
		return
	setup_rotation(location, null if job.is_empty() else _job_target_tile())
	var time: float = Config.UNIT_SPEED[type]
	if scram_count > 0:
		time *= 0.5
	elif state == State.IDLE:
		time *= 2.0
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	move_tween = create_tween()
	var current_y := position.y
	_move_target = location.pathing_centre
	_move_target.y = current_y
	if state == State.IDLE and type == UnitManager.Type.ZOOMBA:
		# Rotate first, then move — gives a deliberate turn-then-walk feel
		var rot_time := time / 4.0
		var move_time := time - rot_time
		move_tween.tween_method(quat_transform, 0.0, 1.0, rot_time)
		move_tween.tween_property(self, "position", _move_target, move_time)
		move_tween.tween_callback(callback)
	else:
		move_tween.tween_method(quat_transform, 0.0, 1.0, time / 2.0)
		move_tween.parallel().tween_property(self, "position", _move_target, time)
		move_tween.parallel().tween_callback(callback).set_delay(time)

# --- Rotation ---

func quick_rotate() -> void:
	if not multiplayer.is_server():
		return
	var target_tile := _job_target_tile()
	if target_tile == null:
		return
	setup_rotation(target_tile, null)
	if _rotate_tween and _rotate_tween.is_valid():
		_rotate_tween.kill()
	_rotate_tween = create_tween()
	_rotate_tween.tween_method(quat_transform, 0.0, 1.0, QUICK_ROTATE_TIME)

func quat_transform(amount: float) -> void:
	if not multiplayer.is_server():
		return
	var mid = quat_from.slerp(quat_to, amount)
	transform.basis = Basis(mid)

func setup_rotation(target: TileElement, look_at_from_target: TileElement) -> void:
	if not multiplayer.is_server():
		return
	quat_from = Quaternion(transform.basis)
	var cache_rot = transform.basis
	var target_pos: Vector3 = target.pathing_centre
	if transform.origin.is_equal_approx(target_pos):
		rotation.y = 0.0
		quat_to = Quaternion(transform.basis)
		transform.basis = cache_rot
		return
	if look_at_from_target != null:
		# If final move, look towards where the job is
		var cache_origin = transform.origin
		transform.origin = target_pos
		look_at(look_at_from_target.pathing_centre, Vector3.UP)
		transform.origin = cache_origin
	else:
		look_at(target_pos, Vector3.UP)
	rotation.y -= PI / 2.0
	quat_to = Quaternion(transform.basis)
	transform.basis = cache_rot

# --- Damage ---

func apply_damage(amount: float, delay: float = 0.0, attacker: Unit = null) -> void:
	if not multiplayer.is_server():
		return
	if delay > 0.0:
		var tween := create_tween()
		tween.tween_callback(apply_damage.bind(amount, 0.0, attacker)).set_delay(delay)
		return
	_apply_damage(amount, attacker)

func _apply_damage(damage: float, _attacker: Unit = null) -> void:
	Global.SM.record_damage_received(player_owner, damage)
	health -= damage
	_repair_timer = -REPAIR_DELAY
	if health <= 0:
		health = 0
		Global.UM.rpc("rpc_remove_unit", id)
		return
	# Scram when attacked (DESIGN): zoombas flee to the MCP under fire.
	if type == UnitManager.Type.ZOOMBA:
		scram()
