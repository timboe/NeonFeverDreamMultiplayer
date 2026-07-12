extends Node
class_name Server

# Authoritative game server. Lives under /root/NetworkManager/Server
# on the host machine only. Remote clients never have this node.
#
# All commands arrive through handle_command():
#   Local (host/AI) → Global.send_command() → handle_command()
#   Remote          → Global._on_remote_command() → handle_command()
#
# Command handlers use the _cmd_ prefix for automatic dispatch via
# reflection — see handle_command().

var enet_peer: ENetMultiplayerPeer
var peer_to_player: Dictionary = {}
var player_to_peer: Dictionary = {}
var next_player_num: int = 1

func start(config: GameConfig):
	enet_peer = ENetMultiplayerPeer.new()
	var err = enet_peer.create_server(config.port, config.player_count)
	if err != OK:
		push_error("Failed to start server: ", err)
		return
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func stop():
	multiplayer.multiplayer_peer = null
	if enet_peer:
		enet_peer.close()

func handle_command(pnum: int, command: String, args: Array):
	var method_name = "_cmd_" + command
	if has_method(method_name):
		callv(method_name, [pnum] + args)
	else:
		push_error("Server: unknown command: ", command)

func _on_peer_connected(peer_id: int):
	var pnum = next_player_num
	next_player_num += 1
	peer_to_player[peer_id] = pnum
	player_to_peer[pnum] = peer_id
	print("Server._on_peer_connected  peer_id=", peer_id, "  assigned pnum=", pnum)
	Global.network_manager.rpc_id(peer_id, "set_my_player_number", pnum)
	# TODO: sync full tile state to reconnecting mid-game peer
	#   tm.rpc_id(peer_id, "set_tile_selection", id, selected_by) for every tile with selectors

func _on_peer_disconnected(peer_id: int):
	var pnum = peer_to_player.get(peer_id)
	if pnum:
		print("Server._on_peer_disconnected  peer_id=", peer_id, "  pnum=", pnum)
		peer_to_player.erase(peer_id)
		player_to_peer.erase(pnum)

func _cmd_toggle_tile(player_number: int, tile_id: int):
	print("Server._cmd_toggle_tile  pnum=", player_number, "  tile_id=", tile_id)
	var tm = get_node_or_null("%TileManager")
	if not tm:
		print("  -> TileManager not found!")
		return
	tm.apply_toggle(player_number, tile_id)
