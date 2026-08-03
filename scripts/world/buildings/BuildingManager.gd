extends Node3D

class_name BuildingManager

# --- Types ---

enum Type {NONE, MCP_1, MCP_2, MCP_3, MCP_4, GEN, VAT, GARAGE, BEACON, NEST}

# --- Constants ---

const HIDE_DEPTH: float = -50.0

# --- State ---

var building_dictionary: Dictionary = {}
var _next_building_id: int = 1

# --- Blueprints ---

var enabled_blueprints: Dictionary = {}
var disabled_blueprints: Dictionary = {}

# --- Empower tracking ---

var _empowered_by_player: Dictionary = {}  # pnum -> Building

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

func can_place_here(tile: TileElement) -> bool:
	return tile.state == TileManager.State.LOWERED and tile.building == null

func check_under_aoe(player_number: int, tile: TileElement) -> bool:
	return player_number in tile.aoe

func check_access(tile: TileElement) -> Array:
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

# --- Blueprint ---

func update_blueprint(player_number: int, tile: TileElement, type: Type) -> void:
	if not can_place_here(tile):
		enabled_blueprints[type].position.y = HIDE_DEPTH
		disabled_blueprints[type].position.y = HIDE_DEPTH
		return
	if check_under_aoe(player_number, tile) and check_access(tile).size() > 0:
		enabled_blueprints[type].global_transform = tile.get_global_transform()
		enabled_blueprints[type].global_position.y = 0
		disabled_blueprints[type].position.y = HIDE_DEPTH
	else:
		disabled_blueprints[type].global_transform = tile.get_global_transform()
		disabled_blueprints[type].global_position.y = 0
		enabled_blueprints[type].position.y = HIDE_DEPTH

# --- Building instances ---

func new_building_instance(t: Type) -> Node3D:
	var node_name := ""
	match t:
		Type.MCP_1: node_name = "MCP_1"
		Type.MCP_2: node_name = "MCP_2"
		Type.MCP_3: node_name = "MCP_3"
		Type.MCP_4: node_name = "MCP_4"
		Type.GEN: node_name = "Generator"
		Type.VAT: node_name = "Vat"
		Type.GARAGE: node_name = "Garage"
		Type.BEACON: node_name = "Beacon"
		Type.NEST: node_name = "Nest"
		_: return null
	var factory_node = $BuildingFactory.get_node_or_null(node_name)
	if not factory_node:
		push_error("BuildingManager: factory node not found: ", node_name)
		return null
	var inst = factory_node.duplicate()
	Blueprints.enable_collision_recursive(inst)
	return inst

func next_building_id() -> int:
	var nbid := _next_building_id
	_next_building_id += 1
	return nbid

func add_to_dict_and_scene(bid: int, b: Building, type: Type) -> void:
	b.id = bid
	b.type = type
	building_dictionary[b.id] = b
	b.name = "Building_" + str(bid)
	add_child(b)

# --- Placement ---

func place_blueprint(player_number: int, tile: TileElement, type: Type) -> void:
	if not multiplayer.is_server():
		return
	if not can_place_here(tile):
		return
	if not check_under_aoe(player_number, tile):
		return
	if check_access(tile).size() == 0:
		return
	update_blueprint(player_number, tile, type)
	Global.TM.remove_tile_from_pathing(tile)
	var bid := next_building_id()
	rpc("broadcast_place_blueprint", bid, player_number, tile.id, type)

@rpc("authority", "call_local", "reliable")
func broadcast_place_blueprint(bid: int, player_number: int, tid: int, type: Type) -> void:
	var tm = Global.TM
	var tile = tm.get_tile_by_id(tid)
	var new_building := new_building_instance(type)
	new_building.visible = false
	add_to_dict_and_scene(bid, new_building, type)
	new_building.global_transform = tile.get_global_transform()
	new_building.global_position.y = 0
	new_building.initialise(player_number, tile)
	# A new building changes access tiles for everyone, so reposition all
	# terminals (the new building is already in building_dictionary).
	position_all_terminals()
	var new_blueprint = enabled_blueprints[type].duplicate()
	new_blueprint.name = "Blueprint_" + str(bid)
	new_blueprint.visible = true
	add_child(new_blueprint)
	new_blueprint.global_transform = tile.get_global_transform()
	new_blueprint.global_position.y = 0
	enabled_blueprints[type].position.y = HIDE_DEPTH
	disabled_blueprints[type].position.y = HIDE_DEPTH
	if player_number == Global.my_player_number:
		var hud = get_tree().get_first_node_in_group("hud")
		hud.build_mode = HUD.Mode.NONE
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
	var b := new_building_instance(type)
	add_to_dict_and_scene(next_building_id(), b, type)
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
		if multiplayer.is_server() and is_instance_valid(b._working_unit):
			b._working_unit.job_finished()
		building_dictionary.erase(id)
		var tile = b.location
		if tile:
			tile.building = null
		b.queue_free()
		Global.TM.recompute_aoe()
		# A neighbour may have just been unblocked (freed access tile) or lost
		# one — re-evaluate every terminal.
		position_all_terminals()
		# Reconnect tile to pathing (reverse of remove_tile_from_pathing)
		if tile and tile.state == TileManager.State.LOWERED:
			var pm = Global.PM
			if pm:
				for n in tile.neighbours:
					if n.state == TileManager.State.LOWERED and n.building == null:
						pm.connect_tiles(tile, n)
