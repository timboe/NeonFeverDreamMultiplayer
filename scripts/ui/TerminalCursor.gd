extends TextureRect

class_name TerminalCursor

# Manual pixel offset applied on top of the image-half alignment in show_at_uv(),
# to dial the cursor graphic's tip onto the aim point.
const CURSOR_FINE_TUNE: Vector2 = Vector2(-16, -10)

var _screen_size: float = Config.TERMINAL_SCREEN_SIZE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

func show_at_uv(uv: Vector2) -> void:
	show()
	var vp_size := Vector2(480, 480)
	var vp := get_viewport()
	if vp:
		vp_size = Vector2(vp.size)
	# The cursor graphic's tip is its top-left corner. Centre the control on the
	# aim point, then shift by half the texture size so the tip sits on it, then
	# apply a manual fine-tune offset.
	var tex_half := Vector2(texture.get_size()) * 0.5
	global_position = uv * vp_size - size * 0.5 + tex_half + CURSOR_FINE_TUNE
	# Propagate hover to whatever control the cursor tip is over.
	_push_hover(uv * vp_size)

func hide_cursor() -> void:
	hide()
	# Push a motion event off-screen so the GUI clears the hovered control.
	var vp := get_viewport() as SubViewport
	if vp:
		_push_hover(Vector2(-100, -100))

func click_at(uv: Vector2) -> void:
	var viewport := get_viewport() as SubViewport
	if not viewport:
		return
	var pos := uv * Vector2(viewport.size)
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
	print("[TerminalCursor] click at ", pos)

func uv_from_collision(screen_mesh: MeshInstance3D, collision_point: Vector3) -> Vector2:
	if not screen_mesh:
		return Vector2.ZERO
	# Convert the world hit point into the screen plane's local space. The screen
	# PlaneMesh lies in its local XZ plane (texture U -> +X, V -> +Z), so the hit's
	# local.x / local.z map straight onto the viewport's u / v. Because the screen's
	# vertical axis is local.x and its horizontal axis is local.z, this differs from
	# a naive world->viewport mapping by a 90 degree rotation.
	var local: Vector3 = screen_mesh.global_transform.affine_inverse() * collision_point
	var pm := screen_mesh.mesh as PlaneMesh
	var pm_size: float = pm.size.x if pm else _screen_size
	var half := pm_size * 0.5
	var u := clampf((local.x + half) / pm_size, 0.0, 1.0)
	var v := clampf((local.z + half) / pm_size, 0.0, 1.0)
	return Vector2(u, v)

func _push_hover(pos: Vector2) -> void:
	var viewport := get_viewport() as SubViewport
	if not viewport:
		return
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	motion.relative = Vector2.ZERO
	viewport.push_input(motion)
