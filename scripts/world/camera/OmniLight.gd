extends OmniLight3D

const HEIGHT : float = 5.0
var floor_lowered : bool = false

@onready var desired_height : float = position.y

func _physics_process(_delta : float):
	visible = %CameraRTS.current
	if !visible:
		return
	if %CameraManager.camera_status != %CameraManager.CameraStatus.OVERHEAD:
		return
	var mouse_pos = get_viewport().get_mouse_position()
	var from = %CameraRTS.project_ray_origin(mouse_pos)
	var to = from + %CameraRTS.project_ray_normal(mouse_pos) * 1000.0
	var query = PhysicsRayQueryParameters3D.create(from, to, 2147483647, [])
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		position.x = result.position.x
		position.z = result.position.z
		desired_height = HEIGHT
		floor_lowered = result.position.y < Global.FLOOR_HEIGHT / 2.0
		desired_height += Global.FLOOR_HEIGHT if not floor_lowered else 0.0
	position.y += (desired_height - position.y) * _delta * 10.0
