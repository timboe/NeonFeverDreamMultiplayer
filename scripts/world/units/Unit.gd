extends Node3D

class_name Unit

# Class constants
const QUICK_ROTATE_TIME := 0.2
const SPAWN_TIME := 2.0

# Immutable properties
var id : int # My ID within the UnitManager
var type : UnitManager.Type # My type
var building : Building # Building which spawned me (designates owner)

# Mutabl properties
enum State {IDLE, PATHING, WORKING}
var state : State = State.IDLE
var job : Dictionary = {}
var health : float = 100.0

# Pathfinding variables
var path : PackedInt64Array = []
var progress : int

# Current (and previous) locations on the pathing grid
var location : TileElement
var previous_location : TileElement
var move_tween : Tween

# Used for rotation
var quat_from : Quaternion
var quat_to : Quaternion

var _health_bar : HealthBar3D

func initialise(b : Building):
	building = b
	location = b.location
	global_transform.origin = building.find_unit_spawn_location()
	add_to_group("unit")
	add_to_group("unit_player"+str(b.player_owner))
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

func _process(_delta):
	if _health_bar:
		_health_bar.set_health(health, Config.UNIT_MAX_HP.get(type, 100.0))

func assign_job(new_job : Dictionary):
	if not multiplayer.is_server():
		return
	assert(job.is_empty())
	assert(state == State.IDLE)
	assert(new_job["pnum"] == building.player_owner)
	state = State.PATHING
	job = new_job
	print("Unit ",self," assigned job ", job)

func idle_callback():
	if not multiplayer.is_server():
		return
	if not job.is_empty(): # Do pathing for job
		assert(state == State.PATHING)
		#assert(scram_count == 0)
		path.resize(0)
		pathing_callback()
		return
	
	# Get possible ways out of this tile. Only wander on to AoE tiles
	var territory_check := building.player_owner if type in Config.HOME_TERRITORY_UNITS else 0	
	var possible_destinations := location.get_access_tiles(territory_check)
	# If not possible to stay on owned tiles, the relax this
	if possible_destinations.size() == 0:
		possible_destinations = location.get_access_tiles()
			
	# Special consderations if scraming
	#if scram_count > 0:
		#scram_count -= 1
		#var enemy_tiles := []
		#for d in possible_destinations:
			#if d.player != player:
				#enemy_tiles.append(d)
		#if possible_destinations.size() - enemy_tiles.size() > 0: # If at lease one way out isn't to enemy land
			#for e in enemy_tiles:
				#var loc = possible_destinations.find( e )
				#possible_destinations.remove_at(loc)
				
	# Avoid backtracking, if possible
	var backtrack = possible_destinations.find(previous_location)
	if possible_destinations.size() > 1 and backtrack != -1:
		possible_destinations.remove_at(backtrack)
		
	# Remember current tile, for the next backtrack check
	previous_location = location
	
	# Assign new location if available
	if possible_destinations.size() > 0:
		location = possible_destinations[ Global.rand.randi() % possible_destinations.size() ]

	# Go to new location. In extreme cases may be the same tile (possible_destinations.size() == 0)
	move(idle_callback)
	
func pathing_callback():
	if not multiplayer.is_server():
		return
	# First - check we didn't scram while moving.
	# If we did then we want to redirect to the idle callback
	#if scram_count > 0:
		#assert(state == State.IDLE)
		#return idle_callback()
	assert(state == State.PATHING)
	# Second - check our job is stil valid
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
	location = pm.get_tile( path[progress] )
	progress += 1
	move(pathing_callback)
	
func start_work():
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
			print("UNKNOWN JOB TYPE")
			assert(false)

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
			# path.size() == 1 means we're already on an access tile — start_work will catch it
			if path.size() == 1 and job.has("path_dest") and job["path_dest"].id == location.id:
				return true
			return false # We were unable to path
	return true
		
# Remove the job as it is finished
func job_finished():
	if not multiplayer.is_server():
		return
	if job.is_empty():
		return
	state = State.IDLE
	var jm = get_node_or_null("/root/World/JobManager") as JobManager
	jm.remove_job(job["id"]) # This then calls our remove_job() which handles idle_callback

# Job was removed - we could be in any state
func remove_job():
	if not multiplayer.is_server():
		return
	if state == State.WORKING:
		match job["type"]:
			JobManager.Type.TOGGLE_TILE:
				job["location"].cancel_toggle_countdown(self)
			JobManager.Type.CONSTRUCT_BUILDING:
				var b = job["location"].building
				if b and b.state == Building.State.UNDER_CONSTRUCTION:
					b.cancel_construction()
					b._working_unit = null
	state = State.IDLE
	if has_node("Zapper"):
		$Zapper.visible = false
	job = {}
	if not move_tween or not move_tween.is_running():
		idle_callback()

func abandon_job():
	assert(state == State.PATHING or state == State.WORKING)
	assert(not job.is_empty())
	match state:
		State.PATHING:
			return abandon_job_while_pathing()
		State.WORKING:
			return abandon_job_while_working()

func abandon_job_while_pathing():
	state = State.IDLE
	var j_id = job["id"]
	print("ABANDONING JOB WHILE PATHING ", job)
	job = {}
	var jm = get_node_or_null("/root/World/JobManager")
	if jm:
		jm.abandon_job(j_id)
	if not move_tween or move_tween.is_running():
		idle_callback()
		
func abandon_job_while_working():
	if has_node("Zapper"):
		$Zapper.visible = false
	match job["type"]:
		JobManager.Type.TOGGLE_TILE:
			job["location"].cancel_toggle_countdown(self)
		JobManager.Type.CONSTRUCT_BUILDING:
			var b = job["location"].building
			if b and b.state == Building.State.UNDER_CONSTRUCTION:
				b.cancel_construction()
				b._working_unit = null
	state = State.IDLE
	var j_id = job["id"]
	print("ABANDONING JOB WHILE WORKIN ", id)
	job = {}
	var jm2 = get_node_or_null("/root/World/JobManager")
	if jm2:
		jm2.abandon_job(j_id)
	# If we abandoned while we were working - then we were waiting for the end-of
	# job callback which will now never come. Hence we now need to call idle_callback
	idle_callback()

func move(callback):
	if not multiplayer.is_server():
		return
	setup_rotation(location, null if job.is_empty() else job["location"])
	var time = Config.UNIT_SPEED[ type ] 
	#if scram_count > 0:
		#time *=  0.5
	if state == State.IDLE:
		time *= 2.0 
	# else - pathing, time *= 1.0
	move_tween = create_tween()
	move_tween.tween_method(quat_transform, 0.0, 1.0, time / 2.0)
	move_tween.parallel().tween_property(self, "position", location.pathing_centre, time)
	move_tween.parallel().tween_callback(callback).set_delay(time)

func quick_rotate():
	if not multiplayer.is_server():
		return
	if job["location"] == null:
		return
	setup_rotation(job["location"], null)
	create_tween().tween_method(quat_transform, 0.0, 1.0, QUICK_ROTATE_TIME)

func quat_transform(amount : float):
	if not multiplayer.is_server():
		return
	var mid = quat_from.slerp(quat_to, amount)
	transform.basis = Basis(mid)

func setup_rotation(target, look_at_from_target):
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
		# Note: Sometimes, if stuck, we path to our own tile
		#if transform.origin.distance_to( location.pathing_centre ) > 1e-3:
		look_at(target.pathing_centre, Vector3.UP)
	rotation.y -= PI/2.0
	quat_to = Quaternion(transform.basis)
	transform.basis = cache_rot
