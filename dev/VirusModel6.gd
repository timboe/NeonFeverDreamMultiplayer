@tool
extends Node3D
class_name VirusModel6

# Design 6 — "Wraith": a hovering neon hunter whose great chevron wings beat in
# slow arcs, dragging sparks from their wingtips. From above it flares as a
# broad >< of pointy danger — a paper-plane predator gliding across the grid.

const WING_SPAN := 0.72
const WING_DEPTH := 0.95
const FLAP_SPEED := 2.1
const FLAP_AMP := 0.55

var _color := Color(1.0, 0.2, 0.4, 1.0)
var _mats: Array[StandardMaterial3D] = []
var _base_alphas: Array[float] = []
var _hinge_l := Node3D.new()
var _hinge_r := Node3D.new()
var _tail := Node3D.new()
var _t := 0.0
var _cloaked := false
var _spark_l: CPUParticles3D
var _spark_r: CPUParticles3D

func _ready() -> void:
	_build_body()
	_build_wings()
	_build_wing_sparks()

func _process(delta: float) -> void:
	_t += delta
	var flap := sin(_t * FLAP_SPEED) * FLAP_AMP
	_hinge_l.rotation.z = -flap
	_hinge_r.rotation.z = flap
	_tail.rotation.z = sin(_t * FLAP_SPEED * 0.5) * FLAP_AMP * 0.4
	position.y = sin(_t * 1.5) * 0.07
	rotation.z = sin(_t * 0.9) * 0.06

func set_player_color(c: Color) -> void:
	_color = c
	for m in _mats:
		m.albedo_color = Color(c.r, c.g, c.b, m.albedo_color.a)
		m.emission = c
	if _spark_l:
		_spark_l.color = c
	if _spark_r:
		_spark_r.color = c

func set_cloak(cloaked: bool) -> void:
	_cloaked = cloaked
	var k := 0.12 if cloaked else 1.0
	for i in _mats.size():
		_mats[i].albedo_color = Color(_color.r, _color.g, _color.b, _base_alphas[i] * k)
	if _spark_l:
		_spark_l.emitting = not cloaked
	if _spark_r:
		_spark_r.emitting = not cloaked

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

func _build_body() -> void:
	var lozenge := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.26, 0.16, 0.5)
	lozenge.mesh = box
	lozenge.position.y = 0.34
	lozenge.material_override = _mat(_color, 0.85, true)
	add_child(lozenge)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	sm.radial_segments = 24
	sm.rings = 12
	core.mesh = sm
	core.position = Vector3(0, 0.42, 0.18)
	core.material_override = _mat(_color, 1.0, true)
	add_child(core)
	var nose := MeshInstance3D.new()
	nose.mesh = _chevron_panel(0.22, 0.26)
	nose.position = Vector3(0, 0.3, 0.5)
	nose.material_override = _mat(_color, 0.9, true)
	add_child(nose)
	_tail.position = Vector3(0, 0.26, -0.52)
	var tail := MeshInstance3D.new()
	tail.mesh = _chevron_panel(0.18, 0.2)
	tail.rotation.y = PI
	tail.material_override = _mat(_color, 0.8, true)
	_tail.add_child(tail)
	add_child(_tail)

func _build_wings() -> void:
	for s in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(0, 0.35, 0)
		var wing := MeshInstance3D.new()
		wing.mesh = _chevron_panel(WING_SPAN, WING_DEPTH)
		wing.rotation.y = -PI / 2.0 if s < 0 else PI / 2.0
		wing.position = Vector3(s * 0.18, 0.0, 0.0)
		wing.material_override = _mat(_color, 0.72, true)
		hinge.add_child(wing)
		add_child(hinge)
		if s < 0:
			_hinge_l = hinge
		else:
			_hinge_r = hinge

func _build_wing_sparks() -> void:
	_spark_l = _make_wing_spark(-1.0)
	_spark_r = _make_wing_spark(1.0)
	_hinge_l.add_child(_spark_l)
	_hinge_r.add_child(_spark_r)

func _make_wing_spark(side: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.7
	p.emitting = true
	p.local_coords = true
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.09
	p.color = _color
	p.mesh = _particle_mesh()
	p.position = Vector3(side * (0.18 + WING_SPAN + 0.02), 0.06, 0)
	return p

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
