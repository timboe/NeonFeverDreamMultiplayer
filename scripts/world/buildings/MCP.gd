extends Building

class_name MCP

# --- Constants ---

const HUD_SCENE: PackedScene = preload("res://scenes/ui/MCPHUD.tscn")

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
	var tm = Global.TM
	return floor(sqrt(tm.player_aoe_totals.get(player_owner, 0)))

# --- Production ---

func _can_produce() -> bool:
	if Global.UM.unit_count(player_owner, UnitManager.Type.AVATAR) < 1:
		return true
	return Global.UM.unit_count(player_owner, UnitManager.Type.ZOOMBA) < zoomba_cap()

func _produce_unit() -> void:
	if not multiplayer.is_server():
		return
	# DESIGN: MCP avatar buff — zoomba spawn rate +25% while empowered.
	var cooldown: float = Config.PRODUCTION_COOLDOWNS.get(type, 10.0)
	if is_empowered:
		cooldown *= Config.EMPOWER_MCP_SPAWN_RATE_MULT
	# Avatar takes priority
	if Global.UM.unit_count(player_owner, UnitManager.Type.AVATAR) < 1:
		var uid: int = Global.UM.next_unit_id()
		Global.UM.rpc("rpc_spawn_unit", uid, UnitManager.Type.AVATAR, self.id)
		_production_energy = 0.0
		_production_timer = cooldown
		return
	# Then zoombas up to cap
	if Global.UM.unit_count(player_owner, UnitManager.Type.ZOOMBA) < zoomba_cap():
		var uid: int = Global.UM.next_unit_id()
		Global.UM.rpc("rpc_spawn_unit", uid, UnitManager.Type.ZOOMBA, self.id)
		_production_energy = 0.0
		_production_timer = cooldown
		return
	# At cap — _can_produce() should prevent reaching here; hold defensively.
	_production_timer = 0.0
	_production_energy = 0.0

# --- Damage ---

# DESIGN: MCP avatar buff — 25% damage reduction while empowered.
func _apply_damage(damage: float, attacker: Unit = null) -> void:
	if state == State.CONSTRUCTED and is_empowered:
		damage *= Config.EMPOWER_MCP_DAMAGE_MULT
	super._apply_damage(damage, attacker)

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
