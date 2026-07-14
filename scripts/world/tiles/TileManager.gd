extends Node3D
class_name TileManager

enum State {RAISED, FALLING, LOWERED, RISING, DISABLED}

@onready var base_material : ShaderMaterial = preload("res://materials/aluminium.tres")
@onready var outline_material : ShaderMaterial = preload("res://materials/floor/grid_edges.tres")
@onready var disabled_material : StandardMaterial3D = preload("res://materials/disabled.tres")
#@onready var monorail_mm : MultiMeshInstance3D = $MonorailMultimesh
#@onready var building_manager : BuildingManager = $"../BuildingManager"

var generated = false

var tile_id : int = 0
var tile_dictionary : Dictionary

var player_aoe_totals : Dictionary = {} # player_number -> float (split AoE score)
var player_aoe_rings : Dictionary = {} # player_number -> Array[Array[TileElement]] (BFS rings from MCP within AoE)

var rand := RandomNumberGenerator.new()

@onready var tile_script = preload("res://scripts/world/tiles/TileElement.gd")

func tiles():
	return tile_dictionary.values()

func remove_tile_from_pathing(tile : TileElement):
	$PathingManager.disconnect_tile(tile)
	%UnitManager.displace_units_on_tile(tile)
	
func get_tile_by_id(id: int) -> TileElement:
	return tile_dictionary.get(id)

func populate(physics_body_instance : StaticBody3D, rotation_group : String):
	var mesh_instance = MeshInstance3D.new()
	if not Engine.is_editor_hint(): physics_body_instance.set_id(tile_id)
	tile_dictionary[tile_id] = physics_body_instance
	var mat : Material
	if tile_id in Global.LEVEL.IMMUTABLE or not physics_body_instance.visible:
		physics_body_instance.visible = true # Note: was being used as a flag
		mat = disabled_material
		if not Engine.is_editor_hint(): physics_body_instance.set_disabled()
		physics_body_instance.add_to_group("disabled")
	elif tile_id in Global.LEVEL.INVISIBLE:
		# Similar to immutable, but seethrough too
		mesh_instance.visible = false
		if not Engine.is_editor_hint(): physics_body_instance.set_disabled()
		physics_body_instance.add_to_group("invisible")
	else:
		mat = base_material.duplicate()
		physics_body_instance.add_to_group("interactive")
		physics_body_instance.add_to_group(rotation_group)
	tile_id += 1
	mesh_instance.set_mesh($CairoDisabled.mesh) # Doesn't matter which
	mesh_instance.set_surface_override_material(0, mat)
	mesh_instance.set_surface_override_material(1, outline_material)
	physics_body_instance.add_child(mesh_instance)
	physics_body_instance.add_child($CairoDisabled.get_child(0).duplicate())
	var ray := RayCast3D.new()
	ray.position = Vector3(Cairo.UNIT/2.0, Cairo.HEIGHT/2.0, Cairo.UNIT/2.0)
	ray.target_position = Vector3(50.0, 0, 0)
	physics_body_instance.add_child(ray)
	physics_body_instance.add_to_group("tiles")
	if not Engine.is_editor_hint(): physics_body_instance.delayed_ready()
	
func check_disabled(physics_body_instance : StaticBody3D) -> bool:
	var t_local : Vector3 = physics_body_instance.position
	var t : Vector3 = physics_body_instance.to_global(t_local)
	var distance_v := Vector2()
	var max_outer : float = Global.LEVEL.TRIPLETS*3*Cairo.UNIT*2
	if t.z < 0 or t.x < 0:
		distance_v.x = -min(t.x, t.z)
	if t.z > max_outer or t.x > max_outer:
		distance_v.y = max(t.x, t.z) - max_outer
	var distance = max(distance_v.x, distance_v.y)
	if distance > 0:
		physics_body_instance.visible = false # Used to communicate w below
		if distance > Cairo.UNIT*4 and distance > rand.randf_range(0.0, Cairo.UNIT*8):
			return true
	return false

func add_cluster(xOff : int, yOff : int):
	var spatial : Node3D = Node3D.new()
	var yMod : float = $CairoDisabled.RIGHT_POINT__UP * xOff
	var xMod : float = $CairoDisabled.RIGHT_POINT__UP * yOff
	spatial.position = Vector3(yMod + yOff*($CairoDisabled.TOP_POINT__RIGHT + $CairoDisabled.TOP_POINT__UP), 
		0, xOff*(Cairo.UNIT + Cairo.RIGHT_POINT__RIGHT) - xMod)
	var physics_body_a := StaticBody3D.new() # TL
	var physics_body_b := StaticBody3D.new() # BL
	var physics_body_c := StaticBody3D.new() # BR
	var physics_body_d := StaticBody3D.new() # TR
	physics_body_a.set_script(tile_script)
	physics_body_b.set_script(tile_script)
	physics_body_c.set_script(tile_script)
	physics_body_d.set_script(tile_script)
	physics_body_a.position = Vector3(Cairo.UNIT, -Global.TILE_OFFSET, 0)
	physics_body_b.position = Vector3(Cairo.UNIT, -Global.TILE_OFFSET, 0)
	physics_body_c.position = Vector3(Cairo.UNIT + Cairo.RIGHT_POINT__UP,
		-Global.TILE_OFFSET, Cairo.UNIT + Cairo.RIGHT_POINT__RIGHT)
	physics_body_d.position = Vector3(Cairo.UNIT + Cairo.RIGHT_POINT__UP,
		-Global.TILE_OFFSET, Cairo.UNIT + Cairo.RIGHT_POINT__RIGHT)
	physics_body_b.rotate_y(deg_to_rad(-90.0))
	physics_body_c.rotate_y(deg_to_rad(180.0))
	physics_body_d.rotate_y(deg_to_rad(90.0))
	spatial.add_child(physics_body_a)
	spatial.add_child(physics_body_b)
	spatial.add_child(physics_body_c)
	spatial.add_child(physics_body_d)
	$Tiles.add_child(spatial)
	physics_body_a.queue_free() if check_disabled(physics_body_a) else populate(physics_body_a, "tilesA")
	physics_body_b.queue_free() if check_disabled(physics_body_b) else populate(physics_body_b, "tilesB")
	physics_body_c.queue_free() if check_disabled(physics_body_c) else populate(physics_body_c, "tilesC")
	physics_body_d.queue_free() if check_disabled(physics_body_d) else populate(physics_body_d, "tilesD")

func _generate():
	tile_id = 0
	tile_dictionary.clear()
	rand.set_seed(Global.LEVEL.SEED)
	for i in range(0, $Tiles.get_child_count()):
		$Tiles.get_child(i).queue_free()
	var floor_v := Vector2()
	var border : int = Global.LEVEL.BORDER_TRIPLETS*3
	var arena : int = Global.LEVEL.TRIPLETS*3
	for x in range(-border, (arena*2) + border):
		for y in range(-border - arena, arena + border):
			floor_v = Vector2(floor(x/3.0), floor(y/3.0))
			if (y+border < 0 - floor_v.x  ||  y-border > arena - floor_v.x): continue
			if (x+border < 0 + floor_v.y  ||  x-border > arena + floor_v.y): continue
			add_cluster(x, y)
	set_physics_process(true)
	generated = true

# Called when the node enters the scene tree for the first time.
func _ready():
	#pass
	_generate()

func _physics_process(_delta):
	if not generated:
		return
	set_physics_process(false)
	print("Phys once")
	if Engine.is_editor_hint():
		return
	set_neighbours()
	disabled_tiles_to_multimesh()
	enabled_tiles_to_multimesh()
	apply_loaded_level()
	#add_monorail()

func set_neighbours():
	for tile in get_tree().get_nodes_in_group("tiles"):
		var ray : RayCast3D = tile.get_child(2)
		for _a in range(10):
			ray.force_raycast_update()
			var c = ray.get_collider()
			if c != null and c.has_method("add_neighbour"):
				c.add_neighbour( tile )
				tile.add_neighbour( c )
			ray.rotate_object_local(Vector3.UP, 2.0*PI / 10.0)
		if tile.state == TileManager.State.RAISED:
			assert(tile.neighbours.size() == 5)
		ray.queue_free()
	#var cap : MeshInstance3D = $"../ObjectFactory/MonorailCap"
	#if cap != null:
		#var cap_mm = $MonorailCapMultimesh
		#cap_mm.multimesh = MultiMesh.new()
		#cap_mm.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		#cap_mm.multimesh.mesh = cap.mesh.duplicate()
	var interactive : Array = get_tree().get_nodes_in_group("interactive")
	#if cap != null:
		#cap_mm = $MonorailCapMultimesh
		#cap_mm.multimesh.instance_count = interactive.size()
	#var cap_count := 0
	for tile in interactive:
		var t = tile.get_child(0).get_transform()
		t.origin += Vector3($CairoDisabled.RIGHT_POINT__UP, 0.0, $CairoDisabled.RIGHT_POINT__UP)
		t = tile.get_global_transform() * t
		t.origin.y = 0
		tile.pathing_centre = t.origin
		tile.pathing_manager = $PathingManager
		$PathingManager.add_tile(tile)
		#t.origin.y = -0.6 # to hide - no longer need to hide as not using monorail
		#if cap != null:
			#cap_mm.multimesh.set_instance_transform(cap_count, t)
			#tile.monorail_cap_id = cap_count
			#tile.monorail_cap_mm = cap_mm.multimesh
			#cap_count += 1

func apply_loaded_level():
	for tile in get_tree().get_nodes_in_group("tiles"):
		if tile.get_id() in Global.LEVEL.MCP:
			var player_number = (Global.LEVEL.MCP.find(tile.get_id()) + 1)
			var mcp_type = %BuildingManager.Type.MCP_1
			match player_number:
				1: mcp_type = %BuildingManager.Type.MCP_1
				2: mcp_type = %BuildingManager.Type.MCP_2
				3: mcp_type = %BuildingManager.Type.MCP_3
				4: mcp_type = %BuildingManager.Type.MCP_4
				_: printerr("Unknown player number ", player_number)
			%BuildingManager.place_building(tile, player_number, mcp_type)
		elif tile.get_id() in Global.LEVEL.LOWERED:
			tile.set_lowered()
	%TileManager.recompute_aoe()

func recompute_aoe():
	for t in tiles():
		t.aoe.clear()
		t.gen_count = 0
	var touched := {}
	for b in %BuildingManager.buildings():
		var queue := []
		var visited := {}
		visited[b.location] = true
		queue.append({tile = b.location, depth = 0})
		while queue:
			var entry = queue.pop_front()
			var current = entry.tile as TileElement
			var depth = entry.depth as int
			current.add_to_aoe(b.player_owner)
			if b.type == BuildingManager.Type.GEN:
				current.gen_count += 1
			touched[current] = true
			if depth >= b.get_aoe_radius():
				continue
			for n in current.neighbours:
				if not visited.has(n):
					visited[n] = true
					queue.append({tile = n, depth = depth + 1})

	# player_aoe_totals: each tile contributes 1, split evenly among players with AoE
	player_aoe_totals.clear()
	for t in touched:
		var count = t.aoe.size()
		if count == 0:
			continue
		var share = 1.0 / count
		for p in t.aoe:
			player_aoe_totals[p] = player_aoe_totals.get(p, 0.0) + share

	# player_aoe_rings: BFS from each player's MCP, restricted to their AoE
	player_aoe_rings.clear()
	for pnum in player_aoe_totals:
		var mcp_tile_id = Global.LEVEL.MCP[pnum - 1]
		if not tile_dictionary.has(mcp_tile_id):
			continue
		var mcp_tile = tile_dictionary[mcp_tile_id]
		var rings : Array = [] # Array of Array[TileElement]
		var visited := {}
		visited[mcp_tile] = true
		var current_ring := [mcp_tile]
		while current_ring.size() > 0:
			rings.append(current_ring)
			var next_ring : Array = []
			for tile in current_ring:
				for n in tile.neighbours:
					if not visited.has(n) and pnum in n.aoe:
						visited[n] = true
						next_ring.append(n)
			current_ring = next_ring
		player_aoe_rings[pnum] = rings

	for t in touched: # Un-select anything no longer under AoE
		for s in t.selected_by:
			if s not in t.aoe:
				t.selected_by.erase(s)
	for t in touched:
		t.update_selection_and_aoe_visual()

# Register click on tile to select. Toggle selection for pnum
# WARNING: Do not call directly. Use Global.send_command(player_number, "toggle_tile", [tile_id])
func apply_toggle(pnum: int, toggle_tile_id: int):
	if not tile_dictionary.has(toggle_tile_id):
		print("TileManager.apply_toggle: unknown tile_id ", toggle_tile_id)
		return
	var tile: TileElement = tile_dictionary[toggle_tile_id]
	if tile.state != TileManager.State.RAISED and tile.state != TileManager.State.LOWERED:
		print("TileManager.apply_toggle: tile ", toggle_tile_id, " is not RAISED or LOWERED (state=", tile.state, ")")
		return
	if tile.state == TileManager.State.LOWERED and tile.building != null:
		print("TileManager.apply_toggle: tile ", toggle_tile_id, " is LOWERED but has a building (state=", tile.building, ")")
		return
	var result = tile.toggle_selected_by(pnum)
	if result:
		%JobManager.add_job(pnum, JobManager.Type.TOGGLE_TILE, tile)
	else:
		%JobManager.cancel_job(pnum, JobManager.Type.TOGGLE_TILE, tile)
	tile.update_selection_and_aoe_visual()
	rpc("broadcast_tile_selection", toggle_tile_id, tile.selected_by.duplicate())
		
# NOTE - "selected by" is only strictly needed on the original client and server - not all other nodes.
@rpc("authority", "call_remote", "reliable")
func broadcast_tile_selection(update_tile_id: int, selected_by: Array):
	if not tile_dictionary.has(update_tile_id):
		return
	var tile: TileElement = tile_dictionary[update_tile_id]
	tile.selected_by = selected_by
	tile.update_selection_and_aoe_visual()

@rpc("authority", "call_local")
func rpc_toggle_animation(tile_id: int, mode : int, thunk_distance: float = 0, thunk_time: float = 0, fall_time: float = 0, dest: float = 0):
	if not tile_dictionary.has(tile_id):
		return
	tile_dictionary[tile_id].rpc_toggle_animation(mode, thunk_distance, thunk_time, fall_time, dest)

func disabled_tiles_to_multimesh():
	var disabled := get_tree().get_nodes_in_group("disabled")
	var disabled_mm := $DisabledTileMultimesh
	disabled_mm.multimesh = MultiMesh.new()
	disabled_mm.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	disabled_mm.multimesh.mesh = $CairoDisabled.mesh.duplicate()
	disabled_mm.multimesh.instance_count = disabled.size()
	for i in range(disabled.size()):
		disabled_mm.multimesh.set_instance_transform(i, disabled[i].get_global_transform())
		disabled[i].get_child(0).queue_free()
		
func enabled_tiles_to_multimesh():
	var enabled : Array = get_tree().get_nodes_in_group("interactive")
	var tile_mm : MultiMeshInstance3D = $TileMultimesh
	tile_mm.multimesh = MultiMesh.new()
	tile_mm.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	tile_mm.multimesh.use_colors = true
	tile_mm.multimesh.use_custom_data = true
	var mesh_dup = $CairoEnabled.mesh.duplicate()
	# All these duplicates are not needed?
	#var surface_mat = mesh_dup.surface_get_material(0)
	#if surface_mat:
		#var mat = surface_mat.duplicate()
		#mat.set_shader_parameter(&"use_instance_color", true)
		#mesh_dup.surface_set_material(0, mat)
	#var edge_surface_mat = mesh_dup.surface_get_material(1)
	#if edge_surface_mat:
		#var edge_mat = edge_surface_mat.duplicate()
		#edge_mat.set_shader_parameter(&"use_instance_color", true)
		#mesh_dup.surface_set_material(1, edge_mat)
	mesh_dup.surface_get_material(0).set_shader_parameter(&"use_instance_color", true)
	tile_mm.multimesh.mesh = mesh_dup
	tile_mm.multimesh.instance_count = enabled.size()
	var count = 0
	for i in range(enabled.size()):
		tile_mm.multimesh.set_instance_transform(i, enabled[i].get_global_transform())
		enabled[i].get_child(0).queue_free()
		enabled[i].tile_mm = tile_mm.multimesh
		enabled[i].tile_mm_id = count
		enabled[i].set_tile_mm_emission(0.0)
		enabled[i].set_tile_mm_color(Color.CYAN)
		count += 1
