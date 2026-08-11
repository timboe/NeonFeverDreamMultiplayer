extends Unit

class_name Virus

# Viewer-relative cloak opacity: the owner keeps a semi-transparent ghost so
# their own viruses stay trackable, everyone else sees them fully invisible.
const OWNER_CLOAK_ALPHA := 0.05

var cloaked: bool = false

# Re-cloak cooldown (server). The virus spawns uncloaked and re-cloaks once the
# cooldown elapses; being uncloaked again (enemy detection) restarts it. Never
# re-cloaks while attached (WORKING) so PATROLs can kill an attacking virus.
var _recloak_timer: float = 0.0

# Ambient health decay — self-depletes at 1.25 HP/s (~120s from full health).
# Paused while WORKING (attached/channelling) so a limpet can finish its job.
var _health_decay_rate: float = 1.25
var _decay_timer: float = 0.0
const DECAY_INTERVAL: float = 0.1

# Idle time spent jobless (server) — prevents offense-job thrash.
var _idle_time := 0.0

# Limpet state (server only). One virus attaches to one target; multiple viruses
# may attach to the same target.
var _limpet_target: Object = null
var _limpet_is_building: bool = false
var _limpet_delay: float = 0.0
var _health_at_attach: float = 0.0
var _infection_duration: float = 0.0
var _infection_timer: float = 0.0
var _infection_complete: bool = false

var _last_cloak_k: float = -1.0
var _cloak_applied: bool = false

func _process(delta: float) -> void:
	super._process(delta)
	if multiplayer.is_server():
		if state == State.WORKING and not job.is_empty() and job["type"] == JobManager.Type.ATTACK:
			_tick_limpet(delta)
		elif health > 0:
			_decay_timer += delta
			while _decay_timer >= DECAY_INTERVAL:
				_decay_timer -= DECAY_INTERVAL
				health -= _health_decay_rate * DECAY_INTERVAL
				if health <= 0:
					health = 0
					Global.UM.rpc("rpc_remove_unit", id)
					return
		# Re-cloak after the cooldown if uncloaked and not attached.
		if not cloaked and state != State.WORKING:
			_recloak_timer -= delta
			if _recloak_timer <= 0.0:
				recloak()
		_idle_time = (_idle_time + delta) if (state == State.IDLE and job.is_empty()) else 0.0
	_update_cloak_visual()

func initialise(b: Building) -> void:
	super.initialise(b)
	type = UnitManager.Type.VIRUS
	_health_bar.position.y = 3.2
	health = Config.UNIT_MAX_HP.get(type, 100.0)
	add_to_group("virus")
	add_to_group("virus_player" + str(player_owner))
	var model = _model()
	if model and model.has_method("set_player_color"):
		model.set_player_color(Config.player_accent(player_owner))
	# Spawn uncloaked; cloak after the cooldown elapses.
	cloaked = false
	_recloak_timer = Config.VIRUS_RECLOAK_COOLDOWN
	_update_cloak_visual()

func _model() -> Node:
	return get_node_or_null("Body")

func _update_cloak_visual() -> void:
	var is_owner: bool = player_owner == Global.my_player_number
	var k := 1.0
	if cloaked:
		k = OWNER_CLOAK_ALPHA if is_owner else 0.0
	if _cloak_applied and is_equal_approx(_last_cloak_k, k):
		return
	_cloak_applied = true
	_last_cloak_k = k
	if _health_bar:
		_health_bar.visible = k > 0.0
	var model = _model()
	if model and model.has_method("set_cloak_alpha"):
		model.set_cloak_alpha(k)

func uncloak() -> void:
	cloaked = false
	_recloak_timer = Config.VIRUS_RECLOAK_COOLDOWN
	_update_cloak_visual()

func recloak() -> void:
	cloaked = true
	_update_cloak_visual()

# --- Offence: viruses generate their own personal ATTACK job when idle ---

func try_generate_offense_job() -> bool:
	if not multiplayer.is_server():
		return false
	if _idle_time < 1.0:
		return false
	var enemies: Array = []
	for p in orders.get("enemy", []):
		if p != player_owner:
			enemies.append(int(p))
	if enemies.is_empty():
		return false
	# Roll the Nest's TANK/BUILDING ratio; fall back to a building if no tanks.
	var target: Object = null
	var tank_ratio: float = orders.get("tank_ratio", 0.5)
	if randf() < tank_ratio:
		target = _pick_enemy_tank(enemies)
	if target == null:
		target = Global.CM.choose_building_target(enemies, orders.get("target", []))
	if target == null:
		return false
	_idle_time = 0.0 # If the job is immediately abandoned, wait before re-targeting
	Global.JM.add_job(player_owner, JobManager.Type.ATTACK, target, self, true) # personal, auto-assigned to self
	return true

func _pick_enemy_tank(enemies: Array) -> Unit:
	var candidates: Array = []
	for u in Global.UM.units():
		if u.type != UnitManager.Type.TANK:
			continue
		if u.player_owner not in enemies:
			continue
		if u.health <= 0:
			continue
		candidates.append(u)
	if candidates.is_empty():
		return null
	return candidates[Global.rand.randi() % candidates.size()]

# --- Limpet (WORKING) state ---

func start_attack() -> void:
	if not multiplayer.is_server():
		return
	uncloak() # auto-uncloak when beginning an attack
	_limpet_target = job["target"]
	_limpet_is_building = _limpet_target is Building
	# TODO per DESIGN: enforce the infection cap — one active building infection
	# per enemy player. Currently multiple VIRUS may channel the same building
	# (personal jobs skip dedup) and the cap is unenforced.
	_health_at_attach = health
	_limpet_delay = Config.VIRUS_ATTACH_DELAY
	_infection_duration = 0.0
	_infection_timer = 0.0
	_infection_complete = false

func cancel_attack() -> void:
	_limpet_target = null
	_limpet_is_building = false
	_limpet_delay = 0.0
	_infection_duration = 0.0
	_infection_timer = 0.0
	_infection_complete = false

func _tick_limpet(delta: float) -> void:
	var target = _limpet_target
	if target == null or not is_instance_valid(target) or target.health <= 0:
		# Attached target destroyed. TANK: the virus dies with it. Building: the
		# virus survives an interrupted channel and re-targets via idle.
		if _limpet_is_building:
			job_finished()
		else:
			Global.UM.rpc("rpc_remove_unit", id)
		return
	if _limpet_delay > 0.0:
		_limpet_delay -= delta
		return
	if _limpet_is_building:
		_tick_building_infection(delta)
	else:
		# Limpet tracks the tank — stay attached (on it) as it moves.
		var tank: Unit = target as Unit
		if tank:
			location = tank.location
			global_position = tank.global_position
		var amount: float = Config.VIRUS_TANK_DRAIN_DPS * delta
		target.apply_damage(amount)
		Global.SM.record_damage_done(player_owner, amount)

func _tick_building_infection(delta: float) -> void:
	if _infection_duration <= 0.0:
		# Channel duration is based on health at attach: base 15s at full 150 HP,
		# prorated linearly (e.g. 75 HP = 7.5s).
		_infection_duration = Config.VIRUS_INFECTION_BASE_DURATION * (_health_at_attach / Config.UNIT_MAX_HP.get(UnitManager.Type.VIRUS, 150.0))
	_infection_timer += delta
	if _infection_timer >= _infection_duration and not _infection_complete:
		_infection_complete = true
		_apply_building_effect()
		Global.UM.rpc("rpc_remove_unit", id) # self-sacrifice on completed infection

func _apply_building_effect() -> void:
	# Stub: apply the building infection effect to _limpet_target here once the
	# channel completes. DESIGN: infected Generator/Vat/Beacon/Garage/Nest/MCP.
	pass
