extends Node3D
class_name GameGrid

# Owns the 32×32 grid state (grid_data) and the visual cell nodes (cells).
# Present in every game instance (host machine + remote clients).
#
# Three toggle paths, all converging on apply_toggle():
#
#   Path A — Host human:  HumanController.send_toggle_cell()
#                            → Server._handle_toggle_cell()
#                            → GameGrid.apply_toggle()
#
#   Path B — AI:          AIController._on_timer()
#                            → Server._handle_toggle_cell()
#                            → GameGrid.apply_toggle()
#
#   Path C — Remote:      Remote client clicks → rpc_id(1, "toggle_cell")
#                            → GameGrid.toggle_cell() [on server]
#                            → Server._on_remote_toggle_cell()
#                            → _handle_toggle_cell() → apply_toggle()
#
# After modifying grid_data, apply_toggle() calls apply_cell_update(),
# which updates the local visual and broadcasts rpc("set_cell") to
# all connected remote clients.

var cells: Array = []
var grid_data: Array = []

func _ready():
	print("GameGrid._ready()  nm=", Global.network_manager, "  server=", (Global.network_manager.server if Global.network_manager else "no nm"))
	grid_data.resize(32)
	for x in range(32):
		grid_data[x] = []
		grid_data[x].resize(32)
		for z in range(32):
			grid_data[x][z] = []

	cells.resize(32)
	for x in range(32):
		cells[x] = []
		cells[x].resize(32)
		for z in range(32):
			var cell = preload("res://scenes/world/GridCell.tscn").instantiate()
			cell.position = Vector3(x, 0, z)
			cell.cell_x = x
			cell.cell_z = z
			add_child(cell)
			cells[x][z] = cell

func update_cell(x: int, z: int, owners: Array):
	if x < 0 or x >= 32 or z < 0 or z >= 32:
		return
	cells[x][z].set_owners(owners)

func apply_cell_update(x: int, z: int, owners: Array):
	# Update local visual, then broadcast to all remote peers.
	# The server machine already has the right state; this call
	# handles the local repaint while rpc() sends to everyone else.
	print("GameGrid.apply_cell_update(x=", x, ", z=", z, ", owners=", owners, ")  broadcasting rpc set_cell")
	update_cell(x, z, owners)
	rpc("set_cell", x, z, owners)

@rpc("authority", "call_remote", "reliable")
func set_cell(x: int, z: int, owners: Array):
	# Executed on remote clients when the server broadcasts a state change.
	# "authority" ensures only the server (peer 1) can send this.
	print("GameGrid.set_cell() received  x=", x, " z=", z, " owners=", owners, "  id=", multiplayer.get_unique_id())
	update_cell(x, z, owners)

@rpc("any_peer", "call_remote")
func toggle_cell(x: int, z: int):
	# Executed on the server when a remote client sends a toggle request.
	# "any_peer" allows clients to call this; multiplayer.get_remote_sender_id()
	# identifies which client. Forwards to Server for peer_id→player_number
	# translation and validation.
	var caller = multiplayer.get_remote_sender_id()
	var srv = Global.network_manager.server if Global.network_manager else null
	print("GameGrid.toggle_cell() called  caller=", caller, "  server=", srv)
	if srv:
		srv._on_remote_toggle_cell(caller, x, z)

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var space = get_world_3d().direct_space_state
		var camera = get_viewport().get_camera_3d()
		var from = camera.project_ray_origin(event.position)
		var dir = camera.project_ray_normal(event.position)
		var ray = PhysicsRayQueryParameters3D.new()
		ray.from = from
		ray.to = from + dir * 1000.0
		var result = space.intersect_ray(ray)
		if result:
			var collider = result.collider
			var cell = collider.get_parent()
			if cell.has_method("get_cell_pos"):
				var pos = cell.get_cell_pos()
				_on_cell_clicked(pos.x, pos.y)

func _on_cell_clicked(x: int, z: int):
	# On the host machine: find the HumanController (group-managed) and
	# send the click through the direct local path (Path A above).
	# On a remote client: no HumanController exists, so fall through to
	# rpc_id(1, ...) which sends the click to the server (Path C above).
	print("GameGrid._on_cell_clicked(", x, ", ", z, ")  multiplayer_id=", multiplayer.get_unique_id())
	var controllers = get_tree().get_nodes_in_group("human_controllers")
	if controllers.size() > 0:
		print("  -> found human_controllers, sending direct (Path A)")
		controllers[0].send_toggle_cell(x, z)
		return

	print("  -> no human_controllers, sending rpc_id(1, toggle_cell) (Path C)")
	rpc_id(1, "toggle_cell", x, z)

func apply_toggle(player_number: int, x: int, z: int):
	# Authoritative toggle logic — mutates grid_data[x][z].
	# Adds the player's number if absent, removes it if present.
	# Always called on the server side (from any of the three paths above).
	if x < 0 or x >= 32 or z < 0 or z >= 32:
		return
	var arr: Array = grid_data[x][z]
	print("GameGrid.apply_toggle(pnum=", player_number, ", x=", x, ", z=", z, ")  before=", arr)
	if player_number in arr:
		arr.erase(player_number)
	else:
		arr.append(player_number)
	grid_data[x][z] = arr
	print("  after=", arr)
	apply_cell_update(x, z, arr)
