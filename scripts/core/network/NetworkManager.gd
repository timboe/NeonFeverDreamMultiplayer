extends Node
class_name NetworkManager

# Orchestrator: starts the server and spawns AI controllers.
# On a remote machine, connect_to_server() sets up the ENet client peer
# on the default multiplayer API so commands reach the server via RPC.

# --- State ---

var server: Server
var ai_controllers: Array[AIController] = []
var config: GameConfig

# --- Signals ---

# Emitted when a client connect attempt resolves: true = connected, false = failed.
signal connect_result(success: bool)

# --- Server (host) ---

func start_server(server_config: GameConfig) -> bool:
	# Called on the host machine. Creates an authoritative ENet server and
	# spawns an AIController for each AI slot.
	# Local (host human) players don't need a controller node -- they send
	# commands directly via Global.send_command_me().
	# Remote clients connect via ENet and send commands as RPCs.
	# Returns false if the server could not bind the port (e.g. another game
	# instance is already holding it) — the caller must abort the host flow.
	self.config = server_config
	server = Server.new()
	add_child(server)
	if not server.start(self.config):
		server.queue_free()
		server = null
		return false

	# Player number = slot index + 1, so each slot's number always matches the
	# "Player N" label in the MainMenu. LOCAL/AI slots claim their number
	# directly; REMOTE slots are reserved and drawn by Server._on_peer_connected
	# in slot order (first connector = lowest-numbered remote slot).
	for i in range(config.slots.size()):
		match config.slots[i]:
			GameConfig.SlotType.LOCAL:
				Global.my_player_number = i + 1
			GameConfig.SlotType.AI:
				var ai := AIController.new(i + 1)
				add_child(ai)
				ai_controllers.append(ai)
			GameConfig.SlotType.REMOTE:
				server.remote_slot_pnums.append(i + 1)
	return true

# --- Client (remote) ---

@rpc("authority", "call_remote", "reliable")
func rpc_set_my_player_number(pnum: int) -> void:
	Global.my_player_number = pnum

func connect_to_server(ip: String, port: int) -> void:
	# Sets the default multiplayer API to an ENet client peer so that
	# rpc_id(1, ...) calls on any node reach the server.
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("Failed to connect: ", err)
		connect_result.emit(false)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connected_to_server.connect(_on_connect_success)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_connect_failed)

func _on_connect_success() -> void:
	connect_result.emit(true)

func _on_connect_failed() -> void:
	connect_result.emit(false)

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
	for sig in [multiplayer.connected_to_server, multiplayer.connection_failed, multiplayer.server_disconnected]:
		for cb in [_on_connected, _on_connect_success, _on_connect_failed]:
			if sig.is_connected(cb):
				sig.disconnect(cb)
