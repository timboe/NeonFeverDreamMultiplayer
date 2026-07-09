extends RayCast3D

class_name Zapper

@onready var ray_render : MeshInstance3D = $RayRender
@onready var imm_mesh := ImmediateMesh.new()
@onready var rand = RandomNumberGenerator.new()

const JAGGIES_UPDATE := 0.1
var jaggies : float = 0.0

func _ready():
	ray_render.mesh = imm_mesh

func _process(delta : float):
	jaggies += delta
	if jaggies <= JAGGIES_UPDATE:
		return
	jaggies -= JAGGIES_UPDATE
	
	var target : Vector3
	if enabled:
		if is_colliding():
			target = get_collision_point()
		else:
			return
	else:
		target = target_position
	
	imm_mesh.clear_surfaces()
	draw_jaggy_to(target.y)
	
func draw_jaggy_to(dist : float):
	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	imm_mesh.surface_set_color(Color.WHITE)
	imm_mesh.surface_add_vertex(Vector3.ZERO)
	var pos := Vector3.ZERO
	imm_mesh.surface_add_vertex(pos)
	while pos.y < dist:
		pos.x += rand.randf_range(-0.2, 0.2)
		pos.z += rand.randf_range(-0.2, 0.2)
		pos.y += rand.randf_range(-1.0, 3.0)
		if pos.y >= dist:
			pos = Vector3(0, dist, 0)
		imm_mesh.surface_add_vertex(pos)
	imm_mesh.surface_end()
