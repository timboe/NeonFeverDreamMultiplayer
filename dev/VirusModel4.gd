@tool
extends Node3D
class_name VirusModel4

# Design 4 — "Sonar": a hovering detection disc that never stops pinging.
# A glowing radar face with a rotating sweep arm of chevron blades, four
# standing chevron ticks at the compass points and sonar rings that flare
# outward from the hub — an active, pointy warning beacon that reads cleanly
# from above.

const DISC_RADIUS := 1.1
const SWEEP_SPEED := 1.6
const PING_COUNT := 3
const PING_PERIOD := 2.2
const PING_ALPHA := 0.65

var _color := Color(1.0, 0.2, 0.4, 1.0)
var _mats: Array[StandardMaterial3D] = []
var _base_alphas: Array[float] = []
var _sweep := Node3D.new()
var _ping_nodes: Array[MeshInstance3D] = []
var _ping_mats: Array[StandardMaterial3D] = []
var _t := 0.0
var _cloaked := false
var _sparks: CPUParticles3D

func _ready() -> void:
	_build_disc()
	_build_ticks()
	_build_sweep()
	_build_pings()
	_build_sparks()

func _process(delta: float) -> void:
	_t += delta
	position.y = sin(_t * 1.4) * 0.03
	_sweep.rotation.y = _t * SWEEP_SPEED
	var k := 0.12 if _cloaked else 1.0
	for i in _ping_nodes.size():
		var tt := fmod(_t / PING_PERIOD + float(i) / float(PING_COUNT), 1.0)
		var s := 0.3 + tt * 2.1
		_ping_nodes[i].scale = Vector3(s, s, 1.0)
		_ping_mats[i].albedo_color.a = PING_ALPHA * (1.0 - tt) * k

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

func _build_disc() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = DISC_RADIUS
	cyl.bottom_radius = DISC_RADIUS
	cyl.height = 0.03
	cyl.radial_segments = 64
	var fill := MeshInstance3D.new()
	fill.mesh = cyl
	fill.position.y = 0.03
	fill.material_override = _mat(_color, 0.16, true)
	add_child(fill)
	var tor := TorusMesh.new()
	tor.inner_radius = DISC_RADIUS
	tor.outer_radius = DISC_RADIUS + 0.06
	tor.rings = 96
	tor.ring_segments = 8
	var rim := MeshInstance3D.new()
	rim.mesh = tor
	rim.position.y = 0.05
	rim.material_override = _mat(_color, 0.9, true)
	add_child(rim)
	var hub := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 24
	sm.rings = 12
	hub.mesh = sm
	hub.position.y = 0.1
	hub.material_override = _mat(_color, 1.0, true)
	add_child(hub)

func _build_ticks() -> void:
	for i in 4:
		var a := TAU * i / 4.0
		var pivot := Node3D.new()
		pivot.position = Vector3(cos(a) * DISC_RADIUS, 0.01, sin(a) * DISC_RADIUS)
		pivot.rotation.y = a
		var mi := MeshInstance3D.new()
		mi.mesh = _chevron_prism(0.22, 0.26, 0.36)
		mi.material_override = _mat(_color, 0.85, false)
		pivot.add_child(mi)
		add_child(pivot)

func _build_sweep() -> void:
	_sweep.position.y = 0.03
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.022, 0.02, DISC_RADIUS * 0.85)
	beam.mesh = box
	beam.position = Vector3(0, 0.02, DISC_RADIUS * 0.42)
	beam.material_override = _mat(_color, 0.7, true)
	_sweep.add_child(beam)
	for r in [0.4, 0.75, 1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = _chevron_prism(0.24, 0.3, 0.05)
		mi.position = Vector3(0, 0.05, r)
		mi.material_override = _mat(_color, 0.95, false)
		_sweep.add_child(mi)
	add_child(_sweep)

func _build_pings() -> void:
	for i in PING_COUNT:
		var tor := TorusMesh.new()
		tor.inner_radius = 0.5
		tor.outer_radius = 0.53
		tor.rings = 72
		tor.ring_segments = 8
		var mi := MeshInstance3D.new()
		mi.mesh = tor
		mi.position.y = 0.09
		var m := _mat(_color, PING_ALPHA, true)
		mi.material_override = m
		add_child(mi)
		_ping_nodes.append(mi)
		_ping_mats.append(m)

func _build_sparks() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.amount = 24
	_sparks.lifetime = 1.0
	_sparks.emitting = true
	_sparks.gravity = Vector3(0, 0.4, 0)
	_sparks.initial_velocity_min = 0.3
	_sparks.initial_velocity_max = 1.3
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = DISC_RADIUS
	_sparks.scale_amount_min = 0.04
	_sparks.scale_amount_max = 0.12
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

func _chevron_prism(span: float, depth: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var notch := depth * 0.3
	var top := PackedVector3Array([
		Vector3(0, height, depth),
		Vector3(span, height, 0),
		Vector3(0, height, -notch),
		Vector3(-span, height, 0),
	])
	var bot := PackedVector3Array([
		Vector3(0, 0, depth),
		Vector3(span, 0, 0),
		Vector3(0, 0, -notch),
		Vector3(-span, 0, 0),
	])
	_tri(st, top[0], top[1], top[2])
	_tri(st, top[0], top[2], top[3])
	_tri(st, bot[0], bot[2], bot[1])
	_tri(st, bot[0], bot[3], bot[2])
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, top[i], top[j], bot[j], bot[i])
	st.generate_normals()
	return st.commit()

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
