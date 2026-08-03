extends TerminalHUD

class_name NestHUD

const BUILDING_TYPE_NAMES: Dictionary = {
	BuildingManager.Type.MCP_1: "MCP",
	BuildingManager.Type.GEN: "Generator",
	BuildingManager.Type.VAT: "Vat",
	BuildingManager.Type.GARAGE: "Garage",
	BuildingManager.Type.BEACON: "Beacon",
	BuildingManager.Type.NEST: "Nest",
}

var building: Nest

@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn
@onready var prod_btn: Button = $Window/VBox/ProdRow/ProdBtn
@onready var ratio_slider: HSlider = $Window/VBox/RatioRow/RatioSlider
@onready var ratio_label: Label = $Window/VBox/RatioRow/RatioHeader/RatioLabel
@onready var enemy_grid: GridContainer = $Window/VBox/EnemyGrid
@onready var building_grid: GridContainer = $Window/VBox/BuildingTargetSection/BuildingGrid
@onready var building_target_section: VBoxContainer = $Window/VBox/BuildingTargetSection
@onready var virus_nearest_btn: Button = $Window/VBox/VirusPriorityRow/VirusNearestBtn
@onready var virus_lowest_btn: Button = $Window/VBox/VirusPriorityRow/VirusLowestBtn
@onready var virus_label: Label = $Window/VBox/VirusRow/VirusLabel
@onready var spawn_bar: ProgressBar = $Window/VBox/SpawnRow/SpawnBar
@onready var empower_indicator: Label = $Window/VBox/EmpowerRow/EmpowerIndicator

var _enemy_buttons: Dictionary = {}
var _building_buttons: Dictionary = {}

func _ready() -> void:
	if not ratio_slider:
		return
	ratio_slider.value_changed.connect(_on_ratio_changed)
	prod_btn.pressed.connect(_on_prod_pressed)
	if empower_btn:
		empower_btn.pressed.connect(_on_empower_pressed)
	virus_nearest_btn.pressed.connect(_on_virus_priority.bind(JobManager.Priority.NEAREST))
	virus_lowest_btn.pressed.connect(_on_virus_priority.bind(JobManager.Priority.LOWEST_HP))
	_build_enemy_buttons()
	_build_building_buttons()

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
		btn.pressed.connect(_on_enemy_toggle.bind(i))
		enemy_grid.add_child(btn)
		_enemy_buttons[i] = btn

func _build_building_buttons() -> void:
	for t in BUILDING_TYPE_NAMES:
		var btn := Button.new()
		btn.text = BUILDING_TYPE_NAMES[t]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(60, 32)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_building_toggle.bind(t))
		building_grid.add_child(btn)
		_building_buttons[t] = btn

func _on_ratio_changed(value: float) -> void:
	if building:
		Global.send_command_me("set_nest_ratio", [building.id, value / 100.0])

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

func _on_building_toggle(t: BuildingManager.Type) -> void:
	if not building:
		return
	var targets := building._building_targets.duplicate()
	if t in targets:
		targets.erase(t)
	else:
		targets.append(t)
	Global.send_command_me("set_building_targets", [building.id, targets])

func _on_virus_priority(priority: JobManager.Priority) -> void:
	if building:
		Global.send_command_me("set_virus_priority", [building.id, priority])

func _process(_delta: float) -> void:
	if not building or not prod_btn:
		return
	prod_btn.text = "PRODUCING" if building._production_enabled else "PAUSED"
	prod_btn.set_pressed_no_signal(building._production_enabled)
	var pct := int(building._virus_tank_building_ratio * 100)
	ratio_slider.set_value_no_signal(pct)
	# Label is "Tank / Building"; pct is building ratio, so tank = 100 - pct
	ratio_label.text = str(100 - pct) + "% / " + str(pct) + "%"
	for pnum in _enemy_buttons:
		var btn: Button = _enemy_buttons[pnum]
		btn.set_pressed_no_signal(pnum in building._enemy_targets)
	for t in _building_buttons:
		var btn: Button = _building_buttons[t]
		btn.set_pressed_no_signal(t in building._building_targets)
	virus_nearest_btn.set_pressed_no_signal(building._virus_priority == JobManager.Priority.NEAREST)
	virus_lowest_btn.set_pressed_no_signal(building._virus_priority == JobManager.Priority.LOWEST_HP)
	# Show/hide building targeting section based on ratio
	building_target_section.visible = building._virus_tank_building_ratio < 1.0
	var um = Global.UM
	if um:
		virus_label.text = str(um.unit_count(building.player_owner, UnitManager.Type.VIRUS))
	var cooldown: float = Config.PRODUCTION_COOLDOWNS.get(building.type, 5.0)
	if building._production_timer > 0.0:
		var progress := (cooldown - building._production_timer) / cooldown * 100.0
		spawn_bar.value = progress
	else:
		spawn_bar.value = 0.0
	empower_indicator.visible = building.is_empowered
