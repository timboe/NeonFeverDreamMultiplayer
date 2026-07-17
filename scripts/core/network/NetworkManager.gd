extends Node
class_name NetworkManager

# Orchestrator: starts the server and spawns AI controllers.
# On a remote machine, connect_to_server() sets up the ENet client peer
# on the default multiplayer API so commands reach the server via RPC.

var server: Server
var ai_controllers: Array[AIController] = []
var config: GameConfig

# --- Server (host) ---

func start_server(server_config: GameConfig) -> void:
	# Called on the host machine. Creates an authoritative ENet server and
	# spawns an AIController for each AI slot.
	# Local (host human) players don't need a controller node -- they send
	# commands directly via Global.send_command_me().
	# Remote clients connect via ENet and send commands as RPCs.
	self.config = server_config
	server = Server.new()
	add_child(server)
	server.start(self.config)

	# Assign player numbers: LOCAL and AI slots claim numbers first,
	# then remote peers get numbers starting after them.
	var player_num := 1
	for slot in config.slots:
		match slot:
			GameConfig.SlotType.LOCAL:
				Global.my_player_number = player_num
				player_num += 1
			GameConfig.SlotType.AI:
				var ai := AIController.new(player_num)
				add_child(ai)
				ai_controllers.append(ai)
				player_num += 1
			GameConfig.SlotType.REMOTE:
				player_num += 1
	server.next_player_num = player_num

# --- Client (remote) ---

@rpc("authority", "call_remote", "reliable")
func set_my_player_number(pnum: int) -> void:
	Global.my_player_number = pnum

func connect_to_server(ip: String, port: int) -> void:
	# Sets the default multiplayer API to an ENet client peer so that
	# rpc_id(1, ...) calls on any node reach the server.
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("Failed to connect: ", err)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)

func _on_connected() -> void:
	print("Connected to server")

# --- Teardown ---

func stop() -> void:
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
