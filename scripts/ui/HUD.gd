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
# Terminal HUDs are designed for this viewport size; scaled to fit the tooltip.
const HUD_DESIGN_SIZE: float = 480.0

# --- State ---

var tile_mode: Mode = Mode.LOWER
var build_mode: Mode = Mode.NONE
var _drag_action: DragAction = DragAction.NONE
var _tooltip_hud  # cached tooltip HUD Control (per building type)
var _tooltip_hud_type: BuildingManager.Type = BuildingManager.Type.NONE

# --- Nodes ---

@onready var _root: Control = $HUDRoot
@onready var energy_bar: ProgressBar = %EnergyBar
@onready var energy_label: Label = %EnergyLabel
@onready var energy_rate_label: Label = %EnergyRateLabel
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
		btn.add_theme_font_size_override("font_size", 12)
	for mode in _build_buttons:
		var btn: Button = _build_buttons[mode]
		btn.pressed.connect(_on_mode_pressed.bind(mode))
		btn.add_theme_font_size_override("font_size", 12)
	fps_button.pressed.connect(func(): toggle_camera.emit())
	_style_all_panels()
	_apply_player_color()
	_update_button_styles()

func _process(_delta: float) -> void:
	_update_camera_ui()
	_update_tooltip()
	var e := _get_player_energy()
	energy_bar.max_value = e.capacity
	energy_bar.value = e.current
	energy_label.text = str(int(e.current))

	var rate: float = e.rate
	energy_rate_label.text = ("+" if rate >= 0 else "") + str(int(rate)) + "/s"
	energy_rate_label.add_theme_color_override(
		"font_color", Color.GREEN if rate >= 0 else Color.RED)

	if e.capacity > 0 and e.current / e.capacity < 0.2:
		var fill_sb := _root.get_theme_stylebox("fill", "ProgressBar") as StyleBoxFlat
		if fill_sb:
			fill_sb.bg_color = Color.RED
	else:
		var fill_sb := _root.get_theme_stylebox("fill", "ProgressBar") as StyleBoxFlat
		if fill_sb:
			fill_sb.bg_color = Color.CYAN

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
		_scale_tooltip_hud()
		var vp_size := Vector2(get_viewport().size)
		var mouse := get_viewport().get_mouse_position()
		var pos := mouse + Vector2(24, 24)
		pos.x = clampf(pos.x, 0.0, maxf(0.0, vp_size.x - tooltip.size.x))
		pos.y = clampf(pos.y, 0.0, maxf(0.0, vp_size.y - tooltip.size.y))
		tooltip.position = pos
		tooltip.visible = true
	else:
		tooltip.visible = false

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

# The SubViewport renders at the tooltip's (smaller) size, so scale the HUD —
# designed for HUD_DESIGN_SIZE — down around its centre to fit inside it.
func _scale_tooltip_hud() -> void:
	if not _tooltip_hud:
		return
	var k := minf(Vector2(tooltip_viewport.size).x, Vector2(tooltip_viewport.size).y) / HUD_DESIGN_SIZE
	_tooltip_hud.pivot_offset = _tooltip_hud.size * 0.5
	_tooltip_hud.scale = Vector2.ONE * k

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
	return {"current": 0.0, "capacity": 0.0, "rate": 0.0}

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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0.3, 0.35, 0.7)
	sb.set_border_width_all(1)
	sb.border_color = Color(0, 1, 1, 1)
	sb.shadow_color = Color(0, 1, 1, 0.5)
	sb.shadow_size = 12
	sb.set_corner_radius_all(20)
	sb.content_margin_left = 12.0
	sb.content_margin_top = 4.0
	sb.content_margin_right = 12.0
	sb.content_margin_bottom = 4.0
	return sb

# --- Styling ---

func _style_all_panels() -> void:
	for node in _root.get_children():
		if node is PanelContainer:
			_style_panel(node)

func _style_panel(panel: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	# The RTS tooltip shows a building HUD (which has its own black background),
	# so keep its fill black for a uniform backdrop.
	sb.bg_color = Color(0, 0, 0, 1) if panel == tooltip else Color(0.02, 0.02, 0.05, 0.88)
	sb.set_border_width_all(2)
	sb.border_color = Color(0, 1, 1, 0.7)
	sb.shadow_color = Color(0, 1, 1, 0.3)
	sb.shadow_size = 8
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 10.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)

func _apply_player_color() -> void:
	var pnum: int = Global.my_player_number
	if pnum < 1 or pnum > Config.PLAYER_COLORS.size():
		return
	var c: Color = Config.PLAYER_COLORS[pnum - 1]
	for node in _root.get_children():
		if node is PanelContainer:
			var sb := node.get_theme_stylebox("panel") as StyleBoxFlat
			if sb:
				sb.border_color = Color(c.r, c.g, c.b, 0.7)
				sb.shadow_color = Color(c.r, c.g, c.b, 0.3)

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
