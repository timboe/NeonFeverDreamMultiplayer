extends Unit

class_name Zoomba

# --- Constants ---

# Googly eye driver (cosmetic, runs on every peer — no sync needed since
# client positions are snapshot-interpolated and health comes via snapshots).
const EYE_VELOCITY_GAIN := 0.22
const EYE_MAX_OFFSET := 0.9
const EYE_SMOOTHING := 2.2
const EYE_PUPIL_CALM := 0.62
const EYE_PUPIL_ALERT := 0.8

# --- State ---

var _eye_materials: Array[ShaderMaterial] = []
var _eye_off := Vector2.ZERO
var _prev_eye_pos := Vector3.ZERO

func _ready() -> void:
	$Zapper.visible = false
	var shader := load("res://shaders/zoomba_eye.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	$Body/Ball.material_override = mat
	# Duplicate with a different seed so the two eyes wobble out of sync, and
	# point each cap along its own socket's outward direction (radially away
	# from the body centre, horizontal plane) so both eyes look out sideways.
	var mat2: ShaderMaterial = mat.duplicate()
	mat2.set_shader_parameter(&"eye_seed", 7.7)
	var ball := $Body/Ball as Node3D
	var ball2 := $Body/Ball2 as Node3D
	mat.set_shader_parameter(&"eye_outward", Vector3(ball.position.x, 0.0, ball.position.z).normalized())
	mat2.set_shader_parameter(&"eye_outward", Vector3(ball2.position.x, 0.0, ball2.position.z).normalized())
	$Body/Ball2.material_override = mat2
	_eye_materials = [mat, mat2]
	_prev_eye_pos = global_position

func initialise(b: Building) -> void:
	super.initialise(b)
	type = UnitManager.Type.ZOOMBA
	_health_bar.position.y = 2.5
	health = Config.UNIT_MAX_HP.get(type, 100.0)
	add_to_group("zoomba")
	var updated_mat = load("res://materials/player/player" + str(player_owner) + "_unit_material.tres")
	$Body/CSG.set_surface_override_material(0, updated_mat)
	# initialise() teleports the node to its spawn tile — drop the tracker so
	# the first _process frames don't read a phantom spawn velocity.
	_prev_eye_pos = global_position

func _process(delta: float) -> void:
	super._process(delta)
	if _eye_materials.is_empty():
		return
	# Pupils roll toward the direction of travel, with smoothing for a laggy
	# "ball rolling in the socket" feel. Idle wobble lives in the shader (TIME).
	var vel := (global_position - _prev_eye_pos) / maxf(delta, 0.0001)
	_prev_eye_pos = global_position
	var target := Vector2(-vel.x, vel.z) * EYE_VELOCITY_GAIN
	var max_off := Vector2(EYE_MAX_OFFSET, EYE_MAX_OFFSET)
	_eye_off = _eye_off.lerp(target.clamp(-max_off, max_off), 1.0 - exp(-delta * EYE_SMOOTHING))
	# Alert via health (snapshot-synced) rather than scram_count (server-only),
	# so dilated pupils look identical on every peer.
	var alert := clampf(1.0 - health / _max_hp * 2.0, 0.0, 1.0)
	var pupil_radius := lerpf(EYE_PUPIL_CALM, EYE_PUPIL_ALERT, alert)
	for m in _eye_materials:
		m.set_shader_parameter(&"pupil_offset", _eye_off)
		m.set_shader_parameter(&"pupil_radius", pupil_radius)
