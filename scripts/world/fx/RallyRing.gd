extends Node3D

class_name RallyRing

# One-shot expanding ring visual for the avatar's rally call. Cosmetic only —
# spawned locally on every peer from UnitManager.rpc_rally_fx (call_local), so
# no networking is involved. Builds its mesh in code (like DestructionFX).

# --- Constants ---

const DURATION := 1.2

# Spawns the ring at the rally origin and lets it play out, then frees itself.
static func spawn(parent: Node, origin: Vector3, radius: float, pnum: int) -> void:
	var ring := RallyRing.new()
	ring.name = "RallyRing"
	parent.add_child(ring)
	ring.setup(origin, radius, pnum)

func setup(origin: Vector3, radius: float, pnum: int) -> void:
	global_position = origin
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.45
	torus.outer_radius = radius * 0.5
	torus.rings = 6
	torus.ring_segments = 64
	mi.mesh = torus
	var accent := Config.player_accent(pnum)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = accent
	mi.material_override = mat
	add_child(mi)
	scale = Vector3.ONE * 0.2
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, DURATION)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_method(_fade.bind(mat), 0.9, 0.0, DURATION)
	tween.tween_callback(queue_free)

func _fade(value: float, mat: StandardMaterial3D) -> void:
	mat.albedo_color.a = value
