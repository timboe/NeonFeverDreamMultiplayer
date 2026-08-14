extends Building

class_name Beacon

# --- Constants ---

const HUD_SCENE: PackedScene = preload("res://scenes/ui/BeaconHUD.tscn")

# --- State ---

var patrol_strike_ratio: float = 0.5
var _patrol_stance: JobManager.Stance = JobManager.Stance.WIDE
var _enemy_targets: Array[int] = [1, 2, 3, 4]
var _building_targets: Array[BuildingManager.Type] = Config.ALL_BUILDING_TARGETS
# The aerial DoT is an O(units) scan — tick it at 1 Hz instead of per frame.
var _do_tick_timer := 0.0

func _get_hud_scene() -> PackedScene:
	return HUD_SCENE

# DESIGN: an infected Beacon drains the owner's power (EnergyManager handles the
# store drain) and deals 25 DPS to every AERIAL the owner has in the air — the
# beacon's fleet turns against itself. Magnitude scales with infection strength.
func _tick_infection(delta: float) -> void:
	super._tick_infection(delta)
	_do_tick_timer += delta
	if _do_tick_timer < 1.0:
		return
	_do_tick_timer = 0.0
	for attacker in infections:
		var strength: float = float(infections[attacker].get("strength", 1.0))
		var dps: float = Config.VIRUS_BEACON_AERIAL_DPS * strength
		for u in Global.UM.units():
			if u.type == UnitManager.Type.AERIAL and u.player_owner == player_owner:
				u.apply_damage(dps)

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
	var uid: int = Global.UM.next_unit_id()
	Global.UM.rpc("rpc_spawn_unit", uid, UnitManager.Type.AERIAL, self.id)
	_production_energy = 0.0
	_production_timer = Config.PRODUCTION_COOLDOWNS.get(type, 4.0)

func _update_orders() -> void:
	_enemy_targets = _clean_enemy_targets(_enemy_targets)
	orders["patrol"]["stance"] = _patrol_stance
	orders["patrol"]["enemy"] = _enemy_targets
	orders["strike"]["enemy"] = _enemy_targets
	orders["strike"]["target"] = _building_targets

func set_enemy_targets(et: Array[int]) -> void:
	_enemy_targets = _clean_enemy_targets(et)
	_update_orders()

func set_patrol_stance(ps: JobManager.Stance) -> void:
	_patrol_stance = ps
	_update_orders()

func set_building_targets(bt: Array[BuildingManager.Type]) -> void:
	_building_targets = bt
	_update_orders()

func _copy_settings_from(sibling: Building) -> void:
	var b := sibling as Beacon
	if not b:
		return
	if multiplayer.is_server():
		Global.send_command(player_owner, "set_beacon_ratio", [id, b.patrol_strike_ratio])
		Global.send_command(player_owner, "set_enemy_targets", [id, b._enemy_targets])
		Global.send_command(player_owner, "set_building_targets", [id, b._building_targets])
		Global.send_command(player_owner, "set_patrol_stance", [id, b._patrol_stance])
	else:
		patrol_strike_ratio = b.patrol_strike_ratio
		set_enemy_targets(b._enemy_targets)
		set_building_targets(b._building_targets)
		set_patrol_stance(b._patrol_stance)
