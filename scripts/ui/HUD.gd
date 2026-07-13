extends CanvasLayer

class_name HUD

signal mode_changed(mode: Mode)
signal fps_button_pressed

enum Mode { NONE, RAISE, LOWER, GEN, VAT, GARAGE, BEACON, NEST }

var current_mode: Mode = Mode.NONE

@onready var _root: Control = $HUDRoot
@onready var energy_bar: ProgressBar = %EnergyBar
@onready var energy_label: Label = %EnergyLabel
@onready var energy_rate_label: Label = %EnergyRateLabel
@onready var notification_list: VBoxContainer = %List
@onready var fps_button: Button = %FPSButton

var _mode_buttons: Array[Button] = []
var _prev_energy: float = 5000.0
var _notification_count: int = 0
const MAX_NOTIFICATIONS := 5

func _ready():
	_mode_buttons = [
		%RaiseBtn, %LowerBtn,
		%GenBtn, %VatBtn, %GarageBtn, %BeaconBtn, %NestBtn,
	]
	var modes := [
		Mode.RAISE, Mode.LOWER,
		Mode.GEN, Mode.VAT, Mode.GARAGE, Mode.BEACON, Mode.NEST,
	]
	for i in _mode_buttons.size():
		var btn := _mode_buttons[i]
		btn.pressed.connect(_on_mode_pressed.bind(modes[i]))
		btn.add_theme_font_size_override("font_size", 12)

	fps_button.pressed.connect(func(): fps_button_pressed.emit())

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
	if current_mode == mode:
		current_mode = Mode.NONE
	else:
		current_mode = mode
	_update_button_styles()
	mode_changed.emit(current_mode)


func _update_button_styles():
	var modes := [
		Mode.RAISE, Mode.LOWER,
		Mode.GEN, Mode.VAT, Mode.GARAGE, Mode.BEACON, Mode.NEST,
	]
	for i in _mode_buttons.size():
		var btn := _mode_buttons[i]
		if modes[i] == current_mode:
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
	var t := Time.get_ticks_msec() / 1000.0
	var current := 3000.0 + sin(t * 0.5) * 2000.0
	var rate := cos(t * 0.3) * 150.0
	return {"current": current, "capacity": 6000.0, "rate": rate}


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
