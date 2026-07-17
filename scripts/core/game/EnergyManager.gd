extends Node3D

class_name EnergyManager

const TICK_INTERVAL := 0.05
const SECOND_INTERVAL := 1.0

var energy: Dictionary = {}
var capacity: Dictionary = {}
var rate_of_change: Dictionary = {}

var _generated: Dictionary = {}
var _requested: Dictionary = {}
var _ratio: Dictionary = {}

var _tick_timer := 0.0
var _second_timer := 0.0

# --- Lifecycle ---

func _ready() -> void:
	for p in Global.MAX_PLAYERS:
		energy[p] = 0.0
		capacity[p] = 0.0
		rate_of_change[p] = 0.0
		_generated[p] = 0.0
		_requested[p] = 0.0
		_ratio[p] = 1.0

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick_timer += delta
	_second_timer += delta
	while _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_energy_tick()
	while _second_timer >= SECOND_INTERVAL:
		_second_timer -= SECOND_INTERVAL
		_second_tick()

# --- Tick functions ---

func _energy_tick() -> void:
	for p in Global.MAX_PLAYERS:
		if capacity[p] <= 0.0:
			continue
		var tick_gen := 0.0
		for b in get_tree().get_nodes_in_group("generator"):
			if b.player_owner == p:
				tick_gen += b.get_energy() * TICK_INTERVAL
		energy[p] = minf(energy[p] + tick_gen, capacity[p])
		_generated[p] += tick_gen
	_broadcast_energy()

func _second_tick() -> void:
	for p in Global.MAX_PLAYERS:
		rate_of_change[p] = _generated[p] - _requested[p]
		if _requested[p] > 0.0:
			_ratio[p] = _generated[p] / _requested[p]
		else:
			_ratio[p] = 1.0
		_generated[p] = 0.0
		_requested[p] = 0.0

# --- Public API ---

func request_energy(pnum: int, amount: float) -> float:
	if not multiplayer.is_server():
		return 0.0
	var allocated := amount
	if rate_of_change[pnum] < 0.0 and -rate_of_change[pnum] > energy[pnum]:
		allocated *= _ratio.get(pnum, 1.0)
	allocated = minf(allocated, energy[pnum])
	energy[pnum] -= allocated
	_requested[pnum] += amount
	return allocated

func recalculate_capacity() -> void:
	for p in Global.MAX_PLAYERS:
		capacity[p] = 0.0
	for v in get_tree().get_nodes_in_group("vat"):
		if v.state == Building.State.CONSTRUCTED:
			capacity[v.player_owner] += v.get_capacity()
	for p in Global.MAX_PLAYERS:
		if energy[p] > capacity[p]:
			energy[p] = capacity[p]

# --- Network ---

func _broadcast_energy() -> void:
	var data := PackedFloat64Array()
	data.append(Global.MAX_PLAYERS)
	for p in Global.MAX_PLAYERS:
		data.append(p)
		data.append(energy[p])
		data.append(capacity[p])
		data.append(rate_of_change[p])
	rpc("apply_energy", data)

@rpc("authority", "call_remote", "unreliable")
func apply_energy(data: PackedFloat64Array) -> void:
	var count := int(data[0])
	var idx := 1
	for _i in range(count):
		var pnum := int(data[idx]); idx += 1
		energy[pnum] = data[idx]; idx += 1
		capacity[pnum] = data[idx]; idx += 1
		rate_of_change[pnum] = data[idx]; idx += 1

# --- Queries ---

func get_player_energy(pnum: int) -> Dictionary:
	return {
		"current": energy.get(pnum, 0.0),
		"capacity": capacity.get(pnum, 0.0),
		"rate": rate_of_change.get(pnum, 0.0),
	}
