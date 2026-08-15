extends Node3D

class_name EnergyManager

# --- Constants ---

const TICK_INTERVAL := 0.05
const SECOND_INTERVAL := 1.0
# Number of ticks that make up the full 1s rolling window.
const HISTORY_SAMPLES: int = int(SECOND_INTERVAL / TICK_INTERVAL)

# --- State ---

var energy: Dictionary = {}
var capacity: Dictionary = {}
# Supply ratio produced/requested, used to split limited incoming production
# fairly between consumers when rationing is active (see request_energy).
var _ratio: Dictionary = {}

# Rolling 1-second statistics (per player): energy generated, actually consumed
# and requested, integrated over the last second. Each tick the per-tick delta is
# pushed into the history ring buffer and the oldest sample is dropped, so the
# sum is a stable per-second rate rather than a ramping accumulator.
var _produced: Dictionary = {}
var _consumed: Dictionary = {}
var _requested: Dictionary = {}

# Per-tick accumulators, drained into the rolling buffers every tick.
var _consumed_tick: Dictionary = {}
var _requested_tick: Dictionary = {}

var _gen_history: Dictionary = {}
var _cons_history: Dictionary = {}
var _req_history: Dictionary = {}

var _tick_timer := 0.0

# Cached "generator" group membership, rebuilt on demand (see
# invalidate_collections). Group queries at 20 Hz were the hot spot.
var _generator_cache: Array = []
var _collections_dirty := true

# --- Lifecycle ---

func _ready() -> void:
	Global.EM = self
	for p in range(1, Global.MAX_PLAYERS + 1):
		energy[p] = 0.0
		capacity[p] = 0.0
		_ratio[p] = 1.0
		_produced[p] = 0.0
		_consumed[p] = 0.0
		_requested[p] = 0.0
		_consumed_tick[p] = 0.0
		_requested_tick[p] = 0.0
		_gen_history[p] = []
		_cons_history[p] = []
		_req_history[p] = []

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not Global.game_started:
		return
	_tick_timer += delta
	while _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_energy_tick()

# --- Tick functions ---

func _push_sample(history: Array, rolling: Dictionary, key: int, sample: float) -> void:
	history.append(sample)
	rolling[key] += sample
	if history.size() > HISTORY_SAMPLES:
		rolling[key] -= history.pop_front()

func _energy_tick() -> void:
	if _collections_dirty:
		_generator_cache = get_tree().get_nodes_in_group("generator")
		_collections_dirty = false
	var tick_rates: Dictionary = {}
	for b in _generator_cache:
		# Defensive: a queued-for-deletion node can linger in the cache between
		# invalidation and actual free (rpc_remove_building defers queue_free).
		if not is_instance_valid(b):
			continue
		if b.state != Building.State.CONSTRUCTED:
			continue
		var gen: float = b.get_energy() * TICK_INTERVAL
		if gen > 0.0:
			if b is Generator and not b.infections.is_empty():
				# DESIGN: an infected Generator generates power for the virus
				# owner(s) instead of the generator owner. Multiple attackers
				# split the output by infection strength. An infected MCP (also
				# in the "generator" group) keeps its power — theft is
				# Generator-only.
				var total_strength := 0.0
				for a in b.infections:
					total_strength += float(b.infections[a].get("strength", 1.0))
				for a in b.infections:
					var share: float = float(b.infections[a].get("strength", 1.0)) / total_strength
					tick_rates[a] = tick_rates.get(a, 0.0) + gen * share
			else:
				tick_rates[b.player_owner] = tick_rates.get(b.player_owner, 0.0) + gen
	for p in range(1, Global.MAX_PLAYERS + 1):
		var tick_gen := 0.0
		if capacity[p] > 0.0:
			tick_gen = tick_rates.get(p, 0.0)
			# DESIGN: Desperation Meter — the behind player's MCP gains a stacking
			# energy bonus per minute behind the leader (server-only state, already
			# broadcast below through rpc_apply_energy).
			tick_gen += Global.GM.desperation_energy_rate(p) * TICK_INTERVAL
			if tick_gen > 0.0:
				energy[p] = minf(energy[p] + tick_gen, capacity[p])
		# Always sample — even with capacity 0 (eliminated player). Skipping the
		# push froze the rolling produced/consumed/requested sums and the supply
		# ratio at their last values for the rest of the game.
		_push_sample(_gen_history[p], _produced, p, tick_gen)
		_push_sample(_cons_history[p], _consumed, p, _consumed_tick[p])
		_consumed_tick[p] = 0.0
		_push_sample(_req_history[p], _requested, p, _requested_tick[p])
		_requested_tick[p] = 0.0
		# Refresh the supply ratio from the trailing 1s of data.
		_ratio[p] = _produced[p] / _requested[p] if _requested[p] > 0.0 else 1.0
	_infection_drains()
	_broadcast_energy()

# DESIGN: infection drains on the owner's stored energy. Each infected Vat in a
# chain drains at the base rate (cascade = more vats, faster drain); an infected
# Beacon drains its owner's store as a parasite. The drained energy is
# destroyed, and counted as consumed so it shows up in the stats "used" rate.
func _infection_drains() -> void:
	# Iterate the tracked infected set (maintained by BuildingManager) instead
	# of scanning every building at 20 Hz — almost no buildings are infected.
	for b in Global.BM.infected_buildings:
		if not is_instance_valid(b) or b.state != Building.State.CONSTRUCTED or b.infections.is_empty():
			continue
		var rate := 0.0
		match b.type:
			BuildingManager.Type.VAT:
				rate = Config.VIRUS_VAT_DRAIN_DPS
			BuildingManager.Type.BEACON:
				rate = Config.VIRUS_BEACON_POWER_DPS
			_:
				continue
		var drained := 0.0
		for a in b.infections:
			drained += rate * float(b.infections[a].get("strength", 1.0)) * TICK_INTERVAL
		if drained <= 0.0:
			continue
		var stored: float = energy.get(b.player_owner, 0.0)
		var actual := minf(drained, stored)
		if actual > 0.0:
			energy[b.player_owner] = stored - actual
			_consumed_tick[b.player_owner] += actual

# --- Public API ---

# Called by TileManager whenever the "generator" group membership may have
# changed (building place/remove/construct), so the 20 Hz tick re-scans it.
func invalidate_collections() -> void:
	_collections_dirty = true

func request_energy(pnum: int, amount: float) -> float:
	if not multiplayer.is_server():
		return 0.0
	var allocated := amount
	# Ration only once the store actually runs dry. While reserves remain,
	# consumers draw their full request and the store absorbs the deficit (so a
	# banked surplus is spent at full rate); when it empties, scale requests by
	# the supply ratio so the remaining production income is split fairly instead
	# of going first-come-first-served.
	if energy.get(pnum, 0.0) <= 0.0:
		var produced: float = _produced.get(pnum, 0.0)
		if produced > 0.0:
			# Draw against this tick's production income (plus any residue) so an
			# empty store doesn't zero out the proportional share. The overdraft
			# is bounded by one tick of production and repaid next tick.
			allocated = minf(amount * _ratio.get(pnum, 1.0), maxf(energy.get(pnum, 0.0), 0.0) + produced * TICK_INTERVAL)
		else:
			allocated = 0.0
	else:
		allocated = minf(amount, energy.get(pnum, 0.0))
	energy[pnum] = energy.get(pnum, 0.0) - allocated
	_requested_tick[pnum] += amount
	_consumed_tick[pnum] += allocated
	return allocated

func recalculate_capacity() -> void:
	for p in range(1, Global.MAX_PLAYERS + 1):
		capacity[p] = 0.0
	# Iterate the building dictionary rather than the "vat" group: rpc_remove_building
	# erases a vat from the dictionary before calling recompute_aoe(), while queue_free
	# is deferred — so the group would still contain the just-destroyed vat and keep
	# counting its capacity.
	for b in Global.BM.buildings():
		# "vat" group includes both Vats and MCPs (the MCP is the baseline 1000e
		# supplier) — both expose get_capacity().
		if b.is_in_group("vat") and b.state == Building.State.CONSTRUCTED:
			capacity[b.player_owner] += b.get_capacity()
	for p in range(1, Global.MAX_PLAYERS + 1):
		if energy[p] > capacity[p]:
			energy[p] = capacity[p]

# --- Network ---

func _broadcast_energy() -> void:
	var data := PackedFloat64Array()
	data.append(Global.MAX_PLAYERS)
	for p in range(1, Global.MAX_PLAYERS + 1):
		data.append(p)
		data.append(maxf(energy[p], 0.0))
		data.append(capacity[p])
		data.append(_produced[p])
		data.append(_consumed[p])
	rpc("rpc_apply_energy", data)

@rpc("authority", "call_remote", "unreliable")
func rpc_apply_energy(data: PackedFloat64Array) -> void:
	var count := int(data[0])
	var idx := 1
	for _i in range(count):
		var pnum := int(data[idx]); idx += 1
		energy[pnum] = data[idx]; idx += 1
		capacity[pnum] = data[idx]; idx += 1
		_produced[pnum] = data[idx]; idx += 1
		_consumed[pnum] = data[idx]; idx += 1

# --- Queries ---

func get_player_energy(pnum: int) -> Dictionary:
	return {
		"current": maxf(energy.get(pnum, 0.0), 0.0),
		"capacity": capacity.get(pnum, 0.0),
		# Total energy generated and actually consumed per second, integrated over
		# the trailing 1 second of ticks.
		"produced": _produced.get(pnum, 0.0),
		"consumed": _consumed.get(pnum, 0.0),
	}
