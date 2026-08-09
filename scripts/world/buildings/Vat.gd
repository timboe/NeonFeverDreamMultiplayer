extends Building

class_name Vat

const HUD_SCENE: PackedScene = preload("res://scenes/ui/VatHUD.tscn")

# --- Constants ---

const FULL_Y: float = 10.5
const EMPTY_Y: float = -7.5
const HEIGHT: float = FULL_Y - EMPTY_Y
const CAPACITY: float = 1000

# --- State ---

var capacity_mod_vats: float = 0.0
var capacity_mult_empower: float = 1.0

# Shared health pool. The master (smallest id in the connected group) holds the
# pool's health/max_health; every member mirrors them. Null master = solo.
var pool_master: Vat = null
var pool_members: Array[Vat] = []

# --- Visuals ---

var liquid: MeshInstance3D = null

# --- Lifecycle ---

func _get_hud_scene() -> PackedScene:
	return HUD_SCENE

func _ready() -> void:
	if has_node("Liquid"):
		liquid = $Liquid

func initialise(pnum: int, tile: TileElement) -> void:
	super.initialise(pnum, tile)
	type = BuildingManager.Type.VAT
	_health_bar.global_position.y = Building.HEALTH_BAR_HEIGHT
	max_health = Config.BUILDING_MAX_HP[type]
	health = max_health
	if has_node("Liquid"):
		var mat_path := "res://materials/player/player" + str(pnum) + "_material.tres"
		$Liquid.set_surface_override_material(0, load(mat_path))
	add_to_group("vat")
	add_to_group("vat_player" + str(player_owner))
	_setup_hud()

func _process(delta: float) -> void:
	super._process(delta)
	if liquid == null or state != State.CONSTRUCTED:
		return
	var e = Global.EM.get_player_energy(player_owner)
	var fraction := 0.0
	if e.capacity > 0:
		fraction = e.current / e.capacity
	liquid.position.y = EMPTY_Y + fraction * HEIGHT

# --- Shared health pool (server-side only) ---

func set_constructed() -> void:
	super.set_constructed()
	_join_pool()
	# super.set_constructed() triggers recompute_aoe (via rpc_constructed) before
	# _join_pool() runs, so re-refresh capacity now that pooling is final.
	if Global.EM:
		Global.EM.recalculate_capacity()

func _adjacent_pool_vats() -> Array[Vat]:
	var result: Array[Vat] = []
	for n in location.neighbours:
		var b = n.building
		if b is Vat and b.player_owner == player_owner and b.state == Building.State.CONSTRUCTED:
			result.append(b)
	return result

# DESIGN.md: each vat contributes base HP minus 10% per adjacent friendly vat
# (additive, 0%-50%). Same-player adjacency only, like the capacity bonus.
func _pool_contribution() -> float:
	var count := 0
	for n in location.neighbours:
		var b = n.building
		if b is Vat and b.player_owner == player_owner:
			count += 1
	return Config.BUILDING_MAX_HP[type] * (1.0 - minf(0.5, 0.1 * count))

func _recompute_pool_max() -> void:
	var total := _pool_contribution()
	for m in pool_members:
		total += m._pool_contribution()
	max_health = total

func _sync_pool_health() -> void:
	for m in pool_members:
		if is_instance_valid(m):
			m.health = health
			m.max_health = max_health

# Called on a newly constructed vat: joins the adjacent pool, merges pools if it
# bridges two or more, or starts a solo pool.
func _join_pool() -> void:
	var adj := _adjacent_pool_vats()
	var masters: Dictionary = {}  # id -> Vat (resolved pool masters)
	for v in adj:
		var m: Vat = v.pool_master if v.pool_master != null else v
		masters[m.id] = m
	if masters.is_empty():
		pool_master = null
		pool_members = []
		max_health = _pool_contribution()
		health = max_health
		return
	if masters.size() == 1:
		var master: Vat = masters.values()[0]
		pool_master = master
		master.pool_members.append(self)
		master._recompute_pool_max()
		master.health = clampf(master.health + _pool_contribution(), 0.0, master.max_health)
		master._sync_pool_health()
	else:
		_merge_pools(masters)

func _merge_pools(masters: Dictionary) -> void:
	var new_master: Vat = self
	for m in masters.values():
		if m.id < new_master.id:
			new_master = m
	var all: Array[Vat] = []
	all.append(self)
	var old_current_sum := 0.0
	for m in masters.values():
		old_current_sum += m.health
		all.append(m)
		for mem in m.pool_members:
			all.append(mem)
		m.pool_members.clear()
	for v in all:
		if v == new_master:
			v.pool_master = null
		else:
			v.pool_master = new_master
			new_master.pool_members.append(v)
	new_master._recompute_pool_max()
	new_master.health = clampf(old_current_sum + _pool_contribution(), 0.0, new_master.max_health)
	new_master._sync_pool_health()

func _destroy_pool() -> void:
	var bm = Global.BM
	if not bm:
		return
	bm.rpc("rpc_remove_building", id)
	for m in pool_members:
		if is_instance_valid(m):
			bm.rpc("rpc_remove_building", m.id)

# --- Damage / repair ---

func _apply_damage(damage: float) -> void:
	if Global.SM:
		Global.SM.record_damage_received(player_owner, damage)
	if state == State.CONSTRUCTED:
		if pool_master != null:
			pool_master._apply_damage(damage)
			return
		health -= damage
		_sync_pool_health()
		if health <= 0:
			health = 0
			_sync_pool_health()
			_destroy_pool()
	else:
		# Under construction — no pool involvement (base behaviour).
		_construction_energy_spent -= damage
		if _construction_energy_spent <= 0:
			_construction_energy_spent = 0
			rpc("rpc_constructed", id)
			Global.BM.rpc("rpc_remove_building", id)

func _repair_heal() -> bool:
	var target: Vat = pool_master if pool_master != null else self
	target.health = minf(target.health + REPAIR_AMOUNT, target.max_health)
	target._sync_pool_health()
	if target.health >= target.max_health:
		finish_repair()
		return true
	return false

# --- Empower ---

func _empower_changed(val: bool) -> void:
	capacity_mult_empower = 1.2 if val else 1.0
	if not multiplayer.is_server():
		return
	if pool_master != null:
		# Member: ask the master to sync the whole pool (it also recomputes capacity).
		if pool_master.is_empowered != val:
			pool_master.rpc_set_empowered(val)
		return
	# Master (or solo): propagate to members, then refresh capacity once so the
	# +20% bonus (and its removal) is reflected immediately.
	if not pool_members.is_empty():
		for m in pool_members:
			if m.is_empowered != val:
				m.rpc_set_empowered(val)
	if Global.EM:
		Global.EM.recalculate_capacity()

# --- Capacity ---

func update_capacity() -> void:
	var count := 0
	for n in location.neighbours:
		if n.building and n.building is Vat and n.building.player_owner == player_owner:
			count += 1
	capacity_mod_vats = count * 0.1 * CAPACITY

func get_capacity() -> float:
	return (CAPACITY + capacity_mod_vats) * capacity_mult_empower
