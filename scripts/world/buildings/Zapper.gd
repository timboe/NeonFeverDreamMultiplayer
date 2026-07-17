extends RayCast3D

class_name Zapper

# --- Constants ---

const JAGGIES_UPDATE: float = 0.1

# --- Nodes ---

@onready var ray_render: MeshInstance3D = $RayRender
@onready var imm_mesh := ImmediateMesh.new()
@onready var rand := RandomNumberGenerator.new()

# --- State ---

var jaggies: float = 0.0

# --- Lifecycle ---

func _ready() -> void:
	ray_render.mesh = imm_mesh

func _process(delta: float) -> void:
	jaggies += delta
	if jaggies <= JAGGIES_UPDATE:
		return
	jaggies -= JAGGIES_UPDATE

	if not visible:
		imm_mesh.clear_surfaces()
		return

	imm_mesh.clear_surfaces()
	draw_jaggy_to(target_position.y)

# --- Rendering ---

func draw_jaggy_to(dist: float) -> void:
	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	imm_mesh.surface_set_color(Color.WHITE)
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
