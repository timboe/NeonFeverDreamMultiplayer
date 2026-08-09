extends Node3D
class_name CombatManager

var _scan_timer := 0.0

func _ready() -> void:
	Global.CM = self

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not Global.game_started:
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
	# Avatars live in their FPSBody child — the Unit root stays at spawn, so aim at the body.
	var body := combat_target.get_node_or_null("FPSBody") as Node3D
	if body:
		return body.global_position
	return combat_target.global_position
func _enemy_list_for(unit: Unit) -> Array[int]:
	# Explicit enemy list only — no fallback to "everyone". An empty list means
	# the unit attacks nothing. Never include the unit's own team.
	var players: Array[int] = []
	if unit.orders.has("enemy") and not unit.orders["enemy"].is_empty():
		for p in unit.orders["enemy"]:
			if p != unit.player_owner:
				players.append(int(p))
	return players

func _attacker_mode(unit: Unit) -> int:
	if unit.type == UnitManager.Type.AERIAL and unit.has_method(&"get_mode"):
		return unit.get_mode()
	return Config.AERIAL_MODE_PATROL

# Shared enemy-building target selection (VIRUS attack jobs + AERIAL STRIKE
# personal jobs). Picks a random living enemy building of the allowed types.
func choose_building_target(enemies: Array, target_types: Array) -> Building:
	var bm = Global.BM
	if not bm:
		return null
	var candidates: Array = []
	for b in bm.buildings():
		if b.player_owner not in enemies:
			continue
		if b.health <= 0:
			continue
		if not target_types.is_empty() and b.type not in target_types:
			continue
		candidates.append(b)
	if candidates.is_empty():
		return null
	return candidates[Global.rand.randi() % candidates.size()]

func _in_range(from: Vector3, to: Vector3) -> bool:
	return from.distance_squared_to(to) < Config.COMBAT_RANGE * Config.COMBAT_RANGE

func _has_los(from: Vector3, to: Vector3, excludes: Array = []) -> bool:
	var space = get_world_3d().direct_space_state if get_world_3d() else null
	if not space:
		return true
	var query = PhysicsRayQueryParameters3D.create(from, to, Config.COMBAT_LOS_MASK, [])
	var rids: Array[RID] = []
	for n in excludes:
		rids.append_array(_collect_collision_rids(n))
	query.exclude = rids
	var result = space.intersect_ray(query)
	if result.is_empty():
		return true
	var collider = result.collider
	if collider is TileElement and collider.state in [TileManager.State.LOWERED, TileManager.State.FALLING]:
		return true
	var total_dist := from.distance_to(to)
	var hit_dist := from.distance_to(result.position)
	if hit_dist >= total_dist - 0.5:
		return true
	return false

func _collect_collision_rids(node: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if node is CollisionObject3D:
		rids.append(node.get_rid())
	for child in node.get_children():
		rids.append_array(_collect_collision_rids(child))
	return rids

func _can_see(attacker: Unit, target) -> bool:
	var from = attacker._get_muzzle_global()
	var to = combat_target_position(target)
	if not _in_range(from, to):
		return false
	return _has_los(from, to, [attacker, target])

func _score_for_damage(dmg: float, health: float) -> float:
	return dmg * 10.0 - health

func _scan_targets() -> void:
	if Global.JM == null:
		return
	for unit in Global.UM.units():
		match unit.type:
			UnitManager.Type.TANK:
				_scan_tank(unit)
			UnitManager.Type.AERIAL:
				_scan_aerial(unit)
			UnitManager.Type.AVATAR:
				_scan_avatar(unit)

func _dist_2d(a: Node3D, b: Node3D) -> float:
	var p := a.global_position
	var q := b.global_position
	return Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z))

# Single unit pass - LOS computed once per candidate is shared between
# combat-target picking and interception COMBAT job registration.
func _scan_tank(tank: Unit) -> void:
	if tank.health <= 0:
		tank.combat_target = null
		return
	var enemies := _enemy_list_for(tank)
	var best_target: Node = null
	var best_score := -INF
	if tank.combat_target and is_instance_valid(tank.combat_target):
		var t = tank.combat_target
		var dmg = Config.get_damage(tank.type, t)
		if dmg > 0 and t.health > 0 and t.player_owner in enemies and _can_see(tank, t):
			best_target = t
			best_score = _score_for_damage(dmg, t.health)
	for c in Global.UM.units():
		if c == tank or c.health <= 0:
			continue
		if c.player_owner not in enemies:
			continue
		match c.type:
			UnitManager.Type.AERIAL:
				# AA cover - only intercept aerial over own/contested territory
				if tank.player_owner not in c.location.aoe:
					continue
				var seen := _can_see(tank, c)
				if seen:
					Global.JM.add_job(tank.player_owner, JobManager.Type.COMBAT_PERSUE, c, tank, false, [UnitManager.Type.TANK], false, true)
					var dmg := Config.get_damage(tank.type, c)
					var score := _score_for_damage(dmg, c.health)
					if score > best_score:
						best_score = score
						best_target = c
			UnitManager.Type.VIRUS:
				# A tank spots an uncloaked virus attacking it and queues a kill-VIRUS job for patrols
				if c.cloaked or _dist_2d(tank, c) > Config.TANK_VIRUS_DETECT_RADIUS:
					continue
				if _can_see(tank, c):
					Global.JM.add_job(tank.player_owner, JobManager.Type.COMBAT_PERSUE, c, null, false, [UnitManager.Type.AERIAL], true, true)
	tank.combat_target = best_target

func _scan_aerial(aerial: Unit) -> void:
	if aerial.health <= 0:
		aerial.combat_target = null
		return
	var enemies := _enemy_list_for(aerial)
	var mode := _attacker_mode(aerial)
	var is_patrol := mode == Config.AERIAL_MODE_PATROL
	var best_target: Node = null
	var best_score := -INF
	if aerial.combat_target and is_instance_valid(aerial.combat_target):
		var t = aerial.combat_target
		var dmg = Config.get_damage(aerial.type, t, mode)
		if dmg > 0 and t.health > 0 and t.player_owner in enemies and _can_see(aerial, t):
			best_target = t
			best_score = _score_for_damage(dmg, t.health)
	for c in Global.UM.units():
		if c == aerial or c.health <= 0:
			continue
		if c.player_owner not in enemies:
			continue
		var dmg := Config.get_damage(aerial.type, c, mode)
		match c.type:
			UnitManager.Type.TANK:
				# Spot an enemy tank and queue a VIRUS ATTACK job — a freshly
				# spawned virus can be assigned it before it derives its own
				# personal ATTACK job (the 1s _idle_time guard).
				var seen := _can_see(aerial, c)
				if seen:
					Global.JM.add_job(aerial.player_owner, JobManager.Type.ATTACK, c, null, false, [UnitManager.Type.VIRUS])
					if dmg > 0:
						var score := _score_for_damage(dmg, c.health)
						if score > best_score:
							best_score = score
							best_target = c
			UnitManager.Type.VIRUS:
				# Detection (radius + LoS) uncloaks a cloaked virus — a cloaked
				# virus is never a fire target. Kill-VIRUS jobs are patrol-only:
				# PATROL executes them; STRIKE only queues.
				var radius := Config.PATROL_VIRUS_DETECT_RADIUS if is_patrol else Config.STRIKE_VIRUS_DETECT_RADIUS
				if _dist_2d(aerial, c) <= radius and _can_see(aerial, c):
					if c.cloaked:
						c.uncloak()
					var patrol_aerial := aerial if is_patrol else null
					Global.JM.add_job(aerial.player_owner, JobManager.Type.COMBAT_PERSUE, c, patrol_aerial, false, [UnitManager.Type.AERIAL], true, true)
				if dmg > 0 and not c.cloaked and _can_see(aerial, c):
					var score := _score_for_damage(dmg, c.health)
					if score > best_score:
						best_score = score
						best_target = c
			_:
				if dmg > 0:
					var score := _score_for_damage(dmg, c.health)
					if score > best_score and _can_see(aerial, c):
						best_score = score
						best_target = c
	if Global.BM:
		for b in Global.BM.buildings():
			if b.player_owner not in enemies or b.health <= 0:
				continue
			var dmg = Config.get_damage(aerial.type, b, mode)
			if dmg <= 0:
				continue
			var score := _score_for_damage(dmg, b.health)
			if score > best_score and _can_see(aerial, b):
				best_score = score
				best_target = b
	aerial.combat_target = best_target

func _scan_avatar(avatar: Unit) -> void:
	# Ground-level spotting: an enemy Avatar uncloaks cloaked VIRUS within its
	# sight radius + LoS. FPS sees 3-4 tiles, RTS only 1 tile (DESIGN). The
	# avatar lives in its FPSBody, so range/LoS originate from the body.
	var radius := Config.AVATAR_VIRUS_DETECT_RADIUS_FPS
	if Global.VM and Global.VM.camera_status == VideoManager.CameraStatus.OVERHEAD:
		radius = Config.AVATAR_VIRUS_DETECT_RADIUS_RTS
	var origin := avatar._get_muzzle_global()
	for c in Global.UM.units():
		if c.type != UnitManager.Type.VIRUS:
			continue
		if not c.cloaked or c.health <= 0 or c.player_owner == avatar.player_owner:
			continue
		var to := combat_target_position(c)
		if Vector2(origin.x, origin.z).distance_to(Vector2(to.x, to.z)) > radius:
			continue
		if _has_los(origin, to, [avatar, c]):
			c.uncloak()

func _update_firing(delta: float) -> void:
	for u in Global.UM.units():
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
		if target is Unit and target.type == UnitManager.Type.VIRUS and target.cloaked:
			# A re-cloaked virus cannot be targeted nor fired at.
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
					if Global.SM:
						Global.SM.record_damage_done(u.player_owner, dmg)
					if u.type == UnitManager.Type.AERIAL:
						u.combat_fire_event += 1
			if u.combat_burst_timer <= 0.0:
				u.combat_burst_timer = 0.0
