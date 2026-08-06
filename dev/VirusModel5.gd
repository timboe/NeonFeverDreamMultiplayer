@tool
extends Node3D
class_name VirusModel5

# Design 5 — "Corrupt": a chunky slab of corrupted data glitching in place.
# A translucent data block tumbles slowly while a big neon chevron holo-glyph
# hovers above it, splitting into red/cyan ghosts that stutter. Every beat the
# block snaps to a new angle and spits sparks — a broken file crawling across
# the grid.

const TUMBLE_SPEED := 0.45
const GLITCH_INTERVAL := 1.5
const GLITCH_JITTER := 0.06
const BLOCK_SIZE := Vector3(1.0, 0.9, 1.0)

var _color := Color(1.0, 0.2, 0.4, 1.0)
var _mats: Array[StandardMaterial3D] = []
var _base_alphas: Array[float] = []
var _block := Node3D.new()
var _glyph := Node3D.new()
var _glyph_main_mat: StandardMaterial3D
var _ghost_mats: Array[StandardMaterial3D] = []
var _ghost_base: Array[float] = []
var _t := 0.0
var _next_glitch := 2.0
var _flicker := 0.0
var _sparks: CPUParticles3D
var _cloaked := false

func _ready() -> void:
	_build_block()
	_build_glyph()
	_build_sparks()

func _process(delta: float) -> void:
	_t += delta
	_flicker = 0.7 + 0.3 * sin(_t * 21.0)
	if _t >= _next_glitch:
		_next_glitch = _t + GLITCH_INTERVAL
		_glitch()
	var k := 0.12 if _cloaked else 1.0
	_block.rotation.y = _t * TUMBLE_SPEED
	_block.rotation.x = sin(_t * 0.8) * 0.12
	_block.position.x = lerp(_block.position.x, 0.0, delta * 6.0)
	_block.position.y = 0.5 + sin(_t * 1.2) * 0.06
	_block.scale = _block.scale.lerp(Vector3.ONE, delta * 8.0)
	_glyph.position.y = 1.5 + sin(_t * 1.6) * 0.05
	_glyph.rotation.y = _t * 0.25
	if _glyph_main_mat:
		_glyph_main_mat.albedo_color.a = _base_alphas[0] * _flicker * k
	for i in _ghost_mats.size():
		_ghost_mats[i].albedo_color.a = _ghost_base[i] * (0.5 + 0.5 * randf()) * k

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

func _glitch() -> void:
	_block.rotation.y += randf_range(-1.2, 1.2)
	_block.position.x = randf_range(-GLITCH_JITTER, GLITCH_JITTER)
	_block.scale = Vector3(1.07, 1.07, 1.07)
	if _sparks:
		_sparks.restart()

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

func _build_block() -> void:
	var box := BoxMesh.new()
	box.size = BLOCK_SIZE
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = _mat(_color, 0.32, true)
	_block.add_child(mi)
	var half_x := BLOCK_SIZE.x * 0.5
	var half_z := BLOCK_SIZE.z * 0.5
	var rim_y := BLOCK_SIZE.y * 0.5 + 0.02
	for s in [-1.0, 1.0]:
		var a := MeshInstance3D.new()
		var ab := BoxMesh.new()
		ab.size = Vector3(BLOCK_SIZE.x + 0.02, 0.025, 0.025)
		a.mesh = ab
		a.position = Vector3(0, rim_y, s * half_z)
		a.material_override = _mat(_color, 0.95, true)
		_block.add_child(a)
		var b := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.025, 0.025, BLOCK_SIZE.z + 0.02)
		b.mesh = bb
		b.position = Vector3(s * half_x, rim_y, 0)
		b.material_override = _mat(_color, 0.95, true)
		_block.add_child(b)
	add_child(_block)

func _build_glyph() -> void:
	_glyph.position.y = 1.5
	var main := MeshInstance3D.new()
	main.mesh = _chevron_panel(0.5, 0.55)
	_glyph_main_mat = _mat(_color, 0.95, true)
	main.material_override = _glyph_main_mat
	_glyph.add_child(main)
	for ghost in 2:
		var gm := MeshInstance3D.new()
		gm.mesh = _chevron_panel(0.5, 0.55)
		var gc := Color(1.0, 0.1, 0.2) if ghost == 0 else Color(0.2, 1.0, 1.0)
		var gmat := _mat(gc, 0.8, true)
		gm.material_override = gmat
		gm.position.x = -0.045 if ghost == 0 else 0.045
		_glyph.add_child(gm)
		_ghost_mats.append(gmat)
		_ghost_base.append(0.8)
	_glyph.rotation.y = 0.3
	add_child(_glyph)

func _build_sparks() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.amount = 30
	_sparks.lifetime = 0.6
	_sparks.one_shot = true
	_sparks.emitting = false
	_sparks.gravity = Vector3(0, 1.2, 0)
	_sparks.initial_velocity_min = 0.8
	_sparks.initial_velocity_max = 2.4
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 0.6
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
