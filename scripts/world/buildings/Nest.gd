extends Building

class_name Nest

const HUD_SCENE: PackedScene = preload("res://scenes/ui/NestHUD.tscn")

enum VirusPriority {NEAREST, LOWEST_HP}

var virus_tank_building_ratio: float = 0.5
var virus_priority: VirusPriority = VirusPriority.NEAREST
var enemy_targets: Array[int] = []
var building_targets: Array[BuildingManager.Type] = []

func _get_hud_scene() -> PackedScene:
	return HUD_SCENE

func initialise(pnum: int, tile: TileElement) -> void:
	super.initialise(pnum, tile)
	type = BuildingManager.Type.NEST
	max_health = Config.BUILDING_MAX_HP[type]
	health = max_health
	_setup_production(UnitManager.Type.VIRUS)
	add_to_group("nest")
	add_to_group("nest_player" + str(pnum))
	_setup_hud()
