extends TerminalHUD

class_name VatHUD

var building: Vat

@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn
@onready var energy_bar: ProgressBar = $Window/VBox/EnergyBar
@onready var energy_label: Label = $Window/VBox/EnergyRow/EnergyLabel
@onready var capacity_label: Label = $Window/VBox/CapacityRow/CapacityLabel
@onready var adjacent_label: Label = $Window/VBox/AdjacentRow/AdjacentLabel
@onready var hp_bar: ProgressBar = $Window/VBox/HPBar
@onready var hp_label: Label = $Window/VBox/HPRow/HPLabel
@onready var empower_indicator: Label = $Window/VBox/EmpowerRow/EmpowerIndicator

func _ready() -> void:
	if not empower_btn:
		return
	# Empower visual only for Vat until gameplay effect is wired
	empower_btn.pressed.connect(_on_empower_pressed)

func _on_empower_pressed() -> void:
	if building:
		Global.send_command_me("empower", [building.id])

func _process(_delta: float) -> void:
	if not building or not energy_bar:
		return
	var em = Global.EM
	if em:
		var e = em.get_player_energy(building.player_owner)
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
	empower_indicator.visible = building.is_empowered
