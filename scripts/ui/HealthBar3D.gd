extends Node3D
class_name HealthBar3D

var _mesh: MeshInstance3D
var _material: ShaderMaterial

const DEFAULT_WIDTH := 1.0
const DEFAULT_HEIGHT := 0.15

func _ready():
	var shader := Shader.new()
	shader.code = "shader_type spatial;\n" \
		+ "render_mode unshaded, cull_disabled;\n" \
		+ "\n" \
		+ "uniform float fraction : hint_range(0.0, 1.0) = 1.0;\n" \
		+ "uniform vec4 fill_color : source_color = vec4(0.9, 0.15, 0.15, 0.95);\n" \
		+ "uniform vec4 bg_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);\n" \
		+ "\n" \
		+ "void fragment() {\n" \
		+ "\tif (UV.x <= fraction) {\n" \
		+ "\t\tALBEDO = fill_color.rgb;\n" \
		+ "\t\tALPHA = fill_color.a;\n" \
		+ "\t} else {\n" \
		+ "\t\tALBEDO = bg_color.rgb;\n" \
		+ "\t\tALPHA = bg_color.a;\n" \
		+ "\t}\n" \
		+ "}"
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("fraction", 1.0)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(DEFAULT_WIDTH, DEFAULT_HEIGHT)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.material_override = _material
	add_child(_mesh)

func _process(_delta):
	var cam = get_viewport().get_camera_3d()
	if cam:
		look_at(cam.global_position, Vector3.UP)

func set_bar_size(w: float, h: float):
	_mesh.mesh.size = Vector2(w, h)

func set_health(current: float, maximum: float):
	if maximum <= 0.0:
		_mesh.visible = false
		return
	_mesh.visible = true
	var fraction := clampf(current / maximum, 0.0, 1.0)
	_material.set_shader_parameter("fraction", fraction)
