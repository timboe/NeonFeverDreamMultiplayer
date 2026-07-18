extends Node

# --- Mesh helpers ---

static func add_faces_edges(mesh_tool: SurfaceTool, edge_tool: SurfaceTool, from: int) -> void:
	mesh_tool.add_index(from)
	mesh_tool.add_index(from + 1)
	mesh_tool.add_index(from + 2)
	mesh_tool.add_index(from)
	mesh_tool.add_index(from + 2)
	mesh_tool.add_index(from + 3)
	edge_tool.add_index(from)
	edge_tool.add_index(from + 1)
	edge_tool.add_index(from + 1)
	edge_tool.add_index(from + 2)
	edge_tool.add_index(from + 2)
	edge_tool.add_index(from + 3)
	edge_tool.add_index(from + 3)
	edge_tool.add_index(from)

static func add_vertex(mesh_tool: SurfaceTool, edge_tool: SurfaceTool, v3: Vector3) -> void:
	mesh_tool.add_vertex(v3)
	edge_tool.add_vertex(v3)

static func add_vertex_alt(mesh_tool: SurfaceTool, edge_tool: SurfaceTool, y: float, v2: Vector2) -> void:
	add_vertex(mesh_tool, edge_tool, Vector3(v2.x, y, v2.y))

static func add_face(mesh_tool: SurfaceTool, edge_tool: SurfaceTool, height: float,
	bl: Vector2, tl: Vector2,
	this_tr: Vector2, br: Vector2) -> void: # var tr otherwise shadows 
	mesh_tool.add_uv(Vector2(0, 0))
	add_vertex(mesh_tool, edge_tool, Vector3(bl.x, 0, bl.y))
	mesh_tool.add_uv(Vector2(0, 1))
	add_vertex(mesh_tool, edge_tool, Vector3(tl.x, height, tl.y))
	mesh_tool.add_uv(Vector2(1, 1))
	add_vertex(mesh_tool, edge_tool, Vector3(this_tr.x, height, this_tr.y))
	mesh_tool.add_uv(Vector2(1, 0))
	add_vertex(mesh_tool, edge_tool, Vector3(br.x, 0, br.y))
