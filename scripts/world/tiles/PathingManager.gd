extends Node

class_name PathingManager

var astar: AStar3D
var monorail: MonorailMultimesh

var debug_enabled := false
var debug_mesh: ImmediateMesh
var debug_mesh_instance: MeshInstance3D

# --- Lifecycle ---

func _ready() -> void:
	astar = AStar3D.new()
	if debug_enabled:
		_setup_debug()

func _process(_delta: float) -> void:
	if not debug_enabled or not debug_mesh:
		return
	debug_mesh.clear_surfaces()
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	debug_mesh.surface_set_color(Color.RED)
	for id in astar.get_point_ids():
		var from_pos := astar.get_point_position(id)
		for conn_id in astar.get_point_connections(id):
			if id < conn_id:
				debug_mesh.surface_add_vertex(from_pos)
				debug_mesh.surface_add_vertex(astar.get_point_position(conn_id))
	debug_mesh.surface_end()

func toggle_debug() -> void:
	debug_enabled = not debug_enabled
	set_process(debug_enabled)
	if debug_enabled:
		_setup_debug()
	else:
		if debug_mesh_instance:
			debug_mesh_instance.queue_free()
			debug_mesh_instance = null
			debug_mesh = null

func _setup_debug() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	debug_mesh = ImmediateMesh.new()
	debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.mesh = debug_mesh
	debug_mesh_instance.material_override = mat
	add_child(debug_mesh_instance)

# --- Graph operations ---

func add_tile(tile: TileElement) -> void:
	astar.add_point(tile.get_id(), tile.pathing_centre)

func connect_tiles(from: TileElement, to: TileElement, bidirectional: bool = true) -> void:
	astar.connect_points(from.get_id(), to.get_id(), bidirectional)
	if monorail:
		monorail.connect_edge(from, to)
		monorail.cap_raise(from)
		monorail.cap_raise(to)

func disconnect_tiles(a: TileElement, b: TileElement, bidirectional: bool = true) -> void:
	astar.disconnect_points(a.get_id(), b.get_id(), bidirectional)
	if monorail:
		monorail.disconnect_edge(a, b)

func disconnect_tile(tile: TileElement) -> void:
	var tile_id := tile.get_id()
	for conn_id in astar.get_point_connections(tile_id):
		astar.disconnect_points(tile_id, conn_id, true)
	if monorail:
		monorail.disconnect_tile_edges(tile)
		monorail.cap_lower(tile)

# --- Queries ---

func distance(a: TileElement, b: TileElement) -> int:
	var path := pathfind(a, b)
	return max(0, path.size() - 1)

func are_tiles_connected(a: TileElement, b: TileElement) -> bool:
	return pathfind(a, b).size() > 0

func pathfind(from: TileElement, to: TileElement) -> PackedInt64Array:
	return astar.get_id_path(from.get_id(), to.get_id())

func get_point(id: int) -> Vector3:
	return astar.get_point_position(id)

func get_tile(id: int) -> TileElement:
	return get_node("/root/World/TileManager").tile_dictionary[id]
