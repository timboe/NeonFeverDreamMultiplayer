extends Control

class_name GarageHUD

const PLAYER_NAMES: Array[String] = ["", "Red", "Blue", "Green", "Yellow"]

var building: Garage

@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn
@onready var prod_btn: Button = $Window/VBox/ProdRow/ProdBtn
@onready var ratio_slider: HSlider = $Window/VBox/RatioRow/RatioSlider
@onready var ratio_label: Label = $Window/VBox/RatioRow/RatioHeader/RatioLabel
@onready var ratio_total_label: Label = $Window/VBox/RatioRow/RatioTotalLabel
@onready var tank_label: Label = $Window/VBox/TankRow/TankLabel
@onready var spawn_bar: ProgressBar = $Window/VBox/SpawnRow/SpawnBar
@onready var empower_indicator: Label = $Window/VBox/EmpowerRow/EmpowerIndicator
@onready var enemy_grid: GridContainer = $Window/VBox/EnemyGrid

var _enemy_buttons: Dictionary = {}
var _cursor: Cursor3D

func _ready() -> void:
	if not ratio_slider:
		return
	ratio_slider.value_changed.connect(_on_ratio_changed)
	prod_btn.pressed.connect(_on_prod_pressed)
	if empower_btn:
		empower_btn.pressed.connect(_on_empower_pressed)
	_build_enemy_buttons()

func _build_enemy_buttons() -> void:
	for i in range(1, 5):
		var btn := Button.new()
		btn.text = PLAYER_NAMES[i]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(60, 32)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_enemy_toggle.bind(i))
		enemy_grid.add_child(btn)
		_enemy_buttons[i] = btn

func _on_enemy_toggle(pnum: int) -> void:
	if not building:
		return
	var targets := building._enemy_targets.duplicate()
	if pnum in targets:
		targets.erase(pnum)
	else:
		targets.append(pnum)
	Global.send_command_me("set_enemy_targets", [building.id, targets])

func setup_cursor_3d(screen: MeshInstance3D) -> void:
	_cursor = Cursor3D.new(screen, Config.TERMINAL_SCREEN_SIZE)

func _on_empower_pressed() -> void:
	if building:
		Global.send_command_me("empower", [building.id])

func _on_ratio_changed(value: float) -> void:
	if building:
		Global.send_command_me("set_garage_ratio", [building.id, value / 100.0])

func _on_prod_pressed() -> void:
	if building:
		Global.send_command_me("toggle_production", [building.id])

func _process(_delta: float) -> void:
	if not building or not prod_btn:
		return
	prod_btn.text = "PRODUCING" if building._production_enabled else "PAUSED"
	var pct := int(building.zoomba_tank_ratio * 100)
	ratio_slider.set_value_no_signal(pct)
	ratio_label.text = str(100 - pct) + "% / " + str(pct) + "%"
	tank_label.text = str(building.cached_tank_count)
	# Ratio total across all garages
	var total_ratio := 0.0
	var bm = Global.BM
	if bm:
		for b in bm.buildings():
			if b is Garage and b.player_owner == building.player_owner:
				total_ratio += b.zoomba_tank_ratio
	var total_pct := int(total_ratio * 100)
	ratio_total_label.text = "Total: " + str(total_pct) + "%"
	if total_pct > 100:
		ratio_total_label.add_theme_color_override("font_color", Color.RED)
	else:
		ratio_total_label.add_theme_color_override("font_color", Color.WHITE)
	var cooldown: float = Config.PRODUCTION_COOLDOWNS.get(building.type, 6.0)
	if building._production_timer > 0.0:
		var progress := (cooldown - building._production_timer) / cooldown * 100.0
		spawn_bar.value = progress
	else:
		spawn_bar.value = 0.0
	empower_indicator.visible = building.is_empowered
	for pnum in _enemy_buttons:
		var btn: Button = _enemy_buttons[pnum]
		btn.set_pressed_no_signal(pnum in building._enemy_targets)

func show_cursor_at_uv(uv: Vector2) -> void:
	if _cursor:
		_cursor.show_at_uv(uv, Config.TERMINAL_SCREEN_SIZE)

func hide_cursor() -> void:
	if _cursor:
		_cursor.hide()

func click_at_uv(uv: Vector2) -> void:
	var viewport := get_viewport() as SubViewport
	if _cursor:
		_cursor.click_at_viewport(viewport, uv)

func uv_from_collision(screen_mesh: MeshInstance3D, collision_point: Vector3) -> Vector2:
	if _cursor:
		return _cursor.uv_from_collision(Config.TERMINAL_SCREEN_SIZE, collision_point)
	return Vector2.ZERO
