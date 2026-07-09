extends Building
# warning-ignore-all:return_value_discarded

class_name Vat

const FULL_Y := 10.5
const EMPTY_Y := -7.5
const HEIGHT := FULL_Y - EMPTY_Y

const CAPACITY := 100.0 * 60.0
var capacity_mod := 0.0

var _contains_val: int
var contains: int:
	get: return _contains_val
	set(value): _contains_val = value

var liquid = null
var _liquid_tween: Tween

func _ready():
	if location != null:
		add_to_group("vat")
	if has_node("Liquid"):
		liquid = $Liquid

func get_capacity():
	return CAPACITY + capacity_mod
	
func animate(time : float, total_energy_cache : Array):
	if location != null and state == State.CONSTRUCTED:
		total_energy_cache[ location.player ].x += get_capacity()
		total_energy_cache[ location.player ].y += _contains_val
	if liquid != null:
		if _liquid_tween and _liquid_tween.is_valid():
			_liquid_tween.kill()
		_liquid_tween = create_tween()
		_liquid_tween.tween_property(liquid, "position:y",
			EMPTY_Y + (_contains_val / CAPACITY) * HEIGHT, time)
		
func set_contains(c : float):
	_contains_val = c
	assert(_contains_val <= get_capacity())

func add(to_add : float) -> float:
	if state != State.CONSTRUCTED:
		return to_add
	var remainder : float = _contains_val + to_add - get_capacity()
	if remainder > 0:
		set_contains(get_capacity())
		return remainder
	else:
		set_contains(_contains_val + to_add)
		return 0.0
		
func remove(to_remove : float) -> float:
	if state != State.CONSTRUCTED:
		return to_remove
	if to_remove <= _contains_val:
		set_contains(_contains_val - to_remove)
		return 0.0
	else:
		to_remove -= _contains_val
		set_contains(0.0)
		return to_remove
		
