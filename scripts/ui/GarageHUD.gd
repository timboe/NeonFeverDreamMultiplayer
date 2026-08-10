extends TerminalHUD

class_name GarageHUD

var building: Garage

@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn
@onready var prod_btn: Button = $Window/VBox/ProdRow/ProdBtn
@onready var ratio_slider: HSlider = $Window/VBox/RatioRow/RatioSlider
@onready var ratio_label: Label = $Window/VBox/RatioRow/RatioHeader/RatioLabel
@onready var ratio_total_label: Label = $Window/VBox/RatioRow/RatioTotalLabel
@onready var tank_label: Label = $Window/VBox/TankRow/TankLabel
@onready var spawn_bar: ProgressBar = $Window/VBox/TankRow/SpawnBar
@onready var empower_indicator: Label = $Window/VBox/EmpowerRow/EmpowerIndicator
@onready var enemy_grid: GridContainer = $Window/VBox/EnemyGrid
@onready var patrol_hold_btn: Button = $Window/VBox/PatrolStanceRow/PatrolHoldBtn
@onready var patrol_wide_btn: Button = $Window/VBox/PatrolStanceRow/PatrolWideBtn

var _enemy_buttons: Dictionary = {}
var _mcp: Node
# Terminal HUDs refresh at 4 Hz — unit counts and ratios change on production
# cadence, not every frame.
const REFRESH_INTERVAL := 0.25
var _refresh_timer := 0.0

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

func _on_enemy_toggle(pnum: int) -> void:
	if not building:
		return
	var targets := building._enemy_targets.duplicate()
	if pnum in targets:
		targets.erase(pnum)
	else:
		targets.append(pnum)
	Global.send_command_me("set_enemy_targets", [building.id, targets])

func _on_empower_pressed() -> void:
	_empower_building(building)

func _on_ratio_changed(value: float) -> void:
	if building:
		Global.send_command_me("set_garage_ratio", [building.id, value / 100.0])
	var pct := int(value)
	ratio_label.text = str(100 - pct) + "% / " + str(pct) + "%"

func _on_prod_pressed() -> void:
	if building:
		Global.send_command_me("toggle_production", [building.id])

func _on_patrol_stance(stance: JobManager.Stance) -> void:
	if building:
		Global.send_command_me("set_patrol_stance", [building.id, stance])
	patrol_hold_btn.set_pressed_no_signal(stance == JobManager.Stance.HOLD)
	patrol_wide_btn.set_pressed_no_signal(stance == JobManager.Stance.WIDE)

# Total tanks this garage requests at equilibrium: the player's zoomba cap
# (from the MCP) times this garage's tank/zoomba ratio.
func _requested_tanks() -> int:
	var cap := 0
	# Cache the MCP ref — group lookup per frame was the hot spot.
	if _mcp == null or not is_instance_valid(_mcp):
		_mcp = get_tree().get_first_node_in_group("mcp_player" + str(building.player_owner))
	if _mcp and _mcp.has_method("zoomba_cap"):
		cap = int(_mcp.zoomba_cap())
	return roundi(cap * building.zoomba_tank_ratio)

func _process(delta: float) -> void:
	if not building or not prod_btn:
		return
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	prod_btn.text = "PRODUCING" if building._production_enabled else "PAUSED"
	prod_btn.set_pressed_no_signal(building._production_enabled)
	var tanks: int = Global.UM.unit_count(building.player_owner, UnitManager.Type.TANK)
	tank_label.text = str(tanks) + " / " + str(_requested_tanks())
	# Ratio total across all garages
	var total_ratio := 0.0
	for b in Global.BM.buildings():
		if b is Garage and b.player_owner == building.player_owner:
			total_ratio += b.zoomba_tank_ratio
	var total_pct := int(total_ratio * 100)
	ratio_total_label.text = "Total requested over all Garages: " + str(total_pct) + "%"
	if total_pct > 100:
		ratio_total_label.add_theme_color_override("font_color", Color.RED)
	else:
		ratio_total_label.add_theme_color_override("font_color", Color.WHITE)
	# "Next Tank" tracks the production energy accumulated toward the tank cost —
	# the cooldown timer is held at 0 while a conversion job is pending.
	if building._production_cost > 0.0:
		spawn_bar.value = clampf(building._production_energy / building._production_cost * 100.0, 0.0, 100.0)
	else:
		spawn_bar.value = 0.0
	empower_indicator.visible = building.is_empowered
	if _should_render_controls_from_vars():
		_update_controls_from_vars()

# Set the config controls (ratio slider, enemy targets, patrol stance) from the
# building's settings. Runs for other players' terminals (spying) and the RTS
# tooltip; owned terminals are client-set only.
func _update_controls_from_vars() -> void:
	if not building:
		return
	var pct := int(building.zoomba_tank_ratio * 100)
	ratio_slider.set_value_no_signal(pct)
	ratio_label.text = str(100 - pct) + "% / " + str(pct) + "%"
	for pnum in _enemy_buttons:
		var btn: Button = _enemy_buttons[pnum]
		btn.set_pressed_no_signal(pnum in building._enemy_targets)
	patrol_hold_btn.set_pressed_no_signal(building.patrol_stance == JobManager.Stance.HOLD)
	patrol_wide_btn.set_pressed_no_signal(building.patrol_stance == JobManager.Stance.WIDE)

func refresh_controls_from_building() -> void:
	_update_controls_from_vars()
