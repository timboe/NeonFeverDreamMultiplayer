@tool
extends Node3D
class_name VirusModelBase

# Shared builders for the VIRUS unit model designs. Each design scene
# (Virus1.tscn etc.) has a script extending this that implements
# _build_design(). Visual-only, runs on all peers. @tool so the designs are
# visible when opening the scenes in the editor.

# --- Constants ---

const CHEVRON_T := 0.05 # plate thickness
const CHEVRON_W := 0.1  # ribbon width
const RING_TUBE := 0.05
const ARC_UPDATE := 0.07
const ARC_COUNT := 4
const ARC_SEGMENTS := 9
const ARC_TOP_Y := 2.3

# --- State ---

var _color := Color(1.0, 0.2, 0.4, 1.0)
var _core_mat: ShaderMaterial
var _chevron_mats: Array[StandardMaterial3D] = []
var _cage_mats: Array[StandardMaterial3D] = []
var _ring_mat: StandardMaterial3D
var _arc_color := Color.WHITE
var _arc_immediate := ImmediateMesh.new()
var _arc_rng := RandomNumberGenerator.new()
var _arc_timer := 0.0
var _bob_phase := 0.0
var _bob_amplitude := 0.06
var _cloud: CPUParticles3D
var _sparks: CPUParticles3D
var _spin_nodes: Array = []
var _spin_speeds: Array[float] = []
var _built := false

@onready var _csg: MeshInstance3D = $CSG
@onready var _arc_node: MeshInstance3D = $Arcs

static var _chevron_mesh_cache: Dictionary = {}

# --- Lifecycle ---

func _ready() -> void:
	if _built:
		return
	_built = true
	_arc_rng.randomize()
	_build_design()

func _process(delta: float) -> void:
	_bob_phase += delta
	position.y = sin(_bob_phase * 1.4) * _bob_amplitude
	for i in _spin_nodes.size():
		var n: Node3D = _spin_nodes[i]
		n.rotation.y += _spin_speeds[i] * delta
	_arc_timer -= delta
	if _arc_node and _arc_node.visible and _arc_timer <= 0.0:
		_arc_timer = ARC_UPDATE
		_redraw_arcs()

# --- Design hook ---

func _build_design() -> void:
	pass

# --- Public API (called by Virus.gd when integrated) ---

func set_player_color(c: Color) -> void:
	_color = c
	if _core_mat:
		_core_mat.set_shader_parameter("player_color", c)
	for m in _chevron_mats:
		m.albedo_color = Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, m.albedo_color.a)
		m.emission = c
	if _ring_mat:
		_ring_mat.albedo_color = Color(c.r, c.g, c.b, _ring_mat.albedo_color.a)
	for m in _cage_mats:
		m.albedo_color = Color(c.r, c.g, c.b, m.albedo_color.a)
	_arc_color = c
	if _cloud:
		_cloud.color = Color(c.r, c.g, c.b, _cloud.color.a)
	if _sparks:
		_sparks.color = Color(c.r, c.g, c.b, _sparks.color.a)

func set_cloak(cloaked: bool) -> void:
	var alpha := 0.15 if cloaked else 1.0
	if _core_mat:
		_core_mat.set_shader_parameter("cloak_alpha", alpha)
		_core_mat.set_shader_parameter("energy", 1.0 if cloaked else 1.7)
	for m in _chevron_mats:
		m.albedo_color.a = alpha
		m.emission_energy_multiplier = 0.6 if cloaked else 2.4
	if _ring_mat:
		_ring_mat.albedo_color.a = alpha
	for m in _cage_mats:
		m.albedo_color.a = alpha
	if _arc_node:
		_arc_node.visible = not cloaked
	if _cloud:
		_cloud.emitting = not cloaked
	if _sparks:
		_sparks.emitting = not cloaked

# --- Shared builders ---

func _build_core(radius: float, center_y: float) -> void:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 32
	sm.rings = 24
	_csg.mesh = sm
	_csg.position.y = center_y
	var shader := load("res://dev/virus_core.gdshader") as Shader
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = shader
	_core_mat.set_shader_parameter("player_color", _color)
	_core_mat.set_shader_parameter("cloak_alpha", 1.0)
	_core_mat.set_shader_parameter("energy", 1.0)
	_core_mat.set_shader_parameter("churn_seed", _arc_rng.randf_range(0.0, 10.0))
	_csg.material_override = _core_mat

func _build_ring(radius: float, y: float) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - RING_TUBE * 0.5
	torus.outer_radius = radius + RING_TUBE * 0.5
	torus.rings = 72
	torus.ring_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.position.y = y
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = _color
	mi.material_override = _ring_mat
	add_child(mi)

func _build_cage(radius: float, center_y: float) -> Node3D:
	var node := Node3D.new()
	node.position.y = center_y
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES)
	var vs: Array[Vector3] = [
		Vector3(radius, 0, 0), Vector3(-radius, 0, 0),
		Vector3(0, radius, 0), Vector3(0, -radius, 0),
		Vector3(0, 0, radius), Vector3(0, 0, -radius),
	]
	for i in vs.size():
		for j in range(i + 1, vs.size()):
			if vs[i].is_equal_approx(-vs[j]):
				continue
			imm.surface_add_vertex(vs[i])
			imm.surface_add_vertex(vs[j])
	imm.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = _color
	var mi := MeshInstance3D.new()
	mi.mesh = imm
	mi.material_override = mat
	node.add_child(mi)
	_cage_mats.append(mat)
	add_child(node)
	return node

func _build_arcs() -> void:
	_arc_node.mesh = _arc_immediate
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	_arc_node.material_override = mat
	_arc_node.visible = true

func _build_motes(cloud_count: int, spark_count: int) -> void:
	_cloud = _make_particles(cloud_count, 5.0, 0.7, 0.15, Vector3(0, 0.7, 0), 1.2, 0.4, 0.85,
		Color(_color.r, _color.g, _color.b, 0.22))
	_sparks = _make_particles(spark_count, 2.2, 1.6, 0.4, Vector3(0, 1.8, 0), 1.15, 0.12, 0.3,
		Color(_color.r, _color.g, _color.b, 1.0))

func _make_particles(amount: int, lifetime: float, vel_max: float, vel_min: float, gravity: Vector3,
		radius: float, scale_min: float, scale_max: float, tint: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = true
	p.gravity = gravity
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	p.color = tint
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.albedo_color = Color.WHITE
	sm.material = pm
	p.mesh = sm
	add_child(p)
	return p

# --- Chevron helpers ---

func _radial_yaw(a: float, inward := false) -> float:
	# Chevron tip (+Z) points radially, i.e. 90 deg to the orbital motion.
	return PI / 2.0 - a if not inward else -PI / 2.0 - a

func _tangent_yaw(a: float, spin: float) -> float:
	# Chevron tip (+Z) wraps along the direction of orbital motion.
	return -a if spin < 0.0 else PI - a

func _make_chevron_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.8
	mat.roughness = 0.3
	mat.albedo_color = Color(_color.r * 0.35, _color.g * 0.35, _color.b * 0.35, 1.0)
	mat.emission_enabled = true
	mat.emission = _color
	mat.emission_energy_multiplier = 2.4
	return mat

func _spawn_chevron(parent: Node, span: float, depth: float, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _cached_chevron_mesh(span, depth)
	mi.position = pos
	mi.rotation = rot
	var mat := _make_chevron_material()
	mi.material_override = mat
	_chevron_mats.append(mat)
	parent.add_child(mi)
	return mi

func _add_spin(node: Node3D, speed: float) -> void:
	_spin_nodes.append(node)
	_spin_speeds.append(speed)

func _cached_chevron_mesh(span: float, depth: float) -> ArrayMesh:
	var key := str(span) + "_" + str(depth)
	if _chevron_mesh_cache.has(key):
		return _chevron_mesh_cache[key]
	var mesh := _make_chevron_mesh(span, depth)
	_chevron_mesh_cache[key] = mesh
	return mesh

func _make_chevron_mesh(span: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var path: Array[Vector3] = [
		Vector3(0, 0, depth),
		Vector3(span, 0, 0),
		Vector3(0, 0, depth),
		Vector3(-span, 0, 0),
	]
	for i in range(path.size() - 1):
		_add_ribbon_segment(st, path[i], path[i + 1])
	st.generate_normals()
	return st.commit()

func _add_ribbon_segment(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var dir := b - a
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var n := Vector3(dir.z, 0, -dir.x)
	var w := CHEVRON_W * 0.5
	var t := CHEVRON_T
	var up := Vector3.UP
	var p0 := a + n * w + up * t
	var p1 := a - n * w + up * t
	var p2 := b - n * w + up * t
	var p3 := b + n * w + up * t
	var p4 := p0 - up * t
	var p5 := p1 - up * t
	var p6 := p2 - up * t
	var p7 := p3 - up * t
	_add_quad(st, p0, p1, p2, p3, up)
	_add_quad(st, p4, p7, p6, p5, -up)
	_add_quad(st, p1, p5, p6, p2, -n)
	_add_quad(st, p0, p3, p7, p4, n)
	_add_quad(st, p0, p4, p5, p1, -dir)
	_add_quad(st, p3, p2, p6, p7, dir)

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, desired: Vector3) -> void:
	var normal := (b - a).cross(c - b)
	if normal.dot(desired) < 0.0:
		var tmp := a
		a = d
		d = tmp
		tmp = b
		b = c
		c = tmp
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(c)
	st.add_vertex(d)
	st.add_vertex(a)

# --- Electric arcs ---

func _redraw_arcs() -> void:
	_arc_immediate.clear_surfaces()
	_arc_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	_arc_immediate.surface_set_color(_arc_color)
	var base_radius := 1.3
	for i in ARC_COUNT:
		var a0 := TAU * i / ARC_COUNT + _arc_rng.randf_range(-0.06, 0.06)
		var from := Vector3(cos(a0) * base_radius, 0.15, sin(a0) * base_radius)
		var tip := Vector3(_arc_rng.randf_range(-0.2, 0.2), ARC_TOP_Y, _arc_rng.randf_range(-0.2, 0.2))
		for s in range(1, ARC_SEGMENTS + 1):
			var tt := float(s) / float(ARC_SEGMENTS)
			var p := from.lerp(tip, tt)
			if s < ARC_SEGMENTS:
				p += Vector3(_arc_rng.randf_range(-0.3, 0.3), 0, _arc_rng.randf_range(-0.3, 0.3)) * (0.3 + tt)
			else:
				p = tip
			_arc_immediate.surface_add_vertex(from)
			_arc_immediate.surface_add_vertex(p)
			from = p
	_arc_immediate.surface_end()
