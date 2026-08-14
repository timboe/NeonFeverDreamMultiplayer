extends Building

class_name Garage

# --- Constants ---

const HUD_SCENE: PackedScene = preload("res://scenes/ui/GarageHUD.tscn")

# --- State ---

var zoomba_tank_ratio: float = 0.5  # 0.0 = all zoombas, 1.0 = all tanks
var cached_tank_count: int = 0
var patrol_stance: JobManager.Stance = JobManager.Stance.WIDE
var _enemy_targets: Array[int] = [1, 2, 3, 4]
# 1 Hz caches refreshed in check_work — _can_produce runs every frame and used
# to pay group lookups + O(jobs)/O(buildings) scans per frame for values that
# only change on spawn cadence.
var _mcp: Node
var _claimed_consume_jobs := 0
var _pending_job_here := false
var _tank_target_cached := 0

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

# Pooled tank target across all of the player's garages, derived from the
# stable MCP zoomba cap (not the live zoomba count, which the MCP refills as
# conversions happen). Summed ratios may exceed 100% — the cap − 1 clamp is the
# "never convert the last zoomba" rule, applied to the pool.
func player_tank_target() -> int:
	# Cache the MCP ref — group lookup per call was the hot spot.
	if _mcp == null or not is_instance_valid(_mcp):
		_mcp = get_tree().get_first_node_in_group("mcp_player" + str(player_owner))
	if not _mcp or not _mcp.has_method("zoomba_cap"):
		return 0
	var cap := int(_mcp.zoomba_cap())
	var total := 0
	for b in Global.BM.buildings():
		if b is Garage and b.player_owner == player_owner:
			total += roundi(cap * b.zoomba_tank_ratio)
	return clampi(total, 0, maxi(cap - 1, 0))

func check_work() -> void:
	super.check_work()
	if not multiplayer.is_server():
		return
	if state != State.CONSTRUCTED:
		return
	# Tank count only changes at spawn cadence — refresh on the 1 s tick, not per frame.
	_update_tank_count()
	# Refresh the per-frame _can_produce caches (job scans + tank target are
	# O(jobs)/O(buildings) — far too heavy to run every frame).
	_pending_job_here = Global.JM.has_job(player_owner, JobManager.Type.CONSUME_ZOOMBA, location)
	_claimed_consume_jobs = Global.JM.count_jobs(player_owner, JobManager.Type.CONSUME_ZOOMBA)
	_tank_target_cached = player_tank_target()
	if not _production_enabled:
		return
	# When energy accumulated and timer ready, create CONSUME_ZOOMBA job
	if _production_energy >= _production_cost and _production_timer <= 0:
		# Don't start a new cycle while the previous CONSUME_ZOOMBA job is still
		# pending (a zoomba hasn't arrived yet) — otherwise the garage spends
		# energy on a conversion that hasn't happened.
		if _pending_job_here:
			return
		var total_zoombas: int = Global.UM.unit_count(player_owner, UnitManager.Type.ZOOMBA)
		# Always keep at least 1 zoomba free
		if total_zoombas - _claimed_consume_jobs < 2:
			_production_energy = 0.0
			_production_timer = 0.0
			return
		# Tank cap from the pooled ratio across all garages, minus already
		# claimed zoombas
		if cached_tank_count + _claimed_consume_jobs >= _tank_target_cached:
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
# (a tank was actually produced) and the building isn't hemmed in. Reads the
# 1 Hz caches refreshed by check_work — worst case a tick of staleness, which
# only delays energy accumulation (job creation itself is gated in check_work
# on fresh data).
func _can_produce() -> bool:
	if not super._can_produce():
		return false
	if _pending_job_here:
		return false
	var total_zoombas: int = Global.UM.unit_count(player_owner, UnitManager.Type.ZOOMBA)
	if total_zoombas - _claimed_consume_jobs < 2:
		return false
	if cached_tank_count + _claimed_consume_jobs >= _tank_target_cached:
		return false
	return true

func _produce_unit() -> void:
	# Override to do nothing — Garage uses CONSUME_ZOOMBA job instead
	pass
