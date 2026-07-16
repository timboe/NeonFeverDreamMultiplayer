extends Building
# warning-ignore-all:return_value_discarded

class_name Vat

const FULL_Y := 10.5
const EMPTY_Y := -7.5
const HEIGHT := FULL_Y - EMPTY_Y

const CAPACITY := 100.0 * 60.0
var capacity_mod := 0.0

var _contains_val: float
var contains: float:
	get: return _contains_val
	set(value): _contains_val = value

var liquid = null

func _ready():
	if has_node("Liquid"):
		liquid = $Liquid

func initialise(pnum : int, tile : TileElement):
	super.initialise(pnum, tile)
	type = BuildingManager.Type.VAT
	add_to_group("vat")

func get_capacity():
	return CAPACITY + capacity_mod
	
func _process(_delta: float) -> void:
	if liquid == null or state != State.CONSTRUCTED:
		return
	var em = get_node_or_null("/root/World/EnergyManager")
	if em == null:
		return
	var e = em.get_player_energy(player_owner)
	var fraction := 0.0
	if e.capacity > 0:
		fraction = e.current / e.capacity
	liquid.position.y = EMPTY_Y + fraction * HEIGHT
		
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
		
