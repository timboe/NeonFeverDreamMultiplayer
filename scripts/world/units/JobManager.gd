extends Node3D

class_name JobManager

enum Type {NONE, CONSTRUCT_BUILDING, REPAIR_BUILDING, TOGGLE_TILE}

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

func add_job(pnum: int, type: Type, location: TileElement) -> void:
	assert(pnum > 0 and pnum <= Global.MAX_PLAYERS)
	for the_job in jobs_dict.values():
		if the_job["type"] != type:
			continue
		if the_job["location"] != location:
			continue
		return # Already have this job
	job_id += 1
	var job := {"id": job_id, "pnum": pnum, "type": type,
		"location": location, "assigned": null,
		"abandoned_by": null, "abandoned_n": 0, "abandoned_timer": 0.0}
	jobs_dict[job_id] = job

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

func remove_job(id_to_remove: int) -> void:
	if jobs_dict.has(id_to_remove):
		if jobs_dict[id_to_remove]["assigned"]:
			jobs_dict[id_to_remove]["assigned"].remove_job()
		jobs_dict.erase(id_to_remove)

func abandon_job(id_to_abandon: int) -> void:
	assert(jobs_dict.has(id_to_abandon))
	var job = jobs_dict[id_to_abandon]
	job["abandoned_by"] = job["assigned"]
	job["assigned"] = null
	job["abandoned_n"] += 1
	job["abandoned_timer"] = min(DELAY_MAX, job["abandoned_n"] * DELAY_PER_ABANDON)

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
