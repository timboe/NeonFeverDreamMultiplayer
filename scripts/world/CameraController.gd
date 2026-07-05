extends Node3D
class_name CameraController

@onready var camera: Camera3D = $Camera3D

var drag_start: Vector2
var drag_origin: Vector3
var zoom: float = 20.0

func _ready():
	rotation_degrees = Vector3(-35, 45, 0)
	position = Vector3(16, 0, 16)

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				drag_start = event.position
				drag_origin = position
			Input.set_default_cursor_shape(Input.CURSOR_DRAG if event.pressed else Input.CURSOR_ARROW)

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = max(5.0, zoom - 2.0)
			_update_camera()

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = min(50.0, zoom + 2.0)
			_update_camera()

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var delta = (event.position - drag_start) * 0.02
		var forward = -transform.basis.z
		forward.y = 0
		forward = forward.normalized()
		var right = transform.basis.x
		right.y = 0
		right = right.normalized()
		position = drag_origin + right * -delta.x + forward * -delta.y

func _update_camera():
	camera.position = Vector3(0, 0, zoom)
