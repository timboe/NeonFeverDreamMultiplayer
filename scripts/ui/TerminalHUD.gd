extends Control

class_name TerminalHUD

# Shared cursor wiring for all diegetic terminal HUDs. Each subclass scene must
# contain a "Cursor" node (TerminalCursor scene/script) that the avatar ray drives.
@onready var cursor: TerminalCursor = $Cursor

var _crt_overlay: ColorRect
var _crt_material: ShaderMaterial

# The CRT overlay is added in _enter_tree so it works for every terminal HUD
# without each subclass having to call super._ready().
func _enter_tree() -> void:
	if _crt_overlay == null or not is_instance_valid(_crt_overlay):
		_crt_overlay = _build_crt_overlay()
		add_child(_crt_overlay)
	# Buttons are created by subclass _ready (scene + code), so attach the hover
	# glow-pulse after the ready pass.
	call_deferred("_attach_button_pulses")
	call_deferred("_apply_owner_color")
	call_deferred("_add_section_strips")

func _owner_accent() -> Color:
	var b = get("building")
	if b != null and is_instance_valid(b):
		return Config.player_accent(b.player_owner)
	return Color.WHITE

# --- Targeting button theming ---

# Duplicate a themed Button stylebox and tint its border/glow with a player
# colour, mirroring the main HUD's per-player button styling.
func _tinted_button_style(state: StringName, border: Color, glow: Color) -> StyleBoxFlat:
	var base := get_theme_stylebox(state, &"Button") as StyleBoxFlat
	if base == null:
		return null
	var sb: StyleBoxFlat = base.duplicate()
	sb.border_color = border
	sb.shadow_color = glow
	return sb

# Apply the same base/hover/pressed/focus/disabled colours the main HUD uses to a
# toggle button, tinted with the colour of the player the button targets.
func _apply_enemy_button_theme(btn: Button, pnum: int) -> void:
	var c := Config.player_accent(pnum)
	var lit := Color(c.r, c.g, c.b, Config.BUTTON_LIT_ALPHA)
	btn.add_theme_stylebox_override("normal", _tinted_button_style(&"normal", Color(c.r, c.g, c.b, Config.BUTTON_NORMAL_BORDER_ALPHA), Color(c.r, c.g, c.b, Config.BUTTON_NORMAL_GLOW_ALPHA)))
	btn.add_theme_stylebox_override("hover", _tinted_button_style(&"hover", lit, Color(c.r, c.g, c.b, Config.BUTTON_HOVER_GLOW_ALPHA)))
	var pressed := _tinted_button_style(&"pressed", lit, Color(c.r, c.g, c.b, Config.BUTTON_PRESSED_GLOW_ALPHA))
	if pressed:
		pressed.bg_color = Color(c.r * Config.BUTTON_PRESSED_BG_SCALE, c.g * Config.BUTTON_PRESSED_BG_SCALE, c.b * Config.BUTTON_PRESSED_BG_SCALE, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", _tinted_button_style(&"focus", Color(c.r, c.g, c.b, Config.BUTTON_FOCUS_BORDER_ALPHA), Color(c.r, c.g, c.b, Config.BUTTON_FOCUS_GLOW_ALPHA)))
	btn.add_theme_stylebox_override("disabled", _tinted_button_style(&"disabled", Color(c.r, c.g, c.b, Config.BUTTON_DISABLED_BORDER_ALPHA), Color(c.r, c.g, c.b, Config.BUTTON_DISABLED_GLOW_ALPHA)))

# Rebuild the dynamically-created targeting buttons. Needed because the RTS
# tooltip instantiates the HUD scene before its `building` is assigned, so the
# owner-filter (skip self) and owner tint can't be applied in _ready.
func _rebuild_enemy_buttons(grid: GridContainer, dict: Dictionary) -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	dict.clear()
	_build_enemy_buttons()

# Overridden by subclasses to populate their enemy-targeting grid.
func _build_enemy_buttons() -> void:
	pass

# --- Section header accent strips ---

# Every Label using the SectionHeader theme variation gets a short accent bar on
# its left. The bar is coloured with the building owner's player colour.
func _add_section_strips() -> void:
	if not is_inside_tree():
		return
	var accent := _owner_accent()
	for lbl in _find_section_labels(self):
		if lbl.has_meta("_section_strip"):
			continue
		var container := lbl.get_parent()
		if container is VBoxContainer:
			# Wrap in a row so the strip sits to the left of the text.
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			container.add_child(row)
			container.move_child(row, lbl.get_index())
			container.remove_child(lbl)
			row.add_child(lbl)
			container = row
		if container is HBoxContainer:
			var strip := ColorRect.new()
			strip.custom_minimum_size = Vector2(4, 0)
			strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			strip.color = Color(accent.r, accent.g, accent.b, 0.9)
			container.add_child(strip)
			container.move_child(strip, lbl.get_index())
			lbl.set_meta("_section_strip", strip)

func _tint_section_strips(accent: Color) -> void:
	for lbl in _find_section_labels(self):
		if lbl.has_meta("_section_strip"):
			var strip = lbl.get_meta("_section_strip")
			strip.color = Color(accent.r, accent.g, accent.b, 0.9)

func _find_section_labels(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in node.get_children():
		if child is Label and (child as Label).theme_type_variation == &"SectionHeader":
			out.append(child)
		out.append_array(_find_section_labels(child))
	return out

# Tint the terminal window border to the owning player's accent colour.
func set_building_owner(pnum: int) -> void:
	_tint_window(pnum)

func _apply_owner_color() -> void:
	if not is_inside_tree():
		return
	var b = get("building")
	if b != null and is_instance_valid(b):
		_tint_window(b.player_owner)

func _tint_window(pnum: int) -> void:
	var accent := Config.player_accent(pnum)
	# Tint the terminal window border/glow with the owner's colour.
	var window := get_node_or_null("Window") as PanelContainer
	if window:
		var sb := CutCornerBox.new()
		sb.cut = 12.0
		sb.fill_color = Color(0.03, 0.04, 0.08, 0.92)
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.6)
		sb.border_width = 2.0
		sb.content_margin_left = 12.0
		sb.content_margin_top = 10.0
		sb.content_margin_right = 12.0
		sb.content_margin_bottom = 10.0
		window.add_theme_stylebox_override("panel", sb)
	# Tint the CRT phosphor to match.
	if _crt_material:
		_crt_material.set_shader_parameter("phosphor_tint", accent)
	# Tint the terminal cursor glow to match.
	var cursor_node := get_node_or_null("Cursor") as TerminalCursor
	if cursor_node:
		cursor_node.set_glow_color(Color(accent.r, accent.g, accent.b, 0.55))
	# Tint the section-header accent strips to match.
	_tint_section_strips(accent)

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
	_crt_material = mat
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

func drive_cursor_at_uv(uv: Vector2, held: bool, just_pressed: bool, just_released: bool) -> void:
	if cursor:
		cursor.drive_at_uv(uv, held, just_pressed, just_released)

func release_cursor() -> void:
	if cursor:
		cursor.release()

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
	# The tooltip preview isn't a diegetic screen — drop the CRT overlay and the
	# black screen bezel, and let the terminal fill the tooltip so the two
	# player-tinted borders sit close together.
	if _crt_overlay:
		_crt_overlay.visible = not active
	var bg := get_node_or_null("Background") as ColorRect
	if bg:
		bg.visible = not active
	var window := get_node_or_null("Window") as PanelContainer
	if window and active:
		window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _tooltip_hidden_controls() -> Array[Control]:
	var btn := get_node_or_null("Window/VBox/Header/EmpowerBtn") as Button
	return [btn]
