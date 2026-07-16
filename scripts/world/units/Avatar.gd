extends Unit

class_name Avatar

const GRAVITY = -60
var vel = Vector3()
const MAX_SPEED = 20
const JUMP_SPEED = 18
const ACCEL = 4.5

var dir = Vector3()
var jaggies : float = 0
var mouse_initial : bool = true

const JAGGIES_UPDATE := 0.05

const DEACCEL= 16
const MAX_SLOPE_ANGLE = 40

@onready var fps_body : CharacterBody3D = $FPSBody
@onready var camera : Camera3D = $FPSBody/Rotation_Helper/FPSCamera
@onready var rotation_helper : Node3D = $FPSBody/Rotation_Helper
@onready var ray : RayCast3D = $FPSBody/Rotation_Helper/RayCast
@onready var ray_render : MeshInstance3D = $FPSBody/Rotation_Helper/RayRender
@onready var rand := RandomNumberGenerator.new()

var ray_mesh := ImmediateMesh.new()

func _ready():
	ray_render.mesh = ray_mesh

var MOUSE_SENSITIVITY = 0.4

func _physics_process(delta):
	process_input(delta)
	process_movement(delta)

func process_input(delta):
	if !camera.current:
		return
	
	# ----------------------------------
	# Walking
	dir = Vector3()
	var cam_xform = camera.get_global_transform()

	var input_movement_vector = Vector2()

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
	# ----------------------------------

	# ----------------------------------
	# Jumping
	if fps_body.is_on_floor():
		if Input.is_action_just_pressed("ui_movement_jump"):
			vel.y = JUMP_SPEED
	# ----------------------------------

	# ----------------------------------
	# Capturing/Freeing the cursor
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# ----------------------------------
	
	# Casting and selecting
	if Input.is_mouse_button_pressed(1):
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
		
func draw_jaggy_to(dist : float):
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

func process_movement(delta):
	if !camera.current:
		return
		
	dir.y = 0
	dir = dir.normalized()

	vel.y += delta * GRAVITY

	var hvel = vel
	hvel.y = 0

	var target = dir
	target *= MAX_SPEED

	var accel
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

func _input(event):
	if !camera.current:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotation_helper.rotate_x(deg_to_rad(event.relative.y * MOUSE_SENSITIVITY * -1))
		fps_body.rotate_y(deg_to_rad(event.relative.x * MOUSE_SENSITIVITY) * -1)

		var camera_rot = rotation_helper.rotation_degrees
		camera_rot.x = clamp(camera_rot.x, -70, 70)
		rotation_helper.rotation_degrees = camera_rot

func initialise(b : Building):
	super.initialise(b)
	type = UnitManager.Type.AVATAR
	add_to_group("avatar")
	add_to_group("avatar_player" + str(building.player_owner))

func idle_callback():
	pass # Avatar uses FPS controls, not the idle/pathing system
