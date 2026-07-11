extends Node3D

class_name JobManager

const DELAY_PER_ABANDON = 11.0
const DELAY_MAX = 60.0

enum Type {NONE, CONSTRUCT_BUILDING, TOGGLE_TILE}

var jobs_dict : Dictionary
var unassigned := 0
var job_id := -1

#var priorities : Array

var debug_enabled := true
var debug_mesh: ImmediateMesh
var debug_mesh_instance: MeshInstance3D

func _ready():
	#for _i in range(Global.MAX_PLAYERS):
		#player_jobs.append({})
		#unassigned_count.append(0)
		#var p : Array = []
		#for _jt in Type:
			#p.append(1)
		#priorities.append(p)
	set_process(true)
	if debug_enabled:
		_setup_debug()
	
func _setup_debug():
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	debug_mesh = ImmediateMesh.new()
	debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.mesh = debug_mesh
	debug_mesh_instance.material_override = mat
	add_child(debug_mesh_instance)

func add_job(pnum : int, type : Type, place, target):
	assert(pnum > 0 and pnum <= Global.MAX_PLAYERS)
	var job : Dictionary
	var have_job := false
	for the_job in jobs_dict.values():
		if the_job["type"] != type:
			continue
		if the_job["place"] != place:
			continue
		if the_job["target"] != target:
			continue
		have_job = true
		break
	if have_job:
		return
	#
	job_id += 1
	job = {"id": job_id, "pnum": pnum, "type": type,
		"place": place, "target": target, "assigned": null,
		"abandoned_by": null, "abandoned_n": 0, "abandoned_timer": 0.0}
	unassigned += 1
	jobs_dict[job_id] = job
	print("New job ", job)

func remove_job(id_to_remove : int):
	assert(jobs_dict.has(id_to_remove))
	jobs_dict.erase(id_to_remove)

func abandon_job(id_to_remove : int):
	assert(jobs_dict.has(id_to_remove))
	var job = jobs_dict[id_to_remove]
	unassigned += 1
	job["abandoned_by"] = job["assigned"]
	job["assigned"] = null
	job["abandoned_n"] += 1
	job["abandoned_timer"] = min(DELAY_MAX, job["abandoned_n"] * DELAY_PER_ABANDON)

func try_and_assign(job : Dictionary) -> bool:
	# Get all units belonging to this player's job
	var best_unit = null
	for unit in get_tree().get_nodes_in_group("unit_player" + str(job["pnum"])):
		if not unit.job.empty():
			continue
		#if zoomba.scram_count > 0:
			#continue
		# in following if: or priority[job["type"]] < priority[bestest_job["type"]
		# TODO - use pathing system distance rather than simple crow-fly
		if best_unit == null \
			or job["place"].pathing_centre.distance_to(unit.location.pathing_centre) \
				< job["place"].pathing_centre.distance_to(best_unit.location.pathing_centre):
			best_unit = unit
	if best_unit != null:
		job["assigned"] = best_unit
		best_unit.assign_job(job)
		return true
	return false

func assign_jobs():
	if unassigned == 0:
		return
	for job in jobs_dict.values():
		if job["assigned"] != null:
			continue
		job["abandoned_timer"] -= 1.0 # TODO make this configurable to the server job tick
		if job["abandoned_timer"] > 0.0:
			continue
		if try_and_assign(job):
			unassigned -= 1

#func _on_AssignJobs_timeout():
	#if unassigned == 0:
		#return
	#for job in jobs_dict.values():
		#job["abandoned_timer"] -= $AssignJobs.wait_time
	#assign_jobs()

func _process(_delta : float):
	if not debug_enabled or jobs_dict.is_empty():
		return
	debug_mesh.clear_surfaces()
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for job in jobs_dict.values():
		var a = job["place"].pathing_centre
		match job["type"]:
			Type.CONSTRUCT_BUILDING:
				var b = job["target"].pathing_centre
				debug_mesh.surface_set_color(Color.GREEN)
				debug_mesh.surface_add_vertex(Vector3(a.x, a.y + 5, a.z))
				debug_mesh.surface_add_vertex(Vector3(b.x, b.y + 5, b.z))
			#Type.CLAIM_TILE:
				#debug_mesh.surface_set_color(Color.YELLOW)
				#$DebugRender.surface_add_vertex(Vector3(a.x - 5, a.y + 5, a.z - 5))
				#$DebugRender.surface_add_vertex(Vector3(a.x + 5, a.y + 5, a.z + 5))
				#$DebugRender.surface_add_vertex(Vector3(a.x - 5, a.y + 5, a.z + 5))
				#$DebugRender.surface_add_vertex(Vector3(a.x + 5, a.y + 5, a.z - 5))
	debug_mesh.surface_end()
