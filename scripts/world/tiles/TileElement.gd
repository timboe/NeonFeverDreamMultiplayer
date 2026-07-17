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
var toggle_tween : Tween  # Visual countdown animation — synced to clients via rpc_toggle_animation RPC; read by update_selection_and_aoe_visual (runs on all peers)
var _countdown_tween : Tween  # Server-only — fires begin_toggle after TOGGLE_COUNTDOWN_TIME; never synced, never read on clients

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

var pathing_manager

@onready var HEIGHT : float = Global.FLOOR_HEIGHT + Global.TILE_OFFSET

const SELECT_COLOUR : Color = Color(1, 1, 1)
const HOVER_REMOVE_COLOUR : Color = Color(160/255.0, 0/255.0, 56/255.0)

const FADE_TIME : float = 5.0 # Time to allow revoke of destroy order
const TOGGLE_COUNTDOWN_TIME : float = 2.0

enum EmissionEffect {
	GENERATOR_CATCHMENT, # highest priority
	TILE_SELECTED,
	TILE_HOVER,
	PULSE_ANIMATION,     # lowest priority
}

var _emission_requests : Dictionary = {} # EmissionEffect (int) → {color: Color, strength: float}

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
	_emission_requests.clear()
	_apply_emission()
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

	# Emission priority system — toggle_tween guard is inside _apply_emission
	var is_selected = (Global.my_player_number in selected_by)
	if is_selected:
		request_emission(EmissionEffect.TILE_SELECTED, Color.WHITE, 0.4)
	else:
		release_emission(EmissionEffect.TILE_SELECTED)
		
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

func request_emission(effect : EmissionEffect, color : Color, strength : float) -> void:
	_emission_requests[effect] = {"color": color, "strength": strength}
	_apply_emission()

func release_emission(effect : EmissionEffect) -> void:
	var was_active = not _emission_requests.is_empty() and _get_active_effect() == effect
	_emission_requests.erase(effect)
	if was_active:
		_apply_emission()

func _apply_emission() -> void:
	if toggle_tween and toggle_tween.is_valid() and toggle_tween.is_running():
		return
	var effect = _get_active_effect()
	if effect != -1:
		var req = _emission_requests[effect]
		set_tile_mm_color(req.color)
		set_tile_mm_emission(req.strength)
	else:
		set_tile_mm_emission(0.0)

func _get_active_effect() -> int:
	var best := -1
	for effect in _emission_requests:
		if best == -1 or effect < best:
			best = effect
	return best

func do_toggle_countdown(z : Zoomba):
	if not multiplayer.is_server():
		return
	assert(toggle_zoomba_player == 0)
	assert(working_unit == null)
	toggle_zoomba_player = z.building.player_owner
	working_unit = z
	get_node_or_null("/root/World/TileManager").rpc("rpc_toggle_animation", id, 0) # MODE 0
	_countdown_tween = create_tween()
	_countdown_tween.tween_callback(begin_toggle).set_delay(TOGGLE_COUNTDOWN_TIME)

func cancel_toggle_countdown(z : Zoomba):
	if not multiplayer.is_server():
		return
	if toggle_zoomba_player == 0:
		# begin_toggle already ran — nothing to cancel, done_toggle will handle cleanup
		return
	assert(toggle_zoomba_player == z.building.player_owner)
	toggle_zoomba_player = 0
	working_unit = null
	if _countdown_tween and _countdown_tween.is_valid():
		_countdown_tween.kill()
		_countdown_tween = null
	get_node_or_null("/root/World/TileManager").rpc("rpc_toggle_animation", id, 1) # MODE 1

# Point of no return - raising or lowering if this gets called.
# Even if the zoomba gets called away
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
	elif mode == 1: # Cancel
		toggle_tween.kill()
		toggle_tween = null
		_apply_emission()
	elif mode == 2: # Commit
		$Particles.emitting = true
		toggle_tween = create_tween()
		# Need to alter collision box and nav mesh
		toggle_tween.tween_property(self, "position:y", dest * thunk_distance, thunk_time)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
		toggle_tween.parallel().tween_method(set_tile_mm_height, get_tile_mm_height(), dest * thunk_distance, thunk_time)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
		toggle_tween.parallel().tween_method(set_tile_mm_emission, 1.0, 0.0, thunk_time)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
		#
		toggle_tween.parallel().tween_property(self, "position:y", dest, fall_time)\
			.from(dest * thunk_distance).set_delay(thunk_time)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
		toggle_tween.parallel().tween_method(set_tile_mm_height, dest * thunk_distance, dest, fall_time)\
			.set_delay(thunk_time)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
		toggle_tween.tween_callback(_apply_emission)

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
	var hud = get_tree().get_first_node_in_group("hud") as HUD
	if not hud:
		update_selection_and_aoe_visual()
		return
	if hud.is_placing():
		get_node_or_null("/root/World/BuildingManager").update_blueprint(Global.my_player_number, self, hud.building_being_placed())
		request_emission(EmissionEffect.TILE_HOVER, Color.WHITE, 0.1)
		update_selection_and_aoe_visual()
		return
	if hud.can_toggle_tile(self):
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and hud.should_toggle(self):
			Global.send_command_me("toggle_tile", [id])
		request_emission(EmissionEffect.TILE_HOVER, Color.WHITE, 0.1)
	update_selection_and_aoe_visual()

func _on_StaticBody_mouse_exited():
	var hud = get_tree().get_first_node_in_group("hud") as HUD
	if hud and hud.is_placing():
		var type = hud.building_being_placed()
		var bm = get_node_or_null("/root/World/BuildingManager")
		bm.enabled_blueprints[type].transform.origin.y = BuildingManager.HIDE_DEPTH
		bm.disabled_blueprints[type].transform.origin.y = BuildingManager.HIDE_DEPTH
	release_emission(EmissionEffect.TILE_HOVER)
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
		array.append(n)
	return array

func _on_StaticBody_input_event(_camera, event, _click_position, _click_normal, _shape_idx):
	if not event is InputEventMouseButton or not event.is_pressed() or not event.button_index == MOUSE_BUTTON_LEFT:
		return
	var hud = get_tree().get_first_node_in_group("hud") as HUD
	if not hud:
		return
	if hud.is_placing():
		Global.send_command_me("place_blueprint", [id, hud.building_being_placed()])
		return
	if hud.can_toggle_tile(self):
		hud.begin_drag(self)
		Global.send_command_me("toggle_tile", [id])
