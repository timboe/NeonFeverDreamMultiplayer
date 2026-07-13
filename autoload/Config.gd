extends Node

static var BUILDING_AOE : Dictionary = {
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

static var UNIT_SPEED : Dictionary = {
	UnitManager.Type.ZOOMBA: 1.0,
	UnitManager.Type.TANK: 1.0,
	UnitManager.Type.AERIAL_PATROL: 1.0,
	UnitManager.Type.AERIAL_SCOUT: 1.0,
	UnitManager.Type.VIRUS: 1.0,
}

static var HOME_TERRITORY_UNITS : Array = [
	UnitManager.Type.ZOOMBA,
	UnitManager.Type.TANK,
	UnitManager.Type.AERIAL_PATROL,
]

static var PLAYER_COLORS : Array[Color] = [
	Color.RED,
	Color.PURPLE,
	Color.YELLOW,
	Color.GREEN,
]
