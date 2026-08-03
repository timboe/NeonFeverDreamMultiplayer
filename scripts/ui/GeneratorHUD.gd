extends TerminalHUD

class_name GeneratorHUD

var building: Generator

@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn
@onready var power_label: Label = $Window/VBox/PowerRow/PowerLabel
@onready var tiles_label: Label = $Window/VBox/TilesRow/TilesLabel
@onready var per_tile_label: Label = $Window/VBox/PerTileRow/PerTileLabel
@onready var empower_indicator: Label = $Window/VBox/EmpowerRow/EmpowerIndicator

func _ready() -> void:
	if not empower_btn:
		return
	empower_btn.pressed.connect(_on_empower_pressed)

func _on_empower_pressed() -> void:
	_empower_building(building)

func _process(_delta: float) -> void:
	if not building or not power_label:
		return
	# Empowered Generators also draw from the extra ring of tiles.
	var power: float = building.get_energy()
	var total_tiles: int = building._aoe_tiles.size() + (building._aoe_tiles_extra.size() if building.is_empowered else 0)
	power_label.text = str(int(power)) + " e/s"
	tiles_label.text = str(total_tiles)
	var avg := 0.0
	if total_tiles > 0:
		avg = power / total_tiles
	per_tile_label.text = str(snappedf(avg, 0.1))
	empower_indicator.visible = building.is_empowered
