extends StaticBody3D

class_name TileElement

var id := 0

var state = TileManager.State.RAISED

# Multiplayer synchronised
var selected_by : Array # players who have a raise/lower command queued on the tile
var aoe : Array # players for whome this tile falls under their AoE
var gen_count : int = 0 # number of GEN buildings whose AoE covers this tile

var particles_instance : GPUParticles3D

# Why do we need paths? Use pathfinding instead 
#var paths : Dictionary # dict of all pathable neighbours. Key=neighbour, Value=connecting monorail

var neighbours : Array # Array of all neighbours (including immutible ones)

#var building_manager

var building : Building = null# What is built here

var toggle_zoomba_player : int # player who is raising or lowering me
var working_unit : Unit = null # unit currently toggling this tile
var toggle_tween : Tween 

#var monorail_cap_mm : MultiMesh
#var monorail_cap_id : int
#var monorail_cap_moved := false

var tile_mm : MultiMesh # Referenec to the TileManager's TileMultiMesh
var tile_mm_id : int # This tile's index within the MM

#var claim_strength : int = 0 # del me
#var pulse_count : int = 0 # del me
#var updating_owner_emission := false # del me

# Set to a vec3 if this tile is participating in the pathing. Note: in global coordinates
var pathing_centre = null

var _hovered := false
var pathing_manager

@onready var HEIGHT : float = Global.FLOOR_HEIGHT + Global.TILE_OFFSET

const DEFAULT_COLOUR : Color = Color.WHITE
#const HOVER_COLOUR : Color = Color.YELLOW
const SELECT_COLOUR : Color = Color(1, 1, 1)
const HOVER_REMOVE_COLOUR : Color = Color(160/255.0, 0/255.0, 56/255.0)


#const PULSE_TIME := 0.1 # Time in seconds to pulse for
#const PULSE_DECAY := 0.001 # Amount to reduce pulse by per tile
#const CAPTURE_TIME = 1.5 # Time in seconds to capture per enemy neighbour
const FADE_TIME : float = 5.0 # Time to allow revoke of destroy order
const TOGGLE_COUNTDOWN_TIME : float = 2.0

func set_building(b):
	assert(building == null)
	building = b
	b.location = self

func set_disabled():
	state = TileManager.State.DISABLED
	
func add_to_aoe(player_n : int):
	if player_n not in aoe and state != TileManager.State.DISABLED:
		aoe.append(player_n)
		
func toggle_selected_by(player_n : int):
	if state == TileManager.State.DISABLED:
		return false
	if player_n in selected_by:
		selected_by.erase(player_n)
	elif player_n in aoe:
		selected_by.append(player_n)
		return true
	return false
	
func set_lowered():
	state = TileManager.State.LOWERED
	set_tile_mm_emission(0.0)
	var t = transform
	t.origin.y = -HEIGHT
	transform = t
	set_tile_mm_height(-HEIGHT)
	# TODO - is this still comment true? I don't think so (2026)
	# Note: We don't have access to the paths variable yet
	# as this is called also during the level setup
	for n in neighbours:
		if n.state == TileManager.State.LOWERED:
			pathing_manager.connect_tiles(self, n)
			
# Unlike lowering where all the stuff happens at the end, we kill the pathing as soon as we move
func set_rising():
	state = TileManager.State.RISING
	get_node_or_null("/root/World/TileManager").remove_tile_from_pathing(self)
	
func get_state() -> int:
	return state
	
func set_id(i: int):
	id = i
	
func get_id():
	return id
	
#func links_to(target : StaticBody3D, mr, my_child : bool):
	#assert(neighbours.has(target))
	#paths[target] = mr
	#if my_child:
		#mr.set_connections(self, target)
		#target.links_to(self, mr, false) # Add reciprocal link
	
func add_neighbour(n : StaticBody3D):
	if !neighbours.has(n):
		neighbours.append(n)

func can_be_lowered() -> bool:
	return true
	#for n in paths.keys():
		#if n.state == TileManager.State.LOWERED and n.player != -1 and selected_by[ n.player ]:
			## My destruction was requested by someone who has a tile right nextdoor
			#return true
	#var pathing_manager = $"../../../PathingManager" 
	#for n in paths.keys():
		#if n.state != TileManager.State.LOWERED:
			#continue
		#for p in Global.MAX_PLAYERS:
			#if selected_by[p]:
				## Get player's home base tile
				#var myMCP = $"../../../../TileManager".tile_dictionary[ Global.LEVEL.MCP[p] ]
				#if pathing_manager.are_tiles_connected(Global.MAX_PLAYERS, n, myMCP):
					## My destriction was requested by someone who has a theoretically navagable
					## path from a lowered tile next to me back to their home-base
					#return true 
	#return false
	
func _ready():
	building = null
	# See delayed_ready
	
func delayed_ready():
	if state >= TileManager.State.DISABLED:
		return
	mouse_entered.connect(_on_StaticBody_mouse_entered)
	mouse_exited.connect(_on_StaticBody_mouse_exited)
	input_event.connect(_on_StaticBody_input_event)
	# Only do this here as setup code depends on the orderign of the children
	add_child($"../../../Particles".duplicate())
	#building_manager = $"../../../../BuildingManager"

func update_selection_and_aoe_visual():
	if tile_mm == null:
		return
	#if state >= TileManager.State.FALLING:
		#return

	# INSTANCE_CUSTOM → aluminium band stripes (who has an AoE claim)
	var mask = Color(0, 0, 0, 0)
	for p in aoe:
		if p == 1:   mask.r = 1.0
		elif p == 2: mask.g = 1.0
		elif p == 3: mask.b = 1.0
		elif p == 4: mask.a = 1.0
	set_tile_mm_selecting_mask(mask)

	# COLOR.rgb → grid_edges ALBEDO (local hover)
	# TODO - figure out an alternate way of doing this
	#set_tile_mm_color(HOVER_COLOUR if _hovered else DEFAULT_COLOUR)

	# NOTE: Don't mess with the emission here if a zoomba is "doing work" on this tile
	# Detectable on client and server via the toggle_tween currently running 
	if not (toggle_tween and toggle_tween.is_valid() and toggle_tween.is_running()):
		var is_selected = (Global.my_player_number in selected_by)
		if is_selected:
			set_tile_mm_color(Color.WHITE)
		set_tile_mm_emission(0.4 if is_selected else 0.0)
		
# Called when one of MY neighbors is lowered. Check if I was queued for destruction
#func a_neighbour_just_fell():
	#if state == TileManager.State.SELECTED and can_be_lowered():
		#do_deconstruct_start(FADE_TIME / 5.0)
		
func get_tile_mm_height() -> float:
	return tile_mm.get_instance_transform(tile_mm_id).origin.y

func set_tile_mm_height(value : float):
	var t : Transform3D = tile_mm.get_instance_transform(tile_mm_id)
	t.origin.y = value
	tile_mm.set_instance_transform(tile_mm_id, t)

func set_tile_mm_selecting_mask(mask: Color):
	if tile_mm == null:
		return
	var d = tile_mm.get_instance_custom_data(tile_mm_id)
	d = mask
	tile_mm.set_instance_custom_data(tile_mm_id, d)

func get_tile_mm_color() -> Color:
	var c = tile_mm.get_instance_color(tile_mm_id)
	return Color(c.r, c.g, c.b, 1.0)

func set_tile_mm_color(value : Color):
	var c = tile_mm.get_instance_color(tile_mm_id)
	tile_mm.set_instance_color(tile_mm_id, Color(value.r, value.g, value.b, c.a))

func get_tile_mm_emission() -> float:
	return tile_mm.get_instance_color(tile_mm_id).a

func set_tile_mm_emission(value : float):
	var c = tile_mm.get_instance_color(tile_mm_id)
	c.a = value
	tile_mm.set_instance_color(tile_mm_id, c)

func do_toggle_countdown(z : Zoomba):
	if not multiplayer.is_server():
		return
	assert(toggle_zoomba_player == 0)
	assert(working_unit == null)
	toggle_zoomba_player = z.building.player_owner
	working_unit = z
	get_node_or_null("/root/World/TileManager").rpc("rpc_toggle_animation", id, 0) # MODE 0
	var t = create_tween()
	t.tween_callback(begin_toggle).set_delay(TOGGLE_COUNTDOWN_TIME)

func cancel_toggle_countdown(z : Zoomba):
	if not multiplayer.is_server():
		return
	assert(toggle_zoomba_player == z.building.player_owner)
	toggle_zoomba_player = 0
	working_unit = null
	get_node_or_null("/root/World/TileManager").rpc("rpc_toggle_animation", id, 1) # MODE 1
	
func begin_toggle():
	if not multiplayer.is_server():
		return
	# If tile state changed during countdown (human click, another unit), abort
	# TODO - LLM - needed?
	if state != TileManager.State.RAISED and state != TileManager.State.LOWERED:
		if is_instance_valid(working_unit):
			working_unit.job_finished()
		working_unit = null
		toggle_zoomba_player = 0
		return

	if state == TileManager.State.RAISED:
		state = TileManager.State.FALLING
	elif state == TileManager.State.LOWERED:
		set_rising()
	
	selected_by.erase( toggle_zoomba_player )
	toggle_zoomba_player = 0
	get_node_or_null("/root/World/TileManager").rpc("broadcast_tile_selection", id, selected_by.duplicate())
	
	var thunk_distance := Global.rand.randf_range(0.05, 0.2)
	var thunk_time := thunk_distance * 2
	var fall_time := Global.rand.randf_range(4.5, 5.5)
	var dest = -HEIGHT if state == TileManager.State.FALLING else HEIGHT 

	# Set the animation going everywhere (routed through TileManager for reliable RPC delivery)
	# MODE=2
	get_node_or_null("/root/World/TileManager").rpc("rpc_toggle_animation", id, 2, thunk_distance, thunk_time, fall_time, dest)

	# Finished animation callback only runs on the server
	var t = create_tween()
	t.tween_callback(done_toggle).set_delay(fall_time + thunk_time)
	
# Called locally by TileManager.rpc_toggle_animation
func rpc_toggle_animation(mode : int, thunk_distance : float = 0, thunk_time : float = 0, fall_time : float = 0, dest : float = 0):
	if mode == 0: # Countdown
		set_tile_mm_color(Color.WHITE)
		set_tile_mm_emission(0.4)
		toggle_tween = create_tween()
		toggle_tween.tween_method(set_tile_mm_color, SELECT_COLOUR, HOVER_REMOVE_COLOUR, TOGGLE_COUNTDOWN_TIME)\
			.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)
		toggle_tween.tween_callback(begin_toggle).set_delay(TOGGLE_COUNTDOWN_TIME)
	elif mode == 1: # Cancel
		toggle_tween.kill()
		toggle_tween = create_tween()
		set_tile_mm_emission(0.0)
	elif mode == 2: # Commit
		$Particles.emitting = true
		var t = create_tween()
		# Need to alter collision box and nav mesh
		t.tween_property(self, "position:y", dest * thunk_distance, thunk_time)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_method(set_tile_mm_height, get_tile_mm_height(), dest * thunk_distance, thunk_time)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_method(set_tile_mm_emission, 1.0, 0.0, thunk_time)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
		#
		t.parallel().tween_property(self, "position:y", dest, fall_time)\
			.from(dest * thunk_distance).set_delay(thunk_time)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_method(set_tile_mm_height, dest * thunk_distance, dest, fall_time)\
			.set_delay(thunk_time)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)

func done_toggle():
	if not multiplayer.is_server():
		return
	if state == TileManager.State.FALLING:
		set_lowered() # set lowered gets called at the end
	elif state == TileManager.State.RISING:
		state = TileManager.State.RAISED
	# Notify the unit that its job is complete
	if is_instance_valid(working_unit):
		working_unit.job_finished()
	working_unit = null

func _on_StaticBody_mouse_entered():
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if state == TileManager.State.RAISED or state == TileManager.State.LOWERED:
			Global.send_command_me("toggle_tile", [id])
	_hovered = true
	#print("Tile AoE ", aoe, ". Selected by ", selected_by)
	update_selection_and_aoe_visual()

func _on_StaticBody_mouse_exited():
	_hovered = false
	update_selection_and_aoe_visual()

# From one lowered tile to another	
func get_access_tiles(require_aoe : int = 0) -> Array:
	var array : Array = []
	for n in neighbours:
		if n.building != null:
			continue
		if n.state != TileManager.State.LOWERED:
			continue
		if require_aoe and require_aoe not in n.aoe:
			continue
		array.push_back(n)
	return array

func _on_StaticBody_input_event(_camera, event, _click_position, _click_normal, _shape_idx):
	if not event is InputEventMouseButton or not event.is_pressed() or not event.button_index == MOUSE_BUTTON_LEFT:
		return
	if state == TileManager.State.RAISED or state == TileManager.State.LOWERED:
		Global.send_command_me("toggle_tile", [id])
