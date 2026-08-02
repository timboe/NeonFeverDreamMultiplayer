extends Building

class_name Garage

const HUD_SCENE: PackedScene = preload("res://scenes/ui/GarageHUD.tscn")

var zoomba_tank_ratio: float = 0.5  # 0.0 = all zoombas, 1.0 = all tanks
var cached_tank_count: int = 0
var patrol_stance: JobManager.Stance = JobManager.Stance.HOLD
var _enemy_targets: Array[int] = []

func _get_hud_scene() -> PackedScene:
	return HUD_SCENE

func initialise(pnum: int, tile: TileElement) -> void:
	super.initialise(pnum, tile)
	type = BuildingManager.Type.GARAGE
	max_health = Config.BUILDING_MAX_HP[type]
	health = max_health
	_setup_production(UnitManager.Type.TANK)
	add_to_group("garage")
	add_to_group("garage_player" + str(pnum))
	_build_aoe_tiles()
	_setup_hud()
	orders["order"] = JobManager.Orders.PATROL
	orders["stance"] = patrol_stance
	orders["source"] = self
	_update_orders()

func set_enemy_targets(targets: Array[int]) -> void:
	_enemy_targets = targets
	_update_orders()

func _update_orders() -> void:
	orders["enemy"] = _enemy_targets

func _process(delta: float) -> void:
	super._process(delta)
	if multiplayer.is_server() and state == State.CONSTRUCTED:
		_update_tank_count()

func _update_tank_count() -> void:
	var um = Global.UM
	if um:
		cached_tank_count = um.unit_count(player_owner, UnitManager.Type.TANK)

func check_work() -> void:
	super.check_work()
	if not multiplayer.is_server():
		return
	if state != State.CONSTRUCTED:
		return
	if not _production_enabled:
		return
	# When energy accumulated and timer ready, create CONSUME_ZOOMBA job
	if _production_energy >= _production_cost and _production_timer <= 0:
		var um = Global.UM
		if not um:
			return
		var jm = Global.JM
		if not jm:
			return
		var total_zoombas : int = um.unit_count(player_owner, UnitManager.Type.ZOOMBA)
		var claimed : int = jm.count_jobs(player_owner, JobManager.Type.CONSUME_ZOOMBA)
		# Always keep at least 1 zoomba free
		if total_zoombas - claimed < 2:
			return
		# Tank cap based on ratio, minus already claimed zoombas
		var target_tanks : int = roundi(total_zoombas * zoomba_tank_ratio)
		if cached_tank_count + claimed >= target_tanks:
			return
		# Create CONSUME_ZOOMBA job
		jm.add_job(player_owner, JobManager.Type.CONSUME_ZOOMBA, location)
		# Consume the production budget/cooldown for this conversion so the
		# building issues a fresh job on its next production cycle.
		_production_energy = 0.0
		_production_timer = Config.PRODUCTION_COOLDOWNS.get(type, 10.0)

func _produce_unit() -> void:
	# Override to do nothing — Garage uses CONSUME_ZOOMBA job instead
	pass
