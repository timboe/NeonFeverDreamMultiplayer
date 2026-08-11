@tool
extends Node3D
class_name AerialModel

# "Hexdrone": a rugged hex-bodied quadcopter. Four outrigger arms
# carry big spinning rotors. Radial symmetry is the theme: a centre dot caps the
# hull and a belly cannon hangs from the bottom centre, so the craft reads the
# same from every heading. Everything wears the owner's colour.
#
# This is the production AERIAL model (scenes/world/units/Aerial.tscn). The
# root runs Aerial.gd for gameplay; this node builds and animates the full
# model. Player branding: Aerial.gd paints the CSG hull via the surface
# override, then calls set_player_color() here so the arms, rotor hubs and
# centre sensor match. set_player_color() assigns a fresh per-instance material
# each call, so units spawned from the same factory template never share a
# colour.
#
# Instantiate-safe: UnitManager spawns aerials from the packed scene, so
# _ready() builds the model once (the has_node("Arms") guard also protects the
# editor / duplicated legacy copies), and _process() re-locates the blade
# MultiMesh against the local tree. Draw-call lean: all repeated geometry is
# instanced via MultiMesh — four arms share one mesh, four rotor hubs one mesh,
# four blades one mesh. Total meshes rendered: CSG hull + arms + hubs + blades
# + sensor + gun barrel = 6 draw calls.

const ROTOR_SPEED := 20.0
const ROTOR_DIRS := [1.0, -1.0, 1.0, -1.0]
const ROTOR_POS := [
	Vector3(0.95, 0.12, 0.95),
	Vector3(0.95, 0.12, -0.95),
	Vector3(-0.95, 0.12, -0.95),
	Vector3(-0.95, 0.12, 0.95),
]

var _blade_mmi: MultiMeshInstance3D
var _blade_angles: Array[float] = [0.0, 0.0, 0.0, 0.0]
# Rotor buffer writes at 30 Hz instead of per frame — 4 set_instance_transform
# calls per airframe per frame were dirtying the MultiMesh buffer 60×/s.
const ROTOR_INTERVAL := 0.033
var _rotor_timer := 0.0

@onready var _csg: MeshInstance3D = $CSG

static var _hex_mesh_cache: CylinderMesh
static var _arm_mesh_cache: BoxMesh
static var _hub_mesh_cache: BoxMesh
static var _sensor_mesh_cache: SphereMesh
static var _barrel_mesh_cache: CylinderMesh
static var _blade_mesh_cache: ArrayMesh
static var _dark_mat_cache: StandardMaterial3D
static var _chrome_mat_cache: StandardMaterial3D

# --- Lifecycle ---

func _ready() -> void:
	scale = Vector3(1.5, 1.5, 1.5)
	if has_node("Arms"):
		return
	_build()

func _process(delta: float) -> void:
	if _blade_mmi == null or not is_instance_valid(_blade_mmi) or _blade_mmi.get_parent() != self:
		_blade_mmi = get_node_or_null("Blades")
	if _blade_mmi == null:
		return
	_rotor_timer += delta
	if _rotor_timer < ROTOR_INTERVAL:
		return
	for i in ROTOR_POS.size():
		_blade_angles[i] += _rotor_timer * ROTOR_SPEED * ROTOR_DIRS[i]
		_blade_mmi.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _blade_angles[i]), ROTOR_POS[i]))
	_rotor_timer = 0.0

# --- Player branding (called by Aerial.gd after the hull is painted) ---

func set_player_color(c: Color) -> void:
	var m := _new_brand_mat(c)
	$Arms.material_override = m
	$Hubs.material_override = m
	$Sensor.material_override = m

# --- Build ---

func _build() -> void:
	_csg.mesh = _hex_mesh()
	_build_arms()
	_build_rotors()
	_build_sensor()
	_build_gun()
	var m := _new_brand_mat(Color(0.1, 0.9, 0.7, 1.0))
	$Arms.material_override = m
	$Hubs.material_override = m
	$Sensor.material_override = m

func _new_brand_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, 1.0)
	m.metallic = 0.9
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.2
	return m

func _build_arms() -> void:
	var am := MultiMesh.new()
	am.transform_format = MultiMesh.TRANSFORM_3D
	am.mesh = _arm_mesh()
	am.instance_count = 4
	for i in 4:
		var a := deg_to_rad(45.0 + i * 90.0)
		var p := Vector3(cos(a) * 0.849, 0.06, sin(a) * 0.849)
		am.set_instance_transform(i, Transform3D(Basis(Vector3.UP, a), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Arms"
	mmi.multimesh = am
	add_child(mmi)

func _build_rotors() -> void:
	var hm := MultiMesh.new()
	hm.transform_format = MultiMesh.TRANSFORM_3D
	hm.mesh = _hub_mesh()
	hm.instance_count = ROTOR_POS.size()
	for i in ROTOR_POS.size():
		hm.set_instance_transform(i, Transform3D(Basis(), ROTOR_POS[i]))
	var hub_mmi := MultiMeshInstance3D.new()
	hub_mmi.name = "Hubs"
	hub_mmi.multimesh = hm
	add_child(hub_mmi)

	var bm := MultiMesh.new()
	bm.transform_format = MultiMesh.TRANSFORM_3D
	bm.mesh = _blade_mesh()
	bm.instance_count = ROTOR_POS.size()
	for i in ROTOR_POS.size():
		bm.set_instance_transform(i, Transform3D(Basis(), ROTOR_POS[i]))
	_blade_mmi = MultiMeshInstance3D.new()
	_blade_mmi.name = "Blades"
	_blade_mmi.multimesh = bm
	_blade_mmi.material_override = _dark_mat()
	add_child(_blade_mmi)

func _build_sensor() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Sensor"
	mi.mesh = _sensor_mesh()
	mi.position = Vector3(0, 0.16, 0)
	add_child(mi)

func _build_gun() -> void:
	$Gun.position = Vector3(0, -0.16, 0)
	$Gun.rotation_degrees = Vector3(90, 0, 0)
	$Gun/Muzzle.position = Vector3(0, 0, 0.55)
	var barrel := MeshInstance3D.new()
	barrel.mesh = _barrel_mesh()
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0, 0.275)
	barrel.material_override = _chrome_mat()
	barrel.name = "Barrel"
	$Gun.add_child(barrel)

# --- Cached primitives (shared across every Hexdrone instance) ---

static func _hex_mesh() -> CylinderMesh:
	if _hex_mesh_cache == null:
		_hex_mesh_cache = CylinderMesh.new()
		_hex_mesh_cache.top_radius = 0.6
		_hex_mesh_cache.bottom_radius = 0.6
		_hex_mesh_cache.height = 0.32
		_hex_mesh_cache.radial_segments = 6
	return _hex_mesh_cache

static func _arm_mesh() -> BoxMesh:
	if _arm_mesh_cache == null:
		_arm_mesh_cache = BoxMesh.new()
		_arm_mesh_cache.size = Vector3(1.0, 0.08, 0.14)
	return _arm_mesh_cache

static func _hub_mesh() -> BoxMesh:
	if _hub_mesh_cache == null:
		_hub_mesh_cache = BoxMesh.new()
		_hub_mesh_cache.size = Vector3(0.16, 0.16, 0.16)
	return _hub_mesh_cache

static func _sensor_mesh() -> SphereMesh:
	if _sensor_mesh_cache == null:
		_sensor_mesh_cache = SphereMesh.new()
		_sensor_mesh_cache.radius = 0.14
		_sensor_mesh_cache.height = 0.14
		_sensor_mesh_cache.radial_segments = 16
		_sensor_mesh_cache.rings = 8
		_sensor_mesh_cache.is_hemisphere = true
	return _sensor_mesh_cache

static func _barrel_mesh() -> CylinderMesh:
	if _barrel_mesh_cache == null:
		_barrel_mesh_cache = CylinderMesh.new()
		_barrel_mesh_cache.top_radius = 0.08
		_barrel_mesh_cache.bottom_radius = 0.08
		_barrel_mesh_cache.height = 0.55
		_barrel_mesh_cache.radial_segments = 12
	return _barrel_mesh_cache

static func _blade_mesh() -> ArrayMesh:
	if _blade_mesh_cache:
		return _blade_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_push_box(st, Vector3(0.72, 0.016, 0.1), Vector3.ZERO)
	_push_box(st, Vector3(0.1, 0.016, 0.72), Vector3.ZERO)
	st.generate_normals()
	_blade_mesh_cache = st.commit()
	return _blade_mesh_cache

static func _push_box(st: SurfaceTool, size: Vector3, center: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var c := center
	var v := [
		Vector3(-hx, -hy, -hz) + c, Vector3(hx, -hy, -hz) + c,
		Vector3(hx, -hy, hz) + c, Vector3(-hx, -hy, hz) + c,
		Vector3(-hx, hy, -hz) + c, Vector3(hx, hy, -hz) + c,
		Vector3(hx, hy, hz) + c, Vector3(-hx, hy, hz) + c,
	]
	_push_tri(st, v[4], v[6], v[5])  # top
	_push_tri(st, v[4], v[7], v[6])
	_push_tri(st, v[0], v[2], v[3])  # bottom
	_push_tri(st, v[0], v[1], v[2])
	_push_tri(st, v[3], v[2], v[6])  # front
	_push_tri(st, v[3], v[6], v[7])
	_push_tri(st, v[1], v[0], v[4])  # back
	_push_tri(st, v[1], v[4], v[5])
	_push_tri(st, v[1], v[6], v[2])  # right
	_push_tri(st, v[1], v[5], v[6])
	_push_tri(st, v[0], v[7], v[3])  # left
	_push_tri(st, v[0], v[4], v[7])

static func _push_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

static func _dark_mat() -> StandardMaterial3D:
	if _dark_mat_cache == null:
		_dark_mat_cache = StandardMaterial3D.new()
		_dark_mat_cache.albedo_color = Color(0.05, 0.05, 0.06, 1.0)
		_dark_mat_cache.metallic = 0.6
		_dark_mat_cache.roughness = 0.5
	return _dark_mat_cache

static func _chrome_mat() -> StandardMaterial3D:
	if _chrome_mat_cache == null:
		_chrome_mat_cache = StandardMaterial3D.new()
		_chrome_mat_cache.albedo_color = Color(0.8, 0.84, 0.9, 1.0)
		_chrome_mat_cache.metallic = 1.0
		_chrome_mat_cache.roughness = 0.15
	return _chrome_mat_cache
