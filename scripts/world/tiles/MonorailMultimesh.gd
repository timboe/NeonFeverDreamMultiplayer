extends MultiMeshInstance3D
class_name MonorailMultimesh

# --- Constants ---

const HIDE_DEPTH: float = -3.0
const CONNECT_TIME: float = 0.5
const DISCONNECT_TIME: float = 0.2

# --- State ---

var edge_dict: Dictionary = {}
var tile_edges: Dictionary = {}
var _active_tweens: Dictionary = {}
var _monorail_body: StaticBody3D
var _shape: ConcavePolygonShape3D
var _mesh_center: Vector3 = Vector3.ZERO

var _cap_mm: MultiMeshInstance3D
var _cap_dict: Dictionary = {}
var _cap_active_tweens: Dictionary = {}

var _loading := true

# --- Lifecycle ---

func setup(tile_dictionary: Dictionary) -> void:
	if multimesh != null:
		return
	_loading = true

	var rail_mesh := _extract_monorail_mesh()

	var seen: Dictionary = {}
	for tile in tile_dictionary.values():
		for n in tile.neighbours:
			if not tile_dictionary.has(n.get_id()):
				continue
			var key := _edge_key(tile.get_id(), n.get_id())
			seen[key] = true
	var edge_count := seen.size()
	seen.clear()

	if edge_count == 0:
		return

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = rail_mesh
	multimesh.mesh.surface_set_material(0, preload("res://materials/chrome.tres"))
	multimesh.instance_count = edge_count

	_monorail_body = StaticBody3D.new()
	_monorail_body.name = "MonorailBody"
	add_child(_monorail_body)
	_shape = _build_collision_shape(rail_mesh)

	var mm_id := 0
	for tile in tile_dictionary.values():
		for n in tile.neighbours:
			if not tile_dictionary.has(n.get_id()):
				continue
			var key := _edge_key(tile.get_id(), n.get_id())
			if edge_dict.has(key):
				continue

			var xform := _compute_edge_transform(tile.pathing_centre, n.pathing_centre)
			xform.origin.y = HIDE_DEPTH

			multimesh.set_instance_transform(mm_id, xform)

			var collision := CollisionShape3D.new()
			collision.shape = _shape
			var col_xform := xform
			col_xform.origin = xform.origin + xform.basis * _mesh_center
			collision.transform = col_xform
			_monorail_body.add_child(collision)

			edge_dict[key] = {"mm_id": mm_id, "collision": collision}
			_add_edge_to_tile(tile.get_id(), key)
			_add_edge_to_tile(n.get_id(), key)

			mm_id += 1

func cap_setup(tile_dictionary: Dictionary, cap_node: MultiMeshInstance3D) -> void:
	_cap_mm = cap_node
	if _cap_mm.multimesh != null:
		return

	var scene = preload("res://scenes/csg_bases/Cap_CSG.tscn").instantiate()
	var cap_mesh: Mesh = scene.mesh if scene is MeshInstance3D else CylinderMesh.new()
	scene.queue_free()

	var tile_count := tile_dictionary.size()
	if tile_count == 0:
		return

	_cap_mm.multimesh = MultiMesh.new()
	_cap_mm.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_cap_mm.multimesh.mesh = cap_mesh
	_cap_mm.multimesh.instance_count = tile_count

	var mm_id := 0
	for tile_id in tile_dictionary:
		var tile: TileElement = tile_dictionary[tile_id]
		var pos := tile.pathing_centre
		pos.y = HIDE_DEPTH
		_cap_mm.multimesh.set_instance_transform(mm_id, Transform3D(Basis.IDENTITY, pos))
		_cap_dict[tile_id] = mm_id
		mm_id += 1

func finish_setup() -> void:
	_loading = false

# --- Public: edges ---

func connect_edge(from_id: int, to_id: int) -> void:
	_connect_edge_impl(from_id, to_id)
	if not _loading and multiplayer.is_server():
		get_parent().rpc("rpc_monorail_connect_edge", from_id, to_id)

func disconnect_edge(from_id: int, to_id: int) -> void:
	_disconnect_edge_impl(from_id, to_id)
	if not _loading and multiplayer.is_server():
		get_parent().rpc("rpc_monorail_disconnect_edge", from_id, to_id)

func disconnect_tile_edges(tile_id: int) -> void:
	_disconnect_tile_edges_impl(tile_id)
	if not _loading and multiplayer.is_server():
		get_parent().rpc("rpc_monorail_disconnect_tile_edges", tile_id)

# --- Public: caps ---

func cap_raise(tile_id: int) -> void:
	_cap_raise_impl(tile_id)
	if not _loading and multiplayer.is_server():
		get_parent().rpc("rpc_monorail_cap_raise", tile_id)

func cap_lower(tile_id: int) -> void:
	_cap_lower_impl(tile_id)
	if not _loading and multiplayer.is_server():
		get_parent().rpc("rpc_monorail_cap_lower", tile_id)

# --- Internal: edge impl ---

func _connect_edge_impl(from_id: int, to_id: int) -> void:
	var key := _edge_key(from_id, to_id)
	if not edge_dict.has(key):
		return
	var data: Dictionary = edge_dict[key]
	var mm_id: int = data["mm_id"]
	var current_y := multimesh.get_instance_transform(mm_id).origin.y
	if current_y >= 0.0:
		return
	if _loading:
		_set_instance_y(mm_id, data["collision"], 0.0)
	else:
		_tween_edge(mm_id, data["collision"], 0.0, CONNECT_TIME)

func _disconnect_edge_impl(from_id: int, to_id: int) -> void:
	var key := _edge_key(from_id, to_id)
	if not edge_dict.has(key):
		return
	var data: Dictionary = edge_dict[key]
	var mm_id: int = data["mm_id"]
	var current_y := multimesh.get_instance_transform(mm_id).origin.y
	if current_y <= HIDE_DEPTH:
		return
	if _loading:
		_set_instance_y(mm_id, data["collision"], HIDE_DEPTH)
	else:
		_tween_edge(mm_id, data["collision"], HIDE_DEPTH, DISCONNECT_TIME)

func _disconnect_tile_edges_impl(tile_id: int) -> void:
	if not tile_edges.has(tile_id):
		return
	for key: Vector2i in tile_edges[tile_id]:
		if not edge_dict.has(key):
			continue
		var data: Dictionary = edge_dict[key]
		var mm_id: int = data["mm_id"]
		var current_y := multimesh.get_instance_transform(mm_id).origin.y
		if current_y <= HIDE_DEPTH:
			continue
		if _loading:
			_set_instance_y(mm_id, data["collision"], HIDE_DEPTH)
		else:
			_tween_edge(mm_id, data["collision"], HIDE_DEPTH, DISCONNECT_TIME)

# --- Internal: cap impl ---

func _cap_raise_impl(tile_id: int) -> void:
	if not _cap_dict.has(tile_id):
		return
	var mm_id: int = _cap_dict[tile_id]
	var current_y := _cap_mm.multimesh.get_instance_transform(mm_id).origin.y
	if current_y >= 0.0:
		return
	if _loading:
		_set_cap_y(mm_id, 0.0)
	else:
		_tween_cap(mm_id, 0.0, CONNECT_TIME)

func _cap_lower_impl(tile_id: int) -> void:
	if not _cap_dict.has(tile_id):
		return
	var mm_id: int = _cap_dict[tile_id]
	var current_y := _cap_mm.multimesh.get_instance_transform(mm_id).origin.y
	if current_y <= HIDE_DEPTH:
		return
	if _loading:
		_set_cap_y(mm_id, HIDE_DEPTH)
	else:
		_tween_cap(mm_id, HIDE_DEPTH, DISCONNECT_TIME)

# --- Internal: edge visual helpers ---

func _set_instance_y(mm_id: int, collision: CollisionShape3D, y: float) -> void:
	var t := multimesh.get_instance_transform(mm_id)
	t.origin.y = y
	multimesh.set_instance_transform(mm_id, t)
	var ct := collision.transform
	ct.origin.y = y
	collision.transform = ct

func _tween_edge(mm_id: int, collision: CollisionShape3D, target_y: float, duration: float) -> void:
	if _active_tweens.has(mm_id):
		var old: Tween = _active_tweens[mm_id]
		if old and old.is_valid():
			old.kill()
	var start_y := multimesh.get_instance_transform(mm_id).origin.y
	var tween := create_tween()
	_active_tweens[mm_id] = tween
	tween.tween_method(func(y: float):
		_set_instance_y(mm_id, collision, y)
	, start_y, target_y, duration)

# --- Internal: cap visual helpers ---

func _set_cap_y(mm_id: int, y: float) -> void:
	var t := _cap_mm.multimesh.get_instance_transform(mm_id)
	t.origin.y = y
	_cap_mm.multimesh.set_instance_transform(mm_id, t)

func _tween_cap(mm_id: int, target_y: float, duration: float) -> void:
	if _cap_active_tweens.has(mm_id):
		var old: Tween = _cap_active_tweens[mm_id]
		if old and old.is_valid():
			old.kill()
	var start_y := _cap_mm.multimesh.get_instance_transform(mm_id).origin.y
	var tween := create_tween()
	_cap_active_tweens[mm_id] = tween
	tween.tween_method(func(y: float):
		_set_cap_y(mm_id, y)
	, start_y, target_y, duration)

# --- Internal: edge utilities ---

func _edge_key(id_a: int, id_b: int) -> Vector2i:
	return Vector2i(mini(id_a, id_b), maxi(id_a, id_b))

func _add_edge_to_tile(tile_id: int, key: Vector2i) -> void:
	if not tile_edges.has(tile_id):
		tile_edges[tile_id] = []
	if key not in tile_edges[tile_id]:
		tile_edges[tile_id].append(key)

func _compute_edge_transform(from_pos: Vector3, to_pos: Vector3) -> Transform3D:
	var midpoint := (from_pos + to_pos) * 0.5
	var direction := to_pos - from_pos
	direction.y = 0.0
	var angle := atan2(-direction.z, direction.x)
	var the_basis := Basis(Vector3.UP, angle)
	var origin := midpoint - the_basis * _mesh_center
	return Transform3D(the_basis, origin)

# --- Mesh extraction ---

const _SNAP := 1000.0

func _extract_monorail_mesh() -> Mesh:
	var scene = preload("res://scenes/csg_bases/Monorail_CSG.tscn").instantiate()
	var csg = scene.get_node_or_null("CSGCombiner")
	if csg == null or not csg is CSGCombiner3D:
		scene.queue_free()
		return preload("res://meshes/rail_centre.tres")

	var csg_xform: Transform3D = csg.transform
	var entries: Array[Array] = []
	for child in csg.get_children():
		if not child is CSGMesh3D:
			continue
		var mesh: Mesh = child.mesh
		if mesh == null:
			continue
		var world_xform: Transform3D = csg_xform * child.transform
		entries.append([mesh, world_xform])
	scene.queue_free()

	var result := _weld_entries(entries)
	if result == null or result.get_aabb().size.length_squared() < 0.001:
		return preload("res://meshes/rail_centre.tres")

	_mesh_center = result.get_aabb().position + result.get_aabb().size * 0.5
	return result

func _weld_entries(entries: Array[Array]) -> Mesh:
	var out_verts := PackedVector3Array()
	var out_norms := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var out_indices := PackedInt32Array()
	var snap_to_idx: Dictionary = {}
	var vert_count := 0

	for entry in entries:
		var mesh: Mesh = entry[0]
		var xform: Transform3D = entry[1]
		for s in range(mesh.get_surface_count()):
			var mesh_arrays := mesh.surface_get_arrays(s)
			var in_verts: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
			var in_norms: PackedVector3Array = mesh_arrays[Mesh.ARRAY_NORMAL]
			var in_uvs = mesh_arrays[Mesh.ARRAY_TEX_UV]
			var in_idx = mesh_arrays[Mesh.ARRAY_INDEX]

			var local_to_global: Dictionary = {}
			for i in range(in_verts.size()):
				var wp := xform * in_verts[i]
				var wn := (xform.basis * in_norms[i]).normalized() if i < in_norms.size() else Vector3.UP
				var wuv: Vector2 = in_uvs[i] if in_uvs != null and i < in_uvs.size() else Vector2.ZERO
				var key := "%d_%d_%d_%d_%d_%d" % [
					roundi(wp.x * _SNAP), roundi(wp.y * _SNAP), roundi(wp.z * _SNAP),
					roundi(wn.x * _SNAP), roundi(wn.y * _SNAP), roundi(wn.z * _SNAP)]
				if snap_to_idx.has(key):
					local_to_global[i] = snap_to_idx[key]
				else:
					local_to_global[i] = vert_count
					snap_to_idx[key] = vert_count
					out_verts.append(wp)
					out_norms.append(wn)
					out_uvs.append(wuv)
					vert_count += 1

			if in_idx != null:
				for ii in range(in_idx.size()):
					out_indices.append(local_to_global[in_idx[ii]])

	if vert_count == 0:
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(vert_count):
		st.set_normal(out_norms[i])
		st.set_uv(out_uvs[i])
		st.add_vertex(out_verts[i])
	for i in range(0, out_indices.size(), 3):
		st.add_index(out_indices[i])
		st.add_index(out_indices[i + 1])
		st.add_index(out_indices[i + 2])
	st.generate_tangents()
	return st.commit()

func _build_collision_shape(mesh: Mesh) -> ConcavePolygonShape3D:
	var verts := PackedVector3Array()
	var idx_out := PackedInt32Array()
	for s in range(mesh.get_surface_count()):
		var src := mesh.surface_get_arrays(s)
		var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var si = src[Mesh.ARRAY_INDEX]
		if si != null:
			for i in range(sv.size()):
				verts.append(sv[i] - _mesh_center)
			idx_out.append_array(si)
		else:
			var base := verts.size()
			for i in range(sv.size()):
				verts.append(sv[i] - _mesh_center)
			for i in range(sv.size()):
				idx_out.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx_out
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return tmp.create_trimesh_shape()
