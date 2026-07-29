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

const BASE_DPS: float = 50.0

static var DAMAGE_MULTIPLIERS: Dictionary = {
	UnitManager.Type.TANK: {
		UnitManager.Type.AERIAL: 5.0,
	},
	UnitManager.Type.AERIAL: {
		UnitManager.Type.ZOOMBA: 0.9,
		UnitManager.Type.AERIAL: 1.0,
		UnitManager.Type.VIRUS: 2.0,
	},
	UnitManager.Type.VIRUS: {
		UnitManager.Type.TANK: 2.0,
	},
}

const BUILDING_DAMAGE_BONUS: Dictionary = {
	UnitManager.Type.AERIAL: 2.0,
}

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

static func get_damage(attacker_type: UnitManager.Type, target) -> float:
	var defender_type: UnitManager.Type = UnitManager.Type.NONE
	var multiplier := 1.0
	if target is Unit:
		defender_type = target.type
		var row: Dictionary = DAMAGE_MULTIPLIERS.get(attacker_type, {})
		multiplier = row.get(defender_type, 1.0)
	elif target is Building:
		multiplier = BUILDING_DAMAGE_BONUS.get(attacker_type, 1.0)
	return BASE_DPS * multiplier

# --- Players ---

static var PLAYER_COLORS: Array[Color] = [
	Color.RED,
	Color.GREEN,
	Color.YELLOW,
	Color.ORANGE_RED,
]
