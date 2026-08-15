extends Node3D

class_name JobManager

# --- Types ---

enum Type {NONE, CONSTRUCT_BUILDING, REPAIR_BUILDING, TOGGLE_TILE, CONSUME_ZOOMBA, COMBAT_PERSUE, ATTACK}
enum Orders {NONE, PATROL, ATTACK}
enum Stance {WIDE, HOLD}

# --- Constants ---

const DELAY_PER_ABANDON := 11.0
const DELAY_MAX := 60.0
# Upper bound on the world-space distance between two adjacent pathing
# centres (the Cairo pentagon spans ~15 units edge-to-edge). The euclidean
# distance between any two tiles can never exceed path_edges x this bound,
# so it lower-bounds the A* path length for candidate pruning in assignment.
const PATH_EDGE_EUCLID_BOUND: float = Cairo.UNIT * 2.5

# --- State ---

var jobs_dict: Dictionary # int (id) -> job dict
var job_id := -1

# Memoized (from_tile, to_tile) -> path length, valid only within one
# assign_jobs() pass (see _get_pathlength).
var _path_cache: Dictionary = {}

# Rallied-squad follow: the tile the avatar's FPSBody currently stands on,
# memoized per avatar instance (keyed by instance id) so a squad of units
# shares one nearest-tile lookup per interval.
var _rally_avatar_tile_cache: Dictionary = {} # instance_id -> {tile: TileElement, time: float}
const RALLY_AVATAR_TILE_TTL := 0.5

var debug_enabled := false
var debug_mesh: ImmediateMesh
var debug_mesh_instance: MeshInstance3D

# --- Lifecycle ---

func _ready() -> void:
	Global.JM = self
	if debug_enabled:
		_setup_debug()

func _process(_delta: float) -> void:
	if not debug_enabled or jobs_dict.is_empty():
		return
	debug_mesh.clear_surfaces()
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for job in jobs_dict.values():
		if job["assigned"] == null or not is_instance_valid(job["assigned"]) or not job.has("path_dest"):
			continue
		var a = job["path_dest"].pathing_centre
		var b = job["assigned"].location.pathing_centre
		match job["type"]:
			Type.TOGGLE_TILE:
				debug_mesh.surface_set_color(Color.GREEN)
			Type.CONSTRUCT_BUILDING:
				debug_mesh.surface_set_color(Color.CYAN)
			Type.CONSUME_ZOOMBA:
				debug_mesh.surface_set_color(Color.MAGENTA)
			Type.COMBAT_PERSUE:
				debug_mesh.surface_set_color(Color.RED)
			Type.ATTACK:
				debug_mesh.surface_set_color(Color.ORANGE_RED)
			_:
				continue
		debug_mesh.surface_add_vertex(Vector3(a.x, a.y + 5, a.z))
		debug_mesh.surface_add_vertex(Vector3(b.x, b.y + 5, b.z))
	debug_mesh.surface_end()

func _setup_debug() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	debug_mesh = ImmediateMesh.new()
	debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.mesh = debug_mesh
	debug_mesh_instance.material_override = mat
	add_child(debug_mesh_instance)

# --- Job lifecycle ---

# Resolve a job target (TileElement / Unit / Building) to the tile it occupies.
func target_tile(target: Variant) -> TileElement:
	if target is TileElement:
		return target
	if target is Unit or target is Building:
		return target.location
	return null

func add_job(pnum: int, type: Type, target: Variant, request_assign: Unit = null, personal: bool = false, eligible_types: Array = [], patrol_only: bool = false, territory_only: bool = false) -> int:
	assert(pnum > 0 and pnum <= Global.MAX_PLAYERS)
	for the_job in jobs_dict.values():
		if the_job["type"] != type:
			continue
		# Personal jobs must not block each other — multiple units need to
		# attack the same target independently.
		if the_job["personal"]:
			continue
		if the_job["target"] != target:
			continue
		if the_job["pnum"] != pnum:
			continue
		# Already have this job - still hand it to a waiting eligible unit
		if request_assign and the_job["assigned"] == null:
			_try_assign_job(the_job, request_assign)
		return the_job["id"]
	job_id += 1
	var job := {"id": job_id, "pnum": pnum, "type": type,
		"target": target, "assigned": null, "personal": personal,
		"eligible_types": eligible_types, "patrol_only": patrol_only,
		"territory_only": territory_only,
		"abandoned_by": null, "abandoned_n": 0, "abandoned_timer": 0.0}
	jobs_dict[job_id] = job
	_notify_job_event(job["pnum"], "added", job)
	if request_assign:
		_try_assign_job(job, request_assign)
	return job_id

func cancel_job(pnum: int, type: Type, target: Variant) -> void:
	assert(pnum > 0 and pnum <= Global.MAX_PLAYERS)
	for the_job in jobs_dict.values():
		if the_job["pnum"] != pnum:
			continue
		if the_job["type"] != type:
			continue
		if the_job["target"] != target:
			continue
		remove_job(the_job["id"])
		return

func count_jobs(pnum: int, type: Type) -> int:
	var c := 0
	for job in jobs_dict.values():
		if job["pnum"] == pnum and job["type"] == type:
			c += 1
	return c

func has_job(pnum: int, type: Type, target: Variant) -> bool:
	for job in jobs_dict.values():
		if job["pnum"] == pnum and job["type"] == type and job["target"] == target:
			return true
	return false

func remove_job(id_to_remove: int) -> void:
	if jobs_dict.has(id_to_remove):
		var job = jobs_dict[id_to_remove]
		var pnum = job["pnum"]
		# A freed Object still evaluates truthy — guard in case a future removal
		# path frees a unit without abandoning its job first.
		if job["assigned"] != null and is_instance_valid(job["assigned"]):
			job["assigned"].remove_job()
		jobs_dict.erase(id_to_remove)
		_notify_job_event(pnum, "finished", job)

func abandon_job(id_to_abandon: int) -> void:
	assert(jobs_dict.has(id_to_abandon))
	var job = jobs_dict[id_to_abandon]
	job["abandoned_by"] = job["assigned"]
	job["assigned"] = null
	job["abandoned_n"] += 1
	job["abandoned_timer"] = min(DELAY_MAX, job["abandoned_n"] * DELAY_PER_ABANDON)
	_notify_job_event(job["pnum"], "abandoned", job)
	if job["personal"]: # Personal jobs cannot be abandoned, they expire if their unit gives up
		jobs_dict.erase(id_to_abandon)

# --- Assignment ---

func assign_jobs() -> void:
	if not multiplayer.is_server():
		return
	# Path lengths are memoized per assign pass — many idle units share the same
	# (from, to) tile pairs, so a single A* per pair replaces one per unit.
	_path_cache.clear()
	# Remove unassigned jobs that are no longer valid (e.g. destroyed targets).
	# Assigned jobs are validated by their unit's pathing loop instead.
	for id_to_check in jobs_dict.keys():
		var job = jobs_dict[id_to_check]
		if job["assigned"] != null:
			continue
		if not check_job_still_valid(job):
			remove_job(id_to_check)
	# Decrement timers for all unassigned jobs
	for job in jobs_dict.values():
		if job["assigned"] != null:
			continue
		job["abandoned_timer"] -= 1.0
	# One snapshot of the job list for the whole assignment pass — building it
	# per idle unit was a fresh Array allocation (and dict iteration) per unit.
	var job_list: Array = jobs_dict.values()
	# Assign jobs to idle workers
	for unit in get_tree().get_nodes_in_group("unit"):
		if not unit.job.is_empty():
			continue
		if unit.type == UnitManager.Type.AVATAR:
			continue
		if unit.scram_count > 0:
			continue
		_assign_nearest_job(unit, job_list)

func _assign_nearest_job(unit: Unit, job_list: Array) -> bool:
	var pnum = unit.player_owner
	var from_pos: Vector3 = unit.location.pathing_centre
	# Filter to this unit's eligible jobs and precompute the straight-line
	# distance — it provides a lower bound on the A* path length, so candidates
	# can be visited nearest-first and the rest skipped without pathfinding.
	var candidates: Array = []
	for job in job_list:
		if job["pnum"] != pnum:
			continue
		if job["assigned"] != null:
			continue
		if job["abandoned_timer"] > 0.0:
			continue
		if not _unit_eligible_for_job(unit, job):
			continue
		var tile := target_tile(job["target"])
		if tile == null:
			continue
		candidates.append({"job": job, "d2": from_pos.distance_squared_to(tile.pathing_centre)})
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a, b): return a["d2"] < b["d2"])
	var best_job = null
	var best_dist := 9999
	for c in candidates:
		# Euclidean lower bound: path edges x PATH_EDGE_EUCLID_BOUND >= straight
		# distance (an adjacent pathing-centre pair is always closer than the
		# bound). Once the bound exceeds the best path found, no later (farther)
		# candidate can win — skip its A* queries.
		if sqrt(c["d2"]) / PATH_EDGE_EUCLID_BOUND > best_dist:
			break
		var tile := target_tile(c["job"]["target"])
		var dist = _get_pathlength(unit.location, tile)
		if dist < best_dist:
			best_dist = dist
			best_job = c["job"]
	if best_job != null:
		_try_assign_job(best_job, unit)
		return true
	return false

func _try_assign_job(job: Dictionary, unit: Unit) -> bool:
	if not is_instance_valid(unit):
		return false
	if unit.player_owner != job["pnum"]:
		return false
	if not unit.job.is_empty():
		return false
	if unit.state != Unit.State.IDLE:
		return false
	if unit.scram_count > 0:
		return false
	if unit.type == UnitManager.Type.AVATAR:
		return false
	if not _unit_eligible_for_job(unit, job):
		return false
	job["assigned"] = unit
	job["abandoned_timer"] = 0.0
	unit.assign_job(job)
	_notify_job_event(job["pnum"], "assigned", job)
	return true

func _unit_eligible_for_job(unit: Unit, job: Dictionary) -> bool:
	var etypes: Array = job.get("eligible_types", [])
	if not etypes.is_empty() and unit.type not in etypes:
		return false
	match job["type"]:
		JobManager.Type.TOGGLE_TILE, JobManager.Type.CONSTRUCT_BUILDING, JobManager.Type.REPAIR_BUILDING, JobManager.Type.CONSUME_ZOOMBA:
			if unit.type != UnitManager.Type.ZOOMBA:
				return false
	if job.get("patrol_only", false):
		if unit.type != UnitManager.Type.AERIAL:
			return false
		if not unit.has_method(&"get_mode") or unit.get_mode() != Config.AERIAL_MODE_PATROL:
			return false
	if job.get("territory_only", false):
		var tile := target_tile(job["target"])
		if tile == null or unit.player_owner not in tile.aoe:
			return false
	return true

func _get_pathlength(from: TileElement, to: TileElement) -> int:
	var key := from.id * 100000 + to.id
	if _path_cache.has(key):
		return _path_cache[key]
	var shortest := 9999
	var pm = Global.PM
	for n in to.get_access_tiles():
		var dist = pm.pathfind(from, n)
		if dist.size() != 0 and dist.size() < shortest:
			shortest = dist.size()
	_path_cache[key] = shortest
	return shortest

func check_job_still_valid(job: Dictionary) -> bool:
	if not multiplayer.is_server():
		return false
	if job.is_empty():
		return false
	var pnum: int = job["pnum"]
	match job["type"]:
		Type.CONSTRUCT_BUILDING:
			var b = job["target"].building
			if not b or b.state != Building.State.BLUEPRINT:
				return false
		Type.TOGGLE_TILE:
			var tile = job["target"] as TileElement
			if tile.state != TileManager.State.RAISED and tile.state != TileManager.State.LOWERED:
				return false
			if tile.selected_by.count(pnum) == 0:
				return false
		Type.REPAIR_BUILDING:
			var b = job["target"].building
			if not b or b.health >= b.max_health:
				return false
		Type.CONSUME_ZOOMBA:
			var b = job["target"].building
			if not b or b.state != Building.State.CONSTRUCTED or b.type != BuildingManager.Type.GARAGE:
				return false
		Type.COMBAT_PERSUE:
			var t = job["target"]
			if t == null or not is_instance_valid(t):
				return false
			if t is Unit or t is Building:
				if t.health <= 0:
					return false
			else:
				return false
			# A cloaked VIRUS cannot be targeted — a re-cloaked target cancels
			# any in-flight kill-VIRUS jobs (same as if it were destroyed).
			if t is Unit and t.type == UnitManager.Type.VIRUS and t.cloaked:
				return false
			if job.get("territory_only", false):
				var tile := target_tile(t)
				if tile == null or pnum not in tile.aoe:
					return false
		Type.ATTACK:
			# Personal VIRUS attack/limpet job. Valid while the target is alive;
			# the empowered building is immune to infection (DESIGN), so a path
			# to one is a wasted trip — invalidate before pathing starts.
			var t = job["target"]
			if t == null or not is_instance_valid(t):
				return false
			if t is Unit or t is Building:
				if t.health <= 0:
					return false
				if t is Building and t.is_empowered:
					return false
			else:
				return false
	return true

# --- Avatar rally ---

# DESIGN: the avatar gathers nearby friendly TANK/AERIAL/VIRUS into a squad
# that follows it while in FPS. Each member gets its own personal COMBAT_PERSUE
# job targeting the avatar (personal jobs don't dedupe, so any squad size is
# fine). The squad disbands when the avatar dies or the player leaves FPS
# (Server._cmd_camera_mode / UnitManager avatar removal -> cancel_player_rally).
func start_rally(pnum: int) -> int:
	if not multiplayer.is_server():
		return 0
	var avatar := get_tree().get_first_node_in_group("avatar_player" + str(pnum)) as Unit
	if not avatar or not is_instance_valid(avatar) or avatar.health <= 0:
		return 0
	var body: Node3D = avatar.fps_body_node
	var origin: Vector3 = body.global_position if body else avatar.global_position
	var joined := 0
	for u in Global.UM.units():
		if u.player_owner != pnum:
			continue
		if u.type != UnitManager.Type.TANK \
			and u.type != UnitManager.Type.AERIAL \
			and u.type != UnitManager.Type.VIRUS:
			continue
		if u == avatar or u.health <= 0 or u.scram_count > 0:
			continue
		if u.rallied:
			continue # Already in the squad — pressing again only grows it.
		if origin.distance_squared_to(u.global_position) > Config.RALLY_RADIUS * Config.RALLY_RADIUS:
			continue
		if not Global.CM.has_los(origin, u.global_position, [avatar, u]):
			continue
		# HOLD-stance home units (TANK / AERIAL-PATROL) switch to WIDE at rally
		# time: once dragged away, walking back to the spawning building's
		# patrol tiles is too much of an edge case (per DESIGN).
		if u.orders.get("stance", JobManager.Stance.WIDE) == JobManager.Stance.HOLD \
			and (u.type == UnitManager.Type.TANK \
				or (u.type == UnitManager.Type.AERIAL and u.get_mode() == Config.AERIAL_MODE_PATROL)):
			u.orders["stance"] = JobManager.Stance.WIDE
		if not u.job.is_empty():
			u.abandon_job()
		add_job(pnum, Type.COMBAT_PERSUE, avatar, u, true) # personal, auto-assigned
		if not u.job.is_empty() and u.job["type"] == Type.COMBAT_PERSUE and u.job["target"] == avatar:
			u.set_rallied(true)
			joined += 1
	return joined

func cancel_player_rally(pnum: int) -> void:
	if not multiplayer.is_server():
		return
	var ids: Array[int] = []
	for job in jobs_dict.values():
		if job["pnum"] != pnum or not job["personal"]:
			continue
		if job["type"] != Type.COMBAT_PERSUE:
			continue
		var t = job["target"]
		# is_instance_valid: the avatar may already be freed (death removal
		# runs before this in rpc_remove_unit; camera-mode cancel can arrive
		# after). Such jobs are dead anyway — the validity check drops them.
		if is_instance_valid(t) and t is Avatar and t.player_owner == pnum:
			ids.append(job["id"])
	for id_to_remove in ids:
		remove_job(id_to_remove) # each removal clears the unit's rallied flag
	var avatar := get_tree().get_first_node_in_group("avatar_player" + str(pnum))
	if avatar:
		_rally_avatar_tile_cache.erase(avatar.get_instance_id())

# The LOWERED tile nearest the avatar's FPSBody — the squad's follow target
# (the avatar's root node never moves). Nearest-tile scan is memoized per
# avatar instance so a whole squad shares one lookup per 0.5s.
func rally_avatar_tile(avatar: Unit) -> TileElement:
	if not multiplayer.is_server():
		return null
	if not avatar or not is_instance_valid(avatar):
		return null
	var now := Time.get_ticks_msec() / 1000.0
	var key := avatar.get_instance_id()
	var entry = _rally_avatar_tile_cache.get(key)
	if entry != null and now - entry["time"] < RALLY_AVATAR_TILE_TTL:
		return entry["tile"]
	var body: Node3D = avatar.fps_body_node
	var pos: Vector3 = body.global_position if body else avatar.global_position
	var best: TileElement = null
	var best_d2 := INF
	for t in Global.TM.tile_dictionary.values():
		if not t.walkable() or t.building != null:
			continue
		var d2: float = t.pathing_centre.distance_squared_to(pos)
		if d2 < best_d2:
			best_d2 = d2
			best = t
	_rally_avatar_tile_cache[key] = {"tile": best, "time": now}
	return best

# --- Job notifications ---

func _notify_job_event(pnum: int, event: String, job: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if job["type"] == Type.COMBAT_PERSUE or job["type"] == Type.ATTACK:
		return
	var text := _format_job_notification(event, job)
	var loc := _get_job_location(job)
	Global.NM.rpc("rpc_add_job_notification", pnum, event, text, loc.x, loc.y, loc.z)

func _format_job_notification(event: String, job: Dictionary) -> String:
	var type_name := _job_type_name(job["type"])
	var target := _target_name(job)
	var who := ""
	if job.get("assigned") and is_instance_valid(job["assigned"]):
		who = _unit_name(job["assigned"])
	if who.is_empty():
		who = "Unit"
	match event:
		"added":
			if job["type"] == Type.TOGGLE_TILE:
				return "New %s job on tile %d" % [type_name, job["target"].id]
			return "New %s job at %s" % [type_name, target]
		"assigned":
			if job["type"] == Type.TOGGLE_TILE:
				return "%s assigned to toggle tile %d" % [who, job["target"].id]
			return "%s assigned %s at %s" % [who, type_name, target]
		"abandoned":
			var suffix := ""
			if job["abandoned_n"] > 1:
				suffix = " (x%d)" % job["abandoned_n"]
			if job["type"] == Type.TOGGLE_TILE:
				return "%s job on tile %d abandoned%s" % [type_name, job["target"].id, suffix]
			return "%s job at %s abandoned%s" % [type_name, target, suffix]
		"finished":
			if job["type"] == Type.TOGGLE_TILE:
				return "%s completed on tile %d" % [type_name, job["target"].id]
			return "%s job at %s completed" % [type_name, target]
	return "Job event: %s" % event

func _job_type_name(type: Type) -> String:
	match type:
		Type.CONSTRUCT_BUILDING: return "Build"
		Type.REPAIR_BUILDING:    return "Repair"
		Type.TOGGLE_TILE:        return "Toggle"
		Type.CONSUME_ZOOMBA:     return "Consume"
		Type.COMBAT_PERSUE:      return "Pursue"
		Type.ATTACK:             return "Attack"
	return "Job"

func _unit_name(unit: Unit) -> String:
	return UnitManager.Type.keys()[unit.type] + str(unit.id)

func _target_name(job: Dictionary) -> String:
	var t = job["target"]
	if t is Unit:
		return UnitManager.Type.keys()[t.type] + str(t.id)
	if t is Building:
		return BuildingManager.Type.keys()[t.type]
	if t is TileElement:
		if t.building:
			return "%s" % BuildingManager.Type.keys()[t.building.type]
		return "tile %d" % t.id
	return "Unknown"

func _get_job_location(job: Dictionary) -> Vector3:
	var t = job["target"]
	if t is TileElement:
		return t.pathing_centre
	if t is Unit or t is Building:
		return t.location.pathing_centre
	return Vector3.ZERO
