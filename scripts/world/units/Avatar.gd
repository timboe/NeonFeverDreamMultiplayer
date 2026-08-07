extends Unit

class_name Avatar

const GRAVITY := -60.0
const MAX_SPEED := 20.0
const JUMP_SPEED := 18.0
const ACCEL := 4.5
const DEACCEL := 16.0
const MAX_SLOPE_ANGLE := 40.0
const JAGGIES_UPDATE := 0.05
const MOUSE_SENSITIVITY := 0.4

@onready var fps_body: CharacterBody3D = $FPSBody
@onready var camera: Camera3D = $FPSBody/Rotation_Helper/FPSCamera
@onready var rotation_helper: Node3D = $FPSBody/Rotation_Helper
@onready var ray: RayCast3D = $FPSBody/Rotation_Helper/RayCast
@onready var screen_ray: RayCast3D = $FPSBody/Rotation_Helper/FPSCamera/ScreenRay
@onready var ray_render: MeshInstance3D = $FPSBody/Rotation_Helper/RayRender
@onready var rand := RandomNumberGenerator.new()

var ray_mesh := ImmediateMesh.new()
var vel := Vector3()
var dir := Vector3()
var jaggies: float = 0
var mouse_initial: bool = true
var _prev_left_mouse: bool = false
# Server-side timestamp of this avatar instance's spawn. Used by GameManager to
# reject buffered avatar snapshots from the previous incarnation after respawn.
var server_spawn_time: float = 0.0

# --- Lifecycle ---

func _ready() -> void:
	ray_render.mesh = ray_mesh

func _physics_process(delta: float) -> void:
	if not Global.game_started:
		return
	process_input(delta)
	process_movement(delta)

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

func process_input(delta: float) -> void:
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

	# Casting and selecting
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		jaggies += delta
		ray.force_raycast_update()
		if jaggies > JAGGIES_UPDATE:
			jaggies -= JAGGIES_UPDATE
			ray_mesh.clear_surfaces()
			if ray.is_colliding():
				var local = ray_render.global_transform.affine_inverse() * ray.get_collision_point()
				draw_jaggy_to(local.y)
	else:
		ray_mesh.clear_surfaces()
		mouse_initial = true

	# Screen cursor
	_update_screen_cursor()

# --- Movement ---

func process_movement(delta: float) -> void:
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
	screen_ray.force_raycast_update()
	var left_mouse := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var just_clicked := left_mouse and not _prev_left_mouse
	_prev_left_mouse = left_mouse
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
				var hud_root := building.get_node_or_null("BuildingHUD/Root")
				if hud_root and hud_root.has_method("uv_from_collision"):
					var uv: Vector2 = hud_root.uv_from_collision(screen_mesh, screen_ray.get_collision_point())
					hud_root.show_cursor_at_uv(uv)
					if just_clicked:
						hud_root.click_at_uv(uv)
					return
	_hide_all_hud_cursors()

func _hide_all_hud_cursors() -> void:
	for b in get_tree().get_nodes_in_group("building"):
		var hud_root := b.get_node_or_null("BuildingHUD/Root")
		if hud_root and hud_root.has_method("hide_cursor"):
			hud_root.hide_cursor()

func draw_jaggy_to(dist: float) -> void:
	ray_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	ray_mesh.surface_set_color(Color.WHITE)
	ray_mesh.surface_add_vertex(Vector3.ZERO)
	var pos := Vector3.ZERO
	ray_mesh.surface_add_vertex(pos)
	while pos.y > dist:
		pos.x += rand.randf_range(-0.1, 0.1)
		pos.z += rand.randf_range(-0.1, 0.1)
		pos.y += rand.randf_range(-3.0, 1.0) if pos.y > -5.0 else rand.randf_range(-3.0, 0.0)
		if pos.y <= dist:
			pos = Vector3(0, dist, 0)
		ray_mesh.surface_add_vertex(pos)
	ray_mesh.surface_end()
