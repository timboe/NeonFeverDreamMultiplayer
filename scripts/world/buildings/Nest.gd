extends Building

class_name Nest

const HUD_SCENE: PackedScene = preload("res://scenes/ui/NestHUD.tscn")

var _virus_tank_building_ratio: float = 0.5
var _enemy_targets: Array[int] = [1, 2, 3, 4]
var _building_targets: Array[BuildingManager.Type] = Config.ALL_BUILDING_TARGETS

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
	orders["order"] = JobManager.Orders.ATTACK
	orders["source"] = self
	_update_orders()
	
func _update_orders() -> void:
	_enemy_targets = _clean_enemy_targets(_enemy_targets)
	orders["enemy"] = _enemy_targets
	orders["target"] = _building_targets
	orders["tank_ratio"] = _virus_tank_building_ratio

func set_enemy_targets(et: Array[int]) -> void:
	_enemy_targets = _clean_enemy_targets(et)
	_update_orders()

func set_building_targets(bt: Array[BuildingManager.Type]) -> void:
	_building_targets = bt
	_update_orders()

func set_virus_tank_building_ratio(ratio: float) -> void:
	_virus_tank_building_ratio = clampf(ratio, 0.0, 1.0)
	_update_orders()
