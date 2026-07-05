extends Node
class_name NetworkManager

# Orchestrator: starts the server and spawns local (human/AI) clients.
# On a remote machine, connect_to_server() sets up the ENet client peer
# on the default multiplayer API so rpc_id(1, ...) reaches the server.

var server: Server
var local_clients: Array[LocalClient] = []
var config: GameConfig

func start_server(config: GameConfig):
	# Called on the host machine. Creates an authoritative ENet server and
	# spawns a LocalClient subtree for each LOCAL or AI slot.
	# Local clients (HumanController / AIController) call server methods
	# directly via Global.network_manager.server — no network hop.
	# Remote clients connect via ENet and send toggle_cell as an RPC.
	self.config = config
	server = Server.new()
	add_child(server)
	server.start(config)

	# Initialize next_player_num so remote clients get the correct player number,
	# accounting for LOCAL and AI slots that already claimed lower numbers.
	server.next_player_num = 1
	for slot in config.slots:
		if slot == GameConfig.SlotType.REMOTE:
			break
		if slot != GameConfig.SlotType.CLOSED:
			server.next_player_num += 1

	var player_num = 1
	for i in range(config.slots.size()):
		var slot = config.slots[i]
		if slot == GameConfig.SlotType.LOCAL or slot == GameConfig.SlotType.AI:
			var client = LocalClient.new()
			client.player_number = player_num
			client.is_ai = (slot == GameConfig.SlotType.AI)
			add_child(client)
			local_clients.append(client)

			if client.is_ai:
				client.add_child(AIController.new())
			else:
				var human = HumanController.new()
				client.add_child(human)
				human.add_to_group("human_controllers")

			player_num += 1
		elif slot == GameConfig.SlotType.REMOTE:
			player_num += 1

func connect_to_server(ip: String, port: int):
	# Called on a remote machine. Sets the default multiplayer API to an
	# ENet client peer so that rpc_id(1, ...) calls on any node reach the
	# server. The server responds with rpc("set_cell", ...) broadcasts.
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, port)
	if err != OK:
		push_error("Failed to connect: ", err)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)

func _on_connected():
	print("Connected to server")

func stop():
	for client in local_clients:
		client.queue_free()
	local_clients.clear()
	if server:
		server.stop()
		server.queue_free()
		server = null
