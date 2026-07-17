extends Building

class_name Generator

const BASE_GENERATION := 10.0
var generation := 0.0

func initialise(pnum : int, tile : TileElement):
	super.initialise(pnum, tile)
	type = BuildingManager.Type.GEN
	_health_bar.global_position.y = 22.0
	max_health = Config.BUILDING_MAX_HP[type]
	health = max_health
	add_to_group("generator")
	add_to_group("generator_player"+str(pnum))

func get_energy() -> float:
	if state != State.CONSTRUCTED:
		return 0.0
	return BASE_GENERATION + generation
