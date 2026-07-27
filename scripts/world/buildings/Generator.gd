extends Building

class_name Generator

const HUD_SCENE: PackedScene = preload("res://scenes/ui/GeneratorHUD.tscn")

# --- State ---

var generation: float = 0.0

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
	var total := 0
	for t in _aoe_tiles:
		total += t.gen_count
	generation = total

func get_energy() -> float:
	if state != State.CONSTRUCTED:
		return 0.0
	return generation

# --- Mouse hover ---

func _on_mouse_entered() -> void:
	if state != State.CONSTRUCTED:
		return
	for t in _aoe_tiles:
		var color : Color
		match t.gen_count:
			1: color = Color.GREEN
			2: color = Color.YELLOW
			3: color = Color.ORANGE_RED
			_: color = Color.RED
		t.request_emission(TileElement.EmissionEffect.GENERATOR_CATCHMENT, color, 0.5)

func _on_mouse_exited() -> void:
	for t in _aoe_tiles:
		t.release_emission(TileElement.EmissionEffect.GENERATOR_CATCHMENT)
