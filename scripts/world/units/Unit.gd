extends Node3D

class_name Unit

const QUICK_ROTATE_TIME := 0.2
const SPAWN_TIME := 2.0
const SCRAM: int = 10

# --- Identity ---

var id: int # My ID within the UnitManager
var type: UnitManager.Type # My type
var building: Building # Building which spawned me (designates owner)

# --- State machine ---

enum State {IDLE, PATHING, WORKING}

var state: State = State.IDLE
var job: Dictionary = {}
var health: float = 100.0
var scram_count: int = 0

# --- Pathfinding ---

var path: PackedInt64Array = []
var progress: int

# --- Location ---

var location: TileElement
var previous_location: TileElement
var move_tween: Tween

# --- Rotation ---

var quat_from: Quaternion
var quat_to: Quaternion

# --- UI ---

var _health_bar: HealthBar3D

# --- Lifecycle ---

func initialise(b: Building) -> void:
	building = b
	location = b.location
	global_transform.origin = building.find_unit_spawn_location()
	add_to_group("unit")
	add_to_group("unit_player" + str(b.player_owner))
	position.y = -1 # hide
	_health_bar = preload("res://scripts/ui/HealthBar3D.gd").new()
	_health_bar.position.y = 2.5
	add_child(_health_bar)
	_health_bar.set_bar_size(1.6, 0.2)
	# Following animates the unit in and starts the callback loop.
	# This all happens only the server.
	if not multiplayer.is_server():
		return
	var tw = create_tween()
	tw.tween_property(self, "position:y", 0, SPAWN_TIME)
	tw.tween_callback(idle_callback)

func _process(_delta: float) -> void:
	if _health_bar:
		_health_bar.set_health(health, Config.UNIT_MAX_HP.get(type, 100.0))

# --- Job assignment ---

func assign_job(new_job: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	assert(job.is_empty())
	assert(state == State.IDLE)
	assert(new_job["pnum"] == building.player_owner)
	state = State.PATHING
	job = new_job

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

	# Get possible ways out of this tile. Only wander on to AoE tiles
	var territory_check := building.player_owner if type in Config.HOME_TERRITORY_UNITS else 0
	var possible_destinations := location.get_access_tiles(territory_check)
	# If not possible to stay on owned tiles, then relax this
	if possible_destinations.size() == 0:
		possible_destinations = location.get_access_tiles()

	# Special considerations if scrambling, always head towards home
	if scram_count > 0:
		scram_count -= 1
		var lowest_dist := 9999
		var best_target = null
		var mcp = get_tree().get_first_node_in_group("mcp_player" + str(building.player_owner))
		var pm = get_node_or_null("/root/World/TileManager/PathingManager") as PathingManager
		for d in possible_destinations:
			var dist = pm.distance(d, mcp.location)
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
		assert(state == State.IDLE)
		return idle_callback()
	assert(state == State.PATHING)
	# Second - check our job is still valid
	if not check_job_still_valid():
		return job_finished()
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
	var pm = get_node_or_null("/root/World/TileManager/PathingManager") as PathingManager
	location = pm.get_tile(path[progress])
	progress += 1
	move(pathing_callback)

func check_job_still_valid() -> bool:
	if not multiplayer.is_server():
		return false
	if job.is_empty():
		return false
	if job["type"] == JobManager.Type.CONSTRUCT_BUILDING:
		var b = job["location"].building
		if not b or b.state != Building.State.BLUEPRINT:
			return false
	return true

func check_pathing_valid() -> bool:
	if not multiplayer.is_server():
		return false
	if path.size() == 0:
		var pm = get_node_or_null("/root/World/TileManager/PathingManager") as PathingManager
		for n in job["location"].get_access_tiles():
			var check_path = pm.pathfind(location, n)
			if path.size() == 0 or check_path.size() < path.size():
				path = check_path
				job["path_dest"] = n
		progress = 1 # 0 is our starting location
		if path.size() < 2:
			# path.size() == 1 means we're already on an access tile -- start_work will catch it
			if path.size() == 1 and job.has("path_dest") and job["path_dest"].id == location.id:
				return true
			return false # We were unable to path
	return true

# --- Working state ---

func start_work() -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.PATHING)
	state = State.WORKING
	quick_rotate()
	if has_node("Zapper"):
		$Zapper.visible = true
	match job["type"]:
		JobManager.Type.TOGGLE_TILE:
			if has_node("Zapper"):
				$Zapper.target_position.y = Cairo.UNIT
			job["location"].do_toggle_countdown(self)
		JobManager.Type.CONSTRUCT_BUILDING:
			if has_node("Zapper"):
				$Zapper.target_position.y = Cairo.UNIT
			var b = job["location"].building
			if b:
				b.start_construction(self)
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
	var jm = get_node_or_null("/root/World/JobManager") as JobManager
	jm.remove_job(job["id"]) # This then calls our remove_job() which handles idle_callback

# Job was removed - we could be in any state
func remove_job() -> void:
	if not multiplayer.is_server():
		return
	if state == State.WORKING:
		_cleanup_working_state()
	state = State.IDLE
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	move_tween = null
	job = {}
	idle_callback()

func _cleanup_working_state() -> void:
	if has_node("Zapper"):
		$Zapper.visible = false
	match job["type"]:
		JobManager.Type.TOGGLE_TILE:
			job["location"].cancel_toggle_countdown(self)
		JobManager.Type.CONSTRUCT_BUILDING:
			var b = job["location"].building
			if b and b.state == Building.State.UNDER_CONSTRUCTION:
				b.cancel_construction()

func abandon_job() -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.PATHING or state == State.WORKING)
	assert(not job.is_empty())
	if state == State.WORKING:
		_cleanup_working_state()
	state = State.IDLE
	var j_id = job["id"]
	job = {}
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	move_tween = null
	var jm = get_node_or_null("/root/World/JobManager")
	if jm:
		jm.abandon_job(j_id)
	idle_callback()

func scram() -> void:
	scram_count = SCRAM
	if state != State.IDLE:
		abandon_job()

# --- Movement ---

func move(callback: Callable) -> void:
	if not multiplayer.is_server():
		return
	setup_rotation(location, null if job.is_empty() else job["location"])
	var time: float = Config.UNIT_SPEED[type]
	if scram_count > 0:
		time *= 0.5
	elif state == State.IDLE:
		time *= 2.0
	move_tween = create_tween()
	move_tween.tween_method(quat_transform, 0.0, 1.0, time / 2.0)
	move_tween.parallel().tween_property(self, "position", location.pathing_centre, time)
	move_tween.parallel().tween_callback(callback).set_delay(time)

# --- Rotation ---

func quick_rotate() -> void:
	if not multiplayer.is_server():
		return
	if job["location"] == null:
		return
	setup_rotation(job["location"], null)
	create_tween().tween_method(quat_transform, 0.0, 1.0, QUICK_ROTATE_TIME)

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
	if look_at_from_target != null:
		# If final move, look towards where the job is
		var cache_origin = transform.origin
		transform.origin = target.pathing_centre
		look_at(look_at_from_target.pathing_centre, Vector3.UP)
		transform.origin = cache_origin
	else:
		look_at(target.pathing_centre, Vector3.UP)
	rotation.y -= PI / 2.0
	quat_to = Quaternion(transform.basis)
	transform.basis = cache_rot
