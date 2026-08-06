@tool
extends Node3D
class_name VirusModel

# Design 8 — "Saw": a spinning razor disc. Two counter-rotating rings of
# overlapping chevron teeth interlock like a sawblade, whirring on a glowing
# hub with a spinning top's wobble. Reads from above as a blur of spinning
# >>>> — pointy danger you keep your distance from.

const OUTER := {"radius": 1.15, "count": 12, "span": 0.34, "depth": 0.42, "spin": 0.95}
const INNER := {"radius": 0.62, "count": 8, "span": 0.26, "depth": 0.3, "spin": -1.2}
const LIFT_Y := 0.8

var _color := Color(1.0, 0.2, 0.4, 1.0)
var _mats: Array[StandardMaterial3D] = []
var _base_alphas: Array[float] = []
var _outer := Node3D.new()
var _inner := Node3D.new()
var _t := 0.0
var _cloaked := false

func _ready() -> void:
	_build_ring(OUTER, _outer, 0.08)
	_build_ring(INNER, _inner, 0.15)
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

func _build_ring(spec: Dictionary, node: Node3D, y: float) -> void:
	node.position.y = y
	for i in int(spec["count"]):
		var a := TAU * i / float(spec["count"])
		var seg := MeshInstance3D.new()
		seg.mesh = _chevron_panel(spec["span"], spec["depth"])
		seg.position = Vector3(cos(a) * spec["radius"], 0, sin(a) * spec["radius"])
		seg.rotation.y = -a if spec["spin"] > 0 else PI - a
		seg.material_override = _mat(_color, 0.9, true)
		node.add_child(seg)
	add_child(node)

func _build_hub() -> void:
	var hub := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	sm.radial_segments = 24
	sm.rings = 12
	hub.mesh = sm
	hub.position.y = 0.16
	hub.material_override = _mat(_color, 1.0, true)
	add_child(hub)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.9
	tor.outer_radius = 0.92
	tor.rings = 72
	tor.ring_segments = 8
	ring.mesh = tor
	ring.position.y = 0.12
	ring.material_override = _mat(_color, 0.7, true)
	add_child(ring)

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
