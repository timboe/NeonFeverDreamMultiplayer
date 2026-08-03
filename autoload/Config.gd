extends Node

# --- Buildings ---

static var BUILDING_AOE: Dictionary = {
	BuildingManager.Type.MCP_1: 6,
	BuildingManager.Type.MCP_2: 6,
	BuildingManager.Type.MCP_3: 6,
	BuildingManager.Type.MCP_4: 6,
	BuildingManager.Type.GEN: 4,
	BuildingManager.Type.VAT: 2,
	BuildingManager.Type.GARAGE: 3,
	BuildingManager.Type.BEACON: 3,
	BuildingManager.Type.NEST: 2,
}

static var BUILDING_MAX_HP: Dictionary = {
	BuildingManager.Type.MCP_1: 15000.0,
	BuildingManager.Type.MCP_2: 15000.0,
	BuildingManager.Type.MCP_3: 15000.0,
	BuildingManager.Type.MCP_4: 15000.0,
	BuildingManager.Type.GEN: 2000.0,
	BuildingManager.Type.VAT: 1500.0,
	BuildingManager.Type.GARAGE: 2000.0,
	BuildingManager.Type.BEACON: 2000.0,
	BuildingManager.Type.NEST: 2000.0,
}

static var BUILDING_ENERGY_CAPACITY: Dictionary = {
	BuildingManager.Type.MCP_1: 1000.0,
	BuildingManager.Type.MCP_2: 1000.0,
	BuildingManager.Type.MCP_3: 1000.0,
	BuildingManager.Type.MCP_4: 1000.0,
	BuildingManager.Type.GEN: 0.0,
	BuildingManager.Type.VAT: 1000.0,
	BuildingManager.Type.GARAGE: 0.0,
	BuildingManager.Type.BEACON: 0.0,
	BuildingManager.Type.NEST: 0.0,
}

static var CONSTRUCTION_COST: Dictionary = {
	BuildingManager.Type.GEN: 900.0,
	BuildingManager.Type.VAT: 400.0,
	BuildingManager.Type.GARAGE: 750.0,
	BuildingManager.Type.BEACON: 750.0,
	BuildingManager.Type.NEST: 750.0,
}

const TERMINAL_SCREEN_SIZE: float = 3.0

# --- Production ---

static var UNIT_COST: Dictionary = {
	UnitManager.Type.ZOOMBA: 25.0,
	UnitManager.Type.TANK: 150.0,
	UnitManager.Type.AERIAL: 100.0,
	UnitManager.Type.VIRUS: 100.0,
	UnitManager.Type.AVATAR: 0.0,
}

static var PRODUCTION_COOLDOWNS: Dictionary = {
	BuildingManager.Type.MCP_1: 2.0, # TESTING
	BuildingManager.Type.MCP_2: 10.0,
	BuildingManager.Type.MCP_3: 10.0,
	BuildingManager.Type.MCP_4: 10.0,
	BuildingManager.Type.GARAGE: 6.0,
	BuildingManager.Type.BEACON: 4.0,
	BuildingManager.Type.NEST: 5.0,
}

# --- Combat ---

const BASE_DPS: float = 5.0

const AERIAL_MODE_PATROL := 0
const AERIAL_MODE_STRIKE := 1

const COMBAT_SCAN_INTERVAL: float = 0.5
const COMBAT_FIRE_INTERVAL: float = 0.8
const COMBAT_RANGE: float = 40.0
const WEAPON_TURN_SPEED: float = PI
const WEAPON_ALIGN_THRESHOLD: float = 0.05
const PROJECTILE_MAX_FLIGHT_TIME: float = 1.0
const WEAPON_BURST_DURATION: float = 0.4
const DAMAGE_TICK_DURATION: float = 0.1
const COMBAT_LOS_MASK: int = 1

# Interception COMBAT job detection radii (world units).
const PATROL_VIRUS_DETECT_RADIUS: float = 25.0 # PATROL spotting cloaked VIRUS (2-3 tiles)
const STRIKE_VIRUS_DETECT_RADIUS: float = 10.0 # STRIKE direct-overfly detection (1 tile)
const TANK_VIRUS_DETECT_RADIUS: float = 25.0   # TANK seeing an uncloaked VIRUS attacker

static var TANK_AERIAL_MODE_MULTIPLIERS: Dictionary = {
	AERIAL_MODE_PATROL: 6.0,
	AERIAL_MODE_STRIKE: 5.0,
}

static var AERIAL_DAMAGE_MULTIPLIERS: Dictionary = {
	AERIAL_MODE_PATROL: {
		UnitManager.Type.ZOOMBA: 1.0,
		UnitManager.Type.TANK: 1.0,
		UnitManager.Type.VIRUS: 5.0,
		UnitManager.Type.AVATAR: 1.0,
		"BUILDING": 1.0,
	},
	AERIAL_MODE_STRIKE: {
		UnitManager.Type.ZOOMBA: 1.0,
		UnitManager.Type.TANK: 1.0,
		UnitManager.Type.VIRUS: 1.0,
		UnitManager.Type.AVATAR: 1.0,
		"BUILDING": 2.0,
	},
}

static var AERIAL_AERIAL_MODE_MULTIPLIERS: Dictionary = {
	AERIAL_MODE_PATROL: {
		AERIAL_MODE_PATROL: 1.0,
		AERIAL_MODE_STRIKE: 0.5,
	},
	AERIAL_MODE_STRIKE: {
		AERIAL_MODE_PATROL: 2.0,
		AERIAL_MODE_STRIKE: 1.0,
	},
}

func get_damage(attacker_type: UnitManager.Type, target, attacker_mode: int = AERIAL_MODE_PATROL) -> float:
	if attacker_type == UnitManager.Type.TANK:
		if target is Unit and target.type == UnitManager.Type.AERIAL:
			var mode = target.mode if target.has_method(&"get_mode") else AERIAL_MODE_PATROL
			return BASE_DPS * TANK_AERIAL_MODE_MULTIPLIERS.get(mode, 5.0)
		return 0.0
	elif attacker_type == UnitManager.Type.AERIAL:
		if target is Unit:
			if target.type == UnitManager.Type.AERIAL:
				var tmode = target.mode if target.has_method(&"get_mode") else AERIAL_MODE_PATROL
				return BASE_DPS * AERIAL_AERIAL_MODE_MULTIPLIERS.get(attacker_mode, {}).get(tmode, 1.0)
			var row = AERIAL_DAMAGE_MULTIPLIERS.get(attacker_mode, {})
			return BASE_DPS * row.get(target.type, 0.0)
		elif target is Building:
			var row = AERIAL_DAMAGE_MULTIPLIERS.get(attacker_mode, {})
			return BASE_DPS * row.get("BUILDING", 0.0)
	return 0.0

# --- Units ---

static var UNIT_SPEED: Dictionary = {
	UnitManager.Type.ZOOMBA: 1.0,
	UnitManager.Type.TANK: 1.0,
	UnitManager.Type.AERIAL: 1.0,
	UnitManager.Type.VIRUS: 1.0,
	UnitManager.Type.AVATAR: 0.0,
}

static var UNIT_MAX_HP: Dictionary = {
	UnitManager.Type.ZOOMBA: 50.0,
	UnitManager.Type.TANK: 400.0,
	UnitManager.Type.AERIAL: 400.0,
	UnitManager.Type.VIRUS: 150.0,
	UnitManager.Type.AVATAR: 200.0,
}

static var HOME_TERRITORY_UNITS: Array[int] = [
	UnitManager.Type.ZOOMBA,
	UnitManager.Type.TANK,
	UnitManager.Type.AERIAL,
]

static var SELF_HEALING_UNITS: Array[int] = [
	UnitManager.Type.ZOOMBA,
	UnitManager.Type.TANK,
]

# --- Players ---

static var PLAYER_COLORS: Array[Color] = [
	Color.RED,
	Color.GREEN,
	Color.YELLOW,
	Color.ORANGE_RED,
]

# 0-based, aligned with PLAYER_COLORS — index player_number - 1.
static var PLAYER_NAMES: Array[String] = [
	"Red",
	"Green",
	"Yellow",
	"Orange",
]
