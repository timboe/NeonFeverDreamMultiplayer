extends Unit

class_name Avatar

# --- Constants ---

const GRAVITY := -60.0
const MAX_SPEED := 20.0
const JUMP_SPEED := 18.0
const ACCEL := 4.5
const DEACCEL := 16.0
const MAX_SLOPE_ANGLE := 40.0
const MOUSE_SENSITIVITY := 0.4
# Max distance from the avatar to a friendly building's tile for its terminal
# to be interactive (DESIGN: FPS terminal interaction range, 2 tiles).
const TERMINAL_INTERACT_RANGE: float = Cairo.UNIT * 2.0
# Max avatar-to-terminal distance for the empower beam. Wider than the FPS
# interact range so the beam holds across the terminal's parking edge; still
# short enough to hide the beam after a respawn at a distant MCP.
const EMPOWER_BEAM_MAX_RANGE: float = TERMINAL_INTERACT_RANGE * 1.5

# --- Nodes ---

@onready var fps_body: CharacterBody3D = $FPSBody
@onready var camera: Camera3D = $FPSBody/Rotation_Helper/FPSCamera
@onready var rotation_helper: Node3D = $FPSBody/Rotation_Helper
@onready var screen_ray: RayCast3D = $FPSBody/Rotation_Helper/FPSCamera/ScreenRay
@onready var zapper: Zapper = $FPSBody/Zapper

# --- State ---

var vel := Vector3()
var dir := Vector3()
var _prev_left_mouse: bool = false
var _cursor_shown: bool = false
var _cursor_ray_timer := 0
# Server-side timestamp of this avatar instance's spawn. Used by GameManager to
# reject buffered avatar snapshots from the previous incarnation after respawn.
var server_spawn_time: float = 0.0

# --- Lifecycle ---

func _physics_process(delta: float) -> void:
	if not Global.game_started:
		return
	_process_input(delta)
	_process_movement(delta)

func _process(delta: float) -> void:
	super._process(delta)
	_update_empower_beam()

func _input(event: InputEvent) -> void:
	if not Global.game_started:
		return
	if not camera.current:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotation_helper.rotate_x(deg_to_rad(event.relative.y * MOUSE_SENSITIVITY * -1))
		fps_body.rotate_y(deg_to_rad(event.relative.x * MOUSE_SENSITIVITY) * -1)
		var camera_rot = rotation_helper.rotation_degrees
		camera_rot.x = clamp(camera_rot.x, -70, 70)
		rotation_helper.rotation_degrees = camera_rot

func initialise(b: Building) -> void:
	super.initialise(b)
	type = UnitManager.Type.AVATAR
	server_spawn_time = Time.get_ticks_usec() / 1e6
	_health_bar.set_bar_size(3.0, 0.3)
	_health_bar.reparent(fps_body)
	_health_bar.position = Vector3(0, 5.0, 0)
	health = Config.UNIT_MAX_HP.get(type, 100.0)
	add_to_group("avatar")
	add_to_group("avatar_player" + str(player_owner))

func idle_callback() -> void:
	pass # Avatar uses FPS controls, not the idle/pathing system

# --- Input ---

func _process_input(_delta: float) -> void:
	if not camera.current:
		return

	# Walking
	dir = Vector3()
	var cam_xform = camera.get_global_transform()
	var input_movement_vector := Vector2()
	if Input.is_action_pressed("ui_movement_forward"):
		input_movement_vector.y += 1
	if Input.is_action_pressed("ui_movement_backward"):
		input_movement_vector.y -= 1
	if Input.is_action_pressed("ui_movement_left"):
		input_movement_vector.x -= 1
	if Input.is_action_pressed("ui_movement_right"):
		input_movement_vector.x += 1
	input_movement_vector = input_movement_vector.normalized()
	# Basis vectors are already normalized.
	dir += -cam_xform.basis.z * input_movement_vector.y
	dir += cam_xform.basis.x * input_movement_vector.x

	# Jumping
	if fps_body.is_on_floor():
		if Input.is_action_just_pressed("ui_movement_jump"):
			vel.y = JUMP_SPEED

	# Capturing/Freeing the cursor
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Screen cursor
	_update_screen_cursor()

# --- Movement ---

func _process_movement(delta: float) -> void:
	if not camera.current:
		return

	dir.y = 0
	dir = dir.normalized()
	vel.y += delta * GRAVITY

	var hvel := vel
	hvel.y = 0

	var target := dir
	target *= MAX_SPEED

	var accel: float
	if dir.dot(hvel) > 0:
		accel = ACCEL
	else:
		accel = DEACCEL

	hvel = hvel.lerp(target, accel * delta)
	vel.x = hvel.x
	vel.z = hvel.z
	fps_body.floor_max_angle = deg_to_rad(MAX_SLOPE_ANGLE)
	fps_body.velocity = vel
	fps_body.move_and_slide()
	vel = fps_body.velocity

# --- Visual ---

func _update_screen_cursor() -> void:
	# While a cursor is shown, scan every physics frame (clicks need fresh
	# sampling). Otherwise idle-scan at 10 Hz — clicks in empty space do
	# nothing, so the reduced rate only delays the cursor's first appearance
	# by one interval.
	if _cursor_shown:
		_run_cursor_scan()
	else:
		_cursor_ray_timer += 1
		if _cursor_ray_timer >= 6:
			_cursor_ray_timer = 0
			_run_cursor_scan()

func _run_cursor_scan() -> void:
	screen_ray.force_raycast_update()
	var left_mouse := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var just_clicked := left_mouse and not _prev_left_mouse
	var just_released := not left_mouse and _prev_left_mouse
	_prev_left_mouse = left_mouse
	if just_released:
		_release_all_hud_cursors()
	if not screen_ray.is_colliding():
		_hide_all_hud_cursors()
		return
	var col := screen_ray.get_collider()
	if col and col.name == "ScreenBody":
		var terminal: Node = col.get_parent()
		if terminal and terminal.visible:
			# The ScreenBody collider's parent is the Terminal root; the actual
			# display plane (and its material texture) is the "Screen" child.
			var screen_mesh := terminal.get_node_or_null("Screen") as MeshInstance3D
			var building := terminal.get_parent() as Building
			if screen_mesh and building and building.player_owner == Global.my_player_number:
				if fps_body.global_position.distance_to(building.location.pathing_centre) > TERMINAL_INTERACT_RANGE:
					_hide_all_hud_cursors()
					return
				var hud_root := building.get_node_or_null("BuildingHUD/Root")
				if hud_root and hud_root.has_method("uv_from_collision"):
					var uv: Vector2 = hud_root.uv_from_collision(screen_mesh, screen_ray.get_collision_point())
					_cursor_shown = true
					hud_root.drive_cursor_at_uv(uv, left_mouse, just_clicked, just_released)
					return
	_hide_all_hud_cursors()

func _release_all_hud_cursors() -> void:
	if not _cursor_shown:
		return
	for b in get_tree().get_nodes_in_group("building"):
		var hud_root := b.get_node_or_null("BuildingHUD/Root")
		if hud_root and hud_root.has_method("release_cursor"):
			hud_root.release_cursor()

func _hide_all_hud_cursors() -> void:
	if not _cursor_shown:
		return
	_cursor_shown = false
	for b in get_tree().get_nodes_in_group("building"):
		var hud_root := b.get_node_or_null("BuildingHUD/Root")
		if hud_root and hud_root.has_method("hide_cursor"):
			hud_root.hide_cursor()

# --- Empower beam ---

# While the player has a building empowered, fire the avatar's zapper into that
# building's terminal screen. Runs on every peer: the empowered building
# (is_empowered, synced via the reliable rpc_set_empowered), its terminal
# transform (deterministic position_terminal), and the avatar's FPSBody
# transform (locally driven or relayed via avatar snapshots) are all
# identical everywhere, so every peer draws the same beam with no extra sync.
func _update_empower_beam() -> void:
	if zapper == null:
		return
	var target: Building = _find_empowered_building()
	if target == null or not is_instance_valid(target) or not target.visible:
		zapper.visible = false
		return
	var terminal := target.get_node_or_null("Terminal") as Node3D
	if terminal == null:
		zapper.visible = false
		return
	var screen := terminal.get_node_or_null("Screen") as Node3D
	var terminal_pos: Vector3 = screen.global_position if screen else terminal.global_position
	var origin := zapper.global_position
	var dist := origin.distance_to(terminal_pos)
	if dist <= 0.001 or dist > EMPOWER_BEAM_MAX_RANGE:
		zapper.visible = false
		return
	zapper.visible = true
	# Align the zapper's local +Y (its beam axis) on the terminal screen by
	# building the basis explicitly — look_at's front-axis convention varies
	# and got the beam pointing away from the terminal.
	var zap_dir := (terminal_pos - origin).normalized()
	var up_ref := Vector3.UP if abs(zap_dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x_axis := up_ref.cross(zap_dir).normalized()
	var z_axis := x_axis.cross(zap_dir)
	zapper.global_transform = Transform3D(Basis(x_axis, zap_dir, z_axis), origin)
	# The jaggy endpoint is snapped to (0, target_position.y, 0), so an exact
	# distance parks the tip on the screen plane — any overreach punches
	# through the terminal and out the other side.
	zapper.target_position = Vector3(0.0, dist, 0.0)

func _find_empowered_building() -> Building:
	for b in Global.BM.buildings():
		if b.player_owner == player_owner and b.is_empowered:
			return b
	return null
