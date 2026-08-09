extends Node3D

class_name StatisticsManager

# Server-only stats aggregator. Samples once per second and stashes one record
# per player per second into a full history (for graph drawing). The server
# keeps the complete history for every player; each record is pushed to the
# owning player's client the moment it's finalized. A client therefore only has
# its own player-number key populated, with copies of the per-second snapshots.
# Access via Global.SM.

# --- Constants ---

const TICK_INTERVAL := 1.0

# --- State ---

# pnum -> Array of per-second record dicts (newest last):
#   "time":   float, monotonic seconds since engine start (x-axis for graphs)
#   "aoe_size": float (split AoE score from TileManager.player_aoe_totals)
#   "energy":   {stored, capacity, generated, used} (per-second generated/used)
#   "units":    {zoomba, tank, aerial_strike, aerial_patrol, virus}
#   "damage":   {done, received} (accumulated over that second)
var stats: Dictionary = {}

var _timer := 0.0

# Per-second damage accumulators, drained into stats each tick.
var _damage_done: Dictionary = {}
var _damage_received: Dictionary = {}

# --- Lifecycle ---

func _ready() -> void:
	Global.SM = self
	for p in range(1, Global.MAX_PLAYERS + 1):
		stats[p] = []
		_damage_done[p] = 0.0
		_damage_received[p] = 0.0

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not Global.game_started:
		return
	_timer += delta
	while _timer >= TICK_INTERVAL:
		_timer -= TICK_INTERVAL
		_tick()

# --- Tick functions ---

static func _empty_record() -> Dictionary:
	return {
		"time": 0.0,
		"aoe_size": 0.0,
		"energy": {"stored": 0.0, "capacity": 0.0, "generated": 0.0, "used": 0.0},
		"units": {"zoomba": 0, "tank": 0, "aerial_strike": 0, "aerial_patrol": 0, "virus": 0},
		"damage": {"done": 0.0, "received": 0.0},
	}

func _tick() -> void:
	var tm = Global.TM
	var em = Global.EM
	var um = Global.UM
	var srv = Global._get_server()
	for p in range(1, Global.MAX_PLAYERS + 1):
		var record: Dictionary = _empty_record()
		record["time"] = Time.get_ticks_msec() / 1000.0
		record["aoe_size"] = tm.player_aoe_totals.get(p, 0.0)
		var e = em.get_player_energy(p)
		record["energy"]["stored"] = e["current"]
		record["energy"]["capacity"] = e["capacity"]
		record["energy"]["generated"] = e["produced"]
		record["energy"]["used"] = e["consumed"]
		record["units"]["zoomba"] = um.unit_count(p, UnitManager.Type.ZOOMBA)
		record["units"]["tank"] = um.unit_count(p, UnitManager.Type.TANK)
		record["units"]["virus"] = um.unit_count(p, UnitManager.Type.VIRUS)
		var strike := 0
		var patrol := 0
		for u in um.units():
			if u.player_owner == p and u.type == UnitManager.Type.AERIAL:
				if u.get_mode() == Config.AERIAL_MODE_STRIKE:
					strike += 1
				else:
					patrol += 1
		record["units"]["aerial_strike"] = strike
		record["units"]["aerial_patrol"] = patrol
		record["damage"]["done"] = _damage_done.get(p, 0.0)
		record["damage"]["received"] = _damage_received.get(p, 0.0)
		_damage_done[p] = 0.0
		_damage_received[p] = 0.0
		# Keep the full history on the server, then sync the just-finalized
		# record to the owning client. player_to_peer only contains remote
		# clients (peers > 1) — the host's local slot and AI slots have no peer,
		# so the host player (already stored server-side) is naturally skipped.
		stats[p].append(record)
		if srv:
			var peer: int = srv.player_to_peer.get(p, 0)
			if peer > 1:
				rpc_id(peer, "rpc_receive_stats", p, record)

# --- Public API ---

# Server-side hooks. Damage done is recorded by CombatManager at fire time;
# damage received is recorded in Unit/Building._apply_damage at impact time.
func record_damage_done(pnum: int, amount: float) -> void:
	if not multiplayer.is_server():
		return
	_damage_done[pnum] = _damage_done.get(pnum, 0.0) + amount

func record_damage_received(pnum: int, amount: float) -> void:
	if not multiplayer.is_server():
		return
	_damage_received[pnum] = _damage_received.get(pnum, 0.0) + amount

# Full per-second history for a player (server has everyone's; a client only
# has its own key populated). Newest record is last.
func get_stats(pnum: int) -> Array:
	return stats.get(pnum, [])

# --- Network ---

@rpc("authority", "call_remote", "reliable")
func rpc_receive_stats(pnum: int, record: Dictionary) -> void:
	if not stats.has(pnum):
		stats[pnum] = []
	stats[pnum].append(record)
