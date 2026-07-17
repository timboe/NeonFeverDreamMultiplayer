# Licensed under the MIT License.
# Copyright (c) 2018-2020 Jaccomo Lorenz (Maujoe)

extends Node3D
class_name CameraController

# --- Constants ---

const WHEEL_MOD: float = 20.0
const PITCH_LIMIT := Vector2(deg_to_rad(-80), deg_to_rad(5))
const Y_LIMIT := Vector2(Global.FLOOR_HEIGHT + 10.0, Global.FLOOR_HEIGHT + 60.0)
const ACCELERATION: float = 5.0
const MAX_SPEED: float = 2.0
const SENSITIVITY: float = 0.5
const SMOOTHNESS: float = 0.5

# --- State ---

var _mouse_offset := Vector2()
var _direction := Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0
var _wheel_cache: int = 0
var _v: float = 0.0

# --- Input ---

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_mouse_offset = event.relative
	if event is InputEventMouseButton:
		var wheel: float = WHEEL_MOD * (Input.get_action_strength("ui_zoom_out") - Input.get_action_strength("ui_zoom_in"))
		if wheel != 0.0:
			_wheel_cache = round(wheel)

func _poll() -> void:
	_direction.x = Input.get_action_strength("ui_movement_right") - Input.get_action_strength("ui_movement_left")
	_direction.z = Input.get_action_strength("ui_movement_backward") - Input.get_action_strength("ui_movement_forward")

	var zoom: float = Input.get_action_strength("ui_zoom_in") - Input.get_action_strength("ui_zoom_out")
	if _wheel_cache != 0:
		zoom += 1 * sign(_wheel_cache)
		_wheel_cache -= 1 * sign(_wheel_cache)
	zoom = clamp(zoom, -1, 1)
	if zoom != 0:
		if zoom == -1 and position.y == Y_LIMIT.y:
			pass
		elif zoom == 1 and position.y == Y_LIMIT.x:
			pass
		else:
			var a := deg_to_rad(10 + rotation_degrees.x)
			var y_amount := sin(a)
			var z_amount := cos(a)
			_direction.y = zoom * y_amount
			_direction.z -= zoom * z_amount
	_direction = _direction.rotated(Vector3.UP, rotation.y)

# --- Frame ---

func _process(delta: float) -> void:
	_poll()
	_update_rotation(delta)
	_update_movement(delta)

func _update_movement(delta: float) -> void:
	if _direction == Vector3.ZERO:
		_v = 0.0
	else:
		_v = min(MAX_SPEED, _v + ACCELERATION * delta)
	global_translate(_direction * _v)
	position.y = clamp(position.y, Y_LIMIT.x, Y_LIMIT.y)
	_direction = Vector3.ZERO

func _update_rotation(_delta: float) -> void:
	var offset: Vector2 = _mouse_offset * SENSITIVITY
	_mouse_offset = Vector2.ZERO

	_yaw = _yaw * SMOOTHNESS + offset.x * (1.0 - SMOOTHNESS)
	_pitch = _pitch * SMOOTHNESS + offset.y * (1.0 - SMOOTHNESS)
	_pitch = min(_pitch, 5.0)

	rotate_y(deg_to_rad(-_yaw))
	rotate_object_local(Vector3(1, 0, 0), deg_to_rad(-_pitch))
	rotation.x = clamp(rotation.x, PITCH_LIMIT.x, PITCH_LIMIT.y)
