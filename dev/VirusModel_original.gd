extends Node3D
class_name VirusModelLegacy

# Procedural model for the VIRUS unit: a churning electric "unknown core"
# wrapped in an angular wireframe cage, belts of tight chevrons that orbit it,
# a flat light-ring, flickering arcs and an electric cloud (diffuse haze +
# bright sparks). Built at _ready on every spawned unit (all peers) so each
# copy gets independent materials and motion.

# --- Constants ---

const CORE_RADIUS := 0.8
const CORE_CENTER_Y := 1.45
const RING_RADIUS := 1.5
const RING_TUBE := 0.05
const RING_Y := 0.07

const CAGE_RADIUS := 1.0
const CAGE_SPIN := 0.15

const CHEVRON_T := 0.05 # plate thickness
const CHEVRON_W := 0.1  # ribbon width
const CHEVRON_BELTS := [
	{"radius": 1.3, "y": 0.5, "count": 14, "span": 0.38, "depth": 0.4, "spin": 0.6},
	{"radius": 0.95, "y": 1.05, "count": 10, "span": 0.28, "depth": 0.3, "spin": -0.45},
]

const ARC_COUNT := 4
const ARC_SEGMENTS := 9
const ARC_UPDATE := 0.07
const ARC_TOP_Y := 2.3

const CLOUD_COUNT := 90
const SPARK_COUNT := 35

# --- State ---

var _color := Color(1.0, 0.2, 0.4, 1.0)
var _core_mat: ShaderMaterial
var _chevron_mats: Array[StandardMaterial3D] = []
var _ring_mat: StandardMaterial3D
var _cage_mat: StandardMaterial3D
var _arc_color := Color.WHITE
var _arc_immediate := ImmediateMesh.new()
var _arc_rng := RandomNumberGenerator.new()
var _arc_timer := 0.0
var _bob_phase := 0.0
var _belt_nodes: Array[Node3D] = []
var _belt_spins: Array[float] = []
var _cage_node: Node3D
var _cloud: CPUParticles3D
var _sparks: CPUParticles3D

@onready var _core: MeshInstance3D = $CSG
@onready var _arcs: MeshInstance3D = $Arcs

# Chevron meshes are pure geometry and identical across units, so cache them.
static var _chevron_mesh_cache: Dictionary = {}

# --- Lifecycle ---

func _ready() -> void:
	_arc_rng.randomize()
	_build_core()
	_build_ring()
	_build_cage()
	_build_belts()
	_build_arcs()
	_build_motes()

func _process(delta: float) -> void:
	_bob_phase += delta
	position.y = sin(_bob_phase * 1.4) * 0.07
	for i in _belt_nodes.size():
		var node: Node3D = _belt_nodes[i]
		node.rotation.y += _belt_spins[i] * delta
	if _cage_node:
		_cage_node.rotation.y += CAGE_SPIN * delta
		_cage_node.rotation.x += CAGE_SPIN * 0.4 * delta
	_arc_timer -= delta
	if _arcs.visible and _arc_timer <= 0.0:
		_arc_timer = ARC_UPDATE
		_redraw_arcs()

# --- Public API (called by Virus.gd) ---

func set_player_color(c: Color) -> void:
	_color = c
	if _core_mat:
		_core_mat.set_shader_parameter("player_color", c)
	for m in _chevron_mats:
		m.albedo_color = Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, m.albedo_color.a)
		m.emission = c
	if _ring_mat:
		_ring_mat.albedo_color = Color(c.r, c.g, c.b, _ring_mat.albedo_color.a)
	if _cage_mat:
		_cage_mat.albedo_color = Color(c.r, c.g, c.b, _cage_mat.albedo_color.a)
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
	if _cage_mat:
		_cage_mat.albedo_color.a = alpha
	if _arcs:
		_arcs.visible = not cloaked
	if _cloud:
		_cloud.emitting = not cloaked
	if _sparks:
		_sparks.emitting = not cloaked

# --- Builders ---

func _build_core() -> void:
	var sm := SphereMesh.new()
	sm.radius = CORE_RADIUS
	sm.height = CORE_RADIUS * 2.0
	sm.radial_segments = 32
	sm.rings = 24
	_core.mesh = sm
	_core.position.y = CORE_CENTER_Y
	var shader := load("res://dev/virus_core.gdshader") as Shader
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = shader
	_core_mat.set_shader_parameter("player_color", _color)
	_core_mat.set_shader_parameter("cloak_alpha", 1.0)
	_core_mat.set_shader_parameter("energy", 1.0)
	_core_mat.set_shader_parameter("churn_seed", _arc_rng.randf_range(0.0, 10.0))
	_core.material_override = _core_mat

func _build_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - RING_TUBE * 0.5
	torus.outer_radius = RING_RADIUS + RING_TUBE * 0.5
	torus.rings = 72
	torus.ring_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.position.y = RING_Y
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = _color
	mi.material_override = _ring_mat
	add_child(mi)

func _build_cage() -> void:
	_cage_node = Node3D.new()
	_cage_node.position.y = CORE_CENTER_Y
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES)
	var r := CAGE_RADIUS
	var vs: Array[Vector3] = [
		Vector3(r, 0, 0), Vector3(-r, 0, 0),
		Vector3(0, r, 0), Vector3(0, -r, 0),
		Vector3(0, 0, r), Vector3(0, 0, -r),
	]
	for i in vs.size():
		for j in range(i + 1, vs.size()):
			if vs[i].is_equal_approx(-vs[j]):
				continue
			imm.surface_add_vertex(vs[i])
			imm.surface_add_vertex(vs[j])
	imm.surface_end()
	_cage_mat = StandardMaterial3D.new()
	_cage_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cage_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cage_mat.albedo_color = _color
	var mi := MeshInstance3D.new()
	mi.mesh = imm
	mi.material_override = _cage_mat
	_cage_node.add_child(mi)
	add_child(_cage_node)

func _build_belts() -> void:
	for belt in CHEVRON_BELTS:
		var root := Node3D.new()
		root.position.y = belt["y"]
		var chevron_mesh := _cached_chevron_mesh(belt["span"], belt["depth"])
		var count: int = belt["count"]
		for i in count:
			var a: float = TAU * i / float(count)
			var mi := MeshInstance3D.new()
			mi.mesh = chevron_mesh
			mi.position = Vector3(cos(a) * belt["radius"], 0, sin(a) * belt["radius"])
			# Tip points along the orbit tangent in the belt's spin direction,
			# so chevrons always lead their direction of travel.
			mi.rotation.y = -a if belt["spin"] < 0.0 else PI - a
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.metallic = 0.8
			mat.roughness = 0.3
			mat.albedo_color = Color(_color.r * 0.35, _color.g * 0.35, _color.b * 0.35, 1.0)
			mat.emission_enabled = true
			mat.emission = _color
			mat.emission_energy_multiplier = 2.4
			mi.material_override = mat
			root.add_child(mi)
			_chevron_mats.append(mat)
		_belt_nodes.append(root)
		_belt_spins.append(belt["spin"])
		add_child(root)
		root.rotation.y = _arc_rng.randf_range(-0.3, 0.3)

func _build_arcs() -> void:
	_arcs.mesh = _arc_immediate
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	_arcs.material_override = mat
	_arcs.visible = false

func _build_motes() -> void:
	_cloud = _make_particles(CLOUD_COUNT, 5.0, 0.7, 0.15, Vector3(0, 0.7, 0), 1.2, 0.4, 0.85,
		Color(_color.r, _color.g, _color.b, 0.22))
	_sparks = _make_particles(SPARK_COUNT, 2.2, 1.6, 0.4, Vector3(0, 1.8, 0), 1.15, 0.12, 0.3,
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

# --- Chevron mesh (SurfaceTool ribbon along a V path) ---

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
	var base_radius := RING_RADIUS - 0.2
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
