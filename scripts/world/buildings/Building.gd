extends StaticBody3D

class_name Building

const CONSTRUCTION_TIME: float = 5.0
const HEALTH_BAR_HEIGHT: float = 22.0

# --- Identity ---

var id: int
var location: TileElement
var player_owner: int

# --- State ---

enum State {BLUEPRINT, UNDER_CONSTRUCTION, CONSTRUCTED, UNDER_DESTRUCTION}

var state: State
var type: BuildingManager.Type

# --- Health ---

var health: float = 0.0
var max_health: float = 0.0
var _health_bar: HealthBar3D

# --- Construction ---

var _working_unit: Unit = null
var _construction_energy_spent := 0.0
var _construction_cost := 0.0

# --- Lifecycle ---

func initialise(pnum: int, tile: TileElement) -> void:
	location = tile
	tile.set_building(self)
	player_owner = pnum
	state = State.BLUEPRINT
	global_transform = tile.get_global_transform()
	global_position.y = 0
	add_to_group("building")
	add_to_group("building_player" + str(pnum))
	_health_bar = preload("res://scripts/ui/HealthBar3D.gd").new()
	var container = get_node_or_null("/root/World/BuildingManager/HealthBars")
	container.add_child(_health_bar)
	_health_bar.global_position.x = tile.pathing_centre.x
	_health_bar.global_position.z = tile.pathing_centre.z
	_health_bar.global_position.y = 3.0
	_health_bar.set_bar_size(4.0, 0.4)

func _exit_tree() -> void:
	if _health_bar and is_instance_valid(_health_bar):
		_health_bar.queue_free()

func _process(delta: float) -> void:
	if multiplayer.is_server() and state == State.UNDER_CONSTRUCTION:
		var energy_per_tick := _construction_cost / CONSTRUCTION_TIME * delta
		var em = get_node_or_null("/root/World/EnergyManager")
		if em:
			_construction_energy_spent += em.request_energy(player_owner, energy_per_tick)
		if _construction_energy_spent >= _construction_cost:
			set_constructed()
	if _health_bar:
		match state:
			State.UNDER_CONSTRUCTION:
				if _construction_cost > 0.0:
					_health_bar.set_health(_construction_energy_spent, _construction_cost)
				else:
					_health_bar.set_health(1.0, 1.0)
			State.CONSTRUCTED, State.UNDER_DESTRUCTION:
				_health_bar.set_health(health, max_health)
			_:
				_health_bar.set_health(0.0, 1.0)

# --- Queries ---

func find_unit_spawn_location() -> Vector3:
	for n in location.neighbours:
		if n.state == TileManager.State.LOWERED:
			return n.pathing_centre
	return Vector3.ZERO

func get_aoe_radius() -> float:
	return Config.BUILDING_AOE[type]

func check_work() -> void:
	pass

# --- Terminal positioning ---

func position_terminal() -> void:
	var terminal := get_node_or_null("Terminal")
	if not terminal:
		return
	var candidates: Array[TileElement] = location.get_access_tiles(player_owner)
	if candidates.is_empty():
		candidates = location.get_access_tiles()
	if candidates.is_empty():
		if location.neighbours.size() > 0:
			candidates = [location.neighbours[0]]
		else:
			return
	var mcp_nodes := get_tree().get_nodes_in_group("mcp_player" + str(player_owner))
	if mcp_nodes.is_empty():
		return
	var mcp_tile: TileElement = mcp_nodes[0].location
	var best := candidates[0]
	var best_dist := best.pathing_centre.distance_squared_to(mcp_tile.pathing_centre)
	for i in range(1, candidates.size()):
		var d := candidates[i].pathing_centre.distance_squared_to(mcp_tile.pathing_centre)
		if d < best_dist:
			best_dist = d
			best = candidates[i]
	var mid := _compute_edge_midpoint(best)
	terminal.global_position = Vector3(mid.x, 0.0, mid.z)
	var dir := (best.pathing_centre - location.pathing_centre).normalized()
	terminal.rotation.y = atan2(-dir.z, dir.x)

func _compute_edge_midpoint(neighbour: TileElement) -> Vector3:
	var a_xform := location.global_transform
	var b_xform := neighbour.global_transform
	var shared: Array[Vector3] = []
	for v in Cairo.BASE_VERTICES:
		var av: Vector3 = a_xform * v
		for w in Cairo.BASE_VERTICES:
			var bw: Vector3 = b_xform * w
			if av.distance_squared_to(bw) < 0.01:
				shared.append(av)
				break
		if shared.size() == 2:
			break
	if shared.size() == 2:
		return (shared[0] + shared[1]) * 0.5
	return (location.pathing_centre + neighbour.pathing_centre) * 0.5

# --- Construction ---

func start_construction(unit: Unit) -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.BLUEPRINT)
	state = State.UNDER_CONSTRUCTION
	_working_unit = unit
	_construction_energy_spent = 0.0
	_construction_cost = Config.CONSTRUCTION_COST.get(type, 0.0)
	if _construction_cost <= 0.0:
		set_constructed()

func cancel_construction() -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.UNDER_CONSTRUCTION)
	state = State.BLUEPRINT
	_working_unit = null
	_construction_energy_spent = 0.0

func set_constructed() -> void:
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

# --- RPC ---

@rpc("authority", "call_local", "reliable")
func rpc_constructed(bid: int) -> void:
	var bm = get_node_or_null("/root/World/BuildingManager")
	if not bm:
		return
	var bp = bm.get_node_or_null("Blueprint_" + str(bid))
	if bp:
		bp.queue_free()
	set_visible(true)
