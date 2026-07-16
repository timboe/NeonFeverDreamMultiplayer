extends Building

class_name Generator

const BASE_GENERATION := 10.0
var generation := 0.0

func initialise(pnum : int, tile : TileElement, t : BuildingManager.Type):
	initialise_base(pnum, tile, t)
	add_to_group("generator")
	add_to_group("generator_player"+str(pnum))

func get_tick_energy() -> float:
	if state != State.CONSTRUCTED:
		return 0.0
	return BASE_GENERATION + generation
