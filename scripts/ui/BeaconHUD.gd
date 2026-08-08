extends TerminalHUD

class_name BeaconHUD

const BUILDING_TYPE_NAMES: Dictionary = {
	BuildingManager.Type.MCP_1: "MCP",
	BuildingManager.Type.GEN: "Gen",
	BuildingManager.Type.VAT: "Vat",
	BuildingManager.Type.GARAGE: "Gar",
	BuildingManager.Type.BEACON: "Bcn",
	BuildingManager.Type.NEST: "Nest",
}

var building: Beacon

@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn
@onready var prod_btn: Button = $Window/VBox/ProdRow/ProdBtn
@onready var ratio_slider: HSlider = $Window/VBox/RatioRow/RatioSlider
@onready var ratio_label: Label = $Window/VBox/RatioRow/RatioHeader/RatioLabel
@onready var enemy_grid: GridContainer = $Window/VBox/EnemyGrid
@onready var strike_grid: GridContainer = $Window/VBox/StrikeGrid
@onready var patrol_hold_btn: Button = $Window/VBox/PatrolStanceRow/PatrolHoldBtn
@onready var patrol_wide_btn: Button = $Window/VBox/PatrolStanceRow/PatrolWideBtn
@onready var aerial_label: Label = $Window/VBox/AerialRow/AerialLabel
@onready var spawn_bar: ProgressBar = $Window/VBox/AerialRow/SpawnBar
@onready var empower_indicator: Label = $Window/VBox/EmpowerRow/EmpowerIndicator

var _enemy_buttons: Dictionary = {}
var _strike_buttons: Dictionary = {}

func _ready() -> void:
	if not ratio_slider:
		return
	ratio_slider.value_changed.connect(_on_ratio_changed)
	prod_btn.pressed.connect(_on_prod_pressed)
	if empower_btn:
		empower_btn.pressed.connect(_on_empower_pressed)
	patrol_hold_btn.pressed.connect(_on_patrol_stance.bind(JobManager.Stance.HOLD))
	patrol_wide_btn.pressed.connect(_on_patrol_stance.bind(JobManager.Stance.WIDE))
	_build_enemy_buttons()
	_build_strike_buttons()

func _on_empower_pressed() -> void:
	_empower_building(building)

func _build_enemy_buttons() -> void:
	var own: int = building.player_owner if building else 0
	for i in range(1, 5):
		if i == own:
			continue
		var btn := Button.new()
		btn.text = Config.PLAYER_NAMES[i - 1]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(60, 32)
		btn.add_theme_font_size_override("font_size", 14)
		_apply_enemy_button_theme(btn, i)
		btn.pressed.connect(_on_enemy_toggle.bind(i))
		enemy_grid.add_child(btn)
		_enemy_buttons[i] = btn

func set_building_owner(pnum: int) -> void:
	super.set_building_owner(pnum)
	_rebuild_enemy_buttons(enemy_grid, _enemy_buttons)

func _build_strike_buttons() -> void:
	for t in BUILDING_TYPE_NAMES:
		var btn := Button.new()
		btn.text = BUILDING_TYPE_NAMES[t]
		btn.toggle_mode = true
		btn.button_pressed = true
		btn.custom_minimum_size = Vector2(60, 32)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_strike_toggle.bind(t))
		strike_grid.add_child(btn)
		_strike_buttons[t] = btn

func _on_ratio_changed(value: float) -> void:
	if building:
		Global.send_command_me("set_beacon_ratio", [building.id, (100.0 - value) / 100.0])
	var pct := int(value)
	ratio_label.text = str(100 - pct) + "% / " + str(pct) + "%"

func _on_prod_pressed() -> void:
	if building:
		Global.send_command_me("toggle_production", [building.id])

func _on_enemy_toggle(pnum: int) -> void:
	if not building:
		return
	var targets := building._enemy_targets.duplicate()
	if pnum in targets:
		targets.erase(pnum)
	else:
		targets.append(pnum)
	Global.send_command_me("set_enemy_targets", [building.id, targets])

func _on_strike_toggle(t: BuildingManager.Type) -> void:
	if not building:
		return
	var targets := building._building_targets.duplicate()
	if t in targets:
		targets.erase(t)
	else:
		targets.append(t)
	Global.send_command_me("set_building_targets", [building.id, targets])

func _on_patrol_stance(stance: JobManager.Stance) -> void:
	if building:
		Global.send_command_me("set_patrol_stance", [building.id, stance])
	patrol_hold_btn.set_pressed_no_signal(stance == JobManager.Stance.HOLD)
	patrol_wide_btn.set_pressed_no_signal(stance == JobManager.Stance.WIDE)

func _process(_delta: float) -> void:
	if not building or not prod_btn:
		return
	prod_btn.text = "PRODUCING" if building._production_enabled else "PAUSED"
	prod_btn.set_pressed_no_signal(building._production_enabled)
	var um = Global.UM
	if um:
		aerial_label.text = str(um.unit_count(building.player_owner, UnitManager.Type.AERIAL))
	if building._production_cost > 0.0:
		spawn_bar.value = clampf(building._production_energy / building._production_cost * 100.0, 0.0, 100.0)
	else:
		spawn_bar.value = 0.0
	empower_indicator.visible = building.is_empowered
	if _should_render_controls_from_vars():
		_update_controls_from_vars()

# Set the config controls (ratio slider, enemy targets, strike targets, patrol
# stance) from the building's settings. Runs for other players' terminals
# (spying) and the RTS tooltip; owned terminals are client-set only.
func _update_controls_from_vars() -> void:
	if not building:
		return
	var pct := int((1.0 - building.patrol_strike_ratio) * 100)
	ratio_slider.set_value_no_signal(pct)
	ratio_label.text = str(100 - pct) + "% / " + str(pct) + "%"
	for pnum in _enemy_buttons:
		var btn: Button = _enemy_buttons[pnum]
		btn.set_pressed_no_signal(pnum in building._enemy_targets)
	for t in _strike_buttons:
		var btn: Button = _strike_buttons[t]
		btn.set_pressed_no_signal(t in building._building_targets)
	patrol_hold_btn.set_pressed_no_signal(building._patrol_stance == JobManager.Stance.HOLD)
	patrol_wide_btn.set_pressed_no_signal(building._patrol_stance == JobManager.Stance.WIDE)

func refresh_controls_from_building() -> void:
	_update_controls_from_vars()
