extends TerminalHUD

class_name GeneratorHUD

# --- References ---

var building: Generator

# --- Nodes ---

@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn
@onready var power_label: Label = $Window/VBox/PowerRow/PowerLabel
@onready var tiles_label: Label = $Window/VBox/TilesRow/TilesLabel
@onready var per_tile_label: Label = $Window/VBox/PerTileRow/PerTileLabel
@onready var empower_indicator: Label = $Window/VBox/EmpowerRow/EmpowerIndicator
@onready var catchment_bars: Array[ProgressBar] = [
	$Window/VBox/CatchmentRow/CatchmentGrid/Bar1e,
	$Window/VBox/CatchmentRow/CatchmentGrid/BarHalf,
	$Window/VBox/CatchmentRow/CatchmentGrid/BarThird,
	$Window/VBox/CatchmentRow/CatchmentGrid/BarQuarter,
]

func _ready() -> void:
	if not empower_btn:
		return
	empower_btn.pressed.connect(_on_empower_pressed)
	_tint_catchment_bars()

func _tint_catchment_bars() -> void:
	var colors: Array[Color] = [
		Config.CATCHMENT_SINGLE_TILE,
		Config.CATCHMENT_TWO_TILES,
		Config.CATCHMENT_THREE_TILES,
		Config.CATCHMENT_OVERLAPPED,
	]
	for i in catchment_bars.size():
		_tint_bar(catchment_bars[i], colors[i])

func _tint_bar(bar: ProgressBar, color: Color) -> void:
	# Duplicate the theme fill so the shared theme stylebox is never mutated.
	var sb := bar.get_theme_stylebox("fill")
	if sb is StyleBoxFlat:
		sb = (sb as StyleBoxFlat).duplicate()
		sb.bg_color = color
		sb.shadow_color = Color(color.r, color.g, color.b, 0.4)
		bar.add_theme_stylebox_override("fill", sb)

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
	_set_empower_indicator(empower_indicator, building)
	var counts: Dictionary = building.catchment_bucket_counts()
	var bucket_values: Array[int] = [counts[1], counts[2], counts[3], counts[4]]
	for i in catchment_bars.size():
		catchment_bars[i].max_value = float(maxi(total_tiles, 1))
		catchment_bars[i].value = float(bucket_values[i])
