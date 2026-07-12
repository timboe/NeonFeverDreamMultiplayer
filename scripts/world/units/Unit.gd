extends Node3D

class_name Unit

# Class constants
const QUICK_ROTATE_TIME := 0.2

# Immutable properties
var id : int # My ID within the UnitManager
var type : UnitManager.Type # My type
var building : Building # Building which spawned me (designates owner)

# Mutabl properties
enum State {IDLE, PATHING, WORKING}
var state : int = State.IDLE
var job : Dictionary = {}
var health : float = 100.0

# Pathfinding variables
var path : PackedInt64Array = []
var progress : int

# Current (and previous) locations on the pathing grid
var location : TileElement
var previous_location : TileElement

# Used for rotation
var quat_from : Quaternion
var quat_to : Quaternion

func initialise_base(b : Building, t : UnitManager.Type):
	building = b
	location = b.location
	type = t
	global_transform.origin = building.find_unit_spawn_location()
	add_to_group("unit")
	add_to_group("unit_player"+str(b.player_owner))
	position.y = -1 # hide
	# Following animates the unit in and starts the callback loop.
	# This all happens only the server.
	if not multiplayer.is_server():
		return
	var tw = create_tween()
	tw.tween_property(self, "position:y", 0, 5.0)
	tw.tween_callback(idle_callback).set_delay(5.0)

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
		return job_finished(false)
	# Third check if at destination - always a neighbour of location
	for n in job["location"].neighbours:
		if n == location:
			return start_work()
	# Fourth, run pathing
	if not check_pathing_valid():
		pass
		# TODO
		#return abandon_job(false) # No active call-backs
	# Fifth, move to next location
	assert(progress < path.size())
	var pm = get_node_or_null("/root/World/TileManager/PathingManager") as PathingManager
	location = pm.get_tile( path[progress] )
	progress += 1
	move("pathing_callback")
	
func start_work():
	if not multiplayer.is_server():
		return
	assert(state == State.PATHING)
	state = State.WORKING
	quick_rotate()
	$Zapper.visible = true
	match job["type"]:
		JobManager.JobType.TOGGLE_TILE:
			$Zapper.target_position.y = Cairo.UNIT
			job["location"].do_deconstruct_start(5.0)
		#JobManager.JobType.CONSTRUCT_BUILDING:
			#$Zapper.target_position.y = Cairo.UNIT
			#var building = job["target"].building
			#assert(building != null)
			#building.start_construction(self)
		#JobManager.JobType.CLAIM_TILE:
			#$Zapper.target_position.y = Cairo.UNIT / 2.0
			#var tile = job["place"]
			#assert(tile.player != player)
			#tile.start_capture(self)
		#JobManager.JobType.CLAIM_BUILDING:
			#$Zapper.target_position.y = Cairo.UNIT
			#var building = job["target"].building
			#assert(building != null)
			#assert(job["place"].player == player)
			#building.start_capture(self)
		_:
			print("UNKNOWN JOB TYPE")
			assert(false)

func check_job_still_valid() -> bool: # TODO
	if not multiplayer.is_server():
		return false
	return true

func check_pathing_valid() -> bool:
	if not multiplayer.is_server():
		return false
	if path.size() == 0:
		var pm = get_node_or_null("/root/World/TileManager/PathingManager") as PathingManager
		for n in job["location"].get_access_tiles():
			var check_path = pm.pathfind(location, n)
			if check_path.size() < path.size():
				path = check_path
		progress = 1 # 0 is our starting location
		#print("player " , player , " from " , location , " to " , job["place"] , " size " , path.size())
		if path.size() < 2:
			return false # We were unable to path
	return true
		

func job_finished(work_was_done : bool):
	if not multiplayer.is_server():
		return
	assert((work_was_done and state == State.WORKING) or (not work_was_done and state == State.PATHING))
	assert(job != null)
	state = State.IDLE
	$Zapper.visible = false
	var job_id = job["id"]
	job = {}
	var jm = get_node_or_null("/root/World/JobManager") as JobManager
	jm.remove_job(job_id)
	idle_callback()
	
#func abandon_job(have_active_callback : bool = true):
	#assert(state == State.PATHING or state == State.WORKING)
	#assert(job != null)
	#match state:
		#State.PATHING:
			#return abandon_job_while_pathing(have_active_callback)
		#State.WORKING:
			#return abandon_job_while_working(have_active_callback)
		#

func move(callback):
	if not multiplayer.is_server():
		return
	setup_rotation(location, null if job.is_empty() else job["target"])
	var time = Config.UNIT_SPEED[ type ] 
	#if scram_count > 0:
		#time *=  0.5
	if state == State.IDLE:
		time *= 2.0 
	# else - pathing, time *= 1.0
	var t = create_tween()
	t.tween_method(quat_transform, 0.0, 1.0, time / 2.0)
	t.tween_property(self, "position", location.pathing_centre, time)
	t.tween_callback(callback).set_delay(time)

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
