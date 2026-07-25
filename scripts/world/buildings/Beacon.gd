extends Building

class_name Beacon

var patrol_strike_ratio: float = 0.5

func initialise(pnum: int, tile: TileElement) -> void:
	super.initialise(pnum, tile)
	_setup_production(UnitManager.Type.AERIAL)
	add_to_group("beacon")
	add_to_group("beacon_player" + str(pnum))

func check_work() -> void:
	super.check_work()

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
