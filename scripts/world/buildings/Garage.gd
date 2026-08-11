extends Building

class_name Garage

# --- Constants ---

const HUD_SCENE: PackedScene = preload("res://scenes/ui/GarageHUD.tscn")

# --- State ---

var zoomba_tank_ratio: float = 0.5  # 0.0 = all zoombas, 1.0 = all tanks
var cached_tank_count: int = 0
var patrol_stance: JobManager.Stance = JobManager.Stance.WIDE
var _enemy_targets: Array[int] = [1, 2, 3, 4]

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
	_enemy_targets = _clean_enemy_targets(targets)
	_update_orders()

func _copy_settings_from(sibling: Building) -> void:
	var g := sibling as Garage
	if not g:
		return
	if multiplayer.is_server():
		Global.send_command(player_owner, "set_garage_ratio", [id, g.zoomba_tank_ratio])
		Global.send_command(player_owner, "set_enemy_targets", [id, g._enemy_targets])
		Global.send_command(player_owner, "set_patrol_stance", [id, g.patrol_stance])
	else:
		zoomba_tank_ratio = g.zoomba_tank_ratio
		set_enemy_targets(g._enemy_targets)
		set_patrol_stance(g.patrol_stance)

func set_patrol_stance(ps: JobManager.Stance) -> void:
	patrol_stance = ps
	_update_orders()

func _update_orders() -> void:
	_enemy_targets = _clean_enemy_targets(_enemy_targets)
	orders["enemy"] = _enemy_targets

func _process(delta: float) -> void:
	super._process(delta)

func _update_tank_count() -> void:
	cached_tank_count = Global.UM.unit_count(player_owner, UnitManager.Type.TANK)

func check_work() -> void:
	super.check_work()
	if not multiplayer.is_server():
		return
	if state != State.CONSTRUCTED:
		return
	# Tank count only changes at spawn cadence — refresh on the 1 s tick, not per frame.
	_update_tank_count()
	if not _production_enabled:
		return
	# When energy accumulated and timer ready, create CONSUME_ZOOMBA job
	if _production_energy >= _production_cost and _production_timer <= 0:
		# Don't start a new cycle while the previous CONSUME_ZOOMBA job is still
		# pending (a zoomba hasn't arrived yet) — otherwise the garage spends
		# energy on a conversion that hasn't happened.
		if Global.JM.has_job(player_owner, JobManager.Type.CONSUME_ZOOMBA, location):
			return
		var total_zoombas: int = Global.UM.unit_count(player_owner, UnitManager.Type.ZOOMBA)
		var claimed: int = Global.JM.count_jobs(player_owner, JobManager.Type.CONSUME_ZOOMBA)
		# Always keep at least 1 zoomba free
		if total_zoombas - claimed < 2:
			_production_energy = 0.0
			_production_timer = 0.0
			return
		# Tank cap based on ratio, minus already claimed zoombas
		var target_tanks: int = roundi(total_zoombas * zoomba_tank_ratio)
		if cached_tank_count + claimed >= target_tanks:
			_production_energy = 0.0
			_production_timer = 0.0
			return
		# Create CONSUME_ZOOMBA job
		Global.JM.add_job(player_owner, JobManager.Type.CONSUME_ZOOMBA, location)
		# Consume the production budget/cooldown for this conversion so the
		# building issues a fresh job on its next production cycle.
		_production_energy = 0.0
		_production_timer = Config.PRODUCTION_COOLDOWNS.get(type, 10.0)

# Only spend production energy when the previous CONSUME_ZOOMBA job has finished
# (a tank was actually produced) and the building isn't hemmed in.
func _can_produce() -> bool:
	if not super._can_produce():
		return false
	if Global.JM.has_job(player_owner, JobManager.Type.CONSUME_ZOOMBA, location):
		return false
	var total_zoombas: int = Global.UM.unit_count(player_owner, UnitManager.Type.ZOOMBA)
	var claimed: int = Global.JM.count_jobs(player_owner, JobManager.Type.CONSUME_ZOOMBA)
	if total_zoombas - claimed < 2:
		return false
	var target_tanks: int = roundi(total_zoombas * zoomba_tank_ratio)
	if cached_tank_count + claimed >= target_tanks:
		return false
	return true

func _produce_unit() -> void:
	# Override to do nothing — Garage uses CONSUME_ZOOMBA job instead
	pass
