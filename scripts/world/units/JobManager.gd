extends Node3D

class_name JobManager

enum Type {NONE, CONSTRUCT_BUILDING, REPAIR_BUILDING, TOGGLE_TILE, CONSUME_ZOOMBA}
enum Orders {NONE, PATROL, ATTACK}
enum Stance {WIDE, HOLD}
enum Priority {NEAREST, LOWEST_HP}

const DELAY_PER_ABANDON := 11.0
const DELAY_MAX := 60.0

var jobs_dict: Dictionary # int (id) -> job dict
var job_id := -1

var debug_enabled := false
var debug_mesh: ImmediateMesh
var debug_mesh_instance: MeshInstance3D

# --- Lifecycle ---

func _ready() -> void:
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

func add_job(pnum: int, type: Type, location: TileElement, personal : bool = false) -> void:
	assert(pnum > 0 and pnum <= Global.MAX_PLAYERS)
	for the_job in jobs_dict.values():
		if the_job["type"] != type:
			continue
		if the_job["location"] != location:
			continue
		if the_job["pnum"] != pnum:
			continue
		return # Already have this job
	job_id += 1
	var job := {"id": job_id, "pnum": pnum, "type": type,
		"location": location, "assigned": null, "personal": personal,
		"abandoned_by": null, "abandoned_n": 0, "abandoned_timer": 0.0}
	jobs_dict[job_id] = job
	_notify_job_event(job["pnum"], "added", job)

func cancel_job(pnum: int, type: Type, location: TileElement) -> void:
	assert(pnum > 0 and pnum <= Global.MAX_PLAYERS)
	for the_job in jobs_dict.values():
		if the_job["pnum"] != pnum:
			continue
		if the_job["type"] != type:
			continue
		if the_job["location"] != location:
			continue
		remove_job(the_job["id"])
		return

func count_jobs(pnum: int, type: Type) -> int:
	var c := 0
	for job in jobs_dict.values():
		if job["pnum"] == pnum and job["type"] == type:
			c += 1
	return c

func remove_job(id_to_remove: int) -> void:
	if jobs_dict.has(id_to_remove):
		var job = jobs_dict[id_to_remove]
		var pnum = job["pnum"]
		if job["assigned"]:
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
	# Decrement timers for all unassigned jobs
	for job in jobs_dict.values():
		if job["assigned"] != null:
			continue
		job["abandoned_timer"] -= 1.0
	# Assign jobs to idle workers
	for unit in get_tree().get_nodes_in_group("unit"):
		if not unit.job.is_empty():
			continue
		if unit.type == UnitManager.Type.AVATAR:
			continue
		if unit.scram_count > 0:
			continue
		assign_nearest_job(unit)

func assign_nearest_job(unit: Unit) -> bool:
	var pnum = unit.player_owner
	var best_job = null
	var best_dist := 9999
	for job in jobs_dict.values():
		if job["pnum"] != pnum:
			continue
		if job["assigned"] != null:
			continue
		if job["abandoned_timer"] > 0.0:
			continue
		var dist = get_pathlength(unit.location, job["location"])
		if dist < best_dist:
			best_dist = dist
			best_job = job
	if best_job != null:
		best_job["assigned"] = unit
		unit.assign_job(best_job)
		_notify_job_event(best_job["pnum"], "assigned", best_job)
		return true
	return false

func get_pathlength(from: TileElement, to: TileElement) -> int:
	var shortest := 9999
	var pm = get_node_or_null("/root/World/TileManager/PathingManager")
	for n in to.get_access_tiles():
		var dist = pm.pathfind(from, n)
		if dist.size() != 0 and dist.size() < shortest:
			shortest = dist.size()
	return shortest

# --- Job notifications ---

func _notify_job_event(pnum: int, event: String, job: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var text := _format_job_notification(event, job)
	var loc := _get_job_location(job)
	var nm = get_tree().get_first_node_in_group("notification_manager")
	if nm:
		nm.rpc("rpc_add_job_notification", pnum, text, loc.x, loc.y, loc.z)

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
				return "New %s job on tile %d" % [type_name, job["location"].id]
			return "New %s job at %s" % [type_name, target]
		"assigned":
			if job["type"] == Type.TOGGLE_TILE:
				return "%s assigned to toggle tile %d" % [who, job["location"].id]
			return "%s assigned %s at %s" % [who, type_name, target]
		"abandoned":
			var suffix := ""
			if job["abandoned_n"] > 1:
				suffix = " (x%d)" % job["abandoned_n"]
			if job["type"] == Type.TOGGLE_TILE:
				return "%s job on tile %d abandoned%s" % [type_name, job["location"].id, suffix]
			return "%s job at %s abandoned%s" % [type_name, target, suffix]
		"finished":
			if job["type"] == Type.TOGGLE_TILE:
				return "%s completed on tile %d" % [type_name, job["location"].id]
			return "%s job at %s completed" % [type_name, target]
	return "Job event: %s" % event

func _job_type_name(type: Type) -> String:
	match type:
		Type.CONSTRUCT_BUILDING: return "Build"
		Type.REPAIR_BUILDING:    return "Repair"
		Type.TOGGLE_TILE:        return "Toggle"
		Type.CONSUME_ZOOMBA:     return "Consume"
	return "Job"

func _unit_name(unit: Unit) -> String:
	return UnitManager.Type.keys()[unit.type] + str(unit.id)

func _target_name(job: Dictionary) -> String:
	var loc = job["location"]
	if not loc is TileElement:
		return "Unknown"
	if loc.building:
		return "%s" % BuildingManager.Type.keys()[loc.building.type]
	return "tile %d" % loc.id

func _get_job_location(job: Dictionary) -> Vector3:
	var loc = job["location"]
	if loc is TileElement:
		return loc.pathing_centre
	return Vector3.ZERO
