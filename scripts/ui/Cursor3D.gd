extends RefCounted
class_name Cursor3D

const CURSOR_OFFSET: float = 0.05

var _sprite: Sprite3D
var _screen_mesh: MeshInstance3D

func _init(screen: MeshInstance3D, screen_size: float) -> void:
	_screen_mesh = screen
	_sprite = Sprite3D.new()
	_sprite.texture = preload("res://images/cursor.png")
	_sprite.pixel_size = 0.005
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.no_depth_test = true
	_sprite.visible = false
	_sprite.extra_cull_margin = 1000.0
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = preload("res://images/cursor.png")
	mat.render_priority = 10
	_sprite.material_override = mat
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.current_scene:
		tree.current_scene.add_child(_sprite)

func _get_camera_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		return tree.root.get_node_or_null("World/CameraManager")
	return null

func show_at_uv(uv: Vector2, screen_size: float) -> void:
	if not _sprite or not _screen_mesh:
		return
	_sprite.visible = true
	var local := Vector3(
		(uv.x - 0.5) * screen_size,
		0.0,
		(0.5 - uv.y) * screen_size
	)
	var cursor_pos := _screen_mesh.to_global(local)
	var cam_manager = _get_camera_manager()
	if cam_manager and cam_manager.avatar:
		var cam: Camera3D = cam_manager.avatar.camera
		if cam:
			var to_cam := (cam.global_position - cursor_pos).normalized()
			_sprite.global_position = cursor_pos + to_cam * CURSOR_OFFSET
			return
	_sprite.global_position = cursor_pos

func hide() -> void:
	if _sprite:
		_sprite.visible = false

func uv_from_collision(screen_size: float, collision_point: Vector3) -> Vector2:
	var local: Vector3 = _screen_mesh.global_transform.affine_inverse() * collision_point
	var half := screen_size * 0.5
	return Vector2(
		clampf((local.x + half) / screen_size, 0.0, 1.0),
		clampf((half - local.z) / screen_size, 0.0, 1.0)
	)

func click_at_viewport(viewport: SubViewport, uv: Vector2) -> void:
	if not viewport:
		return
	var vp_size := Vector2(viewport.size)
	var pos := Vector2(uv.x, 1.0 - uv.y) * vp_size
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	viewport.push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	viewport.push_input(up)
