extends Control

class_name MCPHUD

# --- References ---

var mcp: MCP

@onready var count_label: Label = %CountLabel
@onready var spawn_bar: ProgressBar = %SpawnBar
@onready var empower_btn: Button = %EmpowerBtn

# --- Lifecycle ---

func _process(_delta: float) -> void:
	if not mcp:
		return
	var um = get_node_or_null("/root/World/UnitManager")
	if not um:
		return
	var current: int = um.unit_count(mcp.player_owner, UnitManager.Type.ZOOMBA)
	var cap: int = mcp.zoomba_cap()
	count_label.text = str(current) + " / " + str(cap)
	if mcp.cooldown_ticks > 0:
		var progress := float(MCP.ZOOMBA_CREATION_COOLDOWN_TICKS - mcp.cooldown_ticks) / float(MCP.ZOOMBA_CREATION_COOLDOWN_TICKS) * 100.0
		spawn_bar.value = progress
	elif current >= cap:
		spawn_bar.value = 100.0
	else:
		spawn_bar.value = 0.0
