extends Node

static func add_faces_edges(mesh_tool : SurfaceTool, edge_tool : SurfaceTool, from : int):
	mesh_tool.add_index(from)
	mesh_tool.add_index(from + 1)
	mesh_tool.add_index(from + 2)
	#
	mesh_tool.add_index(from)
	mesh_tool.add_index(from + 2)
	mesh_tool.add_index(from + 3)
	##
	edge_tool.add_index(from)
	edge_tool.add_index(from + 1)
	#
	edge_tool.add_index(from + 1)
	edge_tool.add_index(from + 2)
	#
	edge_tool.add_index(from + 2)
	edge_tool.add_index(from + 3)
	#
	edge_tool.add_index(from + 3)
	edge_tool.add_index(from)
	
static func add_vertex(mesh_tool : SurfaceTool,edge_tool : SurfaceTool,v3 : Vector3):
	mesh_tool.add_vertex(v3)
	edge_tool.add_vertex(v3)
	
static func add_vertex_alt(mesh_tool : SurfaceTool, edge_tool : SurfaceTool, y : float, v2 : Vector2):
	add_vertex(mesh_tool, edge_tool, Vector3(v2.x, y, v2.y))

static func add_face(mesh_tool : SurfaceTool, edge_tool : SurfaceTool, height : float,
	BL : Vector2, TL : Vector2,
	TR : Vector2, BR : Vector2):
	
	mesh_tool.add_uv(Vector2(0, 0))
	add_vertex(mesh_tool, edge_tool, Vector3(BL.x, 0, BL.y))
	mesh_tool.add_uv(Vector2(0, 1))
	add_vertex(mesh_tool, edge_tool, Vector3(TL.x, height, TL.y))
	mesh_tool.add_uv(Vector2(1, 1))
	add_vertex(mesh_tool, edge_tool, Vector3(TR.x, height, TR.y))
	mesh_tool.add_uv(Vector2(1, 0))
	add_vertex(mesh_tool, edge_tool, Vector3(BR.x, 0, BR.y))
