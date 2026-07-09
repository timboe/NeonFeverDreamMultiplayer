extends Node3D
class_name TileManager

@onready var base_material : ShaderMaterial = preload("res://materials/aluminium.tres")
@onready var outline_material : ShaderMaterial = preload("res://materials/floor/grid_edges.tres")
@onready var disabled_material : StandardMaterial3D = preload("res://materials/disabled.tres")
@onready var cairo_disabled = $CairoDisabled
@onready var cairo_enabled = $CairoEnabled
@onready var tiles : Node = $Tiles
@onready var monorail_mm : MultiMeshInstance3D = $MonorailMultimesh
#@onready var building_manager : BuildingManager = $"../BuildingManager"

var generated = false

var tile_id : int = 0
var tile_dictionary : Dictionary

var rand := RandomNumberGenerator.new()

@onready var tile_script = preload("res://scripts/world/tiles/TileElement.gd")

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
	mesh_instance.set_mesh(cairo_disabled.mesh) # Doesn't matter which
	mesh_instance.set_surface_override_material(0, mat)
	mesh_instance.set_surface_override_material(1, outline_material)
	physics_body_instance.add_child(mesh_instance)
	physics_body_instance.add_child(cairo_disabled.get_child(0).duplicate())
	var ray := RayCast3D.new()
	ray.translate(Vector3(cairo_disabled.UNIT/2.0, cairo_disabled.HEIGHT/2.0, cairo_disabled.UNIT/2.0))
	ray.target_position = Vector3(50.0, 0, 0)
	physics_body_instance.add_child(ray)
	physics_body_instance.add_to_group("tiles")
	if not Engine.is_editor_hint(): physics_body_instance.delayed_ready()
	
func check_disabled(physics_body_instance : StaticBody3D) -> bool:
	var t_local : Vector3 = physics_body_instance.position
	var t : Vector3 = physics_body_instance.to_global(t_local)
	var distance_v := Vector2()
	var max_outer : float = Global.LEVEL.TRIPLETS*3*cairo_disabled.UNIT*2
	if t.z < 0 or t.x < 0:
		distance_v.x = -min(t.x, t.z)
	if t.z > max_outer or t.x > max_outer:
		distance_v.y = max(t.x, t.z) - max_outer
	var distance = max(distance_v.x, distance_v.y)
	if distance > 0:
		physics_body_instance.visible = false # Used to communicate w below
		if distance > cairo_disabled.UNIT*4 and distance > rand.randf_range(0.0, cairo_disabled.UNIT*8):
			return true
	return false

func add_cluster(xOff : int, yOff : int):
	var spatial : Node3D = Node3D.new()
	var yMod : float = cairo_disabled.RIGHT_POINT__UP * xOff
	var xMod : float = cairo_disabled.RIGHT_POINT__UP * yOff
	spatial.translate(Vector3(yMod + yOff*(cairo_disabled.TOP_POINT__RIGHT + cairo_disabled.TOP_POINT__UP), 
		0, xOff*(cairo_disabled.UNIT + cairo_disabled.RIGHT_POINT__RIGHT) - xMod))
	var physics_body_a := StaticBody3D.new() # TL
	var physics_body_b := StaticBody3D.new() # BL
	var physics_body_c := StaticBody3D.new() # BR
	var physics_body_d := StaticBody3D.new() # TR
	physics_body_a.set_script(tile_script)
	physics_body_b.set_script(tile_script)
	physics_body_c.set_script(tile_script)
	physics_body_d.set_script(tile_script)
	physics_body_a.translate(Vector3(cairo_disabled.UNIT, -Global.TILE_OFFSET, 0))
	physics_body_b.translate(Vector3(cairo_disabled.UNIT, -Global.TILE_OFFSET, 0))
	physics_body_c.translate(Vector3(cairo_disabled.UNIT + cairo_disabled.RIGHT_POINT__UP,
		-Global.TILE_OFFSET, cairo_disabled.UNIT + cairo_disabled.RIGHT_POINT__RIGHT))
	physics_body_d.translate(Vector3(cairo_disabled.UNIT + cairo_disabled.RIGHT_POINT__UP,
		-Global.TILE_OFFSET, cairo_disabled.UNIT + cairo_disabled.RIGHT_POINT__RIGHT))
	physics_body_b.rotate_y(deg_to_rad(-90.0))
	physics_body_c.rotate_y(deg_to_rad(180.0))
	physics_body_d.rotate_y(deg_to_rad(90.0))
	spatial.add_child(physics_body_a)
	spatial.add_child(physics_body_b)
	spatial.add_child(physics_body_c)
	spatial.add_child(physics_body_d)
	tiles.add_child(spatial)
	physics_body_a.queue_free() if check_disabled(physics_body_a) else populate(physics_body_a, "tilesA")
	physics_body_b.queue_free() if check_disabled(physics_body_b) else populate(physics_body_b, "tilesB")
	physics_body_c.queue_free() if check_disabled(physics_body_c) else populate(physics_body_c, "tilesC")
	physics_body_d.queue_free() if check_disabled(physics_body_d) else populate(physics_body_d, "tilesD")

func _generate():
	tile_id = 0
	tile_dictionary.clear()
	rand.set_seed(Global.LEVEL.SEED)
	for i in range(0, tiles.get_child_count()):
		tiles.get_child(i).queue_free()
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
	#apply_initial_monorail_and_zoomba()

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
		if tile.state == TileElement.State.RAISED:
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
		t.origin += Vector3(cairo_disabled.RIGHT_POINT__UP, 0.0, cairo_disabled.RIGHT_POINT__UP)
		t = tile.get_global_transform() * t
		t.origin.y = 0
		tile.pathing_centre = t.origin
		$PathingManager.add_tile(tile)
		t.origin.y = -0.6 # -0.6 to hide
		#if cap != null:
			#cap_mm.multimesh.set_instance_transform(cap_count, t)
			#tile.monorail_cap_id = cap_count
			#tile.monorail_cap_mm = cap_mm.multimesh
			#cap_count += 1

func apply_loaded_level():
	for tile in get_tree().get_nodes_in_group("tiles"):
		if tile.get_id() in Global.LEVEL.MCP:
			#building_manager.place_building(tile, building_manager.Type.MCP) # need to add player parameter as well
			pass
		elif tile.get_id() in Global.LEVEL.LOWERED:
			tile.set_lowered()

func apply_toggle(pnum: int, tile_id: int):
	if not tile_dictionary.has(tile_id):
		print("TileManager.apply_toggle: unknown tile_id ", tile_id)
		return
	var tile: TileElement = tile_dictionary[tile_id]
	if tile.state != TileElement.State.RAISED:
		print("TileManager.apply_toggle: tile ", tile_id, " is not RAISED (state=", tile.state, ")")
		return
	tile.selected_by[pnum] = not tile.selected_by[pnum]
	tile.update_selection_visual()
	rpc("set_tile_selection", tile_id, tile.selected_by.duplicate())

@rpc("authority", "call_remote", "reliable")
func set_tile_selection(tile_id: int, selected_by: Array):
	if not tile_dictionary.has(tile_id):
		return
	var tile: TileElement = tile_dictionary[tile_id]
	tile.selected_by = selected_by
	tile.update_selection_visual()

#func add_monorail():
	## Our grid is formed of a tesselation of a four-tile primitive.
	## The linking relationships between neighbouring tiles depends on
	## the translation and rotations applied during the tesselation.
	## The four dictionaries below map this for each of the base tiles
	#var tile_groups : Array = ["tilesA", "tilesB", "tilesC", "tilesD"]
	#var monorail_groups : Array = ["mr1", "mr2", "mr3"]
	#var tilesA_mapping : Dictionary = {"mr1": 2, "mr2": 3, "mr3": 4}
	#var tilesB_mapping : Dictionary = {"mr1": 1, "mr2": 0, "mr3": 2}
	#var tilesC_mapping : Dictionary = {"mr1": 4, "mr2": -1, "mr3": 2} # mr2 was 1 (dupe)
	#var tilesD_mapping : Dictionary = {"mr1": 2, "mr2": -1, "mr3": 4} # mr2 was 3 (dupe)
	#var tiles_mapping : Dictionary = {
		#"tilesA": tilesA_mapping, "tilesB": tilesB_mapping,
		#"tilesC": tilesC_mapping, "tilesD": tilesD_mapping}
	#var total_monorails := 0
	#total_monorails += get_tree().get_nodes_in_group("tilesA").size() * 3
	#total_monorails += get_tree().get_nodes_in_group("tilesB").size() * 3
	#total_monorails += get_tree().get_nodes_in_group("tilesC").size() * 2
	#total_monorails += get_tree().get_nodes_in_group("tilesD").size() * 2
	#monorail_mm.multimesh.set_instance_count(total_monorails) # This is high-balling it, due to DISABLED instances
	#var mr_count := 0
	#for tg in tile_groups:
		#for tile in get_tree().get_nodes_in_group(tg):
			#var mapping = tiles_mapping[tg]
			#for mg in monorail_groups:
				## We don't need to make three links from every tile
				## Some are dupes. These are given -1 above
				#var neighbour_id = mapping[mg]
				#if neighbour_id == -1:
					#continue;
				#var target : StaticBody3D = tile.neighbours[ neighbour_id ]
				#if target.state == TileElement.State.BUILT or target.state == TileElement.State.DESTROYED:
					#var mr : Monorail = monorail_mm.new_mr(mr_count)
					#var t : Transform3D = tile.get_child(0).get_transform()
					#if mg == "mr2":
						#t = t.rotated(Vector3.UP, deg_to_rad(60))
						## This is broken in the new coordinate system... this is good enough TODO - fix!
						#t.origin += Vector3(0.5 * cairo_disabled.RIGHT_POINT__UP, 0.0, 2 * cairo_disabled.RIGHT_POINT__UP)
						##t = tile.get_global_transform() * t
					#elif mg == "mr3":
						#t = t.rotated(Vector3.UP, deg_to_rad(120))
						## As above - ugly & not precise
						#t.origin += Vector3(1.6 * cairo_disabled.RIGHT_POINT__UP, 0.0, 2.0 * cairo_disabled.RIGHT_POINT__UP)
						##t = tile.get_global_transform() * t
					#else:
						#t.origin += Vector3(0.0, 0.0, cairo_disabled.RIGHT_POINT__UP)
					#t = tile.get_global_transform() * t
					#t.origin.y = -0.5 # Hide
					#monorail_mm.multimesh.set_instance_transform(mr_count, t)
					#tile.links_to(target, mr, true)
					#mr_count += 1
	#assert(mr_count <= total_monorails)
	#monorail_mm.multimesh.set_visible_instance_count(mr_count)


#func apply_initial_monorail_and_zoomba():
	#print(monorail_mm.monorail_dict[10], " ", monorail_mm.monorail_dict[10].monorail_id)
	#print(monorail_mm.monorail_dict[11], " ", monorail_mm.monorail_dict[11].monorail_id)
	#for id in Global.LEVEL.MCP:
		#var player = Global.LEVEL.MCP.find( id )
		#var tile : TileElement = tile_dictionary[id] # Get ID of MCP tile
		#tile.player = player
		#var done := false
		#for n in tile.neighbours:
			#if n.state == TileElement.State.DESTROYED: # Find a vaid initial link
				#done = true
				#tile.building.spawn_start_loc = n
				#var zoomba = tile.building.add_zoomba()
				#var mr : Monorail = tile.paths[n]
				#mr.set_constructed(zoomba, true) # Sets as constucted by player
				#break
		#tile.building.update_monorail()
		#if not done:
			#print("Could not connect MCP to starting tile!")
			#assert(false)

func disabled_tiles_to_multimesh():
	var disabled := get_tree().get_nodes_in_group("disabled")
	var disabled_mm := $DisabledTileMultimesh
	disabled_mm.multimesh = MultiMesh.new()
	disabled_mm.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	disabled_mm.multimesh.mesh = cairo_disabled.mesh.duplicate()
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
	var mesh_dup = cairo_enabled.mesh.duplicate()
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
	mesh_dup.surface_get_material(1).set_shader_parameter(&"use_instance_color", true)
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
