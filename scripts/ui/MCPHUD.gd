extends TerminalHUD

class_name MCPHUD

# --- References ---

var building: Building

@onready var count_label: Label = $Window/VBox/ZoombaRow/CountLabel
@onready var spawn_bar: ProgressBar = $Window/VBox/SpawnRow/SpawnBar
@onready var empower_btn: Button = $Window/VBox/Header/EmpowerBtn

func _ready() -> void:
	if not empower_btn:
		return
	empower_btn.pressed.connect(_on_empower_pressed)

func _on_empower_pressed() -> void:
	if building:
		Global.send_command_me("empower", [building.id])

# --- Lifecycle ---

func _process(_delta: float) -> void:
	if not building or not count_label:
		return
	var mcp := building as MCP
	if not mcp:
		return
	var um = Global.UM
	if not um:
		return
	var current: int = um.unit_count(mcp.player_owner, UnitManager.Type.ZOOMBA)
	var cap: int = mcp.zoomba_cap()
	count_label.text = str(current) + " / " + str(cap)
	var cooldown: float = Config.PRODUCTION_COOLDOWNS.get(mcp.type, 10.0)
	if mcp._production_timer > 0.0:
		var progress := (cooldown - mcp._production_timer) / cooldown * 100.0
		spawn_bar.value = progress
	elif current >= cap:
		spawn_bar.value = 100.0
	else:
		spawn_bar.value = 0.0
