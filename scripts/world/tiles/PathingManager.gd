extends Node

class_name PathingManager

var astar : AStar3D 

var debug_enabled := true
var debug_mesh: ImmediateMesh
var debug_mesh_instance: MeshInstance3D

func _ready():
	astar = AStar3D.new()
	if debug_enabled:
		_setup_debug()

func _setup_debug():
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	debug_mesh = ImmediateMesh.new()
	debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.mesh = debug_mesh
	debug_mesh_instance.material_override = mat
	add_child(debug_mesh_instance)

func _process(_delta):
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

func toggle_debug():
	debug_enabled = not debug_enabled
	set_process(debug_enabled)
	if debug_enabled:
		_setup_debug()
	else:
		if debug_mesh_instance:
			debug_mesh_instance.queue_free()
			debug_mesh_instance = null
			debug_mesh = null

func add_tile(tile : TileElement):
	astar.add_point( tile.get_id(), tile.pathing_centre )

func disconnect_tiles(a : TileElement, b : TileElement, bidirectional : bool = true):
	astar.disconnect_points(a.get_id(), b.get_id(), bidirectional)

func disconnect_tile(tile : TileElement):
	var tile_id = tile.get_id()
	for conn_id in astar.get_point_connections(tile_id):
		astar.disconnect_points(tile_id, conn_id, true)

func distance(a : TileElement, b : TileElement) -> int:
	return pathfind(a, b).size()

func are_tiles_connected(a : TileElement, b : TileElement) -> bool:
	return (distance(a, b) > 0)

func connect_tiles(from : TileElement, to : TileElement, bidirectional : bool = true):
	astar.connect_points(from.get_id(), to.get_id(), bidirectional) 

func pathfind(from : TileElement, to : TileElement) -> PackedInt64Array:
	return astar.get_id_path(from.get_id(), to.get_id())

func get_point(id : int) -> Vector3:
	return astar.get_point_position(id)
	
func get_tile(id : int) -> TileElement:
	return get_node("/root/World/TileManager").tile_dictionary[id]
