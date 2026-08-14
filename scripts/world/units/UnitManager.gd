extends Node3D

class_name UnitManager

# --- Types ---

enum Type {NONE, AVATAR, ZOOMBA, TANK, AERIAL, VIRUS}

# --- Constants ---

# Unit scenes are instantiated per spawn (same pattern as buildings) — the
# @tool-built models (AerialModel, VirusModel) build fresh in _ready, and
# initialise() re-applies per-player colour/health/groups, so no live factory
# template duplication is needed.
const UNIT_SCENES: Dictionary = {
	Type.ZOOMBA: preload("res://scenes/world/units/Zoomba.tscn"),
	Type.AVATAR: preload("res://scenes/world/units/Avatar.tscn"),
	Type.TANK: preload("res://scenes/world/units/Tank.tscn"),
	Type.AERIAL: preload("res://scenes/world/units/Aerial.tscn"),
	Type.VIRUS: preload("res://scenes/world/units/Virus.tscn"),
}

# --- State ---

var unit_dictionary: Dictionary # int (id) -> Unit
var _next_unit_id: int = 1

# Per-player, per-type unit counts, maintained event-driven in _spawn_unit /
# rpc_remove_unit (both call_local authority RPCs, so the cache stays
# consistent on every peer). Replaces O(units) scans that ran every frame
# from production buildings and terminal HUDs.
var _player_type_counts: Dictionary = {} # pnum -> {type: int}

# --- Lifecycle ---

func _ready() -> void:
	Global.UM = self

# --- Accessors ---

func units() -> Array:
	return unit_dictionary.values()

func unit_count(pnum: int, type: Type) -> int:
	var by_type = _player_type_counts.get(pnum)
	if by_type == null:
		return 0
	return by_type.get(type, 0)

func _count_add(u: Unit) -> void:
	var by_type = _player_type_counts.get(u.player_owner)
	if by_type == null:
		by_type = {}
		_player_type_counts[u.player_owner] = by_type
	by_type[u.type] = by_type.get(u.type, 0) + 1

func _count_remove(u: Unit) -> void:
	var by_type = _player_type_counts.get(u.player_owner)
	if by_type == null:
		return


	var c: int = by_type.get(u.type, 0)
	if c <= 1:
		by_type.erase(u.type)
	else:
		by_type[u.type] = c - 1

# --- Spawning ---

# Note: Ownership of the unit is stored as unit.player_owner
func _spawn_unit(uid: int, type: Type, building: Building) -> void:
	var scene: PackedScene = UNIT_SCENES.get(type)
	if not scene:
		push_error("UnitManager._spawn_unit: unknown type ", type)
		return
	var u := scene.instantiate() as Unit
	_add_to_dict_and_scene(uid, u)
	u.initialise(building)
	_count_add(u)

func next_unit_id() -> int:
	var nuid := _next_unit_id
	_next_unit_id += 1
	return nuid

func _add_to_dict_and_scene(uid: int, u: Unit) -> void:
	u.id = uid
	unit_dictionary[u.id] = u
	add_child(u)

@rpc("authority", "call_local")
func rpc_spawn_unit(uid: int, type: int, building_id: int) -> void:
	var building = Global.BM.get_building_by_id(building_id)
	if building:
		_spawn_unit(uid, type as Type, building)

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
		unit._kill_combat_hold()
		var j_id = unit.job["id"]
		unit.job = {}
		if unit.move_tween and unit.move_tween.is_valid():
			unit.move_tween.kill()
		unit.move_tween = null
		Global.JM.abandon_job(j_id)
	else:
		if unit.move_tween and unit.move_tween.is_valid():
			unit.move_tween.kill()
		unit.move_tween = null
	# This path bypasses unit.abandon_job() — drop the squad flag explicitly.
	if unit.rallied:
		unit.set_rallied(false)
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
		if u is Avatar:
			Global.GM.clear_avatar_snapshots(u.player_owner)
			# If the local player's avatar died while in FPS, snap back to the RTS camera.
			if u.player_owner == Global.my_player_number:
				Global.VM.exit_fps_immediate()
			# A dead avatar can't keep empowering — clear the player's empower.
			# Server-only: the _empowered_by_player dict is server state, and
			# clear_empowered_for_player broadcasts rpc_set_empowered(false) to
			# every peer so the beam (and buffs) drop everywhere at once.
			if multiplayer.is_server():
				Global.BM.clear_empowered_for_player(u.player_owner)
				# DESIGN: the rally lasts until the avatar dies — disband now.
				Global.JM.cancel_player_rally(u.player_owner)
		# Unit debris: its own meshes become physics chunks blasted from the unit
		# (unit scale, no particle burst). This RPC is call_local so every peer
		# spawns the same effect simultaneously — cosmetic, no sync. Cloaked
		# VIRUS deaths stay invisible (no reveal).
		if not (u is Virus and u.cloaked):
			DestructionFX.spawn_unit(u)
		_count_remove(u)
		u.queue_free()

# One-shot rally shockwave at the avatar — cosmetic, spawned on every peer via
# the call_local RPC (same pattern as the destruction FX).
@rpc("authority", "call_local")
func rpc_rally_fx(pnum: int, origin_x: float, origin_y: float, origin_z: float, radius: float) -> void:
	var ph := get_node_or_null("/root/World/ProjectilesHolder")
	if not ph:
		return
	RallyRing.spawn(ph, Vector3(origin_x, origin_y, origin_z), radius, pnum)
