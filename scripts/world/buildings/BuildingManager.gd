extends Node3D

class_name BuildingManager

enum Type {NONE, MCP_1, MCP_2, MCP_3, MCP_4, GEN, VAT, GARAGE, BEACON, NEST}

# Multiplayer synchronised
var building_dictionary : Dictionary

var building_being_placed : int = Type.NONE # TODO - move this to the UI
#var placement_player : int = -1

const HIDE_DEPTH = -50

var enabled_blueprints := {}
var disabled_blueprints := {}

func _ready():
	enabled_blueprints[Type.GEN] = $BlueprintsEnabled/Generator
	enabled_blueprints[Type.VAT] = $BlueprintsEnabled/Vat
	#
	disabled_blueprints[Type.GEN] = $BlueprintsDisabled/Generator
	disabled_blueprints[Type.VAT] = $BlueprintsDisabled/Vat

func buildings():
	return building_dictionary.values()

func show_blueprint(type : int):
	building_being_placed = type

func can_place_here(tile : TileElement):
	return (tile.state == TileManager.State.LOWERED)
		
func check_under_aoe(tile : TileElement):
	return (tile.under_aoe[Global.my_player_number] == true)
		
func check_access(tile : TileElement):
	return tile.get_access_tiles()

func update_blueprint(tile : TileElement):
	assert(building_being_placed != Type.NONE)
	if not can_place_here(tile) or tile.building != null:
		enabled_blueprints[building_being_placed].transform.origin.y = HIDE_DEPTH
		disabled_blueprints[building_being_placed].transform.origin.y = HIDE_DEPTH
		return
	if check_under_aoe(tile) and check_access(tile).size() > 0: # and %EnergyManager.can_afford(placement_player, 10.0):
		enabled_blueprints[building_being_placed].transform = tile.get_global_transform()
		enabled_blueprints[building_being_placed].transform.origin.y = -HIDE_DEPTH
		disabled_blueprints[building_being_placed].transform.origin.y = HIDE_DEPTH
	else:
		disabled_blueprints[building_being_placed].transform = tile.get_global_transform()
		disabled_blueprints[building_being_placed].transform.origin.y = -HIDE_DEPTH
		enabled_blueprints[building_being_placed].transform.origin.y = HIDE_DEPTH

func new_building_instance(t : BuildingManager.Type):
	match t:
		BuildingManager.Type.MCP_1: return $BuildingFactory/MCP_1.duplicate()
		BuildingManager.Type.MCP_2: return $BuildingFactory/MCP_2.duplicate()
		BuildingManager.Type.MCP_3: return $BuildingFactory/MCP_1.duplicate()
		BuildingManager.Type.MCP_4: return $BuildingFactory/MCP_1.duplicate()
		BuildingManager.Type.GEN: return $BuildingFactory/MCP_1.duplicate()
		BuildingManager.Type.VAT: return $BuildingFactory/MCP_1.duplicate()
		BuildingManager.Type.GARAGE: return $BuildingFactory/MCP_1.duplicate()
		BuildingManager.Type.BEACON: return $BuildingFactory/MCP_1.duplicate()
		BuildingManager.Type.NEST: return $BuildingFactory/MCP_1.duplicate()
	return null	

func place_blueprint(tile : TileElement):
	assert(building_being_placed != Type.NONE)
	update_blueprint(tile)
	if not can_place_here(tile):
		return
	if tile.building != null:
		return
	if not check_under_aoe(tile):
		return
	#if not %EnergyManager.can_afford(placement_player, 10.0):
		#return
	if check_access(tile).size() == 0:
		return
	#
	var b = new_building_instance(building_being_placed)
	b.initalise(tile, Global.my_player_number, building_being_placed)
	add_to_dict_and_scene(b)
	#
	# Set building before set blueprint (to update monorail correctly)
	var new_blueprint = enabled_blueprints[building_being_placed].duplicate()
	new_blueprint.transform.origin.y = 0
	b.set_blueprint(new_blueprint)
	add_child(new_blueprint)
	#
	enabled_blueprints[building_being_placed].transform.origin.y = HIDE_DEPTH # hide the hover one
	#
	#for z in get_tree().get_nodes_in_group("zoomba"):
		#z.path.resize(0) # Force re-pathing
	#
	#new_building.queue_construction_jobs(placement_player)
	#%CameraManager.add_trauma(1.0, tile.pathing_centre)
	#
	building_being_placed = Type.NONE

# Place a pre-constructed building. Used in setting up the level
# Note: Does NOT call recompute_aoe. Call this once done with place_building
func place_building(tile : TileElement, pnum : int, t : BuildingManager.Type):
	var b = new_building_instance(t)
	b.initialise(tile, pnum, t)
	add_to_dict_and_scene(b)
	b.state = b.State.CONSTRUCTED
	if tile.state != TileManager.State.LOWERED:
		tile.set_lowered()

func add_to_dict_and_scene(b : Building):
	b.id = building_dictionary.size()
	building_dictionary[b.id] = b
	add_child(b)

func is_placing() -> bool:
	return building_being_placed != Type.NONE
