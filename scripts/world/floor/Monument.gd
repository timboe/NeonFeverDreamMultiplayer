extends StaticBody3D

const GENERATE = false

@onready var beacon : MeshInstance3D 
@onready var mesh_instance : MeshInstance3D = $MeshInstance
@onready var cylinder : CylinderMesh 
@onready var helper = preload("res://scripts/world/floor/MonumentHelper.gd")
 

var time : float = 0

func add_monument(mesh_tool : SurfaceTool, edge_tool : SurfaceTool,	LENGTH : float, HEIGHT : float, CENTRE : float):
		
	helper.add_face(mesh_tool, edge_tool, HEIGHT,
		Vector2(0,0), Vector2(LENGTH, LENGTH),
		Vector2(LENGTH, LENGTH + CENTRE), Vector2(0, LENGTH + LENGTH + CENTRE))
	
	helper.add_face(mesh_tool, edge_tool, HEIGHT,
		Vector2(0, LENGTH + LENGTH + CENTRE), Vector2(LENGTH, LENGTH + CENTRE),
		Vector2(LENGTH + CENTRE, LENGTH + CENTRE), Vector2(LENGTH + LENGTH + CENTRE, LENGTH + LENGTH + CENTRE))
	
	helper.add_face(mesh_tool, edge_tool, HEIGHT,
		Vector2(LENGTH + LENGTH + CENTRE, LENGTH + LENGTH + CENTRE), Vector2(LENGTH + CENTRE, LENGTH + CENTRE),
		Vector2(LENGTH + CENTRE, LENGTH), Vector2(LENGTH + LENGTH + CENTRE, 0))

	helper.add_face(mesh_tool, edge_tool, HEIGHT,
		Vector2(LENGTH + LENGTH + CENTRE, 0), Vector2(LENGTH + CENTRE, LENGTH),
		Vector2(LENGTH, LENGTH), Vector2(0, 0))
	
	# Top
	mesh_tool.add_uv(Vector2(0, 0))
	helper.add_vertex(mesh_tool, edge_tool, Vector3(LENGTH, HEIGHT, LENGTH))
	mesh_tool.add_uv(Vector2(0, 1))
	helper.add_vertex(mesh_tool, edge_tool, Vector3(LENGTH + CENTRE, HEIGHT, LENGTH ))
	mesh_tool.add_uv(Vector2(1, 1))
	helper.add_vertex(mesh_tool, edge_tool, Vector3(LENGTH + CENTRE, HEIGHT, LENGTH + CENTRE))
	mesh_tool.add_uv(Vector2(1, 0))
	helper.add_vertex(mesh_tool, edge_tool, Vector3(LENGTH, HEIGHT, LENGTH + CENTRE))

		
func _ready():
	var LENGTH : float = 20.0
	var HEIGHT : float = 20.0
	var CENTRE : float = 10.0
	if GENERATE:
		var edge_tool = SurfaceTool.new()
		var mesh_tool = SurfaceTool.new()
		edge_tool.begin(Mesh.PRIMITIVE_LINES)
		edge_tool.add_color(Color.CYAN)
		mesh_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var faces := 4 
		add_monument(mesh_tool, edge_tool, LENGTH, HEIGHT, CENTRE)
		# Faces
		for f in range(0, (faces+1)*4, 4):
			helper.add_faces_edges(mesh_tool, edge_tool, f)
			
		mesh_tool.generate_normals()
		mesh_tool.generate_tangents()
		var m : ArrayMesh = mesh_tool.commit()
		edge_tool.index()
		edge_tool.commit(m)  
		#
		var face_mat = load("res://materials/grid_faces.tres")
		var edge_mat = load("res://materials/grid_edges.tres")
		#
		m.surface_set_material(0, face_mat)
		m.surface_set_material(1, edge_mat)
		mesh_instance.set_mesh(m)
		mesh_instance.create_convex_collision()
		
	beacon = $Beacon
	beacon.transform = Transform3D.IDENTITY
	cylinder = beacon.mesh as CylinderMesh 
	cylinder.height = 2000
	beacon.position = Vector3(LENGTH + CENTRE/2.0, HEIGHT + cylinder.height/2.0, LENGTH + CENTRE/2.0)
	var particles : GPUParticles3D = $Particles
	particles.transform = Transform3D.IDENTITY
	particles.position = Vector3(LENGTH + CENTRE/2.0, HEIGHT + 100, LENGTH + CENTRE/2.0)
	
func _process(delta : float):
	time += delta
	if cylinder:
		cylinder.top_radius = abs(sin(time)) + 0.5
		cylinder.bottom_radius = cylinder.top_radius
