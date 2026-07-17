extends StaticBody3D

# --- Constants ---

const GENERATE: bool = false

# --- Nodes ---

@onready var beacon: MeshInstance3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance
@onready var cylinder: CylinderMesh
@onready var helper = preload("res://scripts/world/floor/MonumentHelper.gd")

# --- State ---

var time: float = 0.0

# --- Mesh generation (dead code, GENERATE=false) ---

func add_monument(mesh_tool: SurfaceTool, edge_tool: SurfaceTool, p_length: float, p_height: float, p_centre: float) -> void:
	helper.add_face(mesh_tool, edge_tool, p_height,
		Vector2(0, 0), Vector2(p_length, p_length),
		Vector2(p_length, p_length + p_centre), Vector2(0, p_length + p_length + p_centre))

	helper.add_face(mesh_tool, edge_tool, p_height,
		Vector2(0, p_length + p_length + p_centre), Vector2(p_length, p_length + p_centre),
		Vector2(p_length + p_centre, p_length + p_centre), Vector2(p_length + p_length + p_centre, p_length + p_length + p_centre))

	helper.add_face(mesh_tool, edge_tool, p_height,
		Vector2(p_length + p_length + p_centre, p_length + p_length + p_centre), Vector2(p_length + p_centre, p_length + p_centre),
		Vector2(p_length + p_centre, p_length), Vector2(p_length + p_length + p_centre, 0))

	helper.add_face(mesh_tool, edge_tool, p_height,
		Vector2(p_length + p_length + p_centre, 0), Vector2(p_length + p_centre, p_length),
		Vector2(p_length, p_length), Vector2(0, 0))

	mesh_tool.add_uv(Vector2(0, 0))
	helper.add_vertex(mesh_tool, edge_tool, Vector3(p_length, p_height, p_length))
	mesh_tool.add_uv(Vector2(0, 1))
	helper.add_vertex(mesh_tool, edge_tool, Vector3(p_length + p_centre, p_height, p_length))
	mesh_tool.add_uv(Vector2(1, 1))
	helper.add_vertex(mesh_tool, edge_tool, Vector3(p_length + p_centre, p_height, p_length + p_centre))
	mesh_tool.add_uv(Vector2(1, 0))
	helper.add_vertex(mesh_tool, edge_tool, Vector3(p_length, p_height, p_length + p_centre))

# --- Lifecycle ---

func _ready() -> void:
	var p_length: float = 20.0
	var p_height: float = 20.0
	var p_centre: float = 10.0
	if GENERATE:
		var edge_tool := SurfaceTool.new()
		var mesh_tool := SurfaceTool.new()
		edge_tool.begin(Mesh.PRIMITIVE_LINES)
		edge_tool.add_color(Color.CYAN)
		mesh_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var faces := 4
		add_monument(mesh_tool, edge_tool, p_length, p_height, p_centre)
		for f in range(0, (faces + 1) * 4, 4):
			helper.add_faces_edges(mesh_tool, edge_tool, f)
		mesh_tool.generate_normals()
		mesh_tool.generate_tangents()
		var m: ArrayMesh = mesh_tool.commit()
		edge_tool.index()
		edge_tool.commit(m)
		var face_mat = load("res://materials/grid_faces.tres")
		var edge_mat = load("res://materials/grid_edges.tres")
		m.surface_set_material(0, face_mat)
		m.surface_set_material(1, edge_mat)
		mesh_instance.set_mesh(m)
		mesh_instance.create_convex_collision()

	beacon = $Beacon
	beacon.transform = Transform3D.IDENTITY
	cylinder = beacon.mesh as CylinderMesh
	cylinder.height = 2000
	beacon.position = Vector3(p_length + p_centre / 2.0, p_height + cylinder.height / 2.0, p_length + p_centre / 2.0)
	var particles: GPUParticles3D = $Particles
	particles.transform = Transform3D.IDENTITY
	particles.position = Vector3(p_length + p_centre / 2.0, p_height + 100, p_length + p_centre / 2.0)

func _process(delta: float) -> void:
	time += delta
	if cylinder:
		cylinder.top_radius = abs(sin(time)) + 0.5
		cylinder.bottom_radius = cylinder.top_radius
