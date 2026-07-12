extends Node3D

class_name Unit

var id : int # My ID within the UnitManager
var building : Building # Building which spawned me (designates owner)

enum State {IDLE, PATHING, WORKING}
var state : int = State.IDLE
var type : UnitManager.Type
var job : Dictionary = {}
var health : float = 100.0

var path : PackedInt64Array = []
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
	position.y = -2 # hide
	# Following animates the unit in and starts the callback loop.
	# This all happens on the server. Wait for next frame as might now have multiplayer yet
	# TODO - when no longer spawing zoomba in init, should be able to remove call deffered
	post_initalise.call_deferred()

@rpc("authority", "call_local")
func post_initalise():
	if not multiplayer.is_server():
		return
	var tw = create_tween()
	tw.tween_property(self, "position:y", 0, 5.0)
	tw.tween_callback(idle_callback).set_delay(5.0)

@rpc("authority", "call_local")
func assign_job(new_job : Dictionary):
	assert(job == null)
	assert(state == State.IDLE)
	assert(new_job["pnum"] == building.player_owner)
	state = State.PATHING
	job = new_job

@rpc("authority", "call_local")
func idle_callback():
	print("idle callback")
	if not job.is_empty():
		#assert(scram_count == 0)
		path.resize(0)
		#pathing_callback() # TODO next
		return
		
	# Get possible ways out of this tile
	var territory_check := building.player_owner if type in Config.HOME_TERRITORY_UNITS else 0	
	var possible_destinations := location.get_access_tiles(territory_check)
	print("pos des ", possible_destinations)
			
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
	print("do move")
	move(idle_callback)

@rpc("authority", "call_local")
func move(callback):
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

@rpc("authority", "call_local")
func quat_transform(amount : float):
	var mid = quat_from.slerp(quat_to, amount)
	transform.basis = Basis(mid)

@rpc("authority", "call_local")
func setup_rotation(target, look_at_from_target):
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
