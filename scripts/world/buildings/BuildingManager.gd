extends Node3D

class_name BuildingManager

enum Type {NONE, MCP_1, MCP_2, MCP_3, MCP_4, GEN, VAT, GARAGE, BEACON, NEST}

# Multiplayer synchronised
var building_dictionary : Dictionary

var building_being_placed : int = Type.NONE
var placement_player : int = -1

const HIDE_DEPTH = -50

var enabled_blueprints := {}
var disabled_blueprints := {}
var building_instances := {}

func _ready():
	enabled_blueprints[Type.GEN] = $BlueprintsEnabled/Generator
	enabled_blueprints[Type.VAT] = $BlueprintsEnabled/Vat
	#
	disabled_blueprints[Type.GEN] = $BlueprintsDisabled/Generator
	disabled_blueprints[Type.VAT] = $BlueprintsDisabled/Vat
	#
	building_instances[Type.MCP_1] = $BuildingFactory/MCP_1
	building_instances[Type.MCP_2] = $BuildingFactory/MCP_2
	building_instances[Type.MCP_3] = $BuildingFactory/MCP_2
	building_instances[Type.MCP_4] = $BuildingFactory/MCP_2
	building_instances[Type.GEN] = $BuildingFactory/Generator
	building_instances[Type.VAT] = $BuildingFactory/Vat
	
func show_blueprint(type : int):
	building_being_placed = type

func can_place_here(tile : TileElement):
	return (tile.state == tile.State.LOWERED)
		
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
	var new_building = building_instances[building_being_placed].duplicate()
	new_building.id = building_dictionary.size()
	new_building.type = building_being_placed
	building_dictionary[new_building.id] = new_building
	tile.set_building(new_building) 
	# Set building before set blueprint (to update monorail correctly)
	var new_blueprint = enabled_blueprints[building_being_placed].duplicate()
	new_building.set_blueprint(new_blueprint)
	#
	add_child(new_building)
	add_child(new_blueprint)
	#
	enabled_blueprints[building_being_placed].transform.origin.y = HIDE_DEPTH
	new_blueprint.transform.origin.y = 0
	new_building.transform = tile.get_global_transform()
	new_building.transform.origin.y = 0
	#
	#for z in get_tree().get_nodes_in_group("zoombas"):
		#z.path.resize(0) # Force re-pathing
	#
	#new_building.queue_construction_jobs(placement_player)
	#%CameraManager.add_trauma(1.0, tile.pathing_centre)
	#
	building_being_placed = Type.NONE

# Place a pre-constructed building. Used in setting up the level
func place_building(tile : TileElement, player_number : int, type : int):
	var b : StaticBody3D = building_instances[type].duplicate()
	b.location = tile
	b.player_owner = player_number
	b.state = b.State.CONSTRUCTED
	b.transform = tile.get_global_transform()
	b.transform.origin.y = 0
	tile.set_building(b)
	add_child(b)
	if tile.state != tile.State.LOWERED:
		tile.set_lowered()

func is_placing() -> bool:
	return building_being_placed != Type.NONE
