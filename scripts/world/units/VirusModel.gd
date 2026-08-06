@tool
extends Node3D
class_name VirusModel

# Design 8 — "Saw": a spinning razor disc. Two counter-rotating rings of
# overlapping chevron teeth interlock like a sawblade, whirring on a glowing
# hub with a spinning top's wobble. Reads from above as a blur of spinning
# >>>> — pointy danger you keep your distance from.
#
# Performance: each chevron ring is a single MultiMesh (one node / one draw
# call / one material), and the chevron + primitive meshes are static-shared
# across every Virus instance. Per unit this is 4 nodes / 4 draws / 4 materials.

const OUTER := {"radius": 1.15, "count": 12, "span": 0.34, "depth": 0.42, "spin": 0.95}
const INNER := {"radius": 0.62, "count": 8, "span": 0.26, "depth": 0.3, "spin": -1.2}
const LIFT_Y := 1.0

static var _mesh_cache: Dictionary = {}
static var _sphere_mesh: SphereMesh
static var _torus_mesh: TorusMesh

var _color := Color(1.0, 0.2, 0.4, 1.0)
var _mats: Array[StandardMaterial3D] = []
var _base_alphas: Array[float] = []
var _outer: MultiMeshInstance3D
var _inner: MultiMeshInstance3D
var _t := 0.0
var _cloaked := false

func _ready() -> void:
	_outer = _build_ring(OUTER, 0.08)
	_inner = _build_ring(INNER, 0.15)
	_build_hub()

func _process(delta: float) -> void:
	_t += delta
	_outer.rotation.y = -_t * OUTER["spin"]
	_inner.rotation.y = -_t * INNER["spin"]
	position.y = LIFT_Y + sin(_t * 1.6) * 0.05
	rotation.x = sin(_t * 2.1) * 0.07
	rotation.z = cos(_t * 2.1) * 0.07

func set_player_color(c: Color) -> void:
	_color = c
	for m in _mats:
		m.albedo_color = Color(c.r, c.g, c.b, m.albedo_color.a)
		m.emission = c

func set_cloak(cloaked: bool) -> void:
	_cloaked = cloaked
	var k := 0.12 if cloaked else 1.0
	for i in _mats.size():
		_mats[i].albedo_color = Color(_color.r, _color.g, _color.b, _base_alphas[i] * k)

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

func _build_ring(spec: Dictionary, y: float) -> MultiMeshInstance3D:
	var count: int = int(spec["count"])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _cached_chevron_mesh(spec["span"], spec["depth"])
	mm.instance_count = count
	for i in count:
		var a := TAU * i / float(count)
		var yaw := -a if spec["spin"] > 0 else PI - a
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw),
			Vector3(cos(a) * spec["radius"], 0, sin(a) * spec["radius"])))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position.y = y
	mmi.material_override = _mat(_color, 0.9, true)
	add_child(mmi)
	return mmi

func _build_hub() -> void:
	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radius = 0.1
		_sphere_mesh.height = 0.2
		_sphere_mesh.radial_segments = 24
		_sphere_mesh.rings = 12
	var hub := MeshInstance3D.new()
	hub.mesh = _sphere_mesh
	hub.position.y = 0.16
	hub.material_override = _mat(_color, 1.0, true)
	add_child(hub)
	if _torus_mesh == null:
		_torus_mesh = TorusMesh.new()
		_torus_mesh.inner_radius = 0.9
		_torus_mesh.outer_radius = 0.92
		_torus_mesh.rings = 72
		_torus_mesh.ring_segments = 8
	var ring := MeshInstance3D.new()
	ring.mesh = _torus_mesh
	ring.position.y = 0.12
	ring.material_override = _mat(_color, 0.7, true)
	add_child(ring)

func _cached_chevron_mesh(span: float, depth: float) -> ArrayMesh:
	var key := str(span) + "_" + str(depth)
	if not _mesh_cache.has(key):
		_mesh_cache[key] = _chevron_panel(span, depth)
	return _mesh_cache[key]

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
