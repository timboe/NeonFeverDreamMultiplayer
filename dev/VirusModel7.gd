@tool
extends Node3D
class_name VirusModel7

# Design 7 — "Serpent": a crawling computer worm. A spine of chevron segments
# undulates with a travelling sine wave, slithering in place and slowly
# circling while a bright head leads the way. Reads from above as a wiggling
# >>>>> — pure creeping danger.

const SEGMENTS := 8
const SEG_SPACING := 0.38
const WAVE_SPEED := 4.5
const WAVE_PHASE := 0.95
const WAVE_AMP := 0.16
const CRAWL_SPEED := 0.35

var _color := Color(1.0, 0.2, 0.4, 1.0)
var _mats: Array[StandardMaterial3D] = []
var _base_alphas: Array[float] = []
var _segs: Array[MeshInstance3D] = []
var _joints: Array[MeshInstance3D] = []
var _head: MeshInstance3D
var _head_core: MeshInstance3D
var _t := 0.0
var _cloaked := false
var _sparks: CPUParticles3D

func _ready() -> void:
	_build_body()
	_build_sparks()

func _process(delta: float) -> void:
	_t += delta
	rotation.y = _t * CRAWL_SPEED
	position.y = sin(_t * 1.3) * 0.04
	var hw := sin(_t * WAVE_SPEED + WAVE_PHASE)
	_head.position.x = hw * WAVE_AMP * 0.7
	_head.position.y = 0.24 + hw * WAVE_AMP * 0.5
	_head.rotation.y = hw * 0.5
	_head_core.position.x = _head.position.x
	_head_core.position.y = _head.position.y + 0.08
	for i in _segs.size():
		var w := sin(_t * WAVE_SPEED - i * WAVE_PHASE)
		var seg: MeshInstance3D = _segs[i]
		seg.position.x = w * WAVE_AMP * 0.7
		seg.position.y = 0.22 + w * WAVE_AMP * 0.5
		seg.rotation.y = w * 0.5
		seg.rotation.z = cos(_t * WAVE_SPEED - i * WAVE_PHASE) * 0.18
		var joint: MeshInstance3D = _joints[i]
		joint.position.x = seg.position.x
		joint.position.y = seg.position.y + 0.06

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

func _build_body() -> void:
	for i in SEGMENTS:
		var tt := float(i) / float(SEGMENTS - 1)
		var span: float = lerpf(0.34, 0.16, tt)
		var depth: float = lerpf(0.4, 0.2, tt)
		var seg := MeshInstance3D.new()
		seg.mesh = _chevron_panel(span, depth)
		seg.position = Vector3(0, 0.22, (SEGMENTS - 1 - i) * SEG_SPACING)
		seg.material_override = _mat(_color, 0.85, true)
		add_child(seg)
		_segs.append(seg)
		var joint := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		sm.radial_segments = 16
		sm.rings = 8
		joint.mesh = sm
		joint.position = Vector3(0, 0.28, (SEGMENTS - 1 - i) * SEG_SPACING)
		joint.material_override = _mat(_color, 1.0, true)
		add_child(joint)
		_joints.append(joint)
	var head_z := (SEGMENTS - 1) * SEG_SPACING + 0.55
	_head = MeshInstance3D.new()
	_head.mesh = _chevron_panel(0.42, 0.5)
	_head.position = Vector3(0, 0.24, head_z)
	_head.material_override = _mat(_color, 0.95, true)
	add_child(_head)
	_head_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 24
	sm.rings = 12
	_head_core.mesh = sm
	_head_core.position = Vector3(0, 0.32, head_z)
	_head_core.material_override = _mat(_color, 1.0, true)
	add_child(_head_core)

func _build_sparks() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.amount = 18
	_sparks.lifetime = 0.9
	_sparks.emitting = true
	_sparks.gravity = Vector3(0, 0.5, 0)
	_sparks.initial_velocity_min = 0.2
	_sparks.initial_velocity_max = 1.0
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 1.2
	_sparks.scale_amount_min = 0.03
	_sparks.scale_amount_max = 0.08
	_sparks.color = _color
	_sparks.mesh = _particle_mesh()
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
