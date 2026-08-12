@tool
extends Node3D
class_name TankModelBase

# Shared builders for the TANK unit model designs. The TANK is the upgraded
# ZOOMBA: every design scene (Tank1.tscn .. Tank10.tscn) has a root node
# running Tank.gd (gameplay) and a Body child running a script that extends
# this and implements _build_design(). Visual-only, runs on all peers. @tool
# so the designs are visible when opening the scenes in the editor.
#
# Tank.gd expects the nodes Body/CSG, Body/Laser and Body/Laser/Muzzle to
# exist, so every design must keep the current zoomba body via
# _build_zoomba_core() (CSG carries the real zoomba.tres mesh, player-coloured
# by Tank.gd at spawn) and add a top-mounted laser cannon via _build_laser():
# the Laser node pivots at its mount point, its barrel runs along +Y (Tank.gd
# aims with weapon_forward_local = UP) and the Muzzle sits at the barrel tip.

# --- Constants ---

const SEG := 12

# --- State ---

var _t := 0.0
var _built := false
var _spin_nodes: Array[Node3D] = []
var _spin_speeds: Array[float] = []
var _pulse_nodes: Array[Node3D] = []
var _pulse_speeds: Array[float] = []
var _pulse_phases: Array[float] = []

@onready var _csg: MeshInstance3D = $CSG
@onready var _laser: Node3D = $Laser
@onready var _muzzle: Marker3D = $Laser/Muzzle

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _zoomba_mesh: ArrayMesh = null

# --- Lifecycle ---

func _ready() -> void:
	if _built:
		return
	_built = true
	_build_design()

func _process(delta: float) -> void:
	_t += delta
	for i in _spin_nodes.size():
		_spin_nodes[i].rotation.y += _spin_speeds[i] * delta
	for i in _pulse_nodes.size():
		var s := 1.0 + sin(_t * _pulse_speeds[i] + _pulse_phases[i]) * 0.3
		_pulse_nodes[i].scale = Vector3(s, s, s)

# --- Design hook ---

func _build_design() -> void:
	pass

# --- The current ZOOMBA design (the TANK is its upgrade) ---

func _build_zoomba_core() -> void:
	if _zoomba_mesh == null:
		_zoomba_mesh = load("res://meshes/zoomba.tres") as ArrayMesh
	_csg.mesh = _zoomba_mesh
	_csg.position = Vector3(0, 1, 0)
	var eye_mat := _mat(Color(0, 0, 0, 1), 0.0, 0.05)
	var ball1 := _part(self, _sphere(0.1), eye_mat, Vector3(-1.8, 1, 0.5))
	ball1.name = "Ball"
	var ball2 := _part(self, _sphere(0.1), eye_mat, Vector3(-1.8, 1, -0.5))
	ball2.name = "Ball2"

# --- Top-mounted laser cannon (Tank.gd contract) ---

func _build_laser(mount_y: float, barrel_len: float, barrel_r: float, barrel_mat: Material) -> void:
	_laser.position = Vector3(0, mount_y, 0)
	var barrel := _part(_laser, _cyl(barrel_r, barrel_r, barrel_len, SEG), barrel_mat, Vector3(0, barrel_len * 0.5, 0))
	barrel.name = "Barrel"
	_muzzle.position = Vector3(0, barrel_len, 0)

# --- Primitive mesh builders (cached, shared across instances) ---

func _box(w: float, h: float, d: float) -> PrimitiveMesh:
	return _mesh("BoxMesh", w, h, d)

func _sphere(r: float) -> PrimitiveMesh:
	return _mesh("SphereMesh", r)

func _hemisphere(r: float) -> PrimitiveMesh:
	return _mesh("HemisphereMesh", r)

func _cyl(top: float, bottom: float, h: float, seg: int = 16) -> PrimitiveMesh:
	return _mesh("CylinderMesh", top, bottom, h, seg)

func _cone(r: float, h: float, seg: int = 12) -> PrimitiveMesh:
	return _mesh("ConeMesh", r, h, seg)

func _capsule(r: float, h: float) -> PrimitiveMesh:
	return _mesh("CapsuleMesh", r, h)

func _torus(inner: float, outer: float, rings: int = 48, seg: int = 10) -> PrimitiveMesh:
	return _mesh("TorusMesh", inner, outer, rings, seg)

func _mesh(kind: String, a: float = 0.0, b: float = 0.0, c: float = 0.0, d: float = 0.0) -> PrimitiveMesh:
	var key := kind + "|" + str(a) + "|" + str(b) + "|" + str(c) + "|" + str(d)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m: PrimitiveMesh
	match kind:
		"BoxMesh":
			var bm := BoxMesh.new()
			bm.size = Vector3(a, b, c)
			m = bm
		"SphereMesh":
			var sm := SphereMesh.new()
			sm.radius = a
			sm.height = a * 2.0
			sm.radial_segments = 24
			sm.rings = 12
			m = sm
		"HemisphereMesh":
			var hm := SphereMesh.new()
			hm.radius = a
			hm.height = a
			hm.radial_segments = 24
			hm.rings = 12
			hm.is_hemisphere = true
			m = hm
		"CylinderMesh":
			var cm := CylinderMesh.new()
			cm.top_radius = a
			cm.bottom_radius = b
			cm.height = c
			cm.radial_segments = int(d)
			m = cm
		"ConeMesh":
			var cnm := CylinderMesh.new()
			cnm.top_radius = 0.0
			cnm.bottom_radius = a
			cnm.height = b
			cnm.radial_segments = int(c)
			m = cnm
		"CapsuleMesh":
			var cpm := CapsuleMesh.new()
			cpm.radius = a
			cpm.height = b
			cpm.radial_segments = 16
			cpm.rings = 12
			m = cpm
		"TorusMesh":
			var tm := TorusMesh.new()
			tm.inner_radius = a
			tm.outer_radius = b
			tm.rings = int(c)
			tm.ring_segments = int(d)
			m = tm
		_:
			return null
	_mesh_cache[key] = m
	return m

# --- Material builder (cached) ---

func _mat(color: Color, metal: float = 0.0, rough: float = 0.6, emiss: Color = Color(0, 0, 0, 0), power: float = 0.0, unshaded: bool = false, alpha: float = 1.0) -> StandardMaterial3D:
	var key := str(color) + "|" + str(metal) + "|" + str(rough) + "|" + str(emiss) + "|" + str(power) + "|" + str(unshaded) + "|" + str(alpha)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.metallic = metal
	m.roughness = rough
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if power > 0.0:
		m.emission_enabled = true
		m.emission = emiss
		m.emission_energy_multiplier = power
	_mat_cache[key] = m
	return m

# --- Part builder ---

func _part(parent: Node, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scale
	parent.add_child(mi)
	return mi

func _add_spin(node: Node3D, speed: float) -> void:
	_spin_nodes.append(node)
	_spin_speeds.append(speed)

func _add_pulse(node: Node3D, speed: float, phase: float = 0.0) -> void:
	_pulse_nodes.append(node)
	_pulse_speeds.append(speed)
	_pulse_phases.append(phase)
