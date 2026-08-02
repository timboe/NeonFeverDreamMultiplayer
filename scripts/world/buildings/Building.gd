extends StaticBody3D

class_name Building

# --- Constants ---

const CONSTRUCTION_TIME: float = 5.0
const HEALTH_BAR_HEIGHT: float = 22.0
const REPAIR_INTERVAL := 0.05
const REPAIR_AMOUNT := 2.5

# --- Identity ---

var id: int
var location: TileElement
var player_owner: int

# --- State ---

enum State {BLUEPRINT, UNDER_CONSTRUCTION, CONSTRUCTED}

var state: State
var type: BuildingManager.Type
var is_empowered: bool = false
var orders: Dictionary = {}
var _aoe_tiles: Array[TileElement] = []
var _aoe_tiles_extra: Array[TileElement] = []

# --- Health ---

var health: float = 0.0
var max_health: float = 0.0
var _health_bar: HealthBar3D
var _repair_timer := 0.0

# --- Construction ---

var _working_unit: Unit = null
var _construction_energy_spent := 0.0

# --- Production ---

var _production_type: UnitManager.Type = UnitManager.Type.NONE
var _production_cost: float = 0.0
var _production_energy: float = 0.0
var _production_timer: float = 0.0
var _production_enabled: bool = true

# --- HUD ---

var _hud: SubViewport = null

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
	var container = Global.BM.get_node_or_null("HealthBars")
	if container:
		container.add_child(_health_bar)
	_health_bar.global_position.x = tile.pathing_centre.x
	_health_bar.global_position.z = tile.pathing_centre.z
	_health_bar.global_position.y = 3.0
	_health_bar.set_bar_size(4.0, 0.4)

func _exit_tree() -> void:
	if _health_bar and is_instance_valid(_health_bar):
		_health_bar.queue_free()

func _process(delta: float) -> void:
	# Do construction - consumes energy
	if multiplayer.is_server() and state == State.UNDER_CONSTRUCTION:
		var cost: float = Config.CONSTRUCTION_COST.get(type, 0.0)
		var energy_per_tick := cost / CONSTRUCTION_TIME * delta
		var em = Global.EM
		if em:
			_construction_energy_spent += em.request_energy(player_owner, energy_per_tick)
		if _construction_energy_spent >= cost:
			set_constructed()

	# Do production - accumulate energy over time
	if multiplayer.is_server() and state == State.CONSTRUCTED and _production_type != UnitManager.Type.NONE:
		if _production_timer > 0.0:
			_production_timer -= delta
		elif _production_enabled:
			var em = Global.EM
			if em and _production_cost > 0.0:
				var tick_amount := _production_cost * delta
				_production_energy += em.request_energy(player_owner, tick_amount)
			if _production_energy >= _production_cost:
				_produce_unit()

	# If under repair (on server)
	if multiplayer.is_server() and state == State.CONSTRUCTED and _working_unit:
		_repair_timer += delta
		while _repair_timer >= REPAIR_INTERVAL:
			_repair_timer -= REPAIR_INTERVAL
			if not is_instance_valid(_working_unit):
				finish_repair()
				return
			health += REPAIR_AMOUNT
			if health >= max_health:
				health = max_health
				finish_repair()
				return

	if _health_bar:
		match state:
			State.UNDER_CONSTRUCTION:
				var cost: float = Config.CONSTRUCTION_COST.get(type, 0.0)
				if cost > 0.0:
					_health_bar.set_health(_construction_energy_spent, cost)
				else:
					_health_bar.set_health(1.0, 1.0)
			State.CONSTRUCTED:
				_health_bar.set_health(health, max_health)
			_:
				_health_bar.set_health(0.0, 1.0)

# --- Queries ---

func find_unit_spawn_location() -> TileElement:
	for n in location.neighbours:
		if n.state == TileManager.State.LOWERED:
			return n
	return location

func get_aoe_radius() -> int:
	return Config.BUILDING_AOE[type]

func _build_aoe_tiles() -> void:
	var interactive: Array = get_tree().get_nodes_in_group("interactive")
	_aoe_tiles.clear()
	_aoe_tiles_extra.clear()
	var radius := int(get_aoe_radius())
	var queue := []
	var visited := {}
	visited[location] = true
	queue.append({tile = location, depth = 0})
	while queue:
		var entry = queue.pop_front()
		var current = entry.tile as TileElement
		var depth = entry.depth as int
		if depth <= radius:
			_aoe_tiles.append(current)
			for n in current.neighbours:
				if n not in interactive:
					continue
				if not visited.has(n):
					visited[n] = true
					queue.append({tile = n, depth = depth + 1})
		elif depth == radius + 1:
			_aoe_tiles_extra.append(current)

func check_work() -> void:
	if not multiplayer.is_server():
		return
	if state != State.CONSTRUCTED:
		return
	if not _production_enabled:
		return
	if health < max_health:
		Global.JM.add_job(player_owner, JobManager.Type.REPAIR_BUILDING, location)

func toggle_production() -> void:
	if not multiplayer.is_server():
		return
	_production_enabled = not _production_enabled

# --- Empower ---

@rpc("authority", "call_local", "reliable")
func rpc_set_empowered(val: bool) -> void:
	is_empowered = val
	_empower_changed(val)

func _empower_changed(_val: bool) -> void:
	pass

# --- Production ---

func _setup_production(unit_type: UnitManager.Type) -> void:
	_production_type = unit_type
	_production_cost = Config.UNIT_COST.get(unit_type, 0.0)
	_production_timer = Config.PRODUCTION_COOLDOWNS.get(type, 10.0)

func _produce_unit() -> void:
	if not multiplayer.is_server():
		return
	if _production_type == UnitManager.Type.NONE:
		return
	var um = Global.UM
	if not um:
		return
	var uid: int = um.next_unit_id()
	um.rpc("rpc_spawn_unit", uid, _production_type, self.id)
	_production_energy = 0.0
	_production_timer = Config.PRODUCTION_COOLDOWNS.get(type, 10.0)

# --- HUD ---

func _get_hud_scene() -> PackedScene:
	return null

func _setup_hud() -> void:
	var hud_scene := _get_hud_scene()
	if not hud_scene:
		return
	# Remove the template node from the tree immediately so it stops rendering
	var template = get_node_or_null("BuildingHUD")
	if template:
		remove_child(template)
		template.queue_free()
	# Create a fresh SubViewport with its own render target
	_hud = SubViewport.new()
	_hud.name = "BuildingHUD"
	_hud.size = Vector2(480, 480)
	_hud.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_hud)
	move_child(_hud, 0)
	# Instantiate the HUD scene fresh — each building gets its own nodes
	var ctrl = hud_scene.instantiate()
	_hud.add_child(ctrl)
	ctrl.building = self
	var screen = get_node_or_null("Terminal/Screen")
	if screen:
		var mat = screen.get_surface_override_material(0)
		if mat:
			# Make the screen material unique so each building has its own texture
			mat = mat.duplicate()
			screen.set_surface_override_material(0, mat)
			mat.albedo_texture = _hud.get_texture()
			mat.albedo_color = Color.WHITE
		if ctrl.has_method("setup_cursor_3d"):
			ctrl.setup_cursor_3d(screen)

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
	var edge_data := _compute_edge(best)
	terminal.global_position = Vector3(edge_data.midpoint.x, 0.0, edge_data.midpoint.z)
	terminal.rotation.y = atan2(-edge_data.normal.z, edge_data.normal.x) + PI - location.rotation.y

func _compute_edge(neighbour: TileElement) -> Dictionary:
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
		var midpoint := (shared[0] + shared[1]) * 0.5
		var edge := shared[1] - shared[0]
		var perp := Vector3(edge.z, 0.0, -edge.x).normalized()
		var outward := (midpoint - location.pathing_centre).normalized()
		if perp.dot(outward) < 0.0:
			perp = -perp
		return {"midpoint": midpoint, "normal": perp}
	var fallback_dir := (neighbour.pathing_centre - location.pathing_centre).normalized()
	return {"midpoint": (location.pathing_centre + neighbour.pathing_centre) * 0.5, "normal": fallback_dir}

# --- Construction ---

func start_construction(unit: Unit) -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.BLUEPRINT)
	state = State.UNDER_CONSTRUCTION
	_working_unit = unit
	if Config.CONSTRUCTION_COST.get(type, 0.0) <= 0.0:
		set_constructed()

func cancel_construction() -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.UNDER_CONSTRUCTION)
	state = State.BLUEPRINT
	_working_unit = null

func set_constructed() -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.UNDER_CONSTRUCTION)
	state = State.CONSTRUCTED
	if is_instance_valid(_working_unit):
		_working_unit.job_finished()
	_working_unit = null
	rpc("rpc_constructed", id)

# --- Damage and Repair ---

func apply_damage(amount: float, delay: float = 0.0) -> void:
	if not multiplayer.is_server():
		return
	if delay > 0.0:
		var tween := create_tween()
		tween.tween_callback(apply_damage.bind(amount)).set_delay(delay)
		return
	_apply_damage(amount)

func _apply_damage(damage: float) -> void:
	if state == State.CONSTRUCTED:
		# If built, specific health pool. Not energy based
		health -= damage
		if health <= 0:
			health = 0
			Global.BM.rpc("rpc_remove_building", id)
	else:
		# If under construction, attacks directly deplete the energy being used to build
		_construction_energy_spent -= damage
		if _construction_energy_spent <= 0:
			_construction_energy_spent = 0
			rpc("rpc_constructed", id) # Remove blueprint as well
			Global.BM.rpc("rpc_remove_building", id)

func start_repair(unit: Unit) -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.CONSTRUCTED)
	_working_unit = unit

func finish_repair() -> void:
	if not multiplayer.is_server():
		return
	if is_instance_valid(_working_unit):
		_working_unit.job_finished()
	_working_unit = null

# --- RPC ---

@rpc("authority", "call_local", "reliable")
func rpc_constructed(bid: int) -> void:
	var bm = Global.BM
	if not bm:
		return
	var bp = bm.get_node_or_null("Blueprint_" + str(bid))
	if bp:
		bp.queue_free()
	set_visible(true)
