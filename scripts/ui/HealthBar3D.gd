extends Node3D

class_name HealthBar3D

# --- Constants ---

const DEFAULT_WIDTH: float = 1.0
const DEFAULT_HEIGHT: float = 0.15

# --- Nodes ---

var _mesh: MeshInstance3D
var _material: ShaderMaterial

# --- Frame caches ---

var _cam: Camera3D
var _cam_refresh_timer := 0.0
var _last_fraction := -1.0

# --- Lifecycle ---

func _ready() -> void:
	var shader := preload("res://shaders/health_bar.gdshader")
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("fraction", 1.0)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(DEFAULT_WIDTH, DEFAULT_HEIGHT)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.material_override = _material
	add_child(_mesh)

func _process(delta: float) -> void:
	# Camera lookup is expensive across 100+ bars — refresh at 4 Hz and
	# slow-follow; the bars are small, so the lag is invisible.
	_cam_refresh_timer -= delta
	if _cam_refresh_timer <= 0.0:
		_cam_refresh_timer = 0.25
		_cam = get_viewport().get_camera_3d()
	if _cam:
		var diff: Vector3 = _cam.global_position - global_position
		if absf(diff.x) > 0.001 or absf(diff.z) > 0.001:
			look_at(_cam.global_position, Vector3.UP)

# --- API ---

func set_bar_size(w: float, h: float) -> void:
	_mesh.mesh.size = Vector2(w, h)

func set_health(current: float, maximum: float) -> void:
	if maximum <= 0.0:
		_mesh.visible = false
		return
	_mesh.visible = true
	var fraction := clampf(current / maximum, 0.0, 1.0)
	if absf(fraction - _last_fraction) < 0.005:
		return
	_last_fraction = fraction
	_material.set_shader_parameter("fraction", fraction)

func set_fill_color(color: Color) -> void:
	_material.set_shader_parameter("fill_color", color)
