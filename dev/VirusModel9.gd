@tool
extends Node3D
class_name VirusModel9

# Design 9 — "Downpour": a data vial. A translucent shaft of code rain streams
# chevron dashes down from a bright crown into a glowing pool, sparks flying
# where they land. Reads as a tall terminal of falling >>>> — corruption
# downloading.

const SHAFT_RADIUS := 0.45
const SHAFT_HEIGHT := 2.2
const RAIN := 6
const RAIN_SPEED := 1.4

var _color := Color(1.0, 0.2, 0.4, 1.0)
var _mats: Array[StandardMaterial3D] = []
var _base_alphas: Array[float] = []
var _dashes: Array[MeshInstance3D] = []
var _dash_mats: Array[StandardMaterial3D] = []
var _dash_offsets: Array[Vector2] = []
var _dash_yaw: Array[float] = []
var _dash_speed: Array[float] = []
var _t := 0.0
var _cloaked := false
var _sparks: CPUParticles3D

func _ready() -> void:
	_build_shaft()
	_build_rain()
	_build_base()
	_build_sparks()

func _process(delta: float) -> void:
	_t += delta
	rotation.y = _t * 0.25
	position.y = sin(_t * 1.1) * 0.03
	var k := 0.12 if _cloaked else 1.0
	for i in _dashes.size():
		var p: float = fmod(_t * RAIN_SPEED * _dash_speed[i] / SHAFT_HEIGHT + float(i) / float(RAIN), 1.0)
		var y: float = SHAFT_HEIGHT + 0.1 - p * (SHAFT_HEIGHT + 0.15)
		_dashes[i].position = Vector3(_dash_offsets[i].x, y, _dash_offsets[i].y)
		_dashes[i].rotation.y = _dash_yaw[i] + _t * 0.4
		var fade := sin(p * PI)
		_dash_mats[i].albedo_color.a = _base_alphas[i] * fade * k

func set_player_color(c: Color) -> void:
	_color = c
	for m in _mats:
		m.albedo_color = Color(c.r, c.g, c.b, m.albedo_color.a)
		m.emission = c
	if _sparks:
		_sparks.color = c

func set_cloak(cloaked: bool) -> void:
	_cloaked = cloaked
	var k := 0.12 if cloaked else 1.0
	for i in _mats.size():
		_mats[i].albedo_color = Color(_color.r, _color.g, _color.b, _base_alphas[i] * k)
	if _sparks:
		_sparks.emitting = not cloaked

func _mat(c: Color, alpha: float, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.2
	_mats.append(m)
	_base_alphas.append(alpha)
	return m

func _build_shaft() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = SHAFT_RADIUS
	cyl.bottom_radius = SHAFT_RADIUS
	cyl.height = SHAFT_HEIGHT
	cyl.radial_segments = 32
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.position.y = SHAFT_HEIGHT * 0.5 + 0.05
	mi.material_override = _mat(_color, 0.06, true)
	add_child(mi)
	for y in [0.05, SHAFT_HEIGHT + 0.05]:
		var rim := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = SHAFT_RADIUS
		tor.outer_radius = SHAFT_RADIUS + 0.05
		tor.rings = 48
		tor.ring_segments = 8
		rim.mesh = tor
		rim.position.y = y
		rim.material_override = _mat(_color, 0.9, true)
		add_child(rim)

func _build_rain() -> void:
	for i in RAIN:
		var dash := MeshInstance3D.new()
		dash.mesh = _chevron_panel(0.42, 0.3)
		var ang: float = randf_range(0.0, TAU)
		var r: float = randf_range(0.0, SHAFT_RADIUS - 0.06)
		var mat := _mat(_color, 0.85, true)
		dash.material_override = mat
		add_child(dash)
		_dashes.append(dash)
		_dash_mats.append(mat)
		_dash_offsets.append(Vector2(cos(ang) * r, sin(ang) * r))
		_dash_yaw.append(randf_range(0.0, TAU))
		_dash_speed.append(randf_range(0.7, 1.3))

func _build_base() -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = SHAFT_RADIUS + 0.12
	cyl.bottom_radius = SHAFT_RADIUS + 0.12
	cyl.height = 0.04
	cyl.radial_segments = 48
	disc.mesh = cyl
	disc.position.y = 0.02
	disc.material_override = _mat(_color, 0.35, true)
	add_child(disc)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	sm.radial_segments = 24
	sm.rings = 12
	core.mesh = sm
	core.position.y = 0.14
	core.material_override = _mat(_color, 1.0, true)
	add_child(core)

func _build_sparks() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.amount = 20
	_sparks.lifetime = 0.8
	_sparks.emitting = true
	_sparks.gravity = Vector3(0, 0.3, 0)
	_sparks.initial_velocity_min = 0.3
	_sparks.initial_velocity_max = 1.1
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = SHAFT_RADIUS
	_sparks.scale_amount_min = 0.03
	_sparks.scale_amount_max = 0.08
	_sparks.color = _color
	_sparks.mesh = _particle_mesh()
	_sparks.position.y = 0.15
	add_child(_sparks)

func _particle_mesh() -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color.WHITE
	sm.material = m
	return sm

func _chevron_panel(span: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var notch := depth * 0.3
	var v := PackedVector3Array([
		Vector3(0, 0, depth),
		Vector3(span, 0, 0),
		Vector3(0, 0, -notch),
		Vector3(-span, 0, 0),
	])
	_tri(st, v[0], v[1], v[2])
	_tri(st, v[0], v[2], v[3])
	st.generate_normals()
	return st.commit()

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
