extends MultiMeshInstance3D
# warning_ignore_all:return_value_discarded

@onready var rand := RandomNumberGenerator.new()

enum Mountain {GOING_UP, GOING_DOWN}
enum Slope {STEEP, SHALLOW}
var mountain : int = Mountain.GOING_UP
var slope : int = Slope.STEEP

var current : Array
var next : Array
var initial_mountain_index : int

# Cannot have min=0 here as != 0 tells the shader to do the mountain
const MOUNTAIN_LIMITS := Vector2(0.1, 1.0)
const EXTENT : int = 50
const MORPH_TIME : float = 1.0

func mountain_range(x : float) -> float:
	var s : float
	match slope:
		Slope.STEEP:
			s = rand.randf_range(-0.20, 0.30)
		Slope.SHALLOW:
			s = rand.randf_range(-0.1, 0.20)
	var r : float
	match mountain:
		Mountain.GOING_UP:
			r = x + s
		Mountain.GOING_DOWN:
			r = x - s
	if r >= MOUNTAIN_LIMITS.y:
		r = MOUNTAIN_LIMITS.y
		mountain = Mountain.GOING_DOWN
	elif r <= MOUNTAIN_LIMITS.x:
		r = MOUNTAIN_LIMITS.x
		mountain = Mountain.GOING_UP
	elif rand.randf() > 0.75:
		mountain = Mountain.GOING_UP if rand.randf() > 0.5 else Mountain.GOING_DOWN
		slope = Slope.STEEP if rand.randf() > 0.5 else Slope.SHALLOW
	return r

func update_mountain(i : int, c : Color):
	multimesh.set_instance_custom_data(i, c)

func _ready():
	rand.randomize()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = false
	multimesh.use_custom_data = true
	var grid_mesh_instance : MeshInstance3D = $"../Grid"
	var grid_mesh : Mesh = grid_mesh_instance.mesh.duplicate()
	var materials : Array = []
	materials.push_back( load("res://materials/floor/grid_faces.tres").duplicate() )
	materials.push_back( load("res://materials/floor/grid_edges.tres").duplicate() )
	for m in materials:
		m.set_shader_parameter("SPEED", 1.0)
		m.set_shader_parameter("SHAPE_SIZE", grid_mesh_instance.STEP_SIZE)
		m.set_shader_parameter("SHAPE_LENGTH", grid_mesh_instance.LENGTH)
		m.set_shader_parameter("MOUNTAIN_MAX_HEIGHT", 200.0)
		m.set_shader_parameter("MOUNTAIN_MAX_COLOUR", 0.25) # Fraction of height
		m.set_shader_parameter("MOUNTAIN_TOP_COLOUR", Color.MAGENTA)
		m.set_shader_parameter("SCROLL", true)
	grid_mesh.surface_set_material(0, materials[0])
	grid_mesh.surface_set_material(1, materials[1])
	multimesh.mesh = grid_mesh
	# Done setup - cannot change anything else after increasing instance_count
	initial_mountain_index = -1
	multimesh.instance_count = EXTENT*EXTENT
	var count : int = -1
	for x in range(-EXTENT/2.0, EXTENT/2.0):
		for z in range(-EXTENT/2.0, EXTENT/2.0):
			count += 1
			assert(count < multimesh.instance_count)
			if x == Global.LEVEL.MOUNTAINS and initial_mountain_index == -1:
				initial_mountain_index = count
			multimesh.set_instance_custom_data(count, Color())
			multimesh.set_instance_transform(count, Transform3D(Basis(),
			  Vector3(x * grid_mesh_instance.LENGTH, 0, z * grid_mesh_instance.LENGTH)))
	current = generate_mountain()
	for i in range(EXTENT):
		update_mountain(initial_mountain_index + i, current[i])
	
func generate_mountain() -> Array:
	var array = []
	var previous_mountain : float = 0.1
	for _i in range(EXTENT):
		var custom := Color()
		custom.r = previous_mountain
		custom.g = mountain_range(custom.r)
		custom.b = mountain_range(custom.g)
		custom.a = mountain_range(custom.b)
		previous_mountain = custom.a
		array.push_back(custom)
	return array

func _on_Timer_timeout():
	current = next if !next.is_empty() else current
	next = generate_mountain()
	var tween = create_tween()
	tween.set_parallel(true)
	for i in range(EXTENT):
		var idx = initial_mountain_index + i
		tween.tween_method(func(v): update_mountain(idx, v), current[i], next[i], MORPH_TIME)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
