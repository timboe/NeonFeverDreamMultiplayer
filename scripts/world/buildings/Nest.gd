extends Building

class_name Nest

func initialise(pnum: int, tile: TileElement) -> void:
	super.initialise(pnum, tile)
	_setup_production(UnitManager.Type.VIRUS)
	add_to_group("nest")
	add_to_group("nest_player" + str(pnum))

func check_work() -> void:
	super.check_work()
