extends Node3D
class_name CombatManager

var _scan_timer := 0.0
var _unit_manager: UnitManager
var _building_manager: BuildingManager
var _pathing_manager: PathingManager

func _ready() -> void:
	_unit_manager = get_node_or_null("/root/World/UnitManager") as UnitManager
	_building_manager = get_node_or_null("/root/World/BuildingManager") as BuildingManager
	_pathing_manager = get_node_or_null("/root/World/TileManager/PathingManager") as PathingManager

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_scan_timer += delta
	while _scan_timer >= Config.COMBAT_SCAN_INTERVAL:
		_scan_timer -= Config.COMBAT_SCAN_INTERVAL
		_scan_targets()
	_update_firing(delta)

func combat_target_position(combat_target : Variant) -> Vector3:
	if not combat_target or not is_instance_valid(combat_target):
		return Vector3.ZERO
	if combat_target is Building:
		return combat_target.location.pathing_centre + Vector3(0, Cairo.HEIGHT / 2.0, 0)
	return combat_target.global_position

func _enemy_list_for(unit: Unit) -> Array[int]:
	if unit.orders.has("enemy") and not unit.orders["enemy"].is_empty():
		return unit.orders["enemy"] as Array[int]
	var players: Array[int] = []
	for p in range(1, Global.MAX_PLAYERS + 1):
		if p != unit.player_owner:
			players.append(p)
	return players

func _attacker_mode(unit: Unit) -> int:
	if unit.type == UnitManager.Type.AERIAL and unit.has_method(&"get_mode"):
		return unit.get_mode()
	return Config.AERIAL_MODE_PATROL

func _in_range(from: Vector3, to: Vector3) -> bool:
	return from.distance_squared_to(to) < Config.COMBAT_RANGE * Config.COMBAT_RANGE

func _has_los(from: Vector3, to: Vector3, exclude: Node = null) -> bool:
	return true
	#
	# TODO DEBUG
	#
	var space = get_world_3d().direct_space_state if get_world_3d() else null
	if not space:
		return true
	var query = PhysicsRayQueryParameters3D.create(from, to, Config.COMBAT_LOS_MASK, [])
	if exclude:
		query.exclude = [exclude]
	var result = space.intersect_ray(query)
	if result.is_empty():
		return true
	var collider = result.collider
	if collider is TileElement and collider.state in [TileManager.State.LOWERED, TileManager.State.FALLING, TileManager.State.DISABLED]:
		return true
	var dist_to_target = from.distance_squared_to(to)
	var hit_dist = from.distance_squared_to(result.position)
	if hit_dist >= dist_to_target - 0.5:
		return true
	return false

func _can_see(attacker: Unit, target) -> bool:
	var from = attacker._get_muzzle_global()
	var to = target.global_position
	if not _in_range(from, to):
		return false
	return _has_los(from, to, attacker)

func _score_for_damage(dmg: float, health: float) -> float:
	return dmg * 10.0 - health

func _pick_target(unit: Unit) -> Node:
	var enemies = _enemy_list_for(unit)
	var unit_mode = _attacker_mode(unit)
	var best_target: Node = null
	var best_score := -INF
	var current_valid = false
	if unit.combat_target and is_instance_valid(unit.combat_target):
		var t = unit.combat_target
		var hp = t.health
		var dmg = Config.get_damage(unit.type, t, unit_mode)
		if dmg > 0 and hp > 0 and t.player_owner in enemies and _can_see(unit, t):
			current_valid = true
			best_target = t
			best_score = _score_for_damage(dmg, hp)
	for u in _unit_manager.units():
		if u == unit or u.health <= 0:
			continue
		if u.player_owner not in enemies:
			continue
		var dmg = Config.get_damage(unit.type, u, unit_mode)
		if dmg <= 0:
			continue
		var score = _score_for_damage(dmg, u.health)
		if score > best_score or (score == best_score and best_target and u == best_target):
			if _can_see(unit, u):
				best_target = u
				best_score = score
				current_valid = true
	if unit.type == UnitManager.Type.AERIAL:
		for b in _building_manager.buildings():
			if b.player_owner not in enemies or b.health <= 0:
				continue
			var dmg = Config.get_damage(unit.type, b, unit_mode)
			if dmg <= 0:
				continue
			var score = _score_for_damage(dmg, b.health)
			if score > best_score:
				if _can_see(unit, b):
					best_target = b
					best_score = score
					current_valid = true
	return best_target

func _scan_targets() -> void:
	for u in _unit_manager.units():
		if u.type != UnitManager.Type.TANK and u.type != UnitManager.Type.AERIAL:
			continue
		if u.health <= 0:
			u.combat_target = null
			continue
		var new_target = _pick_target(u)
		u.combat_target = new_target

func _update_firing(delta: float) -> void:
	for u in _unit_manager.units():
		if u.health <= 0:
			u.combat_target = null
			continue
		if u.type != UnitManager.Type.TANK and u.type != UnitManager.Type.AERIAL:
			continue
		if not u.combat_target or not is_instance_valid(u.combat_target):
			continue
		if not u.is_weapon_aligned():
			continue
		var target = u.combat_target
		if target is Unit and target.health <= 0:
			u.combat_target = null
			continue
		if target is Building and target.health <= 0:
			u.combat_target = null
			continue
		u.combat_fire_timer -= delta
		if u.combat_fire_timer <= 0.0:
			u.combat_fire_timer = Config.COMBAT_FIRE_INTERVAL
			u.combat_burst_timer = Config.WEAPON_BURST_DURATION
			u.combat_damage_tick_timer = 0.0
			if u.type == UnitManager.Type.TANK:
				u.combat_fire_event += 1

		if u.combat_burst_timer > 0.0:
			u.combat_burst_timer -= delta
			u.combat_damage_tick_timer -= delta
			while u.combat_damage_tick_timer <= 0.0 and u.combat_burst_timer > 0.0:
				u.combat_damage_tick_timer += Config.DAMAGE_TICK_DURATION
				if not u.combat_target or not is_instance_valid(u.combat_target):
					continue
				if not u.is_weapon_aligned():
					continue
				var mode = _attacker_mode(u)
				var dmg = Config.get_damage(u.type, u.combat_target, mode)
				if dmg > 0:
					var delay := 0.0
					if u.type == UnitManager.Type.AERIAL:
						delay = u.update_projectile_delay()
					u.combat_target.apply_damage(dmg, delay)
					if u.type == UnitManager.Type.AERIAL:
						u.combat_fire_event += 1
			if u.combat_burst_timer <= 0.0:
				u.combat_burst_timer = 0.0
