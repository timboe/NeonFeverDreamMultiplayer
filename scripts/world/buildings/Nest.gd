extends Building

class_name Nest

# --- Constants ---

const HUD_SCENE: PackedScene = preload("res://scenes/ui/NestHUD.tscn")

# --- State ---

var _virus_tank_building_ratio: float = 0.5
var _enemy_targets: Array[int] = [1, 2, 3, 4]
var _building_targets: Array[BuildingManager.Type] = Config.ALL_BUILDING_TARGETS

func _get_hud_scene() -> PackedScene:
	return HUD_SCENE

# DESIGN: an infected Nest turns against its owner — every VIRUS the owner has
# loses cloak and takes damage over time while on the owner's own territory.
func _tick_infection(delta: float) -> void:
	super._tick_infection(delta)
	for attacker in infections:
		var strength: float = float(infections[attacker].get("strength", 1.0))
		var dps: float = Config.VIRUS_NEST_VIRUS_DPS * strength
		for u in Global.UM.units():
			if u.type != UnitManager.Type.VIRUS or u.player_owner != player_owner:
				continue
			if player_owner in u.location.aoe:
				u.uncloak() # re-armed every tick so the DoT outlasts the 5s re-cloak
				u.apply_damage(dps * delta)

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

func _copy_settings_from(sibling: Building) -> void:
	var n := sibling as Nest
	if not n:
		return
	if multiplayer.is_server():
		Global.send_command(player_owner, "set_nest_ratio", [id, n._virus_tank_building_ratio])
		Global.send_command(player_owner, "set_enemy_targets", [id, n._enemy_targets])
		Global.send_command(player_owner, "set_building_targets", [id, n._building_targets])
	else:
		set_virus_tank_building_ratio(n._virus_tank_building_ratio)
		set_enemy_targets(n._enemy_targets)
		set_building_targets(n._building_targets)
