extends Node3D

class_name UnitManager

enum Type {NONE, AVATAR, ZOOMBA, TANK, AERIAL_PATROL, AERIAL_SCOUT, VIRUS}

var unit_dictionary: Dictionary # int (id) -> Unit
var _next_unit_id: int = 0

# --- Accessors ---

func units() -> Array:
	return unit_dictionary.values()

func unit_count(pnum: int, type: Type) -> int:
	var c := 0
	for u in units():
		if u.player_owner == pnum and u.type == type:
			c += 1
	return c

# --- Spawning ---

# Note: Ownership of the unit is stored as unit.player_owner
func spawn_unit(uid: int, type: Type, building: Building) -> void:
	var u = null
	match type:
		Type.ZOOMBA: u = $UnitFactory/Zoomba.duplicate()
		Type.AVATAR: u = $UnitFactory/Avatar.duplicate()
		_: push_error("UnitManager.spawn_unit: unknown type ", type); return
	add_to_dict_and_scene(uid, u)
	u.initialise(building)

func next_unit_id() -> int:
	var nuid := _next_unit_id
	_next_unit_id += 1
	return nuid

func add_to_dict_and_scene(uid: int, u: Unit) -> void:
	u.id = uid
	unit_dictionary[u.id] = u
	add_child(u)

@rpc("authority", "call_local")
func rpc_spawn_unit(uid: int, type: int, building_id: int) -> void:
	var bm = get_node_or_null("%BuildingManager")
	if not bm:
		return
	var building = bm.get_building_by_id(building_id)
	if building:
		spawn_unit(uid, type as Type, building)

# --- Displacement ---

func displace_units_on_tile(tile: TileElement) -> void:
	var displaced: Array = []
	for u in units():
		if u.location == tile:
			displaced.append(u)
	for u in displaced:
		_displace_unit(u, tile)

func _displace_unit(unit: Unit, tile: TileElement) -> void:
	if not unit.job.is_empty():
		# Clean up job without calling idle_callback (we'll call it once after displacement)
		if unit.state == Unit.State.WORKING:
			unit._cleanup_working_state()
		unit.state = Unit.State.IDLE
		var j_id = unit.job["id"]
		unit.job = {}
		if unit.move_tween and unit.move_tween.is_valid():
			unit.move_tween.kill()
		unit.move_tween = null
		var jm = get_node_or_null("/root/World/JobManager")
		if jm:
			jm.abandon_job(j_id)
	else:
		if unit.move_tween and unit.move_tween.is_valid():
			unit.move_tween.kill()
		unit.move_tween = null
	# Find first adjacent valid tile
	var best_tile: TileElement = null
	for n in tile.get_access_tiles():
		best_tile = n
		break
	if best_tile:
		unit.location = best_tile
		unit.global_position = best_tile.pathing_centre
		unit.idle_callback()
	else:
		rpc("rpc_remove_unit", unit.id)

@rpc("authority", "call_local")
func rpc_remove_unit(unit_id: int) -> void:
	var u = unit_dictionary.get(unit_id)
	if u:
		if not u.job.is_empty():
			u.abandon_job()
		unit_dictionary.erase(unit_id)
		u.queue_free()
