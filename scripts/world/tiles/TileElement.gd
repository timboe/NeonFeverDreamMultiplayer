extends StaticBody3D

class_name TileElement

var id := 0

var state = TileManager.State.RAISED

# Multiplayer synchronised
var selected_by : Array # players who have a raise/lower command queued on the tile
var under_aoe : Array # players for whome this tile falls under their AoE

var particles_instance : GPUParticles3D

var paths : Dictionary # dict of all pathable neighbours. Key=neighbour, Value=connecting monorail
var neighbours : Array # Array of all neighbours (including immutible ones)

var active_tween : Tween
#var building_manager

var building # What is built here

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
const HOVER_COLOUR : Color = Color.YELLOW
#const SELECT_COLOUR : Color = Color(100/255.0, 200/255.0, 150/255.0)
#const HOVER_REMOVE_COLOUR : Color = Color(160/255.0, 0/255.0, 56/255.0)

#const PULSE_TIME := 0.1 # Time in seconds to pulse for
#const PULSE_DECAY := 0.001 # Amount to reduce pulse by per tile
#const CAPTURE_TIME = 1.5 # Time in seconds to capture per enemy neighbour
const FADE_TIME : float = 5.0 # Time to allow revoke of destroy order

# Only have one countdown timer
var tween_active := false

func set_building(b):
	assert(building == null)
	building = b
	b.location = self

func set_disabled():
	state = TileManager.State.DISABLED
	
func set_lowered():
	state = TileManager.State.LOWERED
	set_tile_mm_emission(0.0)
	var t = transform
	t.origin.y = -HEIGHT
	transform = t
	set_tile_mm_height(-HEIGHT)
	# Note: We don't have access to the paths variable yet
	# as this is called also during the level setup
	for n in neighbours:
		if n.state == TileManager.State.LOWERED:
			pathing_manager.connect_tiles(self, n, true)
	
func get_state() -> int:
	return state
	
func set_id(i: int):
	id = i
	
func get_id():
	return id
	
func links_to(target : StaticBody3D, mr, my_child : bool):
	assert(neighbours.has(target))
	paths[target] = mr
	if my_child:
		mr.set_connections(self, target)
		target.links_to(self, mr, false) # Add reciprocal link
	
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
	for _p in Global.MAX_PLAYERS + 1:
		selected_by.push_back(false)
		under_aoe.push_back(false)
	# See delayed_ready
	
func delayed_ready():
	if state >= TileManager.State.DISABLED:
		return
	mouse_entered.connect(_on_StaticBody_mouse_entered)
	mouse_exited.connect(_on_StaticBody_mouse_exited)
	input_event.connect(_on_StaticBody_input_event)
	#building_manager = $"../../../../BuildingManager"

func update_selection_visual():
	if tile_mm == null:
		return
	if state >= TileManager.State.FALLING:
		return
	var selecting := []
	for p in Global.MAX_PLAYERS:
		if selected_by[p]:
			selecting.append(p)

	# INSTANCE_CUSTOM → aluminium band stripes (who has a claim)
	var mask = Color(0, 0, 0, 0)
	for p in selecting:
		if p == 1:   mask.r = 1.0
		elif p == 2: mask.g = 1.0
		elif p == 3: mask.b = 1.0
		elif p == 4: mask.a = 1.0
	set_tile_mm_selecting_mask(mask)

	# COLOR.rgb → grid_edges ALBEDO (local hover)
	set_tile_mm_color(HOVER_COLOUR if _hovered else DEFAULT_COLOUR)

	# COLOR.a → aluminium EMISSION (local-selection glow)
	var is_selected = selected_by[Global.my_player_number]
	set_tile_mm_emission(0.4 if is_selected else 0.0)
		
# Called when one of MY neighbors is lowered. Check if I was queued for destruction
func a_neighbour_just_fell():
	if state == TileManager.State.SELECTED and can_be_lowered():
		do_deconstruct_start(FADE_TIME / 5.0)
		
#func assign_monorail_jobs_on_demolish():
	## Check for monorail construction tasks
	## Call if I was just lowered, and there is an owned tile next door
	## Here the owner of the neighbouring tile(s) sets who the jobs go to
	#for n in paths.keys():
		#if n.state != TileManager.State.LOWERED:
			#continue # No - can only connect to lowered tiles
		#if n.player == -1:
			#continue # No - can't setup jobs from unowned tiles to unowned tiles
		#job_manager.add_job(n.player, job_manager.JobType.CONSTRUCT_MONORAIL, n, self)
			
#func try_and_spread_monorail():
	## Check for monorail construction tasks
	## Call if a piece of monorail was just finished to/from me
	## Here my owner determins who the jobs go to
	#if building != null:
		#return
	#for n in paths.keys():
		#if n.state != TileManager.State.LOWERED:
			#continue # No - can only connect to lowered tiles
		#var mr = paths[n]
		#if mr.state == mr.TileManager.State.INITIAL:
			## Spread 
			#job_manager.add_job(player, job_manager.JobType.CONSTRUCT_MONORAIL, self, n)
			
#func try_and_spread_capture():
	#if building != null:
		#return
	#for n in paths.keys():
		#if n.state != TileManager.State.LOWERED:
			#continue # No - can only connect to lowered tiles
		#var mr = paths[n]
		#if mr.state == mr.TileManager.State.CONSTRUCTED:
			## Attack Check
			#if player != -1 and n.player != -1 and player != n.player:
				#if n.building != null:
					#job_manager.add_job(player, job_manager.JobType.CLAIM_BUILDING, self, n)
				#else:
					#job_manager.add_job(player, job_manager.JobType.CLAIM_TILE, n, null)

#func update_owner_emission():
	#if player == -1:
		#set_tile_mm_emission(0.0)
		#return
	#claim_strength = 1
	#set_tile_mm_color(OWNED_COLOUR[player])
	#for n in paths.keys():
		#if n.player == player:
			#claim_strength += 1
	#var t = create_tween()
	#t.tween_method(set_tile_mm_emission, get_tile_mm_emission(), claim_strength * 0.01, 0.5)
	#t.tween_callback(owner_emission_done).set_delay(0.5)
	#updating_owner_emission = true
	
#func owner_emission_done():
	#updating_owner_emission = false

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

#func raise_cap_call(value : float):
	#var t : Transform3D = monorail_cap_mm.get_instance_transform(monorail_cap_id)
	#t.origin.y = value
	#monorail_cap_mm.set_instance_transform(monorail_cap_id, t)

#func raise_cap(time):
	#if not monorail_cap_moved:
		#var t = create_tween()
		#t.tween_method(raise_cap_call, monorail_cap_mm.get_instance_transform(monorail_cap_id).origin.y, 0.0, time)
		#monorail_cap_moved = true

func do_deconstruct_start(time : float):
	if tween_active:
		return
	var t = create_tween()
	#t.tween_method(set_tile_mm_color, SELECT_COLOUR, HOVER_REMOVE_COLOUR, time)\
		#.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)
	t.tween_callback(do_deconstruct_a).set_delay(time)
	active_tween = t
	tween_active = true
	
func do_deconstruct_a():
	state = TileManager.State.FALLING
	var thunk_distance : float = Global.rand.randf_range(0.05, 0.2)
	var thunk_time := thunk_distance * 2
	var t = create_tween()
	t.tween_property(self, "position:y", -HEIGHT * thunk_distance, thunk_time)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_method(set_tile_mm_height, get_tile_mm_height(), -HEIGHT * thunk_distance, thunk_time)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_method(set_tile_mm_emission, 1.0, 0.0, thunk_time)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(do_deconstruct_b).set_delay(thunk_time)
	
func do_deconstruct_b():
	set_tile_mm_emission(0.0)
	var fall_time : float = Global.rand.randf_range(4.5, 5.5)
	var t = create_tween()
	t.tween_property(self, "position:y", -HEIGHT, fall_time)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_method(set_tile_mm_height, get_tile_mm_height(), -HEIGHT, fall_time)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(done_deconstruct).set_delay(fall_time)
	particles_instance = $"../../../Particles".duplicate()
	self.add_child(particles_instance)
	particles_instance.emitting = true

func done_deconstruct():
	set_lowered()
	for n in paths.keys():
		n.a_neighbour_just_fell()
	#assign_monorail_jobs_on_demolish()
	particles_instance.queue_free()
	
#func pulse_start(pulse_e, pulse_n):
	#pulse_count = pulse_n
	#if not updating_owner_emission:
		#set_tile_mm_emission( get_tile_mm_emission() + pulse_e )
	#var t = create_tween()
	#t.tween_callback(pulse_end.bind(pulse_e, pulse_n, not updating_owner_emission)).set_delay(PULSE_TIME)
		
#func pulse_end(pulse_e, pulse_n, i_pulsed):
	#if i_pulsed:
		#set_tile_mm_emission( get_tile_mm_emission() - pulse_e )
	#pulse_e -= PULSE_DECAY
	#if pulse_e <= 0:
		#return
	#for n in paths.keys():
		#if n.state == TileManager.State.LOWERED and n.pulse_count < pulse_count and n.player == player:
			#n.pulse_start(pulse_e, pulse_n)

func _on_StaticBody_mouse_entered():
	_hovered = true
	update_selection_visual()

func _on_StaticBody_mouse_exited():
	_hovered = false
	update_selection_visual()
	
#func start_capture(by_whome):
	#var time := CAPTURE_TIME * claim_strength
	#if active_tween and active_tween.is_valid():
		#active_tween.kill()
	#var t = create_tween()
	#t.tween_method(set_tile_mm_color, get_tile_mm_color(), OWNED_COLOUR[by_whome.player], time)
	#t.parallel().tween_property(by_whome, "rotation:y", by_whome.rotation.y + (4.0 * PI * time), time)
	#t.tween_callback(set_captured.bind(by_whome)).set_delay(time)
	#active_tween = t
	
#func abandon_capture(by_whome):
	#var time := CAPTURE_TIME
	#if active_tween and active_tween.is_valid():
		#active_tween.kill()
	#var t = create_tween()
	#t.tween_method(set_tile_mm_color, get_tile_mm_color(), OWNED_COLOUR[player], time)
	#active_tween = t
	
#func set_captured(by_whome):
	#player = by_whome.player
	#update_owner_emission()
	#try_and_spread_capture()
	#for n in paths.keys(): # Give the enemy jobs to reclaim
		#n.update_owner_emission()
		#n.try_and_spread_capture()
	#by_whome.job_finished(true)

# From one lowered tile to another	
func get_access_tiles():
	var array : Array = []
	for n in paths.keys():
		if n.building == null:
			assert(n.state == TileManager.State.LOWERED)
			array.push_back(n)
	return array
	
# For a particular player to build a barrier
func get_access_tiles_wall(for_player : int):
	var array : Array = []
	for n in paths.keys():
		if n.building == null and n.player == for_player:
			assert(n.state == TileManager.State.LOWERED)
			array.push_back(n)
	return array

func _on_StaticBody_input_event(_camera, event, _click_position, _click_normal, _shape_idx):
	if not event is InputEventMouseButton or not event.is_pressed() or not event.button_index == MOUSE_BUTTON_LEFT:
		return
	if state != TileManager.State.RAISED:
		return
	Global.send_command_me("toggle_tile", [id])
