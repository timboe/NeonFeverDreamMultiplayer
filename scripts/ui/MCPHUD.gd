extends Control

class_name MCPHUD

const SCREEN_SIZE: float = 1.5
const CURSOR_OFFSET: float = 0.05

# --- References ---

var mcp: MCP

@onready var count_label: Label = %CountLabel
@onready var spawn_bar: ProgressBar = %SpawnBar
@onready var empower_btn: Button = %EmpowerBtn

# --- Cursor (3D) ---

var _cursor_sprite: Sprite3D
var _screen_mesh: MeshInstance3D
var _viewport: SubViewport

func setup_cursor_3d(screen: MeshInstance3D) -> void:
	_screen_mesh = screen
	_viewport = get_viewport() as SubViewport
	_cursor_sprite = Sprite3D.new()
	_cursor_sprite.texture = preload("res://images/cursor.png")
	_cursor_sprite.pixel_size = 0.005
	_cursor_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cursor_sprite.no_depth_test = true
	_cursor_sprite.visible = false
	_cursor_sprite.extra_cull_margin = 1000.0
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = preload("res://images/cursor.png")
	mat.render_priority = 10
	_cursor_sprite.material_override = mat
	get_tree().current_scene.add_child(_cursor_sprite)

	empower_btn.pressed.connect(_on_empower_pressed)

func _on_empower_pressed() -> void:
	print("Empower button pressed!")

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
	if not _cursor_sprite or not _screen_mesh:
		return
	_cursor_sprite.visible = true
	var local := Vector3(
		(uv.x - 0.5) * SCREEN_SIZE,
		0.0,
		(0.5 - uv.y) * SCREEN_SIZE
	)
	var cursor_pos := _screen_mesh.to_global(local)
	var cam_manager = get_node_or_null("/root/World/CameraManager")
	if cam_manager and cam_manager.avatar:
		var cam: Camera3D = cam_manager.avatar.camera
		if cam:
			var to_cam := (cam.global_position - cursor_pos).normalized()
			_cursor_sprite.global_position = cursor_pos + to_cam * CURSOR_OFFSET
			return
	_cursor_sprite.global_position = cursor_pos

func hide_cursor() -> void:
	if _cursor_sprite:
		_cursor_sprite.visible = false

func click_at_uv(uv: Vector2) -> void:
	if not _viewport:
		return
	var vp_size := Vector2(_viewport.size)
	var pos := Vector2(uv.x, 1.0 - uv.y) * vp_size
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	_viewport.push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	_viewport.push_input(up)

func uv_from_collision(screen_mesh: MeshInstance3D, collision_point: Vector3) -> Vector2:
	var local: Vector3 = screen_mesh.global_transform.affine_inverse() * collision_point
	var half := SCREEN_SIZE * 0.5
	return Vector2(
		clampf((local.x + half) / SCREEN_SIZE, 0.0, 1.0),
		clampf((half - local.z) / SCREEN_SIZE, 0.0, 1.0)
	)
