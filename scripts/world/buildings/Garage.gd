extends Building

class_name Garage

var zoomba_tank_ratio: float = 0.5  # 0.0 = all zoombas, 1.0 = all tanks

func initialise(pnum: int, tile: TileElement) -> void:
	super.initialise(pnum, tile)
	_setup_production(UnitManager.Type.TANK)
	add_to_group("garage")
	add_to_group("garage_player" + str(pnum))

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
		var um = get_node_or_null("/root/World/UnitManager")
		if not um:
			return
		var jm = get_node_or_null("/root/World/JobManager")
		if not jm:
			return
		var total_zoombas : int = um.unit_count(player_owner, UnitManager.Type.ZOOMBA)
		var claimed : int = jm.count_jobs(player_owner, JobManager.Type.CONSUME_ZOOMBA)
		var current_tanks : int = um.unit_count(player_owner, UnitManager.Type.TANK)
		# Always keep at least 1 zoomba free
		if total_zoombas - claimed < 2:
			return
		# Tank cap based on ratio, minus already claimed zoombas
		var target_tanks : int = roundi(total_zoombas * zoomba_tank_ratio)
		if current_tanks + claimed >= target_tanks:
			return
		# Create CONSUME_ZOOMBA job
		jm.add_job(player_owner, JobManager.Type.CONSUME_ZOOMBA, location)

func _produce_unit() -> void:
	# Override to do nothing — Garage uses CONSUME_ZOOMBA job instead
	pass
