extends Node3D

enum CameraStatus {OVERHEAD, TO_FPS, FPS, TO_OVERHEAD}
@onready var camera_status : int = CameraStatus.OVERHEAD

###############################
## Transition parameters

var avatar : Node3D = null
@onready var overhead_camera : Camera3D = %CameraRTS
@onready var overhead_light : OmniLight3D = %OmniLight3D_RTS

var quat_from : Quaternion
var quat_to : Quaternion

const TRANSITION_TIME : float = 2.0
const PLAYER_LOWER_DEPTH : float = 5.0
const UNPOSESS_DISTANCE := Vector2(-40, 50)

const SLOW_MO := 0.9

##############################
# Shake parameters

@export var shake_speed := 1.0
@export var shake_decay := 0.5
@export var noise : FastNoiseLite

const RUMBLE_OFFSET : float = 0.75
const RUMBLE_FALLOFF : float = 100.0

var trauma := 0.0
var _time := 0.0
var linger := 0.0

###############

func _ready():
	call_deferred("_connect_hud")

func _connect_hud():
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toggle_camera.connect(_on_toggle_camera)

func _on_toggle_camera():
	match camera_status:
		CameraStatus.OVERHEAD:
			to_fps_cam_start()
			print("To FPS cam")
		CameraStatus.FPS:
			to_overhead_cam_start()
			print("To Overhead cam")

func _process(delta):
	apply_shake(delta)
	decay_trauma(delta)
	
func quat_transform(amount : float):
	var mid = quat_from.slerp(quat_to, amount)
	overhead_camera.transform.basis = Basis(mid)

func to_fps_cam_start():
	avatar = get_tree().get_first_node_in_group("avatar_player" + str(Global.my_player_number) )
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

func to_fps_cam_end():
	camera_status = CameraStatus.FPS
	overhead_camera.current = false
	var fps_camera = avatar.find_child("Rotation_Helper").find_child("FPSCamera")
	if fps_camera:
		fps_camera.current = true

func to_overhead_cam_start():
	camera_status = CameraStatus.TO_OVERHEAD
	var avatar_body = avatar.get_node_or_null("FPSBody")
	overhead_camera.transform.origin = avatar_body.global_position if avatar_body else avatar.global_position
	overhead_camera.rotation.y = avatar_body.global_rotation.y if avatar_body else avatar.rotation.y
	var start_tf : Transform3D = overhead_camera.transform
	overhead_camera.transform.origin += avatar.global_transform.basis.z * UNPOSESS_DISTANCE.y
	overhead_camera.transform.origin.y = UNPOSESS_DISTANCE.y
	overhead_camera.rotation.x = deg_to_rad(-45)
	var target_tf : Transform3D = overhead_camera.transform
	overhead_camera.transform = start_tf
	overhead_camera.current = true
	var fps_camera = avatar.find_child("Rotation_Helper").find_child("FPSCamera")
	if fps_camera:
		fps_camera.current = false
	quat_from = Quaternion(start_tf.basis)
	quat_to = Quaternion(target_tf.basis)
	var tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(overhead_camera, "position", target_tf.origin, TRANSITION_TIME)
	tw.parallel().tween_method(quat_transform, 0.0, 1.0, TRANSITION_TIME)
	tw.tween_callback(to_overhead_cam_end).set_delay(TRANSITION_TIME)

func to_overhead_cam_end():
	camera_status = CameraStatus.OVERHEAD
	call_deferred("_show_mouse")

func _show_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
func add_trauma(amount : float, from, add_linger = false):
	var avatar_pos = avatar.global_position
	var avatar_body = avatar.get_node_or_null("FPSBody")
	if avatar_body:
		avatar_pos = avatar_body.global_position
	var c : Vector3 = overhead_camera.global_position if overhead_camera.current else avatar_pos
	var d : float = from.distance_to(c) if from is Vector3 else 0.0
	linger = max(linger, add_linger) if add_linger is float else linger
	if d > RUMBLE_FALLOFF:
		amount *= (RUMBLE_FALLOFF / d)
	trauma = min(trauma + amount, 1.0)
 
func decay_trauma(delta: float):
	var change := shake_decay * delta
	trauma = max(trauma - change, 0.0)
	linger = max(linger - delta, 0.0)
 
func apply_shake(delta : float):
	_time += delta * shake_speed * 5000.0
	var trauma_mod : float = trauma
	if linger > 0:
		trauma_mod = min(trauma + 0.4, 1.0)
	if trauma_mod == 0:
		return
	var shake := trauma_mod * trauma_mod
	var offset_x := RUMBLE_OFFSET * shake * noise.get_noise_2d(0, _time)
	var offset_y := RUMBLE_OFFSET * shake * noise.get_noise_2d(_time, 0)
	overhead_camera.h_offset = offset_x
	overhead_camera.v_offset = offset_y
