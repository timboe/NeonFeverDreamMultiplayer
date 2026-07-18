extends Node3D

class_name BuildingManager

# --- Types ---

enum Type {NONE, MCP_1, MCP_2, MCP_3, MCP_4, GEN, VAT, GARAGE, BEACON, NEST}

# --- Constants ---

const HIDE_DEPTH: float = -50.0

# --- State ---

var building_dictionary: Dictionary = {}
var _next_building_id: int = 0

# --- Blueprints ---

var enabled_blueprints: Dictionary = {}
var disabled_blueprints: Dictionary = {}
var _blueprint_enabled_mat: ShaderMaterial = preload("res://materials/blueprint_enabled.tres")

# --- Lifecycle ---

func _ready() -> void:
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
	for b in building_dictionary.values():
		b.position_terminal()

# --- Blueprint material ---

func apply_blueprint_material(node: Node, mat: ShaderMaterial) -> void:
	for c in node.get_children():
		apply_blueprint_material(c, mat)
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			node.set_surface_override_material(i, mat)
	elif node is CSGCombiner3D:
		node.material_override = mat
	elif node is GPUParticles3D or node is Zapper or node is CollisionShape3D:
		node.queue_free()

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
	var inst: Node3D
	match t:
		Type.MCP_1: inst = $BuildingFactory/MCP_1.duplicate()
		Type.MCP_2: inst = $BuildingFactory/MCP_2.duplicate()
		Type.MCP_3: inst = $BuildingFactory/MCP_3.duplicate()
		Type.MCP_4: inst = $BuildingFactory/MCP_4.duplicate()
		Type.GEN: inst = $BuildingFactory/Generator.duplicate()
		Type.VAT: inst = $BuildingFactory/Vat.duplicate()
		Type.GARAGE: inst = $BuildingFactory/Garage.duplicate()
		Type.BEACON: inst = $BuildingFactory/Beacon.duplicate()
		Type.NEST: inst = $BuildingFactory/Nest.duplicate()
		_: return null
	Blueprints.enable_collision_recursive(inst)
	return inst

func next_building_id() -> int:
	var nbid := _next_building_id
	_next_building_id += 1
	return nbid

func add_to_dict_and_scene(bid: int, b: Building) -> void:
	b.id = bid
	building_dictionary[b.id] = b
	add_child(b)

# --- Placement ---

func place_blueprint(player_number: int, tile: TileElement, type: Type) -> void:
	if not multiplayer.is_server():
		return
	update_blueprint(player_number, tile, type)
	if not can_place_here(tile):
		return
	if not check_under_aoe(player_number, tile):
		return
	if check_access(tile).size() == 0:
		return
	get_node_or_null("/root/World/TileManager").remove_tile_from_pathing(tile)
	var bid := next_building_id()
	rpc("broadcast_place_blueprint", bid, player_number, tile.id, type)

@rpc("authority", "call_local", "reliable")
func broadcast_place_blueprint(bid: int, player_number: int, tid: int, type: Type) -> void:
	var tm = get_node_or_null("/root/World/TileManager")
	var tile = tm.get_tile_by_id(tid)
	var new_building := new_building_instance(type)
	new_building.visible = false
	add_to_dict_and_scene(bid, new_building)
	new_building.global_transform = tile.get_global_transform()
	new_building.global_position.y = 0
	new_building.initialise(player_number, tile)
	new_building.position_terminal()
	new_building.max_health = Config.BUILDING_MAX_HP.get(type, 1.0)
	new_building.health = new_building.max_health
	var new_blueprint = enabled_blueprints[type].duplicate()
	new_blueprint.name = "Blueprint_" + str(bid)
	new_blueprint.visible = true
	apply_blueprint_material(new_blueprint, _blueprint_enabled_mat)
	add_child(new_blueprint)
	new_blueprint.global_transform = tile.get_global_transform()
	new_blueprint.global_position.y = 0
	if player_number == Global.my_player_number:
		enabled_blueprints[type].position.y = HIDE_DEPTH
		var hud = get_tree().get_first_node_in_group("hud")
		hud.build_mode = HUD.Mode.NONE
	if multiplayer.is_server():
		%EnergyManager.recalculate_capacity()
		if type in Config.CONSTRUCTION_COST:
			%JobManager.add_job(player_number, JobManager.Type.CONSTRUCT_BUILDING, tile)

func place_building(pnum: int, tile: TileElement, type: Type) -> void:
	var b := new_building_instance(type)
	add_to_dict_and_scene(next_building_id(), b)
	b.initialise(pnum, tile)
	b.position_terminal()
	b.max_health = Config.BUILDING_MAX_HP.get(type, 1.0)
	b.health = b.max_health
	b.state = b.State.CONSTRUCTED
	if tile.state != TileManager.State.LOWERED:
		tile.set_lowered()
	get_node_or_null("/root/World/TileManager").remove_tile_from_pathing(tile)
	%EnergyManager.recalculate_capacity()

# --- Removal ---

func remove_building(id: int) -> void:
	var b = building_dictionary.get(id)
	if b:
		building_dictionary.erase(id)
		b.queue_free()
		if multiplayer.is_server():
			%EnergyManager.recalculate_capacity()
