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
	BuildingManager.Type.BEACON: 2,
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

static var CONSTRUCTION_COST: Dictionary = {
	BuildingManager.Type.GEN: 900.0,
	BuildingManager.Type.VAT: 400.0,
	BuildingManager.Type.GARAGE: 750.0,
	BuildingManager.Type.BEACON: 750.0,
	BuildingManager.Type.NEST: 750.0,
}

# --- Units ---

static var UNIT_SPEED: Dictionary = {
	UnitManager.Type.ZOOMBA: 1.0,
	UnitManager.Type.TANK: 1.0,
	UnitManager.Type.AERIAL_PATROL: 1.0,
	UnitManager.Type.AERIAL_SCOUT: 1.0,
	UnitManager.Type.VIRUS: 1.0,
}

static var UNIT_MAX_HP: Dictionary = {
	UnitManager.Type.ZOOMBA: 50.0,
	UnitManager.Type.AVATAR: 200.0,
}

static var HOME_TERRITORY_UNITS: Array[int] = [
	UnitManager.Type.ZOOMBA,
	UnitManager.Type.TANK,
	UnitManager.Type.AERIAL_PATROL,
]

# --- Players ---

static var PLAYER_COLORS: Array[Color] = [
	Color.RED,
	Color.PURPLE,
	Color.YELLOW,
	Color.GREEN,
]
