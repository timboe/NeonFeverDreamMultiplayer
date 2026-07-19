extends Building

class_name Vat

# --- Constants ---

const FULL_Y: float = 10.5
const EMPTY_Y: float = -7.5
const HEIGHT: float = FULL_Y - EMPTY_Y
const CAPACITY: float = 1000

# --- State ---

var capacity_mod_vats: float = 0.0
var capacity_mult_empower : float = 1.0

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
	if has_node("Liquid"):
		var mat_path := "res://materials/player/player" + str(pnum) + "_material.tres"
		$Liquid.set_surface_override_material(0, load(mat_path))
	add_to_group("vat_player" + str(player_owner))

func _process(delta: float) -> void:
	super._process(delta)
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

func update_capacity() -> void:
	var count := 0
	for n in location.neighbours:
		if n.building and n.building is Vat and n.building.player_owner == player_owner:
			count += 1
	capacity_mod_vats = count * 0.1 * CAPACITY

func get_capacity() -> float:
	return (CAPACITY + capacity_mod_vats) * capacity_mult_empower
