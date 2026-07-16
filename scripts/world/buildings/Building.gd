extends StaticBody3D

class_name Building

var id : int # My ID within the BuildingManager dict. TODO - not needed?
var location : TileElement # My tile, bi-directional linked
var player_owner : int # Building owner. Cannot be infered from tile

var default_mat = preload("res://materials/player/player1_material.tres")
var updated_mat

enum State {BLUEPRINT, UNDER_CONSTRUCTION, CONSTRUCTED, UNDER_DESTRUCTION}
var state : int
var type : BuildingManager.Type

const SPAWN_TIME : float = 5.0
const CONSTRUCTION_TIME : float = 5.0
const CAPTURE_TIME : float = 10.0
var capture_in_progress = false

var spawn_particles
var zoomba_constructing_me

var my_blueprint

var _build_tween: Tween

func initialise(pnum : int, tile : TileElement, t : BuildingManager.Type):
	initialise_base(pnum, tile, t)

func initialise_base(pnum : int, tile : TileElement, t : BuildingManager.Type):
	type = t
	location = tile # Two way link
	tile.set_building(self)  # Two way link
	player_owner = pnum
	state = State.BLUEPRINT
	global_transform = tile.get_global_transform()
	global_position.y = 0
	add_to_group("building")
	add_to_group("building_player"+str(pnum))

func set_blueprint(b):
	my_blueprint = b
	set_visible(false)
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

func check_work():
	pass

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
	by_whome.job_finished()
	_build_tween = create_tween()
	_build_tween.tween_callback(set_constructed_b).set_delay(1.0)
	
func set_constructed_b():
	# Now with cloud cover
	set_visible(true)
	my_blueprint.queue_free()
	
	
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
	
