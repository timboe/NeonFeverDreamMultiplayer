extends TerminalHUD

class_name BeaconHUD

const PLAYER_NAMES: Array[String] = ["", "Red", "Blue", "Green", "Yellow"]
const BUILDING_TYPE_NAMES: Dictionary = {
	BuildingManager.Type.MCP_1: "MCP",
	BuildingManager.Type.GEN: "Generator",
	BuildingManager.Type.VAT: "Vat",
	BuildingManager.Type.GARAGE: "Garage",
	BuildingManager.Type.BEACON: "Beacon",
	BuildingManager.Type.NEST: "Nest",
}

var building: Beacon

@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn
@onready var prod_btn: Button = $Window/VBox/ProdRow/ProdBtn
@onready var ratio_slider: HSlider = $Window/VBox/RatioRow/RatioSlider
@onready var ratio_label: Label = $Window/VBox/RatioRow/RatioHeader/RatioLabel
@onready var enemy_grid: GridContainer = $Window/VBox/EnemyGrid
@onready var strike_grid: GridContainer = $Window/VBox/StrikeGrid
@onready var strike_nearest_btn: Button = $Window/VBox/StrikePriorityRow/StrikeNearestBtn
@onready var strike_lowest_btn: Button = $Window/VBox/StrikePriorityRow/StrikeLowestBtn
@onready var patrol_hold_btn: Button = $Window/VBox/PatrolStanceRow/PatrolHoldBtn
@onready var patrol_wide_btn: Button = $Window/VBox/PatrolStanceRow/PatrolWideBtn
@onready var aerial_label: Label = $Window/VBox/AerialRow/AerialLabel
@onready var spawn_bar: ProgressBar = $Window/VBox/SpawnRow/SpawnBar
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
	strike_nearest_btn.pressed.connect(_on_strike_priority.bind(JobManager.Priority.NEAREST))
	strike_lowest_btn.pressed.connect(_on_strike_priority.bind(JobManager.Priority.LOWEST_HP))
	patrol_hold_btn.pressed.connect(_on_patrol_stance.bind(JobManager.Stance.HOLD))
	patrol_wide_btn.pressed.connect(_on_patrol_stance.bind(JobManager.Stance.WIDE))
	_build_enemy_buttons()
	_build_strike_buttons()

func _on_empower_pressed() -> void:
	_empower_building(building)

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

func _build_strike_buttons() -> void:
	for t in BUILDING_TYPE_NAMES:
		var btn := Button.new()
		btn.text = BUILDING_TYPE_NAMES[t]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(60, 32)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_strike_toggle.bind(t))
		strike_grid.add_child(btn)
		_strike_buttons[t] = btn

func _on_ratio_changed(value: float) -> void:
	if building:
		Global.send_command_me("set_beacon_ratio", [building.id, value / 100.0])

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

func _on_strike_priority(priority: JobManager.Priority) -> void:
	if building:
		Global.send_command_me("set_strike_priority", [building.id, priority])

func _on_patrol_stance(stance: JobManager.Stance) -> void:
	if building:
		Global.send_command_me("set_patrol_stance", [building.id, stance])

func _process(_delta: float) -> void:
	if not building or not prod_btn:
		return
	prod_btn.text = "PRODUCING" if building._production_enabled else "PAUSED"
	var pct := int(building.patrol_strike_ratio * 100)
	ratio_slider.set_value_no_signal(pct)
	ratio_label.text = str(100 - pct) + "% / " + str(pct) + "%"
	for pnum in _enemy_buttons:
		var btn: Button = _enemy_buttons[pnum]
		btn.set_pressed_no_signal(pnum in building._enemy_targets)
	for t in _strike_buttons:
		var btn: Button = _strike_buttons[t]
		btn.set_pressed_no_signal(t in building._building_targets)
	strike_nearest_btn.set_pressed_no_signal(building._strike_priority == JobManager.Priority.NEAREST)
	strike_lowest_btn.set_pressed_no_signal(building._strike_priority == JobManager.Priority.LOWEST_HP)
	patrol_hold_btn.set_pressed_no_signal(building._patrol_stance == JobManager.Stance.HOLD)
	patrol_wide_btn.set_pressed_no_signal(building._patrol_stance == JobManager.Stance.WIDE)
	var um = Global.UM
	if um:
		aerial_label.text = str(um.unit_count(building.player_owner, UnitManager.Type.AERIAL))
	var cooldown: float = Config.PRODUCTION_COOLDOWNS.get(building.type, 4.0)
	if building._production_timer > 0.0:
		var progress := (cooldown - building._production_timer) / cooldown * 100.0
		spawn_bar.value = progress
	else:
		spawn_bar.value = 0.0
	empower_indicator.visible = building.is_empowered
