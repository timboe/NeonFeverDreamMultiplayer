extends CanvasLayer

class_name HUD

# --- Signals ---

signal mode_changed(mode: Mode)
signal toggle_camera

# --- Types ---

enum Mode {NONE, RAISE, LOWER, GEN, VAT, GARAGE, BEACON, NEST}
enum DragAction {NONE, SELECTING, UNSELECTING}

# --- Constants ---

const MODE_TO_BUILDING_TYPE: Dictionary = {
	Mode.GEN: BuildingManager.Type.GEN,
	Mode.VAT: BuildingManager.Type.VAT,
	Mode.GARAGE: BuildingManager.Type.GARAGE,
	Mode.BEACON: BuildingManager.Type.BEACON,
	Mode.NEST: BuildingManager.Type.NEST,
}

# --- State ---

var tile_mode: Mode = Mode.LOWER
var build_mode: Mode = Mode.NONE
var _drag_action: DragAction = DragAction.NONE
var _tooltip_hud  # cached tooltip HUD Control (per building type)
var _tooltip_hud_type: BuildingManager.Type = BuildingManager.Type.NONE
var _active_btn_style: StyleBoxFlat
var _energy_fill_sb: StyleBoxFlat
var _tooltip_tween: Tween

# --- Nodes ---

@onready var _root: Control = $HUDRoot
@onready var energy_bar: ProgressBar = %EnergyBar
@onready var energy_label: Label = %EnergyLabel
@onready var energy_prod_label: Label = %EnergyProdLabel
@onready var energy_cons_label: Label = %EnergyConsLabel
@onready var fps_button: Button = %FPSButton
@onready var crosshair: Control = $HUDRoot/Crosshair
@onready var mode_bar: PanelContainer = $HUDRoot/ModeBar
@onready var tooltip: PanelContainer = $HUDRoot/Tooltip
@onready var tooltip_viewport: SubViewport = $HUDRoot/Tooltip/SubViewportContainer/Viewport

var _tile_buttons: Dictionary = {}
var _build_buttons: Dictionary = {}
# --- Queries ---

func building_being_placed() -> int:
	return MODE_TO_BUILDING_TYPE.get(build_mode, BuildingManager.Type.NONE)

func is_placing() -> bool:
	return build_mode != Mode.NONE

func can_toggle_tile(tile: TileElement) -> bool:
	if build_mode != Mode.NONE:
		return false
	match tile_mode:
		Mode.RAISE:
			return tile.state == TileManager.State.LOWERED
		Mode.LOWER:
			return tile.state == TileManager.State.RAISED
	return false

# --- Lifecycle ---

func _ready() -> void:
	add_to_group("hud")
	_tile_buttons = {Mode.RAISE: %RaiseBtn, Mode.LOWER: %LowerBtn}
	_build_buttons = {
		Mode.GEN: %GenBtn, Mode.VAT: %VatBtn, Mode.GARAGE: %GarageBtn,
		Mode.BEACON: %BeaconBtn, Mode.NEST: %NestBtn,
	}
	for mode in _tile_buttons:
		var btn: Button = _tile_buttons[mode]
		btn.pressed.connect(_on_mode_pressed.bind(mode))
	for mode in _build_buttons:
		var btn: Button = _build_buttons[mode]
		btn.pressed.connect(_on_mode_pressed.bind(mode))
	fps_button.pressed.connect(func(): toggle_camera.emit())
	_apply_player_color()
	_update_button_styles()
	_style_crosshair()
	# Hover glow-pulse on the mode + FPS buttons, tinted with the player accent.
	var accent := Config.player_accent(Global.my_player_number)
	var glow := Color(accent.r, accent.g, accent.b, 0.6)
	for mode in _tile_buttons:
		UiFX.attach_glow_pulse(_tile_buttons[mode], glow)
	for mode in _build_buttons:
		UiFX.attach_glow_pulse(_build_buttons[mode], glow)
	UiFX.attach_glow_pulse(fps_button, glow)
	# Dedicated fill stylebox for the energy bar so low-energy tinting doesn't
	# mutate the shared theme fill (which other ProgressBars use).
	_energy_fill_sb = (energy_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	energy_bar.add_theme_stylebox_override("fill", _energy_fill_sb)

func _process(_delta: float) -> void:
	_update_camera_ui()
	_update_tooltip()
	var e := _get_player_energy()
	energy_bar.max_value = e.capacity
	energy_bar.value = e.current
	energy_label.text = str(int(e.current))

	energy_prod_label.text = "+" + str(int(e.produced)) + "/s"
	energy_cons_label.text = "-" + str(int(e.consumed)) + "/s"
	energy_prod_label.add_theme_color_override("font_color", Config.UI_SUCCESS)
	energy_cons_label.add_theme_color_override("font_color", Config.UI_WARNING)

	if e.capacity > 0 and e.current / e.capacity < 0.2:
		if _energy_fill_sb:
			_energy_fill_sb.bg_color = Config.UI_DANGER
			_energy_fill_sb.shadow_color = Color(1, 0.25, 0.25, 0.4)
	else:
		if _energy_fill_sb:
			_energy_fill_sb.bg_color = Config.UI_ACCENT
			_energy_fill_sb.shadow_color = Color(0, 1, 1, 0.4)

func _input(event: InputEvent) -> void:
	if not Global.game_started:
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		end_drag()
	if event.is_action_pressed("ui_capture_toggle"):
		toggle_camera.emit()
	if event.is_action_pressed("ui_scram"):
		for zoomba in get_tree().get_nodes_in_group("zoomba"):
			zoomba.scram()
	if event.is_action_pressed("ui_damage_building"):
		Global.send_command_me("debug_damage_building", [])
	if event.is_action_pressed("ui_damage_unit"):
		Global.send_command_me("debug_damage_unit", [])

# --- Camera UI ---

func _update_camera_ui() -> void:
	var is_fps := false
	var vm = Global.VM
	if vm:
		is_fps = vm.camera_status == vm.CameraStatus.FPS
	crosshair.visible = is_fps
	mode_bar.visible = not is_fps

# --- RTS building tooltip ---

func _exit_tree() -> void:
	_free_tooltip_hud()

func _update_tooltip() -> void:
	var bm = Global.BM
	var hovered: Building = bm.hovered_building if bm else null
	var vm = Global.VM
	var in_rts: bool = vm != null and vm.camera_status == vm.CameraStatus.OVERHEAD
	# Tooltip is only for the current player's buildings — no need to build the
	# HUD preview for other players' local instances.
	if in_rts and hovered and is_instance_valid(hovered) \
		and hovered.state == Building.State.CONSTRUCTED \
		and hovered.player_owner == Global.my_player_number:
		_set_tooltip_building(hovered)
		var vp_size := Vector2(get_viewport().size)
		var mouse := get_viewport().get_mouse_position()
		var pos := mouse + Vector2(24, 24)
		pos.x = clampf(pos.x, 0.0, maxf(0.0, vp_size.x - tooltip.size.x))
		pos.y = clampf(pos.y, 0.0, maxf(0.0, vp_size.y - tooltip.size.y))
		tooltip.position = pos
		if not tooltip.visible:
			tooltip.visible = true
			_fade_tooltip(true)
	else:
		if tooltip.visible:
			tooltip.visible = false
			_fade_tooltip(false)

func _fade_tooltip(fade_in: bool) -> void:
	if _tooltip_tween and _tooltip_tween.is_valid():
		_tooltip_tween.kill()
	_tooltip_tween = null
	if fade_in:
		tooltip.modulate.a = 0.0
		_tooltip_tween = create_tween()
		_tooltip_tween.tween_property(tooltip, "modulate:a", 1.0, 0.15)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		tooltip.modulate.a = 1.0

func _set_tooltip_building(b: Building) -> void:
	if _tooltip_hud and _tooltip_hud_type == b.type and _tooltip_hud.building == b:
		return
	if _tooltip_hud_type != b.type:
		_free_tooltip_hud()
		var hud_scene: PackedScene = b._get_hud_scene()
		if not hud_scene:
			return
		var ctrl = hud_scene.instantiate()
		tooltip_viewport.add_child(ctrl)
		_tooltip_hud = ctrl
		_tooltip_hud_type = b.type
		if ctrl.has_method("set_tooltip_mode"):
			ctrl.set_tooltip_mode(true)
	_tooltip_hud.building = b
	if _tooltip_hud.has_method("set_building_owner"):
		_tooltip_hud.set_building_owner(b.player_owner)

func _free_tooltip_hud() -> void:
	if _tooltip_hud:
		_tooltip_hud.queue_free()
		_tooltip_hud = null
	_tooltip_hud_type = BuildingManager.Type.NONE

# --- Energy ---

func _get_player_energy() -> Dictionary:
	var em = Global.EM
	if em:
		return em.get_player_energy(Global.my_player_number)
	return {"current": 0.0, "capacity": 0.0, "produced": 0.0, "consumed": 0.0}

# --- Mode buttons ---

func _on_mode_pressed(mode: Mode) -> void:
	end_drag()
	if mode == Mode.RAISE or mode == Mode.LOWER:
		tile_mode = mode
		build_mode = Mode.NONE
	else:
		if build_mode == mode:
			build_mode = Mode.NONE
		else:
			build_mode = mode
	_update_button_styles()
	mode_changed.emit(mode)

func clear_build_mode() -> void:
	build_mode = Mode.NONE
	_update_button_styles()

func _update_button_styles() -> void:
	for mode in _tile_buttons:
		var btn: Button = _tile_buttons[mode]
		if mode == tile_mode:
			btn.add_theme_stylebox_override("normal", _active_style())
			btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			btn.remove_theme_stylebox_override("normal")
			btn.remove_theme_color_override("font_color")
	for mode in _build_buttons:
		var btn: Button = _build_buttons[mode]
		if mode == build_mode:
			btn.add_theme_stylebox_override("normal", _active_style())
			btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			btn.remove_theme_stylebox_override("normal")
			btn.remove_theme_color_override("font_color")

func _active_style() -> StyleBoxFlat:
	return _active_btn_style

# --- Styling ---

# Panels and buttons are styled by the theme; here we re-tint them with the
# local player's accent colour. The active-mode buttons reuse the theme's
# pressed stylebox, tinted with the player accent.
func _apply_player_color() -> void:
	var c := Config.player_accent(Global.my_player_number)
	var lit := Color(c.r, c.g, c.b, 0.85)
	var dim := Color(c.r, c.g, c.b, 0.35)
	for node in _root.get_children():
		if node is PanelContainer:
			var cut_sb := CutCornerBox.new()
			cut_sb.cut = 12.0
			cut_sb.border_color = lit
			cut_sb.border_width = 2.0
			cut_sb.fill_color = Color(0.02, 0.02, 0.05, 0.92)
			if node == tooltip:
				# Keep the outer tooltip panel tight around the terminal preview so
				# its border sits right next to the terminal HUD's own border.
				cut_sb.content_margin_left = 2.0
				cut_sb.content_margin_top = 2.0
				cut_sb.content_margin_right = 2.0
				cut_sb.content_margin_bottom = 2.0
			else:
				cut_sb.content_margin_left = 12.0
				cut_sb.content_margin_top = 10.0
				cut_sb.content_margin_right = 12.0
				cut_sb.content_margin_bottom = 10.0
			node.add_theme_stylebox_override("panel", cut_sb)
	var pressed := _root.get_theme_stylebox("pressed", "Button") as StyleBoxFlat
	_active_btn_style = pressed.duplicate()
	_active_btn_style.bg_color = Color(c.r * 0.12, c.g * 0.12, c.b * 0.12, 0.85)
	_active_btn_style.border_color = lit
	_active_btn_style.shadow_color = Color(c.r, c.g, c.b, 0.6)

# Tint the FPS crosshair (bars + centre dot) with the player accent, outlined in
# white so it stays visible on vibrant backgrounds, and add a soft glow behind it.
func _style_crosshair() -> void:
	var accent := Config.player_accent(Global.my_player_number)
	for child in crosshair.get_children():
		if child is Panel:
			_set_crosshair_shape(child as Panel, accent)
	var glow := crosshair.get_node_or_null("Glow") as ColorRect
	if glow:
		if glow.material == null:
			var mat := ShaderMaterial.new()
			mat.shader = preload("res://materials/ui/soft_glow.gdshader")
			glow.material = mat
		if glow.material is ShaderMaterial:
			(glow.material as ShaderMaterial).set_shader_parameter("glow_color", Color(accent.r, accent.g, accent.b, 0.35))

func _set_crosshair_shape(p: Panel, accent: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent
	sb.set_border_width_all(1)
	sb.border_color = Color.WHITE
	p.add_theme_stylebox_override("panel", sb)

# --- Drag ---

func begin_drag(tile: TileElement) -> void:
	if _drag_action != DragAction.NONE:
		return
	if Global.my_player_number in tile.selected_by:
		_drag_action = DragAction.UNSELECTING
	else:
		_drag_action = DragAction.SELECTING

func should_toggle(tile: TileElement) -> bool:
	if _drag_action == DragAction.SELECTING:
		return Global.my_player_number not in tile.selected_by
	elif _drag_action == DragAction.UNSELECTING:
		return Global.my_player_number in tile.selected_by
	return false

func end_drag() -> void:
	_drag_action = DragAction.NONE
