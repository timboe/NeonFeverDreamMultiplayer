extends Unit

class_name Virus

var cloaked: bool = true
var _health_decay_rate: float = 1.25
var _decay_timer: float = 0.0
const DECAY_INTERVAL: float = 0.1
var _last_cloak_k: float = -1.0
var _cloak_applied: bool = false

# TEMP (debug): force every virus unit to cloak/de-cloak on a fixed timer so
# the per-viewer cloak visuals can be inspected. Remove once debugging is done.
const DEBUG_CLOAK_INTERVAL := 10.0
var _debug_cloak_timer := 0.0

# Viewer-relative cloak opacity: the owner keeps a semi-transparent ghost so
# their own viruses stay trackable, everyone else sees them fully invisible.
const OWNER_CLOAK_ALPHA := 0.05

func _process(delta: float) -> void:
	super._process(delta)
	if multiplayer.is_server():
		_debug_cloak_timer += delta
		if _debug_cloak_timer >= DEBUG_CLOAK_INTERVAL:
			_debug_cloak_timer = 0.0
			cloaked = not cloaked
		if health > 0 and state != State.WORKING:
			_decay_timer += delta
			while _decay_timer >= DECAY_INTERVAL:
				_decay_timer -= DECAY_INTERVAL
				health -= _health_decay_rate * DECAY_INTERVAL
				if health <= 0:
					health = 0
					Global.UM.rpc("rpc_remove_unit", id)
					return
	_update_cloak_visual()

func initialise(b: Building) -> void:
	super.initialise(b)
	type = UnitManager.Type.VIRUS
	_health_bar.position.y = 3.2
	health = Config.UNIT_MAX_HP.get(type, 100.0)
	add_to_group("virus")
	add_to_group("virus_player" + str(player_owner))
	var model = _model()
	if model and model.has_method("set_player_color"):
		model.set_player_color(Config.player_accent(player_owner))
	_update_cloak_visual()

func _model() -> Node:
	return get_node_or_null("Body")

func _update_cloak_visual() -> void:
	var is_owner: bool = player_owner == Global.my_player_number
	var k := 1.0
	if cloaked:
		k = OWNER_CLOAK_ALPHA if is_owner else 0.0
	if _cloak_applied and is_equal_approx(_last_cloak_k, k):
		return
	_cloak_applied = true
	_last_cloak_k = k
	if _health_bar:
		_health_bar.visible = k > 0.0
	var model = _model()
	if model and model.has_method("set_cloak_alpha"):
		model.set_cloak_alpha(k)

func uncloak() -> void:
	cloaked = false
	_update_cloak_visual()

func recloak() -> void:
	cloaked = true
	_update_cloak_visual()
