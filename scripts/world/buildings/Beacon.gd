extends Building

class_name Beacon

const HUD_SCENE: PackedScene = preload("res://scenes/ui/BeaconHUD.tscn")

var patrol_strike_ratio: float = 0.5
var _strike_priority: JobManager.Priority = JobManager.Priority.NEAREST
var _patrol_stance: JobManager.Stance = JobManager.Stance.HOLD
var _enemy_targets: Array[int] = []
var _building_targets: Array[BuildingManager.Type] = []

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
	_build_aoe_tiles()
	_setup_hud()
	orders["patrol"] = {}
	orders["strike"] = {}
	orders["patrol"]["order"] = JobManager.Orders.PATROL
	orders["patrol"]["source"] = self
	orders["strike"]["order"] = JobManager.Orders.ATTACK
	orders["strike"]["source"] = self
	_update_orders()
	
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

func _update_orders() -> void:
	orders["patrol"]["stance"] = _patrol_stance
	#
	orders["strike"]["enemy"] = _enemy_targets
	orders["strike"]["target"] = _building_targets
	orders["strike"]["priority"] = _strike_priority

func set_strike_priority(sp: JobManager.Priority) -> void:
	_strike_priority = sp
	_update_orders()

func set_enemy_targets(et: Array[int]) -> void:
	_enemy_targets = et
	_update_orders()

func set_patrol_stance(ps: JobManager.Stance) -> void:
	_patrol_stance = ps
	_update_orders()

func set_building_targets(bt: Array[BuildingManager.Type]) -> void:
	_building_targets = bt
	_update_orders()
