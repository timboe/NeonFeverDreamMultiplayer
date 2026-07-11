extends StaticBody3D

class_name Building

var id : int # My ID within the BuildingManager dict. TODO - not needed?
var location : TileElement # My tile, bi-directional linked
var player_owner : int # Building owner. Cannot be infered from tile

var default_mat = preload("res://materials/player/player0_material.tres")
var updated_mat

enum State {BLUEPRINT, UNDER_CONSTRUCTION, CONSTRUCTED, UNDER_DESTRUCTIOfN}
var state : int
var type : BuildingManager.Type

const SPAWN_TIME : float = 5.0
const CONSTRUCTION_TIME : float = 5.0
const CAPTURE_TIME : float = 10.0
var capture_in_progress = false

var spawn_particles
var zoomba_constructing_me

var _my_blueprint
var my_blueprint:
	get: return _my_blueprint
	set(value): _my_blueprint = value

var _build_tween: Tween

func initialise_base(tile : TileElement, pnum : int, t : BuildingManager.Type):
	type = t
	location = tile # Two way link
	tile.set_building(self)  # Two way link
	player_owner = pnum
	state = State.BLUEPRINT
	transform = tile.get_global_transform()
	transform.origin.y = 0
	add_to_group("building")

func set_blueprint(b):
	my_blueprint = b
	set_visible(false)
	#update_monorail()
	state = State.BLUEPRINT
	
func _ready():
	set_livery()

func find_unit_spawn_location():
	for n in location.neighbours:
		if n.state == TileManager.State.LOWERED:
			return n.pathing_centre
	return null
	
func get_aoe_radius():
	return Config.BUILDING_AOE[ type ]
		
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
	
##NOTE: Moved to UnitManager as spawn_zoomba
#func add_zoomba():

##NOTE: Moved to UnitManager
#func zoomba_callback(z):
	
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
	
func queue_construction_jobs(_placement_player : int):
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
	
