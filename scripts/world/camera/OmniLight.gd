extends OmniLight3D

# --- Constants ---

const HEIGHT: float = 5.0 # Hover clearance above the surface being lit.
const RAISED_BOOST: float = Global.FLOOR_HEIGHT # Raised tile tops sit at FLOOR_HEIGHT.
const OFF_MAP_HEIGHT: float = HEIGHT + Global.FLOOR_HEIGHT * 2.0 # Lift clear of the playfield.
const LOWERED_THRESHOLD: float = Global.FLOOR_HEIGHT / 2.0 # Splits raised (~20) from lowered (~0) hits.

const DEBUG_GIZMO_SEGMENTS := 24
const DEBUG_POSITION_COLOR := Color(0.5, 1.0, 1.0)
const DEBUG_RANGE_COLOR := Color(1.0, 0.2, 1.0)
const DEBUG_AXIS_COLOR := Color(1.0, 1.0, 1.0)

# --- State ---

@onready var desired_height: float = position.y

var _debug_visible: bool = false
var _debug_gizmo: MeshInstance3D

# --- Lifecycle ---

func _ready() -> void:
	_debug_gizmo = MeshInstance3D.new()
	_debug_gizmo.name = "DebugLightGizmo"
	_debug_gizmo.mesh = _build_debug_mesh()
	_debug_gizmo.visible = false
	add_child(_debug_gizmo)

# --- Frame ---

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_debug_light"):
		_debug_visible = not _debug_visible
	var is_overhead: bool = Global.VM != null and Global.VM.camera_status == VideoManager.CameraStatus.OVERHEAD
	visible = is_overhead
	_debug_gizmo.visible = is_overhead and _debug_visible
	if not is_overhead:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var from: Vector3 = %CameraRTS.project_ray_origin(mouse_pos)
	var to: Vector3 = from + %CameraRTS.project_ray_normal(mouse_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 2147483647, [])
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		# Horizontal tracking stays exact — snap straight to the cursor's ground hit.
		position.x = result.position.x
		position.z = result.position.z
		var lowered : bool = result.position.y < LOWERED_THRESHOLD
		desired_height = HEIGHT + (RAISED_BOOST if not lowered else 0.0)
	else:
		# Cursor is off the playfield (sky / decorative floor): lift the light
		# high above the map instead of leaving it hovering over the last tile.
		desired_height = OFF_MAP_HEIGHT
	position.y += (desired_height - position.y) * delta * 10.0

# --- Debug gizmo ---

# Wireframe visualising the light's extent: magenta sphere = omni_range boundary,
# white axis = centre direction (the node is oriented straight down at the
# cursor), cyan cross = light origin.
func _build_debug_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var range_mat := _debug_material(DEBUG_RANGE_COLOR)
	for axis in 3:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, range_mat)
		for i in DEBUG_GIZMO_SEGMENTS + 1:
			var a := TAU * float(i) / DEBUG_GIZMO_SEGMENTS
			match axis:
				0: mesh.surface_add_vertex(Vector3(omni_range * cos(a), omni_range * sin(a), 0.0))
				1: mesh.surface_add_vertex(Vector3(omni_range * cos(a), 0.0, omni_range * sin(a)))
				2: mesh.surface_add_vertex(Vector3(0.0, omni_range * cos(a), omni_range * sin(a)))
		mesh.surface_end()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_material(DEBUG_AXIS_COLOR))
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_add_vertex(Vector3(0.0, 0.0, -omni_range))
	mesh.surface_end()
	var origin_mat := _debug_material(DEBUG_POSITION_COLOR)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, origin_mat)
	mesh.surface_add_vertex(Vector3(-1.0, 0.0, 0.0))
	mesh.surface_add_vertex(Vector3(1.0, 0.0, 0.0))
	mesh.surface_add_vertex(Vector3(0.0, -1.0, 0.0))
	mesh.surface_add_vertex(Vector3(0.0, 1.0, 0.0))
	mesh.surface_add_vertex(Vector3(0.0, 0.0, 1.0))
	mesh.surface_add_vertex(Vector3(0.0, 0.0, -1.0))
	mesh.surface_end()
	return mesh

func _debug_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	return mat
