extends Building

class_name Vat

# --- Constants ---

const FULL_Y: float = 10.5
const EMPTY_Y: float = -7.5
const HEIGHT: float = FULL_Y - EMPTY_Y
const CAPACITY: float = 100.0 * 60.0

# --- State ---

var capacity_mod: float = 0.0

var _contains_val: float
var contains: float:
	get: return _contains_val
	set(value): _contains_val = value

# --- Visuals ---

var liquid: MeshInstance3D = null

# --- Lifecycle ---

func _ready() -> void:
	if has_node("Liquid"):
		liquid = $Liquid

func initialise(pnum: int, tile: TileElement) -> void:
	super.initialise(pnum, tile)
	type = BuildingManager.Type.VAT
	_health_bar.global_position.y = Building.HEALTH_BAR_HEIGHT
	max_health = Config.BUILDING_MAX_HP[type]
	health = max_health
	add_to_group("vat")

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

# --- Capacity ---

func get_capacity() -> float:
	return CAPACITY + capacity_mod

# --- Contents ---

func set_contains(c: float) -> void:
	_contains_val = minf(c, get_capacity())

func add(to_add: float) -> float:
	if state != State.CONSTRUCTED:
		return to_add
	var remainder: float = _contains_val + to_add - get_capacity()
	if remainder > 0:
		set_contains(get_capacity())
		return remainder
	else:
		set_contains(_contains_val + to_add)
		return 0.0

func remove(to_remove: float) -> float:
	if state != State.CONSTRUCTED:
		return to_remove
	if to_remove <= _contains_val:
		set_contains(_contains_val - to_remove)
		return 0.0
	else:
		to_remove -= _contains_val
		set_contains(0.0)
		return to_remove
