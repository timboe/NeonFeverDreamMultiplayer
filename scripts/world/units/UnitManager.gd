extends Node3D

class_name UnitManager

enum Type {NONE, AVATAR, ZOOMBA, TANK, AERIAL_PATROL, AERIAL_SCOUT, VIRUS}

# Multiplayer synchronised
var unit_dictionary : Dictionary

var _next_unit_id: int = 0

func _ready() -> void:
	pass # Replace with function body.
	
func units() -> Array:
	return unit_dictionary.values()
	
func unit_count(pnum : int, type : Type) -> int:
	var c := 0
	for u in units():
		if u.building.player_owner == pnum and u.type == type:
			c += 1
	return c

func spawn_unit(type : Type, building : Building) -> void:
	var u = null
	match type:
		Type.ZOOMBA: u = $UnitFactory/Zoomba.duplicate()
		Type.AVATAR: u = $UnitFactory/Avatar.duplicate()
	add_to_dict_and_scene(u)
	u.initialise(building)
	
func add_to_dict_and_scene(u : Unit) -> void:
	u.id = _next_unit_id
	_next_unit_id += 1
	unit_dictionary[u.id] = u
	add_child(u)

@rpc("authority", "call_local")
func rpc_spawn_unit(type: int, building_id: int):
	var bm = get_node_or_null("%BuildingManager")
	if not bm:
		return
	var building = bm.get_building_by_id(building_id)
	if building:
		spawn_unit(type as Type, building)

func displace_units_on_tile(tile : TileElement):
	var displaced : Array = []
	for u in units():
		if u.location == tile:
			displaced.append(u)
	for u in displaced:
		_displace_unit(u, tile)

func _displace_unit(unit : Unit, tile : TileElement):
	if not unit.job.is_empty():
		unit.abandon_job()
	if unit.move_tween and unit.move_tween.is_valid():
		unit.move_tween.kill()
	# Find first adjacent valid tile
	var best_tile : TileElement = null
	for n in tile.get_access_tiles():
		best_tile = n
		break
	if best_tile:
		unit.location = best_tile
		unit.global_position = best_tile.pathing_centre
	else:
		rpc("rpc_remove_unit", unit.id)

@rpc("authority", "call_local")
func rpc_remove_unit(unit_id: int):
	var u = unit_dictionary.get(unit_id)
	if u:
		unit_dictionary.erase(unit_id)
		u.queue_free()
