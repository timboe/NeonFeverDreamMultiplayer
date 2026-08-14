extends TerminalHUD

class_name MCPHUD

# --- References ---

var building: Building

# --- Constants ---

# Terminal HUDs refresh at 4 Hz — unit counts and spawn energy only change
# meaningfully on production cadence, not every frame.
const REFRESH_INTERVAL := 0.25

# --- State ---

var _refresh_timer := 0.0

# --- Nodes ---

@onready var count_label: Label = $Window/VBox/ZoombaRow/CountLabel
@onready var avatar_count_label: Label = $Window/VBox/AvatarRow/AvatarCountLabel
@onready var spawn_bar: ProgressBar = $Window/VBox/SpawnRow/SpawnBar
@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn
@onready var empower_indicator: Label = $Window/VBox/EmpowerRow/EmpowerIndicator
@onready var health_bar: ProgressBar = $Window/VBox/HealthBar
@onready var health_value_label: Label = $Window/VBox/HealthRow/HealthValueLabel

# --- Lifecycle ---

func _ready() -> void:
	if not empower_btn:
		return
	empower_btn.pressed.connect(_on_empower_pressed)

func _on_empower_pressed() -> void:
	_empower_building(building)

func _process(delta: float) -> void:
	if not building or not count_label or not health_bar:
		return
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	var mcp := building as MCP
	if not mcp:
		return
	var avatar_count: int = Global.UM.unit_count(mcp.player_owner, UnitManager.Type.AVATAR)
	avatar_count_label.text = str(avatar_count) + " / 1"
	var current: int = Global.UM.unit_count(mcp.player_owner, UnitManager.Type.ZOOMBA)
	var tank_count: int = Global.UM.unit_count(mcp.player_owner, UnitManager.Type.TANK)
	var cap: int = mcp.zoomba_cap()
	# Converted zoombas (TANKs) spend the cap too — show the combined army.
	count_label.text = str(current + tank_count) + " / " + str(cap)
	if current + tank_count >= cap:
		spawn_bar.value = 100.0
	elif mcp._production_cost > 0.0:
		spawn_bar.value = clampf(mcp._production_energy / mcp._production_cost * 100.0, 0.0, 100.0)
	else:
		spawn_bar.value = 0.0
	health_bar.max_value = mcp.max_health
	health_bar.value = mcp.health
	health_value_label.text = str(int(mcp.health)) + " / " + str(int(mcp.max_health))
	_set_empower_indicator(empower_indicator, mcp)
