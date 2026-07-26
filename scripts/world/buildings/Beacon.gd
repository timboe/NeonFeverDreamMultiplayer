extends Building

class_name Beacon

const HUD_SCENE: PackedScene = preload("res://scenes/ui/BeaconHUD.tscn")

enum StrikePriority {NEAREST, LOWEST_HP}
enum PatrolStance {HOLD, WIDE}

var patrol_strike_ratio: float = 0.5
var strike_priority: StrikePriority = StrikePriority.NEAREST
var patrol_stance: PatrolStance = PatrolStance.HOLD
var enemy_targets: Array[int] = []
var strike_target_types: Array[BuildingManager.Type] = []

func _get_hud_scene() -> PackedScene:
	return HUD_SCENE

func initialise(pnum: int, tile: TileElement) -> void:
	super.initialise(pnum, tile)
	type = BuildingManager.Type.BEACON
	max_health = Config.BUILDING_MAX_HP[type]
	health = max_health
	_setup_production(UnitManager.Type.AERIAL)
	add_to_group("beacon")
	add_to_group("beacon_player" + str(pnum))
	_setup_hud()

func _produce_unit() -> void:
	if not multiplayer.is_server():
		return
	var um = get_node_or_null("/root/World/UnitManager")
	if not um:
		return
	var uid: int = um.next_unit_id()
	um.rpc("rpc_spawn_unit", uid, UnitManager.Type.AERIAL, self.id)
	_production_energy = 0.0
	_production_timer = Config.PRODUCTION_COOLDOWNS.get(type, 4.0)
