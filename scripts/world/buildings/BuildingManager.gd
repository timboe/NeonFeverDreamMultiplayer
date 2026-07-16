extends Node3D

class_name BuildingManager

enum Type {NONE, MCP_1, MCP_2, MCP_3, MCP_4, GEN, VAT, GARAGE, BEACON, NEST}

# Multiplayer synchronised
var building_dictionary : Dictionary

var _next_building_id: int = 0

const HIDE_DEPTH = -50

var enabled_blueprints := {}
var disabled_blueprints := {}

var _blueprint_enabled_mat : ShaderMaterial = preload("res://materials/blueprint_enabled.tres")

func apply_blueprint_material(node, mat : ShaderMaterial):
	for c in node.get_children():
		apply_blueprint_material(c, mat)
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			node.set_surface_override_material(i, mat)
	elif node is CSGCombiner3D:
		node.material_override = mat
	elif node is GPUParticles3D or node is Zapper:
		node.queue_free()

func _ready():
	enabled_blueprints[Type.GEN] = $BlueprintsEnabled/Generator
	enabled_blueprints[Type.VAT] = $BlueprintsEnabled/Vat
	enabled_blueprints[Type.GARAGE] = $BlueprintsEnabled/Garage
	enabled_blueprints[Type.BEACON] = $BlueprintsEnabled/Beacon
	enabled_blueprints[Type.NEST] = $BlueprintsEnabled/Nest
	#
	disabled_blueprints[Type.GEN] = $BlueprintsDisabled/Generator
	disabled_blueprints[Type.VAT] = $BlueprintsDisabled/Vat
	disabled_blueprints[Type.GARAGE] = $BlueprintsDisabled/Garage
	disabled_blueprints[Type.BEACON] = $BlueprintsDisabled/Beacon
	disabled_blueprints[Type.NEST] = $BlueprintsDisabled/Nest

func buildings():
	return building_dictionary.values()

func can_place_here(tile : TileElement):
	return (tile.state == TileManager.State.LOWERED && tile.building == null)
		
func check_under_aoe(player_number : int, tile : TileElement):
	return (player_number in tile.aoe)
		
func check_access(tile : TileElement):
	return tile.get_access_tiles()

func update_blueprint(player_number : int, tile : TileElement, type : int):
	if not can_place_here(tile):
		enabled_blueprints[type].transform.origin.y = HIDE_DEPTH
		disabled_blueprints[type].transform.origin.y = HIDE_DEPTH
		return
	if check_under_aoe(player_number, tile) and check_access(tile).size() > 0:
		enabled_blueprints[type].global_transform = tile.get_global_transform()
		enabled_blueprints[type].global_position.y = 0
		disabled_blueprints[type].transform.origin.y = HIDE_DEPTH
	else:
		disabled_blueprints[type].global_transform = tile.get_global_transform()
		disabled_blueprints[type].global_position.y = 0
		enabled_blueprints[type].transform.origin.y = HIDE_DEPTH

func new_building_instance(t : BuildingManager.Type):
	match t:
		BuildingManager.Type.MCP_1: return $BuildingFactory/MCP_1.duplicate()
		BuildingManager.Type.MCP_2: return $BuildingFactory/MCP_2.duplicate()
		BuildingManager.Type.MCP_3: return $BuildingFactory/MCP_3.duplicate()
		BuildingManager.Type.MCP_4: return $BuildingFactory/MCP_4.duplicate()
		BuildingManager.Type.GEN: return $BuildingFactory/Generator.duplicate()
		BuildingManager.Type.VAT: return $BuildingFactory/Vat.duplicate()
		BuildingManager.Type.GARAGE: return $BuildingFactory/Garage.duplicate()
		BuildingManager.Type.BEACON: return $BuildingFactory/Beacon.duplicate()
		BuildingManager.Type.NEST: return $BuildingFactory/Nest.duplicate()
	return null	

# This is a server only function
func place_blueprint(player_number : int, tile : TileElement, type : Type):
	if not multiplayer.is_server():
		return
	update_blueprint(player_number, tile, type)
	if not can_place_here(tile): # Tile needs to be lowered and not have another building on it
		return
	if not check_under_aoe(player_number, tile): # Tile needs to be under the player's AoE
		return
	if check_access(tile).size() == 0: # Tile must have at least one vantage point
		return
	# Pathing grid change only needs to happen on server
	get_node_or_null("/root/World/TileManager").remove_tile_from_pathing(tile)
	var bid = get_inc_next_building_id()
	rpc("broadcast_place_blueprint", bid, player_number, tile.id, type)

# Server has validated the request is all OK. Place using server-specified ID
@rpc("authority", "call_local", "reliable")
func broadcast_place_blueprint(bid : int, player_number : int, tid : int, type : Type):
	var tm = get_node_or_null("/root/World/TileManager")
	var tile = tm.get_tile_by_id(tid)
	var new_building = new_building_instance(type)
	new_building.visible = false
	add_to_dict_and_scene(bid, new_building)
	new_building.global_transform = tile.get_global_transform()
	new_building.global_position.y = 0
	new_building.initialise(player_number, tile)
	#
	var new_blueprint = enabled_blueprints[type].duplicate()
	new_blueprint.name = "Blueprint_" + str(bid)
	new_blueprint.visible = true
	apply_blueprint_material(new_blueprint, _blueprint_enabled_mat)
	add_child(new_blueprint)
	new_blueprint.global_transform = tile.get_global_transform()
	new_blueprint.global_position.y = 0
	# Only if I happen to be the person who is placing this do we reset these UI elements
	if player_number == Global.my_player_number:
		enabled_blueprints[type].transform.origin.y = HIDE_DEPTH # hide the hover one
		var hud = get_tree().get_first_node_in_group("hud")
		hud.build_mode = HUD.Mode.NONE
	if multiplayer.is_server():
		%EnergyManager.recalculate_capacity()
		if type in Config.CONSTRUCTION_COST:
			%JobManager.add_job(player_number, JobManager.Type.CONSTRUCT_BUILDING, tile)

# Place a pre-constructed building. Used in setting up thhe level
# Note: Does NOT call recompute_aoe. Call this once done with place_building
func place_building(pnum : int, tile : TileElement, type : BuildingManager.Type):
	var b = new_building_instance(type)
	add_to_dict_and_scene(get_inc_next_building_id(), b)
	b.initialise(pnum, tile)
	b.state = b.State.CONSTRUCTED
	if tile.state != TileManager.State.LOWERED:
		tile.set_lowered()
	get_node_or_null("/root/World/TileManager").remove_tile_from_pathing(tile)
	%EnergyManager.recalculate_capacity()

func get_inc_next_building_id() -> int:
	var nbid := _next_building_id
	_next_building_id += 1
	return nbid

func add_to_dict_and_scene(bid : int, b : Building):
	b.id = bid
	building_dictionary[b.id] = b
	add_child(b)

func remove_building(id: int):
	var b = building_dictionary.get(id)
	if b:
		building_dictionary.erase(id)
		b.queue_free()
		if multiplayer.is_server():
			%EnergyManager.recalculate_capacity()

func get_building_by_id(id: int) -> Building:
	return building_dictionary.get(id)
