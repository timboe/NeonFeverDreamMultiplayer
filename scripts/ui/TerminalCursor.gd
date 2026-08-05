extends TextureRect

class_name TerminalCursor

# Manual pixel offset applied on top of the image-half alignment in show_at_uv(),
# to dial the cursor graphic's tip onto the aim point.
const CURSOR_FINE_TUNE: Vector2 = Vector2(-16, -10)

var _screen_size: float = Config.TERMINAL_SCREEN_SIZE
var _hovered: bool = false
var _tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	_setup_glow()
	hide()

func _setup_glow() -> void:
	var glow := ColorRect.new()
	glow.name = "Glow"
	glow.show_behind_parent = true
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -20.0
	glow.offset_top = -20.0
	glow.offset_right = 20.0
	glow.offset_bottom = 20.0
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://materials/ui/soft_glow.gdshader")
	glow.material = mat
	add_child(glow)

func set_glow_color(color: Color) -> void:
	var glow := get_node_or_null("Glow") as ColorRect
	if glow and glow.material is ShaderMaterial:
		(glow.material as ShaderMaterial).set_shader_parameter("glow_color", color)

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
	_update_hover_visual()

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
	_punch()

func _update_hover_visual() -> void:
	var vp := get_viewport() as SubViewport
	var hovered: bool = false
	if vp:
		var ctrl := vp.gui_get_hovered_control()
		hovered = ctrl is Button
	if hovered == _hovered:
		return
	_hovered = hovered
	_scale_to(1.25 if hovered else 1.0, 0.12)

func _punch() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE * 0.85, 0.06)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "scale", Vector2.ONE * (1.25 if _hovered else 1.0), 0.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _scale_to(target: float, duration: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE * target, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

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
