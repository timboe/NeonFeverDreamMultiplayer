extends Building

class_name MCP

const HUD_SCENE: PackedScene = preload("res://scenes/ui/MCPHUD.tscn")

# --- Constants ---

const A_VELOCITY: float = 100.0
const BASE_GENERATION: float = 27.0

# --- State ---

var to_rotate: Array = []

# --- Lifecycle ---

func _get_hud_scene() -> PackedScene:
	return HUD_SCENE

func _ready() -> void:
	if type == BuildingManager.Type.MCP_1:
		to_rotate.append($MCPTop)
		to_rotate.append($MCPFaceTop)
		to_rotate.append($MCPBottom)
		to_rotate.append($MCPFaceBottom)

func _process(delta: float) -> void:
	super._process(delta)
	for to_rot in to_rotate:
		to_rot.rotate_object_local(Vector3.UP, delta * A_VELOCITY)

func initialise(pnum: int, tile: TileElement) -> void:
	super.initialise(pnum, tile)
	_health_bar.global_position.y = Building.HEALTH_BAR_HEIGHT
	max_health = Config.BUILDING_MAX_HP[type]
	health = max_health
	_setup_production(UnitManager.Type.ZOOMBA)
	_production_timer = 0.0
	add_to_group("generator")
	add_to_group("generator_player" + str(pnum))
	add_to_group("mcp")
	add_to_group("mcp_player" + str(pnum))
	add_to_group("vat")
	add_to_group("vat_player" + str(pnum))
	_setup_hud()

# --- Queries ---

func zoomba_cap() -> int:
	var tm = get_node_or_null("/root/World/TileManager")
	return floor(sqrt(tm.player_aoe_totals.get(player_owner, 0)))

# --- Production ---

func _produce_unit() -> void:
	if not multiplayer.is_server():
		return
	var um = get_node_or_null("/root/World/UnitManager")
	if not um:
		return
	# Avatar takes priority
	if um.unit_count(player_owner, UnitManager.Type.AVATAR) < 1:
		var uid: int = um.next_unit_id()
		um.rpc("rpc_spawn_unit", uid, UnitManager.Type.AVATAR, self.id)
		_production_energy = 0.0
		_production_timer = Config.PRODUCTION_COOLDOWNS.get(type, 10.0)
		return
	# Then zoombas up to cap
	if um.unit_count(player_owner, UnitManager.Type.ZOOMBA) < zoomba_cap():
		var uid: int = um.next_unit_id()
		um.rpc("rpc_spawn_unit", uid, UnitManager.Type.ZOOMBA, self.id)
		_production_energy = 0.0
		_production_timer = Config.PRODUCTION_COOLDOWNS.get(type, 10.0)
		return
	# At cap — hold energy, don't consume
	_production_timer = Config.PRODUCTION_COOLDOWNS.get(type, 10.0)

# --- Energy ---

func update_energy() -> void:
	pass

func update_capacity() -> void:
	pass

func get_energy() -> float:
	if state != State.CONSTRUCTED:
		return 0.0
	return BASE_GENERATION

func get_capacity() -> float:
	return Config.BUILDING_ENERGY_CAPACITY[type]
