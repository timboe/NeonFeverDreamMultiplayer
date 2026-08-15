extends Node3D
class_name CombatManager

# --- State ---

var _scan_timer := 0.0

# LOS cache: raycasts are only run on the first query per (attacker, target)
# pair, then reused while both endpoints stay within LOS_CACHE_TOL of their
# cached positions. The cache is cleared (_los_dirty) on any tile-state or
# building change that can alter sight lines, so a stale LOS can never persist
# past a wall raise/place/remove.
const LOS_CACHE_TOL2: float = 4.0 # 2.0 units, squared
var _los_cache: Dictionary = {} # Unit -> {target_key: {"from", "to", "los"}}
var _los_dirty := true

# --- Lifecycle ---

# Called by TileManager on any tile/building change that can alter sight lines.
func invalidate_los() -> void:
	_los_dirty = true

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

# --- Queries ---

func combat_target_position(combat_target: Variant) -> Vector3:
	if not combat_target or not is_instance_valid(combat_target):
		return Vector3.ZERO
	if combat_target is Building:
		return combat_target.location.pathing_centre + Vector3(0, Cairo.HEIGHT / 2.0, 0)
	# Avatars live in their FPSBody child — the Unit root stays at spawn, so aim
	# at the body. The ref is cached on Unit at spawn (fps_body_node).
	if combat_target is Unit:
		var body := combat_target.fps_body_node as Node3D
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
# require_constructed: VIRUS infection targets must be CONSTRUCTED (a
# blueprint/under-construction building can't be infected); AERIAL strikes keep
# the looser filter so they can shell construction sites.
func choose_building_target(enemies: Array, target_types: Array, require_constructed: bool = false) -> Building:
	var candidates: Array = []
	for b in Global.BM.buildings():
		if b.player_owner not in enemies:
			continue
		if b.health <= 0:
			continue
		if require_constructed and b.state != Building.State.CONSTRUCTED:
			continue
		if not target_types.is_empty() and not _type_in_targets(b.type, target_types):
			continue
		candidates.append(b)
	if candidates.is_empty():
		return null
	return candidates[Global.rand.randi() % candidates.size()]

# The building-type toggles use MCP_1 as a stand-in for all enemy MCPs (see
# Config.ALL_BUILDING_TARGETS), but a real MCP has its own type (MCP_2..4) —
# normalize both sides so an enemy MCP matches the MCP_1 toggle.
static func _type_in_targets(btype: BuildingManager.Type, targets: Array) -> bool:
	var norm := btype
	if btype >= BuildingManager.Type.MCP_1 and btype <= BuildingManager.Type.MCP_4:
		norm = BuildingManager.Type.MCP_1
	for t in targets:
		var tn := int(t)
		if tn >= BuildingManager.Type.MCP_1 and tn <= BuildingManager.Type.MCP_4:
			tn = BuildingManager.Type.MCP_1
		if tn == int(norm):
			return true
	return false

func _in_range(from: Vector3, to: Vector3) -> bool:
	return from.distance_squared_to(to) < Config.COMBAT_RANGE * Config.COMBAT_RANGE

# Public line-of-sight query — combat scans and the rally gather scan share it.
# Same raycast + graze-guard logic; the caller supplies the positions (which
# may be an avatar's FPSBody position) and any nodes to exclude from the cast.
func has_los(from: Vector3, to: Vector3, excludes: Array = []) -> bool:
	var space = get_world_3d().direct_space_state if get_world_3d() else null
	if not space:
		return true
	var query = PhysicsRayQueryParameters3D.create(from, to, Config.COMBAT_LOS_MASK, [])
	var rids: Array[RID] = []
	for n in excludes:
		rids.append_array(_collect_collision_rids(n))
	query.exclude = rids
	var result = space.intersect_ray(query)
	# Sight-line graze guard: a ray running exactly along a raised wall tile's
	# face plane (coplanar incidence) can intermittently thread the wall due to
	# float precision in the convex-shape test. When the main ray reads clear,
	# re-cast two rays offset by a small epsilon perpendicular to the sight line
	# (in XZ); if either grazes a RAISED tile, the line actually clips the wall
	# and must be blocked.
	var los_clear := false
	if result.is_empty():
		los_clear = true
	else:
		var collider = result.collider
		if collider is TileElement and collider.state in [TileManager.State.LOWERED, TileManager.State.FALLING]:
			los_clear = true
		elif collider is TileElement and collider.state == TileManager.State.RAISED:
			return false
		else:
			var total_dist := from.distance_to(to)
			var hit_dist := from.distance_to(result.position)
			if hit_dist >= total_dist - 0.5:
				los_clear = true
			else:
				return false
	if los_clear:
		var dir := to - from
		var xz := Vector2(dir.x, dir.z)
		if xz.length_squared() > 0.0001:
			var perp := Vector2(-xz.y, xz.x).normalized() * 0.1
			for side in [-1.0, 1.0]:
				var off := Vector3(perp.x * side, 0.0, perp.y * side)
				var qo := PhysicsRayQueryParameters3D.create(from + off, to + off, Config.COMBAT_LOS_MASK, rids)
				var ro := space.intersect_ray(qo)
				if not ro.is_empty():
					var co = ro.collider
					if co is TileElement and co.state == TileManager.State.RAISED:
						return false
	return true

func _collect_collision_rids(node: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if node is CollisionObject3D:
		rids.append(node.get_rid())
	for child in node.get_children():
		rids.append_array(_collect_collision_rids(child))
	return rids

func _can_see(attacker: Unit, target: Node3D, from := Vector3(INF, INF, INF)) -> bool:
	if _los_dirty:
		_los_cache.clear()
		_los_dirty = false
	# Callers hoist the muzzle fetch (force_update_transform is expensive) and
	# pass it in; only compute it here on direct calls.
	if from == Vector3(INF, INF, INF):
		from = attacker._get_muzzle_global()
	var to: Vector3 = combat_target_position(target)
	if not _in_range(from, to):
		return false
	var key := _los_target_key(target)
	var by_attacker = _los_cache.get(attacker)
	if by_attacker == null:
		by_attacker = {}
		_los_cache[attacker] = by_attacker
	var entry = by_attacker.get(key)
	if entry != null and entry["from"].distance_squared_to(from) < LOS_CACHE_TOL2 \
		and entry["to"].distance_squared_to(to) < LOS_CACHE_TOL2:
		return entry["los"]
	var los := has_los(from, to, [attacker, target])
	by_attacker[key] = {"from": from, "to": to, "los": los}
	return los

static func _los_target_key(target: Node3D) -> int:
	if target is Unit:
		return target.id
	if target is Building:
		return -target.id
	return 0

func _score_for_damage(dmg: float, health: float) -> float:
	return dmg * 10.0 - health

# --- Scanning ---

func _scan_targets() -> void:
	var all_units: Array = Global.UM.units()
	# Per-player groupings built once per scan — each attacker's pass then only
	# iterates enemy players' units/buildings instead of the whole world (the
	# old per-attacker Global.UM.units() call also allocated a fresh Array).
	var units_by_player: Dictionary = {}
	for u in all_units:
		if not units_by_player.has(u.player_owner):
			units_by_player[u.player_owner] = []
		units_by_player[u.player_owner].append(u)
	var buildings_by_player: Dictionary = {}
	for b in Global.BM.buildings():
		if not buildings_by_player.has(b.player_owner):
			buildings_by_player[b.player_owner] = []
		buildings_by_player[b.player_owner].append(b)
	# Freed attackers linger as _los_cache keys until the next _los_dirty clear —
	# sweep them each scan so the cache can't grow without bound in a quiet game.
	for key in _los_cache.keys():
		if not is_instance_valid(key):
			_los_cache.erase(key)
	for unit in all_units:
		match unit.type:
			UnitManager.Type.TANK:
				_scan_tank(unit, units_by_player)
			UnitManager.Type.AERIAL:
				_scan_aerial(unit, units_by_player, buildings_by_player)
			UnitManager.Type.AVATAR:
				_scan_avatar(unit, units_by_player)

func _dist_2d(a: Node3D, b: Node3D) -> float:
	var p := a.global_position
	var q := b.global_position
	return Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z))

# Single unit pass - LOS computed once per candidate is shared between
# combat-target picking and interception COMBAT job registration.
func _scan_tank(tank: Unit, units_by_player: Dictionary) -> void:
	if tank.health <= 0:
		tank.combat_target = null
		return
	# Hoist the muzzle fetch once per attacker for the whole candidate pass.
	var from: Vector3 = tank._get_muzzle_global()
	var enemies := _enemy_list_for(tank)
	var best_target: Node = null
	var best_score := -INF
	if tank.combat_target and is_instance_valid(tank.combat_target):
		var t = tank.combat_target
		var dmg = Config.get_damage(tank.type, t)
		if dmg > 0 and t.health > 0 and t.player_owner in enemies and _can_see(tank, t, from):
			best_target = t
			best_score = _score_for_damage(dmg, t.health)
	# Target stickiness: only switch away from the retained current target when
	# a candidate is clearly better — prevents ping-pong retargets between
	# aerials with near-equal scores (each switch costs re-aim downtime).
	var sticky := Config.COMBAT_TARGET_STICKY_MARGIN if best_target != null else 0.0
	for p in enemies:
		var list: Array = units_by_player.get(p, [])
		for c in list:
			if c == tank or c.health <= 0:
				continue
			match c.type:
				UnitManager.Type.AERIAL:
					# Firing is territory-free: a tank shoots any enemy aerial it can
					# see in range. The COMBAT_PERSUE patrol job is still queued only
					# over own AoE — tanks patrol home territory but engage off-base.
					var seen := _can_see(tank, c, from)
					if seen:
						if tank.player_owner in c.location.aoe:
							Global.JM.add_job(tank.player_owner, JobManager.Type.COMBAT_PERSUE, c, tank, false, [UnitManager.Type.TANK], false, true)
						var dmg := Config.get_damage(tank.type, c)
						var score := _score_for_damage(dmg, c.health)
						if score > best_score + sticky:
							best_score = score
							best_target = c
				UnitManager.Type.VIRUS:
					# A tank spots an uncloaked virus attacking it and queues a kill-VIRUS job for patrols
					if c.cloaked or _dist_2d(tank, c) > Config.TANK_VIRUS_DETECT_RADIUS:
						continue
					if _can_see(tank, c, from):
						Global.JM.add_job(tank.player_owner, JobManager.Type.COMBAT_PERSUE, c, null, false, [UnitManager.Type.AERIAL], true, true)
	tank.combat_target = best_target
	# NOTE: no combat_los_fail_time reset here — _update_firing accumulates and
	# resets it per-frame on actual visibility. Resetting it per scan extended
	# the LOS grace to ~0.8s and let tanks fire through fresh walls.

func _scan_aerial(aerial: Unit, units_by_player: Dictionary, buildings_by_player: Dictionary) -> void:
	if aerial.health <= 0:
		aerial.combat_target = null
		return
	# Hoist the muzzle fetch once per attacker for the whole candidate pass.
	var from: Vector3 = aerial._get_muzzle_global()
	var enemies := _enemy_list_for(aerial)
	var mode := _attacker_mode(aerial)
	var is_patrol := mode == Config.AERIAL_MODE_PATROL
	var best_target: Node = null
	var best_score := -INF
	if aerial.combat_target and is_instance_valid(aerial.combat_target):
		var t = aerial.combat_target
		var dmg = Config.get_damage(aerial.type, t, mode)
		# A re-cloaked VIRUS is invisible — never retain it (retaining it would
		# stick an untargetable score into best_target and suppress real picks).
		# `cloaked` exists only on VIRUS — guard the type before touching it.
		if dmg > 0 and t.health > 0 and t.player_owner in enemies \
			and not (t is Unit and t.type == UnitManager.Type.VIRUS and t.cloaked) \
			and _can_see(aerial, t, from):
			best_target = t
			best_score = _score_for_damage(dmg, t.health)
	for p in enemies:
		var list: Array = units_by_player.get(p, [])
		for c in list:
			if c == aerial or c.health <= 0:
				continue
			var dmg := Config.get_damage(aerial.type, c, mode)
			match c.type:
				UnitManager.Type.TANK:
					# Spot an enemy tank and queue a VIRUS ATTACK job — a freshly
					# spawned virus can be assigned it before it derives its own
					# personal ATTACK job (the 1s _idle_time guard).
					var seen := _can_see(aerial, c, from)
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
					if _dist_2d(aerial, c) <= radius and _can_see(aerial, c, from):
						if c.cloaked:
							c.uncloak()
						var patrol_aerial := aerial if is_patrol else null
						Global.JM.add_job(aerial.player_owner, JobManager.Type.COMBAT_PERSUE, c, patrol_aerial, false, [UnitManager.Type.AERIAL], true, true)
					if dmg > 0 and not c.cloaked and _can_see(aerial, c, from):
						var score := _score_for_damage(dmg, c.health)
						if score > best_score:
							best_score = score
							best_target = c
				_:
					if dmg > 0:
						var score := _score_for_damage(dmg, c.health)
						if score > best_score and _can_see(aerial, c, from):
							best_score = score
							best_target = c
	for p in enemies:
		var blist: Array = buildings_by_player.get(p, [])
		for b in blist:
			if b.health <= 0:
				continue
			var dmg = Config.get_damage(aerial.type, b, mode)
			if dmg <= 0:
				continue
			var score := _score_for_damage(dmg, b.health)
			if score > best_score and _can_see(aerial, b, from):
				best_score = score
				best_target = b
	aerial.combat_target = best_target

func _scan_avatar(avatar: Unit, units_by_player: Dictionary) -> void:
	# Ground-level spotting: an enemy Avatar uncloaks cloaked VIRUS within its
	# sight radius + LoS. FPS sees 3-4 tiles, RTS only 1 tile (DESIGN). The
	# avatar lives in its FPSBody, so range/LoS originate from the body.
	# Camera mode is per-player: the local avatar uses the host's own camera,
	# remote avatars use the mode each client reports via _cmd_camera_mode.
	var radius := Config.AVATAR_VIRUS_DETECT_RADIUS_FPS
	if _avatar_camera_mode(avatar.player_owner) == VideoManager.CameraStatus.OVERHEAD:
		radius = Config.AVATAR_VIRUS_DETECT_RADIUS_RTS
	var origin := avatar._get_muzzle_global()
	for p in units_by_player:
		if p == avatar.player_owner:
			continue
		for c in units_by_player[p]:
			if c.type != UnitManager.Type.VIRUS:
				continue
			if not c.cloaked or c.health <= 0:
				continue
			var to := combat_target_position(c)
			if Vector2(origin.x, origin.z).distance_to(Vector2(to.x, to.z)) > radius:
				continue
			if has_los(origin, to, [avatar, c]):
				c.uncloak()

func _avatar_camera_mode(pnum: int) -> int:
	if pnum == Global.my_player_number:
		return Global.VM.camera_status
	var nm = Global.network_manager
	if nm and nm.server:
		return nm.server.get_camera_mode(pnum)
	return VideoManager.CameraStatus.OVERHEAD

# --- Firing ---

func _update_firing(delta: float) -> void:
	for u in Global.UM.units():
		if u.health <= 0:
			u.combat_target = null
			continue
		if u.type != UnitManager.Type.TANK and u.type != UnitManager.Type.AERIAL:
			continue
		if u.type == UnitManager.Type.TANK and u.virus_immobilized():
			# DESIGN Nest avatar buff: a tank pinned by a VIRUS from an empowered
			# Nest cannot fire against AERIAL (its only target type — full stop).
			# It still queues kill-VIRUS PATROL support from the scan pass.
			continue
		if not u.combat_target or not is_instance_valid(u.combat_target):
			u.combat_target = null
			u.combat_los_fail_time = 0.0
			continue
		if not u.is_weapon_aligned():
			continue
		# Muzzle fetch hoisted once per unit per frame (force_update_transform).
		var from: Vector3 = u._get_muzzle_global()
		# Drop targets only after sustained visibility loss (behind a wall/out of
		# range) — a single-frame LOS flicker must not dump the target into the
		# re-scan + re-aim gap. The weapon keeps tracking while we wait.
		if not _can_see(u, u.combat_target, from):
			u.combat_los_fail_time += delta
			if u.combat_los_fail_time < Config.COMBAT_LOS_GRACE:
				continue
			u.combat_target = null
			u.combat_los_fail_time = 0.0
			continue
		u.combat_los_fail_time = 0.0
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
			# DESIGN Garage avatar buff: TANK fire rate +25% vs aerial targets
			# while the player has a Garage empowered (type-wide, dynamic).
			# DESIGN: an infected Garage cuts the owner's AA fire rate by 80%
			# (type-wide) — the two can stack against the same tank fleet.
			var interval := Config.COMBAT_FIRE_INTERVAL
			if u.type == UnitManager.Type.TANK \
				and target is Unit and target.type == UnitManager.Type.AERIAL:
				if Global.BM.empowered_type(u.player_owner) == BuildingManager.Type.GARAGE:
					interval *= Config.EMPOWER_TANK_FIRE_INTERVAL_MULT
				if Global.BM.player_has_infected_type(u.player_owner, BuildingManager.Type.GARAGE):
					interval *= Config.VIRUS_GARAGE_FIRE_INTERVAL_MULT
			u.combat_fire_timer = interval
			u.combat_burst_timer = Config.WEAPON_BURST_DURATION
			u.combat_damage_tick_timer = 0.0
			if u.type == UnitManager.Type.TANK:
				u.combat_fire_event += 1
		# Burst progression runs every frame while a burst is active — the
		# LOS-grace continues above pause it, so a blinded weapon holds its
		# remaining burst time until sight returns.
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
					# DESIGN: Desperation Meter — offensive units (STRIKE) deal
					# +3% per stack while behind; PATROL/TANK are defensive and
					# excluded.
					if u.type == UnitManager.Type.AERIAL and mode == Config.AERIAL_MODE_STRIKE:
						dmg *= Global.GM.desperation_damage_mult(u.player_owner)
					# DESIGN: rally tether — a rallied unit within 4 tiles of
					# the avatar deals +10% damage.
					if u.rallied and _rally_tethered(u):
						dmg *= Config.RALLY_TETHER_DAMAGE_MULT
					var delay := 0.0
					if u.type == UnitManager.Type.AERIAL:
						delay = u.update_projectile_delay()
					u.combat_target.apply_damage(dmg, delay, u)
					Global.SM.record_damage_done(u.player_owner, dmg)
					if u.type == UnitManager.Type.AERIAL:
						u.combat_fire_event += 1

# Whether a rallied unit is within the tether radius of its player's avatar
# (measured from the avatar's FPSBody — the root never moves).
func _rally_tethered(u: Unit) -> bool:
	var avatar := Global.GM._get_avatar(u.player_owner) as Unit
	if not avatar or not is_instance_valid(avatar):
		return false
	var body: Node3D = avatar.fps_body_node
	var pos: Vector3 = body.global_position if body else avatar.global_position
	return u.global_position.distance_squared_to(pos) <= Config.RALLY_TETHER_RADIUS * Config.RALLY_TETHER_RADIUS
