extends Building

class_name Generator

# --- Constants ---

const BASE_GENERATION: float = 10.0

# --- State ---

var generation: float = 0.0

# --- Lifecycle ---

func initialise(pnum: int, tile: TileElement) -> void:
	super.initialise(pnum, tile)
	type = BuildingManager.Type.GEN
	_health_bar.global_position.y = Building.HEALTH_BAR_HEIGHT
	max_health = Config.BUILDING_MAX_HP[type]
	health = max_health
	add_to_group("generator")
	add_to_group("generator_player" + str(pnum))

# --- Energy ---

func get_energy() -> float:
	if state != State.CONSTRUCTED:
		return 0.0
	return BASE_GENERATION + generation
