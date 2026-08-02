extends Building

class_name Generator

const HUD_SCENE: PackedScene = preload("res://scenes/ui/GeneratorHUD.tscn")

# --- State ---

var generation: float = 0.0
var generation_extra: float = 0.0

# --- Lifecycle ---

func _get_hud_scene() -> PackedScene:
	return HUD_SCENE

func initialise(pnum: int, tile: TileElement) -> void:
	super.initialise(pnum, tile)
	type = BuildingManager.Type.GEN
	_health_bar.global_position.y = Building.HEALTH_BAR_HEIGHT
	max_health = Config.BUILDING_MAX_HP[type]
	health = max_health
	add_to_group("generator")
	add_to_group("generator_player" + str(pnum))
	_build_aoe_tiles()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_setup_hud()

# --- Energy ---

func update_energy() -> void:
	var total := 0.0
	for t in _aoe_tiles:
		if t.gen_count > 0:
			total += 1.0 / t.gen_count
	generation = total
	var total_extra := 0.0
	for t in _aoe_tiles_extra:
		if t.gen_count > 0:
			total_extra += 1.0 / t.gen_count
	generation_extra = total_extra

func get_energy() -> float:
	if state != State.CONSTRUCTED:
		return 0.0
	if is_empowered:
		return generation + generation_extra
	return generation

func _empower_changed(_val: bool) -> void:
	Global.TM.recompute_aoe()

# --- Mouse hover ---

func _on_mouse_entered() -> void:
	if state != State.CONSTRUCTED:
		return
	for t in _hover_tiles():
		var color : Color
		match t.gen_count:
			1: color = Color.GREEN
			2: color = Color.YELLOW
			3: color = Color.ORANGE_RED
			_: color = Color.RED
		t.request_emission(TileElement.EmissionEffect.GENERATOR_CATCHMENT, color, 0.5)

func _on_mouse_exited() -> void:
	for t in _hover_tiles():
		t.release_emission(TileElement.EmissionEffect.GENERATOR_CATCHMENT)

func _hover_tiles() -> Array[TileElement]:
	var tiles: Array[TileElement] = _aoe_tiles.duplicate()
	if is_empowered:
		tiles.append_array(_aoe_tiles_extra)
	return tiles
