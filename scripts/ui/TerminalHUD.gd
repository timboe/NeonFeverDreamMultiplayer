extends Control

class_name TerminalHUD

# Shared cursor wiring for all diegetic terminal HUDs. Each subclass scene must
# contain a "Cursor" node (TerminalCursor scene/script) that the avatar ray drives.
@onready var cursor: TerminalCursor = $Cursor

var _crt_overlay: ColorRect

# The CRT overlay is added in _enter_tree so it works for every terminal HUD
# without each subclass having to call super._ready().
func _enter_tree() -> void:
	if _crt_overlay == null or not is_instance_valid(_crt_overlay):
		_crt_overlay = _build_crt_overlay()
		add_child(_crt_overlay)
	# Buttons are created by subclass _ready (scene + code), so attach the hover
	# glow-pulse after the ready pass.
	call_deferred("_attach_button_pulses")

func _attach_button_pulses() -> void:
	if not is_inside_tree():
		return
	for btn in _find_buttons(self):
		UiFX.attach_glow_pulse(btn)

func _find_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_find_buttons(child))
	return out

func _build_crt_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.name = "CRTOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color.BLACK
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://materials/ui/terminal_crt.gdshader")
	overlay.material = mat
	return overlay

func show_cursor_at_uv(uv: Vector2) -> void:
	if cursor:
		cursor.show_at_uv(uv)

func hide_cursor() -> void:
	if cursor:
		cursor.hide_cursor()

func click_at_uv(uv: Vector2) -> void:
	if cursor:
		cursor.click_at(uv)

func uv_from_collision(screen_mesh: MeshInstance3D, collision_point: Vector3) -> Vector2:
	if cursor:
		return cursor.uv_from_collision(screen_mesh, collision_point)
	return Vector2.ZERO

# Shared empower handler: sends the empower command for this building and forces
# the player out of FPS mode (the empowered status is cleared on re-entering FPS).
func _empower_building(b: Building) -> void:
	if not b:
		return
	Global.send_command_me("empower", [b.id])
	var vm = Global.VM
	if vm:
		vm.force_leave_fps()

# --- RTS tooltip mode ---
# When the HUD is rendered as a read-only tooltip in RTS mode, all interactive
# controls are hidden. Subclasses extend _tooltip_hidden_controls() to hide more.
func set_tooltip_mode(active: bool) -> void:
	for c in _tooltip_hidden_controls():
		if c:
			c.visible = not active

func _tooltip_hidden_controls() -> Array[Control]:
	var btn := get_node_or_null("Window/VBox/Header/EmpowerBtn") as Button
	return [btn]
