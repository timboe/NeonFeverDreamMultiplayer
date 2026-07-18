extends Node
class_name Server

# Authoritative game server. Lives under /root/NetworkManager/Server
# on the host machine only. Remote clients never have this node.
#
# All commands arrive through handle_command():
#   Local (host/AI) -> Global.send_command() -> handle_command()
#   Remote          -> Global._on_remote_command() -> handle_command()
#
# Command handlers use the _cmd_ prefix for automatic dispatch via
# reflection -- see handle_command().

var enet_peer: ENetMultiplayerPeer
var peer_to_player: Dictionary = {}
var player_to_peer: Dictionary = {}
var next_player_num: int = 1

# --- Lifecycle ---

func start(config: GameConfig) -> void:
	enet_peer = ENetMultiplayerPeer.new()
	var err := enet_peer.create_server(config.port, config.player_count)
	if err != OK:
		push_error("Failed to start server: ", err)
		return
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func stop() -> void:
	multiplayer.multiplayer_peer = null
	if enet_peer:
		enet_peer.close()

# --- Command dispatch ---

func handle_command(pnum: int, command: String, args: Array) -> void:
	var method_name := "_cmd_" + command
	if not has_method(method_name):
		push_error("Server: unknown command: ", command)
		return
	var method_list = get_method_list()
	for m in method_list:
		if m.name == method_name:
			var expected_args = m.args.size()
			var provided_args = 1 + args.size()
			if provided_args != expected_args:
				push_error("Server: arg count mismatch for ", command, ": got ", provided_args, " expected ", expected_args)
				return
			break
	callv(method_name, [pnum] + args)

# --- Peer management ---

func _on_peer_connected(peer_id: int) -> void:
	var pnum := next_player_num
	next_player_num += 1
	peer_to_player[peer_id] = pnum
	player_to_peer[pnum] = peer_id
	print("Server._on_peer_connected  peer_id=", peer_id, "  assigned pnum=", pnum)
	Global.network_manager.rpc_id(peer_id, "set_my_player_number", pnum)
	# TODO: sync full tile state to reconnecting mid-game peer
	#   tm.rpc_id(peer_id, "set_tile_selection", id, selected_by) for every tile with selectors

func _on_peer_disconnected(peer_id: int) -> void:
	var pnum = peer_to_player.get(peer_id)
	if pnum != null:
		print("Server._on_peer_disconnected  peer_id=", peer_id, "  pnum=", pnum)
		peer_to_player.erase(peer_id)
		player_to_peer.erase(pnum)

# --- Command handlers ---

func _cmd_place_blueprint(player_number: int, tile_id: int, building_type: int) -> void:
	var tm := get_node_or_null("/root/World/TileManager")
	if not tm:
		push_warning("Server._cmd_place_blueprint: TileManager not found")
		return
	var tile = tm.get_tile_by_id(tile_id)
	if not tile:
		push_warning("Server._cmd_place_blueprint: tile not found: ", tile_id)
		return
	var bm := get_node_or_null("/root/World/BuildingManager")
	if not bm:
		push_warning("Server._cmd_place_blueprint: BuildingManager not found")
		return
	bm.place_blueprint(player_number, tile, building_type)

func _cmd_toggle_tile(player_number: int, tile_id: int) -> void:
	var tm := get_node_or_null("/root/World/TileManager")
	if not tm:
		push_warning("Server._cmd_toggle_tile: TileManager not found")
		return
	tm.apply_toggle(player_number, tile_id)
