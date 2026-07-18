extends Control

class_name MCPHUD

const SCREEN_SIZE: float = 1.5

# --- References ---

var mcp: MCP

@onready var count_label: Label = %CountLabel
@onready var spawn_bar: ProgressBar = %SpawnBar
@onready var empower_btn: Button = %EmpowerBtn
@onready var cursor: TextureRect = %Cursor

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

# --- Cursor ---

func show_cursor_at_uv(uv: Vector2) -> void:
	cursor.visible = true
	var vp_size := Vector2(get_viewport().size)
	cursor.position = uv * vp_size - cursor.size * 0.5

func hide_cursor() -> void:
	cursor.visible = false

func uv_from_collision(screen_mesh: MeshInstance3D, collision_point: Vector3) -> Vector2:
	var local: Vector3 = screen_mesh.global_transform.affine_inverse() * collision_point
	var half := SCREEN_SIZE * 0.5
	return Vector2(
		clampf((local.x + half) / SCREEN_SIZE, 0.0, 1.0),
		clampf((half - local.y) / SCREEN_SIZE, 0.0, 1.0)
	)
