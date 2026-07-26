extends Control

class_name GeneratorHUD

var building: Generator

@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn
@onready var power_label: Label = $Window/VBox/PowerRow/PowerLabel
@onready var tiles_label: Label = $Window/VBox/TilesRow/TilesLabel
@onready var per_tile_label: Label = $Window/VBox/PerTileRow/PerTileLabel
@onready var empower_indicator: Label = $Window/VBox/EmpowerRow/EmpowerIndicator

var _cursor: Cursor3D

func _ready() -> void:
	if not empower_btn:
		return
	empower_btn.pressed.connect(_on_empower_pressed)

func _on_empower_pressed() -> void:
	if building:
		Global.send_command_me("empower", [building.id])

func setup_cursor_3d(screen: MeshInstance3D) -> void:
	_cursor = Cursor3D.new(screen, Config.TERMINAL_SCREEN_SIZE)

func _process(_delta: float) -> void:
	if not building or not power_label:
		return
	power_label.text = str(int(building.generation)) + " e/s"
	tiles_label.text = str(building._aoe_tiles.size())
	var avg := 0.0
	if building._aoe_tiles.size() > 0:
		avg = building.generation / building._aoe_tiles.size()
	per_tile_label.text = str(snappedf(avg, 0.1))
	empower_indicator.visible = building.is_empowered

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
