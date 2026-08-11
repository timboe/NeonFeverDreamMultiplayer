extends StaticBody3D

class_name Building

# --- Constants ---

const CONSTRUCTION_TIME: float = 5.0
const HEALTH_BAR_HEIGHT: float = 22.0
const REPAIR_INTERVAL: float = 0.05
const REPAIR_AMOUNT: float = 2.5
# Squared XZ distance tolerance when matching shared pentagon edge vertices in
# _compute_edge (0.1 world units at Cairo.UNIT = 10).
const EDGE_MATCH_EPSILON: float = 0.01

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

var working_unit: Unit = null
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
	input_ray_pickable = true
	mouse_entered.connect(_on_hover_entered)
	mouse_exited.connect(_on_hover_exited)
	input_event.connect(_on_StaticBody_input_event)

func _exit_tree() -> void:
	if _health_bar and is_instance_valid(_health_bar):
		_health_bar.queue_free()
	if is_instance_valid(Global.BM) and Global.BM.hovered_building == self:
		Global.BM.hovered_building = null
	if is_instance_valid(Global.BM) and Global.BM.is_remove_ghost_for(self):
		Global.BM.hide_remove_ghost()
	# A generator freed while hovered (removal) never fires its mouse_exited,
	# so its catchment glow would linger on the tiles — release it here.
	if self is Generator:
		for t in _aoe_tiles:
			t.release_emission(TileElement.EmissionEffect.GENERATOR_CATCHMENT)

# --- Mouse hover (RTS tooltip / remove ghost) ---

func _on_hover_entered() -> void:
	Global.BM.hovered_building = self
	var hud = get_tree().get_first_node_in_group("hud") as HUD
	if hud and hud.is_removing() and player_owner == Global.my_player_number:
		Global.BM.show_remove_ghost(self)
		return
	if state != State.CONSTRUCTED:
		return

func _on_hover_exited() -> void:
	if Global.BM.hovered_building == self:
		Global.BM.hovered_building = null
	if Global.BM.is_remove_ghost_for(self):
		Global.BM.hide_remove_ghost()

# --- Mouse click (RTS remove mode) ---

func _on_StaticBody_input_event(_camera, event, _click_position, _click_normal, _shape_idx) -> void:
	if not event is InputEventMouseButton or not event.is_pressed() or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var hud = get_tree().get_first_node_in_group("hud") as HUD
	if not hud or not hud.is_removing():
		return
	if player_owner != Global.my_player_number:
		return
	Global.send_command_me("remove_building", [id])

func _process(delta: float) -> void:
	# Do construction - consumes energy
	if multiplayer.is_server() and Global.game_started and state == State.UNDER_CONSTRUCTION:
		var cost: float = Config.CONSTRUCTION_COST.get(type, 0.0)
		var energy_per_tick := cost / CONSTRUCTION_TIME * delta * _drain_multiplier()
		_construction_energy_spent += Global.EM.request_energy(player_owner, energy_per_tick)
		if _construction_energy_spent >= cost:
			set_constructed()

	# Do production - accumulate energy over time
	if multiplayer.is_server() and Global.game_started and state == State.CONSTRUCTED and _production_type != UnitManager.Type.NONE:
		if _production_timer > 0.0:
			if _production_enabled:
				_production_timer -= delta
			if not _can_produce():
				_production_timer = 0.0
		elif _production_enabled and _can_produce():
			if _production_cost > 0.0:
				var tick_amount := _production_cost * delta * _vat_spend_mult()
				_production_energy += Global.EM.request_energy(player_owner, tick_amount)
			if _production_energy >= _production_cost:
				_produce_unit()

	# If under repair (on server)
	if multiplayer.is_server() and Global.game_started and state == State.CONSTRUCTED and working_unit:
		_repair_timer += delta
		while _repair_timer >= REPAIR_INTERVAL:
			_repair_timer -= REPAIR_INTERVAL
			if not is_instance_valid(working_unit):
				finish_repair()
				return
			if _repair_heal():
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
	var access := location.get_access_tiles()
	if not access.is_empty():
		return access[0]
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

# Empowered Vat spend discount: construction/production drains cost 10% less
# while the player has a Vat empowered.
func _vat_spend_mult() -> float:
	if Global.BM.empowered_type(player_owner) == BuildingManager.Type.VAT:
		return Config.EMPOWER_VAT_SPEND_MULT
	return 1.0

# Empowered MCP work-speed bonus: construction drains faster and repairs heal
# more per tick while the working zoomba's MCP is empowered (×1.2 work speed).
func _work_mult() -> float:
	if is_instance_valid(working_unit):
		return working_unit.work_speed_multiplier()
	return 1.0

# Combined per-tick construction drain multiplier (vat discount × zoomba work).
func _drain_multiplier() -> float:
	return _vat_spend_mult() * _work_mult()

# --- Settings inheritance ---

# Newly constructed buildings copy the player's in-game settings (targets,
# ratios, patrol stance) from their most recently placed sibling of the same
# type. Runs on every peer: the server applies the authoritative copy through
# the command relay (same handlers the terminal HUD buttons use), while clients
# apply the values to their local instance so the owner's terminal displays
# them without any network sync.
func _inherit_settings_from_sibling() -> void:
	var sibling := _find_highest_id_sibling()
	if sibling:
		_copy_settings_from(sibling)

func _find_highest_id_sibling() -> Building:
	var best: Building = null
	for b in Global.BM.buildings():
		if b == self or b.player_owner != player_owner or b.type != type:
			continue
		if best == null or b.id > best.id:
			best = b
	return best

# Overridden by subclasses with configurable settings (Garage, Beacon, Nest).
func _copy_settings_from(_sibling: Building) -> void:
	pass

@rpc("authority", "call_local", "reliable")
func rpc_inherit_settings() -> void:
	# The server already applied the authoritative copy through the command
	# relay inside set_constructed(); it only needs its own (host-owned)
	# terminal refreshed, not a second copy. Clients mirror the values onto
	# their local instance so the owning player's terminal displays them.
	if multiplayer.is_server():
		_refresh_owned_terminal_ui()
		return
	_inherit_settings_from_sibling()
	_refresh_owned_terminal_ui()

# Set the owning player's terminal controls to the current settings. Owned
# terminals are client-set only, so this runs once when a building inherits
# settings (and never again — the player's interactions take over).
func _refresh_owned_terminal_ui() -> void:
	if player_owner != Global.my_player_number:
		return
	refresh_terminal_ui()

# Push the building's settings into its terminal controls. Used for buildings
# the current player does not own, so the (server-synced) settings render on
# their terminal for spying.
func refresh_terminal_ui() -> void:
	if not _hud or not is_instance_valid(_hud):
		return
	for c in _hud.get_children():
		if c.has_method("refresh_controls_from_building"):
			c.refresh_controls_from_building()
			return

# --- Production ---

func _setup_production(unit_type: UnitManager.Type) -> void:
	_production_type = unit_type
	_production_cost = Config.UNIT_COST.get(unit_type, 0.0)
	_production_timer = Config.PRODUCTION_COOLDOWNS.get(type, 10.0)

# Whether the building is able to produce a unit right now. Unit producers stop
# when hemmed in — no lowered neighbouring tile without a building — since units
# need an access tile to spawn onto. Subclasses that saturate (e.g. MCP at its
# zoomba cap) override this.
func _can_produce() -> bool:
	return location.has_access()

func _produce_unit() -> void:
	if not multiplayer.is_server():
		return
	if _production_type == UnitManager.Type.NONE:
		return
	var uid: int = Global.UM.next_unit_id()
	Global.UM.rpc("rpc_spawn_unit", uid, _production_type, self.id)
	_production_energy = 0.0
	_production_timer = Config.PRODUCTION_COOLDOWNS.get(type, 10.0)

# --- HUD ---

func _get_hud_scene() -> PackedScene:
	return null

# --- Targeting ---

# Enemy target lists may come from HUD toggles or defaults like [1,2,3,4] that
# include the owner itself — a building can never target its own team.
func _clean_enemy_targets(targets: Array) -> Array[int]:
	var out: Array[int] = []
	for p in targets:
		if p != player_owner:
			out.append(int(p))
	return out

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
	ctrl.building = self
	_hud.add_child(ctrl)
	var screen = get_node_or_null("Terminal/Screen")
	if screen:
		var mat = screen.get_surface_override_material(0)
		if mat:
			# Make the screen material unique so each building has its own texture
			mat = mat.duplicate()
			screen.set_surface_override_material(0, mat)
			mat.albedo_texture = _hud.get_texture()
			mat.albedo_color = Color.WHITE

# --- Terminal positioning ---

func position_terminal(mcp_tile: TileElement = null) -> void:
	var terminal := get_node_or_null("Terminal")
	if not terminal:
		return
	var candidates: Array[TileElement] = location.get_access_tiles(player_owner)
	if candidates.is_empty():
		candidates = location.get_access_tiles()
	if candidates.is_empty():
		# No lowered access tiles — the building is penned in. Hide the terminal
		# rather than floating it on a raised neighbour.
		terminal.visible = false
		return
	terminal.visible = true
	var best := candidates[0]
	if mcp_tile == null:
		var mcp_nodes := get_tree().get_nodes_in_group("mcp_player" + str(player_owner))
		if not mcp_nodes.is_empty():
			mcp_tile = mcp_nodes[0].location
	if mcp_tile:
		var best_dist := best.pathing_centre.distance_squared_to(mcp_tile.pathing_centre)
		for i in range(1, candidates.size()):
			var d := candidates[i].pathing_centre.distance_squared_to(mcp_tile.pathing_centre)
			if d < best_dist:
				best_dist = d
				best = candidates[i]
	var edge_data := _compute_edge(best)
	# Sit the terminal on the chosen tile's surface (raised or lowered) rather
	# than assuming the world floor is y=0.
	var ground_y := best.global_position.y + Cairo.HEIGHT
	var world_pos := Vector3(edge_data.midpoint.x, ground_y, edge_data.midpoint.z)
	# Keep position and rotation in the same (building-local) space.
	terminal.position = to_local(world_pos)
	terminal.rotation.y = atan2(-edge_data.normal.z, edge_data.normal.x) + PI - rotation.y

func _compute_edge(neighbour: TileElement) -> Dictionary:
	var a_xform := location.global_transform
	var b_xform := neighbour.global_transform
	var shared: Array[Vector3] = []
	for v in Cairo.BASE_VERTICES:
		var av: Vector3 = a_xform * v
		for w in Cairo.BASE_VERTICES:
			var bw: Vector3 = b_xform * w
			# Compare in XZ only — adjacent tiles can be at different heights
			# (raised building tile vs lowered access tile) yet share the edge
			# vertically, so a full 3D distance would never match.
			if Vector2(av.x, av.z).distance_squared_to(Vector2(bw.x, bw.z)) < EDGE_MATCH_EPSILON:
				shared.append(av)
				break
		if shared.size() == 2:
			break
	if shared.size() == 2:
		var midpoint := (shared[0] + shared[1]) * 0.5
		midpoint.y = 0.0
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
	working_unit = unit
	if Config.CONSTRUCTION_COST.get(type, 0.0) <= 0.0:
		set_constructed()

func cancel_construction() -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.UNDER_CONSTRUCTION)
	state = State.BLUEPRINT
	working_unit = null

func set_constructed() -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.UNDER_CONSTRUCTION)
	state = State.CONSTRUCTED
	if is_instance_valid(working_unit):
		working_unit.job_finished()
	working_unit = null
	rpc("rpc_constructed", id)
	# Inherit the player's latest settings for this building type: the server
	# applies them authoritatively through the same command relay the terminal
	# UI uses, then tells clients to mirror them onto their local instances.
	_inherit_settings_from_sibling()
	rpc("rpc_inherit_settings")

# --- Damage and Repair ---

func apply_damage(amount: float, delay: float = 0.0, attacker: Unit = null) -> void:
	if not multiplayer.is_server():
		return
	if delay > 0.0:
		var tween := create_tween()
		tween.tween_callback(apply_damage.bind(amount, 0.0, attacker)).set_delay(delay)
		return
	_apply_damage(amount, attacker)

func _apply_damage(damage: float, attacker: Unit = null) -> void:
	Global.SM.record_damage_received(player_owner, damage)
	if state == State.CONSTRUCTED:
		# If built, specific health pool. Not energy based
		health -= damage
		if health <= 0:
			health = 0
			Global.BM.rpc("rpc_remove_building", id)
			return
		_call_for_defense(attacker)
	else:
		# If under construction, attacks directly deplete the energy being used to build
		_construction_energy_spent -= damage
		if _construction_energy_spent <= 0:
			_construction_energy_spent = 0
			rpc("rpc_constructed", id) # Remove blueprint as well
			Global.BM.rpc("rpc_remove_building", id)

# A building under attack calls for defense (DESIGN): queue a COMBAT_PERSUE job
# on the attacker. A VIRUS attacker is answered by PATROL aerials (the only
# units that can engage it — patrol_only + territory_only); any other attacker
# (AERIAL) is answered by TANKs (territory_only). Job dedupe collapses repeated
# damage ticks into a single defense order.
func _call_for_defense(attacker: Unit) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if attacker.player_owner == player_owner:
		return
	match attacker.type:
		UnitManager.Type.VIRUS:
			Global.JM.add_job(player_owner, JobManager.Type.COMBAT_PERSUE, attacker, null, false, [UnitManager.Type.AERIAL], true, true)
		_:
			Global.JM.add_job(player_owner, JobManager.Type.COMBAT_PERSUE, attacker, null, false, [UnitManager.Type.TANK], false, true)

func start_repair(unit: Unit) -> void:
	if not multiplayer.is_server():
		return
	assert(state == State.CONSTRUCTED)
	working_unit = unit

func finish_repair() -> void:
	if not multiplayer.is_server():
		return
	if is_instance_valid(working_unit):
		working_unit.job_finished()
	working_unit = null

# One repair-heal tick. Returns true when the repair is complete (health full).
# Subclasses (Vat shared pools) override to redirect healing.
func _repair_heal() -> bool:
	health += REPAIR_AMOUNT * _work_mult()
	if health >= max_health:
		health = max_health
		finish_repair()
		return true
	return false

# --- RPC ---

@rpc("authority", "call_local", "reliable")
func rpc_constructed(bid: int) -> void:
	var bp = Global.BM.get_node_or_null("Blueprint_" + str(bid))
	if bp:
		bp.queue_free()
	set_visible(true)
	# Construction revealed the building — its terminal becomes interactive now.
	Blueprints.set_terminal_collision(self, true)
	state = State.CONSTRUCTED
	# The building now claims its AoE, so recompute on every peer (this RPC is
	# call_local and thus also runs on the server). Set state before recomputing
	# so server and clients produce the identical grid rather than waiting for a
	# snapshot to arrive.
	Global.TM.recompute_aoe()
