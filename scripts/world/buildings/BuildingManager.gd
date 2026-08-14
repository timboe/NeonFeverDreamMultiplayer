extends Node3D

class_name BuildingManager

# --- Types ---

enum Type {NONE, MCP_1, MCP_2, MCP_3, MCP_4, GEN, VAT, GARAGE, BEACON, NEST}

# --- Constants ---

const HIDE_DEPTH: float = -50.0

# Preloaded building scenes, instantiated per placement. Replaces duplicating
# the live factory templates (the old BuildingFactory node is removed):
# Node.duplicate() on a script-active subtree (instanced BuildingHUD children
# removed/freed by _setup_hud on every placement) intermittently trips the
# engine's children-cache accounting ("Index p_index out of bounds" in
# get_child()). instantiate() builds from packed data and is immune to
# live-tree state.
const BUILDING_SCENES: Dictionary = {
	Type.MCP_1: preload("res://scenes/world/buildings/MCP_1.tscn"),
	Type.MCP_2: preload("res://scenes/world/buildings/MCP_2.tscn"),
	Type.MCP_3: preload("res://scenes/world/buildings/MCP_3.tscn"),
	Type.MCP_4: preload("res://scenes/world/buildings/MCP_4.tscn"),
	Type.GEN: preload("res://scenes/world/buildings/Generator.tscn"),
	Type.VAT: preload("res://scenes/world/buildings/Vat.tscn"),
	Type.GARAGE: preload("res://scenes/world/buildings/Garage.tscn"),
	Type.BEACON: preload("res://scenes/world/buildings/Beacon.tscn"),
	Type.NEST: preload("res://scenes/world/buildings/Nest.tscn"),
}

# --- State ---

var building_dictionary: Dictionary = {}
var _next_id: int = 1

# --- Blueprints ---

var enabled_blueprints: Dictionary = {}
var disabled_blueprints: Dictionary = {}

# --- Empower tracking ---

var _empowered_by_player: Dictionary = {}  # pnum -> Building

# --- Hover state ---

# Building the mouse is currently over in RTS mode (for the main HUD tooltip).
var hovered_building: Building = null

# Building currently showing the remove-mode "doomed" ghost (null = none).
var _remove_ghost_building: Building = null
var _remove_ghost_captured: Array = []

func set_empowered_for_player(pnum: int, building: Building) -> void:
	var prev = _empowered_by_player.get(pnum)
	if prev and prev != building and is_instance_valid(prev):
		prev.is_empowered = false
		prev.rpc("rpc_set_empowered", false)
	building.is_empowered = true
	building.rpc("rpc_set_empowered", true)
	_empowered_by_player[pnum] = building

func clear_empowered_for_player(pnum: int) -> void:
	var prev = _empowered_by_player.get(pnum)
	if prev and is_instance_valid(prev):
		prev.is_empowered = false
		prev.rpc("rpc_set_empowered", false)
	_empowered_by_player.erase(pnum)

# The type of building the player currently has empowered (NONE if none).
# Army-wide empower buffs (Garage/Beacon/Nest) key off this; instance buffs
# (Generator radius, Vat capacity, MCP) read the building's own is_empowered.
func empowered_type(pnum: int) -> Type:
	var b: Building = _empowered_by_player.get(pnum)
	if b and is_instance_valid(b):
		return b.type
	return Type.NONE

# --- VIRUS infection (per DESIGN) ---

# Whether the player owns any infected building of the given type. Drives the
# type-wide infected-Garage penalties (TANK patrol speed, AA fire rate).
func player_has_infected_type(pnum: int, type: Type) -> bool:
	for b in building_dictionary.values():
		if b.player_owner == pnum and b.type == type and not b.infections.is_empty():
			return true
	return false

# Applies (or refreshes) an infection on a building. Returns false when the
# building is immune (currently empowered). Re-infecting an already-infected
# building from the same attacker refreshes: remaining time extends by the base
# duration x new strength and strength is replaced (per DESIGN, agreed update).
# A Vat infection cascades to its whole shared-health pool (adjacency chain),
# skipping empowered pool members.
func infect_building(attacker: int, building: Building, strength: float) -> bool:
	if building.is_empowered:
		return false
	var first := not building.infections.has(attacker)
	_apply_infection_entry(building, attacker, strength)
	if building is Vat:
		var master: Vat = building.pool_master if building.pool_master != null else building
		for m in master.pool_members:
			if m == building or m.is_empowered:
				continue
			_apply_infection_entry(m, attacker, strength)
	if first:
		var text := "Your " + building_type_name(building.type) + " has been infected by " + _player_name(attacker) + "!"
		var loc := building.location.pathing_centre if building.location else Vector3.ZERO
		Global.NM.rpc("rpc_add_job_notification", building.player_owner, "infected", text, loc.x, loc.y, loc.z)
	return true

func _apply_infection_entry(b: Building, attacker: int, strength: float) -> void:
	var entry: Dictionary = b.infections.get(attacker, {})
	if entry.is_empty():
		b.infections[attacker] = {"strength": strength, "remaining": Config.VIRUS_INFECTION_DURATION}
	else:
		entry["strength"] = strength
		entry["remaining"] = float(entry["remaining"]) + Config.VIRUS_INFECTION_DURATION * strength
	b._update_infection_visual()

# Avatar cure: removes every infection from the building. Curing one Vat in a
# shared-health pool cures the whole connected chain (the infection cascaded,
# so the cure does too).
func cure_building(building: Building) -> void:
	var targets: Array[Building] = [building]
	if building is Vat:
		var master: Vat = building.pool_master if building.pool_master != null else building
		targets.append_array(master.pool_members)
	for b in targets:
		if is_instance_valid(b) and not b.infections.is_empty():
			b.infections.clear()
			b._update_infection_visual()

# Per-attacker removal, used when an infection expires on its own.
func cure_infection(building: Building, attacker: int) -> void:
	if not is_instance_valid(building):
		return
	if building.infections.erase(attacker):
		building._update_infection_visual()

func building_type_name(t: Type) -> String:
	match t:
		Type.GEN: return "Generator"
		Type.VAT: return "Vat"
		Type.GARAGE: return "Garage"
		Type.BEACON: return "Beacon"
		Type.NEST: return "Nest"
		_: return "MCP"

func _player_name(pnum: int) -> String:
	if pnum >= 1 and pnum <= Config.PLAYER_NAMES.size():
		return Config.PLAYER_NAMES[pnum - 1]
	return "Player " + str(pnum)

# --- Lifecycle ---

func _ready() -> void:
	Global.BM = self
	enabled_blueprints[Type.GEN] = $BlueprintsEnabled/Generator
	enabled_blueprints[Type.VAT] = $BlueprintsEnabled/Vat
	enabled_blueprints[Type.GARAGE] = $BlueprintsEnabled/Garage
	enabled_blueprints[Type.BEACON] = $BlueprintsEnabled/Beacon
	enabled_blueprints[Type.NEST] = $BlueprintsEnabled/Nest
	disabled_blueprints[Type.GEN] = $BlueprintsDisabled/Generator
	disabled_blueprints[Type.VAT] = $BlueprintsDisabled/Vat
	disabled_blueprints[Type.GARAGE] = $BlueprintsDisabled/Garage
	disabled_blueprints[Type.BEACON] = $BlueprintsDisabled/Beacon
	disabled_blueprints[Type.NEST] = $BlueprintsDisabled/Nest

# --- Queries ---

func buildings() -> Array:
	return building_dictionary.values()

func get_building_by_id(id: int) -> Building:
	return building_dictionary.get(id)

func _can_place_here(tile: TileElement) -> bool:
	return tile.state == TileManager.State.LOWERED and tile.building == null

func _check_under_aoe(player_number: int, tile: TileElement) -> bool:
	return player_number in tile.aoe

func _check_access(tile: TileElement) -> Array:
	return tile.get_access_tiles()

func position_all_terminals() -> void:
	# Resolve each player's MCP tile once instead of per building.
	var mcp_by_player: Dictionary = {}
	for b in building_dictionary.values():
		var pnum: int = b.player_owner
		if not mcp_by_player.has(pnum):
			var mcp_nodes := get_tree().get_nodes_in_group("mcp_player" + str(pnum))
			mcp_by_player[pnum] = mcp_nodes[0].location if not mcp_nodes.is_empty() else null
		b.position_terminal(mcp_by_player[pnum])

# A tile's state change can only affect terminals of buildings whose location is
# adjacent to it (their access tiles / terminal spots changed). Reposition just
# those instead of all buildings — per toggle, this is a handful of buildings
# instead of every one (each with a 25-vertex-pair _compute_edge scan).
func position_terminals_around(tile: TileElement) -> void:
	var mcp_by_player: Dictionary = {}
	for n in tile.neighbours:
		var b: Building = n.building
		if b == null:
			continue
		var pnum: int = b.player_owner
		if not mcp_by_player.has(pnum):
			var mcp_nodes := get_tree().get_nodes_in_group("mcp_player" + str(pnum))
			mcp_by_player[pnum] = mcp_nodes[0].location if not mcp_nodes.is_empty() else null
		b.position_terminal(mcp_by_player[pnum])

# --- Blueprint ---

func _enabled_blueprint_material() -> ShaderMaterial:
	var bp = get_node_or_null("BlueprintsEnabled")
	if bp:
		return bp.blueprint_enabled
	return null

func update_blueprint(player_number: int, tile: TileElement, type: Type) -> void:
	if not _can_place_here(tile):
		enabled_blueprints[type].position.y = HIDE_DEPTH
		disabled_blueprints[type].position.y = HIDE_DEPTH
		return
	if _check_under_aoe(player_number, tile) and _check_access(tile).size() > 0:
		enabled_blueprints[type].global_transform = tile.get_global_transform()
		enabled_blueprints[type].global_position.y = 0
		disabled_blueprints[type].position.y = HIDE_DEPTH
	else:
		disabled_blueprints[type].global_transform = tile.get_global_transform()
		disabled_blueprints[type].global_position.y = 0
		enabled_blueprints[type].position.y = HIDE_DEPTH

# --- Remove-mode hover ghost ---

func is_remove_ghost_for(b: Building) -> bool:
	return _remove_ghost_building == b

# Remove-mode hover, painted in place so the hovered body never disappears
# (hiding it would cancel the mouse hover and flicker):
# - a CONSTRUCTED building has its own meshes swapped to the disabled (red)
#   blueprint material, reverted on exit;
# - a BLUEPRINT/UNDER_CONSTRUCTION building is invisible, so its placement
#   ghost ("Blueprint_N") is switched from the enabled material to the
#   disabled one (it is made pickable by set_remove_mode).
# Never shown on MCPs (no ghost type).
func show_remove_ghost(b: Building) -> void:
	if b == _remove_ghost_building:
		return
	hide_remove_ghost()
	# Never paint MCPs — there is no blueprint template for them (and they
	# can't be removed server-side).
	if b.type not in disabled_blueprints:
		return
	if b.state == Building.State.CONSTRUCTED:
		_remove_ghost_building = b
		_remove_ghost_captured.clear()
		Blueprints.capture_mesh_materials(b, _remove_ghost_captured)
		Blueprints.apply_mesh_material(b, _disabled_blueprint_material())
	else:
		var bp := get_node_or_null("Blueprint_" + str(b.id))
		if bp == null:
			return
		_remove_ghost_building = b
		Blueprints.apply_blueprint_material(bp, _disabled_blueprint_material())

func hide_remove_ghost() -> void:
	var b := _remove_ghost_building
	_remove_ghost_building = null
	# Swap, don't clear: captured is a reference, so clearing the member after
	# aliasing it would empty the restore list before restore runs.
	var captured := _remove_ghost_captured
	_remove_ghost_captured = []
	if b == null or not is_instance_valid(b):
		return
	if b.state == Building.State.CONSTRUCTED:
		Blueprints.restore_mesh_materials(captured)
	else:
		var bp := get_node_or_null("Blueprint_" + str(b.id))
		if bp:
			Blueprints.apply_blueprint_material(bp, _enabled_blueprint_material())

# While remove mode is active, give each placement ghost (BLUEPRINT /
# UNDER_CONSTRUCTION stand-in) a pickable collider so it can be hovered and
# clicked; everything else stays non-pickable as usual. The Terminal subtree is
# skipped — its colliders must stay off until construction so it isn't an
# invisible wall on the access tile.
func set_remove_mode(active: bool) -> void:
	hide_remove_ghost()
	for child in get_children():
		if not String(child.name).begins_with("Blueprint_"):
			continue
		# Building scene roots ship input_ray_pickable = false (except
		# Generator) — the ghost must be explicitly pickable to receive
		# hover/click events; collision still gates them in normal modes.
		child.input_ray_pickable = active
		if active:
			_enable_collision_except_terminal(child)
		else:
			Blueprints.disable_collision_recursive(child)

func _enable_collision_except_terminal(node: Node) -> void:
	if node.name == "Terminal":
		return
	for c in node.get_children():
		_enable_collision_except_terminal(c)
	if node is CollisionShape3D:
		node.disabled = false

func _disabled_blueprint_material() -> ShaderMaterial:
	var bp = get_node_or_null("BlueprintsDisabled")
	if bp:
		return bp.blueprint_disabled
	return null

# --- Building instances ---

func _new_building_instance(t: Type) -> Node3D:
	var scene: PackedScene = BUILDING_SCENES.get(t)
	if not scene:
		return null
	var inst := scene.instantiate() as Node3D
	Blueprints.enable_collision_recursive(inst)
	return inst

func _next_building_id() -> int:
	var nbid := _next_id
	_next_id += 1
	return nbid

func _add_to_dict_and_scene(bid: int, b: Building, type: Type) -> void:
	b.id = bid
	b.type = type
	building_dictionary[b.id] = b
	b.name = "Building_" + str(bid)
	add_child(b)

# --- Placement ---

func place_blueprint(player_number: int, tile: TileElement, type: Type) -> void:
	if not multiplayer.is_server():
		return
	if not _can_place_here(tile):
		return
	if not _check_under_aoe(player_number, tile):
		return
	if _check_access(tile).size() == 0:
		return
	update_blueprint(player_number, tile, type)
	Global.TM.remove_tile_from_pathing(tile)
	var bid := _next_building_id()
	rpc("rpc_broadcast_place_blueprint", bid, player_number, tile.id, type)

@rpc("authority", "call_local", "reliable")
func rpc_broadcast_place_blueprint(bid: int, player_number: int, tid: int, type: Type) -> void:
	var tm = Global.TM
	var tile = tm.get_tile_by_id(tid)
	var new_building := _new_building_instance(type)
	new_building.visible = false
	# Invisible until constructed — its terminal must not collide (invisible
	# wall on an access tile). rpc_constructed re-enables it on reveal.
	Blueprints.set_terminal_collision(new_building, false)
	_add_to_dict_and_scene(bid, new_building, type)
	new_building.global_transform = tile.get_global_transform()
	new_building.global_position.y = 0
	new_building.initialise(player_number, tile)
	# A new building changes access tiles for everyone, so reposition all
	# terminals (the new building is already in building_dictionary).
	position_all_terminals()
	var new_blueprint := _new_building_instance(type)
	Blueprints.prepare_ghost(new_blueprint, _enabled_blueprint_material())
	new_blueprint.name = "Blueprint_" + str(bid)
	new_blueprint.visible = true
	add_child(new_blueprint)
	new_blueprint.global_transform = tile.get_global_transform()
	new_blueprint.global_position.y = 0
	# The ghost is a Building too — give it the placement identity so it can
	# serve as the hover/click target in remove mode (set_remove_mode enables
	# its collision then). Its own hover/click handlers re-route everything
	# through the HUD's remove-mode guards, so they no-op in normal modes.
	new_blueprint.id = bid
	new_blueprint.player_owner = player_number
	new_blueprint.type = type
	new_blueprint.input_ray_pickable = true
	new_blueprint.mouse_entered.connect(new_blueprint._on_hover_entered)
	new_blueprint.mouse_exited.connect(new_blueprint._on_hover_exited)
	new_blueprint.input_event.connect(new_blueprint._on_StaticBody_input_event)
	enabled_blueprints[type].position.y = HIDE_DEPTH
	disabled_blueprints[type].position.y = HIDE_DEPTH
	if player_number == Global.my_player_number:
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.clear_build_mode()
	Global.TM.recompute_aoe()
	if multiplayer.is_server():
		if type in Config.CONSTRUCTION_COST:
			Global.JM.add_job(player_number, JobManager.Type.CONSTRUCT_BUILDING, tile)
		# Cancel any pending toggle jobs on this tile
		for job in Global.JM.jobs_dict.values():
			if job["type"] == JobManager.Type.TOGGLE_TILE and job["target"] == tile:
				Global.JM.remove_job(job["id"])
				break

# Skips all construction phases, used during level setup
func place_building(pnum: int, tile: TileElement, type: Type) -> void:
	var b := _new_building_instance(type)
	_add_to_dict_and_scene(_next_building_id(), b, type)
	b.initialise(pnum, tile)
	b.position_terminal()
	b.state = b.State.CONSTRUCTED
	if tile.state != TileManager.State.LOWERED:
		tile.set_lowered()
	Global.TM.remove_tile_from_pathing(tile)
	Global.TM.recompute_aoe()

# --- Removal ---

@rpc("authority", "call_local")
func rpc_remove_building(id: int) -> void:
	var b = building_dictionary.get(id)
	if b:
		# Read identity before the node is freed at the end of the function.
		var was_mcp: bool = b is MCP and b.state == Building.State.CONSTRUCTED
		var owner: int = b.player_owner
		if multiplayer.is_server() and is_instance_valid(b.working_unit):
			b.working_unit.job_finished()
		building_dictionary.erase(id)
		var tile = b.location
		if tile:
			tile.building = null
		# A BLUEPRINT-state removal leaves its placement ghost behind (the
		# normal destruction path already freed it via rpc_constructed).
		var bp := get_node_or_null("Blueprint_" + str(id))
		if bp:
			bp.queue_free()
		# CONSTRUCTED buildings leave debris: their own meshes become physics
		# chunks blasted out from the building centre + a particle burst. This
		# RPC is call_local so every peer spawns the same effect simultaneously —
		# purely cosmetic, no sync needed. Invisible blueprints/under-construction
		# buildings skip it.
		if b.state == Building.State.CONSTRUCTED:
			DestructionFX.spawn(b)
		b.queue_free()
		Global.TM.recompute_aoe()
		# A neighbour may have just been unblocked (freed access tile) or lost
		# one — re-evaluate every terminal.
		position_all_terminals()
		# Reconnect tile to pathing (reverse of remove_tile_from_pathing)
		if tile and tile.state == TileManager.State.LOWERED:
			for n in tile.neighbours:
				if n.state == TileManager.State.LOWERED and n.building == null:
					Global.PM.connect_tiles(tile, n)
		# Manual removal (not combat destruction) un-selects the remove button,
		# mirroring rpc_broadcast_place_blueprint's clear_build_mode on placement.
		if b.player_owner == Global.my_player_number:
			var hud = get_tree().get_first_node_in_group("hud")
			if hud and hud.is_removing():
				hud.clear_build_mode()
		# A destroyed MCP eliminates its player: the rest of their buildings and
		# units are removed too, and if only one MCP remains the game is over.
		# Server-only — the removals below are call_local RPCs synced to peers.
		if multiplayer.is_server() and was_mcp:
			Global.GM.on_player_eliminated(owner)
