extends Unit

class_name Virus

var cloaked: bool = true
var _health_decay_rate: float = 1.25
var _decay_timer: float = 0.0
const DECAY_INTERVAL: float = 0.1
var _last_cloak_state: bool = false
var _cloak_applied: bool = false

# TEMP (tuning): always render the model fully uncloaked so the whole
# electric-cloud model is visible. Gameplay cloak state is unchanged.
const VISUALIZE_DISABLE_CLOAK := true

func _process(delta: float) -> void:
	super._process(delta)
	if multiplayer.is_server():
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
	var visual_cloak: bool = false if VISUALIZE_DISABLE_CLOAK else cloaked
	if _cloak_applied and _last_cloak_state == visual_cloak:
		return
	_cloak_applied = true
	_last_cloak_state = visual_cloak
	var model = _model()
	if model and model.has_method("set_cloak"):
		model.set_cloak(visual_cloak)

func uncloak() -> void:
	cloaked = false
	_update_cloak_visual()

func recloak() -> void:
	cloaked = true
	_update_cloak_visual()
