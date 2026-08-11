extends Node

class_name PathingManager

# --- State ---

var astar: AStar3D
var monorail: MonorailMultimesh

# Memoized (tile pair) -> path. Any graph mutation (connect/disconnect/add)
# bumps _graph_generation, which clears the cache — a cached path can never
# outlive an edge change, so results stay exactly as fresh as live A* queries.
var _path_cache: Dictionary = {} # int (canonical pair key) -> PackedInt64Array
var _graph_generation := 0

var debug_enabled := false
var debug_mesh: ImmediateMesh
var debug_mesh_instance: MeshInstance3D

# --- Lifecycle ---

func _ready() -> void:
	Global.PM = self
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

func _toggle_debug() -> void:
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

func _bump_generation() -> void:
	_graph_generation += 1
	_path_cache.clear()

func add_tile(tile: TileElement) -> void:
	astar.add_point(tile.get_id(), tile.pathing_centre)
	_bump_generation()

func connect_tiles(from: TileElement, to: TileElement, bidirectional: bool = true) -> void:
	astar.connect_points(from.get_id(), to.get_id(), bidirectional)
	_bump_generation()
	if monorail:
		monorail.connect_edge(from.get_id(), to.get_id())
		monorail.cap_raise(from.get_id())
		monorail.cap_raise(to.get_id())

func disconnect_tile(tile: TileElement) -> void:
	var tile_id := tile.get_id()
	for conn_id in astar.get_point_connections(tile_id):
		astar.disconnect_points(tile_id, conn_id, true)
	_bump_generation()
	if monorail:
		monorail.disconnect_tile_edges(tile_id)
		monorail.cap_lower(tile_id)

# --- Queries ---

func distance(a: TileElement, b: TileElement) -> int:
	var path := pathfind(a, b)
	return max(0, path.size() - 1)

func pathfind(from: TileElement, to: TileElement) -> PackedInt64Array:
	# Directional key: a cached path always starts at `from`. A symmetric key
	# would hand a unit the reverse-direction path — walking it to the end
	# leaves progress == path.size() with path_dest unreached (assert fires in
	# Unit._pathing_callback).
	var key := from.get_id() * 100000 + to.get_id()
	var cached = _path_cache.get(key)
	if cached != null:
		# GDScript packed arrays SHARE their buffer on assignment — a caller
		# resizing its copy (e.g. Unit.path.resize(0)) would corrupt the cache
		# entry and every other aliased copy. Never hand out the cached buffer.
		return cached.duplicate()
	var path := astar.get_id_path(from.get_id(), to.get_id())
	# Store a private copy; the caller receives the fresh array so it can
	# mutate it freely.
	_path_cache[key] = path.duplicate()
	return path

func get_tile(id: int) -> TileElement:
	return Global.TM.tile_dictionary[id]
