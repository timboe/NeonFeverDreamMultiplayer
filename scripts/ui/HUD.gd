extends CanvasLayer

class_name HUD

signal mode_changed(mode: Mode)
signal toggle_camera

enum Mode { NONE, RAISE, LOWER, GEN, VAT, GARAGE, BEACON, NEST }
enum DragAction { NONE, SELECTING, UNSELECTING }

var tile_mode: Mode = Mode.LOWER
var build_mode: Mode = Mode.NONE
var _drag_action: DragAction = DragAction.NONE

@onready var _root: Control = $HUDRoot
@onready var energy_bar: ProgressBar = %EnergyBar
@onready var energy_label: Label = %EnergyLabel
@onready var energy_rate_label: Label = %EnergyRateLabel
@onready var notification_list: VBoxContainer = %List
@onready var fps_button: Button = %FPSButton

var _tile_buttons: Dictionary = {}
var _build_buttons: Dictionary = {}
var _prev_energy: float = 5000.0
var _notification_count: int = 0
const MAX_NOTIFICATIONS := 5

const MODE_TO_BUILDING_TYPE := {
	Mode.GEN: BuildingManager.Type.GEN,
	Mode.VAT: BuildingManager.Type.VAT,
	Mode.GARAGE: BuildingManager.Type.GARAGE,
	Mode.BEACON: BuildingManager.Type.BEACON,
	Mode.NEST: BuildingManager.Type.NEST,
}

func building_being_placed() -> int:
	return MODE_TO_BUILDING_TYPE.get(build_mode, BuildingManager.Type.NONE)

func is_placing() -> bool:
	return build_mode != Mode.NONE

func _ready():
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


func _style_all_panels():
	for node in _root.get_children():
		if node is PanelContainer:
			_style_panel(node)


func _style_panel(panel: PanelContainer):
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.05, 0.88)
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


func _apply_player_color():
	var pnum: int = Global.my_player_number
	if pnum < 0 or pnum >= Config.PLAYER_COLORS.size():
		return
	var c: Color = Config.PLAYER_COLORS[pnum]
	for node in _root.get_children():
		if node is PanelContainer:
			var sb := node.get_theme_stylebox("panel") as StyleBoxFlat
			if sb:
				sb.border_color = Color(c.r, c.g, c.b, 0.7)
				sb.shadow_color = Color(c.r, c.g, c.b, 0.3)


func _on_mode_pressed(mode: Mode):
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


func _update_button_styles():
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


func _process(_delta: float):
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


func _get_player_energy() -> Dictionary:
	var em = get_node_or_null("/root/World/EnergyManager")
	if em:
		return em.get_player_energy(Global.my_player_number)
	return {"current": 0.0, "capacity": 0.0, "rate": 0.0}


func add_notification(text: String, duration: float = 5.0) -> void:
	_notification_count += 1
	if _notification_count > MAX_NOTIFICATIONS:
		var first := notification_list.get_child(1) as Label
		if first:
			first.queue_free()
		_notification_count -= 1

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notification_list.add_child(label)

	var tween := create_tween()
	tween.tween_interval(duration - 2.0)
	tween.tween_property(label, "modulate:a", 0.0, 2.0)
	tween.tween_callback(label.queue_free)


func _input(event: InputEvent):
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		end_drag()
	if event.is_action_pressed("capture_toggle"):
		toggle_camera.emit()


func can_toggle_tile(tile: TileElement) -> bool:
	if build_mode != Mode.NONE:
		return false
	match tile_mode:
		Mode.RAISE:
			return tile.state == TileManager.State.LOWERED
		Mode.LOWER:
			return tile.state == TileManager.State.RAISED
	return false


func begin_drag(tile: TileElement):
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


func end_drag():
	_drag_action = DragAction.NONE
