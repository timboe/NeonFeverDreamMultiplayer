extends Node3D

class_name VideoManager

# --- Types ---

enum CameraStatus {OVERHEAD, TO_FPS, FPS, TO_OVERHEAD}

# --- Constants ---

const TRANSITION_TIME: float = 2.0
const PLAYER_LOWER_DEPTH: float = 5.0
# On leaving FPS: x = distance the camera retreats behind the avatar, y = RTS height.
const UNPOSESS_DISTANCE := Vector2(-40, 50)
const SLOW_MO: float = 0.9
const RUMBLE_OFFSET: float = 0.75
const RUMBLE_FALLOFF: float = 100.0

# --- Configuration ---

@export var shake_speed: float = 1.0
@export var shake_decay: float = 0.5
@export var noise: FastNoiseLite

# --- State ---

var camera_status: CameraStatus = CameraStatus.OVERHEAD
var avatar: Node3D = null
var quat_from: Quaternion
var quat_to: Quaternion
var trauma: float = 0.0
var _time: float = 0.0
var linger: float = 0.0
var _cam_tween: Tween

# --- Nodes ---

@onready var overhead_camera: Camera3D = %CameraRTS
@onready var overhead_light: OmniLight3D = %OmniLight3D_RTS

# --- Lifecycle ---

func _ready() -> void:
	Global.VM = self
	call_deferred("_connect_hud")
	# The player's MCP only exists once the level is loaded (first physics
	# frame), so position the initial RTS camera over it then.
	Global.TM.level_loaded.connect(_position_initial_camera)

func _position_initial_camera() -> void:
	var mcp = get_tree().get_first_node_in_group("mcp_player" + str(Global.my_player_number))
	if not mcp:
		return
	# Use the tile's pathing centre (the middle of the MCP's tile).
	var tile := mcp.location as TileElement
	var centre: Vector3 = tile.pathing_centre if tile else mcp.global_position
	# Back in x from the tile centre (same distance as the FPS->RTS exit), up at
	# the RTS height, and looking down at it.
	var cam_pos := Vector3(centre.x - (-UNPOSESS_DISTANCE.x), UNPOSESS_DISTANCE.y, centre.z)
	overhead_camera.global_position = cam_pos
	overhead_camera.look_at(centre, Vector3.UP)

func _connect_hud() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toggle_camera.connect(_on_toggle_camera)

func _process(delta: float) -> void:
	apply_shake(delta)
	decay_trauma(delta)

# --- Camera toggle ---

func _on_toggle_camera() -> void:
	match camera_status:
		CameraStatus.OVERHEAD:
			to_fps_cam_start()
		CameraStatus.FPS:
			to_overhead_cam_start()

# Drop out of FPS mode if the player is in it (used when interacting with a
# terminal, e.g. pressing Empower).
func force_leave_fps() -> void:
	if camera_status == CameraStatus.FPS:
		to_overhead_cam_start()

# Snap straight back to the RTS camera with no tween — used when the local
# player's avatar dies while in FPS mode.
func exit_fps_immediate() -> void:
	if camera_status != CameraStatus.FPS and camera_status != CameraStatus.TO_FPS:
		return
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
		_cam_tween = null
	camera_status = CameraStatus.OVERHEAD
	overhead_camera.current = true
	var fps_camera = avatar.find_child("Rotation_Helper").find_child("FPSCamera") if avatar else null
	if fps_camera:
		fps_camera.current = false
	# Park the RTS camera behind and above where the avatar was — closer and
	# pitched more steeply down than the normal retreat so it homes in on the
	# destruction site.
	var anchor: Transform3D = fps_camera.get_global_transform() if fps_camera else (avatar.get_global_transform() if avatar else overhead_camera.get_global_transform())
	var forward: Vector3 = -anchor.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var pos: Vector3 = anchor.origin - forward * (-UNPOSESS_DISTANCE.x * 0.5)
	pos.y = UNPOSESS_DISTANCE.y
	overhead_camera.global_position = pos
	overhead_camera.rotation_degrees = Vector3(-55, rad_to_deg(anchor.basis.get_euler().y), 0)
	call_deferred("_show_mouse")

func to_fps_cam_start() -> void:
	avatar = get_tree().get_first_node_in_group("avatar_player" + str(Global.my_player_number))
	if not avatar:
		return
	camera_status = CameraStatus.TO_FPS
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	var fps_camera = avatar.find_child("Rotation_Helper").find_child("FPSCamera")
	var camera_target = fps_camera.to_global(Vector3.ZERO)

	quat_from = Quaternion(overhead_camera.transform.basis)
	quat_to = Quaternion(fps_camera.get_global_transform().basis)

	var tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(overhead_camera, "position", camera_target, TRANSITION_TIME).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(quat_transform, 0.0, 1.0, TRANSITION_TIME).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_callback(to_fps_cam_end).set_delay(TRANSITION_TIME)
	_cam_tween = tw

func to_fps_cam_end() -> void:
	camera_status = CameraStatus.FPS
	overhead_camera.current = false
	var fps_camera = avatar.find_child("Rotation_Helper").find_child("FPSCamera")
	if fps_camera:
		fps_camera.current = true
	_cam_tween = null
	# Re-entering FPS clears the player's empowered building (see empower flow).
	Global.send_command_me("clear_empower", [])

func to_overhead_cam_start() -> void:
	camera_status = CameraStatus.TO_OVERHEAD
	var avatar_body = avatar.get_node_or_null("FPSBody")
	var fps_camera = avatar.find_child("Rotation_Helper").find_child("FPSCamera")
	# Start from the FPS camera's actual transform (inside the avatar), then
	# retreat backwards through the avatar and up to the RTS height, keeping the
	# same XZ view direction as the avatar.
	var start_tf: Transform3D = fps_camera.get_global_transform() if fps_camera else (avatar_body.get_global_transform() if avatar_body else avatar.get_global_transform())
	var forward := -start_tf.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var target_pos := start_tf.origin - forward * (-UNPOSESS_DISTANCE.x)
	target_pos.y = UNPOSESS_DISTANCE.y
	var yaw := start_tf.basis.get_euler().y
	var target_tf := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-45), yaw, 0)), target_pos)
	overhead_camera.transform = start_tf
	overhead_camera.current = true
	if fps_camera:
		fps_camera.current = false
	quat_from = Quaternion(start_tf.basis)
	quat_to = Quaternion(target_tf.basis)
	# EASE_IN_OUT so the camera gracefully backs out of the avatar rather than
	# whipping backward (EASE_OUT fast-start reads as an instant jump out).
	var tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(overhead_camera, "position", target_tf.origin, TRANSITION_TIME).from(start_tf.origin)
	tw.parallel().tween_method(quat_transform, 0.0, 1.0, TRANSITION_TIME)
	tw.tween_callback(to_overhead_cam_end).set_delay(TRANSITION_TIME)
	_cam_tween = tw

func to_overhead_cam_end() -> void:
	camera_status = CameraStatus.OVERHEAD
	_cam_tween = null
	call_deferred("_show_mouse")

func quat_transform(amount: float) -> void:
	var mid = quat_from.slerp(quat_to, amount)
	overhead_camera.transform.basis = Basis(mid)

# --- Mouse ---

func _show_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# --- Notification jump ---

# Snap the RTS camera over to a notification's location. Position only — the
# camera keeps its current height and pitch. No-op while a camera transition
# or FPS mode is active so the position tween can't fight _cam_tween.
func jump_to(location: Vector3) -> void:
	if camera_status != CameraStatus.OVERHEAD:
		return
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
		_cam_tween = null
	var target: Vector3 = Vector3(location.x, overhead_camera.global_position.y, location.z)
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(overhead_camera, "global_position", target, 0.4)
	_cam_tween = tw

# --- Trauma / Shake ---

func add_trauma(amount: float, from, add_linger: float = 0.0) -> void:
	var avatar_pos = avatar.global_position
	var avatar_body = avatar.get_node_or_null("FPSBody")
	if avatar_body:
		avatar_pos = avatar_body.global_position
	var c: Vector3 = overhead_camera.global_position if overhead_camera.current else avatar_pos
	var d: float = from.distance_to(c) if from is Vector3 else 0.0
	linger = max(linger, add_linger)
	if d > RUMBLE_FALLOFF:
		amount *= RUMBLE_FALLOFF / d
	trauma = min(trauma + amount, 1.0)

func decay_trauma(delta: float) -> void:
	var change := shake_decay * delta
	trauma = max(trauma - change, 0.0)
	linger = max(linger - delta, 0.0)

func apply_shake(delta: float) -> void:
	_time += delta * shake_speed * 5000.0
	var trauma_mod: float = trauma
	if linger > 0:
		trauma_mod = min(trauma + 0.4, 1.0)
	if trauma_mod == 0:
		return
	var shake := trauma_mod * trauma_mod
	var offset_x := RUMBLE_OFFSET * shake * noise.get_noise_2d(0, _time)
	var offset_y := RUMBLE_OFFSET * shake * noise.get_noise_2d(_time, 0)
	overhead_camera.h_offset = offset_x
	overhead_camera.v_offset = offset_y
