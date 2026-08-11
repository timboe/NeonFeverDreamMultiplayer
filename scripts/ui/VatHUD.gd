extends TerminalHUD

class_name VatHUD

# --- References ---

var building: Vat

# --- Nodes ---

@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn
@onready var energy_bar: ProgressBar = $Window/VBox/EnergyBar
@onready var energy_label: Label = $Window/VBox/EnergyRow/EnergyLabel
@onready var capacity_label: Label = $Window/VBox/CapacityRow/CapacityLabel
@onready var adjacent_label: Label = $Window/VBox/AdjacentRow/AdjacentLabel
@onready var hp_bar: ProgressBar = $Window/VBox/HPBar
@onready var hp_label: Label = $Window/VBox/HPRow/HPLabel
@onready var empower_indicator: Label = $Window/VBox/EmpowerRow/EmpowerIndicator

# --- Constants ---

# Terminal HUDs refresh at 4 Hz — energy and pool state change on tick cadence.
const REFRESH_INTERVAL := 0.25

# --- State ---

var _refresh_timer := 0.0

func _ready() -> void:
	if not empower_btn:
		return
	empower_btn.pressed.connect(_on_empower_pressed)

func _on_empower_pressed() -> void:
	_empower_building(building)

func _process(delta: float) -> void:
	if not building or not energy_bar:
		return
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	var e = Global.EM.get_player_energy(building.player_owner)
	energy_bar.max_value = e.capacity
	energy_bar.value = e.current
	energy_label.text = str(int(e.current)) + " / " + str(int(e.capacity))
	var cap := building.get_capacity()
	capacity_label.text = str(int(cap)) + "e"
	var adj_count := int(building.capacity_mod_vats / (Vat.CAPACITY * 0.1))
	adjacent_label.text = str(adj_count) + " (+" + str(adj_count * 10) + "%)"
	hp_bar.max_value = building.max_health
	hp_bar.value = building.health
	hp_label.text = str(int(building.health)) + " / " + str(int(building.max_health))
	_set_empower_indicator(empower_indicator, building)
