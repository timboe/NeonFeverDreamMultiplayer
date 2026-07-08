extends Node
class_name NetworkManager

# Orchestrator: starts the server and spawns AI controllers.
# On a remote machine, connect_to_server() sets up the ENet client peer
# on the default multiplayer API so commands reach the server via RPC.

var server: Server
var ai_controllers: Array[AIController] = []
var config: GameConfig

func start_server(server_config: GameConfig):
	# Called on the host machine. Creates an authoritative ENet server and
	# spawns an AIController for each AI slot.
	# Local (host human) players don't need a controller node — they send
	# commands directly via Global.send_command_me().
	# Remote clients connect via ENet and send commands as RPCs.
	self.config = server_config
	server = Server.new()
	add_child(server)
	server.start(self.config)

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
		if slot == GameConfig.SlotType.LOCAL:
			# Host human — no controller node, just remember "me"
			Global.my_player_number = player_num
			player_num += 1
		elif slot == GameConfig.SlotType.AI:
			var ai = AIController.new(player_num)
			add_child(ai)
			ai_controllers.append(ai)
			player_num += 1
		elif slot == GameConfig.SlotType.REMOTE:
			player_num += 1

@rpc("authority", "call_remote", "reliable")
func set_my_player_number(pnum: int):
	Global.my_player_number = pnum

func connect_to_server(ip: String, port: int):
	# Called on a remote machine. Sets the default multiplayer API to an
	# ENet client peer so that rpc_id(1, ...) calls on any node reach the
	# server. The server responds with rpc("set_tile_selection", ...) broadcasts.
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
	for ai in ai_controllers:
		ai.queue_free()
	ai_controllers.clear()
	if server:
		server.stop()
		server.queue_free()
		server = null
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
