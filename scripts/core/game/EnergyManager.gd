extends Node3D

class_name EnergyManager

const TICK_INTERVAL := 0.05
const SECOND_INTERVAL := 1.0
# Number of ticks that make up the full 1s rolling window.
const HISTORY_SAMPLES: int = int(SECOND_INTERVAL / TICK_INTERVAL)

var energy: Dictionary = {}
var capacity: Dictionary = {}
# Internal supply-scaling stats used to ration consumers when demand exceeds
# production and reserves are too low to cover the gap (see request_energy).
var rate_of_change: Dictionary = {}
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

# --- Lifecycle ---

func _ready() -> void:
	Global.EM = self
	for p in range(1, Global.MAX_PLAYERS + 1):
		energy[p] = 0.0
		capacity[p] = 0.0
		rate_of_change[p] = 0.0
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
	var generators := get_tree().get_nodes_in_group("generator")
	var tick_rates: Dictionary = {}
	for b in generators:
		if b.state != Building.State.CONSTRUCTED:
			continue
		var gen : float = b.get_energy() * TICK_INTERVAL
		if gen > 0.0:
			tick_rates[b.player_owner] = tick_rates.get(b.player_owner, 0.0) + gen
	for p in range(1, Global.MAX_PLAYERS + 1):
		if capacity[p] <= 0.0:
			continue
		var tick_gen: float = tick_rates.get(p, 0.0)
		if tick_gen > 0.0:
			energy[p] = minf(energy[p] + tick_gen, capacity[p])
		_push_sample(_gen_history[p], _produced, p, tick_gen)
		_push_sample(_cons_history[p], _consumed, p, _consumed_tick[p])
		_consumed_tick[p] = 0.0
		_push_sample(_req_history[p], _requested, p, _requested_tick[p])
		_requested_tick[p] = 0.0
		# Refresh supply/demand from the trailing 1s of data.
		rate_of_change[p] = _produced[p] - _requested[p]
		_ratio[p] = _produced[p] / _requested[p] if _requested[p] > 0.0 else 1.0
	_broadcast_energy()

# --- Public API ---

func request_energy(pnum: int, amount: float) -> float:
	if not multiplayer.is_server():
		return 0.0
	var allocated := amount
	if rate_of_change[pnum] < 0.0 and -rate_of_change[pnum] > energy[pnum]:
		allocated *= _ratio.get(pnum, 1.0)
	allocated = minf(allocated, energy[pnum])
	energy[pnum] -= allocated
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
	var bm = Global.BM
	if not bm:
		return
	for b in bm.buildings():
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
		data.append(energy[p])
		data.append(capacity[p])
		data.append(_produced[p])
		data.append(_consumed[p])
	rpc("apply_energy", data)

@rpc("authority", "call_remote", "unreliable")
func apply_energy(data: PackedFloat64Array) -> void:
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
		"current": energy.get(pnum, 0.0),
		"capacity": capacity.get(pnum, 0.0),
		# Total energy generated and actually consumed per second, integrated over
		# the trailing 1 second of ticks.
		"produced": _produced.get(pnum, 0.0),
		"consumed": _consumed.get(pnum, 0.0),
	}
