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
# Aerial belly-turret elevation ceiling (radians from horizontal): the drone's
# gun can sweep from straight down (tanks) up to 45° to engage same-level and
# higher aerials (PATROL 10u vs STRIKE 16u = max ~39° at adjacent tiles).
const AERIAL_WEAPON_ELEVATION_MAX: float = PI * 0.25
const PROJECTILE_MAX_FLIGHT_TIME: float = 1.0
const WEAPON_BURST_DURATION: float = 0.4
const DAMAGE_TICK_DURATION: float = 0.1
const COMBAT_LOS_MASK: int = 1
# Keep a combat_target through brief LOS flicker (aerial crossing a wall edge,
# LOS-cache recompute) — drop it only after this much *consecutive* failure so
# the unit doesn't thrash into re-scan + re-aim downtime on every frame.
const COMBAT_LOS_GRACE: float = 0.3
# Target-selection stickiness: a candidate must beat the retained current target
# by this much (score units = dmg*10 - health) to steal it. Stops ping-pong
# retargeting between aerials with near-equal scores (one burst ≈ 120 score).
const COMBAT_TARGET_STICKY_MARGIN: float = 25.0

# --- Empower (avatar buffs, per DESIGN) ---

# MCP: zoomba spawn rate +25% (cooldown x0.8), zoomba move/work speed +20%,
# MCP damage reduction -25% while empowered.
const EMPOWER_MCP_SPAWN_RATE_MULT: float = 0.8
const EMPOWER_ZOOMBA_SPEED_MULT: float = 1.2
const EMPOWER_MCP_DAMAGE_MULT: float = 0.75
# Garage: TANK fire rate +25% vs aerial targets (fire interval x0.8) while the
# player has a Garage empowered (type-wide buff).
const EMPOWER_TANK_FIRE_INTERVAL_MULT: float = 0.8
# Beacon: all the player's AERIALs get +30s lifetime (2m -> 2m30s) while a
# Beacon is empowered (type-wide buff).
const EMPOWER_AERIAL_LIFETIME_EXTRA: float = 30.0
# Nest: all the player's VIRUS get +30% speed while a Nest is empowered
# (type-wide buff); TANKs being attacked by those VIRUS are immobilized and
# cannot fire against AERIAL.
const EMPOWER_VIRUS_SPEED_MULT: float = 1.3
# Vat: +50% capacity while empowered (stacks with adjacency bonus) and a 10%
# discount on the player's construction/production energy drains.
const EMPOWER_VAT_CAPACITY_MULT: float = 1.5
const EMPOWER_VAT_SPEND_MULT: float = 0.9

# Interception COMBAT_PERSUE job detection radii. All are multiples of
# Cairo.UNIT (one tile = 10 world units). PATROL detects cloaked VIRUS at
# 3 tiles; STRIKE only on direct overfly (1 tile). Detection uncloaks a
# cloaked VIRUS.
const PATROL_VIRUS_DETECT_RADIUS: float = Cairo.UNIT * 3.0 # PATROL spotting cloaked VIRUS (3 tiles)
const STRIKE_VIRUS_DETECT_RADIUS: float = Cairo.UNIT * 1.0 # STRIKE direct-overfly detection (1 tile)
const TANK_VIRUS_DETECT_RADIUS: float = Cairo.UNIT * 2.0   # TANK seeing an uncloaked VIRUS attacker

# VIRUS uncloak detection (radius + LoS) from the enemy Avatar. Ground spotting
# is mode-dependent per DESIGN: FPS 3-4 tiles, RTS 1 tile.
const AVATAR_VIRUS_DETECT_RADIUS_FPS: float = Cairo.UNIT * 4.0
const AVATAR_VIRUS_DETECT_RADIUS_RTS: float = Cairo.UNIT * 1.0

# VIRUS limpet / cloak behavior.
const VIRUS_TANK_DRAIN_DPS: float = 40.0      # ~10s to kill a full 400 HP TANK
const VIRUS_ATTACH_DELAY: float = 1.0         # delay between attach and drain/effect start
const VIRUS_INFECTION_BASE_DURATION: float = 15.0 # building infection at full 150 HP, prorated by health
const VIRUS_RECLOAK_COOLDOWN: float = 5.0     # re-cloak delay after being uncloaked (spawn or detection)

# VIRUS building infection effects (per DESIGN). No infection cap: an attacker
# may infect any number of a defender's buildings; re-infecting an
# already-infected building refreshes it (remaining time extends by the base
# duration x new strength, strength is replaced). Effect magnitude scales with
# the completing virus's strength (health at attach / 150).
const VIRUS_INFECTION_DURATION: float = 60.0  # active effect expiry; refresh extends
const VIRUS_VAT_DRAIN_DPS: float = 150.0      # per infected Vat in the chain (~7s to empty a solo 1000e store)
const VIRUS_BEACON_POWER_DPS: float = 20.0    # infected Beacon drains the owner's energy store
const VIRUS_BEACON_AERIAL_DPS: float = 25.0   # per DESIGN: DPS to all owner AERIALs
const VIRUS_GARAGE_TANK_SPEED_MULT: float = 2.0   # move-time mult = halves TANK patrol speed
const VIRUS_GARAGE_FIRE_INTERVAL_MULT: float = 5.0 # fire interval x5 = AA fire rate -80%
const VIRUS_NEST_VIRUS_DPS: float = 10.0      # owner VIRUS DoT while on owner territory
const VIRUS_MCP_AERIAL_DAMAGE_MULT: float = 2.0   # infected MCP takes x2 from AERIAL attackers
const VIRUS_CURE_RADIUS: float = Cairo.UNIT * 2.0 # avatar touch range for curing (FPS mode)

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

# Scram movement is a time multiplier on UNIT_SPEED (<1 = faster than normal).
# Was 0.5 (2x speed) — zoomba panics were too frantic; 0.75 ≈ 1.33x.
const SCRAM_TIME_MULTIPLIER: float = 0.75

static var UNIT_MAX_HP: Dictionary = {
	UnitManager.Type.ZOOMBA: 50.0,
	UnitManager.Type.TANK: 400.0,
	UnitManager.Type.AERIAL: 400.0,
	UnitManager.Type.VIRUS: 150.0,
	UnitManager.Type.AVATAR: 200.0,
}

# Finite unit lifetimes in seconds (DESIGN: aerials 2m, virus ~120s health-based).
static var UNIT_LIFETIME: Dictionary = {
	UnitManager.Type.AERIAL: 120.0,
}

static var HOME_TERRITORY_UNITS: Array[int] = [
	UnitManager.Type.ZOOMBA,
	UnitManager.Type.TANK,
	UnitManager.Type.AERIAL,
]

static var SELF_HEALING_UNITS: Array[int] = [
	UnitManager.Type.ZOOMBA,
	UnitManager.Type.TANK,
	UnitManager.Type.AVATAR,
]

# HP/s self-heal rate per self-healing type (DESIGN: zoomba 10, tank 25, avatar 10).
static var SELF_HEAL_RATE: Dictionary = {
	UnitManager.Type.ZOOMBA: 10.0,
	UnitManager.Type.TANK: 25.0,
	UnitManager.Type.AVATAR: 10.0,
}

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

# --- Building targeting ---

# The building types every Beacon/Nest strike considers by default. Matches the
# building-targeting toggle buttons in the terminal HUDs (MCP_1 stands for all
# enemy MCPs).
static var ALL_BUILDING_TARGETS: Array[BuildingManager.Type] = [
	BuildingManager.Type.MCP_1,
	BuildingManager.Type.GEN,
	BuildingManager.Type.VAT,
	BuildingManager.Type.GARAGE,
	BuildingManager.Type.BEACON,
	BuildingManager.Type.NEST,
]

# --- UI theme ---

# Visual accent palette. These values are mirrored in themes/neon_ui.tres
# (Godot themes can't read GDScript constants) — keep the two in sync.
const UI_ACCENT := Color(0, 1, 1)            # base cyan
const UI_ACCENT_HOT := Color(1, 0.25, 0.85)  # synthwave magenta
const UI_BG_PANEL_TOP := Color(0.05, 0.06, 0.11)
const UI_BG_PANEL_BOTTOM := Color(0.02, 0.02, 0.05)
const UI_TEXT_DIM := Color(0.62, 0.68, 0.78)
const UI_SUCCESS := Color(0.25, 1, 0.4)
const UI_WARNING := Color(1, 0.65, 0.1)
const UI_DANGER := Color(1, 0.25, 0.25)

# Accent color for a player (falls back to the base cyan accent when the
# player number is out of range, e.g. spectating).
func player_accent(pnum: int) -> Color:
	if pnum >= 1 and pnum <= PLAYER_COLORS.size():
		return PLAYER_COLORS[pnum - 1]
	return UI_ACCENT

# --- Generator catchment ---

# Colours by tile gen_count — used by the Generator hover emission and the
# Generator HUD "Tiles contributing" breakdown bars.
const CATCHMENT_SINGLE_TILE := Color.GREEN
const CATCHMENT_TWO_TILES := Color.YELLOW
const CATCHMENT_THREE_TILES := Color.ORANGE_RED
const CATCHMENT_OVERLAPPED := Color.RED

func catchment_color(gen_count: int) -> Color:
	match gen_count:
		1: return CATCHMENT_SINGLE_TILE
		2: return CATCHMENT_TWO_TILES
		3: return CATCHMENT_THREE_TILES
		_: return CATCHMENT_OVERLAPPED

# --- Button theming (per-player) ---

# Multipliers used when tinting the main-HUD button states with a player colour.
# Shared between HUD.gd and the terminal HUDs so both stay in sync.
const BUTTON_LIT_ALPHA: float = 0.85
const BUTTON_NORMAL_BORDER_ALPHA: float = 0.5
const BUTTON_NORMAL_GLOW_ALPHA: float = 0.15
const BUTTON_HOVER_GLOW_ALPHA: float = 0.45
const BUTTON_PRESSED_GLOW_ALPHA: float = 0.6
const BUTTON_PRESSED_BG_SCALE: float = 0.45
const BUTTON_FOCUS_BORDER_ALPHA: float = 0.7
const BUTTON_FOCUS_GLOW_ALPHA: float = 0.3
const BUTTON_DISABLED_BORDER_ALPHA: float = 0.3
const BUTTON_DISABLED_GLOW_ALPHA: float = 0.0
const BUTTON_SEPARATOR_ALPHA: float = 0.45
