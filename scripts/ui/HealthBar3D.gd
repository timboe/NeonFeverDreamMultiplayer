extends Node3D

class_name HealthBar3D

# --- Constants ---

const DEFAULT_WIDTH: float = 1.0
const DEFAULT_HEIGHT: float = 0.15

# --- Nodes ---

var _mesh: MeshInstance3D
var _material: ShaderMaterial

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

func _process(_delta: float) -> void:
	var cam = get_viewport().get_camera_3d()
	if cam:
		var diff: Vector3 = cam.global_position - global_position
		if absf(diff.x) > 0.001 or absf(diff.z) > 0.001:
			look_at(cam.global_position, Vector3.UP)

# --- API ---

func set_bar_size(w: float, h: float) -> void:
	_mesh.mesh.size = Vector2(w, h)

func set_health(current: float, maximum: float) -> void:
	if maximum <= 0.0:
		_mesh.visible = false
		return
	_mesh.visible = true
	var fraction := clampf(current / maximum, 0.0, 1.0)
	_material.set_shader_parameter("fraction", fraction)
