extends StaticBody3D

class_name Building

var id : int
var location : TileElement
var player_owner : int

var default_mat = preload("res://materials/player/player0_material.tres")
var updated_mat

enum State {BLUEPRINT, UNDER_CONSTRUCTION, CONSTRUCTED, UNDER_DESTRUCTION}
var state : int
var type

const PULSE_INITIAL := 0.1
const SPAWN_TIME : float = 5.0
const CONSTRUCTION_TIME : float = 5.0
const CAPTURE_TIME : float = 10.0
var capture_in_progress = false

var _spawn_start_loc: TileElement
var spawn_start_loc: TileElement:
	get: return _spawn_start_loc
	set(value): _spawn_start_loc = value

var spawn_particles
var zoomba_constructing_me

var _my_blueprint
var my_blueprint:
	get: return _my_blueprint
	set(value): _my_blueprint = value

var _build_tween: Tween

func set_blueprint(b):
	my_blueprint = b
	set_visible(false)
	#update_monorail()
	state = State.BLUEPRINT

#func set_spawn_start_loc(s):
	#spawn_start_loc = s
	#spawn_particles = $"../../CameraManager/SpawnParticles".duplicate()
	#$"../".add_child(spawn_particles)
	#spawn_particles.transform.origin = spawn_start_loc.pathing_centre
	
func _ready():
	set_livery()

#func update_monorail():
	#assert(location != null)
	#for mr in location.paths.values():
		#mr.update_building_passable()	

func set_livery():
	# TODO - tile can now have multiple AoE players, this does not work anymore to select the owner
	pass
	#if location != null and location.player > 0:
		#updated_mat = load("res://materials/player" + str(location.player) + "_material.tres")
		#recursive_set_livery(self)

# TODO - fix set_livery first
#func recursive_set_livery(var node):
	#for c in range(node.get_child_count()):
		#recursive_set_livery(node.get_child(c))
	#var rid = node.get_surface_material(0).get_rid() if node is MeshInstance and node.get_surface_material(0) != null else null
	#if rid != null and rid == default_mat.get_rid():
		#node.set_surface_material(0, updated_mat)


func start_construction(by_whome):
	assert(state == State.BLUEPRINT)
	state = State.UNDER_CONSTRUCTION
	_build_tween = create_tween()
	_build_tween.tween_callback(set_constructed_a.bind(by_whome)).set_delay(CONSTRUCTION_TIME)

func abandon_construction():
	assert(state == State.UNDER_CONSTRUCTION)
	if _build_tween and _build_tween.is_valid():
		_build_tween.kill()
	state = State.BLUEPRINT

func set_constructed_a(by_whome):
	assert(state == State.UNDER_CONSTRUCTION)
	assert(my_blueprint != null)
	state = State.CONSTRUCTED
	by_whome.job_finished(true)
	_build_tween = create_tween()
	_build_tween.tween_callback(set_constructed_b).set_delay(1.0)
	
func set_constructed_b():
	# Now with cloud cover
	set_visible(true)
	my_blueprint.queue_free()
		
#func add_zoomba():
	#var zoomba = $"../../ObjectFactory/Zoomba".duplicate()
	#actor_manager.add_child(zoomba)
	#zoomba.initialise(spawn_start_loc, location.player)
	#var t = create_tween()
	#t.tween_property(zoomba, "position:y", zoomba.position.y, SPAWN_TIME)
	#t.tween_callback(zoomba_callback.bind(zoomba)).set_delay(SPAWN_TIME)
	#spawn_particles.emitting = true
	#return zoomba
#
#func zoomba_callback(z):
	#spawn_particles.emitting = false
	#z.idle_callback()
	
#func start_capture(by_whome):
	#var t = create_tween()
	#t.tween_callback(set_captured.bind(by_whome)).set_delay(CAPTURE_TIME)
	#capture_in_progress = true
	
#func abandon_capture():
	#capture_in_progress = false

#func set_captured(var by_whome):
	#location.set_captured(by_whome)
	#set_livery()
	#capture_in_progress = false
	#if zoomba_constructing_me != null:
		#zoomba_constructing_me.scram() # If I was being con/de-structed, now I'm not
	#if state == State.BLUEPRINT:
		## Disallow capture of a barrier - just poof it
		#if type == BuildingManager.Type.BAR:
			#queue_free()
		#else:
			#queue_construction_jobs(-1) # I might have been captured before I was constructed
	
func queue_construction_jobs(placement_player : int):
	pass
	# TODO
	#assert(state == State.BLUEPRINT)
	#if placement_player == -1:
		## Called from set_captured, we can be sure we're not building a barrier then. Safe to do...
		#placement_player = location.player
	#var access_tiles = location.get_access_tiles_wall(placement_player) if type == BuildingManager.Type.BAR else location.get_access_tiles()
	#assert(access_tiles.size() > 0)
	#for access in access_tiles:
		#job_manager.add_job(placement_player, job_manager.JobType.CONSTRUCT_BUILDING, access, location)
	
