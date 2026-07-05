extends Node
class_name Server

# Authoritative game server. Lives under /root/NetworkManager/Server
# on the host machine only. Remote clients never have this node.
#
# RPC boundary:
#   Remote client ──rpc_id(1, "toggle_cell")──→ Server (via GameGrid relay)
#                                                 ↓
#                              _on_remote_toggle_cell(peer_id, x, z)
#                                                 ↓ peer_to_player[peer_id]
#                              _handle_toggle_cell(player_number, x, z)
#                                                 ↓
#                              GameGrid.apply_toggle(player_number, x, z)
#
# Local/AI clients bypass the RPC layer entirely:
#   HumanController/AIController ──direct──→ _handle_toggle_cell(...)

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

func _on_peer_connected(peer_id: int):
	var pnum = next_player_num
	next_player_num += 1
	peer_to_player[peer_id] = pnum
	player_to_peer[pnum] = peer_id
	print("Server._on_peer_connected  peer_id=", peer_id, "  assigned pnum=", pnum)
	_sync_client_grid(peer_id)

func _sync_client_grid(peer_id: int):
	var grid_node = get_node_or_null("/root/World/GameGrid")
	if not grid_node:
		print("Server._sync_client_grid: GameGrid not found!")
		return
	var data = grid_node.grid_data
	var count = 0
	for x in range(32):
		for z in range(32):
			var owners: Array = data[x][z]
			if not owners.is_empty():
				grid_node.rpc_id(peer_id, "set_cell", x, z, owners)
				count += 1
	print("Server._sync_client_grid: sent ", count, " cells to peer ", peer_id)

func _on_peer_disconnected(peer_id: int):
	var pnum = peer_to_player.get(peer_id)
	if pnum:
		print("Server._on_peer_disconnected  peer_id=", peer_id, "  pnum=", pnum)
		peer_to_player.erase(peer_id)
		player_to_peer.erase(pnum)

func _on_remote_toggle_cell(peer_id: int, x: int, z: int):
	# Called by GameGrid.toggle_cell() when a remote client sends the RPC.
	# Translates ENet peer_id → player_number and delegates to the shared
	# _handle_toggle_cell (same path used by local/AI clients).
	var pnum = peer_to_player.get(peer_id)
	print("Server._on_remote_toggle_cell  peer_id=", peer_id, "  pnum=", pnum, "  x=", x, "  z=", z)
	if pnum == null:
		print("  -> pnum is null, dropping")
		return
	_handle_toggle_cell(pnum, x, z)

func _handle_toggle_cell(player_number: int, x: int, z: int):
	# Shared entry point for ALL toggle requests (remote, local host, AI).
	# Validates bounds and forwards to the authoritative GameGrid node.
	# The grid state lives in GameGrid.grid_data; Server is stateless for it.
	print("Server._handle_toggle_cell  pnum=", player_number, "  x=", x, "  z=", z)
	if x < 0 or x >= 32 or z < 0 or z >= 32:
		print("  -> out of bounds")
		return
	var grid_node = get_node_or_null("/root/World/GameGrid")
	if not grid_node:
		print("  -> GameGrid not found!")
		return
	grid_node.apply_toggle(player_number, x, z)
