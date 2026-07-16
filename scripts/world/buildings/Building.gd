extends StaticBody3D

class_name Building

var id : int
var location : TileElement
var player_owner : int

enum State {BLUEPRINT, UNDER_CONSTRUCTION, CONSTRUCTED, UNDER_DESTRUCTION}
var state : int
var type : BuildingManager.Type

const CONSTRUCTION_TIME : float = 5.0

var _working_unit : Unit = null

var _construction_timer := 0.0
var _construction_energy_spent := 0.0
var _construction_cost := 0.0

func initialise(pnum : int, tile : TileElement, t : BuildingManager.Type):
	initialise_base(pnum, tile, t)

func initialise_base(pnum : int, tile : TileElement, t : BuildingManager.Type):
	type = t
	location = tile
	tile.set_building(self)
	player_owner = pnum
	state = State.BLUEPRINT
	global_transform = tile.get_global_transform()
	global_position.y = 0
	add_to_group("building")
	add_to_group("building_player"+str(pnum))

func _ready():
	pass

func _process(delta : float) -> void:
	if not multiplayer.is_server():
		return
	if state != State.UNDER_CONSTRUCTION:
		return
	_construction_timer += delta
	var energy_per_tick := _construction_cost / CONSTRUCTION_TIME * delta
	var em = get_node_or_null("/root/World/EnergyManager")
	if em:
		_construction_energy_spent += em.request_energy(player_owner, energy_per_tick)
	if _construction_energy_spent >= _construction_cost:
		set_constructed()

func find_unit_spawn_location():
	for n in location.neighbours:
		if n.state == TileManager.State.LOWERED:
			return n.pathing_centre
	return null

func get_aoe_radius():
	return Config.BUILDING_AOE[ type ]

func check_work():
	pass

func start_construction(unit : Unit):
	if not multiplayer.is_server():
		return
	assert(state == State.BLUEPRINT)
	state = State.UNDER_CONSTRUCTION
	_working_unit = unit
	_construction_timer = 0.0
	_construction_energy_spent = 0.0
	_construction_cost = Config.CONSTRUCTION_COST.get(type, 0.0)
	if _construction_cost <= 0.0:
		set_constructed()

func cancel_construction():
	if not multiplayer.is_server():
		return
	assert(state == State.UNDER_CONSTRUCTION)
	state = State.BLUEPRINT
	_working_unit = null
	_construction_timer = 0.0
	_construction_energy_spent = 0.0

func set_constructed():
	if not multiplayer.is_server():
		return
	assert(state == State.UNDER_CONSTRUCTION)
	state = State.CONSTRUCTED
	if is_instance_valid(_working_unit):
		_working_unit.job_finished()
	_working_unit = null
	rpc("rpc_constructed", id)
	var em = get_node_or_null("/root/World/EnergyManager")
	if em:
		em.recalculate_capacity()

@rpc("authority", "call_local", "reliable")
func rpc_constructed(bid : int):
	var bm = get_node_or_null("/root/World/BuildingManager")
	if not bm:
		return
	var bp = bm.get_node_or_null("Blueprint_" + str(bid))
	if bp:
		bp.queue_free()
	set_visible(true)
